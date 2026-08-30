--[[
    ERRuneStrip.lua
    ---------------
    The slim rune counter pinned to the bottom of the vanilla Health tab
    (PLAN.md 7.1 A).

        [rune]  4,217 RUNES            LV 12      AT A SITE OF GRACE

    It is a child of ISHealthPanel, added by ERHooks. It never touches the health
    panel's own layout; it only reads self.parent's size to pin itself.
]]

ERRuneStrip = ISPanel:derive("ERRuneStrip")

function ERRuneStrip:new(parent, playerNum)
    local h = ERBalance.UI.stripHeight
    local o = ISPanel:new(0, math.max(0, parent.height - h), parent.width, h)
    setmetatable(o, self)
    self.__index = self
    o.playerNum = playerNum or 0
    o.host = parent
    o.backgroundColor = { r = ERBalance.COLOR.bg.r, g = ERBalance.COLOR.bg.g,
                          b = ERBalance.COLOR.bg.b, a = 0.85 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    return o
end

--- Re-pin to the host panel. Called every render because the character window
-- is resizable.
--
-- The strip sits one text line ABOVE the bottom edge, not on it: the vanilla
-- health panel draws "Right click to show Treatment menu" along its last line,
-- and the first build of this strip landed straight on top of it, so the two
-- read as one garbled line. That line is left alone.
function ERRuneStrip:reposition()
    if self.host == nil then return end
    local h = ERBalance.UI.stripHeight
    local reserved = ERUI.textHeight(ERUI.font("small")) + 6   -- the vanilla hint line
    self:setWidth(self.host.width)
    self:setX(0)
    self:setY(math.max(0, self.host.height - h - reserved))
    self:setHeight(h)
end

function ERRuneStrip:render()
    local C = ERBalance.COLOR
    local snap = ERClient.snapshot(self.playerNum)
    local font = ERUI.font("small")
    local ty = math.floor((self.height - ERUI.textHeight(font)) / 2)

    -- Paint our own opaque ground first rather than relying on ISPanel's
    -- background having been drawn underneath: whatever the vanilla panel drew
    -- in this band must not show through our text.
    ERUI.rect(self, 0, 0, self.width, self.height, C.bgSolid, 0.96)

    -- Rules top and bottom, so the strip reads as its own band.
    ERUI.rect(self, 0, 0, self.width, 1, snap.grace and C.gold or C.goldDim, 0.6)
    ERUI.rect(self, 0, self.height - 1, self.width, 1, C.goldDim, 0.35)

    ERUI.runeIcon(self, 8, math.floor((self.height - 11) / 2), 11, 1.0)
    ERUI.text(self, ERStats.comma(snap.runes or 0), 26, ty, C.gold, 1.0, font)

    local runesLabel = getTextOr("IGUI_ERLeveling_Runes", "runes")
    local w = ERUI.textWidth(font, ERStats.comma(snap.runes or 0))
    ERUI.text(self, runesLabel, 26 + w + 5, ty, C.goldDim, 1.0, font)

    local lv = getTextOr("IGUI_ERLeveling_LevelShort", "LV") .. " " .. tostring(snap.level or 1)
    ERUI.textRight(self, lv, self.width - 8, ty, C.text, 1.0, font)

    if snap.grace then
        local lvW = ERUI.textWidth(font, lv)
        ERUI.textRight(self, getTextOr("IGUI_ERLeveling_GraceShort", "GRACE"),
                       self.width - 8 - lvW - 12, ty, C.gold, 1.0, font)
    end
end
