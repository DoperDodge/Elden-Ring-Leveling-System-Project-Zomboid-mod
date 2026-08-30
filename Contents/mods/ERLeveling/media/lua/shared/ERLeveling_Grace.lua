--[[
    ERLeveling_Grace.lua
    --------------------
    Site of Grace detection (PLAN.md 5).

    DEVIATION FROM PLAN.md 12: the plan filed this under client/. It lives in
    shared/ because PLAN.md 9 requires the *server* to independently re-validate
    Grace proximity on a level-up, and the server cannot call into client Lua.
    The client-only presentation (glow, header state, caching) is in
    client/ERLeveling_GraceClient.lua.

    Detection is deliberately signal-based rather than class-based: we do not know
    which of IsoFireplace / CampfireSystem / sprite naming the installed build
    exposes, so every signal is probed independently and any one of them is enough.
]]

ERGrace = ERGrace or {}

-- Sprite name fragments that identify a heat source. Checked lower-case.
ERGrace.HEAT_SPRITES = {
    "campfire", "fireplace", "stove", "oven", "firepit", "camping_01",
    "brazier", "hearth", "furnace",
}

-- Every member read here goes through ERCompat rather than a bare pcall, and the
-- reason is the log flood described at the top of ERLeveling_Compat.lua: Project
-- Zomboid writes a full stack trace for a caught exception too. This function
-- runs for every object on up to 49 squares, twice a second, and plenty of
-- IsoObjects have no getSprite() - as a bare pcall that is a stack trace per
-- object per scan. Through ERCompat it is one trace per class, ever.
local function spriteNameOf(obj)
    local sprite = ERCompat.get(obj, "getSprite", nil)
    if sprite == nil then return nil end
    local name = ERCompat.get(sprite, "getName", nil)
    if type(name) ~= "string" then return nil end
    return string.lower(name)
end

local function spriteLooksLikeHeat(obj)
    local name = spriteNameOf(obj)
    if not name then return false end
    for i = 1, #ERGrace.HEAT_SPRITES do
        if string.find(name, ERGrace.HEAT_SPRITES[i], 1, true) then return true end
    end
    return false
end

--- Is this object a *lit* heat source?
-- Returns true only when we can positively confirm both "heat source" and "lit".
-- An object that looks like a fireplace but exposes no lit state is treated as
-- unlit: a cold hearth is not a Grace.
local function isLitHeatSource(obj)
    if obj == nil then return false end

    -- Signal B: a live IsoFire on the square is unambiguous.
    local okInst, isFire = pcall(function() return instanceof(obj, "IsoFire") end)
    if okInst and isFire then return true end

    if not spriteLooksLikeHeat(obj) then return false end

    -- Signal A: the object itself reports its lit state.
    if ERCompat.has(obj, "isLit") then
        local ok, lit = ERCompat.call(obj, "isLit")
        if ok then return lit == true end
    end
    -- Some stoves report through isActivated() instead.
    if ERCompat.has(obj, "isActivated") then
        local ok, on = ERCompat.call(obj, "isActivated")
        if ok and on == true then return true end
    end
    -- Campfires built by the player carry their state in modData.
    local md = ERCompat.get(obj, "getModData", nil)
    if type(md) == "table" then
        if md.lit == true or md.isLit == true or md.fuelAmt ~= nil and md.lit ~= false and md.lit ~= nil then
            return md.lit == true or md.isLit == true
        end
    end
    return false
end

--- Signal C: the campfire global-object system, when the build exposes it.
local function campfireLitAt(square)
    if not ERCompat.hasGlobal("CampfireSystem") then return false end
    local ok, obj = pcall(function()
        local sys = CampfireSystem.instance
        if sys == nil then return nil end
        if sys.getLuaObjectOnSquare then return sys:getLuaObjectOnSquare(square) end
        return nil
    end)
    if not ok or obj == nil then return false end
    local ok2, lit = ERCompat.call(obj, "isLit")
    return ok2 and lit == true
end

--- Signal D: a Grace Idol resting on the square.
local function idolOnSquare(square)
    local items = ERCompat.get(square, "getWorldObjects", nil)
    if items == nil then return false end
    local okSize, size = pcall(function() return items:size() end)
    if not okSize or size == nil then return false end
    for i = 0, size - 1 do
        local ok2, wi = pcall(function() return items:get(i) end)
        if ok2 and wi ~= nil then
            local item = ERCompat.get(wi, "getItem", nil)
            if item ~= nil then
                local ft = ERCompat.get(item, "getFullType", nil)
                if ft == ERBalance.GRACE_ITEM then return true end
            end
        end
    end
    return false
end

local function scanSquare(square, radiusKind)
    if square == nil then return nil end
    if campfireLitAt(square) then return "campfire" end
    local objs = ERCompat.get(square, "getObjects", nil)
    if objs ~= nil then
        local okSize, size = pcall(function() return objs:size() end)
        if okSize and size then
            for i = 0, size - 1 do
                local ok2, o = pcall(function() return objs:get(i) end)
                if ok2 and o ~= nil and isLitHeatSource(o) then
                    return radiusKind
                end
            end
        end
    end
    if idolOnSquare(square) then return "idol" end
    return nil
end

--- Does the player hold a Grace Idol? Documented fallback for builds where
-- placing the idol as a world object does not work (see NOTES.md).
local function carryingIdol(player)
    local inv = ERCompat.get(player, "getInventory", nil)
    if inv == nil then return false end
    local ok2, has = ERCompat.call(inv, "containsTypeRecurse", "GraceIdol")
    return ok2 and has == true
end

--- Is the player resting? Sleeping or sitting counts as a Grace (PLAN.md 5).
local function isResting(player)
    if ERCompat.get(player, "isAsleep", false) == true then return true end
    if ERCompat.get(player, "isSitOnGround", false) == true then return true end
    if ERCompat.get(player, "isSitOnFurniture", false) == true then return true end
    return false
end

--- Main entry point. Returns isGrace(boolean), reason(string).
-- `reason` is one of: "campfire", "fireplace", "idol", "carried_idol", "resting",
-- "disabled", or "none".
function ERGrace.check(player)
    if player == nil then return false, "none" end
    if not ERBalance.sv("RequireGrace") then return true, "disabled" end

    if isResting(player) then return true, "resting" end
    if carryingIdol(player) then return true, "carried_idol" end

    local ok, square = pcall(function() return player:getSquare() end)
    if not ok or square == nil then return false, "none" end

    local okXYZ, x, y, z = pcall(function()
        return player:getX(), player:getY(), player:getZ()
    end)
    if not okXYZ then return false, "none" end
    x, y, z = math.floor(x), math.floor(y), math.floor(z)

    local okCell, cell = pcall(function() return getCell() end)
    if not okCell or cell == nil then return false, "none" end

    local maxR = math.max(ERBalance.GRACE.campfireRadius,
                          ERBalance.GRACE.fireplaceRadius,
                          ERBalance.GRACE.idolRadius)
    for dx = -maxR, maxR do
        for dy = -maxR, maxR do
            local dist = math.max(math.abs(dx), math.abs(dy))
            local okSq, sq = pcall(function() return cell:getGridSquare(x + dx, y + dy, z) end)
            if okSq and sq ~= nil then
                local kind = scanSquare(sq, dist <= ERBalance.GRACE.fireplaceRadius and "fireplace" or "campfire")
                if kind == "idol" then
                    if dist <= ERBalance.GRACE.idolRadius then return true, "idol" end
                elseif kind ~= nil then
                    if dist <= ERBalance.GRACE.campfireRadius then return true, kind end
                end
            end
        end
    end
    return false, "none"
end
