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

ERCompat._methodCache = ERCompat._methodCache or {}
ERCompat._globalCache = ERCompat._globalCache or {}
ERCompat._eventCache  = ERCompat._eventCache  or {}
ERCompat._missing     = ERCompat._missing     or {}
ERCompat._reported    = false

local function noteMissing(what)
    if not ERCompat._missing[what] then
        ERCompat._missing[what] = true
    end
end

--- True when `obj` exposes a callable member named `name`.
-- Works for both Lua tables and Java-exposed objects (which answer to indexing
-- but may throw on unknown members, hence the pcall).
function ERCompat.has(obj, name)
    if obj == nil or name == nil then return false end
    local cacheKey = nil
    local ok, tn = pcall(function() return type(obj) end)
    if ok and tn == "userdata" then
        -- Java object: cache per class where we can get one, else per-name only.
        local ok2, cls = pcall(function() return obj:getClass():getName() end)
        cacheKey = (ok2 and cls or "userdata") .. "#" .. name
    end
    if cacheKey and ERCompat._methodCache[cacheKey] ~= nil then
        return ERCompat._methodCache[cacheKey]
    end
    local okIndex, member = pcall(function() return obj[name] end)
    local result = okIndex and member ~= nil
    if cacheKey then ERCompat._methodCache[cacheKey] = result end
    if not result then noteMissing(tostring(cacheKey or name)) end
    return result
end

--- Safe method invocation. Returns ok, value.
-- Never propagates an error out of the game API.
function ERCompat.call(obj, name, ...)
    if not ERCompat.has(obj, name) then return false, nil end
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
        noteMissing(tostring(name) .. "()")
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

--- Subscribe to an event only if it exists. The handler body is pcall-wrapped so a
-- Lua error inside our code can never spam the console every tick (PLAN.md 1.7).
-- Returns true when the subscription was made.
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
