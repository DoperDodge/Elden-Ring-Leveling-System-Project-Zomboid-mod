--[[
    ERWindow.lua
    ------------
    A standalone window holding the Runes panel.

    This exists so the mod stays usable if HOOK 1 in ERHooks.lua ever fails - a
    renamed character-info window in a future build would otherwise leave the
    level-up interface unreachable. When the tab is present this window is never
    created; the keybind prefers the tab.
]]

local Base = _G["ISCollapsableWindow"] or _G["ISPanel"]
if Base == nil then
    -- Neither base class exists on this build. Leave ERWindow.toggle as a no-op
    -- so the keybind still degrades gracefully instead of erroring.
    ERWindow = { instances = {}, toggle = function() return false end }
    return
end
ERWindow = Base:derive("ERWindow")
ERWindow.instances = ERWindow.instances or {}

function ERWindow:new(x, y, width, height, playerNum)
    local o = Base:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.playerNum = playerNum or 0
    o.backgroundColor = ERBalance.COLOR.bg
    o.borderColor = { r = ERBalance.COLOR.goldDim.r, g = ERBalance.COLOR.goldDim.g,
                      b = ERBalance.COLOR.goldDim.b, a = 0.8 }
    o.title = getTextOr("IGUI_ERLeveling_TabName", "Runes")
    o.resizable = true
    return o
end

function ERWindow:createChildren()
    Base.createChildren(self)
    local top = 0
    if type(self.titleBarHeight) == "number" then top = self.titleBarHeight end
    local panel = ERLevelPanel:new(0, top, self.width, self.height - top, self.playerNum)
    panel:initialise()
    panel:instantiate()
    self:addChild(panel)
    self.panelChild = panel
end

function ERWindow:onResize()
    if Base.onResize then pcall(function() Base.onResize(self) end) end
    if self.panelChild then
        local top = self.panelChild:getY()
        self.panelChild:setWidth(self.width)
        self.panelChild:setHeight(self.height - top)
    end
end

--- Show, creating on first use.
function ERWindow.toggle(playerNum)
    local n = playerNum or 0
    local win = ERWindow.instances[n]
    if win ~= nil then
        local visible = false
        pcall(function() visible = win:getIsVisible() end)
        if visible then
            pcall(function() win:setVisible(false); win:removeFromUIManager() end)
        else
            pcall(function() win:setVisible(true); win:addToUIManager(); win:bringToTop() end)
        end
        return true
    end
    local ok = pcall(function()
        local sw, sh = 800, 600
        pcall(function() sw = getCore():getScreenWidth(); sh = getCore():getScreenHeight() end)
        local w, h = 380, 460
        local e = ERWindow:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h, n)
        e:initialise()
        e:instantiate()
        e:addToUIManager()
        ERWindow.instances[n] = e
    end)
    return ok
end
