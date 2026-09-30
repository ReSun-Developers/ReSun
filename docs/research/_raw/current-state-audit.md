# Current-State Engine Capability Audit — ReSun

Repo: `/mnt/work2/Redot/redotian-sun` · Engine: Redot 26.2 LTS (Forward Plus)
Basis: code + 95 `openspec/specs/` + 25 `plans/` · 28 autoloads, 29 component scripts, 46 scenes, ~408 entity `.tres`.
Audit date: 2026-09-14.

Legend: **Implemented** = real runtime behavior wired · **Partial** = schema/subset only,
behavior incomplete · **Spec-only** = described but no code · **Missing** = no spec and no code.

---

## 1. Core engine & simulation

- Rectangular/diamond grid + CellUtil — Implemented — `scripts/core/CellUtil.gd`; specs `rectangular-grid`, `cell-util`
- Terrain heightfield (vertex grid, cascade, grade, pins, height snapshot) — Implemented — `scripts/core/TerrainSystem.gd:102,146,211,236,267,399,675`; specs `terrain-grade`, `terrain-cell-pins`, `terrain-height-cache`
- Heightfield collision authority (segment intersect, HeightMapShape3D) — Implemented — `TerrainSystem.gd:513,621`; spec `terrain-heightfield-collision`
- Land types (LAT) + painted overlay persistence — Implemented — `scripts/data/LandType.gd`; `games/ts/land_types/*.tres` (11); `TerrainSystem.gd:317,334`; spec `land-types`
- Terrain movement costs / resource land resolution — Implemented — `scripts/core/Pathfinder.gd:203,217`; specs `terrain-movement-costs`, `locomotor`
- Grid A* pathfinding (binary heap, LOS smoothing, best-reached fallback, per-cell cost cache) — Implemented — `Pathfinder.gd:229,385,412,458,482`; spec `pathfinder`
- Locomotors (Foot/Track/Wheel/Hover/Amphibious/Fly/Jumpjet/Subterranean/Ship) — Implemented — `scripts/data/Locomotor.gd`; `games/ts/locomotors/*.tres` (9)
- Spatial hash (blocked/building/bib/resource/ice cells, crusher queries) — Implemented — `scripts/core/SpatialHash.gd:70,252,286,310,337,361`; spec `spatial-hash`
- Cell reservation + sub-slots (shared capacity) — Implemented — `scripts/core/CellReservation.gd:17`; `scripts/core/CellSubPositions.gd`; specs `cell-reservation`, `cell-occupancy`
- Bounds system (red map diamond, blue visible, order area) — Implemented — `scripts/core/BoundsSystem.gd:218,267,271`; spec `rectangular-grid`
- Damage model warhead×armor with min/max clamps — Implemented — `scripts/data/GlobalRules.gd` `compute_warhead_damage`; `scripts/data/WarheadData.gd`
- Armor types (none/wood/light/heavy/concrete) — Implemented — `scripts/data/ArmorType.gd`; `games/ts/armor_types/*.tres` (5); spec `armor-types`
- Runtime projectiles — Implemented — `scripts/components/ProjectileController.gd:115,162,227`; `games/ts/projectiles/*.tres` (20); spec `projectile-runtime`
- Projectile/weapon splash AoE — Partial (schema-only) — `WarheadData.splash_radius`, `WeaponData.splash_radius` have no consumer
- Projectile trajectory families (arc/bouncy/high-arc/floater/sub-projectile) — Partial (schema-only) — `ProjectileData.gd`; only `is_guided` consumed (`ProjectileController.gd:128`)
- Power grid (per-player output/drain, low-power) — Implemented — `scripts/core/PowerGrid.gd:105,171`; `scripts/components/PowerComponent.gd`; spec `power-grid`
- Veterancy multipliers (combat/armor/speed) — Implemented — `GlobalRules.gd:253-267`; `CombatComponent.gd:147`; `HealthComponent.gd:33`; `MovementController.gd:194`
- Veterancy promotion / XP accumulation — Missing — `StatsComponent.veteran_level` never increments; `EntityData.trainable` schema-only (`EntityData.gd:81`); no spec
- Vehicle crush — Implemented — `MovementController.gd:1093`; `SpatialHash.gd:286,310`; spec `vehicle-crush`
- Frame-rate-independent timing — Implemented — spec `frame-rate-independent-timing`
- Ice cracking / drowning — Implemented — `scripts/components/IceComponent.gd:13`; `MovementController.gd:1106`; spec `ice-drowning`
- Sensor array / cloak detection — Missing — `EntityData.sensors` schema-only (`EntityData.gd:143`)
- Cloak / stealth — Missing — `EntityData.cloakable` schema-only; `SpecialAbilityComponent.gd:48` TODO
- Special ability behaviors (C4, engineer, disguise, agent/spy, thief, self-heal) — Missing — `SpecialAbilityComponent.gd:48` emits TODO per flag

## 2. Economy & resources

- Harvest → dock → unload → credits loop — Implemented — `HarvestComponent.gd`, `DockClientComponent.gd`, `DockHostComponent.gd`, `DockUnloadComponent.gd:96`, `EconomyManager.gd:44`
- Per-player/per-category storage capacity — Implemented — `EconomyManager.gd:59`; `EntityData.storage_capacity`; `PlayerData.stored_by_category`; spec `resource-storage`
- Tiberium growth / spread / tree regrowth — Implemented — `ResourceGrowthSystem.gd:85,101,189`; specs `resource-growth-system`, `resource-tree`
- Resource types (green/blue/red/tiberium/vein) — Implemented — `games/ts/resource_types/*.tres` (5)
- Harvester yield in bales + capacity + fill rate — Implemented — `HarvestComponent.gd:73,333`; `GlobalRules.harvester_fill_rate`; spec `resource-harvesting`
- Starting credits — Implemented — `games/ts/global_rules.tres:78` (10000)
- Sell refund (50%) — Implemented — `BuildingManager.gd:500`; `GlobalRules.refund_percent`
- Repair — Partial — `BuildingManager.gd:563` heals; credit/step charging path not confirmed wired
- Income tracking / resource-rate HUD — Missing — no code
- Tiberium toxicity damage — Missing — `EntityData.immune_to_resource_damage` schema-only
- Crate power-ups — Missing — `EntityData.crate_goodie` schema-only (`EntityData.gd:85`)
- Weed/vein harvesting — Partial — `resource_types/vein.tres`, `GlobalRules.weed_capacity`; no weed-eater consumer
- Visceroids / meteorites — Missing — `GlobalRules.visceroids`/`meteorites` flags unused

## 3. Construction & base building

- Build mode lifecycle + ghost preview — Implemented — `BuildingManager.gd:69,105,331`; spec `building-manager`
- Placement validation (bounds/cells/height/flatness) — Implemented — `BuildingManager.gd:105,298,317`
- Placement blocking on moving units — Implemented — spec `building-placement-blocking`
- Bib cells + pathfinding penalty — Implemented — `SpatialHash.gd:366`; spec `bib-pathfinding-penalty`
- Adjacency rule / white region — Implemented — `BuildingManager.gd:135,198`; spec `placement-grid-overlay`
- Foundation component — Implemented — `scripts/components/FoundationComponent.gd`; spec `foundation-component`
- Sell building — Implemented — `BuildingManager.gd:500`
- Repair building — Partial — `BuildingManager.gd:563`
- Destroy cleanup (cells + prereqs) — Implemented — `BuildingManager.gd:536`; `EntityFactory.gd:94`
- MCV deploy / undeploy — Implemented — `DeployComponent.gd:300,401`; spec `deploy-undeploy`
- Building upgrades — Missing — `EntityData.upgrades` schema-only (`EntityData.gd:167`)
- Building power toggle — Missing — `EntityData.toggle_power` schema-only (`EntityData.gd:172`)
- Wall/gate building — Partial — wall/gate entities exist; no wall-drag build UI
- Capability flags (construction_yard/weapons_factory/refinery/helipad) — Partial (schema-only)

## 4. Production & tech

- Per-player per-type queues — Implemented — `ProductionManager.gd:71,189`; `scripts/production/ProductionQueue.gd`; spec `production-manager`
- Gradual cost deduction — Implemented — `ProductionManager.gd`
- Prerequisites (AND/OR, factory ownership, build limits, tech level) — Implemented — `PrerequisiteSystem.gd:46`
- Factory + exit + rally point — Implemented — specs `factory-component`, `production-exit`
- Primary building preference — Implemented — `ProductionManager.gd:312`; spec `primary-building`
- Multiple-factory speed bonus — Implemented — `ProductionManager.gd:359`
- Low-power production slowdown — Implemented — `PowerGrid.gd:171`
- Cancel-with-refund / pause / resume — Implemented — `ProductionManager.gd:109,144,155`
- Building completion → placement mode — Implemented — `ProductionManager.gd:402,415`
- Blocked-exit ready-spawn retry — Implemented — `ProductionManager.gd:609,622,640`
- Sidebar build order — Implemented — `Sidebar.gd:170,178`; spec `sidebar-build-order`
- Batch production / queue reordering / true shift-queue — Partial
- Upgrades / research — Missing — `EntityData.upgrades` schema-only
- Tech levels — Implemented — `EntityData.tech_level`

## 5. Units & combat

- Hitscan firing — Implemented — `CombatComponent.gd:508`
- Runtime projectile firing — Implemented — `CombatComponent.gd:451,475,484`
- Weapon cooldown / ROF — Implemented — `CombatComponent.gd:349,425`
- Range / minimum-range checks — Implemented — `CombatComponent.gd:332,395`
- Turrets, sockets, weapon mount groups (salvo/stagger) — Implemented — `TurretComponent.gd:126`; spec `turrets`
- Firing facing gate — Implemented — `CombatComponent.gd:436`; spec `combat-facing`
- Chase / follow-attack with re-planning — Implemented — `CombatComponent.gd:527,704`; spec `combat-follow-attack`
- Burst / salvo / stagger fire modes — Implemented — `CombatComponent.gd:349,403`
- Health / damage / death — Implemented — `HealthComponent.gd:23,68`
- Veteran combat damage bonus — Implemented — `CombatComponent.gd:147,156`
- Auto-engage / guard / threat targeting — Missing — no auto-acquire; `threat_posed` unused (`CombatComponent.gd:40`)
- Attack-move / patrol — Missing — no input action, no code
- Self-healing / regen — Missing — schema-only
- Splash / AoE damage — Missing — splash fields have no consumer
- Death FX / hit animations / runtime smudge — Partial — 40 smudge `.tres`; `kill_animation`/`hit_animation` unused
- Ammo / reload — Missing — `WeaponData.ammo`, `EntityData.unit_reload` schema-only
- Anti-air behavior — Partial — `WeaponData.anti_air`; `ProjectileData.targets_air` partly consumed

## 6. Movement & pathing

- A* pathfinding — Implemented — `Pathfinder.gd:229`
- Catmull-Rom splines + string-pulling — Implemented — `MovementController.gd:1148,1155`; `SplineUtil.gd`
- Radial repulsion steering — Implemented — `MovementController.gd`; `CombatComponent.gd:605`
- Locomotion types (9) — Implemented
- Jumpjet vertical state machine — Implemented — `MovementController.gd:373,457,491`
- Ice footing + crush-on-entry — Implemented
- Subterranean travel — Partial — straight-line hybrid fallback; no underground/untargetable state
- Hover / amphibious — Implemented — `Locomotor.gd` flags
- Formation move + infantry sub-slot assignment — Implemented — `SelectionManager.gd:221,303`
- Batched move dispatch + cell reservation — Implemented
- Wait-state scatter / replan — Implemented — `MovementController.gd:1027`
- Control group hotkeys 1–0 — Missing
- Attack-move / patrol orders — Missing
- Shift waypoint queue — Partial — shift flag cosmetic
- Naval movement / water — Partial — `Ship.tres` + `water.tres` exist; no ship units, no water render
- Aircraft landing/rearm at helipad — Missing — `helipad`/`landable`/`carryall` schema-only
- Bridge traversal / repair — Partial — bridge overlay data stubs; no destruction/repair component

## 7. Vision & fog

- Per-player shroud grid + explored state — Implemented — `ShroudSystem.gd:56,331,344`
- Height-aware shadowcasting — Implemented — `ShroudSystem.gd:225,280,317`
- Ref-counted revealers + allied sharing — Implemented — `ShroudSystem.gd:82,103,682`
- Fog overlay plane + soft edges — Implemented — `FogRenderer.gd:7,345,390`
- Entity culling + post-destruction ghosts — Implemented — `UnitMeshRenderer.gd:466,518,576`; `GhostDepot.gd`
- Explore-all / temporary area reveals — Implemented — `ShroudSystem.gd:483,507,518`
- Shroud growth — Implemented — `ShroudSystem.gd:567,580`
- Minimap fog bake + radar gating — Implemented — `Minimap.gd:167,489`
- VisionComponent revealer wiring — Implemented — `VisionComponent.gd:34,39`
- Cloak/stealth reveal + sensor detection — Missing — no code

## 8. Special systems

- Transport passengers — Implemented — `TransportComponent.gd:170,198,212`; spec `transport-passengers`
- Dock host/client + queue + unload cadence — Implemented — spec `dock-host-client`
- Deploy/undeploy — Implemented — `DeployComponent.gd:300,401`
- Free unit spawn (refinery → harvester) — Implemented — `FreeUnitComponent.gd:35`
- Harvester auto-seek/dock — Implemented — `HarvestComponent.gd:73,155,305`
- Engineer capture / repair — Missing — `EntityData.engineer` schema-only
- C4 demolition — Missing
- Disguise / spy infiltration / thief — Missing
- Self-healing — Missing
- Superweapons (nuke/ion/weather/chrono/iron curtain) — Missing — no spec, no code
- Garrison / building occupation — Missing — no spec, no code
- Mind control / psychic — Missing — no spec, no code
- Navy / submarines — Missing — no content (only `Ship` locomotor)
- Subterranean APC / tunnels — Partial — hybrid fallback only
- Crates — Missing — schema-only
- Bridge destruction / repair — Missing — data stubs only
- Capturable neutral buildings — Missing — `EntityData.capturable` schema-only
- SpecialAbilityComponent wiring — Partial — attached/validated (`EntityFactory.gd:429`) but no active behavior

## 9. UI/UX & controls

- Camera pan / zoom / edge-scroll + remap — Implemented — `CameraController.gd`; `InputSettings.gd`
- Camera rotation — Missing
- Selection (single / box / shift / hover) — Implemented — `SelectionManager.gd:37`; `MouseHandler.gd:376`
- Selection overlay (brackets, health bars, pips, power label) — Implemented — `SelectionOverlay.gd`
- Sidebar (tabs, cameo grid, progress shader, sort, sell/repair) — Implemented — `Sidebar.gd:170,201,593,602`
- Credit counter UI — Implemented — `CreditCounter.gd`
- Power bar — Implemented — `PowerBar.gd`
- Gameplay minimap / radar — Implemented — `Minimap.gd`; spec `gameplay-minimap`
- Cameo + hover tooltips — Implemented — `HoverTooltip.gd`
- Pause menu — Implemented — `PauseMenu.gd:36`; spec `pause-system`
- Debug menu / cheats — Implemented — `DebugMenu.gd`
- Boot screen game selection + persistence — Implemented — `BootScreen.gd`; spec `game-selection-boot-screen`
- Main menu — Partial — `MainMenu01.gd:35` (New Campaign loads fixed `TestMap02`)
- Menu → gameplay flow / map selection — Partial — hardcoded single map, no map browser
- Gameplay save/load — Missing — only editor JSON + InputSettings cfg
- Settings UI — Missing — headless `InputSettings` only
- Faction / skirmish setup UI — Missing
- Control groups / group hotkeys — Missing
- Cursor-state machine — Implemented — `CursorState.gd`
- Order system — Implemented — `OrderSystem.gd`; spec `order-system`
- Stop command — Implemented — spec `stop-command`
- Selection/info panel — Partial — hover tooltip only
- UI typography (Tiny5) — Implemented — spec `ui-typography`

## 10. Presentation & audio

- MultiMesh instanced unit rendering — Implemented — `UnitMeshRenderer.gd:50`
- Per-socket turret instancing — Implemented — `UnitMeshRenderer.gd:452`
- Model baking — Implemented — `ModelBaker.gd:15`
- Async / batch model loading — Implemented — specs `async-model-loading`, `batch-model-loading`
- Shadows / lighting controls — Implemented — specs `shadow-rendering`, `lighting-controls`
- Rendering budget — Implemented — spec `rendering-budget`
- Animations (active-anim sets, power-gated) — Partial — `ArtComponent.gd:338,346,363`
- VFX / explosions / death FX — Missing — no particle runtime
- Audio buses + spatial falloff — Implemented — `AudioManager.gd:80,221`
- Voice playback (select/order/die hooks) — Implemented — `AudioManager.gd:281`
- Weapon-fire / impact / death sounds — Implemented
- Music system — Missing
- EVA announcer — Missing
- Audio content on fresh clone — Partial — `games/ts/external_assets/` gitignored; `.ogg` absent
- Terrain rendering (MultiMesh per submesh) — Partial — art gaps fall back to pink placeholder
- Water rendering — Missing/Partial — water is a land type only; no dedicated water plane/shader

## 11. Campaign & mission scripting

- Map editor tools (height/resource/tree/entity/erase/player-start) — Implemented
- Map editor dialogs/menus — Implemented
- Player start locations + camera framing — Implemented
- Editor save/load JSON — Implemented — `EditorSaveLoad.gd`
- Map JSON v3/v4 + terrain overlays + houses — Implemented — `MapLoader.gd:129`
- Theater system — Partial — 1 theater (`temperate.tres`); no editor theater selection tool
- Terrain object catalog + isotem tooling — Implemented — spec `isotem-tooling`
- Asset preview scene — Implemented
- Trigger / event / action engine — Missing — largest subsystem gap
- Objectives + win/lose conditions — Missing
- Mission boot / briefing / start camera — Missing — hooks only
- Scripted teams / reinforcements — Missing
- Non-start waypoints — Missing
- Campaign progression — Missing
- Land-type paint in editor — Partial — `TerrainSystem.set_land_type:334`; `MapEditor.Tool` enum lacks it
- Editor undo/redo — Missing
- Water/cliff authoring in editor — Missing

## 12. Skirmish, multiplayer, modding, game definitions

- Game definitions + discovery — Implemented — `GameDefinition.gd`; `GameContext.gd:56,185`
- Boot game selection + persisted choice — Implemented — `GameContext.gd:85`
- Data-set layering (last-wins, borrowing) — Implemented — spec `game-content`
- Cross-game id collision validation — Implemented — `GameContext.validate_id_collisions:121`
- Per-game rules wiring/validation — Implemented — `EntityFactory.set_global_rules:487`
- Modding data-set scaffold — Implemented — `register_data_set()` (4 autoloads)
- Mod manager / load-order versioning / mod UI — Missing
- Multiple games (FS/RA2/YR) — Missing — only `games/ts` exists
- Faction catalog + rosters — Implemented — `FactionCatalog.gd`; spec `factions`
- Skirmish setup UI / map selection — Missing
- AI opponents / bot logic — Missing — `PlayerConfig.is_bot` unused
- Multiplayer / netcode — Missing
- Replays — Missing
- House assignment / ownership — Implemented — `Houses.gd`; spec `map-houses`
- MapConfig players/teams/spawns/credits — Implemented — `MapConfig.gd`

---

## Feature count by status

| Status | Count |
|--------|------:|
| Implemented | 120 |
| Partial | 26 |
| Spec-only | 0 |
| Missing | 52 |
| **Total** | **198** |

All 95 spec directories map to code (specs are archived only after implementation), so pure
Spec-only is zero; the real gap is **Partial** (schema-first fields with no consumer) and
**Missing** (no spec, no code).

## Doc drift (docs contradict code)

- `plans/00-0_project_status.md` (2026-08-08) — false "Fog of war / vision — 0% … entire system missing".
- `plans/00-0_project_status.md` — "projectiles, turret … unused"; both shipped.
- `plans/00-0_project_status.md` — "no minimap", "no pause"; both exist.
- `plans/00-0_project_status.md` — "22 autoloads", "63 specs", "74 test files"; actual 28 / 95 / 139.
- `plans/4-1_fog_vision.md` — "Entirely greenfield — 0%" contradicted by `ShroudSystem.gd`.
- `plans/3-1_combat_weapons.md` — wrong damage formula; `WarheadData` exists.
- `plans/7-2_unit_roster.md` — "AIRCRAFT no weapons" (false); "land types 6" (actual 11).
- `plans/2-1_navigation.md` — overview "No global pathfinding" contradicted by `Pathfinder.gd`.
- `AGENTS.md` — "23 components" (actual 29), "37 scenes" (46), "22 design docs" (25).
- Engine-version skew: resolved — plans, AGENTS and CI all use Redot 26.2.

## Notable absences (cross-title features with no spec and no code)

- Superweapons & support powers: nuclear missile, ion cannon, weather control, chronosphere,
  iron curtain, psychic dominator, genetic mutator, force shield, gap generator.
- Spy infiltration / thief / disguise / mind control / psychic systems.
- Garrisoning / building occupation / fire-from-transport / bunkers.
- Naval warfare, submarines, water rendering and water/land-type authoring.
- Skirmish/house AI: auto-engage, guard, attack-move, patrol, threat scoring, bot build orders.
- Campaign mission layer: trigger/event/action engine, objectives, win/lose, briefing,
  scripted teams, reinforcements, non-start waypoints, campaign progression.
- Gameplay save/load and load-game UI.
- Multiplayer/netcode, lobby, replay recording.
- Mod manager / load-order management / mod UI.
- Additional game content sets (Firestorm, RA2, Yuri's Revenge) — only `games/ts` exists.
- Control groups (1–0), formation-selection UI.
- Crates; building upgrades/research; cloak/sensor; aircraft landing/rearm; veterinacy XP;
  ammo/reload; wall line-building & gates; bridge destruction/repair; tiberium toxicity;
  EVA announcer; music system; combat VFX/explosions/craters.
