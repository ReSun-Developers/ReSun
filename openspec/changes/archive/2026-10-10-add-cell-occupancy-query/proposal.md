# Proposal

## Why

"Is this cell free for X?" is re-derived in eight functions across seven files, each checking a
different subset of the facts:

- `FoundationComponent.is_cell_buildable` (`scripts/components/FoundationComponent.gd:129`) —
  building · bib · resource · blocked · any-entity · terrain.
- `DeployComponent._is_cell_free_for_deploy` (`scripts/components/DeployComponent.gd:198`) —
  the same six, plus source exclusion.
- `FreeUnitComponent._find_adjacent_free_cell` (`scripts/components/FreeUnitComponent.gd:74`) —
  building · blocked · `SpatialHash.instance._reserved` (private read) · terrain; **no**
  bib/resource/entity.
- `ExitComponent._is_cell_available` (`scripts/components/ExitComponent.gd:163`) and
  `FactoryComponent._is_cell_available` (`scripts/components/FactoryComponent.gd:142` —
  byte-identical duplicate) — building · bib · blocked · shared-capacity; **no** terrain/entity.
- `ProductionManager._find_exit_cell` (`scripts/production/ProductionManager.gd:380`) — a fourth
  dialect: building · blocked · terrain.
- `ResourceGrowthSystem._is_cell_blocked_for_resource`
  (`scripts/core/ResourceGrowthSystem.gd:295`) — reads `SpatialHash.instance._building_cells`
  and `._bib_cells` directly.

The same class of placement bug therefore has to be fixed eight times. `BuildingManager.can_place`
and `_resolve_highlight_cell_state` route through `FoundationComponent` and agree today, but the
spawn/exit/resource paths have quietly drifted: they miss moving units and sharers, leak private
registries, and re-encode the `""`/`"clear"` terrain convention per site.

Verified against the original TS engine (`OpenTS-Developers/TibSun`): TS has no single cell
predicate either — it has two shared ones (`CellClass::Is_Clear_To_Build`, and
`Can_Enter_Cell`/`Is_Clear_To_Move` for movement) plus per-feature refinements, with placement
orchestrated by `TechnoTypeClass::Legal_Placement`. Centralizing around a small set of well-named
intents is aligned with the original design, not novel.

## What Changes

- Add one composite occupancy query at the `SpatialHash` seam:
  `SpatialHash.get_cell_occupancy(cell, level, exclude) -> SpatialHash.CellOccupancy`. The result
  partitions a cell's momentary occupants (`units`, `blocked`, `moving`, `shared_count`) and
  reports the permanent facts (`building`, `bib`, `resource`, `terrain_buildable`) and `reserved`.
- Add three intent projections built on the snapshot so the shared semantics are encoded once:
  `is_cell_free_for_build`, `is_cell_free_for_unit_exit`, `is_cell_free_for_resource`.
- Route every consumer through them: `FoundationComponent`, `DeployComponent`,
  `FreeUnitComponent`, `ExitComponent`, `FactoryComponent`, `ProductionManager`,
  `ResourceGrowthSystem`. Delete the duplicated `_is_cell_available` copies, the private registry
  reads, and `Deploy`'s `_is_only_source_*` helpers.
- Converge the intents to original-TS behavior (behavior change, not rename-only):
  - **EXIT** now refuses a cell occupied by a **moving** unit (TS `Find_Exit_Cell` demands
    `MOVE_OK`; a moving occupant is `MOVE_MOVING_BLOCK`) and allows idle sharers up to
    `shared_slots_per_cell` (preserving current `is_cell_full_for_shared` behavior). A resource
    (tiberium) cell stays valid and non-`"clear"` terrain (a walkable slope) stays valid — the
    exit test is a movement test, not buildability.
  - **RESOURCE** (tiberium seeding) now ignores units standing on the target cell (TS
    `Can_Tiberium_Germinate` has no occupant test) and gains the terrain gate (TS `Ground[].Build`).
    A unit on a tiberium cell now stops that cell spreading (TS `Can_Tiberium_Spread` rejects an
    occupied source), scoped to resource-to-resource spread only.
- Move the `""`/`"clear"` terrain convention into one predicate,
  `TerrainSystem.is_cell_buildable(cell)` (false for out-of-bounds cells), read by the query. Add
  `TerrainSystem.set_cell_type` so terrain cells can be seeded without poking `_cells`.

**Deliberately NOT in this change:** folding `SpatialHash._reserved` into the build intent. TS
reserves only a unit's destination cell, but ReSun also force-reserves each selected unit's own
origin cell (`SelectionManager.request_move`) and dock-pad/tiberium cells, so folding it in would
make freshly-vacated empty cells unbuildable. The snapshot still exposes `reserved`; a follow-up
SHALL reconcile reservation lifetime and then fold it in.

## Capabilities

### New Capabilities

None — the query extends the existing `cell-occupancy` capability.

### Modified Capabilities

- `cell-occupancy`: broadened from sub-slot capacity to the canonical description of what
  occupies a cell and the three occupancy intents; the query is its implementation.
- `spatial-hash`: adds the `CellOccupancy` inner class and `get_cell_occupancy` /
  intent-projection API alongside the existing per-registry queries.
- `building-placement-blocking`: the per-cell test routes through the shared query (the reject
  set is unchanged — no reservation term).
- `foundation-component`: `is_cell_buildable` delegates to the shared query instead of
  enumerating registries.
- `production-exit`: exit-cell selection routes through `is_cell_free_for_unit_exit` (moving
  units and terrain block; resources do not; idle sharers below capacity allowed).
- `factory-component`: the no-`ExitComponent` fallback uses the shared exit query, not a private copy.
- `free-unit`: adjacent-cell search uses the build intent plus the reservation fact.
- `resource-growth-system`: tiberium target rules ignore units and gain the terrain gate; a new
  source-side requirement stops spread from a tiberium cell occupied by a unit.
- `cell-surfaces`: adds the single terrain-buildability predicate and a cell-type seeding setter.

## Impact

- Code: `scripts/core/SpatialHash.gd`, `scripts/core/TerrainSystem.gd`,
  `scripts/components/FoundationComponent.gd`, `scripts/components/DeployComponent.gd`,
  `scripts/components/FreeUnitComponent.gd`, `scripts/components/ExitComponent.gd`,
  `scripts/components/FactoryComponent.gd`, `scripts/production/ProductionManager.gd`,
  `scripts/core/ResourceGrowthSystem.gd`.
- Tests: new `test/unit/test_cell_occupancy.gd`; migrate private-registry pokes in
  `test/unit/test_spatial_hash.gd`, `test/unit/test_building_manager.gd`,
  `test/unit/test_foundation_component.gd`, `test/integration/test_building_placement.gd`,
  `test/integration/test_placement_highlight_integration.gd`, `test/unit/test_deploy_component.gd`,
  `test/unit/test_resource_growth_system.gd`; add exit cases to
  `test/unit/test_factory_component.gd`, `test/unit/test_exit_component.gd`,
  `test/unit/test_production_manager.gd`; add free-unit cases to the owning suite.
- No scene or `.tscn` changes; no autoload changes. Consumer public signatures are preserved or
  made private where already private.
- Behavioral edges: a produced unit no longer spawns into a moving friendly; tiberium grows under
  units but stops spreading from a covered patch; out-of-grid cells are no longer buildable. Each
  is documented and tested.
- Follow-ups (not this change): reconcile reservation lifetime and fold `reserved` into BUILD;
  unify the `ExitComponent`/`FactoryComponent` "no free cell" fallback (they currently spawn at
  the building's own cell) with the retained-retry behavior; locomotor-aware exit terrain.
- Cross-references: #470 (land-type sentinel constants — this change relocates the existing
  `""`/`"clear"` comparison, adds no constants), #473 (relocates these systems under a World
  root — independent), #469/#370 (movement passability/locomotor — deferred).
