--[[
    ERLevelingDistributions.lua
    ---------------------------
    Loot placement for the rune consumables (PLAN.md 11).

    Build 42 reorganised loot distribution substantially, and we cannot confirm
    which tables the installed build exposes, so this file:
      1. probes for ProceduralDistributions / SuburbsDistributions and injects
         into whichever it finds, on whichever merge event exists;
      2. falls back to a light OnFillContainer roll if neither is present, which
         also carries the Arcane "loot luck" effect either way.

    Nothing here edits a vanilla item; we only add entries (PLAN.md 15.11).
]]

ERLoot = ERLoot or {}

-- room/container table name -> { itemFullType, weight }
-- Weights are vanilla-scale (roughly "1 = uncommon, 0.2 = rare").
ERLoot.PROCEDURAL = {
    -- Golden Runes: personal valuables, where someone would stash cash.
    BedroomDresser        = { { "ERLeveling.GoldenRune1", 0.35 }, { "ERLeveling.GoldenRune2", 0.08 } },
    WardrobeMan           = { { "ERLeveling.GoldenRune1", 0.25 } },
    WardrobeWoman         = { { "ERLeveling.GoldenRune1", 0.25 } },
    LivingRoomShelf       = { { "ERLeveling.GoldenRune1", 0.20 } },
    OfficeDesk            = { { "ERLeveling.GoldenRune1", 0.22 }, { "ERLeveling.GoldenRune2", 0.05 } },
    -- Rune Arcs: churches, thematically, plus prepared safehouses.
    ChurchDonation        = { { "ERLeveling.RuneArc", 0.60 } },
    ChurchStorage         = { { "ERLeveling.RuneArc", 0.45 }, { "ERLeveling.GraceIdol", 0.20 } },
    CrateCampingStore     = { { "ERLeveling.GraceIdol", 0.30 } },
    CampingStoreShelf     = { { "ERLeveling.GraceIdol", 0.25 } },
    SurvivalGear          = { { "ERLeveling.RuneArc", 0.30 }, { "ERLeveling.GraceIdol", 0.30 } },
    -- The really rare things.
    BankVault             = { { "ERLeveling.GoldenRune3", 0.35 }, { "ERLeveling.LarvalTear", 0.20 } },
    SafeHouseLoot         = { { "ERLeveling.GoldenRune2", 0.25 }, { "ERLeveling.LarvalTear", 0.10 } },
    GunStoreCounter       = { { "ERLeveling.GoldenRune2", 0.20 } },
    ArmyStorageAmmunition = { { "ERLeveling.GoldenRune2", 0.15 } },
}

-- Container-type fallback used by OnFillContainer when no distribution table is
-- reachable. containerType -> { itemFullType, chance 0..1 }
ERLoot.FALLBACK = {
    dresser     = { { "ERLeveling.GoldenRune1", 0.010 } },
    wardrobe    = { { "ERLeveling.GoldenRune1", 0.008 } },
    desk        = { { "ERLeveling.GoldenRune1", 0.008 } },
    shelves     = { { "ERLeveling.GoldenRune1", 0.005 }, { "ERLeveling.RuneArc", 0.002 } },
    counter     = { { "ERLeveling.RuneArc", 0.003 } },
    crate       = { { "ERLeveling.GraceIdol", 0.004 } },
    metal_shelves = { { "ERLeveling.GoldenRune2", 0.002 } },
    safe        = { { "ERLeveling.GoldenRune3", 0.060 }, { "ERLeveling.LarvalTear", 0.030 } },
}

local function rate()
    return ERBalance.svNum("RuneArcSpawnRate", 0.0, 10.0)
end

-- ---------------------------------------------------------------------------
-- Path 1: distribution tables
-- ---------------------------------------------------------------------------
local function injectInto(list)
    local injected = 0
    for tableName, entries in pairs(ERLoot.PROCEDURAL) do
        local target = list[tableName]
        if type(target) == "table" and type(target.items) == "table" then
            for i = 1, #entries do
                local fullType, weight = entries[i][1], entries[i][2] * rate()
                if weight > 0 then
                    table.insert(target.items, fullType)
                    table.insert(target.items, weight)
                    injected = injected + 1
                end
            end
        end
    end
    return injected
end

function ERLoot.inject()
    if ERLoot._injected then return end
    local injected = 0
    if ERCompat.hasGlobal("ProceduralDistributions") then
        local ok, list = pcall(function() return ProceduralDistributions.list end)
        if ok and type(list) == "table" then
            injected = injected + injectInto(list)
        end
    end
    if injected == 0 and ERCompat.hasGlobal("SuburbsDistributions") then
        local ok, list = pcall(function() return SuburbsDistributions.all end)
        if ok and type(list) == "table" then
            injected = injected + injectInto(list)
        end
    end
    ERLoot._injected = injected > 0
    print("[ERLeveling] loot: injected " .. tostring(injected) .. " distribution entries"
          .. (ERLoot._injected and "" or " (falling back to OnFillContainer rolls)"))
end

-- Whichever merge hook this build has.
if not ERCompat.onEvent("OnDistributionMerge", function() ERLoot.inject() end) then
    if not ERCompat.onEvent("OnPreDistributionMerge", function() ERLoot.inject() end) then
        ERCompat.onEvent("OnGameBoot", function() ERLoot.inject() end)
    end
end

-- ---------------------------------------------------------------------------
-- Path 2: OnFillContainer, which also carries the Arcane loot-luck effect
-- ---------------------------------------------------------------------------
local function addItem(container, fullType)
    local ok = pcall(function() container:AddItem(fullType) end)
    return ok
end

--- Highest Arcane among the players this side knows about. Container filling has
-- no owning player, so "the luckiest survivor nearby" is the best available proxy.
local function bestArcane()
    local best = ERBalance.svNum("StartingStat", 1, 99)
    ERData.forEachPlayer(function(p)
        local v = ERData.stat(p, "arc")
        if v > best then best = v end
    end)
    return best
end

ERCompat.onEvent("OnFillContainer", function(roomName, containerType, container)
    if container == nil then return end
    local r = rate()
    if r <= 0 then return end

    local rareLuck = 1.0 + ERStats.effect("arc", "rareLuck", bestArcane())

    if not ERLoot._injected then
        local entries = ERLoot.FALLBACK[containerType]
        if entries then
            for i = 1, #entries do
                local fullType, chance = entries[i][1], entries[i][2] * r * rareLuck
                if ZombRand(10000) < math.floor(chance * 10000) then
                    addItem(container, fullType)
                end
            end
        end
    end

    -- Arcane loot luck (PLAN.md 3.1): a small chance of one bonus item from what
    -- the container already rolled. Deliberately subtle - it duplicates one
    -- existing item rather than inventing loot, so it can never introduce
    -- something the room would not have produced.
    local luck = ERStats.reduction("arc", "lootLuck", bestArcane(), 0.60)
    if luck > 0 and ZombRand(10000) < math.floor(luck * 10000) then
        pcall(function()
            local items = container:getItems()
            if items == nil or items:size() == 0 then return end
            local pick = items:get(ZombRand(items:size()))
            if pick ~= nil then
                local ft = ERCompat.get(pick, "getFullType", nil)
                if ft ~= nil then addItem(container, ft) end
            end
        end)
    end
end)
