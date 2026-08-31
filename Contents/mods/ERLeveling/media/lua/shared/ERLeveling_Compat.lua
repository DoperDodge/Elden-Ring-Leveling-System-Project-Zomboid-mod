--[[
    ERLeveling_Compat.lua
    ---------------------
    Runtime capability detection for the Project Zomboid Lua/Java API.

    WHY THIS FILE EXISTS
    --------------------
    PLAN.md 2.4 asks for every [VERIFY] API to be confirmed against the installed
    game source before use. This mod was authored without a game install available,
    so instead of guessing, every uncertain API is probed *at runtime* on the machine
    that actually runs the mod. A missing method degrades to a documented fallback
    and is reported once by ERCompat.report(); it never throws.

    Rules:
      * Nothing in this file may error. Every probe is wrapped.
      * Probe results are cached; probing is cheap but not free.
      * Call sites must branch on ERCompat.has(...) rather than pcall'ing blindly,
        so the fallback path is explicit and reviewable.
]]

ERCompat = ERCompat or {}

ERCompat._globalCache = ERCompat._globalCache or {}
ERCompat._eventCache  = ERCompat._eventCache  or {}
ERCompat._missing     = ERCompat._missing     or {}
ERCompat._reported    = false

local function noteMissing(what)
    if not ERCompat._missing[what] then
        ERCompat._missing[what] = true
    end
end

--[[
    A NOTE THAT SHAPES THIS WHOLE FILE
    ----------------------------------
    Project Zomboid's Lua VM (Kahlua) logs a Java exception to console.txt even
    when a Lua pcall catches it. A caught error is still roughly thirty lines of
    Java and Lua stack trace in the log.

    So "probe by trying it and catching the failure" is only free when it
    succeeds. Every failed probe costs a stack trace, and a failed probe on a
    per-tick path costs one per frame - which is exactly what happened: a
    Class-name lookup used to build a cache key threw on every single probe, was
    caught harmlessly, and buried console.txt from OnPlayerUpdate at frame rate.

    Hence the two rules below:
      1. Never index a Java object to *test* for a member. Only ever call the
         member for real, inside a pcall.
      2. Remember every (class, member) that failed, so a missing member costs one
         logged trace for the session instead of one per call.
]]

-- name -> { [classTag] = true }, the members we have seen fail.
ERCompat._badMembers = ERCompat._badMembers or {}
-- name -> true, so the common case (a member that has never failed anywhere) is
-- a single table lookup with no string work at all.
ERCompat._badNames = ERCompat._badNames or {}

--- A cheap, non-throwing discriminator for an object's class.
-- tostring() on a Java object yields "package.Class@1a2b3c"; the part before the
-- "@" is the class name. Deliberately NOT a Class-name lookup, which is what
-- caused the log flood: Kahlua cannot index the Class object such a lookup
-- returns, so it threw on every probe.
local PLAIN_TYPES = {
    table = true, string = true, number = true,
    boolean = true, ["function"] = true, ["nil"] = true,
}

local function tagOf(obj)
    local t = type(obj)
    -- A member missing on one class says nothing about another. Lumping them
    -- together would let a single object without isLit() convince us that no
    -- campfire is ever lit, so every object gets discriminated by its class.
    if t == "table" then
        -- Lua-side objects: the metatable is the class.
        local mt = getmetatable(obj)
        if mt == nil then return "table" end
        local okMt, id = pcall(tostring, mt)
        return okMt and ("table:" .. tostring(id)) or "table"
    end
    if PLAIN_TYPES[t] then return t end
    local ok, s = pcall(tostring, obj)
    if not ok or type(s) ~= "string" then return "object" end
    local at = string.find(s, "@", 1, true)
    if at then return string.sub(s, 1, at - 1) end
    return s
end

local function isKnownBad(obj, name)
    if not ERCompat._badNames[name] then return false end
    local set = ERCompat._badMembers[name]
    return set ~= nil and set[tagOf(obj)] == true
end

local function markBad(obj, name)
    local tag = tagOf(obj)
    local set = ERCompat._badMembers[name]
    if set == nil then set = {}; ERCompat._badMembers[name] = set end
    set[tag] = true
    ERCompat._badNames[name] = true
    noteMissing(tag .. ":" .. tostring(name))
end

--- "Not known to be missing on this class."
--
-- This is optimistic by design. There is no way to test a Java object for a
-- member without indexing it, and indexing a missing member is precisely the
-- thing that floods the log. So callers assume the member is there, ERCompat.call
-- finds out for real, and the answer here is correct from the second call on.
-- Every call site follows a true answer with a call, so one wasted attempt per
-- class per member is the whole cost.
function ERCompat.has(obj, name)
    if obj == nil or name == nil then return false end
    return not isKnownBad(obj, name)
end

--- Safe METHOD invocation. Returns ok, value.
-- Never propagates an error out of the game API, and never attempts the same
-- missing member twice on the same class.
--
-- METHODS ONLY. This calls obj[name](obj, ...), so passing the name of a plain
-- field calls that field's value - "attempt to call a boolean" - which throws and
-- costs a logged stack trace for nothing. There is no field-reading equivalent
-- here on purpose: indexing a game object for a member it lacks is the thing this
-- whole file exists to avoid.
function ERCompat.call(obj, name, ...)
    if obj == nil or name == nil then return false, nil end
    if isKnownBad(obj, name) then return false, nil end
    local args = { ... }
    local n = select("#", ...)
    local ok, res = pcall(function()
        if     n == 0 then return obj[name](obj)
        elseif n == 1 then return obj[name](obj, args[1])
        elseif n == 2 then return obj[name](obj, args[1], args[2])
        elseif n == 3 then return obj[name](obj, args[1], args[2], args[3])
        elseif n == 4 then return obj[name](obj, args[1], args[2], args[3], args[4])
        elseif n == 5 then return obj[name](obj, args[1], args[2], args[3], args[4], args[5])
        else               return obj[name](obj, args[1], args[2], args[3], args[4], args[5], args[6])
        end
    end)
    if not ok then
        markBad(obj, name)
        return false, nil
    end
    return true, res
end

--- Read a method's return value, or `default` when the method is absent/throws.
function ERCompat.get(obj, name, default)
    local ok, res = ERCompat.call(obj, name)
    if ok and res ~= nil then return res end
    return default
end

--- True when a global function/table of this name exists.
function ERCompat.hasGlobal(name)
    if ERCompat._globalCache[name] ~= nil then return ERCompat._globalCache[name] end
    local ok, val = pcall(function() return _G[name] end)
    local result = ok and val ~= nil
    ERCompat._globalCache[name] = result
    if not result then noteMissing("global " .. tostring(name)) end
    return result
end

--- Call a global function safely. Returns ok, value.
function ERCompat.callGlobal(name, ...)
    if not ERCompat.hasGlobal(name) then return false, nil end
    local fn = _G[name]
    if type(fn) ~= "function" then return false, nil end
    local args = { ... }
    local n = select("#", ...)
    local ok, res = pcall(function()
        if     n == 0 then return fn()
        elseif n == 1 then return fn(args[1])
        elseif n == 2 then return fn(args[1], args[2])
        elseif n == 3 then return fn(args[1], args[2], args[3])
        else               return fn(args[1], args[2], args[3], args[4])
        end
    end)
    if not ok then return false, nil end
    return true, res
end

--- True when Events.<name> exists and can be subscribed to.
function ERCompat.hasEvent(name)
    if ERCompat._eventCache[name] ~= nil then return ERCompat._eventCache[name] end
    local ok, ev = pcall(function() return Events[name] end)
    local result = ok and ev ~= nil and ev.Add ~= nil
    ERCompat._eventCache[name] = result
    if not result then noteMissing("Events." .. tostring(name)) end
    return result
end

--- Subscribe to an event only if it exists. The handler body is pcall-wrapped so
-- a Lua error inside our code cannot propagate into the engine (PLAN.md 1.7).
-- Returns true when the subscription was made.
--
-- NOTE: this stops the error escaping, and ERCompat.throttledError limits OUR
-- printing of it. Neither stops Project Zomboid writing its own stack trace for
-- the underlying exception. The only way to keep the log quiet is not to fail
-- repeatedly in the first place, which is what the (class, member) blacklist
-- above is for.
function ERCompat.onEvent(name, fn)
    if not ERCompat.hasEvent(name) then return false end
    local wrapped = function(a, b, c, d, e)
        local ok, err = pcall(fn, a, b, c, d, e)
        if not ok then ERCompat.throttledError(name, err) end
    end
    local ok = pcall(function() Events[name].Add(wrapped) end)
    return ok
end

-- Error printing is throttled per source so a per-tick failure logs a handful of
-- lines instead of tens of thousands.
ERCompat._errCount = ERCompat._errCount or {}
function ERCompat.throttledError(source, err)
    local key = tostring(source)
    local n = (ERCompat._errCount[key] or 0) + 1
    ERCompat._errCount[key] = n
    if n <= 3 then
        print("[ERLeveling] error in " .. key .. ": " .. tostring(err))
        if n == 3 then
            print("[ERLeveling] further errors from " .. key .. " will be suppressed.")
        end
    end
end

--- pcall a body and report through the throttle. Returns ok, value.
function ERCompat.guard(source, fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then
        ERCompat.throttledError(source, res)
        return false, nil
    end
    return true, res
end

--- getTexture() that never returns a value drawTexture will choke on (PLAN.md 15.5).
function ERCompat.texture(path)
    local ok, tex = pcall(function() return getTexture(path) end)
    if ok and tex ~= nil then return tex end
    noteMissing("texture " .. tostring(path))
    return nil
end

--- Which build are we on? Best-effort; used only for logging and for the
-- distribution-table branch, never for gating a code path that could just probe.
function ERCompat.buildNumber()
    if ERCompat._build then return ERCompat._build end
    local build = 41
    local ok, core = pcall(function() return getCore() end)
    if ok and core then
        local v = ERCompat.get(core, "getVersionNumber", nil)
        if type(v) == "string" then
            local major = string.match(v, "(%d+)%.")
            if major then build = tonumber(major) or build end
            -- Version strings look like "41.78.16" or "42.0.0"; some builds prefix text.
            local alt = string.match(v, "[Bb]uild%s*(%d+)")
            if alt then build = tonumber(alt) or build end
        end
    end
    -- Fall back to a B42-only global if the version string was unhelpful.
    if build < 42 and ERCompat.hasGlobal("getGameFilesystem") then build = 42 end
    ERCompat._build = build
    return build
end

--- Print the capability report once. Called from OnGameStart.
function ERCompat.report()
    if ERCompat._reported then return end
    ERCompat._reported = true
    print("[ERLeveling] build detected: " .. tostring(ERCompat.buildNumber()))
    local any = false
    for what, _ in pairs(ERCompat._missing) do
        if not any then
            print("[ERLeveling] the following APIs were probed and are unavailable; fallbacks are in use:")
            any = true
        end
        print("[ERLeveling]   - " .. tostring(what))
    end
    if not any then
        print("[ERLeveling] all probed APIs present.")
    end
end
