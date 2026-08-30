--[[
    ERRunePopup.lua
    ---------------
    The floating "+8" that rises and fades bottom-right on a rune gain
    (PLAN.md 7.4), plus the optional persistent HUD counter.

    Gains inside ERBalance.UI.popupCoalesceMs merge into a single popup whose
    number ticks up, so a horde does not spray forty overlapping labels.
]]

ERRunePopup = ERRunePopup or {}
ERRunePopup._amount = 0
ERRunePopup._shownAmount = 0
ERRunePopup._startedAt = 0
ERRunePopup._lastPushAt = 0
ERRunePopup._reclaim = false
ERRunePopup.element = nil

--- Queue a gain for display.
function ERRunePopup.push(amount, isReclaim)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    local now = ERUtil.nowMs()
    if (now - ERRunePopup._lastPushAt) > ERBalance.UI.popupCoalesceMs then
        ERRunePopup._amount = 0
        ERRunePopup._shownAmount = 0
        ERRunePopup._startedAt = now
        ERRunePopup._reclaim = false
    end
    ERRunePopup._amount = ERRunePopup._amount + amount
    ERRunePopup._lastPushAt = now
    ERRunePopup._startedAt = now
    if isReclaim then ERRunePopup._reclaim = true end
    ERRunePopup.setAdded(true)
end

-- ---------------------------------------------------------------------------
-- The overlay element
-- ---------------------------------------------------------------------------
ERRuneHud = ISUIElement:derive("ERRuneHud")

function ERRuneHud:new()
    local w, h = 220, 60
    local sw, sh = 800, 600
    pcall(function() sw = getCore():getScreenWidth(); sh = getCore():getScreenHeight() end)
    local o = ISUIElement:new(sw - w - 24, sh - h - 120, w, h)
    setmetatable(o, self)
    self.__index = self
    return o
end

function ERRuneHud:onResolutionChange(oldW, oldH, newW, newH)
    self:setX(newW - self.width - 24)
    self:setY(newH - self.height - 120)
end

function ERRuneHud:onMouseDown(x, y) return false end
function ERRuneHud:onRightMouseDown(x, y) return false end
function ERRuneHud:onMouseUp(x, y) return false end

function ERRuneHud:render()
    local C = ERBalance.COLOR
    local font = ERUI.font("medium")
    local now = ERUtil.nowMs()

    -- Persistent counter (sandbox, default off - PZ's HUD is crowded enough).
    if ERBalance.sv("ShowHudCounter") then
        local snap = ERClient.snapshot(0)
        local text = ERStats.comma(snap.runes or 0)
        local w = ERUI.textWidth(ERUI.font("small"), text)
        ERUI.runeIcon(self, self.width - w - 30, self.height - 14, 10, 0.85)
        ERUI.text(self, text, self.width - w, self.height - 14, C.gold, 0.85, ERUI.font("small"))
    end

    if ERRunePopup._amount <= 0 then return end

    local elapsed = now - ERRunePopup._startedAt
    local life = ERBalance.UI.popupFadeMs
    if elapsed > life then
        ERRunePopup._amount = 0
        ERRunePopup._shownAmount = 0
        return
    end

    -- Tick the displayed number up towards the real total.
    if ERRunePopup._shownAmount < ERRunePopup._amount then
        local step = math.max(1, math.ceil((ERRunePopup._amount - ERRunePopup._shownAmount) * 0.25))
        ERRunePopup._shownAmount = math.min(ERRunePopup._amount, ERRunePopup._shownAmount + step)
    end

    local t = elapsed / life
    local alpha = 1.0 - (t * t)                 -- hold, then fall away
    local rise = math.floor(t * 18)
    local text = "+" .. ERStats.comma(ERRunePopup._shownAmount)
    local colour = ERRunePopup._reclaim and C.goldBright or C.gold

    -- Shadow first, so it stays readable over a bright world.
    ERUI.text(self, text, 1, self.height - 30 - rise + 1, C.black, alpha * 0.7, font)
    ERUI.text(self, text, 0, self.height - 30 - rise, colour, alpha, font)
    if ERRunePopup._reclaim then
        ERUI.text(self, getTextOr("IGUI_ERLeveling_Reclaimed", "RUNES RECLAIMED"),
                  0, self.height - 30 - rise + ERUI.textHeight(font),
                  C.goldDim, alpha, ERUI.font("small"))
    end
end

-- Lifecycle. Like the bloodstain marker, this element is only in the UI manager
-- while it has something to draw: a live popup, or the optional HUD counter. An
-- element sitting permanently in the UI manager is an element that can swallow
-- clicks, and this one lives in the bottom-right corner where the vanilla HUD is.
ERRunePopup._added = false

function ERRunePopup.setAdded(wanted)
    if ERUI.disabled then wanted = false end
    if wanted == ERRunePopup._added then return end
    local el = ERRunePopup.element
    if el == nil then return end
    if wanted then
        pcall(function() el:addToUIManager() end)
    else
        pcall(function() el:removeFromUIManager() end)
    end
    ERRunePopup._added = wanted
end

--- True when there is a reason to be on screen at all.
function ERRunePopup.wanted()
    if ERBalance.sv("ShowHudCounter") then return true end
    if ERRunePopup._amount > 0
       and (ERUtil.nowMs() - ERRunePopup._startedAt) < ERBalance.UI.popupFadeMs then
        return true
    end
    return false
end

function ERRunePopup.create()
    if ERRunePopup.element ~= nil then return end
    local ok, el = pcall(function()
        local e = ERRuneHud:new()
        e:initialise()
        e:instantiate()
        e:setAlwaysOnTop(false)
        -- Purely decorative: must never take the mouse away from the game.
        if e.setCapture then pcall(function() e:setCapture(false) end) end
        if e.setConsumeMouseEvents then pcall(function() e:setConsumeMouseEvents(false) end) end
        return e
    end)
    if ok then ERRunePopup.element = el end
end

function ERRunePopup.destroy()
    ERRunePopup.setAdded(false)
    ERRunePopup.element = nil
end

ERCompat.onEvent("OnGameStart", function()
    ERRunePopup.create()
    ERRunePopup.setAdded(ERRunePopup.wanted())
end)

-- Cheap: a boolean compare a few times a second, and add/remove only on change.
local popupTick = 0
ERCompat.onEvent("OnPlayerUpdate", function(player)
    popupTick = popupTick + 1
    if popupTick < 15 then return end
    popupTick = 0
    ERRunePopup.setAdded(ERRunePopup.wanted())
end)
