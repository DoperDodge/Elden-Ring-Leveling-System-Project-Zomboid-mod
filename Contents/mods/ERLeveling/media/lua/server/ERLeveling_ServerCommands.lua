--[[
    ERLeveling_ServerCommands.lua
    -----------------------------
    Authoritative handlers (PLAN.md 9). This file loads on a dedicated server and
    in single player, never on a multiplayer client, so nothing here can be reached
    by a client except through ERNet.

    Every handler re-derives cost, Grace state and balances from server state.
    `expectedCost` from the client is used for one thing only: telling the player
    their UI was stale.
]]

ERServer = ERServer or {}

-- Per-player rate limiting. Keyed by ERData.keyFor(), values are timestamps.
ERServer._lastAction = ERServer._lastAction or {}

local function rateLimited(player, action, minMs)
    local key = tostring(ERData.keyFor(player)) .. "/" .. action
    local now = ERUtil.nowMs()
    local last = ERServer._lastAction[key] or 0
    if now - last < (minMs or 250) then return true end
    ERServer._lastAction[key] = now
    return false
end

--- The reply body every mutation returns, so the client can reconcile from one shape.
function ERServer.snapshot(player, extra)
    local d = ERData.get(player)
    local grace, reason = ERGrace.check(player)
    local out = {
        ok          = true,
        stats       = ERUtil.copyStats(d.stats),
        runes       = math.floor(d.heldRunes or 0),
        level       = ERLevel.fromStats(d.stats),
        totalEarned = math.floor(d.totalEarned or 0),
        totalSpent  = math.floor(d.totalSpent or 0),
        grace       = grace,
        graceReason = reason,
        bloodstain  = ERBloodstain and ERBloodstain.forPlayer(player) or nil,
    }
    if extra then
        for k, v in pairs(extra) do out[k] = v end
    end
    return out
end

--- Push the current authoritative state at a player.
function ERServer.push(player, extra)
    if player == nil then return end
    ERData.transmit(player)
    ERNet.reply(player, "sync", ERServer.snapshot(player, extra))
end

-- ---------------------------------------------------------------------------
-- sync: client asking for the current truth (login, UI open, reconnect)
-- ---------------------------------------------------------------------------
ERNet.handle("requestSync", function(player, args)
    return ERServer.snapshot(player)
end)

-- ---------------------------------------------------------------------------
-- levelUp
-- ---------------------------------------------------------------------------
ERNet.handle("levelUp", function(player, args)
    if player == nil then return { ok = false, reason = "no_player" } end
    if rateLimited(player, "levelUp", 300) then
        return { ok = false, reason = "too_fast" }
    end

    local deltas = args.deltas
    if type(deltas) ~= "table" then return { ok = false, reason = "bad_request" } end

    local d = ERData.get(player)
    local maxStat = ERBalance.svNum("MaxStat", 10, 99)
    local points = 0
    local clean = {}

    for i = 1, #ERBalance.STAT_ORDER do
        local k = ERBalance.STAT_ORDER[i]
        local delta = math.floor(tonumber(deltas[k]) or 0)
        if delta < 0 then return { ok = false, reason = "negative_delta" } end
        if delta > 0 then
            local current = tonumber(d.stats[k]) or 0
            if current + delta > maxStat then
                return { ok = false, reason = "over_max", stat = k }
            end
            clean[k] = delta
            points = points + delta
        end
    end

    if points <= 0 then return { ok = false, reason = "no_points" } end
    if points > 200 then return { ok = false, reason = "bad_request" } end

    -- Grace gate, re-checked from server-side world state.
    if ERBalance.sv("RequireGrace") then
        local grace = ERGrace.check(player)
        if not grace then return { ok = false, reason = "no_grace" } end
    end

    -- Cost is always recomputed. The client's expectedCost is advisory only.
    local level = ERLevel.fromStats(d.stats)
    local cost = ERLevel.totalCost(level, points)
    local held = math.floor(tonumber(d.heldRunes) or 0)
    if cost > held then
        return { ok = false, reason = "insufficient", cost = cost, runes = held }
    end

    for k, delta in pairs(clean) do
        d.stats[k] = (tonumber(d.stats[k]) or 0) + delta
    end
    d.heldRunes  = held - cost
    d.totalSpent = math.floor(tonumber(d.totalSpent) or 0) + cost
    d.level      = ERLevel.fromStats(d.stats)

    ERServer.applyPerkGrants(player, d)
    ERData.transmit(player)

    return ERServer.snapshot(player, { spent = cost, points = points, levelledUp = true })
end)

-- ---------------------------------------------------------------------------
-- respec (Larval Tear)
-- ---------------------------------------------------------------------------
ERNet.handle("respec", function(player, args)
    if player == nil then return { ok = false, reason = "no_player" } end
    if rateLimited(player, "respec", 2000) then return { ok = false, reason = "too_fast" } end

    local mode = ERBalance.sv("AllowRespec")
    if mode == ERBalance.RESPEC.NEVER then return { ok = false, reason = "respec_disabled" } end

    local consumed = nil
    if mode == ERBalance.RESPEC.LARVAL_TEAR then
        consumed = ERServer.consumeItem(player, ERBalance.RESPEC_ITEM, args.id)
        if not consumed then return { ok = false, reason = "no_larval_tear" } end
    end

    local d = ERData.get(player)
    local refund = math.floor(tonumber(d.totalSpent) or 0)
    local starting = ERBalance.svNum("StartingStat", 1, 99)
    for i = 1, #ERBalance.STAT_ORDER do
        d.stats[ERBalance.STAT_ORDER[i]] = starting
    end
    d.heldRunes  = math.floor(tonumber(d.heldRunes) or 0) + refund
    d.totalSpent = 0
    d.level      = 1

    ERServer.applyPerkGrants(player, d)
    ERData.transmit(player)
    return ERServer.snapshot(player, { refunded = refund, respec = true, consumedItem = consumed })
end)

-- ---------------------------------------------------------------------------
-- consumeRune (Rune Arc / Golden Runes)
-- ---------------------------------------------------------------------------
ERNet.handle("consumeRune", function(player, args)
    if player == nil then return { ok = false, reason = "no_player" } end
    if rateLimited(player, "consumeRune", 400) then return { ok = false, reason = "too_fast" } end

    local fullType = args.fullType
    local valueKey = ERBalance.RUNE_ITEMS[fullType]
    if valueKey == nil then return { ok = false, reason = "unknown_item" } end

    local consumed = ERServer.consumeItem(player, fullType, args.id)
    if not consumed then return { ok = false, reason = "item_missing" } end

    local amount = math.floor((ERBalance.RUNES[valueKey] or 0)
                 * ERBalance.svNum("RuneMultiplier", 0.0, 100.0))
    ERRunes.credit(player, amount, "item")
    return ERServer.snapshot(player, { gained = amount, source = "item" })
end)

--- Remove one item of `fullType` from a player's inventory, server-side where the
-- API allows it. Returns true when we are confident the item is gone.
--
-- On a dedicated server the player's inventory is replicated, so we can find and
-- destroy the item ourselves and the transaction is fully authoritative. If the
-- lookup fails (an unreplicated container, a build without getItems), we fall back
-- to trusting the client's claim, which is why every consuming handler is also
-- rate-limited. Recorded in NOTES.md.
function ERServer.consumeItem(player, fullType, id)
    local item = nil
    if id ~= nil then item = ERUtil.findItemById(player, id) end
    if item ~= nil then
        local ft = ERCompat.get(item, "getFullType", nil)
        if ft ~= fullType then item = nil end
    end
    if item == nil then
        -- Try by type before giving up.
        local ok, inv = pcall(function() return player:getInventory() end)
        if ok and inv ~= nil then
            local shortType = string.match(fullType, "%.(.+)$") or fullType
            local ok2, found = pcall(function() return inv:getFirstTypeRecurse(shortType) end)
            if ok2 then item = found end
        end
    end
    if item ~= nil then
        local ok = pcall(function() player:getInventory():Remove(item) end)
        if ok then return true end
    end
    -- We could not find the item.
    --
    -- In single player (and on a listen host) the inventory in front of us is
    -- the real one, so "not found" means the player does not have it: refuse.
    --
    -- On a dedicated server the player's containers may not be fully replicated
    -- to us, and refusing would break a legitimate action, so we accept the
    -- client's claim. Rate limiting in the calling handler is the guard on that
    -- path, and it is the only place in this mod where a client is trusted about
    -- anything. See NOTES.md.
    if isServer() then return true end
    return false
end

-- ---------------------------------------------------------------------------
-- Perk grants (PLAN.md 6, tier 3 fallback for carry weight)
-- ---------------------------------------------------------------------------
-- Only ever called from server/SP code, never from a client, because changing
-- perk levels client-side is what trips PZ's anti-cheat (PLAN.md 9).
function ERServer.applyPerkGrants(player, d)
    if not ERBalance.PERK_GRANT.enabled then return end
    if not ERBalance.sv("AllowPerkGrants") then return end
    -- If the clean carry-weight API exists we never touch perks at all.
    if ERCompat.has(player, "setMaxWeightBase") then return end
    if not ERCompat.hasGlobal("Perks") then return end

    d = d or ERData.get(player)
    local str  = tonumber(d.stats.str) or 0
    local endr = tonumber(d.stats.endr) or 0
    local starting = ERBalance.svNum("StartingStat", 1, 99)

    local strPoints = math.max(0, ((str + endr) / 2) - starting)
    local wantStr = math.min(ERBalance.PERK_GRANT.maxStrength,
                             math.floor(strPoints / ERBalance.PERK_GRANT.strengthPerPoints))
    local wantFit = math.min(ERBalance.PERK_GRANT.maxFitness,
                             math.floor(math.max(0, endr - starting) / ERBalance.PERK_GRANT.fitnessPerPoints))

    ERServer.grantPerk(player, d, "Strength", wantStr)
    ERServer.grantPerk(player, d, "Fitness",  wantFit)
end

--- Move the granted level count for one perk to `want`, tracking exactly what we
-- gave so it can be revoked cleanly (PLAN.md 8 `grantedPerks`, PLAN.md 18).
function ERServer.grantPerk(player, d, perkName, want)
    local have = math.floor(tonumber(d.grantedPerks[perkName]) or 0)
    if have == want then return end
    local ok, perk = pcall(function() return Perks[perkName] end)
    if not ok or perk == nil then return end

    if want > have then
        for _ = have + 1, want do
            if not ERCompat.call(player, "LevelPerk", perk) then return end
        end
    else
        for _ = have, want + 1, -1 do
            -- Prefer an explicit un-level call; fall back to setting the level.
            if ERCompat.has(player, "LoseLevel") then
                ERCompat.call(player, "LoseLevel", perk)
            else
                local current = ERCompat.get(player, "getPerkLevel", nil)
                if current == nil then return end
                local lvl = player:getPerkLevel(perk)
                if not ERCompat.call(player, "setPerkLevel", perk, math.max(0, lvl - 1)) then return end
            end
        end
    end
    d.grantedPerks[perkName] = want
end

--- Give back every perk level this mod handed out. Called on respec and available
-- to server admins before uninstalling the mod (PLAN.md 18).
function ERServer.revokeAllPerks(player)
    local d = ERData.get(player)
    ERServer.grantPerk(player, d, "Strength", 0)
    ERServer.grantPerk(player, d, "Fitness", 0)
    ERData.transmit(player)
end

-- ---------------------------------------------------------------------------
-- Debug (PLAN.md 14). Refused unless the game is in debug mode, the sandbox
-- option is on, or the requester is a server admin.
-- ---------------------------------------------------------------------------
local function debugAllowed(player)
    local ok, dbg = ERCompat.callGlobal("getDebug")
    if ok and dbg == true then return true end
    if ERBalance.sv("DebugCommands") then return true end
    local access = ERCompat.get(player, "getAccessLevel", nil)
    if type(access) == "string" and access ~= "" and access ~= "None" then return true end
    return false
end

ERNet.handle("debug", function(player, args)
    if player == nil then return { ok = false, reason = "no_player" } end
    if not debugAllowed(player) then return { ok = false, reason = "debug_disabled" } end

    local action = args.action
    local d = ERData.get(player)

    if action == "give" then
        ERRunes.credit(player, math.floor(tonumber(args.amount) or 0), "debug")
    elseif action == "setStat" then
        local key = args.stat
        if ERBalance.STATS[key] ~= nil then
            d.stats[key] = ERUtil.clamp(math.floor(tonumber(args.value) or 1), 1,
                                        ERBalance.svNum("MaxStat", 10, 99))
            d.level = ERLevel.fromStats(d.stats)
            ERServer.applyPerkGrants(player, d)
        end
    elseif action == "setRunes" then
        d.heldRunes = math.max(0, math.floor(tonumber(args.amount) or 0))
    elseif action == "simulateDeath" then
        ERBloodstain.onDeath(player)
    elseif action == "revokePerks" then
        ERServer.revokeAllPerks(player)
    elseif action == "reset" then
        local starting = ERBalance.svNum("StartingStat", 1, 99)
        for i = 1, #ERBalance.STAT_ORDER do d.stats[ERBalance.STAT_ORDER[i]] = starting end
        d.heldRunes, d.totalSpent, d.totalEarned = 0, 0, 0
        d.level = 1
    else
        return { ok = false, reason = "unknown_debug_action" }
    end

    ERData.transmit(player)
    return ERServer.snapshot(player, { debug = action })
end)
