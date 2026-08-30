--[[
    ERLeveling_Keybinds.lua
    -----------------------
    The keybind that opens the Runes tab (PLAN.md 7.1, default P), and the
    keyboard handling for the panel itself.

    The binding is appended to the vanilla `keyBinding` table so it shows up in
    Options -> Key Bindings like any other. If that table is not there, we fall
    back to a fixed default key rather than losing the feature.
]]

ERKeys = ERKeys or {}
ERKeys.BINDING_NAME = "ERLeveling_OpenRunes"
ERKeys.DEFAULT_KEY = nil

local function defaultKey()
    if ERKeys.DEFAULT_KEY ~= nil then return ERKeys.DEFAULT_KEY end
    local ok, k = pcall(function() return Keyboard.KEY_P end)
    ERKeys.DEFAULT_KEY = (ok and k) or 25
    return ERKeys.DEFAULT_KEY
end

-- Register in Options -> Key Bindings.
do
    local ok = pcall(function()
        if _G["keyBinding"] == nil then return end
        table.insert(keyBinding, { value = "[Elden Ring Leveling]" })
        table.insert(keyBinding, { value = ERKeys.BINDING_NAME, key = defaultKey() })
    end)
    if not ok then
        print("[ERLeveling] could not register the keybind; using the default key.")
    end
end

--- The key currently bound to opening the Runes tab.
function ERKeys.openKey()
    local ok, k = pcall(function() return getCore():getKey(ERKeys.BINDING_NAME) end)
    if ok and type(k) == "number" and k > 0 then return k end
    return defaultKey()
end

--- Is a Runes panel on screen right now? Returns the panel, or nil.
function ERKeys.visiblePanel()
    for _, panel in pairs(ERLevelPanel.instances or {}) do
        local visible = false
        pcall(function() visible = panel:getIsVisible() end)
        if visible then return panel end
    end
    return nil
end

ERCompat.onEvent("OnKeyPressed", function(key)
    if key == ERKeys.openKey() then
        -- Prefer the real tab; fall back to the standalone window only if the
        -- character info window hook never ran.
        if not ERHooks.toggleRunesTab(0) then
            ERWindow.toggle(0)
        end
        return
    end

    local panel = ERKeys.visiblePanel()
    if panel == nil then return end
    pcall(function() panel:handleKey(key) end)
end)
