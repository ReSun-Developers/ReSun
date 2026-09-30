# ReSun — Unified Capability Matrix

Master feature reference for supporting **Tiberian Sun (TS)**, **Firestorm (FS)**,
**Red Alert 2 (RA2)**, and **Yuri's Revenge (YR)** in one data-driven, isometric-3D engine.

Companion docs:
- `docs/research/_raw/current-state-audit.md` — what the engine does today (evidence-backed)
- `docs/research/deep/README.md` — **exhaustive per-title catalogs + errata.** Feature-level
  detail and verified constants live here; read its errata before quoting any catalog number.
- `docs/research/deep/verification-{core,gameplay}.md` — adversarial conflict ledgers
- `docs/architecture/unified-engine.md` — target architecture & generic subsystems
- `docs/gap-analysis.md` — prioritized gap list with actions
- `docs/titles/*.md` — per-title quick references

> **Design-impacting facts from the deep pass (must be honored):** warhead `Verses` is editable
> in every title and the **armor enumeration is per-game** (TS 5, RA2/YR 11) — the engine must
> read a per-game armor table with variable-length `Verses`. AI script action IDs and animation
> indices also differ per title. Target YR patch **1.001**, not the 1.000 mirror.

## How to read this

**Per-title columns** mark whether the title has the feature:
`✓` present · `~` partial/variant · `–` absent · `+` added by the expansion over the base title.

**Engine status** is measured against the current ReSun code (see audit):
`impl` implemented · `part` partial/schema-only · `miss` missing (no code, no spec).

**Action** is the gap type:
`DATA` per-game content only · `SYS` needs a generic engine subsystem · `SPEC` needs
documentation/spec first · `—` no action (already supported) · `FUT` future / out of scope scope.

> Rule from `AGENTS.md`: `openspec/specs/` is authoritative. This matrix is a research
> planning artifact; a `SYS`/`SPEC` action becomes real work via a future OpenSpec change.

---

## 1. Core engine & simulation

| Feature | TS | FS | RA2 | YR | Engine | Action |
|---|---|---|---|---|---|---|
| Isometric diamond cell grid + leptons | ✓ | ✓ | ✓ | ✓ | impl | — |
| Rectangular/diamond world bounds, reveal inset | ✓ | ✓ | ✓ | ✓ | impl | — |
| Heightmap grades, cliffs, ramps, collision | ✓ | ✓ | ✓ | ✓ | impl | — |
| Terrain/land types driving passability | ✓ | ✓ | ✓ | ✓ | impl | — |
| Theaters/tilesets (look-only, per-map) | ~ | ~ | ✓ | ✓ (+lunar) | part | SPEC |
| Sub-cell slots / shared occupancy | ✓ | ✓ | ✓ | ✓ | impl | — |
| Armor class matrix (`Warhead.Verses[]`) | 5 classes | 5 | 11 classes | 11 | impl (TS-sized) | SYS: variable-length, data-driven armor list |
| Damage clamp `MinDamage`/`MaxDamage` | ✓ | ✓ | ✓ | ✓ | impl | — |
| Projectile archetypes (bullet/cannon/ballistic/lobbed/homing/laser/pulse) | ✓ | ✓ | ✓ | ✓ | part | SYS: only `is_guided` consumed; add families |
| Projectile splash / `CellSpread` / `PercentAtMax` | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| ROT (unit + turret turn rate) | ✓ | ✓ | ✓ | ✓ | impl | — |
| Power grid supply/demand + low-power penalties | ✓ | ✓ | ✓ | ✓ | impl | — |
| Negative power / drain / forced blackout | – | – | – | ✓ | miss | SYS: signed power + external blackout |
| Per-unit power dependency (powered-down states) | ✓ | ✓ | ✓ | ✓ | impl | — |
| Veterancy stat bonuses (combat/armor/speed/ROF) | ✓ | ✓ | ✓ | ✓ | impl | — |
| Veterancy XP promotion + per-level abilities | ✓ | ✓ | ✓ | ✓ | miss | SYS: XP accumulation + ability unlock |
| Crushing (`Crusher`/`CrusherAll`/`OmniCrusher`, Weight) | ✓ | ✓ | ✓ | ✓ | part | SYS: omni-crusher |
| Ice cracking / drowning | ✓ | ✓ | ✓ | ✓ | impl | — |
| Crate/pickup system (money/heal/unit/etc.) | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Cloak / stealth + detection (sensors, dogs) | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Fire-from-transport / passenger weapon modes | – | – | ~IFV | ✓ | miss | SYS (garrison subsystem) |
| Frame-rate-independent timing | ✓ | ✓ | ✓ | ✓ | impl | — |

## 2. Economy & resources

| Feature | TS | FS | RA2 | YR | Engine | Action |
|---|---|---|---|---|---|---|
| Resource types as data (Tiberium/ore/gems) | ✓ | ✓ | ✓ | ✓ | impl | DATA (ore/gems for RA2/YR) |
| Harvester state machine + dock/unload | ✓ | ✓ | ✓ | ✓ | impl | — |
| Harvester multiple types (chrono/war/slave) | – | – | ✓ | ✓ | part | DATA + SYS: teleport gather, slave spawn/replace |
| Refinery docking, free harvester on placement | ✓ | ✓ | ✓ | ✓ | impl | — |
| Storage cap / silos (per category) | ✓ | ✓ | –(unlimited) | – | impl | DATA: cap policy per game |
| Resource growth / spread | ✓ | ✓ | ✓ | ✓ | impl | — |
| Veins / veinholes / weeds (harvestable + hazard) | ✓ | ✓ | – | – | part | SYS: weed eater + vein hazard |
| Health effects (Tiberium healing/toxicity/mutation) | ✓ | ✓ | ~ore heal | ~ | miss | SYS: aura/status framework |
| Oil derrick / civilian recurring income | – | – | ✓ | ✓ | miss | SYS: generic cash producer |
| Ore Purifier / income multipliers | – | – | – | ✓ | miss | SYS: production modifiers |
| Grinder recycle / credit siphon | – | – | – | ✓ | miss | SYS: refund + per-tick transfer |
| Sell refund % + survivors/crew | ✓ | ✓ | ✓ | ✓ | impl | DATA |
| Income/expense tracking + HUD rate | ~ | ~ | ✓ | ✓ | miss | SYS + SPEC |

## 3. Construction & base building

| Feature | TS | FS | RA2 | YR | Engine | Action |
|---|---|---|---|---|---|---|
| MCV deploy / undeploy | ✓ | ✓ | ✓ | ✓ | impl | — |
| Build mode + ghost preview + validation | ✓ | ✓ | ✓ | ✓ | impl | — |
| Adjacency / build radius rules | ✓ | ✓ | ✓ | ✓ | impl | — |
| Placement blocking by moving units | ✓ | ✓ | ✓ | ✓ | impl | — |
| Bib cells (pathable at cost) | ✓ | ✓ | ~ | ~ | impl | — |
| Foundation / footprint derivation | ✓ | ✓ | ✓ | ✓ | impl | — |
| Sell / repair structures | ✓ | ✓ | ✓ | ✓ | part | SYS: repair cost-per-step path |
| Service depot / repair bay auto-repair | ✓ | ✓ | ✓ | ✓ | miss | SYS: repair aura + vehicle dock |
| Walls & gates (directional, drag-build) | ✓ | ✓ | ✓ | ✓ | part | SYS: wall line build + gate logic |
| Specialized defenses (towers, fences, AA) | ✓ | ✓ | ✓ | ✓ | part | DATA + SYS: defense behavior (auto-fire) |
| Building capture by engineer | ✓ | ✓ | ✓ | ✓ | miss | SYS: capture ability + `Capturable` |
| Capturable neutral/tech buildings (hospitals, derricks) | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Buildable garrison (bunkers, battle bunker) | – | – | – | ✓ | miss | SYS (garrison subsystem) |
| Civilian building garrison ("urban combat") | – | – | ✓ | ✓ | miss | SYS (garrison subsystem) |
| Building upgrades / `PowersUpBuilding` | ✓ | ✓ | ~ | ✓ | miss | SYS: upgrade/prefab target |
| Cloning Vats / infantry duplication | – | – | – | ✓ | miss | SYS |
| Build-up animation | ✓ | ✓ | ✓ | ✓ | part | SYS: construction VFX/anims |
| Undo/redo, land-type paint, water/cliff authoring (editor) | ✓ | ✓ | ✓ | ✓ | part | SPEC + SYS (editor) |

## 4. Production & tech

| Feature | TS | FS | RA2 | YR | Engine | Action |
|---|---|---|---|---|---|---|
| Per-facility production queues | ✓ | ✓ | ✓ | ✓ | impl | — |
| Category queues (building/defense/infantry/vehicle/air/naval) | ✓ | ✓ | ✓ | ✓ | part | SYS: data-driven tab/category set |
| Prerequisites (AND/OR, factory ownership, tech level) | ✓ | ✓ | ✓ | ✓ | impl | — |
| Category-bucket prereqs (`POWER`/`PROC`/`FACTORY`/`RADAR`/`TECH`) | ✓ | ✓ | ✓ | ✓ | part | SYS: alias resolution |
| Country/side gate (`RequiredHouses`/`ForbiddenHouses`) | – | – | ✓ | ✓ | miss | SYS: house/country model |
| Multiple-factory speed bonus | ✓ | ✓ | ✓ | ✓ | impl | — |
| Factory exit + rally point | ✓ | ✓ | ✓ | ✓ | impl | — |
| Blocked-exit retry / bail-out | ✓ | ✓ | ✓ | ✓ | impl | — |
| Priority / primary building | ✓ | ✓ | ✓ | ✓ | impl | — |
| Batch production + queue reorder | ~ | ~ | ~ | ~ | part | SYS |
| Research/upgrade unlock | ✓(PowersUp) | ✓ | ~ | ✓ | miss | SYS |
| Build limits / hero single-build (`BuildLimit`) | ✓ | ✓ | ✓ | ✓ | impl | — |
| Naval yard / airforce command / sub pen | ✓ | ✓ | ✓ | ✓ | miss | SYS: naval producer + water placement |
| Aircraft pad rearm / reload / ammo | ✓ | ✓ | ✓ | ✓ | miss | SYS: ammo/reload + pad |

## 5. Units & combat

| Feature | TS | FS | RA2 | YR | Engine | Action |
|---|---|---|---|---|---|---|
| Hitscan + projectile firing | ✓ | ✓ | ✓ | ✓ | impl | — |
| Burst / salvo / stagger, ROF, charges, ammo | ✓ | ✓ | ✓ | ✓ | part | SYS: ammo/reload; DATA rest |
| Range / min-range / facing gate | ✓ | ✓ | ✓ | ✓ | impl | — |
| Turrets / independent ROT / sockets | ✓ | ✓ | ✓ | ✓ | impl | — |
| Staged / gattling weapons | – | – | – | ✓ | miss | SYS: weapon stage state machine |
| Prism support beams / refraction | – | – | ✓ | ✓ | miss | SYS: weapon support-chain effect |
| Tesla chain / supercharge | – | – | ✓ | ✓ | miss | SYS: chained-warhead effect |
| Mind control (temporary, capacity, immunity) | – | – | ~ | ✓ | miss | SYS: control-link manager |
| Permanent mind control (Dominator) | – | – | – | ✓ | miss | SYS |
| Berserk / allegiance override | – | – | – | ✓ | miss | SYS: status-effect framework |
| Poison / radiation / DoT residue | – | ~gas | ✓ | ✓ | miss | SYS: area DoT |
| Auto-engage / guard / threat targeting | ✓ | ✓ | ✓ | ✓ | miss | SYS (blocks GDI Mission 01) |
| Attack-move / patrol / stance orders | ✓ | ✓ | ✓ | ✓ | miss | SYS (blocks GDI Mission 01) |
| Splash / AoE damage | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Self-healing / regen | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Deploy-to-fire (Juggernaut, GI, Siege Chopper) | ✓(FS) | ✓ | ✓ | ✓ | part | SYS: deploy forms + fire discipline |
| C4 / timed bombs / disarm | ✓ | ✓ | ✓ | ✓ | miss | SYS: ability |
| Spy / infiltration effects / disguise | ✓ | ✓ | ✓ | ✓ | miss | SYS: ability + effect table |
| Engineer capture / repair / bridge repair | ✓ | ✓ | ✓ | ✓ | miss | SYS: ability |
| IFV / passenger-driven weapon tables | – | – | ✓ | ✓ | miss | SYS (garrison subsystem) |
| Crushing / omni-crush | ✓ | ✓ | ✓ | ✓ | part | SYS |
| EMP / disable mechanical | ✓ | ✓ | – | – | miss | SYS: disable status |
| Subterranean units (burrow, untargetable) | ✓ | ✓ | – | – | part | SYS: underground state |
| Jetpack / jumpjet units | ✓ | ✓ | ✓ | ✓ | impl | — |
| Cloak / submarine submerge | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Aircraft flight + landing/rearm | ✓ | ✓ | ✓ | ✓ | part | SYS + DATA |
| Carryall / transport aircraft | ✓ | ✓ | ✓ | ✓ | miss | SYS: air transport |
| Naval units + torpedoes | ✓(minimal) | ✓ | ✓ | ✓ | miss | SYS + DATA |
| Amphibious / hovercraft ferrying | ✓ | ✓ | ✓ | ✓ | part | DATA + SYS |

## 6. Movement & pathing

| Feature | TS | FS | RA2 | YR | Engine | Action |
|---|---|---|---|---|---|---|
| Grid A* + cost cache + LOS smoothing | ✓ | ✓ | ✓ | ✓ | impl | — |
| Pluggable locomotors + terrain speeds | ✓ | ✓ | ✓ | ✓ | impl | — |
| Movement zones passability classes | ✓ | ✓ | ✓ | ✓ | impl | DATA per game |
| Splines + repulsion + wait-scatter | ✓ | ✓ | ✓ | ✓ | impl | — |
| Jumpjet vertical state machine | ✓ | ✓ | ✓ | ✓ | impl | — |
| Teleport / chrono movement | – | – | ✓ | ✓ | miss | SYS: teleport locomotor |
| Forced displacement (magnetron pull) | – | – | – | ✓ | miss | SYS: movement override |
| Subterranean tunnels + entrances | ✓ | ✓ | – | – | part | SYS |
| Bridge traversal / destruction / repair | ✓ | ✓ | ✓ | ✓ | part | SYS: bridge entity state |
| Amphibious / water movement | ✓ | ✓ | ✓ | ✓ | part | SYS + DATA |
| Control groups 1–0 + focus | ✓ | ✓ | ✓ | ✓ | miss | SYS (UI) |
| Formation selection / line-column-spread | ✓ | ✓ | ✓ | ✓ | part | SYS |
| Waypoint queues / planning mode | ✓ | ✓ | ✓ | ✓ | part | SYS |

## 7. Vision & fog

| Feature | TS | FS | RA2 | YR | Engine | Action |
|---|---|---|---|---|---|---|
| Shroud (explored) + fog (dynamic) layers | ✓ | ✓ | ✓ | ✓ | impl | — |
| Height-aware shadowcasting | ✓ | ✓ | ✓ | ✓ | impl | — |
| Revealers, ally sharing, ref counting | ✓ | ✓ | ✓ | ✓ | impl | — |
| Fog rendering + ghosts + shroud growth | ✓ | ✓ | ✓ | ✓ | impl | — |
| Radar availability gating | ✓ | ✓ | ✓ | ✓ | impl | — |
| Radar destructibility / blackout | ✓ | ✓ | ✓ | ✓ | part | SYS: radar loss + gap generator |
| Gap generator / radar blackout bubble | ✓gen | ✓ | ✓ | ✓ | miss | SYS |
| Spy satellite / full-map reveal | – | – | ✓ | ✓ | miss | SYS: reveal power |
| Psychic radar / attack-target reveal | – | – | – | ✓ | miss | SYS: radar extension |
| Sensor vs cloak detection | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Reveal-on-superweapon-build (global timer) | ~ | ~ | ~ | ✓ | miss | SYS (superweapon framework) |

## 8. Special systems — superweapons, abilities, auras

| Feature | TS | FS | RA2 | YR | Engine | Action |
|---|---|---|---|---|---|---|
| Superweapon framework (charge/target/fire/cooldown) | ✓ | ✓ | ✓ | ✓ | miss | SYS (registry of effect handlers) |
| Ion cannon (GDI) | ✓ | ✓ | – | – | miss | SYS + DATA |
| Nuclear missile | – | – | ✓ | ✓ | miss | SYS + DATA |
| Weather control / lightning storm | – | – | ✓ | ✓ | miss | SYS + DATA |
| Chronosphere / mass teleport | – | – | ✓ | ✓ | miss | SYS + DATA |
| Iron Curtain (invuln) | – | – | ✓ | ✓ | miss | SYS + DATA |
| Firestorm barrier / force shield | – | ✓ | – | ✓ | miss | SYS + DATA |
| Multi-missile / chemical missile / gas | ✓ | ✓ | – | – | miss | SYS + DATA |
| Hunter-seeker / kamikaze drone | ✓ | ✓ | – | – | miss | SYS + DATA |
| Drop pods / paradrop / paratroopers | ✓ | ✓ | ✓ | ✓ | miss | SYS + DATA |
| Psychic Dominator (permanent capture) | – | – | – | ✓ | miss | SYS + DATA |
| Genetic Mutator (infantry→Brute) | – | – | – | ✓ | miss | SYS: entity conversion |
| Psychic Reveal / Spy Plane support powers | – | – | ✓ | ✓ | miss | SYS + DATA |
| Ion storms / dynamic weather | ✓ | ✓ | – | – | miss | SYS: global weather system |
| Meteorites / terrain cratering | ✓ | ~ | – | – | miss | SYS + DATA |
| Aura/radius system (heal/repair/sensor/slow) | ~ | ~ | ✓ | ✓ | miss | SYS |
| Status-effect framework (timed, DoT, immunity) | ~ EMP | ~ | ~ | ✓ | miss | SYS |
| Entity conversion / transform primitive | ✓ | ✓ | ✓ | ✓ | part | SYS: generalize deploy/mutate |
| Tunnel network (Nod) | ✓ | ✓ | – | – | miss | SYS + DATA |
| Visceroids / tiberium lifeforms | ✓ | ✓ | – | – | miss | SYS + DATA |
| Deployable mobile structures (mobile war factory, mobile stealth generator) | – | ✓ | – | – | miss | SYS: generalize deploy |
| Limpet attach / scout / slow-vehicle | – | ✓ | – | – | miss | SYS: attach + status effect |
| Web immobilisation | – | ✓ | – | – | miss | SYS: status effect |
| Cluster-split / sub-projectile rockets | ✓ | ✓ | ✓ | ✓ | miss | SYS: projectile spawn-on-flight |
| Levitation / floater locomotion | – | ✓ | – | – | miss | SYS: locomotor variant |
| Conditional invulnerability / activation (CABAL Core Defender) | – | ✓ | – | – | miss | SYS: status + trigger |

## 9. UI/UX & controls

| Feature | TS | FS | RA2 | YR | Engine | Action |
|---|---|---|---|---|---|---|
| Camera pan/zoom/edge-scroll, remap | ✓ | ✓ | ✓ | ✓ | impl | — |
| Isometric 45° view | ✓ | ✓ | ✓ | ✓ | impl | — |
| Camera rotation | – | – | – | – | miss | FUT (target = fixed 45° iso) |
| Selection (single/box/shift/hover) | ✓ | ✓ | ✓ | ✓ | impl | — |
| Selection brackets / health bars / pips | ✓ | ✓ | ✓ | ✓ | impl | — |
| Sidebar tabs + cameo grid + queue | ✓ | ✓ | ✓ | ✓ | impl | — |
| Data-driven tab/category set per game | ✓ | ✓ | ✓ | ✓ | part | SYS |
| Credits counter + power bar | ✓ | ✓ | ✓ | ✓ | impl | — |
| Radar/minimap with events + shroud | ✓ | ✓ | ✓ | ✓ | impl | — |
| Tooltips / hover info | ✓ | ✓ | ✓ | ✓ | impl | — |
| Selection/info panel (portrait, stats, actions) | ✓ | ✓ | ✓ | ✓ | part | SYS |
| Control groups 1–0 | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Stance / guard / attack-move controls | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Rally point UX | ✓ | ✓ | ✓ | ✓ | impl | — |
| Waypoint draw / planning mode UI | ✓ | ✓ | ✓ | ✓ | part | SYS |
| Cursor-state machine | ✓ | ✓ | ✓ | ✓ | impl | — |
| Pause menu | ✓ | ✓ | ✓ | ✓ | impl | — |
| Save/load + load screen | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Settings UI (video/audio/input) | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Main menu / map browser / new game flow | ✓ | ✓ | ✓ | ✓ | part | SYS |
| Skirmish setup + faction/country select | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Superweapon charge UI + shared timer | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Garrison/bunker enter-exit UX | – | – | ~ | ✓ | miss | SYS |
| Mind-control feedback (color/pips) | – | – | ~ | ✓ | miss | SYS |
| EVA/message ticker UI | ✓ | ✓ | ✓ | ✓ | part | SYS |
| UI typography | ✓ | ✓ | ✓ | ✓ | impl | — |

## 10. Presentation & audio

| Feature | TS | FS | RA2 | YR | Engine | Action |
|---|---|---|---|---|---|---|
| Instanced unit rendering (MultiMesh) | ✓ | ✓ | ✓ | ✓ | impl | — |
| 3D models / baked models | ✓ | ✓ | ✓ | ✓ | impl | — |
| Async/batch loading | ✓ | ✓ | ✓ | ✓ | impl | — |
| Shadows / lighting | ✓ | ✓ | ✓ | ✓ | impl | — |
| Building/turret animations + damaged states | ✓ | ✓ | ✓ | ✓ | part | SYS + DATA |
| Combat VFX: explosions, deaths, craters, scorch | ✓ | ✓ | ✓ | ✓ | miss | SYS + DATA |
| Terrain/water rendering + theaters | ~ | ~ | ✓ | ✓ | part | SYS + DATA |
| Audio buses + spatial falloff | ✓ | ✓ | ✓ | ✓ | impl | — |
| Unit voice sets (select/move/attack/death) | ✓ | ✓ | ✓ | ✓ | impl | — |
| EVA announcer per faction | ✓ | ✓ | ✓ | ✓ | miss | SYS + DATA |
| Music system + dynamic tracks | ✓ | ✓ | ✓ | ✓ | miss | SYS + DATA |
| Ambient/VFX particles (smoke, gas, weather) | ✓ | ✓ | ✓ | ✓ | miss | SYS + DATA |
| Post-game score screen | ✓ | ✓ | ✓ | ✓ | miss | SYS |

## 11. Campaign & mission scripting

| Feature | TS | FS | RA2 | YR | Engine | Action |
|---|---|---|---|---|---|---|
| Map editor (height/resource/entity/start) | ✓ | ✓ | ✓ | ✓ | impl | — |
| Map format + loader + houses/overlays | ✓ | ✓ | ✓ | ✓ | impl | — |
| Waypoints (spawns, patrol, reinforcement, reveal) | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Trigger / event / action engine | ✓ | ✓ | ✓ | ✓ | miss | SYS (largest gap) |
| Objectives (primary/secondary) + UI | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Win/lose + mission timer | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Mission boot / briefing / start camera | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| TaskForces / TeamTypes / ScriptTypes (AI scripting) | ✓ | ✓ | ✓ | ✓ | miss | SYS + DATA |
| Reinforcements (land/sea/air/drop) | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Cinematic camera + FMV/briefing | ✓ | ✓ | ✓ | ✓ | miss | FUT |
| Campaign progression / mission select | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Theaters per-map + per-country palettes | ~ | ~ | ~ | ✓ | part | SYS + DATA |
| Scenario roster gating (FS original: `expand01.mix` + `firestrm.ini` detection) | – | ✓ | – | – | miss | SYS: per-map/per-package roster gate |

## 12. Skirmish, multiplayer, meta, modding

| Feature | TS | FS | RA2 | YR | Engine | Action |
|---|---|---|---|---|---|---|
| Game definitions + data-set layering | ✓ | ✓ | ✓ | ✓ | impl | DATA (add fs/ra2/yr game defs) |
| Faction/house/country registry + sides | 2 sides | 2 | 2/9 countries | 3/10 | part | SYS + DATA |
| Per-country unit/bonus data | – | – | ✓ | ✓ | miss | SYS + DATA |
| Skirmish AI (base build, attack teams, difficulty) | ✓ | ✓ | ✓ | ✓ | miss | SYS (blocks first milestone) |
| AI economy cheats / difficulty scaling | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Skirmish/multiplayer setup UI | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Multiplayer modes (battle/team/co-op) | ✓ | ✓ | ✓ | ✓ | miss | SYS |
| Netcode / lobby / reconnect | ✓ | ✓ | ✓ | ✓ | miss | SYS (large, future) |
| Replays / observer | ~ | ~ | ~ | ~ | miss | FUT |
| Game-mode registry + map metadata | ~ | ~ | ✓ | ✓ | miss | SYS |
| Modding data-set scaffold | ✓ | ✓ | ✓ | ✓ | impl | — |
| Mod manager / load-order / mod UI | ~ | ~ | ~ | ~ | miss | SYS |
| Localization / CSF strings | ✓ | ✓ | ✓ | ✓ | miss | SYS + DATA |
| Debug menu / cheats | ✓ | ✓ | ✓ | ✓ | impl | — |

---

## Legend summary

- **Already data-ready:** everything marked `impl` — the per-title work is content under
  `games/<id>/` (a new `GameDefinition` plus data sets), not engine code.
- **Generic subsystems still missing** (the bulk of new engine work, from `SYS` rows):
  superweapon/support-power framework, control-link (mind control) manager, garrison/occupancy,
  weapon state machine, ammo/reload, auto-engage/attack-move/patrol, campaign trigger/objective
  runtime, skirmish AI, navy/water, aerospace landing, save/load, status-effect/aura, crates,
  cloak/sensors, and the side→country→bonus registry.
- **Documentation gaps** (`SPEC`): theater registry semantics, editor authoring scope, and
  per-game data-set conventions for the three new titles.
