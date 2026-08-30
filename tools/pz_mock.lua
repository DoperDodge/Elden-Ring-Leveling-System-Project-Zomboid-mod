--[[
    pz_mock.lua
    -----------
    A minimal stand-in for the Project Zomboid Lua environment, so the shared and
    server halves of this mod can be loaded and exercised outside the game.

    It is deliberately shallow: it implements only the API surface this mod
    actually calls, which is itself the point - if the mod starts calling
    something new, this file has to grow, and that is a visible decision.

    NOT a substitute for in-game testing. See NOTES.md.
]]

local M = {}

-- --- Events ---------------------------------------------------------------
local handlers = {}
local function mkEvent(name)
    return {
        Add = function(fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end,
        Remove = function() end,
    }
end

Events = setmetatable({}, {
    __index = function(t, k)
        -- Only the events this mod subscribes to exist; anything else is absent,
        -- which is exactly what ERCompat.hasEvent is there to survive.
        local known = {
            OnZombieDead = true, OnHitZombie = true, OnWeaponHitCharacter = true,
            OnPlayerGetDamage = true, OnPlayerDeath = true, OnCreatePlayer = true,
            EveryOneMinute = true, EveryTenMinutes = true, EveryHours = true,
            OnPlayerUpdate = true, OnGameStart = true, OnKeyPressed = true,
            OnClientCommand = true, OnServerCommand = true, OnFillContainer = true,
            OnFillInventoryObjectContextMenu = true, OnFillWorldObjectContextMenu = true,
            OnDistributionMerge = true, AddXP = true,
        }
        if not known[k] then return nil end
        local ev = mkEvent(k)
        rawset(t, k, ev)
        return ev
    end,
})

function M.fire(name, ...)
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
end

-- --- Sandbox --------------------------------------------------------------
SandboxVars = { ERLeveling = {} }
function M.setSandbox(k, v) SandboxVars.ERLeveling[k] = v end
function M.clearSandbox() SandboxVars.ERLeveling = {} end

-- --- ModData --------------------------------------------------------------
local globalData = {}
ModData = {
    getOrCreate = function(key)
        globalData[key] = globalData[key] or {}
        return globalData[key]
    end,
    transmit = function() end,
}
function M.resetGlobal() globalData = {} end

-- --- Network flags --------------------------------------------------------
local clientFlag, serverFlag = false, false
function isClient() return clientFlag end
function isServer() return serverFlag end
function M.setMode(client, server) clientFlag, serverFlag = client, server end

function sendClientCommand() end
function sendServerCommand() end

-- --- Misc globals ---------------------------------------------------------
function getTimestampMs() return M.clock or 0 end
function getTimestamp() return math.floor((M.clock or 0) / 1000) end
M.clock = 1000000
function M.advance(ms) M.clock = M.clock + ms end

function ZombRand(n) return 0 end
function getText(k) return k end
function instanceof(obj, class)
    return type(obj) == "table" and obj.__class == class
end

Perks = { Strength = "Strength", Fitness = "Fitness", Aiming = "Aiming",
          Reloading = "Reloading", MetalWelding = "MetalWelding" }
BodyPartType = { Head = "Head", MAX = "MAX", ToIndex = function() return 4 end,
                 FromIndex = function(i) return "part" .. i end }

-- --- Players --------------------------------------------------------------
local Player = {}
Player.__index = Player

function M.newPlayer(username, x, y, z)
    local p = setmetatable({
        __class = "IsoPlayer",
        _md = {},
        _username = username,
        _x = x or 100, _y = y or 100, _z = z or 0,
        _num = 0,
        _inventory = M.newInventory(),
        _perks = {},
    }, Player)
    return p
end

function Player:getModData() return self._md end
function Player:getUsername() return self._username end
function Player:getPlayerNum() return self._num end
function Player:getX() return self._x end
function Player:getY() return self._y end
function Player:getZ() return self._z end
function Player:setPos(x, y, z) self._x, self._y, self._z = x, y, z end
function Player:getInventory() return self._inventory end
function Player:transmitModData() end
function Player:getPerkLevel(p) return self._perks[p] or 0 end
function Player:LevelPerk(p) self._perks[p] = (self._perks[p] or 0) + 1 end
function Player:getAccessLevel() return "" end
function Player:getSquare() return M.square end
function Player:getBodyDamage() return M.bodyDamage end
function Player:playSound() end

-- --- Inventory ------------------------------------------------------------
function M.newInventory()
    local inv = { _items = {} }
    function inv:getItems()
        local list = self._items
        return {
            size = function() return #list end,
            get = function(_, i) return list[i + 1] end,
        }
    end
    function inv:getFirstTypeRecurse(shortType)
        for _, it in ipairs(self._items) do
            if it:getType() == shortType then return it end
        end
        return nil
    end
    function inv:getCountTypeRecurse(shortType)
        local n = 0
        for _, it in ipairs(self._items) do
            if it:getType() == shortType then n = n + 1 end
        end
        return n
    end
    function inv:Remove(item)
        for i, it in ipairs(self._items) do
            if it == item then table.remove(self._items, i) return end
        end
    end
    function inv:AddItem(fullType)
        local it = M.newItem(fullType)
        table.insert(self._items, it)
        return it
    end
    return inv
end

local nextId = 1
function M.newItem(fullType)
    local id = nextId; nextId = nextId + 1
    local short = string.match(fullType, "%.(.+)$") or fullType
    return {
        __class = "InventoryItem",
        getFullType = function() return fullType end,
        getType = function() return short end,
        getID = function() return id end,
    }
end

-- --- World ----------------------------------------------------------------
M.square = {
    getObjects = function() return { size = function() return 0 end } end,
    getWorldObjects = function() return { size = function() return 0 end } end,
    AddWorldInventoryItem = function() end,
    removeWorldObject = function() end,
}
function getCell()
    return { getGridSquare = function(_, x, y, z) return M.square end }
end

M.bodyDamage = {
    getOverallBodyHealth = function() return 100 end,
}

function getOnlinePlayers() return nil end
function getSpecificPlayer(i) return M.players and M.players[i] or nil end
M.players = {}

function getCore() return { getVersionNumber = function() return "41.78.16" end } end

return M
