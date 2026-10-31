# Tasks

## 1. Regression tests (fail on base first)

- [x] 1.1 Add `test/integration/test_one_by_one_structure_occupancy.gd` with setup/teardown that snapshots and restores `BuildingManager._buildings`, `PrerequisiteSystem._player_buildings`, and `SpatialHash._building_cells`. Spawn `GDI_SILO` and `GDI_WALL` through `EntityFactory.spawn` on a `TerrainSystem` grid; assert the cell is free before the spawn, then assert `get_cell_occupancy(cell).building == true`, `is_cell_free_for_build(cell) == false`, `is_cell_free_for_unit_exit(cell) == false`, `get_blocked_cells()` contains the cell, and `Pathfinder.find_path` from one side to the other does not pass through it. Run on base and capture the failures.
- [x] 1.2 In the same suite, assert `SpatialHash.resolve_cell_victim(cell, ...)` returns the spawned structure after `rebuild()` (coverage check; it already passes on base via `_grid`). Add a `GDI_PAVEMENT` case asserting its cell stays free, which locks the non-solid exception.
- [x] 1.3 Migrate `test_order_system_modes._make_building` to `EntityFactory.create_entity("GDI_SILO")` with `StatsComponent.player_id` and `HealthComponent.current_health` set directly, and verify the sell/repair mode tests pass once the fix lands.

## 2. Fix

- [x] 2.1 Add `EntityData.blocks_cells` (default `true`) and mirror it on `FoundationComponent` (`configure` copies it; `_ready` skips registration when false).
- [x] 2.2 Change `EntityFactory._add_foundation_component` to attach for every solid BUILDING, preserving the `foundation != Vector2i(1, 1)` branch for non-buildings. Verify the new integration test passes.
- [x] 2.3 Set `blocks_cells = false` on `games/ts/entities/structures/gdi/gdi_pavement.tres` and the six `civ_invisible_*_light*.tres` files; verify their cells stay free.
- [x] 2.4 Rename the overlay ids in `games/ts/entities/overlay/gdi_wall.tres` and `nod_wall.tres` to `GDI_WALL_OVERLAY`/`NOD_WALL_OVERLAY`; verify `EntityFactory.get_entity_data("GDI_WALL")` returns the BUILDING structure.
- [x] 2.5 Update stale comments that claim 1×1 buildings have no `FoundationComponent`: `scripts/components/CombatComponent.gd`, `scripts/ui/Minimap.gd`, `test/unit/test_combat_component.gd`.
- [x] 2.6 Confirm existing building-placement, minimap, fog, dock-host, entity-factory-spawn, combat, guard, projectile, and order-system suites still pass.

## 3. Gates

- [x] 3.1 Run `gdlint scripts/**/*.gd test/**/*.gd` and `gdformat --check scripts/**/*.gd test/**/*.gd`; fix any findings.
- [x] 3.2 Run `grep -P '\t' scripts/**/*.gd test/**/*.gd` and confirm no tabs.
- [x] 3.3 Run `flock /tmp/opencode/redot.lock redot --headless -s test/run_tests.gd` and confirm the full suite passes.
