--[[
    ERLeveling_Balance.lua
    ----------------------
    EVERY tuning number in this mod lives here (PLAN.md 3.2: "All tuning numbers
    live in one file. No magic numbers scattered through the codebase.").

    Sandbox variables are read lazily through ERBalance.sv() because SandboxVars
    does not exist at file scope (PLAN.md 15.7).
]]

ERBalance = ERBalance or {}

ERBalance.MOD_ID      = "ERLeveling"
ERBalance.MOD_NAME    = "Tarnished"
ERBalance.DATA_VERSION = 1                 -- modData schema version, see ERData migrations
ERBalance.NET_MODULE  = "ERLeveling"       -- sendClientCommand/sendServerCommand module name
ERBalance.GLOBAL_KEY  = "ERLeveling_Global"

-- ---------------------------------------------------------------------------
-- Stat identity
-- ---------------------------------------------------------------------------
-- NOTE (deviation from PLAN.md 8): the plan's data model uses `end` as the
-- Endurance key. `end` is a Lua keyword and cannot be a bare table key, so
-- Endurance is stored as `endr`. Recorded in NOTES.md.
ERBalance.STAT_ORDER = { "vig", "mnd", "endr", "str", "dex", "int", "fth", "arc" }

ERBalance.STATS = {
    vig  = { key = "vig",  name = "Vigor",        short = "VIG", colour = { 0.87, 0.28, 0.24 } },
    mnd  = { key = "mnd",  name = "Mind",         short = "MND", colour = { 0.40, 0.62, 0.85 } },
    endr = { key = "endr", name = "Endurance",    short = "END", colour = { 0.47, 0.74, 0.42 } },
    str  = { key = "str",  name = "Strength",     short = "STR", colour = { 0.85, 0.55, 0.25 } },
    dex  = { key = "dex",  name = "Dexterity",    short = "DEX", colour = { 0.72, 0.78, 0.35 } },
    int  = { key = "int",  name = "Intelligence", short = "INT", colour = { 0.55, 0.48, 0.82 } },
    fth  = { key = "fth",  name = "Faith",        short = "FTH", colour = { 0.90, 0.84, 0.55 } },
    arc  = { key = "arc",  name = "Arcane",       short = "ARC", colour = { 0.70, 0.40, 0.72 } },
}

-- ---------------------------------------------------------------------------
-- Stat effect envelopes
-- ---------------------------------------------------------------------------
-- Each entry is { base, max }. The realised value is
--     base + (max - base) * ERStats.scale(statValue) * EffectStrength
-- so `base` is what a stat of 1 gives and `max` is what 99 gives at
-- EffectStrength = 1.0. See ERStats.effect().
ERBalance.EFFECTS = {
    vig = {
        damageNegation   = { 0.00, 0.45 },   -- fraction of incoming damage removed
        regenPerTenMin   = { 0.00, 1.60 },   -- body-part health restored per 10 in-game minutes
        infectionResist  = { 0.00, 0.20 },   -- multiplier off zombification advance (see NOTES)
    },
    mnd = {
        panicReduction   = { 0.00, 0.75 },   -- fraction of panic scrubbed each minute
        stressReduction  = { 0.00, 0.55 },
        unhappyReduction = { 0.00, 0.45 },
        aimBoost         = { 0.00, 2.00 },   -- Perks.Aiming XP boost, floored to 0..3
    },
    endr = {
        staminaDrainCut  = { 0.00, 0.50 },   -- fraction of per-tick endurance loss refunded
        staminaRegen     = { 0.00, 0.35 },   -- extra endurance restored while resting
        carryWeight      = { 0.00, 8.00 },   -- kg added to max carry weight
        fatigueCut       = { 0.00, 0.35 },
    },
    str = {
        meleeDamage      = { 0.00, 1.10 },   -- +110% weapon damage at 99
        carryWeight      = { 0.00, 12.00 },  -- kg added to max carry weight
        knockback        = { 0.00, 0.60 },   -- fraction of push/shove failures converted to success
    },
    dex = {
        recoilCut        = { 0.00, 0.35 },   -- fraction off recoil delay (swing recovery)
        reloadBoost      = { 0.00, 2.00 },   -- Perks.Reloading XP boost, floored to 0..3
        conditionCut     = { 0.00, 0.55 },   -- fraction of weapon condition loss refunded
    },
    int = {
        xpMultiplier     = { 0.00, 1.00 },   -- +100% skill XP at 99
        readSpeed        = { 0.00, 0.50 },
        perkBoost        = { 0.00, 2.00 },   -- fallback global XP boost, floored to 0..3
    },
    fth = {
        healingPower     = { 0.00, 1.00 },   -- +100% effect from bandages/pills
        sicknessResist   = { 0.00, 0.60 },   -- fraction of foodSickness/illness scrubbed per minute
        moodleDecay      = { 0.00, 0.40 },
    },
    arc = {
        runeFind         = { 0.00, 1.00 },   -- +100% runes at 99
        lootLuck         = { 0.00, 0.35 },   -- chance of one bonus item per container roll
        rareLuck         = { 0.00, 0.50 },   -- multiplier on rune-item spawn weight
    },
}

-- ---------------------------------------------------------------------------
-- Rune sources (PLAN.md 4.1)
-- ---------------------------------------------------------------------------
ERBalance.RUNES = {
    base            = 8,
    crawler         = 5,
    sprinter        = 14,
    corpse          = 0,      -- already-dead / skeleton: no reward for corpse-hitting
    critMult        = 1.5,
    firearmMult     = 0.85,
    injuredMult     = 1.2,    -- killer below injuredThreshold overall health
    injuredThreshold= 0.60,
    hordeMult       = 1.3,
    hordeRadius     = 8,
    hordeCount      = 10,
    -- Consumables
    runeArc         = 500,
    goldenRune1     = 200,
    goldenRune2     = 800,
    goldenRune3     = 2500,
}

-- Item full-types for the rune consumables, mapped to their value.
ERBalance.RUNE_ITEMS = {
    ["ERLeveling.RuneArc"]     = "runeArc",
    ["ERLeveling.GoldenRune1"] = "goldenRune1",
    ["ERLeveling.GoldenRune2"] = "goldenRune2",
    ["ERLeveling.GoldenRune3"] = "goldenRune3",
}
ERBalance.RESPEC_ITEM = "ERLeveling.LarvalTear"
ERBalance.GRACE_ITEM  = "ERLeveling.GraceIdol"

-- ---------------------------------------------------------------------------
-- Sites of Grace (PLAN.md 5)
-- ---------------------------------------------------------------------------
ERBalance.GRACE = {
    campfireRadius  = 3,
    fireplaceRadius = 2,
    idolRadius      = 4,
    recheckMs       = 500,     -- proximity scan throttle
}

-- ---------------------------------------------------------------------------
-- Bloodstains (PLAN.md 4.2)
-- ---------------------------------------------------------------------------
ERBalance.BLOODSTAIN = {
    reclaimRadius   = 2,       -- tiles; ER auto-reclaims on contact
    checkIntervalMs = 750,
    markerRange     = 40,      -- draw the screen marker within this many tiles
}

-- ---------------------------------------------------------------------------
-- Perk-grant fallback for carry weight (PLAN.md 6, tier 3)
-- ---------------------------------------------------------------------------
ERBalance.PERK_GRANT = {
    enabled          = true,   -- only ever runs server-side / single-player
    strengthPerPoints= 12,     -- one Strength level per N points of (STR+END)/2
    fitnessPerPoints = 16,
    maxStrength      = 3,
    maxFitness       = 2,
}

-- ---------------------------------------------------------------------------
-- Sound
-- ---------------------------------------------------------------------------
-- No .ogg files ship with this mod, so these name vanilla sound events rather
-- than custom ones (see NOTES.md). Point them at your own sound pack by editing
-- this table; an empty string means silence.
ERBalance.SOUND = {
    levelUp = "LevelUp",
    grace   = "",
    runes   = "",
}

-- ---------------------------------------------------------------------------
-- UI palette (PLAN.md 7.3). Values are 0..1 floats, PZ's drawing convention.
-- ---------------------------------------------------------------------------
local function rgb(r, g, b) return { r = r / 255, g = g / 255, b = b / 255 } end

ERBalance.COLOR = {
    bg          = { r = 10 / 255, g = 9 / 255, b = 8 / 255, a = 0.92 },
    bgSolid     = { r = 10 / 255, g = 9 / 255, b = 8 / 255, a = 1.00 },
    gold        = rgb(201, 162, 39),    -- #C9A227
    goldDim     = rgb(122, 101, 32),    -- #7A6520
    goldBright  = rgb(233, 201, 96),
    track       = rgb(42, 38, 32),      -- #2A2620
    staged      = rgb(159, 214, 140),   -- #9FD68C
    warn        = rgb(180, 67, 46),     -- #B4432E
    text        = rgb(214, 208, 192),
    textDim     = rgb(128, 122, 108),
    white       = rgb(255, 255, 255),
    black       = rgb(0, 0, 0),
}

ERBalance.UI = {
    rowHeight      = 22,
    barWidth       = 130,
    barHeight      = 8,
    padding        = 10,
    stripHeight    = 26,
    popupFadeMs    = 1200,
    popupCoalesceMs= 500,
    youDiedMs      = 2600,
}

-- ---------------------------------------------------------------------------
-- Sandbox access
-- ---------------------------------------------------------------------------
-- Defaults mirror media/sandbox-options.txt so the mod is fully functional even
-- if the sandbox file fails to load or a save predates an option.
ERBalance.SANDBOX_DEFAULTS = {
    RuneMultiplier          = 1.0,
    CostA                   = 1.6,
    CostB                   = 2.2,
    CostC                   = 40.0,
    CostBase                = 40.0,
    CostPreset              = 1,      -- 1 = LandsBetweenLite, 2 = Authentic, 3 = Custom
    StartingStat            = 10,
    MaxStat                 = 99,
    RequireGrace            = true,
    LoseRunesOnDeath        = 100.0,
    BloodstainPersists      = true,
    AnyoneCanLootBloodstain = false,
    KeepStatsOnDeath        = false,
    ShowYouDied             = true,
    ShowHudCounter          = false,
    AllowRespec             = 2,      -- 1 = Never, 2 = LarvalTear, 3 = Free
    RuneArcSpawnRate        = 1.0,
    EffectStrength          = 1.0,
    AllowPerkGrants         = true,
    EnableSounds            = true,
    DebugCommands           = false,
}

ERBalance.COST_PRESET = { LANDS_BETWEEN_LITE = 1, AUTHENTIC = 2, CUSTOM = 3 }
ERBalance.RESPEC      = { NEVER = 1, LARVAL_TEAR = 2, FREE = 3 }

--- Read a sandbox option, falling back to the shipped default.
-- Never errors and never returns nil for a known key.
function ERBalance.sv(key)
    local default = ERBalance.SANDBOX_DEFAULTS[key]
    local ok, value = pcall(function()
        if SandboxVars == nil then return nil end
        local page = SandboxVars.ERLeveling
        if page == nil then return nil end
        return page[key]
    end)
    if ok and value ~= nil then return value end
    return default
end

--- Numeric sandbox read clamped to a sane range, so a hand-edited server config
-- cannot produce NaN or a divide-by-zero downstream (PLAN.md 14 test matrix).
function ERBalance.svNum(key, minV, maxV)
    local v = tonumber(ERBalance.sv(key))
    if v == nil or v ~= v then v = tonumber(ERBalance.SANDBOX_DEFAULTS[key]) or 0 end
    if minV and v < minV then v = minV end
    if maxV and v > maxV then v = maxV end
    return v
end
