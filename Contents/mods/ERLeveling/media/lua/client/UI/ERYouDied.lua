--[[
    ERYouDied.lua
    -------------
    The black fade and dim red "YOU DIED" (PLAN.md 7.4).

    Hard requirement: this must not interfere with the vanilla death flow. The
    element takes no mouse capture, consumes no events, and removes itself on a
    timer, so at worst it is a decoration the player looks through.
]]

ERYouDied = ERYouDied or {}
ERYouDied.element = nil

ERYouDiedPanel = ISUIElement:derive("ERYouDiedPanel")

function ERYouDiedPanel:new()
    local sw, sh = 800, 600
    pcall(function() sw = getCore():getScreenWidth(); sh = getCore():getScreenHeight() end)
    local o = ISUIElement:new(0, 0, sw, sh)
    setmetatable(o, self)
    self.__index = self
    o.startedAt = ERUtil.nowMs()
    o.dropped = 0
    return o
end

function ERYouDiedPanel:onResolutionChange(oldW, oldH, newW, newH)
    self:setWidth(newW)
    self:setHeight(newH)
end

-- Never take input away from the death screen underneath.
function ERYouDiedPanel:onMouseDown(x, y) return false end
function ERYouDiedPanel:onRightMouseDown(x, y) return false end
function ERYouDiedPanel:isMouseOver() return false end

function ERYouDiedPanel:render()
    local life = ERBalance.UI.youDiedMs
    local elapsed = ERUtil.nowMs() - self.startedAt
    if elapsed > life then
        ERYouDied.hide()
        return
    end

    local t = elapsed / life
    -- Fade in over the first 20%, hold, fade out over the last 35%.
    local alpha
    if t < 0.20 then alpha = t / 0.20
    elseif t < 0.65 then alpha = 1.0
    else alpha = 1.0 - ((t - 0.65) / 0.35) end
    alpha = ERUtil.clamp(alpha, 0, 1)

    self:drawRect(0, 0, self.width, self.height, alpha * 0.72, 0, 0, 0)

    local font = ERUI.font("big")
    local text = getTextOr("IGUI_ERLeveling_YouDied", "YOU DIED")
    local y = math.floor(self.height * 0.44)
    local c = ERBalance.COLOR.warn
    self:drawTextCentre(text, math.floor(self.width / 2), y, c.r, c.g, c.b, alpha, font)

    -- A thin rule above and below, ER's framing.
    local halfW = math.floor(self.width * 0.16)
    local cx = math.floor(self.width / 2)
    local lineY = y - 10
    self:drawRect(cx - halfW, lineY, halfW * 2, 1, alpha * 0.5, c.r, c.g, c.b)
    self:drawRect(cx - halfW, y + ERUI.textHeight(font) + 8, halfW * 2, 1, alpha * 0.5, c.r, c.g, c.b)

    if self.dropped and self.dropped > 0 then
        local lost = ERStats.comma(self.dropped) .. " "
                   .. getTextOr("IGUI_ERLeveling_RunesLost", "RUNES LOST")
        self:drawTextCentre(lost, cx, y + ERUI.textHeight(font) + 16,
                            ERBalance.COLOR.goldDim.r, ERBalance.COLOR.goldDim.g,
                            ERBalance.COLOR.goldDim.b, alpha, ERUI.font("small"))
    end
end

--- Show the overlay. `dropped` may be nil when the client does not know yet;
-- a later "died" reply fills it in.
function ERYouDied.show(dropped)
    if not ERBalance.sv("ShowYouDied") then return end
    if ERUI.disabled then return end
    local ok = pcall(function()
        if ERYouDied.element == nil then
            local e = ERYouDiedPanel:new()
            e:initialise()
            e:instantiate()
            e:setAlwaysOnTop(true)
            if e.setCapture then e:setCapture(false) end
            if e.setConsumeMouseEvents then e:setConsumeMouseEvents(false) end
            e:addToUIManager()
            ERYouDied.element = e
        end
        ERYouDied.element.startedAt = ERUtil.nowMs()
        if dropped ~= nil then ERYouDied.element.dropped = math.floor(dropped) end
    end)
    if not ok then ERYouDied.element = nil end
end

function ERYouDied.hide()
    if ERYouDied.element == nil then return end
    pcall(function() ERYouDied.element:removeFromUIManager() end)
    ERYouDied.element = nil
end

ERYouDied.destroy = ERYouDied.hide

-- Belt and braces: this is the only full-screen element the mod still creates,
-- and a full-screen element left in the UI manager is one that can swallow
-- clicks. If anything stops render() from reaching its own timeout - an error,
-- a load, a respawn - these take it out anyway.
ERCompat.onEvent("OnCreatePlayer", function()
    ERYouDied.hide()
end)
ERCompat.onEvent("OnGameStart", function()
    ERYouDied.hide()
end)
