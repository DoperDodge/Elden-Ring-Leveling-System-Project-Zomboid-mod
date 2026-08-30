--[[
    ERLeveling_Formulas.lua
    -----------------------
    Pure maths. No game API calls other than reading sandbox values through
    ERBalance.sv(), so this file is safe to load on client, server and in the
    stand-alone cost-table script under tools/.
]]

ERStats = ERStats or {}
ERLevel = ERLevel or {}

-- ---------------------------------------------------------------------------
-- Soft-cap curve (PLAN.md 3.2)
-- ---------------------------------------------------------------------------
--- Returns 0.0 .. 1.0 "effectiveness" for a raw stat value.
function ERStats.scale(value)
    local v = tonumber(value) or 0
    v = math.max(0, v - 1)
    if v <= 19 then
        return v * 0.030                          -- 0.000 .. 0.570  (steep)
    elseif v <= 39 then
        return 0.570 + (v - 19) * 0.014           --       .. 0.850  (soft cap 1)
    elseif v <= 59 then
        return 0.850 + (v - 39) * 0.005           --       .. 0.950  (soft cap 2)
    else
        -- PLAN.md 3.2 gives this slope as 0.00125, which lands at 0.99875 rather
        -- than 1.0 (the curve runs to v = 98, not v = 99). The slope is derived
        -- here instead so the top of the range is exactly 1.0. See NOTES.md.
        return math.min(1.0, 0.950 + (v - 59) * (0.05 / 39))
    end
end

--- Effectiveness *relative to a fresh character*: 0.0 at the sandbox starting
-- value, 1.0 at 99.
--
-- DEVIATION FROM PLAN.md 3.2, and an important one. The plan applies effects as
-- `base + (max - base) * scale(value)`. With the default starting value of 10,
-- scale(10) is 0.27, so a brand new Level 1 character would begin the game with
-- 27% of every bonus in the mod - a free +30% melee damage and +12% damage
-- negation before spending a single rune. Normalising against the starting
-- value keeps the soft-cap shape while making a fresh sheet mean exactly what
-- it looks like: nothing yet. Recorded in NOTES.md.
function ERStats.progress(value)
    local start = ERBalance.svNum("StartingStat", 1, 99)
    local floorV = ERStats.scale(start)
    local v = ERStats.scale(value)
    if v <= floorV then return 0 end
    local span = 1.0 - floorV
    if span <= 0 then return 0 end
    return (v - floorV) / span
end

--- Realised value of one stat effect.
-- `statValue` is the raw 1..99 stat. Returns base + (max-base)*scale*EffectStrength.
-- Unknown stat/effect pairs return 0 rather than erroring.
function ERStats.effect(statKey, effectKey, statValue)
    local group = ERBalance.EFFECTS[statKey]
    if not group then return 0 end
    local env = group[effectKey]
    if not env then return 0 end
    local strength = ERBalance.svNum("EffectStrength", 0.0, 5.0)
    local base, maxV = env[1], env[2]
    local result = base + (maxV - base) * ERStats.progress(statValue) * strength
    if result ~= result then return base end      -- NaN guard
    return result
end

--- Same, but for effects that express a *reduction* and must stay below 1.0
-- however high EffectStrength is cranked (PLAN.md 14: sandbox extremes).
function ERStats.reduction(statKey, effectKey, statValue, ceiling)
    local v = ERStats.effect(statKey, effectKey, statValue)
    return math.min(ceiling or 0.85, math.max(0, v))
end

-- ---------------------------------------------------------------------------
-- Level cost curve (PLAN.md 3.3)
-- ---------------------------------------------------------------------------
--- Authentic Elden Ring cost for the given character level (RL >= 12 formula).
function ERLevel.authenticCost(currentLevel)
    local n = (tonumber(currentLevel) or 1) + 81
    return math.floor(0.02 * (n ^ 3) + 3.06 * (n ^ 2) + 105.6 * n - 895)
end

--- Runes required to go from `currentLevel` to `currentLevel + 1`.
function ERLevel.cost(currentLevel)
    local n = math.max(1, math.floor(tonumber(currentLevel) or 1))
    local preset = ERBalance.sv("CostPreset")
    if preset == ERBalance.COST_PRESET.AUTHENTIC then
        return ERLevel.authenticCost(n)
    end
    local a    = ERBalance.svNum("CostA", 0.0, 100.0)
    local b    = ERBalance.svNum("CostB", 0.5, 6.0)
    local c    = ERBalance.svNum("CostC", 0.0, 5000.0)
    local base = ERBalance.svNum("CostBase", 0.0, 100000.0)
    local cost = math.floor(a * (n ^ b) + c * n + base)
    if cost ~= cost or cost < 1 then cost = 1 end  -- NaN / underflow guard
    return cost
end

--- Total runes to buy `points` levels starting from `currentLevel`.
function ERLevel.totalCost(currentLevel, points)
    local total = 0
    local lvl = math.max(1, math.floor(tonumber(currentLevel) or 1))
    local n = math.max(0, math.floor(tonumber(points) or 0))
    for i = 0, n - 1 do
        total = total + ERLevel.cost(lvl + i)
    end
    return total
end

--- Runes already sunk into reaching `level` from level 1. Used by respec refunds.
function ERLevel.spentTotal(level)
    return ERLevel.totalCost(1, math.max(0, (tonumber(level) or 1) - 1))
end

--- Character level derived from the eight stats.
-- A fresh character (every stat at StartingStat) reads Level 1.
function ERLevel.fromStats(stats)
    if type(stats) ~= "table" then return 1 end
    local starting = ERBalance.svNum("StartingStat", 1, 99)
    local sum = 0
    for i = 1, #ERBalance.STAT_ORDER do
        sum = sum + (tonumber(stats[ERBalance.STAT_ORDER[i]]) or starting)
    end
    return math.max(1, sum - (starting * #ERBalance.STAT_ORDER) + 1)
end

-- ---------------------------------------------------------------------------
-- Derived read-outs for the UI (PLAN.md 7.2 "DERIVED" block)
-- ---------------------------------------------------------------------------
--- Returns a table of human-facing derived values for a stat set.
-- Purely descriptive; the effect code reads ERStats.effect() directly so the two
-- can never drift apart on the numbers that matter.
function ERStats.derived(stats)
    local s = stats or {}
    local function v(k)
        return tonumber(s[k]) or ERBalance.svNum("StartingStat", 1, 99)
    end
    return {
        damageNegation = ERStats.reduction("vig", "damageNegation", v("vig"), 0.75),
        healthRegen    = ERStats.effect("vig", "regenPerTenMin", v("vig")),
        panicResist    = ERStats.reduction("mnd", "panicReduction", v("mnd"), 0.90),
        staminaDrain   = ERStats.reduction("endr", "staminaDrainCut", v("endr"), 0.85),
        carryWeight    = ERStats.effect("endr", "carryWeight", v("endr"))
                       + ERStats.effect("str", "carryWeight", v("str")),
        meleeDamage    = ERStats.effect("str", "meleeDamage", v("str")),
        swingRecovery  = ERStats.reduction("dex", "recoilCut", v("dex"), 0.70),
        xpBonus        = ERStats.effect("int", "xpMultiplier", v("int")),
        healingPower   = ERStats.effect("fth", "healingPower", v("fth")),
        sicknessResist = ERStats.reduction("fth", "sicknessResist", v("fth"), 0.90),
        runeFind       = ERStats.effect("arc", "runeFind", v("arc")),
        lootLuck       = ERStats.reduction("arc", "lootLuck", v("arc"), 0.60),
    }
end

-- ---------------------------------------------------------------------------
-- Formatting helpers shared by every UI surface
-- ---------------------------------------------------------------------------
--- 4217 -> "4,217". PZ has no locale-aware number formatter we can rely on.
function ERStats.comma(n)
    local num = math.floor(tonumber(n) or 0)
    local sign = ""
    if num < 0 then sign = "-"; num = -num end
    local s = tostring(num)
    local out = ""
    while #s > 3 do
        out = "," .. string.sub(s, -3) .. out
        s = string.sub(s, 1, #s - 3)
    end
    return sign .. s .. out
end

--- 0.084 -> "8.4%"
function ERStats.pct(f, decimals)
    local d = decimals or 1
    return string.format("%." .. d .. "f%%", (tonumber(f) or 0) * 100)
end

--- 0.084 -> "+8.4%" / -0.19 -> "-19.0%"
function ERStats.signedPct(f, decimals)
    local v = tonumber(f) or 0
    local s = ERStats.pct(math.abs(v), decimals)
    if v < 0 then return "-" .. s end
    return "+" .. s
end
