# Project Planning / Roadmap - RTS Edition

## Overview
This document outlines the project planning and roadmap for the ReSun Tiberian Sun remake using the Redot Engine, specifically tailored for real-time strategy game mechanics.

## Current Status
- **Engine Version**: Redot 26.2 LTS
- **Project State**: Core Tiberian Sun systems complete — mission layer + multi-title expansion next
- **Last Updated**: 2026-09-14
- **Live status**: see `00-0_project_status.md` (verified breakdown) and `docs/capability-matrix.md` (feature × title × status)
- **Multi-title goal**: TS + Firestorm + RA2 + YR from one data-driven engine — `plans/12-0_unified_multi_title_expansion.md`

---

## Entity System Foundation (GitHub Issue #22)

**Status**: ✅ Implemented (architecture + core components)

The composition-based entity system is a prerequisite for most game systems. All entities (buildings, units, infantry, terrain) are created from a single `EntityData.gd` resource with dynamically added components.

**Implemented:**
- `EntityData.gd` — single resource class with ALL entity properties
- `EntityFactory.gd` — autoload that creates entities from data, adds components dynamically
- `Entity.tscn` — single base scene (empty Node3D root)
- `WeaponData.gd` — unlimited weapons per entity via `Array[WeaponData]`
- `ArtData.gd` — separate visual properties per entity, model loading via ArtComponent
- `GlobalRules.gd` — default game values from rules.ini, customizable armor types
- 7 new components: StatsComponent, FoundationComponent, PowerComponent, RadarComponent, FactoryComponent, TransportComponent, SpecialAbilityComponent
- Updated components: CombatComponent (unlimited weapons), MovementController (locomotor/movement_zone)
- ArtComponent loads models from ArtData at runtime

**Remaining work** (see GitHub Issues #23-40):
- Data population: ~30 .tres files for entities, weapons, warheads, art
- Component logic: Each component needs actual behavior (see component-specific issues)
- Integration: BuildingManager migration, GlobalRules wiring
- Validation: Component-level validation, graceful degradation

**See**: GitHub Issue #22 for full architecture details

---

## Phase 1: Core RTS Systems (Priority: Critical)

### 1.1 Camera & Selection System
- [x] Implement RTS-style camera controls (pan, zoom, edge-scroll; rotate is NOT implemented)
- [x] Create box selection and multi-select functionality
- [x] Build selection overlay UI system (brackets, health bars, pips)
- [ ] Add smart camera positioning on events
- [x] Test with basic unit movement

### 1.2 Base Building System
- [x] Implement building placement validation rules
- [x] Create construction queue with timing/resources (ProductionManager queue)
- [ ] Build power grid management system (PowerComponent — Issue #33)
- [x] Add building states and destruction logic (sell, repair, destroy cleanup)
- [x] Integrate with economy for costs
- **Note**: Uses EntityFactory + EntityData for building definitions

### 1.3 Economy & Resources
- [x] Define resource types (Credits, Tiberium — ResourceType hierarchy)
- [x] Implement credit generation from structures (harvest → dock → unload → credits)
- [x] Create Tiberium harvesting mechanics
- [x] Build production cost system
- [ ] Add income/expense cycle tracking

### 1.4 Unit Production Pipeline
- [x] Create factory/barracks structure types (FactoryComponent)
- [x] Implement entity data population (populate-entity-data change)
- [x] Implement tabbed build menu sidebar (GitHub Issue #66)
- [x] Implement production queue system (ProductionManager)
- [x] Build prerequisite system (PrerequisiteSystem)
- [x] Add spawn logic for new units via EntityFactory
- [x] Test with various faction units
- **Note**: Units defined as EntityData .tres files

---

## Phase 2: Movement & Pathfinding (Priority: High)

### 2.1 Navigation System
- [x] Choose pathfinding approach (A* — custom grid, NOT NavigationServer3D)
- [x] Build grid from terrain (Pathfinder.gd, A* with binary-heap + terrain costs)
- [x] Implement dynamic obstacle avoidance (radial repulsion steering)
- [x] Add terrain cost modifiers (per-locomotor terrain_speeds, slope, bib penalty)
- [x] Create path smoothing for units (Catmull-Rom splines, LOS string-pulling)

### 2.2 Unit Movement & Commands
- [x] Implement move command with path following
- [x] Create attack command system (left-click enemy → chase → fire)
- [ ] Build patrol command (gather exists via HarvestComponent; patrol missing)
- [ ] Add formation system (static offsets only, no FormationComponent)
- [x] Test unit pathing in various terrains

---

## Phase 3: Combat System (Priority: High)

### 3.1 Damage & Weapons
- [x] Define damage types via WarheadData resources (27 .tres)
- [x] Create armor types via GlobalRules.armor_types (5 ArmorType .tres)
- [x] Build WeaponData resource system (44 .tres, unlimited weapons per entity)
- [x] Implement projectile or hitscan systems via CombatComponent (hitscan + runtime projectiles shipped; splash/AoE missing)
- [ ] Add unit health/regeneration mechanics (HealthComponent exists; regen not implemented)
- **Note**: Weapons defined in resources/weapons/ .tres files

### 3.2 Combat AI
- [ ] Create target selection logic for units
- [ ] Implement combat states (idle, chase, attack, flee)
- [ ] Build engagement radius and retreat rules
- [ ] Add morale/stamina systems if applicable
- [ ] Test combat scenarios against various enemies
- **Note**: Entirely greenfield — units only fight when player-ordered

---

## Phase 4: Fog of War & Vision (Priority: Medium)

### 4.1 Vision System
- [x] Design fog of war layers (explored, unexplored, hidden — ShroudSystem shroud/fog grids)
- [x] Implement vision radius per unit/structure (VisionComponent revealers)
- [x] Build line-of-sight calculations against terrain/buildings (height-aware shadowcasting)
- [x] Add dynamic fog updates on movement/death events (FogRenderer + ghosts)
- [x] Create minimap integration (Minimap + radar gating)
- [ ] Cloak/stealth + sensor detection (schema-only today)

### 4.2 Map Exploration
- [ ] Track explored map percentage for win conditions
- [x] Implement vision sharing between units/structures (ref-counted revealers + ally sharing)
- [x] Add reveals mechanics (temporary area reveals); blackout/gap generator still missing
- [ ] Test with various unit compositions

---

## Phase 5: UI/UX & Interface (Priority: Medium)

### 5.1 RTS Interface Elements
- [x] Build tabbed sidebar with 4 categories (GitHub Issue #66)
- [x] Implement production queue display with angular progress
- [x] Implement cursor system with per-unit resolution (GitHub Issue #70)
- [x] Implement centralized input routing — InputSettings autoload, camera actions, edge scroll toggle
- [x] Implement resource HUD (credits + power bar done; Tiberium/income/multi-resource HUD partial)
- [x] Add minimap with unit markers (gameplay Minimap + radar gating done)
- [ ] Create selection panel for selected units (health bars exist; stats/actions panel missing)

### 5.2 Game Management
- [x] Implement pause/resume functionality (PauseMenu + pause-system spec)
- [ ] Add save/load system for game state (only editor JSON today)
- [ ] Create settings/configuration screens (headless InputSettings only)
- [ ] Build main menu and faction selection (MainMenu01 loads TestMap02; full flow missing)
- [ ] Add tutorial or training mode

---

## Phase 6: World & Environment (Priority: Low)

### 6.1 Terrain Systems
- [x] Create terrain types with movement modifiers (LandType .tres + per-locomotor terrain_speeds)
- [x] Implement elevation/height system (TerrainSystem heightfield + cascade)
- [x] Add Tiberium fields distribution (paint tool + ResourceGrowthSystem)
- [ ] Build environmental hazards if applicable (ice works; radiation/toxicity missing)
- [x] Test terrain interaction with units/buildings
- **Note**: Terrain objects use EntityData with entity_type=TERRAIN

### 6.2 Map Design Tools
- [x] Create level editor or map import pipeline (MapEditor + JSON v4)
- [ ] Implement scenario scripting system (entirely missing — needed for missions)
- [ ] Add trigger/event system for missions (entirely missing)
- [ ] Build campaign structure for single-player (entirely missing)

### 6.3 Tiberium Growth
- [x] ResourceGrowthSystem (tree + crystal timers, batching, spread limits)

---

## Phase 7: Factions & Content (Priority: Medium)

### 7.1 Faction Systems
- [x] Implement GDI faction data (.tres)
- [x] Create Nod faction data (.tres)
- [ ] Build unique unit/structure differences per faction (data-level differences exist; no mechanic bonuses)
- [ ] Add faction-specific tech trees (per-faction prerequisite data; no research/upgrades)
- [ ] Test faction balance in combat scenarios
- **Note**: Faction bonuses stored in GlobalRules.gd; no FactionManager/bonus logic yet

### 7.2 Unit Roster
- [x] Implement infantry units (EntityData .tres files — 26)
- [x] Create vehicle units (EntityData .tres files — 38)
- [x] Build aircraft units if applicable (8; weapons populated on fighters/bombers)
- [ ] Add hero/special units with unique abilities
- [ ] Test all unit interactions and counters
- **Note**: All units defined in resources/entities/ .tres files (~408 total)

---

## Phase 8: Advanced Features (Priority: Low)

### 8.1 Multiplayer Support
- [ ] Design network architecture for multiplayer
- [ ] Implement sync system for game state
- [ ] Add lobby/matchmaking features
- [ ] Create replay system for recorded games
- [ ] Test multiplayer stability and latency handling

### 8.2 Modding Support
- [ ] Create modding framework via EntityFactory.register_data_set()
- [ ] Build asset import/export tools
- [ ] Add script extensibility points
- [ ] Design mod distribution pipeline
- [ ] Document modding API for community
- **Note**: EntityFactory supports layered data sets for mods/DLCs

---

## Phase 9: Testing & Polish (Priority: High - Ongoing)

### 9.1 Quality Assurance
- [x] Set up custom test runner (GUT rejected — breaks on Redot 26.x class_name registration)
- [x] Unit testing for all core systems (74 files, 777 methods, 4364 asserts)
- [x] Integration testing across modules (7 integration suites)
- [ ] Playtesting sessions with gameplay feedback
- [ ] Bug fixes and refinement cycles
- [ ] Performance optimization profiling (open: #221 SDFGI, #222 shadow grain)

### 9.2 Final Polish
- [ ] Visual effects (explosions, damage, construction — none implemented)
- [ ] Animation quality and transitions
- [ ] Sound design and music integration (AudioManager done; music/EVA/content missing)
- [ ] UI/UX polish and accessibility features
- [ ] Documentation for players and modders

---

## Phase 12: Unified Multi-Title Expansion (TS + FS + RA2 + YR)

**Status:** research + gap plan complete — see `plans/12-0_unified_multi_title_expansion.md`
and `docs/`.

- [x] Deep research: current engine state + TS/FS/RA2/YR feature inventories (`docs/research/_raw/`)
- [x] Unified capability matrix + gap analysis (`docs/capability-matrix.md`, `docs/gap-analysis.md`)
- [x] Target architecture: generic engine vs per-title data (`docs/architecture/unified-engine.md`)
- [ ] Lock generic contracts as specs (armor list, projectile, status/aura, superweapon, house/country, mission, theater)
- [ ] Build Tier-2 generic subsystems (status/aura, superweapon framework, control-link, garrison, weapon state machine, house registry, naval/air, economy hooks, skirmish AI, save/load)
- [ ] Author `games/fs` (delta over `ts`)
- [ ] Author `games/ra2` (independent base — stresses TS assumptions)
- [ ] Author `games/yr` (delta over `ra2`)
- [ ] Multiplayer/netcode (deferred)

---

## Resources & Dependencies

- **Engine**: Redot Engine 26.2 LTS
- **Programming Language**: GDScript only (no C# bindings)
- **Documentation**: [Redot Engine Docs](https://docs.redotengine.org/)
- **Version Control**: Git with GitHub Issues for task tracking
- **Build System**: Redot editor workflow (no external build system)

---

## Next Steps

### Next Milestone: GDI Mission 01 (Reinforce Phoenix Base)
Authenticity-first milestone (GitHub milestone #1, 44 issues). Re-scoped 2026-09-14 — scripted triggers/teams/reinforcements/reveals/bridge-destruction are required; final art is a polish phase. Umbrella: #260. Full plan: `plans/13-0_gdi-mission-01_rescope.md`; status: `00-0_project_status.md`.
- **Mission systems:** #236 boot, #237 trigger engine (+#414 CellTags), #238 teams, #239 reinforcements, #240 objectives/win-lose, #415 timer, #241 camera/reveal, #248 wiring, #244 meteor, #250 bridge destruction, #255 music, #258 EVA
- **Map:** #226–#234 (importer, land-type paint, water, cliffs via #230, bridges, buildout, waypoints), #247 placement (+#412 houses, #413 roster gating)
- **Combat/defense:** #261 guard AI, #264 attack + attack-move, #245 defense weapons, #416 building upgrades
- **Pulled deps:** #203 theater, #267 aircraft, #321 impact FX, #323 AoE splash
- **Done / close:** #246 radar, #242 audio, #243 SFX. **Superseded:** #199/#207 → #230. **Descoped:** #265 superweapon targeting
- **Polish (`milestone-polish`):** #235 terrain art, #251 audio content, #252 overlay art, #253 entity art
- **Corrections applied (#226 series):** 52 triggers (not 49), 20 TaskForces (not 22), 36 structures (not 26), 3 GAPOWR all upgraded, CellTags 49064–54064, 53 waypoints; the "~13 missing entities" premise was false

### Priority: First Blood Goal (Issue #84)
End-to-end combat demo: deploy MCV → build base → train infantry → destroy enemy Con Yard. See `plans/10-1_first_blood_goal.md` for full breakdown.

1. ~~**Per-Player Data & Logic** (Issue #77)~~ ✅
2. ~~**MapEditor Entity Placement** (Issue #83)~~ ✅
3. ~~**MCV Deploy** (Issue #80)~~ ✅
4. ~~**Weapon Data** (Issue #23)~~ ✅
5. ~~**Prerequisite Chain** (Issue #81)~~ ✅
6. ~~**Attack Command** (Issue #79)~~ ✅
7. ~~**CombatComponent Firing** (Issue #28)~~ ✅ — hitscan MVP, fire rate timer, range check, target tracking, player-move-cancels-attack
8. ~~**Death Handling** (Issue #30/#82)~~ ✅ — death handler now frees node + unregisters cells (voice + cleanup)
9. **Projectile System** (Issue #78) + **ProjectileData Resource** (Issue #89) — future upgrade from hitscan
10. **HitboxComponent** (Issue #29) — future upgrade, needs projectile to trigger it

### Remaining Component Logic (Issues #28-40)
- **Economy**: PowerComponent (#33)
- **Movement**: Locomotor enforcement (#34), Terrain movement costs (#51) — mostly done
- **UI**: Infantry health bars (#39), Art damaged states (#38)

### Infrastructure
- **GlobalRules Integration** (Issue #26) — wire armor, veterancy, movement coefficients
- **BuildingManager Migration** (Issue #25) — move from BuildingType to EntityFactory
- **Debug Menu** (Issue #27) — in-game debug tools for testing
- Conduct early playtesting to validate design decisions
- Review weekly and adjust timeline based on actual development velocity

---

*Last updated: 2026-09-14 — multi-title research + docs set added; roadmap reconciled to verified codebase state (`plans/00-0_project_status.md`, `docs/`)*
