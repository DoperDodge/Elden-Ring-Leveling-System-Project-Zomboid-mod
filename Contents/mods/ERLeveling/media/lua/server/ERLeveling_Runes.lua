--[[
    ERLeveling_Runes.lua
    --------------------
    Kill detection and rune crediting (PLAN.md 4.1). Server / single player only;
    this file is never loaded on a multiplayer client, so a client can not credit
    itself.

    Attribution rule (PLAN.md 4.1 and pitfall 15.10): a zombie that dies to fire,
    another zombie, or the world awards nothing. We only pay out when we can name
    a player who hit it.
]]

ERRunes = ERRunes or {}

-- zombieId -> { key = <player key>, at = <ms>, ranged = bool, crit = bool }
ERRunes._lastHit = ERRunes._lastHit or {}
ERRunes._lastHitCount = 0
-- Rune balance mirror, so OnPlayerDeath has a number even if modData is already
-- torn down (PLAN.md 15.3).
ERRunes.snapshot = ERRunes.snapshot or {}

local HIT_MEMORY_MS = 8000

local function zombieId(zombie)
    local id = ERCompat.get(zombie, "getOnlineID", nil)
    if id == nil then id = ERCompat.get(zombie, "getID", nil) end
    return id
end

local function purgeHits(now)
    if ERRunes._lastHitCount < 64 then return end
    local kept = {}
    local n = 0
    for id, rec in pairs(ERRunes._lastHit) do
        if now - (rec.at or 0) < HIT_MEMORY_MS then
            kept[id] = rec
            n = n + 1
        end
    end
    ERRunes._lastHit = kept
    ERRunes._lastHitCount = n
end

local function isPlayerChar(char)
    if char == nil then return false end
    local ok, yes = pcall(function() return instanceof(char, "IsoPlayer") end)
    if ok and yes then return true end
    -- Fall back to a duck-type check if instanceof is unavailable for this object.
    return ERCompat.has(char, "getPlayerNum") and ERCompat.has(char, "getXp")
end

--- Was this a critical / headshot style hit? Both signals are probed; if neither
-- exists on this build there is simply no crit bonus, and ERCompat.report() says so.
local function detectCrit(zombie, bodyPartType)
    if ERCompat.has(zombie, "isHitFromBehind") then
        local ok, behind = ERCompat.call(zombie, "isHitFromBehind")
        if ok and behind == true then return true end
    end
    if bodyPartType ~= nil and ERCompat.hasGlobal("BodyPartType") then
        local ok, head = pcall(function() return BodyPartType.Head end)
        if ok and head ~= nil and bodyPartType == head then return true end
    end
    return false
end

local function detectRanged(weapon)
    if weapon == nil then return false end
    local ok, ranged = ERCompat.call(weapon, "isRanged")
    return ok and ranged == true
end

--- Record who hit what, so OnZombieDead has a fallback attribution source.
local function rememberHit(zombie, attacker, bodyPartType, weapon)
    if zombie == nil or not isPlayerChar(attacker) then return end
    local id = zombieId(zombie)
    if id == nil then return end
    local now = ERUtil.nowMs()
    purgeHits(now)
    if ERRunes._lastHit[id] == nil then
        ERRunes._lastHitCount = ERRunes._lastHitCount + 1
    end
    ERRunes._lastHit[id] = {
        key    = ERData.keyFor(attacker),
        at     = now,
        ranged = detectRanged(weapon),
        crit   = detectCrit(zombie, bodyPartType),
    }
end

--- Resolve the killer. Returns player, hitRecord (record may be nil).
local function resolveKiller(zombie)
    local id = zombieId(zombie)
    local rec = id ~= nil and ERRunes._lastHit[id] or nil

    local ok, attacker = ERCompat.call(zombie, "getAttackedBy")
    if ok and isPlayerChar(attacker) then
        return attacker, rec
    end
    -- getAttackedBy gave us nothing usable; use our own record if it is fresh.
    if rec and (ERUtil.nowMs() - (rec.at or 0)) < HIT_MEMORY_MS then
        local p = ERData.resolve(rec.key)
        if p ~= nil then return p, rec end
    end
    return nil, nil
end

--- Base rune value for a zombie, before multipliers.
local function baseValue(zombie)
    if ERCompat.get(zombie, "isSkeleton", false) == true then
        return ERBalance.RUNES.corpse
    end
    if ERCompat.get(zombie, "isCrawling", false) == true then
        return ERBalance.RUNES.crawler
    end
    -- Sprinters: probed two ways, because the accessor differs between builds.
    if ERCompat.get(zombie, "isSprinter", false) == true then
        return ERBalance.RUNES.sprinter
    end
    local speed = ERCompat.get(zombie, "getSpeedType", nil)
    if type(speed) == "number" and speed <= 1 then
        return ERBalance.RUNES.sprinter
    end
    return ERBalance.RUNES.base
end

--- How many zombies are near the killer, for the horde bonus. Returns nil when
-- the build gives us no cheap way to know, in which case no bonus is applied.
local function nearbyZombies(player)
    local ok, stats = pcall(function() return player:getStats() end)
    if ok and stats ~= nil and ERCompat.has(stats, "getNumChasingZombies") then
        local ok2, n = ERCompat.call(stats, "getNumChasingZombies")
        if ok2 and type(n) == "number" then return n end
    end
    return nil
end

--- Full rune value for one kill.
function ERRunes.valueFor(player, zombie, rec)
    local value = baseValue(zombie)
    if value <= 0 then return 0 end

    if rec and rec.crit   then value = value * ERBalance.RUNES.critMult end
    if rec and rec.ranged then value = value * ERBalance.RUNES.firearmMult end

    -- Desperation bonus: killing while hurt.
    local ok, bd = pcall(function() return player:getBodyDamage() end)
    if ok and bd ~= nil then
        local hp = ERCompat.get(bd, "getOverallBodyHealth", nil)
        if type(hp) == "number" and (hp / 100.0) < ERBalance.RUNES.injuredThreshold then
            value = value * ERBalance.RUNES.injuredMult
        end
    end

    local near = nearbyZombies(player)
    if near ~= nil and near >= ERBalance.RUNES.hordeCount then
        value = value * ERBalance.RUNES.hordeMult
    end

    -- Arcane: rune find.
    local arc = ERData.stat(player, "arc")
    value = value * (1.0 + ERStats.effect("arc", "runeFind", arc))

    -- Global sandbox dial.
    value = value * ERBalance.svNum("RuneMultiplier", 0.0, 100.0)

    local out = math.floor(value + 0.5)
    if out ~= out or out < 0 then return 0 end
    return out
end

--- Credit runes and tell the owning client. The only place heldRunes goes up.
function ERRunes.credit(player, amount, source)
    if player == nil then return 0 end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return 0 end

    local d = ERData.get(player)
    d.heldRunes   = math.floor(tonumber(d.heldRunes) or 0) + amount
    d.totalEarned = math.floor(tonumber(d.totalEarned) or 0) + amount
    ERRunes.snapshot[ERData.keyFor(player)] = d.heldRunes

    ERData.transmit(player)
    ERNet.reply(player, "runeGain", {
        amount = amount,
        total  = d.heldRunes,
        source = source or "kill",
    })
    return amount
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
ERCompat.onEvent("OnWeaponHitCharacter", function(wielder, victim, weapon, damage)
    rememberHit(victim, wielder, nil, weapon)
end)

ERCompat.onEvent("OnHitZombie", function(zombie, character, bodyPartType, handWeapon)
    rememberHit(zombie, character, bodyPartType, handWeapon)
end)

ERCompat.onEvent("OnZombieDead", function(zombie)
    if zombie == nil then return end
    local player, rec = resolveKiller(zombie)
    if player == nil then return end          -- fire, another zombie, the world: no runes

    local amount = ERRunes.valueFor(player, zombie, rec)
    if amount <= 0 then return end
    ERRunes.credit(player, amount, "kill")

    local id = zombieId(zombie)
    if id ~= nil and ERRunes._lastHit[id] ~= nil then
        ERRunes._lastHit[id] = nil
        ERRunes._lastHitCount = math.max(0, ERRunes._lastHitCount - 1)
    end
end)

-- Keep the death-time snapshot warm even for players who have not killed anything
-- recently (PLAN.md 15.3).
ERCompat.onEvent("EveryOneMinute", function()
    ERData.forEachPlayer(function(p)
        ERRunes.snapshot[ERData.keyFor(p)] = ERData.runes(p)
    end)
end)
