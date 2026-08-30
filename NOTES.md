# NOTES.md — TARNISHED implementation log

Companion to `PLAN.md`. Per PLAN.md §1.8 this records what the plan got wrong,
what was substituted and why, tuning that changed, and what is still open.

---

## 0. The one thing to read first

**PLAN.md §2 (Phase 0 reconnaissance) could not be performed as written, and the
whole architecture is shaped by that.**

The mod was built in an environment with no Project Zomboid installation and no
reachable copy of the vanilla Lua tree. Every instruction in §2.3 ("read these
files in full") and §2.4 ("confirm each of these exists with the signature
shown") was impossible to satisfy.

PLAN.md §1.2 says *never guess an API*. Guessing was the only alternative to
stopping, so instead the rule was inverted into a mechanism:
**`media/lua/shared/ERLeveling_Compat.lua` probes every uncertain API at runtime,
on the machine that actually runs the mod.** A method that is not there is not
called; the call site takes a documented fallback and the absence is printed once
at startup by `ERCompat.report()`.

The practical consequences:

* Nothing in this mod calls an unverified API without first asking whether it
  exists. `ERCompat.has`, `ERCompat.call`, `ERCompat.get`, `ERCompat.hasGlobal`,
  `ERCompat.hasEvent` and `ERCompat.onEvent` are the only doors to uncertain
  surface area.
* Every event handler body is `pcall`-wrapped, and error printing is throttled to
  three lines per source, so a per-tick failure cannot spam `console.txt`
  (PLAN.md §1.7, §15.1).
* **Run `ERDebug.compat()` in the in-game Lua console on first launch.** It
  prints exactly which probes failed on your build. That output is the real
  §2.4 checklist, and it is worth pasting into an issue if something is missing.

What this does *not* substitute for: the UI hook targets. If
`ISCharacterInfoWindow.createChildren` or `ISHealthPanel.createChildren` have
been renamed, the hooks log a clear message and the mod runs without those
surfaces (the keybind falls back to a standalone window). That is a graceful
failure, not a verified success.

**Everything below marked [UNVERIFIED IN GAME] has been exercised by the offline
test suite but never by Project Zomboid itself.**

---

## 1. Build target

| Question (PLAN.md §17.1) | Answer |
|---|---|
| B42 only, or B41 too? | **Both, from one source.** |

The Lua is written against the intersection of what both builds plausibly expose,
with runtime probes wherever they diverge. The repository keeps a single flat
`Contents/mods/ERLeveling/media/` tree, which is the Build 41 layout and which
Build 42 still loads. `tools/build.sh` generates the Build 42 versioned layout
(`ERLeveling/42/media/…`) into `dist/` rather than duplicating every file in git.

`ERCompat.buildNumber()` detects the build for logging and for the loot-table
branch. It is deliberately not used to gate anything that could instead be probed
directly — PLAN.md §15.12 is right that the installed source outranks any
assumption, and a probe *is* the installed source.

---

## 2. Deviations from PLAN.md

### 2.1 `end` is a Lua keyword — Endurance is stored as `endr`

PLAN.md §8 specifies `stats = { vig=10, mnd=10, end=10, … }`. `end` cannot be a
bare table key in Lua. The key is `endr` throughout. Everything else matches the
plan's naming.

### 2.2 The soft-cap curve did not reach 1.0

PLAN.md §3.2's final segment is `0.950 + (v - 59) * 0.00125`, annotated
".. 1.000 at 99". Because `v = value - 1`, the top of the range is `v = 98`, and
that slope lands at **0.99875**. The slope is now derived (`0.05 / 39`) so the
endpoint is exactly 1.0. The shape of the curve is otherwise untouched.

### 2.3 Effects are normalised against the *starting* attribute value — important

This is the largest deliberate divergence and it is a correctness fix, not a
taste change.

PLAN.md §3.2 applies effects as `base + (max - base) * scale(value)`. With the
default starting value of 10, `scale(10) = 0.27`. A brand new Level 1 character
would therefore begin the game with **27% of every bonus in the mod** — roughly
+30% melee damage, +12% damage negation, +27% rune find and +3.8 kg carry weight,
before spending a single rune. It also broke the plan's own M1 acceptance
criterion: ten standard kills paid 100 runes instead of 80, because Arcane was
already 27% effective.

`ERStats.progress(value)` now rescales the curve so it reads 0.0 at the sandbox
starting value and 1.0 at 99, preserving the soft-cap shape above the start.
`ERStats.scale()` is unchanged and still available (the debug dump prints both).

Caught by `tools/test_offline.lua`. This is the clearest argument for the harness
existing at all.

### 2.4 Grace detection lives in `shared/`, not `client/`

PLAN.md §12 files `ERLeveling_Grace.lua` under `client/`. PLAN.md §9 requires the
**server** to independently re-validate Grace proximity on a level-up, and the
server cannot call into client Lua. Detection is therefore in `shared/`; the
client-only caching and presentation is in `client/ERLeveling_GraceClient.lua`.

### 2.5 Grace detection is signal-based, not class-based

We cannot confirm whether the installed build exposes campfires as `IsoFireplace`,
through `CampfireSystem`, or via sprite naming, so `ERGrace` tries all of them and
any one match is enough:

1. `instanceof(obj, "IsoFire")` — a live fire on the square.
2. Sprite name contains `campfire` / `fireplace` / `stove` / `oven` / `firepit` /
   `camping_01` / `brazier` / `hearth` / `furnace`, **and** the object reports
   itself lit via `isLit()`, `isActivated()`, or its modData.
3. `CampfireSystem.instance:getLuaObjectOnSquare(square)` reporting `isLit()`.
4. A `GraceIdol` world item within `idolRadius`.
5. The player is asleep or sitting.

A heat source that looks right but exposes no lit state is treated as **unlit** —
a cold hearth is not a Grace.

Also accepted: **carrying** a Grace Idol. Placing an item as a world object is one
of the things we could not verify, and losing the Idol feature entirely to that
uncertainty was the worse trade. If placement turns out to work reliably this can
be tightened to placed-only.

### 2.6 No `.ogg` files ship with the mod

PLAN.md §12 lists `er_levelup.ogg`, `er_runes_gain.ogg`, `er_grace.ogg`. No audio
could be authored here, and a sound script that names files which do not exist
produces console warnings on every load — directly against the "clean
`console.txt`" requirement in §18.

Instead `ERBalance.SOUND` names sound events (default: vanilla `"LevelUp"` for a
level up, silence for the others) and `ERUI.playSound` is a guarded call. Point
those three strings at your own sound pack and they work with no code change; the
`EnableSounds` sandbox option silences them entirely. `media/scripts/erleveling_sounds.txt`
is deliberately absent for the same reason.

### 2.7 No crafting recipes in the item script

Build 41 and Build 42 use different recipe script formats, and a recipe the
running build cannot parse spams the console. The Grace Idol is therefore forged
through a Lua context-menu option
(`ERConsumables.forgeIdol`, 1× Pipe/MetalBar/MetalPipe + Candle + Sheet,
Metalworking 2), which behaves identically on both builds. Everything else is
loot-only.

`WorldStaticModel` was also dropped from every item definition: model names differ
between builds and a missing one logs a warning.

### 2.8 Bloodstain marker: tiers 2 + 3 + 4, not tier 1

PLAN.md §4.3's preferred marker is a floor decal. No world-decal API could be
confirmed, so all three fallbacks ship together:

* **Tier 2** — the server drops an `ERLeveling.Bloodstain` world item on the death
  square when that square is loaded, and removes it on reclaim or when a newer
  death replaces the stain.
* **Tier 3** — `ERBloodstainMarker.lua` draws a pulsing gold marker. When
  `IsoUtils.XToScreenExact` / `YToScreenExact` / `IsoCamera` all probe
  successfully it sits on the square itself; when they do not it becomes an
  edge-of-screen chevron with distance and compass bearing. **The chevron is the
  path more likely to be taken, and honestly the more useful one at Project
  Zomboid's map scale** — which is what PLAN.md §4.2 suspected.
* **Tier 4** — the `Bloodstain: 412 tiles NE — 4,900 runes` line on the Runes tab.

No in-game map marker: no map-annotation API could be confirmed. [OPEN]

### 2.9 The rune strip is a child panel, repositioned in a `render` wrap

As PLAN.md §7.1 asks. The wrap also subtracts the host's scroll offset (when
`getYScroll` exists) so the strip stays pinned to the visible bottom edge rather
than scrolling away with the body-part list.

### 2.10 A standalone window exists as a fallback

Not in the plan. `client/UI/ERWindow.lua` holds the same `ERLevelPanel` in its own
`ISCollapsableWindow`. It is only ever created if the character-info-window hook
failed, so that a rename in a future build costs the tab, not the mod.

### 2.11 One commit, not one per milestone

PLAN.md §1.6 asks for a commit per milestone with the milestone tag in the
message. That rule assumes the incremental, in-game-verified workflow of §1.5:
ship M0, accept it against a running client, then start M1. With no game
available (§0) none of those acceptance gates could be passed, so there was no
honest point at which to cut M0 from M1. Splitting the finished tree into
retroactive M0–M7 commits would manufacture a history that did not happen.
The work landed as one commit that names the milestones it covers.

### 2.12 Extra sandbox options

Beyond PLAN.md §10: `EnableSounds`, `AllowPerkGrants` (see §3.2 below) and
`DebugCommands`. `CostPreset` is an enum of three as specified; the four custom
curve constants are exposed alongside it.

---

## 3. Decisions on the `[VERIFY]` items

Each is resolved the way PLAN.md §6 prescribes: pick the highest tier that
actually works, at runtime, and write down why.

### 3.1 `OnPlayerGetDamage` mutability — assumed **not** mutable

Vigor is implemented as PLAN.md's own fallback: an immediate post-hoc restore of
the negated fraction, spread across damaged body parts worst-first
(`ERFx.healSpread`). The player still takes the hit and still sees the blood, they
just recover part of it instantly. This is also the safer behaviour if the
argument *is* mutable on some build, because the two cannot double-apply.

### 3.2 Carry weight — three tiers, resolved at runtime

1. `player:setMaxWeightBase(n)` — used when present. The original base is
   captured once per player and the bonus is added to it, so the value is
   reversible and never compounds.
2. `setPerkBoost(Perks.Strength, n)` — **not used for carry weight.** It boosts XP
   gain rate, not capacity, exactly as PLAN.md §6 suspected.
3. Server-granted Strength/Fitness perk levels — the fallback, and **only** when
   tier 1 is unavailable (`ERServer.applyPerkGrants` returns immediately if
   `setMaxWeightBase` exists, so the two can never stack). Capped at +3 Strength
   and +2 Fitness, tracked in `grantedPerks`, revoked on respec and by
   `ERDebug.revokePerks()`. Runs only on a server or in single player, never on a
   client (PLAN.md §9). Can be switched off entirely with `AllowPerkGrants`.

### 3.3 `Events.AddXP` — used when present, with a re-entrancy guard

Intelligence multiplies skill XP through `Events.AddXP`. Adding XP from inside
that handler re-enters it, so `ERFx._inXp` breaks the loop. When the event does
not exist, the fallback is a broad `setPerkBoost` across crafting and combat
perks. When it *does* exist the fallback boost is halved rather than removed, so
the two paths cannot compound into something absurd.

### 3.4 Perk *boosts* vs perk *levels*

`setPerkBoost` is what the vanilla trait system uses and changes only XP rate, so
it is applied client-side (Mind→Aiming, Dexterity→Reloading, Intelligence→broad).
Perk **levels** are never touched outside server/single-player code. This is the
anti-cheat line from PLAN.md §9 and it is drawn in exactly one place.
[UNVERIFIED IN GAME] — the assumption that boosts are not policed is untested
against a live server.

### 3.5 Crit and sprinter detection — probed, and simply absent if unavailable

Crit uses `zombie:isHitFromBehind()` or a `BodyPartType.Head` hit, whichever the
build offers. Sprinters use `isSprinter()` or `getSpeedType() <= 1`. If none of
those exist there is no crit multiplier and no sprinter tier, and
`ERCompat.report()` says so rather than the mod silently paying the wrong amount.

### 3.6 Horde bonus — `getNumChasingZombies()` or nothing

Counting nearby zombies by walking the cell would be far too expensive for a
per-kill path (PLAN.md §15.1). If the stats object does not expose a chasing
count, the horde multiplier is not applied.

### 3.7 Kill attribution — belt and braces

`zombie:getAttackedBy()` first. Because §15.10 warns it returns nil for fire and
zombie-on-zombie kills, `OnWeaponHitCharacter` / `OnHitZombie` also record
`zombieId -> {playerKey, timestamp, ranged, crit}` with an 8-second memory and a
purge above 64 entries. **If neither source names a player, nothing is awarded.**

### 3.8 Zombie damage is applied client-side on purpose

Project Zomboid clients simulate their own melee, so Strength's bonus damage is
applied wherever the hit event fires, guarded by `simulatesCombat()` which
excludes a dedicated server. Applying it server-side instead would mean it never
fires in multiplayer.

### 3.9 The one place a client is trusted

`ERServer.consumeItem` looks the item up server-side and destroys it there. If the
lookup fails it refuses in single player (where the inventory in front of us *is*
the real one) and accepts the client's claim on a dedicated server (where
containers may not be replicated to us), guarded by a 400 ms per-player rate
limit. This is the only trust boundary in the mod and it is worth revisiting once
someone can confirm how inventories replicate on a real server. [OPEN]

---

## 4. Tuning changed from the plan

* Effect envelopes (`ERBalance.EFFECTS`) are new — PLAN.md §3.1 describes the
  effects but does not give numbers. They are stated as `{ at start, at 99 }`
  pairs and every one is in that one table.
* Melee damage tops out at **+110%**, damage negation at **45%**, carry weight at
  **+20 kg** (12 from Strength, 8 from Endurance), XP at **+100%**. All are
  multiplied by `EffectStrength`, and all reductions are hard-ceilinged
  (`ERStats.reduction`) so `EffectStrength = 3.0` cannot produce invulnerability.
* Cost curve defaults are the plan's: A=1.6, B=2.2, C=40, Base=40. Verified
  against the plan's own reference points by `tools/cost_table.lua`:
  L1→2 = **81** (plan: ~82), L10→11 = **693** (plan: ~700), L60→61 = **15,503**
  (plan: ~15k). L30→31 is **4,083**; the plan's "~3.6k" was a loose estimate, the
  formula itself is unchanged.
* At 8 runes per kill with no Arcane, reaching Level 10 costs about **440 kills**
  and Level 30 about **6,000**. Run `lua tools/cost_table.lua` to see the whole
  table.

---

## 5. Testing

### What was actually run

`tools/test_offline.lua` loads the shared and server halves against a mock
Project Zomboid environment (`tools/pz_mock.lua`) and asserts **95 checks**,
covering the formula layer, the data model and its repair path, rune crediting
and attribution, every level-up rejection, respec, consumables, the full
death → bloodstain → reclaim cycle, and the empty/edge states from PLAN.md §14.

```
lua5.4 tools/test_offline.lua      # 95 checks, 0 failures
lua5.4 tools/cost_table.lua        # print the cost and soft-cap curves
bash  tools/build.sh               # parse-check, test, then package both builds
```

Every `.lua` file also parses under `luac -p`.

The harness found four real bugs before any of this shipped: the free 27% bonus
(§2.3), the soft-cap endpoint (§2.2), a respec that succeeded without consuming a
Larval Tear (§3.9), and a rate limit that was masking a different rejection.

### What has NOT been run

**The game.** No milestone in PLAN.md §13 has been accepted against a real
client, and none of §14's manual matrix has been executed. In particular these
are all [UNVERIFIED IN GAME]:

* the two UI hooks and whether the tab and strip actually appear;
* every rendering call, font constant and texture load;
* multiplayer end to end — the client/server split is implemented as §9
  specifies, and single player runs the same handlers through the same
  `ERNet.request` short-circuit, but no dedicated server has seen it;
* anti-cheat behaviour under `setPerkBoost` and granted perk levels;
* loot distribution table names, which differ between builds;
* whether `Events.AddXP`, `OnPlayerGetDamage` and friends fire with the argument
  shapes assumed.

### Suggested first session

1. Launch with `-debug`, load a save, open `console.txt`.
2. `ERDebug.compat()` — read the probe report. This is the §2.4 checklist.
3. `ERDebug.dump()` — confirm the data model and derived values.
4. `ERDebug.give(5000)`, light a campfire, level something, `ERDebug.dump()` again.
5. `ERDebug.simulateDeath()`, walk away, walk back, confirm the reclaim.
6. `ERDebug.grace()` anywhere the Grace state looks wrong.

---

## 6. Open items

* **[OPEN]** No in-game map marker for bloodstains (PLAN.md §4.2). Needs a
  confirmed map-annotation API.
* **[OPEN]** The dedicated-server trust fallback in `ERServer.consumeItem` (§3.9).
* **[OPEN]** Custom serif font for the level number — PLAN.md §7.3 rightly calls
  this a stretch goal, and per §7.3 no glyphs are hand-placed.
* **[OPEN]** Every stretch goal in PLAN.md §16 (Ashes of War, Great Runes, Flasks,
  summon signs) is untouched. They are correctly gated behind M7.
* **[OPEN]** Faith's `sicknessResist` scales `getFoodSicknessLevel` and
  `getPoisonLevel` where those exist. It deliberately never touches infection or
  zombification, and the tooltip says so out loud.
* **[NOTE]** Uninstalling: granted perk levels persist unless `ERDebug.revokePerks()`
  is run first, or a respec is performed. Nothing else the mod writes affects a
  save without the mod — it all lives under `modData.ERLeveling` and the
  `ERLeveling_Global` table.

---

## 7. Answers to PLAN.md §17

1. **Build target** — both, from one source (§1 above).
2. **Do stats survive death?** — `KeepStatsOnDeath` defaults to **false**, the
   plan's default. Because a Project Zomboid death produces a new `IsoPlayer`
   with fresh modData, "true" is implemented explicitly: the stats are copied to
   a `carryOver` slot in global data on death and restored in `OnCreatePlayer`.
3. **Do vanilla perks still work normally?** — yes, untouched, except for the
   opt-out carry-weight fallback in §3.2.
4. **Workshop or personal?** — built as if for the Workshop: poster, `mod.info`,
   full EN localisation, `Contents/mods/…` layout, `tools/build.sh --zip`.
5. **How aggressive should effects be?** — `EffectStrength = 1.0` aims at
   "noticeably stronger but still Project Zomboid". A maxed sheet is a
   substantially stronger survivor; a fresh one is now exactly vanilla (§2.3).
   Turn the dial down to 0.5 for flavour-only, up to 2.0 for a power fantasy.
