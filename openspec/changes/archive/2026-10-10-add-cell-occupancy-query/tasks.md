# Tasks

## 1. Composite query on SpatialHash

- [x] 1.1 Add inner `class CellOccupancy extends RefCounted` (fields per design D1) to
  `scripts/core/SpatialHash.gd`. It MUST be an inner class (GDScript allows one `class_name` per
  file; `SpatialHash.gd:1` already declares one). Add
  `get_cell_occupancy(cell: Vector2i, level: int = 0, exclude: Node3D = null) ->
  SpatialHash.CellOccupancy`: permanent facts from `_building_cells`/`_bib_cells`/`_resource_cells`
  (`cell_key`, ground) and `TerrainSystem.is_cell_buildable(cell)`; momentary facts from `_grid`
  entries at `level` with a non-null `mc` (minus `exclude`) → `units: Array[Node3D]`, with
  `blocked`/`moving`/`shared_count` derived from each entry's `state` and `shares`. Verify
  `test/unit/test_spatial_hash.gd` still passes via `redot --headless -s test/run_tests.gd`.
- [x] 1.2 Add the three projections (design D2):
  `is_cell_free_for_build` = terrain ∧ ¬building ∧ ¬bib ∧ ¬resource ∧ units empty;
  `is_cell_free_for_unit_exit` = ¬building ∧ ¬bib ∧ ¬blocked ∧ ¬moving ∧
  `shared_count < get_slot_count()` (no terrain term — walkability is a locomotor concern);
  `is_cell_free_for_resource` = terrain ∧ ¬building ∧ ¬bib.
  Note `reserved` is exposed but used by NO projection. Verify the full suite.
- [x] 1.3 Add `test/unit/test_cell_occupancy.gd`. Seed permanent facts with the public registrars
  (`register_building_cells`, `register_bib_cells`, `register_resource_cell`); seed momentary
  facts by spawning real entities + `SpatialHash.rebuild()`; seed `reserved` with
  `force_reserve`. Assert: snapshot fields; each intent for positive/negative cases;
  `is_cell_free_for_build` refuses any unit (idle, moving, sharer); `is_cell_free_for_unit_exit`
  **allows one idle sharer below capacity and refuses at capacity** (the non-vacuous shared-exit
  test that the original design missed); exclusion removes only the named unit and does not hide
  `reserved`. Tear down fully (unregister cells, `clear_reservations`, free spawned nodes,
  re-`init_grid`) because `test/run_tests.gd` shares one process. Confirm the test fails before
  1.1/1.2 and passes after.

## 2. Terrain buildability predicate and seed setter

- [x] 2.1 Add `TerrainSystem.is_cell_buildable(cell) -> bool` and
  `TerrainSystem.set_cell_type(cell, type) -> void` (specs `cell-surfaces`). `is_cell_buildable`
  MUST return false for a cell outside the grid extent (add a bounds guard; `get_cell_type`
  returns `""` for out-of-extent cells). Verify with the suite.
- [x] 2.2 Repoint `get_cell_occupancy.terrain_buildable` at `TerrainSystem.is_cell_buildable`.
  Add `test_cell_occupancy` cases: an in-bounds cell seeded `set_cell_type(cell, "clear")` is
  buildable and the round-trip `get_cell_type(cell) == "clear"` holds first (guard against a
  vacuous pass); `set_cell_type(cell, "slope")` is not; an out-of-bounds cell is not. Verify.

## 3. Building placement and deploy

- [x] 3.1 Reimplement `FoundationComponent.is_cell_buildable`
  (`scripts/components/FoundationComponent.gd:129`) as
  `SpatialHash.instance.is_cell_free_for_build(cell)` with the null-guard preserved. The reject
  set is unchanged (no reservation term). Verify `test/unit/test_foundation_component.gd`,
  `test/unit/test_building_manager.gd`, `test/integration/test_placement_highlight_integration.gd`.
- [x] 3.2 Reimplement `DeployComponent._is_cell_free_for_deploy`
  (`scripts/components/DeployComponent.gd:198`) as
  `is_cell_free_for_build(cell, 0, source_entity)`; delete `_is_only_source_blocking` and
  `_is_only_source_on_cell`; route `_can_scatter_cell`'s permanent checks through
  `get_cell_occupancy`. Verify `test/unit/test_deploy_component.gd`.
- [x] 3.3 Add a deploy test: a cell blocked only by the deploying source (including a source
  whose reservation exists) is free; the same cell with a second unit is refused. Verify the
  case fails against the old helper and passes after.

## 4. Production exit

- [x] 4.1 Replace `FactoryComponent._is_cell_available` (`scripts/components/FactoryComponent.gd:142`)
  and `ExitComponent._is_cell_available` (`scripts/components/ExitComponent.gd:163`) with
  `SpatialHash.instance.is_cell_free_for_unit_exit`. Note this adds the moving-unit block; it does
  **not** add a terrain gate (walkability is deferred to #469/#370). The two `_find_free_near`
  spirals are byte-identical and match `CellUtil.spiral_first_free`'s order, so they MAY be
  collapsed onto it. Verify `test/unit/test_factory_component.gd`, `test/unit/test_exit_component.gd`.
- [x] 4.2 Route `ProductionManager._find_exit_cell` (`scripts/production/ProductionManager.gd:380`)
  through `is_cell_free_for_unit_exit` via `spiral_first_free`. Verify
  `test/unit/test_production_manager.gd`.
- [x] 4.3 Add exit tests: a moving unit on the only adjacent cell blocks the exit; one idle sharer
  below capacity does **not** block; a tiberium cell is a valid exit cell; a slope cell is accepted
  (walkable). Verify each fails against the old predicates and passes after.
- [x] 4.4 Record the pre-existing gap that `ExitComponent`/`FactoryComponent` return the
  building's own cell when nothing is free (spec `production-exit` documents this as follow-up).
  No behavior change here.

## 5. Free-unit spawn

- [x] 5.1 Reimplement `FreeUnitComponent._find_adjacent_free_cell`
  (`scripts/components/FreeUnitComponent.gd:74`) to use `get_cell_occupancy` +
  `is_cell_free_for_build` plus the `reserved` fact; remove the direct
  `SpatialHash.instance._reserved` read. Verify the owning suite.
- [x] 5.2 Add free-unit cases: a bib cell, a resource cell, and a reserved cell are skipped, and an
  origin at the map edge never returns an out-of-bounds cell. Verify.

## 6. Tiberium spread

- [x] 6.1 Change `ResourceGrowthSystem._is_cell_blocked_for_resource`
  (`scripts/core/ResourceGrowthSystem.gd:295`) to `not is_cell_free_for_resource(cell)`, removing
  the private `_building_cells`/`_bib_cells` reads, the `is_cell_blocked` (idle-unit) check, and
  gaining the terrain gate. Verify `test/unit/test_resource_growth_system.gd`.
- [x] 6.2 Add the source-side freeze (design D5) in `_try_spread_from`
  (`ResourceGrowthSystem.gd:189`): refuse to spread when `get_cell_occupancy(cell).units` is
  non-empty. Scope it to resource-to-resource spread — do NOT gate `_spawn_in_radius` tree
  seeding. Verify: an idle unit on a tiberium cell prevents it seeding a neighbor; removing the
  unit resumes spread; a unit on a tree cell does not stop tree seeding.
- [x] 6.3 Regression tests: tiberium spreads onto an occupied (idle-unit) target; tiberium does
  not spread onto water/slope. Verify the target and terrain cases fail against the old
  implementation and pass after.

## 7. Normalize, migrate test seeding, document

- [x] 7.1 Normalize the change's target main specs that OpenSpec refuses to archive into:
  `openspec/specs/building-placement-blocking/spec.md`, `factory-component/spec.md`,
  `free-unit/spec.md`, `production-exit/spec.md` — replace the leading `## ADDED Requirements`
  with a `# <name> Specification` + `## Purpose` + `## Requirements` header. Verify
  `openspec validate --specs` no longer errors on these four and
  `openspec validate add-cell-occupancy-query` shows no archive-refusal INFO for them.
- [x] 7.2 Replace the offset-key `_cells` writes in the affected terrain fixtures with public
  `set_cell_type` seeding: `test/unit/test_building_manager.gd`,
  `test/unit/test_foundation_component.gd`, `test/integration/test_building_placement.gd` (and
  route `test_foundation_component`'s `_ok` through `TestHelper` so its assertions are counted).
  NOTE: those fixtures wrote `_cells` under an offset key and asserted on a different cell, so they
  only passed because `""` is also buildable — migrated fixtures seed the exact asserted cell and
  assert the round-trip. `test/unit/test_spatial_hash.gd` and
  `test/integration/test_placement_highlight_integration.gd` still poke registries directly and are
  left as-is. Verify the full suite.
- [x] 7.3 Add the `cell occupancy query` term to `GLOSSARY.md` in the **Grid & Cells** cluster
  (not Placement & Building), pointing at `openspec/specs/cell-occupancy/spec.md`; verify the
  link target exists.
- [x] 7.4 Run `gdlint scripts/**/*.gd test/**/*.gd` and
  `gdformat --check scripts/**/*.gd test/**/*.gd`; after `gdformat`, run
  `grep -P '\t' scripts/**/*.gd` to confirm no tabs entered multi-line strings.
