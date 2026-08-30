# TARNISHED — Elden Ring Leveling for Project Zomboid

**Mod ID:** `ERLeveling` · **Builds:** 42 and 41 · **Multiplayer:** yes, server-authoritative

Killing zombies drops **Runes**. Runes are a currency you carry on your body. You
spend them at a **Site of Grace** to raise eight Elden Ring attributes, each of
which does something real to your survivor. When you die you drop every rune you
were carrying at the spot you fell, marked by a **bloodstain**. Walk back and
reclaim them. Die again before you do, and they are gone forever.

The whole interface lives in the vanilla character info window: a rune counter
along the bottom of the **Health** tab, and a new **Runes** tab that is the
level-up screen.

---

## Install

### Steam Workshop
Subscribe, then enable **Tarnished — Elden Ring Leveling** in the mod list.

### Manual
Copy `Contents/mods/ERLeveling` into your Zomboid mods folder:

| OS | Path |
|---|---|
| Windows | `C:\Users\<you>\Zomboid\mods\` |
| Linux | `~/Zomboid/mods/` |
| macOS | `~/Zomboid/mods/` |

Copy the inner **`ERLeveling`** folder, not `Contents`. You should end up with
exactly this, with `mod.info` one level down and nothing in between:

```
Zomboid/mods/ERLeveling/
├── mod.info          <- Build 41 reads this
├── poster.png
├── media/            <- Build 41 content
└── 42/
    ├── mod.info      <- Build 42 reads this
    ├── poster.png
    └── media/        <- Build 42 content
```

Enable the mod, then start a **new game or load any save** — it initialises
cleanly on an existing character.

### The mod doesn't appear in the mod list

The list is built by scanning `Zomboid/mods/*/mod.info`, so a mod that is missing
entirely is almost always one of these three:

1. **Nested one level too deep.** If you see
   `Zomboid/mods/ERLeveling/ERLeveling/mod.info` or
   `Zomboid/mods/ERLeveling/Contents/...`, the game never finds `mod.info`. Move
   the contents up one level. This is by far the most common cause — extracting a
   GitHub zip produces a wrapper folder named after the branch.
2. **Wrong Zomboid folder.** It is your *user* folder
   (`C:\Users\<you>\Zomboid\mods\`), not the Steam install directory.
3. **Build 42 filtering it out.** B42's mod list can hide mods that carry no
   `pzversion`. Both `mod.info` files declare one, so make sure the `42/` folder
   above actually came across in the copy.

Still missing? Open `Zomboid/console.txt` and search for `ERLeveling` — if the
game saw the folder at all it says so there.

### Dedicated server
Add `ERLeveling` to `Mods=` in your server `.ini`. The mod is fully
server-authoritative: the server owns every rune balance, every level-up
transaction and the bloodstain registry. Clients only draw the interface.

---

## Playing it

| | |
|---|---|
| **Open the Runes tab** | `P` (rebindable in Options → Key Bindings), or the character info window |
| **Stage a point** | Click an attribute, then `+` / `−`, the mouse wheel, or ←/→ |
| **Change selection** | ↑/↓ or click |
| **Commit** | `LEVEL UP`, or `Enter` |
| **Discard** | `RESET` |

Nothing is spent until you commit, and the DERIVED panel previews what you are
about to buy before you pay for it.

### Sites of Grace

You can only spend runes at a Grace. A square counts when any of these is true:

* a **lit campfire** within 3 tiles
* a **lit fireplace, stove or oven** within 2 tiles
* a **Grace Idol** within 4 tiles, placed or carried
* you are **resting** — sleeping or sitting

The Runes tab header reads `AT A SITE OF GRACE` in gold when you are, and
`AWAY FROM GRACE` in grey when you are not. Turn the whole requirement off with
the `RequireGrace` sandbox option.

### Dying

You drop every rune you were carrying (configurable) and a bloodstain marks the
spot. Walk within two tiles and it returns to you automatically, or right-click →
**Reclaim Runes**. The Runes tab shows the distance and bearing, and an on-screen
chevron points the way.

**You get one bloodstain.** Dying again before you reach it destroys the first
one, exactly like Elden Ring.

---

## The eight attributes

| | What it does |
|---|---|
| **Vigor** | Reduces the damage you keep from every wound; knits injuries closed over time |
| **Mind** | Blunts panic, stress and unhappiness; sharpens your aim |
| **Endurance** | Slows how fast you tire, speeds recovery, raises carry weight |
| **Strength** | More melee damage, more carry weight |
| **Dexterity** | Faster recovery between swings, quicker reloads, gentler weapon wear |
| **Intelligence** | Every skill you practise is learned faster |
| **Faith** | Dressings and medicine work harder; sickness loosens its grip |
| **Arcane** | More runes from the dead; the world yields a little more |

Attributes run **1–99** on their own scale and are **not** Project Zomboid perks —
your normal skills are untouched. The curve uses Elden Ring's soft caps: the first
twenty points are transformative, the last twenty are a rounding error.

A fresh character sits at 10 in everything and is **exactly vanilla** — no bonuses
until you buy them.

### Faith does not cure the zombie infection

Nothing in this mod does. A bite is still a bite.

---

## Items

| Item | Effect | Found in |
|---|---|---|
| **Rune Arc** | 500 runes | Churches, survival gear |
| **Golden Rune [1] / [2] / [3]** | 200 / 800 / 2,500 runes | Dressers, desks, safes, bank vaults |
| **Larval Tear** | **Rebirth** — resets every attribute and refunds every rune you ever spent | Bank vaults, safehouse loot |
| **Grace Idol** | Makes anywhere a Site of Grace | Camping stores, church storage — or forge one |

**Forging a Grace Idol:** with a Pipe or Metal Bar, a Candle, a Sheet and
Metalworking 2, right-click in your inventory → **Forge Grace Idol**.

---

## Sandbox options

All under the **Elden Ring Leveling** page in sandbox settings.

### Progression
| Option | Default | What it does |
|---|---|---|
| `RuneMultiplier` | 1.0 | Scales every rune payout. 2.0 doubles progression speed. |
| `CostPreset` | Lands Between Lite | `Authentic (Brutal)` uses Elden Ring's real level formula — calibrated for a 300-hour game and punishing here. `Custom` uses the four values below. |
| `CostA` / `CostB` / `CostC` / `CostBase` | 1.6 / 2.2 / 40 / 40 | `cost = A × level^B + C × level + Base` |
| `StartingStat` | 10 | Where every attribute begins. All eight at this value is Level 1. |
| `MaxStat` | 99 | Hard cap per attribute. |
| `EffectStrength` | 1.0 | **The dial that matters.** Global scalar on every attribute effect. 0.5 keeps the flavour without changing difficulty; 2.0 is a power fantasy. |

### Death
| Option | Default | What it does |
|---|---|---|
| `RequireGrace` | on | Runes can only be spent at a Site of Grace. |
| `LoseRunesOnDeath` | 100% | How much of your carried runes drop. |
| `BloodstainPersists` | on | Dropped runes wait where you died. |
| `AnyoneCanLootBloodstain` | off | Multiplayer. Off means only you can reclaim your own. |
| `KeepStatsOnDeath` | off | Elden Ring says you keep your level; Project Zomboid says death is a new character. Off is the harder answer. |
| `AllowRespec` | Larval Tear only | `Never` / `Larval Tear only` / `Free`. |

### Loot and presentation
| Option | Default | What it does |
|---|---|---|
| `RuneArcSpawnRate` | 1.0 | Scales every rune item's spawn rate. 0 removes them. |
| `ShowYouDied` | on | The black fade and **YOU DIED** before the normal death screen. |
| `ShowHudCounter` | off | A persistent rune counter on the HUD. Off because the Zomboid HUD is crowded; the count is always on both panels anyway. |
| `EnableSounds` | on | Level-up and reclaim sounds. |
| `AllowPerkGrants` | on | Only used on builds without a direct carry-weight API. See below. |
| `DebugCommands` | off | Lets any player run `ERDebug` commands. Leave off on a public server. |

---

## Compatibility

* **Additive only.** No vanilla Lua file is copied or overwritten and no vanilla
  item is edited. Every hook wraps the original and calls it first, inside a
  `pcall` — if a hook breaks you lose the rune interface, never the health panel.
* **Every vanilla monkey-patch is in one file:** `media/lua/client/UI/ERHooks.lua`,
  each one naming the vanilla file and function it wraps and why. When a Project
  Zomboid update breaks this mod, that is the only file anyone needs to read.
* **Your normal skills are untouched.** Attributes are a separate system.
* **Carry weight** uses the engine's own API where it exists. Where it does not,
  the *server* grants at most +3 Strength and +2 Fitness, records exactly what it
  gave, and takes them back on a respec or `ERDebug.revokePerks()`. Set
  `AllowPerkGrants` to off to disable that path entirely.

### Removing the mod
Run `ERDebug.revokePerks()` (or respec) first if `AllowPerkGrants` was on, so any
granted perk levels are handed back. Everything else lives in `modData` and
disappears with the mod; saves stay loadable.

---

## Known issues

* Bloodstains have no marker on the in-game world map — the Runes tab readout and
  the on-screen chevron are the navigation aids.
* No custom audio ships with the mod. `ERBalance.SOUND` points at vanilla sound
  events; edit those three strings to use your own pack.
* Sprinter and critical-hit rune bonuses only apply on builds that expose the
  relevant checks. Run `ERDebug.compat()` to see what your build supports.
* The mod has been validated by an offline test suite and static analysis, but
  see `NOTES.md` §5 for exactly what has and has not been exercised in-game.

---

## For developers

```
PLAN.md      the specification this was built from
NOTES.md     every deviation from it, and why - read §0 first
tools/
  build.sh          parse-check, test, drift-check, then package
  sync_versioned.sh regenerate the Build 42 subtree from the root tree
  test_offline.lua  95 assertions against a mock game environment
  pz_mock.lua       that mock
  cost_table.lua    print the cost and soft-cap curves
  make_textures.py  regenerate every PNG the mod ships
```

```bash
lua5.4 tools/test_offline.lua     # 95 checks, 0 failures
lua5.4 tools/cost_table.lua       # tuning made visible
bash   tools/sync_versioned.sh    # regenerate the 42/ subtree from the root tree
bash   tools/build.sh --zip       # validate, test, package to dist/ERLeveling.zip
```

The root tree is the single source of truth; `42/` is generated from it. Edit the
root tree and re-run `sync_versioned.sh` — `build.sh` fails if the two drift.

In-game console helpers (need `-debug`, the `DebugCommands` option, or admin):

```lua
ERDebug.compat()          -- which APIs your build exposes: read this first
ERDebug.dump()            -- full data model plus every derived value
ERDebug.give(5000)
ERDebug.setStat("str", 60)
ERDebug.costTable(1, 60)
ERDebug.simulateDeath()   -- test the bloodstain flow without dying
ERDebug.grace()           -- why Grace detection is or is not triggering
ERDebug.revokePerks()
```

---

Built to `PLAN.md`. Elden Ring is FromSoftware's; this is a fan mod and is not
affiliated with FromSoftware or The Indie Stone.
