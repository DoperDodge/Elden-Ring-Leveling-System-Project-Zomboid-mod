--[[
    test_offline.lua
    ----------------
    Loads the shared and server halves of the mod against tools/pz_mock.lua and
    asserts the behaviour PLAN.md 13 lists as milestone acceptance criteria.

    Run from the repository root:
        lua tools/test_offline.lua

    This checks logic, not integration: it cannot tell you whether
    ISHealthPanel.createChildren still exists in the installed build. In-game
    testing per PLAN.md 14 is still required.
]]

local ROOT = "Contents/mods/ERLeveling/media/lua/"
local mock = dofile("tools/pz_mock.lua")

local failures, checks = 0, 0
local function check(name, cond, detail)
    checks = checks + 1
    if cond then
        print(string.format("  ok    %s", name))
    else
        failures = failures + 1
        print(string.format("  FAIL  %s   %s", name, tostring(detail or "")))
    end
end
local function eq(name, got, want)
    check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want))
end
local function section(s)
    print("")
    print("== " .. s .. " " .. string.rep("=", math.max(0, 56 - #s)))
end

-- Load order mirrors Project Zomboid's: shared/, then server/.
for _, f in ipairs({ "Balance", "Compat", "Data", "Formulas", "Grace", "Net", "Util" }) do
    dofile(ROOT .. "shared/ERLeveling_" .. f .. ".lua")
end
for _, f in ipairs({ "Runes", "Bloodstain", "ServerCommands" }) do
    dofile(ROOT .. "server/ERLeveling_" .. f .. ".lua")
end

-- ---------------------------------------------------------------------------
section("formulas")
-- ---------------------------------------------------------------------------
eq("scale(1) is 0", ERStats.scale(1), 0)
check("scale(99) is 1.0", math.abs(ERStats.scale(99) - 1.0) < 0.001, ERStats.scale(99))
check("scale is monotonic", (function()
    local prev = -1
    for v = 1, 99 do
        local s = ERStats.scale(v)
        if s < prev then return false end
        prev = s
    end
    return true
end)())
check("scale never exceeds 1", ERStats.scale(200) <= 1.0)

eq("comma formats thousands", ERStats.comma(4217), "4,217")
eq("comma formats millions", ERStats.comma(1234567), "1,234,567")
eq("comma handles zero", ERStats.comma(0), "0")
eq("comma handles negatives", ERStats.comma(-1500), "-1,500")
eq("signedPct positive", ERStats.signedPct(0.23, 0), "+23%")
eq("signedPct negative", ERStats.signedPct(-0.19, 0), "-19%")

eq("cost(1) matches the plan's ~82", ERLevel.cost(1), 81)
check("cost(10) is near the plan's ~700", math.abs(ERLevel.cost(10) - 700) < 50, ERLevel.cost(10))
check("cost(60) is near the plan's ~15k", math.abs(ERLevel.cost(60) - 15000) < 1500, ERLevel.cost(60))
check("cost is strictly increasing", (function()
    for l = 1, 149 do
        if ERLevel.cost(l + 1) <= ERLevel.cost(l) then return false end
    end
    return true
end)())
eq("totalCost sums the individual costs",
   ERLevel.totalCost(1, 3), ERLevel.cost(1) + ERLevel.cost(2) + ERLevel.cost(3))
eq("totalCost of zero points is free", ERLevel.totalCost(5, 0), 0)

-- A fresh character reads Level 1 (PLAN.md 3).
local fresh = {}
for _, k in ipairs(ERBalance.STAT_ORDER) do fresh[k] = 10 end
eq("fresh character is level 1", ERLevel.fromStats(fresh), 1)
check("a fresh character has no melee bonus", ERStats.effect("str", "meleeDamage", 10) == 0,
      ERStats.effect("str", "meleeDamage", 10))
check("a fresh character has no damage negation", ERStats.effect("vig", "damageNegation", 10) == 0)
check("a maxed attribute reaches its full envelope",
      math.abs(ERStats.effect("str", "meleeDamage", 99) - 1.10) < 0.001,
      ERStats.effect("str", "meleeDamage", 99))
check("progress is monotonic", (function()
    local prev = -1
    for v = 1, 99 do
        local s = ERStats.progress(v)
        if s < prev then return false end
        prev = s
    end
    return true
end)())
fresh.vig = 15
eq("five points spent is level 6", ERLevel.fromStats(fresh), 6)

-- Sandbox extremes must not produce NaN or negative costs (PLAN.md 14).
mock.setSandbox("CostA", 0.1); mock.setSandbox("CostB", 4.0)
mock.setSandbox("CostC", 0); mock.setSandbox("CostBase", 0)
check("extreme curve stays finite", ERLevel.cost(1) == ERLevel.cost(1) and ERLevel.cost(1) >= 1,
      ERLevel.cost(1))
mock.setSandbox("EffectStrength", 3.0)
check("reduction respects its ceiling at EffectStrength 3",
      ERStats.reduction("vig", "damageNegation", 99, 0.75) <= 0.75)
mock.clearSandbox()

-- ---------------------------------------------------------------------------
section("data model")
-- ---------------------------------------------------------------------------
mock.setMode(false, false)   -- single player
local p = mock.newPlayer("Tarnished", 100, 100, 0)
mock.players[0] = p

local d = ERData.get(p)
eq("stats initialise to the starting value", d.stats.vig, 10)
eq("endurance uses the endr key, not the Lua keyword", d.stats.endr, 10)
eq("held runes start at zero", d.heldRunes, 0)
eq("schema version is stamped", d.version, ERBalance.DATA_VERSION)

-- A save that predates a field must be repaired, not crash (PLAN.md 8).
p._md.ERLeveling = { stats = { vig = 20 } }
local repaired = ERData.get(p)
eq("a partial table keeps what it had", repaired.stats.vig, 20)
eq("a partial table gains what it lacked", repaired.stats.arc, 10)
eq("a partial table gains heldRunes", repaired.heldRunes, 0)
eq("a partial table gains grantedPerks", repaired.grantedPerks.Strength, 0)

-- Garbage in the table must not propagate.
p._md.ERLeveling = { stats = { vig = "nonsense" }, heldRunes = "lots" }
local cleaned = ERData.get(p)
eq("a non-numeric stat is reset", cleaned.stats.vig, 10)
eq("a non-numeric balance is reset", cleaned.heldRunes, 0)

p._md.ERLeveling = nil

-- Single player must key by the local slot, NOT the character name. Keying by
-- getUsername() meant that dying and rolling a new survivor changed the key, so
-- the bloodstain was filed under a name nothing would look up again.
eq("single player keys by slot, not character name", ERData.keyFor(p), "SP_0")

local reborn = mock.newPlayer("A Completely Different Name", 100, 100, 0)
eq("a new character in the same slot keeps the same key",
   ERData.keyFor(reborn), ERData.keyFor(p))

mock.setMode(true, false)   -- multiplayer client
eq("multiplayer keys by account username", ERData.keyFor(p), "Tarnished")
mock.setMode(false, false)

-- ---------------------------------------------------------------------------
section("runes")
-- ---------------------------------------------------------------------------
ERRunes.credit(p, 8, "kill")
eq("crediting adds to the balance", ERData.runes(p), 8)
eq("crediting tracks lifetime earnings", ERData.get(p).totalEarned, 8)
ERRunes.credit(p, -5, "kill")
eq("a negative credit is ignored", ERData.runes(p), 8)

-- PLAN.md 13 M1: kill ten zombies, see eighty runes.
local zombie = { __class = "IsoZombie", _hp = 1,
                 getHealth = function(self) return self._hp end,
                 setHealth = function(self, v) self._hp = v end,
                 getOnlineID = function() return 7 end,
                 getAttackedBy = function() return p end }
p._md.ERLeveling.heldRunes = 0
p._md.ERLeveling.totalEarned = 0
for i = 1, 10 do
    zombie.getOnlineID = function() return i end
    mock.fire("OnZombieDead", zombie)
end
eq("ten standard kills award eighty runes", ERData.runes(p), 80)

-- Attribution: a zombie nobody hit awards nothing (PLAN.md 15.10).
local orphan = { __class = "IsoZombie", getOnlineID = function() return 999 end,
                 getAttackedBy = function() return nil end }
local before = ERData.runes(p)
mock.fire("OnZombieDead", orphan)
eq("an unattributed kill awards nothing", ERData.runes(p), before)

-- Arcane raises the payout.
p._md.ERLeveling.stats.arc = 99
p._md.ERLeveling.heldRunes = 0
zombie.getOnlineID = function() return 1234 end
mock.fire("OnZombieDead", zombie)
check("Arcane 99 roughly doubles the payout", ERData.runes(p) >= 15,
      ERData.runes(p))
p._md.ERLeveling.stats.arc = 10

-- ---------------------------------------------------------------------------
section("level up (server authority)")
-- ---------------------------------------------------------------------------
mock.setSandbox("RequireGrace", false)
p._md.ERLeveling.heldRunes = 100000
p._md.ERLeveling.stats.vig = 10

local reply = ERNet.dispatch(p, "levelUp", { deltas = { vig = 5 }, expectedCost = 1 })
check("a valid level up succeeds", reply.ok == true, reply.reason)
eq("the attribute moved", ERData.stat(p, "vig"), 15)
eq("the exact predicted cost was charged",
   100000 - ERData.runes(p), ERLevel.totalCost(1, 5))
eq("the level recomputed", ERData.level(p), 6)
eq("the client's expectedCost was ignored", reply.spent, ERLevel.totalCost(1, 5))

-- Refuse what it should refuse.
mock.advance(1000)
p._md.ERLeveling.heldRunes = 10
local poor = ERNet.dispatch(p, "levelUp", { deltas = { str = 1 } })
eq("an unaffordable level up is refused", poor.reason, "insufficient")
eq("nothing was charged for a refused request", ERData.runes(p), 10)

mock.advance(1000)
local negative = ERNet.dispatch(p, "levelUp", { deltas = { str = -1 } })
eq("a negative delta is refused", negative.reason, "negative_delta")

mock.advance(1000)
local empty = ERNet.dispatch(p, "levelUp", { deltas = {} })
eq("an empty request is refused", empty.reason, "no_points")

mock.advance(1000)
p._md.ERLeveling.heldRunes = 10 ^ 9
local overMax = ERNet.dispatch(p, "levelUp", { deltas = { vig = 200 } })
eq("exceeding MaxStat is refused", overMax.reason, "over_max")

mock.advance(1000)
local huge = ERNet.dispatch(p, "levelUp", { deltas = { vig = 1000 } })
check("an absurd request is refused", huge.ok == false, huge.reason)

-- Rate limiting.
p._md.ERLeveling.heldRunes = 10 ^ 9
mock.advance(1000)
local first = ERNet.dispatch(p, "levelUp", { deltas = { mnd = 1 } })
local second = ERNet.dispatch(p, "levelUp", { deltas = { mnd = 1 } })
check("the first of two rapid requests succeeds", first.ok == true, first.reason)
eq("the second is rate limited", second.reason, "too_fast")

-- Grace gating (PLAN.md 13 M5).
mock.advance(1000)
mock.setSandbox("RequireGrace", true)
local away = ERNet.dispatch(p, "levelUp", { deltas = { fth = 1 } })
eq("levelling away from a Grace is refused", away.reason, "no_grace")
mock.setSandbox("RequireGrace", false)

-- ---------------------------------------------------------------------------
section("respec")
-- ---------------------------------------------------------------------------
mock.advance(3000)
mock.setSandbox("AllowRespec", ERBalance.RESPEC.FREE)
p._md.ERLeveling.heldRunes = 0
p._md.ERLeveling.stats.vig = 20
p._md.ERLeveling.stats.str = 15
p._md.ERLeveling.totalSpent = 12345
local respec = ERNet.dispatch(p, "respec", {})
check("a free respec succeeds", respec.ok == true, respec.reason)
eq("attributes returned to the starting value", ERData.stat(p, "vig"), 10)
eq("every spent rune was refunded", ERData.runes(p), 12345)
eq("the level reset", ERData.level(p), 1)

mock.advance(3000)
mock.setSandbox("AllowRespec", ERBalance.RESPEC.NEVER)
local denied = ERNet.dispatch(p, "respec", {})
eq("respec can be disabled", denied.reason, "respec_disabled")

mock.advance(3000)
mock.setSandbox("AllowRespec", ERBalance.RESPEC.LARVAL_TEAR)
local noTear = ERNet.dispatch(p, "respec", {})
eq("respec without a Larval Tear is refused", noTear.reason, "no_larval_tear")

mock.advance(3000)
local tear = p:getInventory():AddItem(ERBalance.RESPEC_ITEM)
p._md.ERLeveling.totalSpent = 900
p._md.ERLeveling.heldRunes = 0
local withTear = ERNet.dispatch(p, "respec", { id = tear.getID() })
check("respec with a Larval Tear succeeds", withTear.ok == true, withTear.reason)
eq("the Larval Tear was consumed", p:getInventory():getCountTypeRecurse("LarvalTear"), 0)
eq("the refund landed", ERData.runes(p), 900)
mock.clearSandbox()
mock.setSandbox("RequireGrace", false)

-- ---------------------------------------------------------------------------
section("consumables")
-- ---------------------------------------------------------------------------
mock.advance(3000)
p._md.ERLeveling.heldRunes = 0
local arc = p:getInventory():AddItem("ERLeveling.RuneArc")
local consumed = ERNet.dispatch(p, "consumeRune",
    { fullType = "ERLeveling.RuneArc", id = arc.getID() })
check("absorbing a Rune Arc succeeds", consumed.ok == true, consumed.reason)
eq("a Rune Arc is worth 500", ERData.runes(p), 500)
eq("the item was destroyed", p:getInventory():getCountTypeRecurse("RuneArc"), 0)

mock.advance(3000)
local bogus = ERNet.dispatch(p, "consumeRune", { fullType = "Base.Hammer" })
eq("an unknown item is refused", bogus.reason, "unknown_item")

-- ---------------------------------------------------------------------------
section("death and bloodstains")
-- ---------------------------------------------------------------------------
mock.resetGlobal()
p._md.ERLeveling.heldRunes = 3000
p:setPos(500, 600, 0)
ERBloodstain.onDeath(p)
eq("death strips the carried runes", ERData.runes(p), 0)

local stain = ERBloodstain.forPlayer(p)
check("a bloodstain was created", stain ~= nil)
eq("the bloodstain holds every dropped rune", stain.runes, 3000)
eq("the bloodstain is at the death square x", stain.x, 500)
eq("the bloodstain is at the death square y", stain.y, 600)

-- Reclaiming from too far away is refused; walking back works (M4).
p:setPos(520, 600, 0)
local tooFar = ERNet.dispatch(p, "reclaim", {})
eq("reclaiming from a distance is refused", tooFar.reason, "too_far")
eq("nothing was credited", ERData.runes(p), 0)

p:setPos(500.5, 600.5, 0)
local got = ERNet.dispatch(p, "reclaim", {})
check("reclaiming next to the bloodstain succeeds", got.ok == true, got.reason)
eq("exactly the dropped amount came back", ERData.runes(p), 3000)
check("the bloodstain is gone", ERBloodstain.forPlayer(p) == nil)

-- Dying twice destroys the first stain (PLAN.md 4.2).
mock.resetGlobal()
p._md.ERLeveling.heldRunes = 1000
p:setPos(10, 10, 0)
ERBloodstain.onDeath(p)
mock.advance(20000)
p._md.ERLeveling.heldRunes = 2000
p:setPos(90, 90, 0)
ERBloodstain.onDeath(p)
local only = ERBloodstain.forPlayer(p)
eq("only the newest bloodstain survives", only.x, 90)
eq("the newest bloodstain holds the newest runes", only.runes, 2000)

-- A repeat death report inside the dedupe window must not create a second stain
-- or steal a second batch of runes.
p._md.ERLeveling.heldRunes = 555
ERBloodstain.onDeath(p)
eq("a duplicate death report is ignored", ERData.runes(p), 555)

-- LoseRunesOnDeath partial drop.
mock.resetGlobal()
mock.advance(20000)
mock.setSandbox("LoseRunesOnDeath", 50)
p._md.ERLeveling.heldRunes = 1000
ERBloodstain.onDeath(p)
eq("a 50% loss keeps half", ERData.runes(p), 500)
eq("a 50% loss drops half", ERBloodstain.forPlayer(p).runes, 500)
mock.clearSandbox()
mock.setSandbox("RequireGrace", false)

-- No runes carried means no bloodstain at all.
mock.resetGlobal()
mock.advance(20000)
p._md.ERLeveling.heldRunes = 0
ERBloodstain.onDeath(p)
check("dying broke leaves no bloodstain", ERBloodstain.forPlayer(p) == nil)

-- ---------------------------------------------------------------------------
section("death survives a change of character")
-- ---------------------------------------------------------------------------
-- Reported from a real game: dying dropped no runes, left nothing to collect,
-- and reset every attribute. All three came from the player key changing when
-- the character did.
mock.resetGlobal()
mock.advance(20000)
mock.clearSandbox()
mock.setSandbox("RequireGrace", false)

p._md.ERLeveling.heldRunes = 4000
p._md.ERLeveling.stats.vig = 25
p._md.ERLeveling.stats.str = 18
p._md.ERLeveling.totalSpent = 9999
p:setPos(300, 400, 0)
ERBloodstain.onDeath(p)

-- The survivor who wakes up next is a different character object with a
-- different name, in the same player slot.
local nextLife = mock.newPlayer("Someone Else Entirely", 300, 400, 0)
mock.players[0] = nextLife

local stain = ERBloodstain.forPlayer(nextLife)
check("the next character can see the bloodstain", stain ~= nil)
if stain then
    eq("it holds everything the last one was carrying", stain.runes, 4000)
    eq("it is where they fell (x)", stain.x, 300)
    eq("it is where they fell (y)", stain.y, 400)
end

mock.setSandbox("KeepStatsOnDeath", true)
ERBloodstain.onCreatePlayer(0, nextLife)
eq("attributes carried across, as Elden Ring does", ERData.stat(nextLife, "vig"), 25)
eq("and the second one too", ERData.stat(nextLife, "str"), 18)
eq("runes spent are remembered for a respec", ERData.get(nextLife).totalSpent, 9999)

nextLife:setPos(300.5, 400.5, 0)
local got = ERNet.dispatch(nextLife, "reclaim", {})
check("the next character can reclaim it", got.ok == true, got.reason)
eq("exactly what was dropped comes back", ERData.runes(nextLife), 4000)

-- With the option off, a death should still cost the attributes.
mock.resetGlobal()
mock.advance(20000)
mock.setSandbox("KeepStatsOnDeath", false)
local third = mock.newPlayer("Third Survivor", 10, 10, 0)
mock.players[0] = third
ERBloodstain.onCreatePlayer(0, third)
eq("with the option off, attributes start fresh", ERData.stat(third, "vig"), 10)

mock.players[0] = p
mock.clearSandbox()
mock.setSandbox("RequireGrace", false)

-- ---------------------------------------------------------------------------
section("a failing handler stops being called")
-- ---------------------------------------------------------------------------
-- The log flood the reporter kept seeing. Whatever the cause, a handler that
-- keeps throwing must switch itself off rather than write a stack trace forever.
local calls = 0
ERCompat.onEvent("EveryTenMinutes", function()
    calls = calls + 1
    error("always fails")
end)
for _ = 1, 30 do mock.fire("EveryTenMinutes") end
check("the handler is abandoned after a few failures", calls <= 5, calls)
check("it really did try before giving up", calls >= 1, calls)

local before = calls
for _ = 1, 20 do mock.fire("EveryTenMinutes") end
eq("and is never called again", calls, before)

-- ---------------------------------------------------------------------------
section("empty and edge states")
-- ---------------------------------------------------------------------------
eq("no player yields safe defaults", ERData.get(nil).heldRunes, 0)
eq("keyFor(nil) is nil", ERData.keyFor(nil), nil)
eq("compass points north-east", ERUtil.compass(0, 0, 100, -100), "NE")
eq("compass points due west", ERUtil.compass(0, 0, -100, 0), "W")
eq("compass collapses at zero distance", ERUtil.compass(5, 5, 5, 5), "HERE")
eq("wrap of an empty string is empty", #ERUtil.wrap("", 100, nil), 0)
eq("clamp holds the ceiling", ERUtil.clamp(500, 0, 10), 10)
eq("clamp survives nil", ERUtil.clamp(nil, 3, 10), 3)
check("an unknown effect returns zero, not an error",
      ERStats.effect("nope", "alsonope", 50) == 0)
check("derived() copes with an empty stat table",
      type(ERStats.derived({})) == "table")
local unknownCmd = ERNet.dispatch(p, "notARealCommand", {})
check("an unknown command returns nil rather than erroring", unknownCmd == nil)

-- ---------------------------------------------------------------------------
section("API probing does not flood the log")
-- ---------------------------------------------------------------------------
-- Regression test for the console flood. Project Zomboid logs a Java exception
-- even when a Lua pcall catches it, so every failed probe costs ~30 lines of
-- stack trace. A probe on a per-tick path must therefore fail at most ONCE.

local attempts = 0
local missing = setmetatable({}, {
    __index = function(_, k)
        attempts = attempts + 1
        error("attempted index: " .. tostring(k) .. " of non-table")
    end,
})

local okCall = ERCompat.call(missing, "noSuchMethod")
eq("calling a missing member reports failure", okCall, false)
eq("the first call actually attempts it", attempts, 1)

for _ = 1, 50 do ERCompat.call(missing, "noSuchMethod") end
eq("fifty more calls never attempt it again", attempts, 1)
eq("has() reports the member missing once we know", ERCompat.has(missing, "noSuchMethod"), false)

-- A member that works must not be penalised, and must keep returning its value.
local working = { getEndurance = function(self) return 0.75 end }
local okE, endurance = ERCompat.call(working, "getEndurance")
check("a working member succeeds", okE == true)
eq("a working member returns its value", endurance, 0.75)
eq("a working member stays available", ERCompat.has(working, "getEndurance"), true)

-- A member missing on one class must not be written off on another. This is the
-- Site of Grace case: most world objects have no isLit(), campfires do.
local noLit = setmetatable({}, { __index = function(_, k) error("no " .. k) end })
local hasLit = { isLit = function(self) return true end }
ERCompat.call(noLit, "isLit")
local okLit, lit = ERCompat.call(hasLit, "isLit")
check("a member missing elsewhere is still found here", okLit == true and lit == true)

-- The same trap on the two hottest scanning paths: ERGrace reads members from
-- every object on up to 49 squares twice a second, and the body-part loops run
-- seventeen times a pass on two timers. Both must probe through ERCompat, whose
-- blacklist makes a missing member cost one trace rather than thousands.
check("Grace probes members through ERCompat, not bare pcall", (function()
    local f = io.open(ROOT .. "shared/ERLeveling_Grace.lua", "r")
    if not f then return false end
    local body = f:read("*a"); f:close()
    -- The members that genuinely may be absent must not be read by bare pcall.
    for _, risky in ipairs({ "getSprite", "getModData", "getWorldObjects", "getObjects" }) do
        if string.find(body, "pcall(function() return obj:" .. risky, 1, true)
           or string.find(body, "pcall(function() return square:" .. risky, 1, true) then
            return false
        end
    end
    return true
end)())

check("body-part types are resolved once, not per iteration", (function()
    local f = io.open(ROOT .. "client/ERLeveling_Effects.lua", "r")
    if not f then return false end
    local body = f:read("*a"); f:close()
    -- Match the call syntax, not the word, so the comment explaining the rule
    -- does not trip its own test. The call belongs in the resolver and nowhere
    -- else, so exactly one occurrence.
    local _, n = string.gsub(body, "BodyPartType%.FromIndex%(", "")
    return n == 1
end)())

-- The flood came from deriving a cache key with obj:getClass():getName(), which
-- Kahlua cannot index. Nothing in the mod may call getClass() again.
check("no source file calls getClass()", (function()
    local paths = {
        "shared/ERLeveling_Compat.lua", "shared/ERLeveling_Data.lua",
        "shared/ERLeveling_Grace.lua", "shared/ERLeveling_Util.lua",
        "server/ERLeveling_Runes.lua", "server/ERLeveling_Bloodstain.lua",
        "server/ERLeveling_ServerCommands.lua",
    }
    for _, rel in ipairs(paths) do
        local f = io.open(ROOT .. rel, "r")
        if f then
            local body = f:read("*a")
            f:close()
            -- Match the call syntax, not the word, so the comments explaining
            -- why it is banned do not trip their own test.
            if string.find(body, ":getClass(", 1, true) then return false end
        end
    end
    return true
end)())

-- ---------------------------------------------------------------------------
section("UI crash containment")
-- ---------------------------------------------------------------------------
-- Regression test for the bug that made the game unclickable: an error thrown
-- from one of our render methods reached Project Zomboid's UI loop, filling the
-- console at frame rate and stopping mouse dispatch for the whole game.
-- ERUI.protect must make that impossible.
ERClient = ERClient or {}
dofile(ROOT .. "client/UI/ERUI.lua")

local Widget = { Type = "TestWidget" }
Widget.__index = Widget
function Widget:render() error("boom") end
function Widget:onMouseDown(x, y) error("boom") end
function Widget:prerender() return "fine" end

ERUI.protect(Widget, ERUI.ENTRY_POINTS)
local w = setmetatable({}, Widget)

local ok = pcall(function() w:render() end)
check("a throwing render does not escape into the engine", ok == true)
local ok2, consumed = pcall(function() return w:onMouseDown(1, 1) end)
check("a throwing mouse handler does not escape", ok2 == true)
eq("a failed mouse handler reports the click as unconsumed", consumed, false)
eq("a healthy method still returns its value", w:prerender(), "fine")

check("protect is idempotent", (function()
    ERUI.protect(Widget, ERUI.ENTRY_POINTS)
    return pcall(function() w:render() end) == true
end)())

-- Persistent failure must switch the interface off rather than keep spamming.
for _ = 1, 40 do pcall(function() w:render() end) end
check("persistent UI errors disable the interface", ERUI.disabled == true)
eq("a disabled interface stops calling through", w:prerender(), false)

-- Gameplay must be untouched by a disabled interface.
p._md.ERLeveling.heldRunes = 0
ERRunes.credit(p, 25, "kill")
eq("runes still credit with the interface disabled", ERData.runes(p), 25)
ERUI.disabled = false

print("")
print(string.rep("=", 62))
print(string.format("%d checks, %d failures", checks, failures))
print(string.rep("=", 62))
os.exit(failures == 0 and 0 or 1)
