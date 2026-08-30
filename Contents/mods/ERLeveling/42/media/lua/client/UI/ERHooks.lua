--[[
    ERHooks.lua
    -----------
    EVERY monkey-patch of vanilla code lives in this file and nowhere else
    (PLAN.md 12, "ERHooks.lua rule"). Each hook names the vanilla file and
    function it wraps and why. When a Project Zomboid update breaks this mod,
    this is the only file anyone needs to read.

    Pattern, without exception:
        vanilla first, then our work inside a pcall. A broken hook degrades to
        "no rune UI", never to "the health panel will not open".
]]

ERHooks = ERHooks or {}
ERHooks.windows = ERHooks.windows or {}     -- playerNum -> ISCharacterInfoWindow
ERHooks.installed = false

local function log(msg)
    print("[ERLeveling] " .. tostring(msg))
end

-- ===========================================================================
-- HOOK 1
-- vanilla: media/lua/client/ISUI/ISCharacterInfoWindow.lua :: createChildren
-- why:     add the "Runes" tab alongside Health / Info / Skills (PLAN.md 7.1 B)
-- ===========================================================================
function ERHooks.tabPanelOf(window)
    -- The vanilla window keeps its ISTabPanel in `self.panel`. Fall back to
    -- searching the children for anything that answers to addView, so a rename
    -- in a future build does not silently drop the tab.
    if window.panel ~= nil and type(window.panel.addView) == "function" then
        return window.panel
    end
    local kids = window:getChildren()
    if kids == nil then return nil end
    local ok, result = pcall(function()
        for _, child in pairs(kids) do
            if type(child) == "table" and type(child.addView) == "function" then
                return child
            end
        end
        return nil
    end)
    if ok then return result end
    return nil
end

function ERHooks.attachRunesTab(window)
    local tabs = ERHooks.tabPanelOf(window)
    if tabs == nil then
        log("character info window has no tab panel; the Runes tab is unavailable.")
        return
    end
    if window.ERLevelPanel ~= nil then return end

    local playerNum = window.playerNum
    if playerNum == nil and window.player ~= nil then
        playerNum = ERCompat.get(window.player, "getPlayerNum", 0)
    end
    playerNum = playerNum or 0

    local tabHeight = tabs.tabHeight or 20
    local w = math.max(240, tabs.width or window.width or 320)
    local h = math.max(200, (tabs.height or window.height or 400) - tabHeight)

    local panel = ERLevelPanel:new(0, 0, w, h, playerNum)
    panel:initialise()
    panel:instantiate()
    tabs:addView(getTextOr("IGUI_ERLeveling_TabName", "Runes"), panel)

    window.ERLevelPanel = panel
    ERHooks.windows[playerNum] = window
end

--- Open (or raise) the character window with the Runes tab selected.
-- Used by the keybind (PLAN.md 7.1).
function ERHooks.openRunesTab(playerNum)
    local window = ERHooks.windows[playerNum or 0]
    if window == nil then
        log("the character info window has not been created yet.")
        return false
    end
    local ok = pcall(function()
        if not window:getIsVisible() then
            window:setVisible(true)
            window:addToUIManager()
        end
        window:bringToTop()
        local tabs = ERHooks.tabPanelOf(window)
        if tabs ~= nil and window.ERLevelPanel ~= nil then
            if type(tabs.activateView) == "function" then
                tabs:activateView(getTextOr("IGUI_ERLeveling_TabName", "Runes"))
            end
        end
    end)
    return ok
end

--- Close the character window if it is open on the Runes tab; otherwise open it
-- there. Makes the keybind a toggle.
function ERHooks.toggleRunesTab(playerNum)
    local window = ERHooks.windows[playerNum or 0]
    if window ~= nil then
        local visible = false
        pcall(function() visible = window:getIsVisible() end)
        local onRunes = false
        pcall(function()
            local tabs = ERHooks.tabPanelOf(window)
            onRunes = tabs ~= nil and tabs.activeView ~= nil
                      and tabs.activeView.view == window.ERLevelPanel
        end)
        if visible and onRunes then
            pcall(function() window:setVisible(false); window:removeFromUIManager() end)
            return true
        end
    end
    return ERHooks.openRunesTab(playerNum)
end

-- ===========================================================================
-- HOOK 2 and 3
-- vanilla: media/lua/client/ISUI/ISHealthPanel.lua :: createChildren, render
-- why:     pin the rune counter strip to the bottom of the Health tab
--          (PLAN.md 7.1 A). We append a child and reposition it; the vanilla
--          layout is never touched.
-- ===========================================================================
function ERHooks.attachRuneStrip(healthPanel)
    if healthPanel.ERRuneStrip ~= nil then return end
    local playerNum = healthPanel.playerNum
    if playerNum == nil and healthPanel.character ~= nil then
        playerNum = ERCompat.get(healthPanel.character, "getPlayerNum", 0)
    end
    local strip = ERRuneStrip:new(healthPanel, playerNum or 0)
    strip:initialise()
    strip:instantiate()
    healthPanel:addChild(strip)
    healthPanel.ERRuneStrip = strip
end

function ERHooks.repositionRuneStrip(healthPanel)
    local strip = healthPanel.ERRuneStrip
    if strip == nil then return end
    strip:reposition()
    -- If the host scrolls its children, cancel the scroll so the strip stays
    -- pinned to the bottom edge of the visible area.
    if type(healthPanel.getYScroll) == "function" then
        local ok, scroll = pcall(function() return healthPanel:getYScroll() end)
        if ok and type(scroll) == "number" then
            strip:setY(strip:getY() - scroll)
        end
    end
end

-- ===========================================================================
-- Installation
-- ===========================================================================
local function wrap(class, methodName, after)
    if class == nil or type(class[methodName]) ~= "function" then return false end
    local original = class[methodName]
    class[methodName] = function(self, ...)
        local result = original(self, ...)
        -- Throttled: this runs inside render() for some hooks, so an unthrottled
        -- print here fills console.txt at frame rate (PLAN.md 15.1, 1.7).
        local ok, err = pcall(after, self)
        if not ok then
            ERCompat.throttledError("hook " .. methodName, err)
            ERUI.uiError("hook " .. methodName, err)
        end
        return result
    end
    return true
end

function ERHooks.install()
    if ERHooks.installed then return end
    ERUI.protectAll()

    local okWindow = false
    if _G["ISCharacterInfoWindow"] ~= nil then
        okWindow = wrap(ISCharacterInfoWindow, "createChildren", ERHooks.attachRunesTab)
    end
    if not okWindow then
        log("ISCharacterInfoWindow.createChildren not found; the Runes tab is unavailable "
            .. "(use the keybind's fallback window instead).")
    end

    local okHealth = false
    if _G["ISHealthPanel"] ~= nil then
        okHealth = wrap(ISHealthPanel, "createChildren", ERHooks.attachRuneStrip)
        if okHealth then
            wrap(ISHealthPanel, "render", ERHooks.repositionRuneStrip)
        end
    end
    if not okHealth then
        log("ISHealthPanel.createChildren not found; the rune strip is unavailable.")
    end

    ERHooks.installed = okWindow or okHealth
    if ERHooks.installed then log("UI hooks installed.") end
end

-- Vanilla client Lua is loaded before mod Lua, so this normally succeeds right
-- here. OnGameStart is a retry for builds that load the UI classes later.
ERHooks.install()
ERCompat.onEvent("OnGameStart", function()
    ERHooks.install()
    ERCompat.report()
end)
