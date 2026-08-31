--[[
    ERLeveling_ClientCommands.lua
    -----------------------------
    Client-side reconciliation (PLAN.md 9, step 5).

    The client's source of truth for numbers is the player's modData, which the
    server transmits after every mutation. These handlers exist to react to
    *events* - a gain to animate, a rejection to explain, a death to overlay -
    not to store state the server owns.
]]

ERClient = ERClient or {}
ERClient.lastError = nil
ERClient.lastErrorAt = 0

--- The local player this UI is for. Split-screen aware (PLAN.md 15.4).
-- Falls back to getPlayer() only for slot 0: returning player 0 for an absent
-- second local player would show one survivor's runes under the other's UI.
function ERClient.player(playerNum)
    local n = playerNum or 0
    local ok, p = pcall(function() return getSpecificPlayer(n) end)
    if ok and p ~= nil then return ERClient.usable(p) end
    if n ~= 0 then return nil end
    local ok2, p2 = pcall(function() return getPlayer() end)
    if ok2 then return ERClient.usable(p2) end
    return nil
end

--- nil for a player who is dead or being torn down.
--
-- The rune strip and the Runes tab read from the player on every frame, and the
-- death sequence is precisely when that object stops being safe to touch. Dying
-- was reported to crash the game sometimes; a render path still reading a
-- half-destroyed IsoPlayer is a candidate, and refusing to look is free. The UI
-- shows zeroes for the moment between death and the next character, which is
-- both harmless and honest.
function ERClient.usable(player)
    if player == nil then return nil end
    if ERCompat.get(player, "isDead", false) == true then return nil end
    return player
end

-- Snapshot caching. Both the rune strip and the Runes tab call snapshot() from
-- their render paths, so an uncached call allocates a stats table twice per
-- frame. A short TTL keeps the UI live to the eye while making the steady-state
-- cost a table lookup (PLAN.md 15.1).
ERClient._snapCache = ERClient._snapCache or {}
local SNAPSHOT_TTL_MS = 120

--- Drop the cache so the next read is authoritative. Called on every reply.
function ERClient.invalidate()
    ERClient._snapCache = {}
end

--- Everything the UI needs, in one read.
function ERClient.snapshot(playerNum)
    local n = playerNum or 0
    local cached = ERClient._snapCache[n]
    local now = ERUtil.nowMs()
    if cached ~= nil and (now - cached.at) < SNAPSHOT_TTL_MS then
        return cached.data
    end
    local data = ERClient.buildSnapshot(n)
    ERClient._snapCache[n] = { at = now, data = data }
    return data
end

function ERClient.buildSnapshot(playerNum)
    local p = ERClient.player(playerNum)
    if p == nil then
        return {
            stats = ERUtil.copyStats(nil), runes = 0, level = 1,
            grace = false, graceReason = "none", bloodstain = nil,
            totalEarned = 0, totalSpent = 0, deaths = 0,
        }
    end
    local d = ERData.get(p)
    return {
        stats       = ERUtil.copyStats(d.stats),
        runes       = math.floor(tonumber(d.heldRunes) or 0),
        level       = ERLevel.fromStats(d.stats),
        totalEarned = math.floor(tonumber(d.totalEarned) or 0),
        totalSpent  = math.floor(tonumber(d.totalSpent) or 0),
        deaths      = math.floor(tonumber(d.deaths) or 0),
        grace       = ERGraceClient.isAtGrace(playerNum),
        graceReason = ERGraceClient.reason(playerNum),
        bloodstain  = ERClient.bloodstain(p),
    }
end

--- This player's bloodstain from the transmitted global table.
function ERClient.bloodstain(player)
    if player == nil then return nil end
    local ok, g = pcall(function() return ERData.global() end)
    if not ok or g == nil then return nil end
    local key = ERData.keyFor(player)
    local rec = g.bloodstains[key]
    if rec == nil and ERBalance.sv("AnyoneCanLootBloodstain") then
        local px = ERCompat.get(player, "getX", 0)
        local py = ERCompat.get(player, "getY", 0)
        local best, bestDist
        for _, r in pairs(g.bloodstains) do
            local dist = ERUtil.dist2D(px, py, r.x, r.y)
            if bestDist == nil or dist < bestDist then best, bestDist = r, dist end
        end
        rec = best
    end
    return rec
end

-- ---------------------------------------------------------------------------
-- Requests
-- ---------------------------------------------------------------------------
function ERClient.requestLevelUp(playerNum, deltas, expectedCost)
    local p = ERClient.player(playerNum)
    if p == nil then return end
    ERNet.request(p, "levelUp", { deltas = deltas, expectedCost = expectedCost })
end

function ERClient.requestRespec(playerNum, itemId)
    local p = ERClient.player(playerNum)
    if p == nil then return end
    ERNet.request(p, "respec", { id = itemId })
end

function ERClient.requestReclaim(playerNum)
    local p = ERClient.player(playerNum)
    if p == nil then return end
    ERNet.request(p, "reclaim", {})
end

function ERClient.requestSync(playerNum)
    local p = ERClient.player(playerNum)
    if p == nil then return end
    ERNet.request(p, "requestSync", {})
end

-- ---------------------------------------------------------------------------
-- Results
-- ---------------------------------------------------------------------------
ERClient.ERRORS = {
    no_grace        = "You must rest at a Site of Grace.",
    insufficient    = "Not enough runes.",
    over_max        = "That attribute is already at its limit.",
    no_points       = "Nothing staged.",
    too_fast        = "Slow down.",
    respec_disabled = "Respeccing is disabled on this world.",
    no_larval_tear  = "You need a Larval Tear.",
    no_bloodstain   = "You have no bloodstain to reclaim.",
    too_far         = "Too far from your bloodstain.",
    wrong_floor     = "Your bloodstain is on another floor.",
    item_missing    = "The item is gone.",
    unknown_item    = "That item holds no runes.",
    bad_request     = "Something went wrong.",
    internal_error  = "Something went wrong.",
}

local function showError(reason)
    ERClient.lastError = ERClient.ERRORS[reason] or tostring(reason)
    ERClient.lastErrorAt = ERUtil.nowMs()
    if ERLevelPanel and ERLevelPanel.onServerReply then
        ERLevelPanel.onServerReply(false, ERClient.lastError)
    end
end

local function applyOk(args, flashText)
    ERClient.lastError = nil
    ERClient.invalidate()
    if ERLevelPanel and ERLevelPanel.onServerReply then
        ERLevelPanel.onServerReply(true, flashText, args)
    end
end

local function resultHandler(onSuccess)
    return function(args)
        args = args or {}
        if args.ok == false then
            showError(args.reason)
            return
        end
        onSuccess(args)
    end
end

ERNet.onResult("sync", resultHandler(function(args) applyOk(args, nil) end))

ERNet.onResult("levelUpResult", resultHandler(function(args)
    ERUI.playLevelUpSound()
    ERUI.flash()
    applyOk(args, nil)
end))

ERNet.onResult("respecResult", resultHandler(function(args)
    ERUI.playLevelUpSound()
    applyOk(args, nil)
end))

-- Note: neither of these pushes a popup. Both go through ERRunes.credit on the
-- authoritative side, which already emits a "runeGain" event, and pushing here
-- as well would show the player double what they actually received.
ERNet.onResult("consumeRuneResult", resultHandler(function(args)
    applyOk(args, nil)
end))

ERNet.onResult("reclaimResult", resultHandler(function(args)
    applyOk(args, nil)
end))

ERNet.onResult("runeGain", function(args)
    args = args or {}
    ERClient.invalidate()
    if args.amount then ERUI.pushRuneGain(args.amount, args.source == "bloodstain") end
end)

ERNet.onResult("died", function(args)
    args = args or {}
    ERUI.showYouDied(args.dropped or 0)
end)

ERNet.onResult("reportDeathResult", function(args) end)

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
ERCompat.onEvent("OnCreatePlayer", function(playerIndex, player)
    if player == nil then return end
    ERClient.requestSync(playerIndex)
end)

-- A multiplayer client cannot run the server's death handling, so it reports.
-- The server absorbs duplicates (see ERBloodstain DEDUPE_MS).
ERCompat.onEvent("OnPlayerDeath", function(player)
    if player == nil then return end
    ERUI.showYouDied(nil)
    if isClient() then
        ERNet.request(player, "reportDeath", {})
    end
end)
