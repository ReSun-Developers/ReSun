# Proposal

## Why

Bringing an entity into the world is re-implemented at twelve call sites, and the
registries a building must join (cell occupancy, the building registry, prerequisite
counts, death cleanup) are registered manually at each site — incompletely and
inconsistently. Runtime-placed buildings, map-loaded buildings, and deployed buildings
therefore diverge: map buildings never enter the building registry or prerequisite
counts, deployed buildings are never wired to death cleanup, deploy registers bib cells as
blocked, and editor ghost previews leak occupancy into the live world. Fixing the
placement class of bug once requires a single insertion seam.

## What Changes

- **One entry seam.** Add `EntityFactory.spawn(entity_id, placement)` as the single path by
  which an entity enters the world. It owns assembly plus insertion: position, player
  assignment, parenting, tree insertion, and the spawn event. Callers keep placement
  *policy* (cost, placement validation, terrain flattening, build-up animation, map
  rotation/deck height, health overrides).
- **Detached mode.** `spawn(..., {detached: true})` inserts an entity into the scene for
  rendering but excludes it from every world registry and group. It replaces the ad-hoc
  preview-suppression flags with one marker set only by the seam. Five existing consumers
  of the old `_preview` flag (`FoundationComponent`, `UnitMeshRenderer` in two places,
  `GuardComponent`, `FreeUnitComponent`, `FogRenderer`) are migrated to the detached
  marker.
- **Occupancy registered once.** Cell occupancy is owned by `FoundationComponent` on
  entering/leaving the world; the duplicate `register_building_cells`/`register_bib_cells`
  calls in `place_building` and `_do_deploy` are removed. Preview/editor entities never
  register.
- **Uniform building registration.** Every building — runtime-placed, map-loaded, or
  deployed — is registered once into the building registry, into prerequisite counts, and
  to death cleanup, scoped to the building's own owner rather than the local player. The
  building registry stores the bib-excluded occupied cells, matching `FoundationComponent`.
- **Owner-scoped sell with an acting-player gate.** Selling acts on the building's owning
  player and is refused unless the acting (local) player owns the building, so a pre-placed
  building owned by a player is sellable by that player and enemy structures are not.
- **Editor previews and stamps are detached**, so they never pollute occupancy. Map loads
  into the editor are detached as well.
- **Collapse the insertion sites.** All twelve `create_entity` + `add_child` routines,
  including `BuildingManager._create_building_preview`, route through `spawn`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `entity-factory`: add a single `spawn` insertion seam with a detached mode and a spawn event.
- `foundation-component`: occupancy registration happens once per building on entry/exit, suppressed for detached entities.
- `building-manager`: uniform, owner-scoped registration of every building (registry, prerequisites, death wiring) and owner-gated sell.
- `map-loader`: loaded entities enter through the seam and loaded buildings register identically to runtime placements; editor loads detach.
- `entity-placement`: the map editor's preview and stamp paths create detached entities that do not register occupancy.

## Impact

- **Scripts:** `scripts/entities/EntityFactory.gd`, `scripts/entities/EntityPlacer.gd`,
  `scripts/buildings/BuildingManager.gd`, `scripts/components/FoundationComponent.gd`,
  `scripts/components/DeployComponent.gd`, `scripts/components/GuardComponent.gd`,
  `scripts/components/FreeUnitComponent.gd`, `scripts/maps/MapLoader.gd`,
  `scripts/core/ResourceGrowthSystem.gd`, `scripts/core/UnitMeshRenderer.gd`,
  `scripts/core/FogRenderer.gd`, `scripts/editor/EntityPlacer.gd`,
  `scripts/editor/ResourcePainter.gd`, `scripts/editor/EditorSaveLoad.gd`,
  `scripts/orders/SellOrderGenerator.gd`, `scripts/orders/RepairOrderGenerator.gd`.
- **Scenes:** `scenes/entities/Entity.tscn` (the assembled base scene) is unaffected in
  structure; no new node or serialized property is added, so existing packed scenes
  (`.tscn`) load unchanged. `BuildingManager`'s schematic preview node keeps its type.
- **Signals:** `EntityFactory` gains a `spawned(entity, data, player_id)` signal;
  `EntityPlacer.entity_placed` and `BuildingManager.building_placed` remain the
  trigger-facing signals and are still emitted only for runtime placements.
- **Systems:** `SpatialHash` (occupancy), `PrerequisiteSystem` (counts), `BuildingManager`
  registry, `TerrainSystem.flatten_footprint` (runtime policy only).
- **Tests:** `test/integration/test_building_placement.gd` (registration and preview
  cases), `test/unit/test_foundation_component.gd`, `test/unit/test_entity_death.gd`,
  `test/unit/test_building_manager.gd`, `test/unit/test_deploy_component.gd`,
  `test/unit/test_unit_mesh_renderer.gd`, `test/unit/test_guard_component.gd`,
  `test/integration/test_bridge_persistence.gd`, `test/unit/test_map_loader_placement.gd`.
- **Not changing:** map JSON schema, editor save format, production/prerequisite gating
  semantics, package `.tscn` compatibility, and the behaviour of trigger events.
