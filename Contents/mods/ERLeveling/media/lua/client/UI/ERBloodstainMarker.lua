--[[
    ERBloodstainMarker.lua
    ----------------------
    Finding your runes again (PLAN.md 4.2, 4.3).

    The plan's preferred marker is a floor decal. We could not confirm a world-decal
    API exists, so the shipped marker is the rest of the ladder, all at once:

      tier 2  a world item dropped on the death square by the server, where the
              square is loaded (ERLeveling_Bloodstain.lua);
      tier 3  a screen-space beacon, drawn here. Where the world-to-screen helpers
              probe successfully the beacon sits on the square itself; where they
              do not, it becomes an edge-of-screen chevron pointing the way, which
              is the more useful of the two at Project Zomboid's map scale anyway;
      tier 4  the distance/direction line on the Runes tab.

    This file also owns proximity reclaim: it *asks*, the server decides.
]]

ERBloodstainUI = ERBloodstainUI or {}
ERBloodstainUI.element = nil
ERBloodstainUI._lastCheck = 0
ERBloodstainUI._lastRequest = 0

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

-- ---------------------------------------------------------------------------
-- The overlay
-- ---------------------------------------------------------------------------
ERBloodstainOverlay = ISUIElement:derive("ERBloodstainOverlay")

function ERBloodstainOverlay:new()
    local sw, sh = 800, 600
    pcall(function() sw = getCore():getScreenWidth(); sh = getCore():getScreenHeight() end)
    local o = ISUIElement:new(0, 0, sw, sh)
    setmetatable(o, self)
    self.__index = self
    return o
end

function ERBloodstainOverlay:onResolutionChange(oldW, oldH, newW, newH)
    self:setWidth(newW)
    self:setHeight(newH)
end

function ERBloodstainOverlay:onMouseDown(x, y) return false end
function ERBloodstainOverlay:isMouseOver() return false end

--- A slow gold pulse, 0.45 .. 1.0.
local function pulse()
    local t = (ERUtil.nowMs() % 1800) / 1800
    return 0.45 + 0.55 * (0.5 + 0.5 * math.cos(t * math.pi * 2))
end

function ERBloodstainOverlay:render()
    local player = ERClient.player(0)
    if player == nil then return end
    local rec = ERClient.bloodstain(player)
    if rec == nil then return end

    local px = ERCompat.get(player, "getX", 0)
    local py = ERCompat.get(player, "getY", 0)
    local pz = math.floor(ERCompat.get(player, "getZ", 0))
    local dist = ERUtil.dist2D(px, py, rec.x + 0.5, rec.y + 0.5)
    local C = ERBalance.COLOR
    local a = pulse()

    -- On-square beacon when the tile is near, on our floor, and projectable.
    if dist <= ERBalance.BLOODSTAIN.markerRange and math.floor(rec.z or 0) == pz then
        local sx, sy = project(rec.x, rec.y, rec.z, 0)
        if sx and sy and sx > -80 and sy > -80 and sx < self.width + 80 and sy < self.height + 80 then
            local tex = ERUI.tex("bloodstain")
            if tex ~= nil then
                pcall(function()
                    self:drawTextureScaled(tex, sx - 24, sy - 16, 48, 32, a * 0.85, 1, 1, 1)
                end)
            else
                -- Vector fallback: a flat gold lozenge on the ground.
                for i = 0, 7 do
                    local w = (8 - i) * 5
                    self:drawRect(sx - w / 2, sy - 4 + i, w, 1, a * 0.35, C.gold.r, C.gold.g, C.gold.b)
                end
            end
            local text = ERStats.comma(rec.runes or 0)
            self:drawTextCentre(text, sx, sy - 30, C.gold.r, C.gold.g, C.gold.b, a, ERUI.font("small"))
            return
        end
    end

    -- Otherwise: an edge chevron pointing the way, with distance.
    local cx, cy = self.width / 2, self.height / 2
    local dx, dy = (rec.x + 0.5) - px, (rec.y + 0.5) - py
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then return end
    -- World axes are rotated 45 degrees on screen in Project Zomboid's isometric view.
    local ex = (dx - dy)
    local ey = (dx + dy) * 0.5
    local elen = math.sqrt(ex * ex + ey * ey)
    if elen < 0.001 then return end
    ex, ey = ex / elen, ey / elen

    local radius = math.min(self.width, self.height) * 0.36
    local mx = cx + ex * radius
    local my = cy + ey * radius

    ERUI.runeIcon(self, mx - 6, my - 6, 12, a * 0.9)
    local label = math.floor(dist) .. "  " .. ERUtil.compass(px, py, rec.x, rec.y)
    self:drawTextCentre(label, mx, my + 10, C.gold.r, C.gold.g, C.gold.b, a * 0.9, ERUI.font("small"))
    if math.floor(rec.z or 0) ~= pz then
        local updown = (math.floor(rec.z or 0) > pz)
            and getTextOr("IGUI_ERLeveling_Above", "ABOVE")
            or  getTextOr("IGUI_ERLeveling_Below", "BELOW")
        self:drawTextCentre(updown, mx, my + 10 + ERUI.textHeight(ERUI.font("small")),
                            C.goldDim.r, C.goldDim.g, C.goldDim.b, a * 0.9, ERUI.font("small"))
    end
end

function ERBloodstainUI.create()
    if ERBloodstainUI.element ~= nil then return end
    local ok, el = pcall(function()
        local e = ERBloodstainOverlay:new()
        e:initialise()
        e:instantiate()
        if e.setCapture then e:setCapture(false) end
        if e.setConsumeMouseEvents then e:setConsumeMouseEvents(false) end
        e:addToUIManager()
        return e
    end)
    if ok then ERBloodstainUI.element = el end
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
