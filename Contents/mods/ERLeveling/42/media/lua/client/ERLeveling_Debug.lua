--[[
    ERLeveling_Debug.lua
    --------------------
    Console helpers (PLAN.md 14). Ships with the mod but every command is refused
    server-side unless the game is in debug mode (-debug), the DebugCommands
    sandbox option is on, or the caller is a server admin.

    Use from the in-game Lua console:
        ERDebug.give(5000)
        ERDebug.setStat("str", 60)
        ERDebug.dump()
        ERDebug.costTable(1, 60)
        ERDebug.simulateDeath()
        ERDebug.grace()
]]

ERDebug = ERDebug or {}

local function send(action, extra)
    local p = ERClient.player(0)
    if p == nil then print("[ERDebug] no player.") return end
    local args = { action = action }
    if extra then for k, v in pairs(extra) do args[k] = v end end
    ERNet.request(p, "debug", args)
end

function ERDebug.give(n)          send("give", { amount = n }) end
function ERDebug.setRunes(n)      send("setRunes", { amount = n }) end
function ERDebug.setStat(key, v)  send("setStat", { stat = key, value = v }) end
function ERDebug.simulateDeath()  send("simulateDeath") end
function ERDebug.revokePerks()    send("revokePerks") end
function ERDebug.reset()          send("reset") end

--- Print the full data model plus every derived value.
function ERDebug.dump()
    local p = ERClient.player(0)
    if p == nil then print("[ERDebug] no player.") return end
    local d = ERData.get(p)
    print("=== ERLeveling dump ===")
    print(" level        : " .. tostring(ERLevel.fromStats(d.stats)))
    print(" heldRunes    : " .. tostring(d.heldRunes))
    print(" totalEarned  : " .. tostring(d.totalEarned))
    print(" totalSpent   : " .. tostring(d.totalSpent))
    print(" deaths       : " .. tostring(d.deaths))
    print(" grantedPerks : Strength=" .. tostring(d.grantedPerks.Strength)
          .. " Fitness=" .. tostring(d.grantedPerks.Fitness))
    print(" nextLevelCost: " .. tostring(ERLevel.cost(ERLevel.fromStats(d.stats))))
    print(" --- stats ---")
    for i = 1, #ERBalance.STAT_ORDER do
        local k = ERBalance.STAT_ORDER[i]
        print(string.format("  %-4s %3d   scale=%.3f  progress=%.3f", k, d.stats[k] or 0,
                            ERStats.scale(d.stats[k] or 0),
                            ERStats.progress(d.stats[k] or 0)))
    end
    print(" --- derived ---")
    local derived = ERStats.derived(d.stats)
    local keys = {}
    for k in pairs(derived) do table.insert(keys, k) end
    table.sort(keys)
    for i = 1, #keys do
        print(string.format("  %-16s %.4f", keys[i], derived[keys[i]]))
    end
    print(" --- grace ---")
    local grace, reason = ERGrace.check(p)
    print("  atGrace=" .. tostring(grace) .. " reason=" .. tostring(reason))
    local rec = ERClient.bloodstain(p)
    if rec then
        print(" --- bloodstain ---")
        print(string.format("  x=%d y=%d z=%d runes=%d", rec.x or 0, rec.y or 0,
                            rec.z or 0, rec.runes or 0))
    end
    print("=======================")
end

--- Print the cost curve so tuning is visible (PLAN.md 3.3).
function ERDebug.costTable(from, to)
    from = from or 1
    to = to or 100
    local total = 0
    print("=== ERLeveling cost table (preset " .. tostring(ERBalance.sv("CostPreset")) .. ") ===")
    for level = from, to do
        local c = ERLevel.cost(level)
        total = total + c
        if level % 5 == 0 or level == from or level <= 10 then
            print(string.format("  L%-4d -> L%-4d  %10s   cumulative %12s",
                  level, level + 1, ERStats.comma(c), ERStats.comma(total)))
        end
    end
    print("=======================")
end

--- Explain the Grace verdict (PLAN.md 14).
function ERDebug.grace()
    local p = ERClient.player(0)
    if p == nil then print("[ERDebug] no player.") return end
    local grace, reason = ERGrace.check(p)
    print("[ERDebug] atGrace=" .. tostring(grace) .. "  reason=" .. tostring(reason))
    print("[ERDebug] RequireGrace=" .. tostring(ERBalance.sv("RequireGrace"))
          .. "  radii: campfire=" .. ERBalance.GRACE.campfireRadius
          .. " fireplace=" .. ERBalance.GRACE.fireplaceRadius
          .. " idol=" .. ERBalance.GRACE.idolRadius)
    if not grace then
        print("[ERDebug] no lit campfire, fireplace, stove or Grace Idol in range, "
              .. "and you are not resting.")
    end
end

--- Report which probed APIs are missing on this build.
function ERDebug.compat()
    ERCompat._reported = false
    ERCompat.report()
end
