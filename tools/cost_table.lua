--[[
    cost_table.lua
    --------------
    Prints the level cost curve outside the game, so tuning is visible without
    launching Project Zomboid (PLAN.md 3.3: "Include a unit-test-ish Lua scratch
    script that prints the cost table for levels 1-150 so tuning is visible").

    Run from the repository root:
        lua tools/cost_table.lua              # default preset
        lua tools/cost_table.lua authentic    # Elden Ring's real formula
        lua tools/cost_table.lua 2.0 2.4 50 40

    It loads the shipped ERLeveling_Balance.lua and ERLeveling_Formulas.lua, so
    the numbers it prints are the numbers the mod uses.
]]

local MOD = "Contents/mods/ERLeveling/media/lua/shared/"

-- Minimal stand-ins for the two game globals the shared files touch at load time.
ERCompat = {
    guard = function(_, fn, ...) return pcall(fn, ...) end,
}

dofile(MOD .. "ERLeveling_Balance.lua")
dofile(MOD .. "ERLeveling_Formulas.lua")

-- Command-line overrides.
local args = { ... }
if args[1] == "authentic" then
    ERBalance.SANDBOX_DEFAULTS.CostPreset = ERBalance.COST_PRESET.AUTHENTIC
elseif args[1] ~= nil then
    ERBalance.SANDBOX_DEFAULTS.CostA    = tonumber(args[1]) or ERBalance.SANDBOX_DEFAULTS.CostA
    ERBalance.SANDBOX_DEFAULTS.CostB    = tonumber(args[2]) or ERBalance.SANDBOX_DEFAULTS.CostB
    ERBalance.SANDBOX_DEFAULTS.CostC    = tonumber(args[3]) or ERBalance.SANDBOX_DEFAULTS.CostC
    ERBalance.SANDBOX_DEFAULTS.CostBase = tonumber(args[4]) or ERBalance.SANDBOX_DEFAULTS.CostBase
end

local presetNames = { "Lands Between Lite", "Authentic (Brutal)", "Custom" }
print(string.format("Cost preset: %s   (A=%.2f B=%.2f C=%.1f Base=%.1f)",
      presetNames[ERBalance.sv("CostPreset")] or "?",
      ERBalance.sv("CostA"), ERBalance.sv("CostB"),
      ERBalance.sv("CostC"), ERBalance.sv("CostBase")))
print(string.rep("-", 62))
print(string.format("%-8s %14s %18s %14s", "level", "cost", "cumulative", "kills*"))
print(string.rep("-", 62))

-- * kills assumes the default 8 runes per standard zombie, no multipliers.
local RUNES_PER_KILL = ERBalance.RUNES.base
local total = 0
for level = 1, 150 do
    local cost = ERLevel.cost(level)
    total = total + cost
    if level <= 10 or level % 5 == 0 then
        print(string.format("%-8d %14s %18s %14s",
              level, ERStats.comma(cost), ERStats.comma(total),
              ERStats.comma(math.ceil(total / RUNES_PER_KILL))))
    end
end
print(string.rep("-", 62))
print("* cumulative zombie kills to reach that level from level 1, at "
      .. RUNES_PER_KILL .. " runes per kill and no Arcane bonus.")

-- Soft-cap curve, so the two halves of the tuning are visible side by side.
print("")
print("Attribute soft-cap curve (ERStats.scale):")
for _, v in ipairs({ 1, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 99 }) do
    local s = ERStats.scale(v)
    local bar = string.rep("#", math.floor(s * 40))
    print(string.format("  %3d  %.3f  %s", v, s, bar))
end
