--[[
    ERLevelPanel.lua
    ----------------
    The Runes tab: the full level-up interface (PLAN.md 7.2).

    Nothing here mutates a rune balance or a stat. Points are *staged* locally for
    instant feedback, the commit is a request, and the panel repaints from the
    authoritative reply (PLAN.md 9, step 1 and step 5).

    All layout is derived from self.width / self.height, because the character
    info window can be resized and we do not know its dimensions up front
    (PLAN.md 2.3).
]]

ERLevelPanel = ISPanel:derive("ERLevelPanel")
ERLevelPanel.instances = ERLevelPanel.instances or {}

local BTN_H = 22

function ERLevelPanel:new(x, y, width, height, playerNum)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.playerNum = playerNum or 0
    o.staged = {}
    o.selected = ERBalance.STAT_ORDER[1]
    o.hoveredStat = nil
    o.rows = {}
    o.message = nil
    o.messageAt = 0
    o.messageOk = false
    o.snapshot = ERClient.snapshot(o.playerNum)
    o.backgroundColor = ERBalance.COLOR.bg
    o.borderColor = { r = ERBalance.COLOR.goldDim.r, g = ERBalance.COLOR.goldDim.g,
                      b = ERBalance.COLOR.goldDim.b, a = 0.55 }
    o.moveWithMouse = false
    ERLevelPanel.instances[o.playerNum] = o
    return o
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
function ERLevelPanel:metrics()
    local pad = ERBalance.UI.padding
    local m = {}
    m.pad = pad
    m.innerW = self.width - pad * 2
    m.headerY = pad
    m.headerH = ERUI.textHeight(ERUI.font("big")) + ERUI.textHeight(ERUI.font("small")) * 2 + 12
    m.graceY = m.headerY + m.headerH + 8
    m.rowsY = m.graceY + 12
    m.rowH = ERBalance.UI.rowHeight
    m.rowsH = m.rowH * #ERBalance.STAT_ORDER
    m.derivedY = m.rowsY + m.rowsH + 12
    m.derivedRowH = ERUI.textHeight(ERUI.font("small")) + 4
    m.derivedH = m.derivedRowH * 3 + 8
    m.buttonsY = m.derivedY + m.derivedH + 10
    m.bloodY = m.buttonsY + BTN_H + 12
    m.contentH = m.bloodY + ERUI.textHeight(ERUI.font("small")) + pad
    return m
end

function ERLevelPanel:createChildren()
    ISPanel.createChildren(self)
    local m = self:metrics()

    for i = 1, #ERBalance.STAT_ORDER do
        local key = ERBalance.STAT_ORDER[i]
        local row = ERStatRow:new(m.pad, m.rowsY + (i - 1) * m.rowH, m.innerW, m.rowH, key, self)
        row:initialise()
        self:addChild(row)
        self.rows[i] = row
    end

    local function mkButton(x, w, label, internal)
        local b = ISButton:new(x, m.buttonsY, w, BTN_H, label, self, ERLevelPanel.onButton)
        b.internal = internal
        b:initialise()
        b:instantiate()
        b.borderColor = { r = ERBalance.COLOR.goldDim.r, g = ERBalance.COLOR.goldDim.g,
                          b = ERBalance.COLOR.goldDim.b, a = 0.8 }
        b.backgroundColor = { r = 0.06, g = 0.055, b = 0.05, a = 0.9 }
        b.backgroundColorMouseOver = { r = ERBalance.COLOR.gold.r * 0.35,
                                       g = ERBalance.COLOR.gold.g * 0.35,
                                       b = ERBalance.COLOR.gold.b * 0.35, a = 0.95 }
        self:addChild(b)
        return b
    end

    local smallW = 26
    self.btnMinus  = mkButton(m.pad, smallW, "-", "MINUS")
    self.btnPlus   = mkButton(m.pad + smallW + 4, smallW, "+", "PLUS")
    local restX    = m.pad + (smallW + 4) * 2 + 6
    local restW    = math.max(60, math.floor((self.width - m.pad - restX - 6) / 2))
    self.btnLevel  = mkButton(restX, restW, getTextOr("IGUI_ERLeveling_LevelUp", "LEVEL UP"), "LEVELUP")
    self.btnReset  = mkButton(restX + restW + 6, restW, getTextOr("IGUI_ERLeveling_Reset", "RESET"), "RESET")

    -- Drawn last so it paints above the rows (PZ renders children in add order).
    self.tooltipLayer = ERTooltipLayer:new(0, 0, self.width, self.height, self)
    self.tooltipLayer:initialise()
    self:addChild(self.tooltipLayer)

    -- Scrolling, when this build's ISPanel supports it. Without it the content
    -- simply clips, which is why the layout is kept compact.
    if type(self.setScrollChildren) == "function" then
        pcall(function()
            self:setScrollChildren(true)
            self:addScrollBars()
        end)
    end
    self:relayout()
end

--- Re-run the layout after a resize.
function ERLevelPanel:relayout()
    local m = self:metrics()
    for i = 1, #self.rows do
        local row = self.rows[i]
        row:setX(m.pad)
        row:setY(m.rowsY + (i - 1) * m.rowH)
        row:setWidth(m.innerW)
        row:setHeight(m.rowH)
    end
    local smallW = 26
    if self.btnMinus then
        self.btnMinus:setY(m.buttonsY); self.btnMinus:setX(m.pad)
        self.btnPlus:setY(m.buttonsY);  self.btnPlus:setX(m.pad + smallW + 4)
        local restX = m.pad + (smallW + 4) * 2 + 6
        local restW = math.max(60, math.floor((self.width - m.pad - restX - 6) / 2))
        self.btnLevel:setY(m.buttonsY); self.btnLevel:setX(restX);              self.btnLevel:setWidth(restW)
        self.btnReset:setY(m.buttonsY); self.btnReset:setX(restX + restW + 6);  self.btnReset:setWidth(restW)
    end
    if self.tooltipLayer then
        self.tooltipLayer:setWidth(self.width)
        self.tooltipLayer:setHeight(self.height)
    end
    if type(self.setScrollHeight) == "function" then
        pcall(function() self:setScrollHeight(m.contentH) end)
    end
    self._lastWidth, self._lastHeight = self.width, self.height
end

-- ---------------------------------------------------------------------------
-- Staging
-- ---------------------------------------------------------------------------
function ERLevelPanel:select(key)
    self.selected = key
end

function ERLevelPanel:stagedPoints()
    local n = 0
    for _, v in pairs(self.staged) do n = n + (tonumber(v) or 0) end
    return n
end

function ERLevelPanel:stagedCost()
    return ERLevel.totalCost(self.snapshot.level or 1, self:stagedPoints())
end

--- Move a stat's staged points by `delta`, respecting MaxStat and the balance.
function ERLevelPanel:stage(key, delta)
    if key == nil then return end
    local current = math.floor(tonumber(self.staged[key]) or 0)
    local target = current + delta
    if target < 0 then target = 0 end

    local base = tonumber(self.snapshot.stats[key]) or 0
    local maxStat = ERBalance.svNum("MaxStat", 10, 99)
    if base + target > maxStat then
        target = math.max(0, maxStat - base)
        self:say(getTextOr("IGUI_ERLeveling_AtMax", "That attribute is at its limit."), false)
    end

    if target > current then
        -- Only stage what the player can actually pay for.
        local trial = {}
        for k, v in pairs(self.staged) do trial[k] = v end
        trial[key] = target
        local points = 0
        for _, v in pairs(trial) do points = points + v end
        local cost = ERLevel.totalCost(self.snapshot.level or 1, points)
        if cost > (self.snapshot.runes or 0) then
            self:say(getTextOr("IGUI_ERLeveling_NotEnough", "Not enough runes."), false)
            return
        end
    end

    self.staged[key] = target > 0 and target or nil
end

function ERLevelPanel:clearStaging()
    self.staged = {}
end

function ERLevelPanel:say(text, ok)
    self.message = text
    self.messageOk = ok and true or false
    self.messageAt = ERUtil.nowMs()
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------
function ERLevelPanel:onButton(button)
    local internal = button.internal
    if internal == "PLUS" then
        self:stage(self.selected, 1)
    elseif internal == "MINUS" then
        self:stage(self.selected, -1)
    elseif internal == "RESET" then
        self:clearStaging()
    elseif internal == "LEVELUP" then
        self:commit()
    end
end

function ERLevelPanel:canCommit()
    if self:stagedPoints() <= 0 then return false, "no_points" end
    if self:stagedCost() > (self.snapshot.runes or 0) then return false, "insufficient" end
    if ERBalance.sv("RequireGrace") and not self.snapshot.grace then return false, "no_grace" end
    return true
end

function ERLevelPanel:commit()
    local ok, reason = self:canCommit()
    if not ok then
        self:say(ERClient.ERRORS[reason] or "", false)
        return
    end
    local deltas = {}
    for k, v in pairs(self.staged) do deltas[k] = v end
    self._pending = deltas
    ERClient.requestLevelUp(self.playerNum, deltas, self:stagedCost())
end

--- Called from ERClient when the authoritative reply lands.
function ERLevelPanel.onServerReply(ok, message, args)
    for _, panel in pairs(ERLevelPanel.instances) do
        if panel ~= nil then
            if ok then
                panel:clearStaging()
                panel._pending = nil
                panel.snapshot = ERClient.snapshot(panel.playerNum)
                if args and args.spent then
                    panel:say(getTextOr("IGUI_ERLeveling_Spent", "Spent") .. " "
                              .. ERStats.comma(args.spent) .. " "
                              .. getTextOr("IGUI_ERLeveling_Runes", "runes"), true)
                elseif args and args.refunded then
                    panel:say(getTextOr("IGUI_ERLeveling_Refunded", "Refunded") .. " "
                              .. ERStats.comma(args.refunded), true)
                end
            else
                panel._pending = nil
                panel:say(message, false)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------
function ERLevelPanel:prerender()
    -- Refresh cheaply: modData reads are local, and Grace comes from a cache.
    self.snapshot = ERClient.snapshot(self.playerNum)

    if self._lastWidth ~= self.width or self._lastHeight ~= self.height then
        self:relayout()
    end

    ISPanel.prerender(self)

    local flash = ERUI.flashAlpha()
    if flash > 0 then
        ERUI.rect(self, 0, 0, self.width, self.height, ERBalance.COLOR.gold, flash)
    end

    -- Soft gold wash at a Site of Grace.
    if self.snapshot.grace then
        ERUI.graceWash(self, self.width, self.height)
    end

    if self.btnLevel then
        local can = self:canCommit()
        pcall(function() self.btnLevel:setEnable(can) end)
    end
end

function ERLevelPanel:render()
    local C = ERBalance.COLOR
    local m = self:metrics()
    local snap = self.snapshot
    local fSmall, fBig = ERUI.font("small"), ERUI.font("big")
    local lineH = ERUI.textHeight(fSmall)

    -- --- Header -----------------------------------------------------------
    local y = m.headerY
    ERUI.runeIcon(self, m.pad, y + 2, 12, 1.0)
    ERUI.text(self, getTextOr("IGUI_ERLeveling_Level", "LEVEL"), m.pad + 20, y, C.gold, 1.0, fSmall)
    ERUI.textRight(self, tostring(snap.level or 1), self.width - m.pad, y - 4, C.goldBright, 1.0, fBig)

    y = y + math.max(lineH, ERUI.textHeight(fBig)) + 2
    ERUI.text(self, getTextOr("IGUI_ERLeveling_RunesHeld", "RUNES HELD"), m.pad + 20, y, C.textDim)
    ERUI.textRight(self, ERStats.comma(snap.runes or 0), self.width - m.pad, y, C.gold)

    y = y + lineH + 2
    local points = self:stagedPoints()
    local needed = self:stagedCost()
    local nextCost = ERLevel.cost(snap.level or 1)
    local label = points > 0
        and (getTextOr("IGUI_ERLeveling_RunesNeeded", "RUNES NEEDED") .. "  (+" .. points .. ")")
        or getTextOr("IGUI_ERLeveling_NextLevel", "NEXT LEVEL")
    local shown = points > 0 and needed or nextCost
    local colour = (shown > (snap.runes or 0)) and C.warn or C.text
    ERUI.text(self, label, m.pad + 20, y, C.textDim)
    ERUI.textRight(self, ERStats.comma(shown), self.width - m.pad, y, colour)

    -- --- Grace divider ----------------------------------------------------
    ERUI.divider(self, m.pad, m.graceY, m.innerW, ERGraceClient.headerText(self.playerNum),
                 snap.grace == true)

    -- --- Derived ----------------------------------------------------------
    local d = self:previewDerived()
    ERUI.divider(self, m.pad, m.derivedY, m.innerW, getTextOr("IGUI_ERLeveling_Derived", "DERIVED"), false)

    local colW = math.floor(m.innerW / 2)
    local dy = m.derivedY + 8
    local function pair(col, rowIdx, name, value)
        local x = m.pad + (col * colW)
        local yy = dy + rowIdx * m.derivedRowH
        ERUI.text(self, name, x, yy, C.textDim)
        ERUI.textRight(self, value, x + colW - 8, yy, C.text)
    end
    pair(0, 0, getTextOr("IGUI_ERLeveling_DmgNeg", "Damage Negation"), ERStats.pct(d.damageNegation))
    pair(1, 0, getTextOr("IGUI_ERLeveling_Carry", "Carry Weight"), string.format("+%.1f", d.carryWeight))
    pair(0, 1, getTextOr("IGUI_ERLeveling_Stam", "Stamina Drain"), ERStats.signedPct(-d.staminaDrain, 0))
    pair(1, 1, getTextOr("IGUI_ERLeveling_Melee", "Melee Damage"), ERStats.signedPct(d.meleeDamage, 0))
    pair(0, 2, getTextOr("IGUI_ERLeveling_RuneFind", "Rune Find"), ERStats.signedPct(d.runeFind, 0))
    pair(1, 2, getTextOr("IGUI_ERLeveling_Healing", "Healing"), ERStats.signedPct(d.healingPower, 0))

    -- --- Bloodstain / message --------------------------------------------
    local by = m.bloodY
    if self.message and (ERUtil.nowMs() - self.messageAt) < 4000 then
        ERUI.text(self, self.message, m.pad, by, self.messageOk and C.staged or C.warn)
    else
        local line = self:bloodstainLine()
        if line then
            ERUI.text(self, line, m.pad, by, C.warn)
        elseif not snap.grace and ERBalance.sv("RequireGrace") then
            ERUI.text(self, getTextOr("IGUI_ERLeveling_NeedGraceHint",
                "Rest at a lit campfire, fireplace or Grace Idol to level up."), m.pad, by, C.textDim)
        end
    end
end

--- Stats including staged points, so the DERIVED block previews the purchase.
function ERLevelPanel:previewStats()
    local out = ERUtil.copyStats(self.snapshot.stats)
    for k, v in pairs(self.staged) do
        out[k] = (out[k] or 0) + v
    end
    return out
end

--- Derived values for the previewed stats, cached.
-- render() runs every frame; recomputing this would allocate two tables per
-- frame for numbers that only move when the player stages a point
-- (PLAN.md 15.1).
function ERLevelPanel:previewDerived()
    local hash = 0
    for i = 1, #ERBalance.STAT_ORDER do
        local k = ERBalance.STAT_ORDER[i]
        hash = hash * 211
              + (tonumber(self.snapshot.stats[k]) or 0)
              + (tonumber(self.staged[k]) or 0) * 100
    end
    if self._derivedHash ~= hash then
        self._derivedHash = hash
        self._derived = ERStats.derived(self:previewStats())
    end
    return self._derived
end

--- "Bloodstain: 412 tiles NE - 4,900 runes", or nil when there is none.
function ERLevelPanel:bloodstainLine()
    local rec = self.snapshot.bloodstain
    if rec == nil then return nil end
    local p = ERClient.player(self.playerNum)
    if p == nil then return nil end
    local px = ERCompat.get(p, "getX", 0)
    local py = ERCompat.get(p, "getY", 0)
    local dist = math.floor(ERUtil.dist2D(px, py, rec.x, rec.y))
    local dir = ERUtil.compass(px, py, rec.x, rec.y)
    return getTextOr("IGUI_ERLeveling_Bloodstain", "Bloodstain") .. ": "
        .. dist .. " " .. getTextOr("IGUI_ERLeveling_Tiles", "tiles") .. " " .. dir
        .. "  -  " .. ERStats.comma(rec.runes or 0) .. " "
        .. getTextOr("IGUI_ERLeveling_Runes", "runes")
end

-- ---------------------------------------------------------------------------
-- Keyboard: arrow keys stage the selected row (PLAN.md 7.2)
-- ---------------------------------------------------------------------------
function ERLevelPanel:handleKey(key)
    local idx = 1
    for i = 1, #ERBalance.STAT_ORDER do
        if ERBalance.STAT_ORDER[i] == self.selected then idx = i end
    end
    if key == Keyboard.KEY_UP then
        self.selected = ERBalance.STAT_ORDER[math.max(1, idx - 1)]
    elseif key == Keyboard.KEY_DOWN then
        self.selected = ERBalance.STAT_ORDER[math.min(#ERBalance.STAT_ORDER, idx + 1)]
    elseif key == Keyboard.KEY_RIGHT or key == Keyboard.KEY_ADD or key == Keyboard.KEY_EQUALS then
        self:stage(self.selected, 1)
    elseif key == Keyboard.KEY_LEFT or key == Keyboard.KEY_SUBTRACT or key == Keyboard.KEY_MINUS then
        self:stage(self.selected, -1)
    elseif key == Keyboard.KEY_RETURN then
        self:commit()
    else
        return false
    end
    return true
end

function ERLevelPanel:onMouseWheel(del)
    self:stage(self.selected, del < 0 and 1 or -1)
    return true
end

-- ---------------------------------------------------------------------------
-- Tooltip layer
-- ---------------------------------------------------------------------------
ERTooltipLayer = ISPanel:derive("ERTooltipLayer")

function ERTooltipLayer:new(x, y, w, h, owner)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.owner = owner
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    return o
end

-- Purely decorative: never eat a click meant for a row underneath.
function ERTooltipLayer:onMouseDown(x, y) return false end
function ERTooltipLayer:isMouseOver() return false end

ERTooltipLayer.DESCRIPTIONS = {
    vig = "Vigor hardens the flesh. Reduces the damage you keep from every wound and knits injuries back together over time.",
    mnd = "Mind steadies the will. Blunts panic, stress and despair, and sharpens your eye down a barrel.",
    endr= "Endurance is breath and burden. Slows how fast you tire, speeds your recovery, and lets you carry more.",
    str = "Strength is the swing. More damage with every melee blow, and a heavier load on your back.",
    dex = "Dexterity is the hand. Faster recovery between swings, quicker reloads, and gentler wear on your weapons.",
    int = "Intelligence is the study. Every skill you practise is learned faster.",
    fth = "Faith is the mending. Wounds you have dressed knit closed a little further with every passing minute, and sickness loosens its grip. It does NOT cure the zombie infection.",
    arc = "Arcane is the fortune. More runes from the dead, and the world yields a little more to those who look.",
}

function ERTooltipLayer:render()
    local owner = self.owner
    if owner == nil or owner.hoveredStat == nil then return end
    local key = owner.hoveredStat
    local def = ERBalance.STATS[key]
    if def == nil then return end

    local C = ERBalance.COLOR
    local font = ERUI.font("small")
    local lineH = ERUI.textHeight(font)
    local boxW = math.min(300, math.max(200, self.width - 20))
    local lines = ERUtil.wrap(ERTooltipLayer.DESCRIPTIONS[key] or "", boxW - 16, font)

    local value = tonumber(owner.snapshot.stats[key]) or 0
    local staged = math.floor(tonumber(owner.staged[key]) or 0)
    local detail = {}
    for effectKey, _ in pairs(ERBalance.EFFECTS[key] or {}) do
        table.insert(detail, effectKey)
    end
    table.sort(detail)

    local boxH = 8 + lineH * (#lines + 1 + #detail) + 8
    local mx = self:getMouseX() + 14
    local my = self:getMouseY() + 14
    if mx + boxW > self.width then mx = math.max(0, self.width - boxW - 4) end
    if my + boxH > self.height then my = math.max(0, self.height - boxH - 4) end

    ERUI.rect(self, mx, my, boxW, boxH, C.bgSolid, 0.96)
    ERUI.border(self, mx, my, boxW, boxH, C.goldDim, 0.9)

    local ty = my + 6
    ERUI.text(self, string.upper(def.name) .. "   " .. value
              .. (staged > 0 and ("  >  " .. (value + staged)) or ""),
              mx + 8, ty, C.gold, 1.0, font)
    ty = ty + lineH + 2
    for i = 1, #lines do
        ERUI.text(self, lines[i], mx + 8, ty, C.text, 1.0, font)
        ty = ty + lineH
    end
    for i = 1, #detail do
        local eff = detail[i]
        local now = ERStats.effect(key, eff, value)
        local soon = ERStats.effect(key, eff, value + staged)
        local text = eff .. ": " .. string.format("%.2f", now)
        if staged > 0 then text = text .. "  >  " .. string.format("%.2f", soon) end
        ERUI.text(self, text, mx + 8, ty, staged > 0 and C.staged or C.textDim, 1.0, font)
        ty = ty + lineH
    end
end
