--[[
    ERUI.lua
    --------
    Shared drawing helpers, the palette bridge, sound, and the small amount of
    cross-widget state (flash timer, popup queue).

    Every texture is loaded once through ERCompat.texture() and nil-checked at the
    draw site, because getTexture() on a missing path returns nil and drawTexture
    then errors (PLAN.md 15.5).
]]

ERUI = ERUI or {}
ERUI._flashUntil = 0
ERUI._textures = nil

ERUI.TEXTURE_PATHS = {
    rune       = "media/textures/ERLeveling/rune_icon.png",
    bloodstain = "media/textures/ERLeveling/bloodstain.png",
    graceGlow  = "media/textures/ERLeveling/grace_glow.png",
    divider    = "media/textures/ERLeveling/divider.png",
}

--- Lazily load and cache every texture. Missing textures stay nil for the
-- session and every draw site falls back to vector drawing.
function ERUI.tex(name)
    if ERUI._textures == nil then
        ERUI._textures = {}
        for k, path in pairs(ERUI.TEXTURE_PATHS) do
            ERUI._textures[k] = ERCompat.texture(path)
        end
    end
    return ERUI._textures[name]
end

-- ---------------------------------------------------------------------------
-- Crash containment
-- ---------------------------------------------------------------------------
-- PLAN.md 1.7: "Every unfinished path returns safely rather than erroring. A Lua
-- error in PZ spams the console every tick and can soft-lock the UI."
--
-- The hooks in ERHooks.lua were pcall-wrapped from the start, but the render and
-- mouse methods of our own widgets were not, and Project Zomboid calls those
-- directly. A throw inside one of them lands in the middle of the engine's UI
-- loop: the console fills at frame rate, and mouse-event dispatch for the whole
-- UI can stop, which takes the game with it - you cannot click the UI or the
-- world. That is exactly the soft-lock the plan named.
--
-- ERUI.protect() closes that hole. Every method PZ can call into is wrapped so a
-- failure is caught, throttled and contained. If one keeps failing, the whole rune
-- UI switches itself off rather than making the game unplayable.

ERUI.disabled = false
ERUI._errorCounts = ERUI._errorCounts or {}
ERUI._totalErrors = 0

local MAX_ERRORS_PER_SITE = 3
local MAX_ERRORS_TOTAL = 25

--- Record a UI failure. Disables the mod's UI entirely once it is clear something
-- is persistently broken, so a bug degrades to "no rune UI" and never to
-- "unplayable game".
function ERUI.uiError(where, err)
    local key = tostring(where)
    local n = (ERUI._errorCounts[key] or 0) + 1
    ERUI._errorCounts[key] = n
    ERUI._totalErrors = ERUI._totalErrors + 1

    if n <= MAX_ERRORS_PER_SITE then
        print("[ERLeveling] UI error in " .. key .. ": " .. tostring(err))
        if n == MAX_ERRORS_PER_SITE then
            print("[ERLeveling] further errors from " .. key .. " suppressed.")
        end
    end

    if ERUI._totalErrors >= MAX_ERRORS_TOTAL and not ERUI.disabled then
        ERUI.disable("too many UI errors")
    end
end

--- Switch the mod's interface off for the rest of the session. Gameplay - runes,
-- levelling, bloodstains - keeps working; only the drawing stops.
function ERUI.disable(reason)
    if ERUI.disabled then return end
    ERUI.disabled = true
    print("[ERLeveling] ==============================================================")
    print("[ERLeveling] Disabling the rune interface for this session: " .. tostring(reason))
    print("[ERLeveling] Runes, levelling and bloodstains keep working; only the")
    print("[ERLeveling] on-screen interface has been switched off, so a bug in our")
    print("[ERLeveling] drawing code cannot take your input with it.")
    print("[ERLeveling] Please report the errors above.")
    print("[ERLeveling] ==============================================================")
    -- Take our overlays back out of the UI manager immediately.
    pcall(function() if ERBloodstainUI and ERBloodstainUI.destroy then ERBloodstainUI.destroy() end end)
    pcall(function() if ERRunePopup and ERRunePopup.destroy then ERRunePopup.destroy() end end)
    pcall(function() if ERYouDied and ERYouDied.hide then ERYouDied.hide() end end)
end

--- Wrap the named methods of a widget class so they can never throw into the
-- engine. Render methods return nothing on failure; mouse handlers return false,
-- which tells Project Zomboid we did not consume the click.
function ERUI.protect(class, names)
    if class == nil then return end
    for i = 1, #names do
        local name = names[i]
        local original = class[name]
        if type(original) == "function" and not class["_erProtected_" .. name] then
            local label = tostring(class.Type or "ERWidget") .. ":" .. name
            class[name] = function(self, a, b, c, d)
                if ERUI.disabled then return false end
                local ok, result = pcall(original, self, a, b, c, d)
                if not ok then
                    ERUI.uiError(label, result)
                    return false
                end
                return result
            end
            class["_erProtected_" .. name] = true
        end
    end
end

--- The full set of entry points Project Zomboid can call on a widget.
ERUI.ENTRY_POINTS = {
    "render", "prerender", "onMouseDown", "onMouseUp", "onRightMouseDown",
    "onRightMouseUp", "onMouseWheel", "onMouseMove", "onMouseMoveOutside",
    "onMouseDownOutside", "createChildren", "onResolutionChange", "onResize",
}

-- ---------------------------------------------------------------------------
-- Fonts
-- ---------------------------------------------------------------------------
-- PLAN.md 2.3 asks which font constants exist. Rather than assume, probe once and
-- keep the best available for each role.
ERUI._fonts = nil
function ERUI.font(role)
    if ERUI._fonts == nil then
        local function pick(...)
            local names = { ... }
            for i = 1, #names do
                local ok, f = pcall(function() return UIFont[names[i]] end)
                if ok and f ~= nil then return f end
            end
            return nil
        end
        ERUI._fonts = {
            big    = pick("Large", "Medium", "Small"),
            medium = pick("Medium", "Small"),
            small  = pick("Small", "NewSmall", "Medium"),
            tiny   = pick("NewSmall", "Small"),
        }
    end
    return ERUI._fonts[role] or ERUI._fonts.small
end

function ERUI.textWidth(font, text)
    local ok, w = pcall(function() return getTextManager():MeasureStringX(font, text) end)
    if ok and type(w) == "number" then return w end
    return #tostring(text) * 6
end

function ERUI.textHeight(font)
    local ok, h = pcall(function() return getTextManager():getFontHeight(font) end)
    if ok and type(h) == "number" then return h end
    return 14
end

-- ---------------------------------------------------------------------------
-- Drawing helpers. `self` is any ISUIElement.
-- ---------------------------------------------------------------------------
local C = function() return ERBalance.COLOR end

function ERUI.rect(self, x, y, w, h, colour, alpha)
    local c = colour or C().track
    self:drawRect(x, y, w, h, alpha or 1.0, c.r, c.g, c.b)
end

function ERUI.border(self, x, y, w, h, colour, alpha)
    local c = colour or C().goldDim
    self:drawRectBorder(x, y, w, h, alpha or 1.0, c.r, c.g, c.b)
end

function ERUI.text(self, s, x, y, colour, alpha, font)
    local c = colour or C().text
    self:drawText(tostring(s), x, y, c.r, c.g, c.b, alpha or 1.0, font or ERUI.font("small"))
end

function ERUI.textRight(self, s, x, y, colour, alpha, font)
    local c = colour or C().text
    self:drawTextRight(tostring(s), x, y, c.r, c.g, c.b, alpha or 1.0, font or ERUI.font("small"))
end

function ERUI.textCentre(self, s, x, y, colour, alpha, font)
    local c = colour or C().text
    self:drawTextCentre(tostring(s), x, y, c.r, c.g, c.b, alpha or 1.0, font or ERUI.font("small"))
end

--- A 1px gold rule with the section label sitting on it, Elden Ring style.
function ERUI.divider(self, x, y, w, label, lit)
    local colour = lit and C().gold or C().goldDim
    local labelW = 0
    if label and label ~= "" then
        labelW = ERUI.textWidth(ERUI.font("small"), label) + 12
        ERUI.text(self, label, x + 4, y - math.floor(ERUI.textHeight(ERUI.font("small")) / 2),
                  colour, 1.0, ERUI.font("small"))
    end
    local ruleX, ruleW = x + labelW, math.max(0, w - labelW)
    local tex = ERUI.tex("divider")
    local drawn = false
    if tex ~= nil and ruleW > 0 then
        drawn = pcall(function()
            self:drawTextureScaled(tex, ruleX, y - 1, ruleW, 3, 0.75,
                                   colour.r, colour.g, colour.b)
        end)
    end
    if not drawn then
        ERUI.rect(self, ruleX, y, ruleW, 1, colour, 0.55)
    end
    if labelW > 0 then
        ERUI.rect(self, x, y, 2, 1, colour, 0.55)
    end
end

--- The soft gold wash shown while the player is at a Site of Grace.
-- Uses the glow texture where it loaded, and falls back to edge bands.
function ERUI.graceWash(self, w, h)
    local c = C().gold
    local tex = ERUI.tex("graceGlow")
    if tex ~= nil then
        local ok = pcall(function()
            self:drawTextureScaled(tex, -math.floor(w * 0.25), math.floor(h * 0.35),
                                   math.floor(w * 1.5), math.floor(h * 1.1),
                                   0.16, c.r, c.g, c.b)
        end)
        if ok then return end
    end
    for i = 0, 5 do
        local a = 0.05 * (1 - i / 6)
        self:drawRect(0, i, w, 1, a, c.r, c.g, c.b)
        self:drawRect(0, h - i - 1, w, 1, a, c.r, c.g, c.b)
    end
end

--- Segmented attribute bar. `value` and `stagedTo` are raw stat numbers.
function ERUI.statBar(self, x, y, w, h, value, stagedTo, maxStat)
    local maxV = maxStat or 99
    local frac = ERUtil.clamp(value / maxV, 0, 1)
    ERUI.rect(self, x, y, w, h, C().track, 0.9)
    ERUI.rect(self, x, y, math.floor(w * frac), h, C().gold, 0.95)
    if stagedTo and stagedTo > value then
        local sFrac = ERUtil.clamp(stagedTo / maxV, 0, 1)
        local from = math.floor(w * frac)
        ERUI.rect(self, x + from, y, math.floor(w * sFrac) - from, h, C().staged, 0.9)
    end
    ERUI.border(self, x, y, w, h, C().goldDim, 0.6)
end

--- The rune diamond. Falls back to a drawn lozenge when the texture is missing.
function ERUI.runeIcon(self, x, y, size, alpha)
    local tex = ERUI.tex("rune")
    if tex ~= nil then
        local ok = pcall(function()
            self:drawTextureScaled(tex, x, y, size, size, alpha or 1.0, 1, 1, 1)
        end)
        if ok then return end
    end
    local c = C().gold
    local half = math.floor(size / 2)
    for i = 0, half - 1 do
        local w = (i + 1) * 2
        self:drawRect(x + half - i - 1, y + i, w, 1, alpha or 1.0, c.r, c.g, c.b)
        self:drawRect(x + half - i - 1, y + size - i - 1, w, 1, alpha or 1.0, c.r, c.g, c.b)
    end
end

-- ---------------------------------------------------------------------------
-- Flash, sound, popups
-- ---------------------------------------------------------------------------
function ERUI.flash()
    ERUI._flashUntil = ERUtil.nowMs() + 420
end

function ERUI.flashAlpha()
    local left = ERUI._flashUntil - ERUtil.nowMs()
    if left <= 0 then return 0 end
    return ERUtil.clamp(left / 420, 0, 1) * 0.35
end

--- Play a named sound on the local player. Sound names are configurable in
-- ERBalance so a server owner can point them at whatever their pack provides;
-- an empty name is silence. See NOTES.md on why no .ogg files ship with the mod.
function ERUI.playSound(name)
    if name == nil or name == "" then return end
    if not ERBalance.sv("EnableSounds") then return end
    local p = ERClient.player(0)
    if p == nil then return end
    pcall(function() p:playSound(name) end)
end

function ERUI.playLevelUpSound() ERUI.playSound(ERBalance.SOUND.levelUp) end
function ERUI.playGraceSound()   ERUI.playSound(ERBalance.SOUND.grace) end
function ERUI.playRuneSound()    ERUI.playSound(ERBalance.SOUND.runes) end

--- Route a rune gain to the floating popup, if it exists yet.
function ERUI.pushRuneGain(amount, isReclaim)
    if ERRunePopup and ERRunePopup.push then
        ERRunePopup.push(amount, isReclaim)
    end
    if isReclaim then ERUI.playRuneSound() end
end

function ERUI.showYouDied(dropped)
    if ERYouDied and ERYouDied.show then
        ERYouDied.show(dropped)
    end
end

-- ---------------------------------------------------------------------------
-- Applying the protection
-- ---------------------------------------------------------------------------
-- Project Zomboid loads client/UI alphabetically, so this file loads after some
-- widget classes and before others. Rather than each file protecting itself, the
-- whole set is protected from one place on OnGameStart. Instances resolve their
-- methods through the class table at call time, so widgets created before or
-- after this runs both get the wrapped versions.
ERUI.PROTECTED_CLASSES = {
    "ERLevelPanel", "ERStatRow", "ERTooltipLayer", "ERRuneStrip",
    "ERRuneHud", "ERBloodstainOverlay", "ERYouDiedPanel", "ERWindow",
}

function ERUI.protectAll()
    for i = 1, #ERUI.PROTECTED_CLASSES do
        local name = ERUI.PROTECTED_CLASSES[i]
        local class = _G[name]
        if class ~= nil then
            ERUI.protect(class, ERUI.ENTRY_POINTS)
        end
    end
end

ERCompat.onEvent("OnGameStart", function()
    ERUI.protectAll()
end)
