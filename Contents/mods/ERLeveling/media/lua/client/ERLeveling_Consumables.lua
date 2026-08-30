--[[
    ERLeveling_Consumables.lua
    --------------------------
    Context-menu handling for the rune items (PLAN.md 11) and the manual
    bloodstain reclaim option.

    The client removes the item from its own inventory for immediate feedback and
    then asks the server to credit the runes; the server does its own lookup first
    and only falls back to trusting the claim when it cannot see the item
    (see ERServer.consumeItem). Every consuming command is rate limited.
]]

ERConsumables = ERConsumables or {}

local function unwrap(entry)
    if entry == nil then return nil end
    local ok, isItem = pcall(function() return instanceof(entry, "InventoryItem") end)
    if ok and isItem then return entry end
    if type(entry) == "table" and type(entry.items) == "table" and entry.items[1] ~= nil then
        return entry.items[1]
    end
    return nil
end

local function removeLocally(playerNum, item)
    local p = ERClient.player(playerNum)
    if p == nil or item == nil then return end
    pcall(function() p:getInventory():Remove(item) end)
end

function ERConsumables.absorb(playerNum, item)
    if item == nil then return end
    local fullType = ERCompat.get(item, "getFullType", nil)
    if ERBalance.RUNE_ITEMS[fullType] == nil then return end
    local id = ERCompat.get(item, "getID", nil)
    removeLocally(playerNum, item)
    local p = ERClient.player(playerNum)
    if p == nil then return end
    ERNet.request(p, "consumeRune", { fullType = fullType, id = id })
end

function ERConsumables.respec(playerNum, item)
    local p = ERClient.player(playerNum)
    if p == nil then return end
    local id = item and ERCompat.get(item, "getID", nil) or nil

    local function confirmed(_, button)
        if button.internal ~= "YES" then return end
        if item ~= nil then removeLocally(playerNum, item) end
        ERClient.requestRespec(playerNum, id)
    end

    local snap = ERClient.snapshot(playerNum)
    local text = getTextOr("IGUI_ERLeveling_RespecConfirm",
        "Return to the larval state? Every attribute resets and ")
        .. ERStats.comma(snap.totalSpent or 0) .. " "
        .. getTextOr("IGUI_ERLeveling_RunesReturned", "runes are returned to you.")

    local ok = pcall(function()
        local modal = ISModalDialog:new(0, 0, 340, 140, text, true, nil, confirmed, playerNum)
        modal:initialise()
        modal:instantiate()
        modal:addToUIManager()
    end)
    if not ok then
        -- No modal API: just do it rather than losing the feature.
        if item ~= nil then removeLocally(playerNum, item) end
        ERClient.requestRespec(playerNum, id)
    end
end

-- ---------------------------------------------------------------------------
-- Inventory context menu
-- ---------------------------------------------------------------------------
ERCompat.onEvent("OnFillInventoryObjectContextMenu", function(playerNum, context, items)
    if context == nil or items == nil then return end
    for i = 1, #items do
        local item = unwrap(items[i])
        if item ~= nil then
            local fullType = ERCompat.get(item, "getFullType", nil)
            if ERBalance.RUNE_ITEMS[fullType] ~= nil then
                local valueKey = ERBalance.RUNE_ITEMS[fullType]
                local amount = math.floor(ERBalance.RUNES[valueKey] or 0)
                local label = getTextOr("ContextMenu_ERLeveling_Absorb", "Absorb Runes")
                          .. "  (" .. ERStats.comma(amount) .. ")"
                context:addOption(label, playerNum, function(pn)
                    ERConsumables.absorb(pn, item)
                end)
                return
            elseif fullType == ERBalance.RESPEC_ITEM then
                if ERBalance.sv("AllowRespec") ~= ERBalance.RESPEC.NEVER then
                    context:addOption(getTextOr("ContextMenu_ERLeveling_Respec", "Rebirth"),
                        playerNum, function(pn) ERConsumables.respec(pn, item) end)
                end
                return
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- World context menu: manual bloodstain reclaim
-- ---------------------------------------------------------------------------
ERCompat.onEvent("OnFillWorldObjectContextMenu", function(playerNum, context, worldobjects, test)
    if test == true then return end
    if context == nil then return end
    local p = ERClient.player(playerNum)
    if p == nil then return end
    local rec = ERClient.bloodstain(p)
    if rec == nil then return end

    local px = ERCompat.get(p, "getX", 0)
    local py = ERCompat.get(p, "getY", 0)
    if ERUtil.dist2D(px, py, rec.x + 0.5, rec.y + 0.5) > (ERBalance.BLOODSTAIN.reclaimRadius + 2) then
        return
    end
    context:addOption(getTextOr("ContextMenu_ERLeveling_Reclaim", "Reclaim Runes")
                      .. "  (" .. ERStats.comma(rec.runes or 0) .. ")",
                      playerNum, function(pn) ERClient.requestReclaim(pn) end)
end)

-- ---------------------------------------------------------------------------
-- Forging a Grace Idol
-- ---------------------------------------------------------------------------
-- Implemented in Lua rather than as a script recipe on purpose: Build 41 and
-- Build 42 use different recipe formats, and a recipe the running build cannot
-- parse spams the console. This works identically on both.
ERConsumables.IDOL_RECIPE = {
    base   = { "Pipe", "MetalBar", "MetalPipe" },   -- any one of these
    extra  = { "Candle", "Sheet" },                 -- all of these
    perk   = "MetalWelding",
    level  = 2,
}

local function firstOfType(inv, types)
    for i = 1, #types do
        local ok, item = pcall(function() return inv:getFirstTypeRecurse(types[i]) end)
        if ok and item ~= nil then return item end
    end
    return nil
end

function ERConsumables.canForgeIdol(player)
    if player == nil then return false end
    local ok, inv = pcall(function() return player:getInventory() end)
    if not ok or inv == nil then return false end

    if firstOfType(inv, ERConsumables.IDOL_RECIPE.base) == nil then return false end
    for i = 1, #ERConsumables.IDOL_RECIPE.extra do
        if firstOfType(inv, { ERConsumables.IDOL_RECIPE.extra[i] }) == nil then return false end
    end

    if ERCompat.hasGlobal("Perks") then
        local okP, perk = pcall(function() return Perks[ERConsumables.IDOL_RECIPE.perk] end)
        if okP and perk ~= nil then
            local level = ERCompat.get(player, "getPerkLevel", nil)
            if level ~= nil then
                local okL, lvl = pcall(function() return player:getPerkLevel(perk) end)
                if okL and type(lvl) == "number" and lvl < ERConsumables.IDOL_RECIPE.level then
                    return false
                end
            end
        end
    end
    return true
end

function ERConsumables.forgeIdol(playerNum)
    local p = ERClient.player(playerNum)
    if p == nil or not ERConsumables.canForgeIdol(p) then return end
    local ok, inv = pcall(function() return p:getInventory() end)
    if not ok or inv == nil then return end

    local consumed = {}
    local base = firstOfType(inv, ERConsumables.IDOL_RECIPE.base)
    if base ~= nil then table.insert(consumed, base) end
    for i = 1, #ERConsumables.IDOL_RECIPE.extra do
        local it = firstOfType(inv, { ERConsumables.IDOL_RECIPE.extra[i] })
        if it ~= nil then table.insert(consumed, it) end
    end
    if #consumed < 3 then return end

    for i = 1, #consumed do
        pcall(function() inv:Remove(consumed[i]) end)
    end
    pcall(function() inv:AddItem(ERBalance.GRACE_ITEM) end)
end

ERCompat.onEvent("OnFillInventoryObjectContextMenu", function(playerNum, context, items)
    if context == nil then return end
    local p = ERClient.player(playerNum)
    if p == nil or not ERConsumables.canForgeIdol(p) then return end
    context:addOption(getTextOr("ContextMenu_ERLeveling_Forge", "Forge Grace Idol"),
                      playerNum, function(pn) ERConsumables.forgeIdol(pn) end)
end)
