--[[
    ERLeveling_Effects.lua
    ----------------------
    Turns the eight attributes into real Project Zomboid effects (PLAN.md 3.1).

    Performance contract (PLAN.md 15.1): OnPlayerUpdate fires constantly, so the
    only work it does is a float comparison plus, at most, one endurance write.
    Everything derived is cached and recomputed only when a stat actually changes.

    Anti-cheat contract (PLAN.md 9): nothing in this file changes a perk *level*.
    Perk XP *boosts* (setPerkBoost) are what the vanilla trait system uses and are
    applied here; perk levels are granted only by the server, in
    ERLeveling_ServerCommands.lua.

    Zombie damage is applied here rather than server-side because Project Zomboid
    clients simulate their own melee; the guard below keeps a dedicated server
    from double-applying it.
]]

ERFx = ERFx or {}
ERFx._cache = ERFx._cache or {}      -- playerNum -> { hash, derived, stats }
ERFx._endurance = ERFx._endurance or {}
ERFx._weaponCond = ERFx._weaponCond or {}
ERFx._inXp = false
ERFx._weightBase = ERFx._weightBase or {}

--- True on a machine that owns melee simulation for a local player.
local function simulatesCombat()
    if isServer() and not isClient() then return false end
    return true
end

local function statHash(stats)
    local h = 0
    for i = 1, #ERBalance.STAT_ORDER do
        h = h * 101 + (tonumber(stats[ERBalance.STAT_ORDER[i]]) or 0)
    end
    return h
end

--- Cached derived values for a player. Recomputed only on a stat change.
function ERFx.derived(player)
    if player == nil then return nil end
    local n = ERCompat.get(player, "getPlayerNum", 0)
    local d = ERData.get(player)
    local hash = statHash(d.stats)
    local c = ERFx._cache[n]
    if c == nil or c.hash ~= hash then
        c = { hash = hash, stats = ERUtil.copyStats(d.stats), derived = ERStats.derived(d.stats) }
        ERFx._cache[n] = c
        ERFx.onStatsChanged(player, c)
    end
    return c.derived, c.stats
end

--- Everything that only needs doing when the numbers move.
function ERFx.onStatsChanged(player, c)
    ERFx.applyPerkBoosts(player, c.stats)
    ERFx.applyCarryWeight(player, c.derived)
end

-- ---------------------------------------------------------------------------
-- Perk XP boosts (Mind: Aiming, Dexterity: Reloading, Intelligence: everything)
-- ---------------------------------------------------------------------------
local function setBoost(xp, perkName, level)
    if xp == nil then return end
    if not ERCompat.hasGlobal("Perks") then return end
    local ok, perk = pcall(function() return Perks[perkName] end)
    if not ok or perk == nil then return end
    ERCompat.call(xp, "setPerkBoost", perk, ERUtil.clamp(math.floor(level), 0, 3))
end

ERFx.BOOSTABLE_PERKS = {
    "Woodwork", "Cooking", "Farming", "Doctor", "Electricity", "MetalWelding",
    "Mechanics", "Tailoring", "Fishing", "Trapping", "PlantScavenging",
    "Blunt", "Axe", "SmallBlunt", "SmallBlade", "LongBlade", "Spear", "Maintenance",
}

function ERFx.applyPerkBoosts(player, stats)
    local ok, xp = pcall(function() return player:getXp() end)
    if not ok or xp == nil then return end
    if not ERCompat.has(xp, "setPerkBoost") then return end

    setBoost(xp, "Aiming",    ERStats.effect("mnd", "aimBoost",    stats.mnd))
    setBoost(xp, "Reloading", ERStats.effect("dex", "reloadBoost", stats.dex))

    -- Intelligence gives a broad XP boost. This is the *fallback* path for the
    -- Events.AddXP multiplier below; when that event exists the boost is kept at
    -- half strength so the two do not compound into something absurd.
    local intBoost = ERStats.effect("int", "perkBoost", stats.int)
    if ERCompat.hasEvent("AddXP") then intBoost = intBoost * 0.5 end
    for i = 1, #ERFx.BOOSTABLE_PERKS do
        setBoost(xp, ERFx.BOOSTABLE_PERKS[i], intBoost)
    end
end

-- ---------------------------------------------------------------------------
-- Carry weight (PLAN.md 6)
-- ---------------------------------------------------------------------------
-- Tier 1: setMaxWeightBase, if the build has it. Tier 3 (server-granted Strength
-- levels) lives in ERLeveling_ServerCommands.lua and only runs when tier 1 is
-- unavailable, so the two can never stack.
function ERFx.applyCarryWeight(player, derived)
    if not ERCompat.has(player, "setMaxWeightBase") then return end
    local n = ERCompat.get(player, "getPlayerNum", 0)
    if ERFx._weightBase[n] == nil then
        local base = ERCompat.get(player, "getMaxWeightBase", nil)
        if type(base) ~= "number" then base = 8 end
        ERFx._weightBase[n] = base
    end
    local target = ERFx._weightBase[n] + (derived.carryWeight or 0)
    ERCompat.call(player, "setMaxWeightBase", target)
end

-- ---------------------------------------------------------------------------
-- Vigor: damage negation + regeneration
-- ---------------------------------------------------------------------------
--- Spread `amount` of healing over the player's damaged body parts, worst first.
function ERFx.healSpread(player, amount)
    if amount == nil or amount <= 0 then return end
    local ok, bd = pcall(function() return player:getBodyDamage() end)
    if not ok or bd == nil then return end
    if not ERCompat.hasGlobal("BodyPartType") then return end

    local ok2, count = pcall(function() return BodyPartType.ToIndex(BodyPartType.MAX) end)
    if not ok2 or type(count) ~= "number" then count = 17 end

    local remaining = amount
    for i = 0, count - 1 do
        if remaining <= 0 then break end
        local okP, part = pcall(function() return bd:getBodyPart(BodyPartType.FromIndex(i)) end)
        if okP and part ~= nil then
            local hp = ERCompat.get(part, "getHealth", nil)
            if type(hp) == "number" and hp < 100 then
                local give = math.min(remaining, 100 - hp)
                if ERCompat.call(part, "setHealth", hp + give) then
                    remaining = remaining - give
                end
            end
        end
    end
end

-- OnPlayerGetDamage cannot be relied on to mutate the incoming value, so Vigor is
-- implemented as an immediate post-hoc restore of the negated fraction. The player
-- still takes the hit, they just recover part of it instantly.
ERCompat.onEvent("OnPlayerGetDamage", function(player, damageType, damageAmount)
    if player == nil or not simulatesCombat() then return end
    local derived = ERFx.derived(player)
    if derived == nil then return end
    local negate = derived.damageNegation or 0
    if negate <= 0 then return end
    local amt = tonumber(damageAmount) or 0
    if amt <= 0 then return end
    ERFx.healSpread(player, amt * negate)
end)

ERCompat.onEvent("EveryTenMinutes", function()
    ERData.forEachPlayer(function(player)
        local derived = ERFx.derived(player)
        if derived == nil then return end
        if (derived.healthRegen or 0) > 0 then
            ERFx.healSpread(player, derived.healthRegen)
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- Mind: panic / stress / unhappiness
-- ---------------------------------------------------------------------------
local function scaleStat(stats, getter, setter, keep)
    if not ERCompat.has(stats, getter) or not ERCompat.has(stats, setter) then return end
    local ok, v = ERCompat.call(stats, getter)
    if not ok or type(v) ~= "number" or v <= 0 then return end
    ERCompat.call(stats, setter, v * keep)
end

ERCompat.onEvent("EveryOneMinute", function()
    ERData.forEachPlayer(function(player)
        local derived, raw = ERFx.derived(player)
        if derived == nil then return end

        -- Mind: panic, stress, unhappiness. Endurance: fatigue.
        local ok, stats = pcall(function() return player:getStats() end)
        if ok and stats ~= nil then
            scaleStat(stats, "getPanic",  "setPanic",  1.0 - (derived.panicResist or 0))
            scaleStat(stats, "getStress", "setStress",
                      1.0 - ERStats.reduction("mnd", "stressReduction", raw.mnd, 0.85))
            scaleStat(stats, "getUnhappynessLevel", "setUnhappynessLevel",
                      1.0 - ERStats.reduction("mnd", "unhappyReduction", raw.mnd, 0.80))
            scaleStat(stats, "getFatigue", "setFatigue",
                      1.0 - ERStats.reduction("endr", "fatigueCut", raw.endr, 0.60))
        end

        -- Faith: illness and food poisoning only. Zombification is never touched,
        -- here or anywhere else in this mod.
        local okB, bd = pcall(function() return player:getBodyDamage() end)
        if okB and bd ~= nil then
            local keep = 1.0 - (derived.sicknessResist or 0)
            scaleStat(bd, "getFoodSicknessLevel", "setFoodSicknessLevel", keep)
            scaleStat(bd, "getPoisonLevel",       "setPoisonLevel",       keep)
        end

        -- Faith: give bandaged wounds a nudge.
        local heal = derived.healingPower or 0
        if heal > 0 then ERFx.boostBandages(player, heal) end
    end)
end)

--- Faith makes dressings work harder: bandaged parts recover a little extra each
-- minute, proportional to healingPower.
function ERFx.boostBandages(player, healingPower)
    local ok, bd = pcall(function() return player:getBodyDamage() end)
    if not ok or bd == nil then return end
    if not ERCompat.hasGlobal("BodyPartType") then return end
    local ok2, count = pcall(function() return BodyPartType.ToIndex(BodyPartType.MAX) end)
    if not ok2 or type(count) ~= "number" then count = 17 end
    for i = 0, count - 1 do
        local okP, part = pcall(function() return bd:getBodyPart(BodyPartType.FromIndex(i)) end)
        if okP and part ~= nil then
            if ERCompat.get(part, "bandaged", nil) == true
               or ERCompat.get(part, "isBandaged", false) == true then
                local hp = ERCompat.get(part, "getHealth", nil)
                if type(hp) == "number" and hp < 100 then
                    ERCompat.call(part, "setHealth", math.min(100, hp + healingPower * 0.25))
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Endurance: stamina drain and recovery
-- ---------------------------------------------------------------------------
-- Endurance in PZ is 0..1 where 1 is fully rested. We watch for a drop between
-- ticks and hand back a fraction of it.
ERCompat.onEvent("OnPlayerUpdate", function(player)
    if player == nil then return end
    local n = ERCompat.get(player, "getPlayerNum", 0)
    local ok, stats = pcall(function() return player:getStats() end)
    if not ok or stats == nil then return end
    local okE, endurance = ERCompat.call(stats, "getEndurance")
    if not okE or type(endurance) ~= "number" then return end

    local last = ERFx._endurance[n]
    ERFx._endurance[n] = endurance
    if last == nil then return end

    local derived = ERFx.derived(player)
    if derived == nil then return end

    if endurance < last then
        local cut = derived.staminaDrain or 0
        if cut > 0 then
            local refund = (last - endurance) * cut
            ERCompat.call(stats, "setEndurance", math.min(1.0, endurance + refund))
            ERFx._endurance[n] = math.min(1.0, endurance + refund)
        end
    elseif endurance > last then
        local bonus = ERStats.effect("endr", "staminaRegen", ERData.stat(player, "endr"))
        if bonus > 0 then
            local extra = (endurance - last) * bonus
            ERCompat.call(stats, "setEndurance", math.min(1.0, endurance + extra))
            ERFx._endurance[n] = math.min(1.0, endurance + extra)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Strength: melee damage. Dexterity: swing recovery and weapon wear.
-- ---------------------------------------------------------------------------
ERCompat.onEvent("OnWeaponHitCharacter", function(wielder, victim, weapon, damage)
    if wielder == nil or victim == nil or not simulatesCombat() then return end
    local okP, isPlayer = pcall(function() return instanceof(wielder, "IsoPlayer") end)
    if not okP or not isPlayer then return end
    local okZ, isZombie = pcall(function() return instanceof(victim, "IsoZombie") end)
    if not okZ or not isZombie then return end

    local derived, raw = ERFx.derived(wielder)
    if derived == nil then return end

    -- Strength: extra damage applied directly to the victim's health, because the
    -- `damage` argument is not writable (PLAN.md 3.1 "Direct health subtraction is
    -- the reliable path").
    local bonusMult = derived.meleeDamage or 0
    local isRanged = ERCompat.get(weapon, "isRanged", false) == true
    if bonusMult > 0 and not isRanged then
        local dealt = tonumber(damage) or 0
        if dealt > 0 then
            local hp = ERCompat.get(victim, "getHealth", nil)
            if type(hp) == "number" then
                ERCompat.call(victim, "setHealth", hp - (dealt * bonusMult))
            end
        end
    end

    -- Dexterity: shorten the recovery window after a swing.
    local cut = derived.swingRecovery or 0
    if cut > 0 then
        local delay = ERCompat.get(wielder, "getRecoilDelay", nil)
        if type(delay) == "number" and delay > 0 then
            ERCompat.call(wielder, "setRecoilDelay", delay * (1.0 - cut))
        end
    end

    -- Dexterity: refund weapon condition loss.
    ERFx.refundCondition(weapon, ERStats.reduction("dex", "conditionCut", raw.dex, 0.80))
end)

--- Give back a condition point when the weapon just lost one and the roll passes.
-- Tracked per weapon ID so we only ever refund an actual loss.
function ERFx.refundCondition(weapon, chance)
    if weapon == nil or chance <= 0 then return end
    local id = ERCompat.get(weapon, "getID", nil)
    if id == nil then return end
    local cond = ERCompat.get(weapon, "getCondition", nil)
    if type(cond) ~= "number" then return end
    local last = ERFx._weaponCond[id]
    ERFx._weaponCond[id] = cond
    if last == nil or cond >= last then return end
    if ZombRand(1000) < math.floor(chance * 1000) then
        local maxCond = ERCompat.get(weapon, "getConditionMax", 100)
        ERCompat.call(weapon, "setCondition", math.min(maxCond, cond + (last - cond)))
        ERFx._weaponCond[id] = math.min(maxCond, cond + (last - cond))
    end
end

-- ---------------------------------------------------------------------------
-- Intelligence: skill XP multiplier
-- ---------------------------------------------------------------------------
-- Events.AddXP fires whenever XP is awarded. Adding more XP from inside the
-- handler re-enters it, so ERFx._inXp breaks the loop.
ERCompat.onEvent("AddXP", function(character, perk, amount)
    if ERFx._inXp then return end
    if character == nil or perk == nil then return end
    local okP, isPlayer = pcall(function() return instanceof(character, "IsoPlayer") end)
    if not okP or not isPlayer then return end

    local derived = ERFx.derived(character)
    if derived == nil then return end
    local mult = derived.xpBonus or 0
    if mult <= 0 then return end

    local amt = tonumber(amount) or 0
    if amt <= 0 then return end

    ERFx._inXp = true
    local ok, xp = pcall(function() return character:getXp() end)
    if ok and xp ~= nil then
        ERCompat.call(xp, "AddXP", perk, amt * mult)
    end
    ERFx._inXp = false
end)

-- ---------------------------------------------------------------------------
-- Housekeeping
-- ---------------------------------------------------------------------------
ERCompat.onEvent("OnPlayerDeath", function(player)
    if player == nil then return end
    local n = ERCompat.get(player, "getPlayerNum", 0)
    ERFx._cache[n] = nil
    ERFx._endurance[n] = nil
    ERFx._weightBase[n] = nil
end)

-- The weapon-condition table would otherwise grow for the life of the session.
ERCompat.onEvent("EveryHours", function()
    ERFx._weaponCond = {}
end)
