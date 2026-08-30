--[[
    ERStatRow.lua
    -------------
    One attribute row on the Runes tab (PLAN.md 7.2).

        VIGOR          14  > 15    ########........   +HP

    The row owns its hit-testing (click to select, wheel to stage) and reports the
    hovered stat to its owner so the owner can draw the tooltip on top.
]]

ERStatRow = ISPanel:derive("ERStatRow")

function ERStatRow:new(x, y, width, height, statKey, owner)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.statKey = statKey
    o.owner = owner
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.hovered = false
    return o
end

function ERStatRow:isSelected()
    return self.owner ~= nil and self.owner.selected == self.statKey
end

function ERStatRow:value()
    if self.owner == nil then return 0 end
    return tonumber((self.owner.snapshot.stats or {})[self.statKey]) or 0
end

function ERStatRow:staged()
    if self.owner == nil then return 0 end
    return math.floor(tonumber(self.owner.staged[self.statKey]) or 0)
end

function ERStatRow:onMouseDown(x, y)
    if self.owner == nil then return end
    self.owner:select(self.statKey)
    return true
end

function ERStatRow:onRightMouseDown(x, y)
    if self.owner == nil then return end
    self.owner:select(self.statKey)
    self.owner:stage(self.statKey, -1)
    return true
end

function ERStatRow:onMouseWheel(del)
    if self.owner == nil then return false end
    self.owner:select(self.statKey)
    self.owner:stage(self.statKey, del < 0 and 1 or -1)
    return true    -- consume, so the tab does not scroll under us
end

function ERStatRow:onMouseMove(dx, dy)
    self.hovered = true
    if self.owner then self.owner.hoveredStat = self.statKey end
end

function ERStatRow:onMouseMoveOutside(dx, dy)
    self.hovered = false
    if self.owner and self.owner.hoveredStat == self.statKey then
        self.owner.hoveredStat = nil
    end
end

--- Short right-hand tag naming this attribute's headline effect, shown only when
-- the attribute is above its starting value so a fresh sheet stays quiet.
ERStatRow.TAGS = {
    vig = "+HP", mnd = "+Calm", endr = "+Stam", str = "+Dmg",
    dex = "+Speed", int = "+XP", fth = "+Heal", arc = "+Runes",
}

function ERStatRow:render()
    local C = ERBalance.COLOR
    local def = ERBalance.STATS[self.statKey]
    if def == nil then return end

    local h = self.height
    local pad = 6
    local value = self:value()
    local staged = self:staged()
    local selected = self:isSelected()
    local textY = math.floor((h - ERUI.textHeight(ERUI.font("small"))) / 2)

    if selected then
        ERUI.rect(self, 0, 0, self.width, h, C.gold, 0.10)
        ERUI.rect(self, 0, 0, 2, h, C.gold, 0.9)
    elseif self.hovered then
        ERUI.rect(self, 0, 0, self.width, h, C.gold, 0.05)
    end

    -- Name
    local nameColour = selected and C.goldBright or C.text
    ERUI.text(self, string.upper(def.name), pad, textY, nameColour)

    -- Layout of the numeric columns, derived from the row width so the panel can
    -- be any size the character window gives it.
    local barW = math.max(60, math.min(ERBalance.UI.barWidth, math.floor(self.width * 0.38)))
    local tagW = 52
    local barX = self.width - barW - tagW - pad
    local valueRight = barX - 10

    -- Current value, and the staged preview "14 > 15"
    if staged > 0 then
        local preview = tostring(value + staged)
        local pw = ERUI.textWidth(ERUI.font("small"), preview)
        ERUI.text(self, preview, valueRight - pw, textY, C.staged)
        ERUI.textRight(self, tostring(value) .. "  >", valueRight - pw - 4, textY, C.textDim)
    else
        ERUI.textRight(self, tostring(value), valueRight, textY, C.text)
    end

    -- Bar
    local barY = math.floor((h - ERBalance.UI.barHeight) / 2)
    ERUI.statBar(self, barX, barY, barW, ERBalance.UI.barHeight,
                 value, staged > 0 and (value + staged) or nil,
                 ERBalance.svNum("MaxStat", 10, 99))

    -- Effect tag
    local starting = ERBalance.svNum("StartingStat", 1, 99)
    if value > starting then
        ERUI.text(self, ERStatRow.TAGS[self.statKey] or "", barX + barW + 8, textY, C.goldDim)
    end
end
