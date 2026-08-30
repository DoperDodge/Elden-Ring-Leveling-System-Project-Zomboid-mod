--[[
    ERLeveling_Data.lua
    -------------------
    The only place that touches modData. Every read goes through an accessor that
    lazily initialises, so no other file ever has to assume a field exists
    (PLAN.md 8, "Migration").
]]

ERData = ERData or {}

-- ---------------------------------------------------------------------------
-- Identity
-- ---------------------------------------------------------------------------
--- Stable key for a player across death/respawn and across sessions.
-- Never store an IsoPlayer in a long-lived table (PLAN.md 15.2); store this.
function ERData.keyFor(player)
    if player == nil then return nil end
    local name = ERCompat.get(player, "getUsername", nil)
    if type(name) == "string" and name ~= "" then return name end
    local idx = ERCompat.get(player, "getPlayerNum", nil)
    if idx == nil then idx = 0 end
    return "SP_" .. tostring(idx)
end

--- Re-resolve a player object from a stored key. Returns nil if they are gone.
function ERData.resolve(key)
    if key == nil then return nil end
    if string.sub(key, 1, 3) == "SP_" then
        local idx = tonumber(string.sub(key, 4)) or 0
        local ok, p = pcall(function() return getSpecificPlayer(idx) end)
        if ok then return p end
        return nil
    end
    local ok, players = pcall(function() return getOnlinePlayers() end)
    if ok and players then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p and ERData.keyFor(p) == key then return p end
        end
    end
    -- Single player with a Steam username still answers to getSpecificPlayer(0).
    local ok2, p0 = pcall(function() return getSpecificPlayer(0) end)
    if ok2 and p0 and ERData.keyFor(p0) == key then return p0 end
    return nil
end

--- Iterate every player this side of the connection knows about.
-- Handles split-screen (PLAN.md 15.4) and dedicated servers alike.
function ERData.forEachPlayer(fn)
    local handled = {}
    local ok, players = pcall(function() return getOnlinePlayers() end)
    if ok and players and players:size() > 0 then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p then
                handled[ERData.keyFor(p)] = true
                ERCompat.guard("forEachPlayer", fn, p)
            end
        end
    end
    for i = 0, 3 do
        local ok2, p = pcall(function() return getSpecificPlayer(i) end)
        if ok2 and p and not handled[ERData.keyFor(p)] then
            handled[ERData.keyFor(p)] = true
            ERCompat.guard("forEachPlayer", fn, p)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Per-player data
-- ---------------------------------------------------------------------------
local function defaults()
    local starting = ERBalance.svNum("StartingStat", 1, 99)
    local stats = {}
    for i = 1, #ERBalance.STAT_ORDER do
        stats[ERBalance.STAT_ORDER[i]] = starting
    end
    return {
        version      = ERBalance.DATA_VERSION,
        stats        = stats,
        heldRunes    = 0,
        totalEarned  = 0,
        totalSpent   = 0,
        level        = 1,
        deaths       = 0,
        grantedPerks = { Strength = 0, Fitness = 0 },
        lastGraceX   = nil,
        lastGraceY   = nil,
        lastGraceZ   = nil,
    }
end

ERData.defaults = defaults

-- Migration functions run in ascending order; each takes the table and upgrades
-- it by exactly one schema version. Add new ones here, never edit old ones.
ERData.MIGRATIONS = {
    -- [1] = function(d) ... end,   -- 1 -> 2, when the schema next changes
}

local function migrate(d)
    local from = tonumber(d.version) or 0
    while from < ERBalance.DATA_VERSION do
        local step = ERData.MIGRATIONS[from]
        if step then ERCompat.guard("migrate " .. tostring(from), step, d) end
        from = from + 1
        d.version = from
    end
end

--- The mod's data table for a player. Always returns a fully populated table.
function ERData.get(player)
    if player == nil then return defaults() end
    local ok, md = pcall(function() return player:getModData() end)
    if not ok or md == nil then return defaults() end
    local d = md.ERLeveling
    if type(d) ~= "table" then
        d = defaults()
        md.ERLeveling = d
        return d
    end
    -- Repair anything missing rather than trusting the shape (PLAN.md 8).
    --
    -- This runs on every read, including from OnPlayerUpdate, so it must not
    -- allocate on the happy path (PLAN.md 15.1): the starting value is read as a
    -- number and no defaults table is built unless something is actually wrong.
    local starting = ERBalance.svNum("StartingStat", 1, 99)
    if type(d.stats) ~= "table" then d.stats = {} end
    for i = 1, #ERBalance.STAT_ORDER do
        local k = ERBalance.STAT_ORDER[i]
        if tonumber(d.stats[k]) == nil then d.stats[k] = starting end
    end
    if tonumber(d.heldRunes)   == nil then d.heldRunes   = 0 end
    if tonumber(d.totalEarned) == nil then d.totalEarned = 0 end
    if tonumber(d.totalSpent)  == nil then d.totalSpent  = 0 end
    if tonumber(d.deaths)      == nil then d.deaths      = 0 end
    if type(d.grantedPerks) ~= "table" then d.grantedPerks = { Strength = 0, Fitness = 0 } end
    if tonumber(d.grantedPerks.Strength) == nil then d.grantedPerks.Strength = 0 end
    if tonumber(d.grantedPerks.Fitness)  == nil then d.grantedPerks.Fitness  = 0 end
    if d.version == nil then d.version = 0 end
    migrate(d)
    d.level = ERLevel.fromStats(d.stats)
    return d
end

--- Convenience: one stat value.
function ERData.stat(player, key)
    local d = ERData.get(player)
    return tonumber(d.stats[key]) or ERBalance.svNum("StartingStat", 1, 99)
end

function ERData.runes(player)
    return math.floor(tonumber(ERData.get(player).heldRunes) or 0)
end

function ERData.level(player)
    return ERLevel.fromStats(ERData.get(player).stats)
end

--- Push modData to the network. Server-authoritative writes must call this.
function ERData.transmit(player)
    if player == nil then return end
    if not isClient() and not isServer() then return end   -- single player: nothing to do
    ERCompat.call(player, "transmitModData")
end

-- ---------------------------------------------------------------------------
-- Global (bloodstain registry)
-- ---------------------------------------------------------------------------
--- The shared ERLeveling_Global table. On a dedicated server this is the
-- authoritative copy; clients receive it via ModData.transmit.
function ERData.global()
    local ok, g = pcall(function() return ModData.getOrCreate(ERBalance.GLOBAL_KEY) end)
    if not ok or g == nil then
        -- No ModData API (should not happen); fall back to a process-local table so
        -- single-player still works, and say so once.
        ERLeveling_LocalGlobal = ERLeveling_LocalGlobal or {}
        g = ERLeveling_LocalGlobal
    end
    if tonumber(g.version) == nil then g.version = ERBalance.DATA_VERSION end
    if type(g.bloodstains) ~= "table" then g.bloodstains = {} end
    return g
end

function ERData.transmitGlobal()
    if not isClient() and not isServer() then return end
    pcall(function() ModData.transmit(ERBalance.GLOBAL_KEY) end)
end
