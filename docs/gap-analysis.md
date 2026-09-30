# Unified Engine — Gap Analysis & Action Plan

Derived from the audit (`docs/research/_raw/current-state-audit.md`) and the four title
inventories, cross-referenced in `docs/capability-matrix.md`.

Two kinds of gap, kept separate on purpose:

- **DOC GAP** — the feature exists or is specified but the docs are wrong/silent.
- **CAPABILITY GAP** — the feature is genuinely absent or a schema stub. Split into:
  - **CONTENT** — needs only data under `games/<id>/` (engine already supports it).
  - **SYSTEM** — needs a generic engine subsystem, then data.

Priorities: **P0** blocks the current milestone (GDI Mission 01) · **P1** required for RA2/YR
support · **P2** completeness/polish.

---

## A. Documentation gaps (fix now, no engine work)

| # | Wrong/absent doc | Reality | Action |
|---|---|---|---|
| D1 | `plans/00-0_project_status.md` (2026-08-08) | says fog/radar/power/projectiles/turrets/minimap/pause missing; 22 autoloads, 63 specs, 74 tests | Rewrite to 2026-09-14 verified state |
| D2 | `plans/project_planning_roadmap.md` | Phase 2/3.1/6.1 unchecked despite implementation; engine version skew (resolved: 26.2) | Reconcile checkboxes; add cross-title phase |
| D3 | `plans/3-1_combat_weapons.md` | wrong damage formula; claims WarheadData absent | Rewrite |
| D4 | `plans/4-1_fog_vision.md` | "0% greenfield" | Rewrite to shipped state |
| D5 | `plans/2-1_navigation.md` overview | "no global pathfinding" | Fix overview |
| D6 | `plans/7-2_unit_roster.md` | "aircraft no weapons"; "6 land types" | Fix |
| D7 | `plans/5-2_game_management.md` | minimap/pause/menu now exist | Fix |
| D8 | `plans/1-4, 6-2, 6-3, 11-1` | under-/over-report shipped systems | Reconcile |
| D9 | `AGENTS.md` | 23 components→29, 37 scenes→46, 22 plans→25; engine version skew (resolved: 26.2) | Fix counts (version now unified at 26.2) |
| D10 | no `docs/` unified reference | — | Added by this work |
| D11 | `GLOSSARY.md` lacks cross-title terms | — | Extend (see §D) |
| D12 | no multi-title plan | — | Add `plans/12-0_unified_multi_title_expansion.md` |
| D13 | new capabilities unspecced | — | Future OpenSpec changes per SYSTEM item |

## B. Capability gaps — by priority

### P0 — blocks GDI Mission 01 (current milestone)

| Gap | Type | Notes |
|---|---|---|
| Auto-engage / guard / threat targeting | SYSTEM | units only fire when ordered today |
| Attack-move + patrol + stances | SYSTEM | no input action/order exists |
| Mission boot / briefing / start camera | SYSTEM | hooks only |
| Trigger / event / action engine | SYSTEM | nothing exists — largest subsystem |
| Objectives + win/lose + mission timer | SYSTEM | depends on trigger engine |
| Scripted teams / reinforcements / waypoints | SYSTEM | `TaskForce`/`TeamType` runtime |
| Menu → map flow / map browser | SYSTEM | hardcoded `TestMap02` |
| Entity-placement + 13 missing entity types | CONTENT | mission map content |
| Map editor: land-type paint, water, player starts polish | SYSTEM | authoring blockers |
| Combat VFX: explosions, deaths, craters, scorch | SYSTEM | presentation |
| EVA announcer + music | SYSTEM | content gitignored/flags unused |
| Projectile splash / AoE | SYSTEM | schema has no consumer |
| Veterancy XP promotion | SYSTEM | only static multipliers |
| Radar/minimap known already impl — verify | DOC | audit says impl |

### P1 — required to support RA2 / YR

| Gap | Type | Notes |
|---|---|---|
| Variable-length data-driven armor list + Verses | SYSTEM | TS=5, RA2/YR=11 |
| Superweapon / support-power framework | SYSTEM | registry of pluggable effects |
| Control-link (mind control) manager | SYSTEM | temporary + permanent + capacity |
| Garrison / occupancy subsystem (bunkers, civ, fire-from-transport, bio reactor) | SYSTEM | base on Transport/Dock |
| Weapon state machine: staged/gattling, passenger modes, prism/tesla chains | SYSTEM | YR/RA2 |
| House → side → country registry + per-country bonuses | SYSTEM | RA2/YR countries |
| Naval movement + water rendering + ship content | SYSTEM | water is land type only |
| Aerospace: aircraft flight, landing/rearm, ammo/reload, carryall | SYSTEM | schema stubs |
| Status-effect / aura framework (EMP, gas, berserk, poison, mutate, invuln) | SYSTEM | TS + YR |
| Entity conversion / mutate (infantry→Brute, deploy forms) | SYSTEM | generalize deploy |
| Economy hooks: refund/recycle, siphon, cost/income multipliers | SYSTEM | Grinder/Floating Disc/Purifier |
| Cloak / stealth + sensor/dog detection + gap generator + spy satellite | SYSTEM | TS/RA2/YR |
| Spy infiltration effects + disguise + thief | SYSTEM | ability + effect table |
| Crates / pickups | SYSTEM | TS/RA2/YR |
| Teleport / chrono movement | SYSTEM | RA2/YR |
| Skirmish AI (base build, attack teams, difficulty scaling) | SYSTEM | blocks any bot game |
| Save/load of live game state | SYSTEM | only editor JSON today |
| Data packages `games/fs`, `games/ra2`, `games/yr` | CONTENT | after systems land |
| Save/load, settings UI, skirmish setup UI | SYSTEM | shell completeness |

### P2 — completeness / meta

| Gap | Type | Notes |
|---|---|---|
| Initial/explored map percentage win conditions | SYSTEM | plan 4-2 |
| Bridge destruction/repair, wall drag-build & gates | SYSTEM | TS/RA2/YR |
| Vengeance: repulsion polish, formations menu, control groups | SYSTEM | QoL |
| Multiplayer/netcode/lobby/replays | SYSTEM | large; future |
| Mod manager / load-order / mod UI / localization | SYSTEM | modding plan 8-2 |
| Ion storms / dynamic weather / meteorites | SYSTEM | TS/FS flavor |
| Visceroids / tiberium lifeforms / vein hazards | SYSTEM | TS/FS flavor |
| Post-game score screen | SYSTEM | all titles |
| Editor undo/redo | SYSTEM | authoring |

## C. Content inventory gaps (per-title data to author)

| Title | Package | Roster scale | Notable specifics |
|---|---|---|---|
| Tiberian Sun | `games/ts` (exists) | ~26 infantry, 38 vehicles, ~168 buildings, 8 aircraft, 45 terrain, 83 overlay, 40 smudge | Fill stubs: special abilities, superweapons, sub/naval, visceroids |
| Firestorm | `games/fs` (new, delta over ts) | +GDI Juggernaut/Mobile EMP/Firestorm/Mobile War Factory/Limpet; +Nod Reaper/Mobile Stealth Gen/Mobile WF/AA Obelisk; +CABAL faction | Original gates content via `expand01.mix` + `firestrm.ini` detection, not a map flag |
| Red Alert 2 | `games/ra2` (new base) | 2 sides / 9 countries; infantry/vehicles/aircraft/naval | Ore+gems, 11 armor, no silos, countries, superweapons (Chrono/IC/Nuke/Weather), naval |
| Yuri's Revenge | `games/yr` (new, delta over ra2) | +ThirdSide / YuriCountry (10 countries), full Yuri roster | Mind control, bunkers, gattling, Dominator/Genetics/Force Shield, slave economy, Lunar theater |

## D. Glossary terms to add

From the research, these cross-title terms are missing and should be recorded:
`side`, `country`, `house bonus`, `superweapon`, `support power`, `superweapon charge`,
`mind control link`, `permanent control`, `garrison`, `bunker`, `fire-from-transport`,
`passenger weapon mode`, `staged weapon`/`gattling stage`, `prism support`, `tesla chain`,
`aura`, `status effect`, `EMP`, `berserk`, `mutation`, `cloak`/`stealth`, `sensor`,
`gap generator`, `spy infiltration`, `crate`, `theater` (already), `game mode`,
`taskforce`/`teamtype`/`scripttype`, `trigger`/`event`/`action`, `waypoint` (already),
`reinforcement`, `ion storm`, `vein`/`veinhole`, `visceroid`, `chrono`, `teleport locomotor`.

Also record **Undecided**: true 2:1 dimetric vs current 45° camera.

## E. Recommended sequencing (not a commitment)

1. **Reconcile docs** (D1–D9, D11–D12) — cheap, immediate, no code.
2. **P0 systems** to ship the existing milestone (guard/attack-move → mission runtime → VFX).
3. **Lock generic contracts as specs** (armor, projectile, status, superweapon, house, mission,
   theater) before authoring new games.
4. **P1 systems** in dependency order (status/aura → superweapon → garrison → control-link →
   weapon state machine → house/country → naval/air → economy hooks → skirmish AI → save/load).
5. **Author `games/fs`**, validate delta model.
6. **Author `games/ra2`** — the TS-assumption stress test.
7. **Author `games/yr`** — forces the P1 systems to be complete.
8. **P2 polish + multiplayer.**

## F. Pass-2 findings (exhaustive research + adversarial verification)

Sources: `docs/research/deep/` (12 exhaustive catalogs + 2 conflict ledgers). The errata in
`docs/research/deep/README.md` overrides the catalogs.

### F1. Newly confirmed generic subsystems (added to the P1/P2 lists)

| Gap | Type | Notes |
|---|---|---|
| Per-game armor enumeration + variable-length `Verses` | SYSTEM | **Design-impacting.** `Verses` is editable in every title; only the armor count differs (TS 5, RA2/YR 11). Never hardcode TS sizing. |
| Per-game AI action registry | SYSTEM | **Design-impacting.** RA2/YR shift TS action IDs ≥11 by +1 and add 26–32. Key AI actions per game. |
| Per-game animation index + caching | SYSTEM | **Design-impacting.** TS `[Animations]`=277; YR ~607 with a +4 shift bug at #209. Per-title arrays. |
| Patch-level data versioning | SYSTEM | Target YR 1.001, not the 1.000 mirror. Data packages need an explicit version. |
| Deployable mobile structures (mobile war factory, mobile stealth generator) | SYSTEM | Generalize deploy/undeploy beyond MCV/Tick Tank. |
| Limpet attach / scout / slow-vehicle effect (FS) | SYSTEM | Status-effect + attach primitive. |
| Mobile EMP: charge meter + area pulse (FS) | SYSTEM | Charge state + superweapon-like local delivery. |
| Web immobilisation (FS Cyborg Reaper) | SYSTEM | Status effect. |
| Cluster-split / sub-projectile rockets (FS + Multi-Missile) | SYSTEM | Projectile spawn-on-flight. |
| Core Defender activation / conditional invulnerability (FS CABAL) | SYSTEM | Status + activation trigger. |
| Levitation / floater locomotion (FS) | SYSTEM | Locomotor variant. |
| Ownership/control-link serialization | SYSTEM | Save/load must persist mind-control and capture graphs. |
| Superweapon global reveal + shared timer contract (YR) | SYSTEM | Part of the superweapon framework. |
| Per-game map/house/theater schema tolerance | SYSTEM | Loader must accept per-title sections (`[SpecialFlags]`, `GameModes=`, etc.). |

### F2. Corrections that affect the plan

- **`Verses` is editable in TS too** — remove any assumption that TS damage tables are hardcoded
  (this was wrong in the first-pass docs). Elevate "per-game armor table" to a Tier-2 priority:
  it must land **before** RA2 content.
- **Firestorm gating** is `expand01.mix` + `firestrm.ini` detection in the original; a
  `Firestorm=yes` map flag is our own design choice, not original behavior.
- **FS content**: `CraterLevel`/veinhole tuning are **not** in the FS INI (first pass guessed);
  "mutate" was a misattribution (it is the Tiberium Floater lifeform, `JFISH`).
- **YR content**: Slave Miner $1750, Chaos Drone $1000, Siege Chopper $1100 (all 1.001);
  Grand Cannon `GTGCAN`; Korea unique = Black Eagle; RA2 sidebar = **4 tabs**, control groups 9
  (TS = 10).
- **Campaigns**: TS Nod = 13 main missions (not 15); GDI 15 main; FS 18; RA2 12+12; YR 7+7.
- **Cross-engine nuances**: original TS shroud is local-player-only (our per-player system is a
  superset — decide parity intent); `CellSpread` is a 3D lepton sphere; 5 sub-positions per cell
  with a separate bridge mask.
- **Still approximate**: type-list counts (TS 36/50/150; RA2 45/57) — not primary-counted.

### F3. Deep-research doc-internal errors (errata applied via `deep/README.md`)

The catalogs contain a handful of self-contradictions and wrong values fixed in the errata:
RA2 6-tab claim (4 is right), TS Nod=15 (13), `GAGCAN` (`GTGCAN`), YR cost patch level, plus the
`Verses`-hardcoded falsehood. Always read `deep/README.md` before quoting a catalog number.
