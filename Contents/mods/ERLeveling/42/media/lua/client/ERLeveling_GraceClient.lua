--[[
    ERLeveling_GraceClient.lua
    --------------------------
    Client-side cache and presentation for Grace state.

    ERGrace.check() walks up to 49 squares, so it is never called from a render
    path. It runs at most once per ERBalance.GRACE.recheckMs per player, from a
    throttled OnPlayerUpdate, and everything else reads the cache.
]]

ERGraceClient = ERGraceClient or {}
ERGraceClient._cache = ERGraceClient._cache or {}   -- playerNum -> { at, grace, reason }

local function cacheFor(playerNum)
    local n = playerNum or 0
    local c = ERGraceClient._cache[n]
    if c == nil then
        c = { at = 0, grace = false, reason = "none", enteredAt = 0 }
        ERGraceClient._cache[n] = c
    end
    return c
end

--- Recompute if the cache is stale. Cheap when it is not.
function ERGraceClient.refresh(playerNum, force)
    local c = cacheFor(playerNum)
    local now = ERUtil.nowMs()
    if not force and (now - c.at) < ERBalance.GRACE.recheckMs then return c end
    c.at = now
    local player = ERClient.player(playerNum)
    if player == nil then
        c.grace, c.reason = false, "none"
        return c
    end
    local ok, g, r = pcall(ERGrace.check, player)
    if not ok then
        c.grace, c.reason = false, "none"
        return c
    end
    g = (g == true)
    if g ~= c.grace then
        c.enteredAt = now
        if g then ERUI.playGraceSound() end
    end
    c.grace, c.reason = g, r
    return c
end

function ERGraceClient.isAtGrace(playerNum)
    return ERGraceClient.refresh(playerNum).grace == true
end

function ERGraceClient.reason(playerNum)
    return ERGraceClient.refresh(playerNum).reason or "none"
end

--- Human-readable label for the Runes tab header.
function ERGraceClient.headerText(playerNum)
    if ERGraceClient.isAtGrace(playerNum) then
        return getTextOr("IGUI_ERLeveling_AtGrace", "AT A SITE OF GRACE")
    end
    return getTextOr("IGUI_ERLeveling_AwayFromGrace", "AWAY FROM GRACE")
end

-- Throttled refresh so the header and glow are current without the UI having to
-- poll. OnPlayerUpdate fires constantly (PLAN.md 15.1), so this does nothing at
-- all on most ticks.
local tickCounter = 0
ERCompat.onEvent("OnPlayerUpdate", function(player)
    tickCounter = tickCounter + 1
    if tickCounter < 30 then return end
    tickCounter = 0
    if player == nil then return end
    local n = ERCompat.get(player, "getPlayerNum", 0)
    ERGraceClient.refresh(n)
end)
