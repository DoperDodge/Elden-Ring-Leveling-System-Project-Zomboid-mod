--[[
    ERLeveling_Util.lua
    -------------------
    Small shared helpers. Nothing here touches modData or the network.
]]

ERUtil = ERUtil or {}

--- Milliseconds since some fixed epoch. Used only for throttling and rate limits,
-- so the epoch does not matter as long as it is monotonic within a session.
function ERUtil.nowMs()
    local ok, t = ERCompat.callGlobal("getTimestampMs")
    if ok and type(t) == "number" then return t end
    local ok2, t2 = ERCompat.callGlobal("getTimestamp")
    if ok2 and type(t2) == "number" then return t2 * 1000 end
    local ok3, t3 = pcall(function() return os.time() end)
    if ok3 and type(t3) == "number" then return t3 * 1000 end
    return 0
end

--- Seconds-resolution wall clock for stored timestamps.
function ERUtil.now()
    return math.floor(ERUtil.nowMs() / 1000)
end

function ERUtil.clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function ERUtil.round(v)
    return math.floor((tonumber(v) or 0) + 0.5)
end

function ERUtil.copyStats(stats)
    local out = {}
    for i = 1, #ERBalance.STAT_ORDER do
        local k = ERBalance.STAT_ORDER[i]
        out[k] = tonumber((stats or {})[k]) or ERBalance.svNum("StartingStat", 1, 99)
    end
    return out
end

function ERUtil.dist2D(x1, y1, x2, y2)
    local dx, dy = (x1 or 0) - (x2 or 0), (y1 or 0) - (y2 or 0)
    return math.sqrt(dx * dx + dy * dy)
end

--- 8-point compass bearing from (fromX,fromY) to (toX,toY), PZ axes
-- (+x = east, +y = south).
function ERUtil.compass(fromX, fromY, toX, toY)
    local dx, dy = (toX or 0) - (fromX or 0), (toY or 0) - (fromY or 0)
    if math.abs(dx) < 0.5 and math.abs(dy) < 0.5 then return "HERE" end
    local ns, ew = "", ""
    if dy < -0.5 then ns = "N" elseif dy > 0.5 then ns = "S" end
    if dx > 0.5 then ew = "E" elseif dx < -0.5 then ew = "W" end
    -- Suppress the minor axis when one direction dominates by 2.5x.
    if math.abs(dx) > math.abs(dy) * 2.5 then ns = "" end
    if math.abs(dy) > math.abs(dx) * 2.5 then ew = "" end
    local out = ns .. ew
    if out == "" then out = "HERE" end
    return out
end

--- Find an inventory item by its numeric ID, searching the main inventory and
-- every container inside it. Returns the item or nil.
function ERUtil.findItemById(player, id)
    if player == nil or id == nil then return nil end
    local ok, inv = pcall(function() return player:getInventory() end)
    if not ok or inv == nil then return nil end
    local ok2, items = pcall(function() return inv:getItems() end)
    if not ok2 or items == nil then return nil end
    local okSize, size = pcall(function() return items:size() end)
    if not okSize or size == nil then return nil end
    for i = 0, size - 1 do
        local ok3, item = pcall(function() return items:get(i) end)
        if ok3 and item ~= nil then
            local iid = ERCompat.get(item, "getID", nil)
            if iid ~= nil and iid == id then return item end
        end
    end
    return nil
end

--- Count how many items of a full type the player holds.
function ERUtil.countType(player, fullType)
    local ok, inv = pcall(function() return player:getInventory() end)
    if not ok or inv == nil then return 0 end
    local shortType = string.match(fullType, "%.(.+)$") or fullType
    local ok2, n = pcall(function() return inv:getCountTypeRecurse(shortType) end)
    if ok2 and type(n) == "number" then return n end
    return 0
end

--- Text-drawing helper: hard-wrap a string to `width` pixels (PLAN.md 15.6 -
-- PZ has no text wrapping).
function ERUtil.wrap(text, width, font)
    local lines = {}
    if type(text) ~= "string" or text == "" then return lines end
    local tm = nil
    local ok = pcall(function() tm = getTextManager() end)
    if not ok or tm == nil then return { text } end
    local current = ""
    for word in string.gmatch(text, "%S+") do
        local candidate = (current == "") and word or (current .. " " .. word)
        local okW, w = pcall(function() return tm:MeasureStringX(font, candidate) end)
        if okW and w and w > width and current ~= "" then
            table.insert(lines, current)
            current = word
        else
            current = candidate
        end
    end
    if current ~= "" then table.insert(lines, current) end
    return lines
end

--- getText() that falls back to a literal, so a missing translation entry renders
-- readable English rather than the raw key. Global on purpose: every UI file uses it.
function getTextOr(key, fallback)
    local ok, s = pcall(function() return getText(key) end)
    if ok and type(s) == "string" and s ~= "" and s ~= key then return s end
    return fallback
end
