--[[
    ERBloodstainMarker.lua
    ----------------------
    Finding your runes again (PLAN.md 4.2, 4.3).

    The plan's preferred marker is a floor decal. We could not confirm a world-decal
    API exists, so the shipped marker is the rest of the ladder:

      tier 2  a world item dropped on the death square by the server, where the
              square is loaded (ERLeveling_Bloodstain.lua);
      tier 3  a screen marker, drawn here. Where the world-to-screen helpers probe
              successfully it sits on the square itself; where they do not it
              becomes a chevron pointing the way, which is the more useful of the
              two at Project Zomboid's map scale anyway;
      tier 4  the distance/direction line on the Runes tab.

    THIS ELEMENT IS DELIBERATELY SMALL.
    It used to be a full-screen ISUIElement added to the UI manager at game start
    and left there for the whole session, whether or not the player had a
    bloodstain. A full-screen element sits over everything and can swallow every
    mouse click in the game. It is now a 170x70 box that is only in the UI manager
    while a bloodstain actually exists, and it moves itself to wherever the marker
    belongs. See NOTES.md.

    This file also owns proximity reclaim: it *asks*, the server decides.
]]

ERBloodstainUI = ERBloodstainUI or {}
ERBloodstainUI.element = nil
ERBloodstainUI._added = false
ERBloodstainUI._lastCheck = 0
ERBloodstainUI._lastRequest = 0

local BOX_W, BOX_H = 170, 70

-- ---------------------------------------------------------------------------
-- World -> screen, probed once
-- ---------------------------------------------------------------------------
ERBloodstainUI._project = nil

local function canProject()
    if ERBloodstainUI._project ~= nil then return ERBloodstainUI._project end
    local ok = false
    pcall(function()
        ok = IsoUtils ~= nil
             and IsoUtils.XToScreenExact ~= nil
             and IsoUtils.YToScreenExact ~= nil
             and IsoCamera ~= nil
    end)
    ERBloodstainUI._project = ok
    if not ok then
        print("[ERLeveling] world-to-screen helpers unavailable; bloodstain uses the edge chevron.")
    end
    return ok
end

--- Screen position of a world tile, or nil.
local function project(x, y, z, playerNum)
    if not canProject() then return nil end
    local sx, sy
    local ok = pcall(function()
        local zoom = 1.0
        pcall(function() zoom = getCore():getZoom(playerNum or 0) end)
        sx = (IsoUtils.XToScreenExact(x + 0.5, y + 0.5, z, 0) - IsoCamera.getOffX()) / zoom
        sy = (IsoUtils.YToScreenExact(x + 0.5, y + 0.5, z, 0) - IsoCamera.getOffY()) / zoom
    end)
    if not ok or sx == nil or sy == nil then return nil end
    if sx ~= sx or sy ~= sy then return nil end
    return sx, sy
end

local function screenSize()
    local sw, sh = 800, 600
    pcall(function() sw = getCore():getScreenWidth(); sh = getCore():getScreenHeight() end)
    return sw, sh
end

-- ---------------------------------------------------------------------------
-- The marker element
-- ---------------------------------------------------------------------------
ERBloodstainOverlay = ISUIElement:derive("ERBloodstainOverlay")

function ERBloodstainOverlay:new()
    local o = ISUIElement:new(0, 0, BOX_W, BOX_H)
    setmetatable(o, self)
    self.__index = self
    o.onSquare = false
    return o
end

-- Decorative only: never take a click away from the game.
function ERBloodstainOverlay:onMouseDown(x, y) return false end
function ERBloodstainOverlay:onRightMouseDown(x, y) return false end
function ERBloodstainOverlay:onMouseUp(x, y) return false end

--- Work out where the marker belongs and move the box there. Returns false when
-- there is nothing to draw, which takes the element back out of the UI manager.
function ERBloodstainOverlay:prerender()
    local player = ERClient.player(0)
    if player == nil then return false end
    local rec = ERClient.bloodstain(player)
    if rec == nil then
        ERBloodstainUI.setAdded(false)
        return false
    end

    local sw, sh = screenSize()
    local px = ERCompat.get(player, "getX", 0)
    local py = ERCompat.get(player, "getY", 0)
    local pz = math.floor(ERCompat.get(player, "getZ", 0))
    local dist = ERUtil.dist2D(px, py, rec.x + 0.5, rec.y + 0.5)

    self.record = rec
    self.distance = dist
    self.sameFloor = (math.floor(rec.z or 0) == pz)
    self.onSquare = false

    -- On-square marker when the tile is close, on our floor, and projectable.
    if self.sameFloor and dist <= ERBalance.BLOODSTAIN.markerRange then
        local sx, sy = project(rec.x, rec.y, rec.z, 0)
        if sx and sy and sx > 0 and sy > 0 and sx < sw and sy < sh then
            self.onSquare = true
            self:setX(math.floor(sx - BOX_W / 2))
            self:setY(math.floor(sy - BOX_H / 2))
            return true
        end
    end

    -- Otherwise a chevron on a ring around the player, pointing the way. World
    -- axes are rotated 45 degrees on screen in the isometric view.
    local dx, dy = (rec.x + 0.5) - px, (rec.y + 0.5) - py
    local ex, ey = (dx - dy), (dx + dy) * 0.5
    local elen = math.sqrt(ex * ex + ey * ey)
    if elen < 0.001 then
        ERBloodstainUI.setAdded(false)
        return false
    end
    ex, ey = ex / elen, ey / elen

    local radius = math.min(sw, sh) * 0.34
    self:setX(math.floor((sw / 2) + ex * radius - BOX_W / 2))
    self:setY(math.floor((sh / 2) + ey * radius - BOX_H / 2))
    return true
end

--- A slow gold pulse, 0.45 .. 1.0.
local function pulse()
    local t = (ERUtil.nowMs() % 1800) / 1800
    return 0.45 + 0.55 * (0.5 + 0.5 * math.cos(t * math.pi * 2))
end

function ERBloodstainOverlay:render()
    local rec = self.record
    if rec == nil then return end
    local C = ERBalance.COLOR
    local a = pulse()
    local cx, cy = BOX_W / 2, BOX_H / 2

    if self.onSquare then
        local tex = ERUI.tex("bloodstain")
        if tex ~= nil then
            self:drawTextureScaled(tex, cx - 24, cy - 16, 48, 32, a * 0.85, 1, 1, 1)
        else
            for i = 0, 7 do
                local w = (8 - i) * 5
                self:drawRect(cx - w / 2, cy - 4 + i, w, 1, a * 0.35, C.gold.r, C.gold.g, C.gold.b)
            end
        end
        self:drawTextCentre(ERStats.comma(rec.runes or 0), cx, cy - 30,
                            C.gold.r, C.gold.g, C.gold.b, a, ERUI.font("small"))
        return
    end

    ERUI.runeIcon(self, cx - 6, cy - 6, 12, a * 0.9)
    local label = math.floor(self.distance or 0) .. "  "
                  .. ERUtil.compass(ERCompat.get(ERClient.player(0), "getX", 0),
                                    ERCompat.get(ERClient.player(0), "getY", 0),
                                    rec.x, rec.y)
    self:drawTextCentre(label, cx, cy + 10, C.gold.r, C.gold.g, C.gold.b, a * 0.9,
                        ERUI.font("small"))
    if not self.sameFloor then
        local pz = math.floor(ERCompat.get(ERClient.player(0), "getZ", 0))
        local updown = (math.floor(rec.z or 0) > pz)
            and getTextOr("IGUI_ERLeveling_Above", "ABOVE")
            or  getTextOr("IGUI_ERLeveling_Below", "BELOW")
        self:drawTextCentre(updown, cx, cy + 10 + ERUI.textHeight(ERUI.font("small")),
                            C.goldDim.r, C.goldDim.g, C.goldDim.b, a * 0.9, ERUI.font("small"))
    end
end

-- ---------------------------------------------------------------------------
-- Lifecycle: in the UI manager only while there is a bloodstain to point at
-- ---------------------------------------------------------------------------
function ERBloodstainUI.setAdded(wanted)
    if ERUI.disabled then wanted = false end
    if wanted == ERBloodstainUI._added then return end
    local el = ERBloodstainUI.element
    if el == nil then return end
    if wanted then
        pcall(function() el:addToUIManager() end)
    else
        pcall(function() el:removeFromUIManager() end)
    end
    ERBloodstainUI._added = wanted
end

function ERBloodstainUI.create()
    if ERBloodstainUI.element ~= nil then return end
    local ok, el = pcall(function()
        local e = ERBloodstainOverlay:new()
        e:initialise()
        e:instantiate()
        if e.setCapture then pcall(function() e:setCapture(false) end) end
        if e.setConsumeMouseEvents then pcall(function() e:setConsumeMouseEvents(false) end) end
        return e
    end)
    -- Deliberately NOT added to the UI manager here. It goes in only when the
    -- player actually has a bloodstain, and comes straight back out afterwards.
    if ok then ERBloodstainUI.element = el end
end

function ERBloodstainUI.destroy()
    ERBloodstainUI.setAdded(false)
    ERBloodstainUI.element = nil
end

-- ---------------------------------------------------------------------------
-- Proximity reclaim (PLAN.md 4.2: walking within a tile auto-reclaims)
-- ---------------------------------------------------------------------------
ERCompat.onEvent("OnPlayerUpdate", function(player)
    if player == nil then return end
    local now = ERUtil.nowMs()
    if (now - ERBloodstainUI._lastCheck) < ERBalance.BLOODSTAIN.checkIntervalMs then return end
    ERBloodstainUI._lastCheck = now

    local rec = ERClient.bloodstain(player)

    -- The marker is only on screen while there is something to point at.
    ERBloodstainUI.setAdded(rec ~= nil)
    if rec == nil then return end

    local pz = math.floor(ERCompat.get(player, "getZ", 0))
    if math.floor(rec.z or 0) ~= pz then return end
    local px = ERCompat.get(player, "getX", 0)
    local py = ERCompat.get(player, "getY", 0)
    if ERUtil.dist2D(px, py, rec.x + 0.5, rec.y + 0.5) > ERBalance.BLOODSTAIN.reclaimRadius then return end

    -- Do not spam the server while it makes up its mind.
    if (now - ERBloodstainUI._lastRequest) < 2000 then return end
    ERBloodstainUI._lastRequest = now
    ERClient.requestReclaim(ERCompat.get(player, "getPlayerNum", 0))
end)

ERCompat.onEvent("OnGameStart", function()
    ERBloodstainUI.create()
end)
