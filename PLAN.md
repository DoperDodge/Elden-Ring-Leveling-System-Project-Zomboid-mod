# PLAN.md — "TARNISHED" — Elden Ring Leveling for Project Zomboid

**Codename:** TARNISHED
**Mod ID:** `ERLeveling`
**Target:** Project Zomboid (Build 42 primary, Build 41 fallback)
**Author handle:** DoperDodge
**Implementing agent:** Claude Opus 5 via Claude Code CLI
**Doc status:** authoritative spec. If reality contradicts this doc, reality wins — but you must say so in `NOTES.md` before deviating.

---

## 0. What this mod is, in one paragraph

Killing zombies drops **Runes**. Runes are a currency you carry on your body. You spend them at a **Site of Grace** to raise eight Elden Ring stats (Vigor, Mind, Endurance, Strength, Dexterity, Intelligence, Faith, Arcane), each of which applies real mechanical effects to your Project Zomboid character. When you die, you drop every rune you were carrying at the spot you died, marked by a **bloodstain**. Walk back and reclaim them. Die again before you do, and they are gone forever. The entire interface lives inside the vanilla **Health panel** of the character info window, as a new tab plus a persistent rune counter, styled to look like Elden Ring's level-up screen.

---

## 1. Rules for the implementing agent (read these first)

1. **Verify before you write.** Section 2 is a mandatory reconnaissance phase. Every line in this doc tagged `[VERIFY]` is my best recollection of the PZ Lua/Java API and may be wrong or renamed in the installed build. Read the actual game source before relying on it.
2. **Never guess an API.** If a method isn't in the decompiled source or the vanilla Lua, do not call it. Find the real one or implement the effect a different way, and log the substitution in `NOTES.md`.
3. **Do not fight anti-cheat.** In multiplayer, changing perk levels or player stats client-side gets people kicked. See §9. Server authority is non-negotiable.
4. **Do not overwrite vanilla Lua files.** Hook and wrap. Never copy `ISHealthPanel.lua` into the mod and edit it — that breaks every other UI mod and every game patch.
5. **Incremental milestones.** Ship M0 working before starting M1. Each milestone in §13 has acceptance criteria; do not move on until they pass in-game.
6. **Commit per milestone** with the milestone tag in the message.
7. **No placeholder crashes.** Every unfinished path returns safely rather than erroring. A Lua error in PZ spams the console every tick and can soft-lock the UI.
8. **Write `NOTES.md`** as you go: verified API signatures, things this plan got wrong, tuning numbers you changed, open bugs.

---

## 2. Phase 0 — Reconnaissance (MANDATORY, do this before any code)

### 2.1 Locate the install

Typical Windows path:
```
C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid\
```
Vanilla Lua lives in `media/lua/{client,server,shared}/`. User mods live in:
```
C:\Users\<user>\Zomboid\mods\
```
Logs and Lua errors:
```
C:\Users\<user>\Zomboid\console.txt
C:\Users\<user>\Zomboid\Logs\
```

### 2.2 Determine the build

Read `ProjectZomboid/media/lua/shared/Definitions/` and the game version string. Then pick the mod folder layout:

- **Build 42:** `mods/ERLeveling/42/media/lua/...` with `mod.info` at `mods/ERLeveling/mod.info` and a `versionMin`/`pack` aware structure. B42 supports multiple versioned subfolders in one mod.
- **Build 41:** `mods/ERLeveling/media/lua/...` flat structure.

Detect it, build for it, and record which one in `NOTES.md`. Structure the repo so both can be produced from the same source if that's cheap; if it isn't, target B42 only and say so.

### 2.3 Files you must read before writing UI code

Read these in full and summarize each in `NOTES.md`:

```
media/lua/client/ISUI/ISCharacterInfoWindow.lua      -- the tabbed window; how tabs are registered
media/lua/client/ISUI/ISHealthPanel.lua              -- the Health tab; layout, render(), body part list
media/lua/client/ISUI/ISPanel.lua                    -- base panel: render, prerender, drawRect, drawText
media/lua/client/ISUI/ISUIElement.lua                -- base element lifecycle
media/lua/client/ISUI/ISTabPanel.lua                 -- addView / tab API
media/lua/client/ISUI/ISButton.lua
media/lua/client/ISUI/ISTickBox.lua
media/lua/client/ISUI/ISScrollingListBox.lua
media/lua/client/ISUI/ISModalDialog.lua
media/lua/client/ISUI/ISToolTip.lua
media/lua/client/ISUI/ISEquippedItem.lua             -- for HUD anchoring reference
media/lua/client/ISUI/ISKeyBindings.lua              -- how to append a keybind
media/lua/client/OptionScreens/                      -- sandbox option rendering reference
media/lua/shared/Sandbox/                            -- sandbox option definition format
media/lua/server/Items/SuburbsDistributions.lua      -- loot distribution pattern (for Rune Arc spawns)
```

Answer these questions explicitly in `NOTES.md`:

- What is the exact class name and constructor of the health tab, and how does `ISCharacterInfoWindow` register its tabs?
- Is there an existing hook/event for adding a tab, or must I wrap `createChildren`?
- What are the pixel dimensions of the character info window and the health panel's usable area?
- Does the window resize? Is there a `setWidth`/`onResize` path I must respect?
- Which font constants exist (`UIFont.Small`, `.Medium`, `.Large`, `.NewSmall`, `.NewMedium`?) and what does `getTextManager():MeasureStringX/Y` take?

### 2.4 API surface to verify

Confirm each of these exists with the signature shown. Mark ✅/❌/⚠️(different signature) in `NOTES.md`.

**Character & stats**
```lua
getPlayer()                                  -- IsoPlayer
player:getModData()                          -- table, persisted
player:getStats()                            -- Stats: endurance, fatigue, panic, stress, fitness?
player:getBodyDamage()                       -- BodyDamage
player:getBodyDamage():getOverallBodyHealth()
player:getBodyDamage():getBodyPart(BodyPartType.Torso_Upper)
player:getXp()                               -- PlayerXp
player:getXp():AddXP(Perks.Strength, 10)
player:getXp():getXP(Perks.Fitness)
player:getXp():setPerkBoost(Perks.Aiming, 2)
player:getPerkLevel(Perks.Strength)
player:LevelPerk(Perks.Strength)             -- [VERIFY] client-side use is anti-cheat risky in MP
player:getMaxWeight()
player:setMaxWeightBase(n)                   -- [VERIFY] may not exist; see §6 fallback
player:getRecoilDelay()
player:getNutrition()
player:getMoodles()
```

**Zombies & combat**
```lua
Events.OnZombieDead.Add(function(zombie) end)
zombie:getAttackedBy()                       -- [VERIFY] returns the killer character or nil
Events.OnHitZombie.Add(function(zombie, character, bodyPartType, handWeapon) end)
Events.OnWeaponHitCharacter.Add(function(wielder, character, weapon, damage) end)
Events.OnPlayerGetDamage.Add(function(player, damageType, damageAmount) end)  -- [VERIFY] can it mutate?
zombie:getHealth() / zombie:setHealth(n)
zombie:isCrawling() / zombie:isSkeleton()    -- [VERIFY] for rune value tiers
```

**Lifecycle events**
```lua
Events.OnGameStart.Add(fn)
Events.OnCreatePlayer.Add(function(playerIndex, player) end)
Events.OnPlayerDeath.Add(function(player) end)
Events.EveryOneMinute.Add(fn)
Events.EveryTenMinutes.Add(fn)
Events.OnPlayerUpdate.Add(function(player) end)   -- fires very often; keep work tiny
Events.OnTick.Add(fn)                              -- avoid unless necessary
Events.OnKeyPressed.Add(function(key) end)
Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldobjects, test) end)
Events.OnFillContainer.Add(function(roomName, containerType, container) end)
```

**World / items**
```lua
getCell():getGridSquare(x, y, z)
square:AddWorldInventoryItem(itemOrType, xoff, yoff, zoff)
player:getInventory():AddItem("ERLeveling.RuneArc")
InventoryItemFactory.CreateItem("ERLeveling.RuneArc")
getSpecificPlayer(0)
```

**Multiplayer**
```lua
isClient()      -- true on an MP client
isServer()      -- true on a dedicated server / host
sendClientCommand(player, "ERLeveling", "spendRunes", args)
Events.OnClientCommand.Add(function(module, command, player, args) end)   -- server side
sendServerCommand(player, "ERLeveling", "syncRunes", args)
Events.OnServerCommand.Add(function(module, command, args) end)           -- client side
ModData.getOrCreate("ERLeveling_Global")
ModData.transmit("ERLeveling_Global")
```

**UI**
```lua
ISPanel:derive("Name")
self:drawRect(x, y, w, h, a, r, g, b)
self:drawRectBorder(x, y, w, h, a, r, g, b)
self:drawText(text, x, y, r, g, b, a, font)
self:drawTextRight(...) / drawTextCentre(...)
self:drawTexture(texture, x, y, alpha, r, g, b)
self:drawTextureScaled(texture, x, y, w, h, a, r, g, b)
getTexture("media/textures/ERLeveling/rune.png")
getTextManager():MeasureStringX(UIFont.Small, "text")
getSoundManager():PlayWorldSound(...)  -- or player:playSound("ERLevelUp")
```

If any ❌ shows up, **stop and design around it**, don't fake it.

---

## 3. Core design — the eight stats

Stats are **mod-owned**, on their own 1–99 scale like Elden Ring. They are **not** PZ perk levels. This is deliberate: PZ perks cap at 10, are anti-cheat sensitive in MP, and are shared with every other mod. Keeping our stats separate means we can have a real ER-feeling level curve and apply effects as multipliers.

Starting value for every stat: **10** (sandbox configurable). Character Level = sum of all eight stats minus 79 (so a fresh character is Level 1 with 80 points spent... adjust so a fresh char reads **Level 1**; do the arithmetic in code, expose `baseStat` and derive).

### 3.1 Stat effects table

| Stat | PZ effect | Implementation approach | Notes |
|---|---|---|---|
| **Vigor** | Damage taken reduction; faster natural health regen | Hook `OnPlayerGetDamage` to scale incoming damage; if immutable, restore a fraction of body-part health immediately after damage lands. Regen: on `EveryTenMinutes`, heal body parts by a small amount scaled by Vigor. | `[VERIFY]` whether `OnPlayerGetDamage` can mutate. Fallback = post-hoc heal. |
| **Mind** | Panic and stress resistance; slower unhappiness gain; steadier aim | `EveryOneMinute`: read `player:getStats():getPanic()` and multiply down. Also `setPerkBoost(Perks.Aiming, n)` at breakpoints. | Keep the panic clamp gentle or it trivializes the game. |
| **Endurance** | Slower stamina drain, faster stamina recovery, higher carry weight | `OnPlayerUpdate`: if endurance dropped this tick, refund a fraction. Carry weight: see §6. | This is the workhorse stat; balance carefully. |
| **Strength** | Melee damage multiplier, carry weight, less push-back fail | On `OnWeaponHitCharacter`, apply bonus damage by directly reducing `zombie:getHealth()`. | Direct health subtraction is the reliable path if the damage arg is read-only. |
| **Dexterity** | Faster weapon swing recovery, faster reload, less weapon condition loss | Reduce `player:setRecoilDelay()` post-swing; boost `Perks.Reloading` via `setPerkBoost`; on weapon condition loss event, restore a fraction. | `[VERIFY]` condition-loss hook exists. |
| **Intelligence** | Skill XP multiplier, faster reading, faster crafting | Hook XP gain (`Events.AddXP` if it exists, else `setPerkBoost` on all perks at breakpoints) and multiply. | `[VERIFY]` `Events.AddXP`. |
| **Faith** | Healing item effectiveness, infection/food-poisoning resistance, faster moodle decay | Post-process bandage/pill application; scale `bodyPart:setBandaged` benefit; reduce sickness value on tick. | Explicitly does **not** cure zombification. Say so in the tooltip. |
| **Arcane** | Rune find rate, loot luck, better container rolls | Multiply rune drop value. For loot: on `OnFillContainer`, small chance to add one extra item from that room's distribution table. | Keep the loot effect subtle; it's easy to make this broken. |

### 3.2 Scaling formula

Elden Ring uses soft caps. Mirror that feel with a piecewise curve so early points feel great and late points feel earned:

```lua
-- returns 0.0 .. 1.0 "effectiveness" for a stat value
function ERStats.scale(value)
    local v = math.max(0, value - 1)
    if v <= 19 then        return v * 0.030                    -- 0.00 .. 0.570   (steep)
    elseif v <= 39 then    return 0.570 + (v - 19) * 0.014     -- .. 0.850        (soft cap 1)
    elseif v <= 59 then    return 0.850 + (v - 39) * 0.005     -- .. 0.950        (soft cap 2)
    else                   return 0.950 + (v - 59) * 0.00125   -- .. 1.000 at 99
    end
end
```

Every stat effect is then `effect = baseline + (maxBonus - baseline) * ERStats.scale(value)`, with `maxBonus` per stat in a single `Balance.lua` table. **All tuning numbers live in one file.** No magic numbers scattered through the codebase.

### 3.3 Level cost curve

Elden Ring's real formula (for reference, RL ≥ 12):

```
runes = 0.02 * (RL+81)^3 + 3.06 * (RL+81)^2 + 105.6 * (RL+81) - 895
```

That's calibrated for a 300-hour ARPG and would be absurd in PZ. Ship a **scaled** curve as default, and expose the authentic one as a sandbox preset called `Authentic (Brutal)`.

```lua
-- default "Lands Between Lite"
function ERLevel.cost(currentLevel)
    local n = currentLevel
    return math.floor(SandboxVars.ERLeveling.CostA * (n ^ SandboxVars.ERLeveling.CostB)
                    + SandboxVars.ERLeveling.CostC * n
                    + SandboxVars.ERLeveling.CostBase)
end
-- defaults: CostA = 1.6, CostB = 2.2, CostC = 40, CostBase = 40
-- L1->2 ≈ 82, L10->11 ≈ 700, L30->31 ≈ 3.6k, L60->61 ≈ 15k
```

Include a unit-test-ish Lua scratch script that prints the cost table for levels 1–150 so tuning is visible.

---

## 4. Runes — the currency

### 4.1 Sources

| Source | Base runes | Notes |
|---|---|---|
| Standard zombie kill | 8 | |
| Crawler | 5 | |
| Sprinter (if sandbox) | 14 | Detect via zombie speed/sandbox, `[VERIFY]` |
| Skeleton / already-dead | 0 | Don't reward corpse-hitting |
| Melee headshot / critical | ×1.5 | `[VERIFY]` crit detection |
| Firearm kill | ×0.85 | Slight nudge toward melee |
| Killing while injured (below 60% health) | ×1.2 | "Desperation" bonus, ER-flavored |
| Rune Arc consumable | 500 | Craftable/lootable item |
| Golden Rune I/II/III items | 200 / 800 / 2500 | Rare loot, "use" to consume |
| First kill of a horde (10+ nearby) | ×1.3 | Optional, stretch |

All multipliers are sandbox-configurable via a single `RuneMultiplier` global plus per-source toggles.

**Attribution rule:** on `OnZombieDead`, resolve the killer via `zombie:getAttackedBy()`. If it returns nil or a non-player, award nothing. In MP, award only to the resolving player, and do it **server-side**.

### 4.2 Death and the bloodstain

This is the mechanic people will judge the mod on. Get it right.

On `OnPlayerDeath`:
1. Read `heldRunes` from player modData.
2. If `heldRunes <= 0`, no bloodstain.
3. Record `{x, y, z, runes, timestamp, ownerId}` in the **global** mod data table `ERLeveling_Bloodstains` (one active bloodstain per player — a new death **destroys** the old one, exactly like Elden Ring).
4. Set `heldRunes = 0`.
5. Spawn a visual marker on the square (§4.3).
6. On respawn (new character), the bloodstain persists and is recoverable by that same player only (sandbox toggle: `AnyoneCanLoot`).

**Recovery:** walking within 1 tile auto-reclaims (ER behavior), plays the recovery sound, shows the `+N RUNES` popup. Sandbox alternative: require right-click → "Reclaim Runes".

**Map marker:** if a map API is available `[VERIFY]`, draw a bloodstain marker on the in-game world map at the death location. Otherwise show distance+direction text on the Runes tab ("Bloodstain: 340 tiles NE") — which is honestly more useful in PZ's scale anyway. Ship both if possible.

### 4.3 Bloodstain visuals

Preferred: a floor overlay texture drawn at the square (a dim gold pool with a slow pulse). If a proper world-decal API isn't available `[VERIFY]`, fall back in this order:
1. Spawn a custom `Moveable`/world item with a gold icon on the square.
2. Draw a screen-space marker via `Events.OnPostRender` when the square is on screen, projecting world→screen `[VERIFY]` `IsoUtils.XToScreen` / `ISUIElement` coordinate helpers.
3. Text-only distance indicator in the UI.

Document which one you used.

---

## 5. Sites of Grace

Leveling requires a Grace by default (sandbox toggle `RequireGrace`, default **true**).

**A square counts as a Grace if any of these are true:**
- A lit campfire within 3 tiles
- A lit fireplace/stove within 2 tiles
- A **Grace Idol** (custom placeable, see below) within 4 tiles
- The player is sitting/sleeping in a bed `[VERIFY]` sit/sleep state check

**Grace Idol** (stretch but high value): a craftable placeable item.
- Recipe: 1 × Metal Bar or Pipe + 1 × Candle + 1 × Sheet + Metalworking 2. Tune later.
- Uses a re-textured existing placeable tile if adding a new tile sprite is too heavy — **check whether custom tiles require TileZed**; if so, reuse a vanilla candle/lamp tile and just gate the mechanic on the custom item existing in a nearby container/floor. Document the compromise.
- When within range, a soft gold glow overlay renders on screen edges and the Runes tab header changes from "AWAY FROM GRACE" to "AT A SITE OF GRACE".

**Grace bonus (optional, sandbox):** resting at a Grace for 1 in-game hour restores a small amount of health and clears a fraction of fatigue/stress. Tempting but it changes PZ's core loop — default it **off**.

---

## 6. The carry-weight problem (worked example of how to handle `[VERIFY]` failures)

Carry weight in PZ derives from the Strength perk. Three possible implementations, in order of preference:

1. **`player:setMaxWeightBase(n)`** if it exists — clean, no perk changes, no anti-cheat.
2. **`player:getXp():setPerkBoost(Perks.Strength, n)`** — check whether this actually affects carry weight or only XP rate. Probably only XP rate, so likely useless here.
3. **Server-authoritative perk levels:** at Endurance/Strength breakpoints (e.g. every 12 points), grant one real Strength perk level via a server command. Cap the granted total at +3 so we never blow past vanilla balance, and **store how many levels we granted** in modData so we can revoke them cleanly on uninstall or respec.

Pick the highest one that actually works. Write down why in `NOTES.md`. Apply the same decision procedure to every other `[VERIFY]` in this doc.

---

## 7. UI specification

### 7.1 Placement

Two surfaces, both anchored to the health area as requested:

**A. Rune counter strip — inside the Health panel.**
A slim bar pinned to the bottom of the existing Health tab, below the body-part list. It shows: rune icon, current held runes, current character level. It renders even when the tab content scrolls. Implemented by wrapping `ISHealthPanel:createChildren` and `ISHealthPanel:render` — append our child panel, never replace their logic.

**B. "Runes" tab — a new tab in the character info window.**
Full level-up interface, sitting alongside Health / Info / Skills. Registered by wrapping `ISCharacterInfoWindow:createChildren` and calling the same `addView`-style API the vanilla tabs use.

Also bind a keybind (default **`P`**) that opens the character info window directly on the Runes tab. Append to the keybinding table so it appears in Options → Key Bindings.

### 7.2 Runes tab layout

```
┌──────────────────────────────────────────────────────────┐
│  ◆  LEVEL                                    12          │  <- big serif-ish, gold
│     RUNES HELD                            4,217          │
│     RUNES NEEDED                            892          │  <- red if unaffordable
│                                                          │
│  ── AT A SITE OF GRACE ───────────────────────────────   │  <- gold when true,
│                                                          │     grey "AWAY FROM GRACE" when false
│   VIGOR          14  ▸ 15      ████████░░░░░░░░  +HP     │
│   MIND           10            █████░░░░░░░░░░░          │
│   ENDURANCE      13  ▸ 14      ███████░░░░░░░░░  +Stam   │
│   STRENGTH       16  ▸ 17      █████████░░░░░░░  +Dmg    │
│   DEXTERITY      11            ██████░░░░░░░░░░          │
│   INTELLIGENCE    9            ████░░░░░░░░░░░░          │
│   FAITH          10            █████░░░░░░░░░░░          │
│   ARCANE          8            ████░░░░░░░░░░░░          │
│                                                          │
│  ── DERIVED ─────────────────────────────────────────    │
│   Damage Negation   8.4%      Carry Weight     +6.0      │
│   Stamina Drain    -19%       Melee Damage    +23%       │
│   Rune Find        +12%       Healing         +15%       │
│                                                          │
│           [ − ]   [ + ]        [ LEVEL UP ]  [ RESET ]   │
│                                                          │
│  Bloodstain: 412 tiles NE — 4,900 runes                  │  <- only if one exists
└──────────────────────────────────────────────────────────┘
```

Behavior:
- Selecting a row highlights it; `+`/`−` (and mouse wheel, and arrow keys) stage points.
- Staged changes show as `14 ▸ 15` and update the "RUNES NEEDED" total live.
- `LEVEL UP` commits, `RESET` clears staging. Nothing is spent until commit.
- If not at a Grace, `LEVEL UP` is disabled and the button tooltip explains why.
- Hovering a stat name shows a tooltip with its full effect description and current derived values.
- Every commit fires the level-up sound and a brief gold flash on the panel.

### 7.3 Visual style

Elden Ring's palette, not a literal ripoff:
- Background: `rgba(10, 9, 8, 0.92)` near-black
- Primary gold: `#C9A227`
- Dim gold / inactive: `#7A6520`
- Bar fill: gold gradient; bar track: `#2A2620`
- Staged-increase text: pale green `#9FD68C`
- Unaffordable / warning: `#B4432E`
- Thin 1px gold borders on section dividers, no rounded corners
- Generous letter-spacing on headers via manual per-character draw if PZ has no letter-spacing option, otherwise skip — **do not** hand-place glyphs, it's not worth it

Use `UIFont.Medium` for the level number, `UIFont.Small` for everything else, unless recon finds better options. **Do not attempt custom font packing** unless everything else is done — flag it as a stretch goal.

### 7.4 HUD elements (outside the panel)

- **Rune gain popup:** bottom-right of the screen, `+8` in gold, fades over ~1.2s, stacking gains coalesce into one number that ticks up. Rate-limit rendering: coalesce all gains within 500ms into one popup.
- **Rune total display:** optional persistent bottom-right counter (sandbox toggle, default off — PZ's HUD is already crowded).
- **"YOU DIED" overlay:** on death, before the vanilla death screen, a black fade with serif "YOU DIED" in dim red for ~2s. Sandbox toggle, default **on**. Must not block or break the vanilla death flow — if it risks that, make it default off and say so.

---

## 8. Data model

All persisted in `player:getModData().ERLeveling`:

```lua
{
  version    = 1,                 -- schema version, for migrations
  stats      = { vig=10, mnd=10, end=10, str=10, dex=10, int=10, fth=10, arc=10 },
  heldRunes  = 0,
  totalEarned= 0,                 -- lifetime, for stats screen
  level      = 1,
  grantedPerks = { Strength = 0, Fitness = 0 },  -- what we gave, so we can revoke
  lastGraceX = nil, lastGraceY = nil, lastGraceZ = nil,
}
```

Global (server) mod data `ERLeveling_Global`:

```lua
{
  version = 1,
  bloodstains = {
    ["<steamOrUsername>"] = { x=, y=, z=, runes=, time=, },
  },
}
```

**Migration:** always check `version`. If missing, initialize defaults. If lower than current, run migration functions in sequence. Never assume a field exists — every read goes through a `getStat(player, key)` accessor that lazily initializes.

---

## 9. Multiplayer architecture (hard requirement)

Same standard as the Re:Zero mod: this must work on a dedicated server.

**Authority split:**
- **Server owns:** rune balances, level-up transactions, stat values, bloodstain registry, perk grants.
- **Client owns:** UI only. The client never mutates rune counts or stats directly, ever.

**Flow for leveling up:**
1. Client validates locally (affordable, at Grace) for instant UI feedback.
2. Client sends `sendClientCommand(player, "ERLeveling", "levelUp", { deltas = {vig=1, str=2}, expectedCost = 1742 })`.
3. Server re-validates **everything** independently — cost, Grace proximity, balance. Never trust `expectedCost`; recompute it.
4. Server mutates modData, calls `player:transmitModData()` `[VERIFY]`, and replies with `sendServerCommand(player, "ERLeveling", "levelUpResult", {ok=true, stats=..., runes=...})`.
5. Client reconciles UI from the authoritative reply. On `ok=false`, revert the optimistic UI and show the reason.

**Flow for rune gain:** kill detection runs server-side (`isServer()` branch of `OnZombieDead`), server credits, server pushes the new balance. Client shows the popup on receipt.

**Anti-cheat notes:**
- PZ kicks players for client-side perk level changes (the "type 12" style checks). Any `LevelPerk`/`setPerkLevel` call must be inside an `isServer()` guard, or run in single-player only.
- Same caution for direct stat writes (`getStats():setEndurance` etc.). Test on a local dedicated server before assuming it's fine. If a stat effect trips anti-cheat, redesign that effect rather than telling users to disable anti-cheat.

**Single-player:** short-circuit the command round-trip (a `ERNet.request()` wrapper that calls the handler directly when `not isClient()`), so there is exactly one code path for the logic.

---

## 10. Sandbox options

`media/sandbox-options.txt` in the mod, with `media/lua/shared/Translate/EN/Sandbox_EN.txt` for labels. Page name: `ERLeveling`.

| Option | Type | Default | Range |
|---|---|---|---|
| `RuneMultiplier` | double | 1.0 | 0.1 – 10.0 |
| `CostA` | double | 1.6 | 0.1 – 10 |
| `CostB` | double | 2.2 | 1.0 – 4.0 |
| `CostC` | double | 40 | 0 – 500 |
| `CostBase` | double | 40 | 0 – 1000 |
| `CostPreset` | enum | LandsBetweenLite | LandsBetweenLite / Authentic / Custom |
| `StartingStat` | int | 10 | 1 – 30 |
| `MaxStat` | int | 99 | 10 – 99 |
| `RequireGrace` | bool | true | |
| `LoseRunesOnDeath` | double (%) | 100 | 0 – 100 |
| `BloodstainPersists` | bool | true | |
| `AnyoneCanLootBloodstain` | bool | false | |
| `KeepStatsOnDeath` | bool | false | ER-accurate is false; PZ players may want true |
| `ShowYouDied` | bool | true | |
| `ShowHudCounter` | bool | false | |
| `AllowRespec` | enum | LarvalTear | Never / LarvalTear / Free |
| `RuneArcSpawnRate` | double | 1.0 | 0 – 10 |
| `EffectStrength` | double | 1.0 | 0.25 – 3.0 (global scalar on all stat effects) |

`EffectStrength` matters — it's the one dial that lets someone keep the flavor without breaking PZ's difficulty.

---

## 11. Custom items

Define in `media/scripts/erleveling_items.txt`:

- `RuneArc` — consumable, 500 runes, rare loot, uses a gold-ish existing icon or a custom PNG
- `GoldenRune1` / `GoldenRune2` / `GoldenRune3` — 200 / 800 / 2500
- `LarvalTear` — consumable, triggers full respec (refunds all spent runes, resets stats to `StartingStat`), very rare
- `GraceIdol` — placeable, enables Grace anywhere (see §5)

Loot distribution in `media/lua/server/Items/ERLevelingDistributions.lua`. Put Golden Runes in bedroom drawers/safes/corpses at low rates, Rune Arcs in churches (thematic) and safehouse loot, Larval Tears in bank vaults / gun store safes. Rates scaled by `RuneArcSpawnRate`.

Icons: `media/textures/Item_RuneArc.png` etc., 32×32, referenced by `Icon = RuneArc` in the item script `[VERIFY]` naming convention (PZ expects `Item_<Icon>.png`).

---

## 12. File tree

```
ERLeveling/
├── mod.info
├── poster.png                          (512×256 workshop poster)
├── NOTES.md                            (agent-maintained; see §1.8)
├── README.md
├── 42/                                 (or flat, per §2.2)
│   └── media/
│       ├── sandbox-options.txt
│       ├── scripts/
│       │   ├── erleveling_items.txt
│       │   └── erleveling_sounds.txt
│       ├── textures/
│       │   ├── Item_RuneArc.png
│       │   ├── Item_GoldenRune.png
│       │   └── ERLeveling/
│       │       ├── rune_icon.png
│       │       ├── bloodstain.png
│       │       └── grace_glow.png
│       ├── sound/
│       │   ├── er_levelup.ogg
│       │   ├── er_runes_gain.ogg
│       │   └── er_grace.ogg
│       └── lua/
│           ├── shared/
│           │   ├── ERLeveling_Balance.lua      -- ALL tuning constants
│           │   ├── ERLeveling_Formulas.lua     -- scale(), cost(), derived effects
│           │   ├── ERLeveling_Data.lua         -- modData accessors + migrations
│           │   ├── ERLeveling_Net.lua          -- request() wrapper, SP short-circuit
│           │   └── Translate/EN/
│           │       ├── UI_EN.txt
│           │       ├── Sandbox_EN.txt
│           │       └── ItemName_EN.txt
│           ├── server/
│           │   ├── ERLeveling_ServerCommands.lua  -- authoritative handlers
│           │   ├── ERLeveling_Runes.lua           -- kill detection + crediting
│           │   ├── ERLeveling_Bloodstain.lua      -- death/registry/recovery
│           │   └── Items/ERLevelingDistributions.lua
│           └── client/
│               ├── ERLeveling_Effects.lua         -- applies stat effects on tick
│               ├── ERLeveling_Grace.lua           -- Grace proximity detection
│               ├── ERLeveling_Keybinds.lua
│               ├── ERLeveling_ClientCommands.lua
│               └── UI/
│                   ├── ERLevelPanel.lua           -- the Runes tab
│                   ├── ERStatRow.lua              -- one stat row widget
│                   ├── ERRuneStrip.lua            -- counter inside Health tab
│                   ├── ERRunePopup.lua            -- +N floating text
│                   ├── ERYouDied.lua              -- death overlay
│                   └── ERHooks.lua                -- all vanilla UI wrapping lives here
```

**`ERHooks.lua` rule:** every single monkey-patch of vanilla code goes in this one file, each with a comment naming the vanilla file and function being wrapped and why. When PZ updates and things break, this is the only file anyone needs to read.

Standard wrap pattern:

```lua
local original_createChildren = ISHealthPanel.createChildren
function ISHealthPanel:createChildren()
    original_createChildren(self)          -- vanilla first, always
    local ok, err = pcall(function()
        ERHooks.attachRuneStrip(self)
    end)
    if not ok then print("[ERLeveling] hook error: " .. tostring(err)) end
end
```

`pcall` around every hook body. A broken mod should degrade to "no rune UI", not "health panel doesn't open".

---

## 13. Milestones

### M0 — Skeleton (no gameplay)
- Mod loads, appears in the mod list with icon and description
- A "Runes" tab appears in the character info window, renders static text
- A rune strip appears at the bottom of the Health tab
- Zero console errors on load, new game, load game, and death

**Accept:** open the character screen, see both surfaces, `console.txt` is clean.

### M1 — Runes exist
- Kills award runes (SP only)
- Balance persists across save/load
- `+N` popup appears
- Rune count shown in both UI surfaces and updates live

**Accept:** kill 10 zombies, see 80 runes, quit to menu, reload, still 80.

### M2 — Leveling
- Full Runes tab per §7.2: staging, cost calc, commit, reset
- Stats persist
- Level number derives correctly
- Cost curve matches the printed table

**Accept:** level Vigor 10→15 for the exact predicted cost; reload the save; stats intact.

### M3 — Stat effects
- All eight stats produce measurable, testable effects
- `EffectStrength` sandbox scalar works
- A debug command prints every derived value so effects are verifiable

**Accept:** with Strength 60, melee kills demonstrably faster than Strength 10, measured by hits-to-kill on a standard zombie. Write the measurement down.

### M4 — Death & bloodstains
- Runes drop on death, bloodstain registered
- Marker visible (whichever fallback tier worked)
- Recovery works, second death destroys the old stain
- Distance/direction readout on the Runes tab

**Accept:** die with 3,000 runes, respawn, walk back, reclaim exactly 3,000. Then die twice in a row and confirm the first stain is gone.

### M5 — Sites of Grace
- Grace detection working for campfires and fireplaces
- Level-up gated on Grace, button disabled with a clear tooltip when away
- Header text and glow state change correctly

**Accept:** cannot level in an open field; can level next to a lit campfire.

### M6 — Multiplayer
- Full server-authoritative flow
- Two clients on a local dedicated server can each earn and spend independently
- No anti-cheat kicks over a 30-minute session with active combat and leveling
- Bloodstains are per-player and respect `AnyoneCanLootBloodstain`

**Accept:** run a local dedicated server, two clients, 30 min, zero kicks, zero desyncs.

### M7 — Polish & ship
- Custom items + loot distribution
- Sounds
- YOU DIED overlay
- All sandbox options wired and labeled
- Localization file complete for EN
- README with install instructions, feature list, sandbox option docs, known issues
- Workshop-ready structure (`Contents/mods/ERLeveling/...`), poster image

**Accept:** a clean install on a machine with no other mods works end to end from a fresh save.

---

## 14. Testing protocol

Launch with `-debug` for the debug menu and Lua hot-reload.

Write `dev/ERDebug.lua` (excluded from the shipped mod, or gated behind `isDebugEnabled()`) providing console commands:
- `ERDebug.give(n)` — grant runes
- `ERDebug.setStat("str", 60)`
- `ERDebug.dump()` — print full modData + all derived values
- `ERDebug.costTable(1, 150)` — print the cost curve
- `ERDebug.simulateDeath()` — test bloodstain flow without dying
- `ERDebug.grace()` — report why Grace detection is/isn't triggering

Manual test matrix to run before each milestone commit:

| Scenario | Check |
|---|---|
| New game | Stats initialize to defaults, no errors |
| Load existing save (mod added mid-save) | Migration initializes cleanly |
| Load save with mod **removed** | Game doesn't crash (nothing we can control, but note it in README) |
| Death → respawn | Runes zeroed, bloodstain created |
| Split-screen / second local player | `getSpecificPlayer(1)` handled, not just player 0 |
| MP client | No anti-cheat kick, values sync |
| Sandbox extremes (RuneMultiplier 10, EffectStrength 3) | No math errors, no NaN, UI doesn't overflow |
| Zero runes, empty state | UI doesn't divide by zero or render garbage |

---

## 15. Known pitfalls (do not rediscover these the hard way)

1. **`OnPlayerUpdate` fires constantly.** Anything expensive there tanks FPS. Cache derived stat values and only recompute when a stat actually changes.
2. **Never store an `IsoPlayer` reference in a long-lived table.** Store the player's index/username and re-resolve. Stale references cause crashes on death/respawn.
3. **`getModData()` on a dead player** may be unavailable. Snapshot rune balance on damage or at intervals so `OnPlayerDeath` has something to work with even if the player object is already half-torn-down.
4. **Split-screen exists.** `getPlayer()` is not always the right player. Prefer explicit player arguments from events.
5. **Textures fail silently.** `getTexture()` on a missing path returns nil and then `drawTexture` errors. Nil-check every texture load once at init.
6. **PZ text drawing has no wrapping.** Measure and manually break long tooltip lines.
7. **Sandbox vars don't exist until the game loads.** Reading `SandboxVars.ERLeveling.X` at file scope will be nil. Read them inside `OnGameStart` or lazily.
8. **The character info window may not exist yet** when your `OnGameStart` runs. Hook `createChildren`, don't poke at instances at load time.
9. **Perk boosts stack with traits.** If a player has the Strong trait and you add boosts, verify you're not double-dipping into absurd values.
10. **`Events.OnZombieDead` fires for zombies killed by other zombies, fire, and the environment.** Attribution check is mandatory or players get free runes from forest fires.
11. **Modifying vanilla item scripts** breaks compatibility with other mods. Add new items; don't edit existing ones.
12. **Build 42 changed a lot of Lua paths.** Do not assume a B41 tutorial you find in training data is current. Trust the installed source files over anything else, including this document.

---

## 16. Stretch goals (only after M7)

- **Ashes of War equivalent:** apply a "weapon art" modData tag to a melee weapon, granting an alternate power attack.
- **Great Runes:** kill a "boss" zombie (a specially spawned high-health named zombie) → equip a Great Rune for a large passive buff, activated by Rune Arcs.
- **Flask of Crimson/Cerulean Tears:** limited-charge healing item refilled at a Grace. Fits PZ's medical system awkwardly — design carefully or skip.
- **Custom serif font** for the level number.
- **Summon signs:** MP-only, place a sign at a Grace that lets another player fast-travel to you. Almost certainly out of scope for PZ's map, but fun.
- **Rune-cost respec via Larval Tear** with a proper confirmation modal.
- **Compatibility pass** with popular mods (Brita's, Superb Survivors, Authentic Z) — mostly means checking that our hooks survive their hooks.

---

## 17. Questions to resolve with the author before/while building

Log answers in `NOTES.md`. Don't block on these — pick the noted default and flag it.

1. **Build target:** B42 only, or B41 too? *(default: B42, B41 if cheap)*
2. **Do stats survive death?** ER says you keep levels. PZ death means a new character, so keeping stats makes every subsequent life easier. *(default: `KeepStatsOnDeath = false`, sandbox toggle exposed prominently)*
3. **Should PZ's own skill perks still function normally?** *(default: yes, untouched — this mod is additive)*
4. **Workshop release or personal use?** Affects how much polish M7 needs. *(default: assume Workshop, like the Re:Zero mod)*
5. **How aggressive should the effects be?** Default `EffectStrength = 1.0` aims at "noticeably stronger but still PZ." Confirm that's the intent.

---

## 18. Definition of done

- All M0–M7 acceptance criteria pass
- `console.txt` is clean across a full 2-hour play session
- MP session with 2+ players, 30+ minutes, no kicks or desyncs
- README documents every sandbox option in plain language
- `NOTES.md` records every deviation from this plan and why
- Uninstalling the mod leaves a loadable save (perk grants revoked or documented as permanent)
