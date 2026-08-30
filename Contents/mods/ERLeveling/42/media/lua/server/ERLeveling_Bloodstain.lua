--[[
    ERLeveling_Bloodstain.lua
    -------------------------
    Death, the bloodstain registry, and reclaiming (PLAN.md 4.2).

    "This is the mechanic people will judge the mod on."

    Rules implemented here:
      * One active bloodstain per player. A new death destroys the old one.
      * The stain is stored in global mod data, so it survives the death of the
        character that made it and is visible to the new one.
      * Reclaiming is server-validated: the client can ask, it can not grant.
      * Stats optionally carry across characters (KeepStatsOnDeath), because a PZ
        death makes a brand new IsoPlayer with brand new modData.
]]

ERBloodstain = ERBloodstain or {}

local DEDUPE_MS = 10000   -- ignore a duplicate death report within this window

--- The stain record for a player, or nil.
function ERBloodstain.forPlayer(player)
    if player == nil then return nil end
    local key = ERData.keyFor(player)
    local g = ERData.global()
    local rec = g.bloodstains[key]
    if rec == nil and ERBalance.sv("AnyoneCanLootBloodstain") then
        -- Any stain is fair game; hand back the nearest one so the UI can point at it.
        local best, bestDist = nil, nil
        local px = ERCompat.get(player, "getX", 0)
        local py = ERCompat.get(player, "getY", 0)
        for _, r in pairs(g.bloodstains) do
            local dist = ERUtil.dist2D(px, py, r.x, r.y)
            if bestDist == nil or dist < bestDist then best, bestDist = r, dist end
        end
        rec = best
    end
    if rec == nil then return nil end
    return { x = rec.x, y = rec.y, z = rec.z, runes = rec.runes, time = rec.time, owner = rec.owner }
end

-- ---------------------------------------------------------------------------
-- World marker (PLAN.md 4.3 fallback ladder)
-- ---------------------------------------------------------------------------
-- Tier 1 (a proper floor decal) needs a world-decal API we cannot confirm exists,
-- so the shipped marker is tier 2 + tier 3 + tier 4 together: a world item where
-- the square is loaded, a screen-space beacon drawn by the client, and the
-- distance/direction readout on the Runes tab. See NOTES.md.
local MARKER_TYPE = "ERLeveling.Bloodstain"

local function squareAt(x, y, z)
    local ok, cell = pcall(function() return getCell() end)
    if not ok or cell == nil then return nil end
    local ok2, sq = pcall(function() return cell:getGridSquare(x, y, z) end)
    if not ok2 then return nil end
    return sq
end

local function spawnMarker(x, y, z)
    local sq = squareAt(x, y, z)
    if sq == nil then return false end
    local ok = pcall(function() sq:AddWorldInventoryItem(MARKER_TYPE, 0.5, 0.5, 0.0) end)
    return ok
end

local function removeMarker(x, y, z)
    local sq = squareAt(x, y, z)
    if sq == nil then return end
    pcall(function()
        local items = sq:getWorldObjects()
        if items == nil then return end
        for i = items:size() - 1, 0, -1 do
            local wi = items:get(i)
            local item = wi and wi:getItem() or nil
            if item ~= nil and ERCompat.get(item, "getFullType", nil) == MARKER_TYPE then
                sq:removeWorldObject(wi)
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Death
-- ---------------------------------------------------------------------------
--- Create (or replace) the bloodstain for a player and strip their runes.
-- Safe to call more than once; repeats inside DEDUPE_MS are ignored.
function ERBloodstain.onDeath(player)
    if player == nil then return end
    local key = ERData.keyFor(player)
    if key == nil then return end

    local g = ERData.global()
    local existing = g.bloodstains[key]
    local now = ERUtil.nowMs()
    if existing and existing.createdMs and (now - existing.createdMs) < DEDUPE_MS then
        return   -- already handled this death
    end

    -- Rune balance: prefer live modData, fall back to the mirror if the player
    -- object is already half torn down (PLAN.md 15.3).
    local held = ERRunes.snapshot[key]
    local okData, d = pcall(function() return ERData.get(player) end)
    if okData and d ~= nil and tonumber(d.heldRunes) ~= nil then
        held = math.floor(d.heldRunes)
    end
    held = math.floor(tonumber(held) or 0)

    local losePct = ERBalance.svNum("LoseRunesOnDeath", 0, 100) / 100.0
    local dropped = math.floor(held * losePct)

    if okData and d ~= nil then
        d.heldRunes = held - dropped
        d.deaths    = (tonumber(d.deaths) or 0) + 1
        -- Carry-over slot for the next character.
        g.carryOver = g.carryOver or {}
        g.carryOver[key] = {
            stats      = ERUtil.copyStats(d.stats),
            totalSpent = math.floor(tonumber(d.totalSpent) or 0),
            totalEarned= math.floor(tonumber(d.totalEarned) or 0),
            keptRunes  = d.heldRunes,
            deaths     = d.deaths,
        }
    end
    ERRunes.snapshot[key] = math.max(0, held - dropped)

    -- Destroy the previous stain, exactly like Elden Ring.
    if existing then removeMarker(existing.x, existing.y, existing.z) end
    g.bloodstains[key] = nil

    if dropped > 0 and ERBalance.sv("BloodstainPersists") then
        local x = math.floor(ERCompat.get(player, "getX", 0))
        local y = math.floor(ERCompat.get(player, "getY", 0))
        local z = math.floor(ERCompat.get(player, "getZ", 0))
        g.bloodstains[key] = {
            x = x, y = y, z = z,
            runes = dropped,
            time = ERUtil.now(),
            createdMs = now,
            owner = key,
        }
        spawnMarker(x, y, z)
    end

    ERData.transmitGlobal()
    pcall(function() ERData.transmit(player) end)
    ERNet.reply(player, "died", { dropped = dropped, x = g.bloodstains[key] and g.bloodstains[key].x or nil,
                                  y = g.bloodstains[key] and g.bloodstains[key].y or nil })
end

-- ---------------------------------------------------------------------------
-- Respawn: restore carried-over stats when the sandbox says so
-- ---------------------------------------------------------------------------
function ERBloodstain.onCreatePlayer(playerIndex, player)
    if player == nil then return end
    local key = ERData.keyFor(player)
    local g = ERData.global()
    local carry = g.carryOver and g.carryOver[key] or nil
    local d = ERData.get(player)

    if carry and ERBalance.sv("KeepStatsOnDeath") then
        d.stats      = ERUtil.copyStats(carry.stats)
        d.totalSpent = math.floor(tonumber(carry.totalSpent) or 0)
        d.totalEarned= math.floor(tonumber(carry.totalEarned) or 0)
        d.heldRunes  = math.floor(tonumber(carry.keptRunes) or 0)
        d.deaths     = math.floor(tonumber(carry.deaths) or 0)
        d.level      = ERLevel.fromStats(d.stats)
        ERServer.applyPerkGrants(player, d)
    end
    ERRunes.snapshot[key] = math.floor(tonumber(d.heldRunes) or 0)
    ERData.transmit(player)
    ERNet.reply(player, "sync", ERServer.snapshot(player))
end

-- ---------------------------------------------------------------------------
-- Reclaim
-- ---------------------------------------------------------------------------
ERNet.handle("reclaim", function(player, args)
    if player == nil then return { ok = false, reason = "no_player" } end
    local key = ERData.keyFor(player)
    local g = ERData.global()

    local rec, recKey = g.bloodstains[key], key
    if rec == nil and ERBalance.sv("AnyoneCanLootBloodstain") then
        local px = ERCompat.get(player, "getX", 0)
        local py = ERCompat.get(player, "getY", 0)
        for k, r in pairs(g.bloodstains) do
            if ERUtil.dist2D(px, py, r.x, r.y) <= ERBalance.BLOODSTAIN.reclaimRadius then
                rec, recKey = r, k
                break
            end
        end
    end
    if rec == nil then return { ok = false, reason = "no_bloodstain" } end

    -- Server re-validates the distance; the client only asks.
    local px = ERCompat.get(player, "getX", 0)
    local py = ERCompat.get(player, "getY", 0)
    local pz = math.floor(ERCompat.get(player, "getZ", 0))
    if math.floor(rec.z or 0) ~= pz then return { ok = false, reason = "wrong_floor" } end
    if ERUtil.dist2D(px, py, rec.x + 0.5, rec.y + 0.5) > ERBalance.BLOODSTAIN.reclaimRadius then
        return { ok = false, reason = "too_far" }
    end

    local amount = math.floor(tonumber(rec.runes) or 0)
    g.bloodstains[recKey] = nil
    removeMarker(rec.x, rec.y, rec.z)
    ERData.transmitGlobal()

    ERRunes.credit(player, amount, "bloodstain")
    return ERServer.snapshot(player, { reclaimed = amount })
end)

--- A multiplayer client cannot run server Lua, so it reports its own death and the
-- server does the work. Duplicates are absorbed by the DEDUPE_MS window above.
ERNet.handle("reportDeath", function(player, args)
    ERBloodstain.onDeath(player)
    return { ok = true }
end)

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
ERCompat.onEvent("OnPlayerDeath", function(player)
    ERBloodstain.onDeath(player)
end)

ERCompat.onEvent("OnCreatePlayer", function(playerIndex, player)
    ERBloodstain.onCreatePlayer(playerIndex, player)
end)
