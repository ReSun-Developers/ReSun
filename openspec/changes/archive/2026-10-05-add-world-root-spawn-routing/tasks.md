# Tasks

## 1. World spawn seam

- [x] 1.1 Add `class_name World` and a static accessor to `scripts/core/World.gd`: `_enter_tree`/`_exit_tree` register and clear a `static var _active`, and the accessor returns the live root only when `is_instance_valid`, `is_inside_tree`, and not queued for deletion. Verify a unit test that the accessor returns the live World and returns `null` for a freed/outgoing root.
- [x] 1.2 Add static `spawn_container(bucket, fallback)` and instance `spawn(node, bucket)` with an `Entities`/`Effects` bucket enum, lazily creating each container under the World root; when no World is live, resolve the explicit fallback, then `current_scene`, then `tree.root`. Verify a unit test asserts a spawned node lands in the expected bucket and that a second World replaces the first.
- [x] 1.3 Extend `test/unit/test_world_root.gd` to cover the accessor, the no-World fallback chain, and per-bucket placement. Verify `redot --headless -s test/run_tests.gd` reports the new assertions passing.
- [x] 1.4 Document the seam on `World.gd` (accessor guarantees, `spawn`/`spawn_container`, the no-World fallback, that spawners with an explicit in-tree parent keep it) and update `GLOSSARY.md` only if a new term is needed. Verify the doc comment names the accessor and `spawn` and matches the implemented behavior.

## 2. Route gameplay entity spawning

- [x] 2.1 Change `scripts/entities/EntityPlacer.gd` `place_entity` (no explicit parent) and `start_preview` to resolve the destination through `World.spawn_container(World.Bucket.ENTITIES)`. Verify a test produces a unit via `FactoryComponent`/`ProductionManager` and asserts it is a descendant of the match World root, and that a preview ghost is parented under the World root.
- [x] 2.2 Change `scripts/buildings/BuildingManager.gd` so `_find_buildings_parent` resolves the World `Entities` container instead of looking up/creating `Main/Buildings`, and `_get_buildings_parent` re-resolves when its cached node is invalid or out of tree (no stale bucket across a swap). Verify a test builds a structure and asserts it is under the World root with no `Main/Buildings` node created.
- [x] 2.3 Change `scripts/components/DeployComponent.gd` fallbacks to route deployed/undeployed structures through the same seam instead of `current_scene`. Verify a deploy/undeploy test places the resulting structure under the World root.
- [x] 2.4 Remove the dead `Buildings` node from `scenes/maps/MapBase01.tscn`; sanity-check `scenes/maps/TestMap01.tscn` child-index overrides for the shifted index. Verify the mission map still loads and `test/integration/test_match_swap.gd` passes.
- [x] 2.5 Update `test/unit/test_placing_session.gd` (preview ghost) and any placement test asserting the old parent so they pass under the seam. Verify the full unit suite passes.

## 3. Route combat and effects

- [x] 3.1 Change `scripts/components/CombatComponent.gd` `_spawn_projectile` to resolve the container through `World.spawn_container(World.Bucket.EFFECTS, shooter.get_parent())`, removing the `current_scene` lookup. Verify `test/integration/test_projectile_flight.gd` passes and a new assertion (using a World fixture) finds a fired projectile under the World root.
- [x] 3.2 Change `scripts/core/FxSystem.gd` `_effect_parent` to resolve the World `Effects` container, falling back to `current_scene` then `tree.root` when no World exists, keeping the explicit `parent` override. Verify `test/unit/test_fx_system.gd` passes and an effect is under the World root with the no-World fallback intact.

## 4. Route runtime resource growth

- [x] 4.1 Remove the cached `_resource_parent` in `scripts/core/ResourceGrowthSystem.gd` and resolve the spawn container through the seam in `_spawn_at_cell`; drop the unused cache assignment in `_rebuild_cache`. Verify `test/unit/test_resource_growth_system.gd` is reworked so it no longer reads/writes `_resource_parent` (add a World and inspect its `Entities` bucket) and passes.
- [x] 4.2 Add a resource-growth assertion that spawning after a World is replaced parents under the new World's `Entities` container. Verify the new assertion fails if the container is cached.

## 5. Teardown integration proof

- [x] 5.1 Extend `test/integration/test_match_swap.gd` to drive the real spawn paths in match 1 (produce a unit, build a structure, fire a projectile, play an effect, grow a resource), record the produced nodes, start match 2, and assert synchronously that every recorded node is `not is_inside_tree()` and the outgoing World root `is_queued_for_deletion()`, with a non-empty guard. Verify the test fails if a spawn site is reverted to `current_scene`.
- [x] 5.2 Add an assertion that a spawn issued after the second `start_mission` resolves to the incoming World root. Verify the incoming match owns the node.
- [x] 5.3 Run `redot --headless -s test/run_tests.gd` and confirm the full suite passes.
- [x] 5.4 Run `gdlint scripts/**/*.gd test/**/*.gd` and `gdformat --check scripts/**/*.gd test/**/*.gd`, then `grep -P '\t' scripts/**/*.gd` for tab introduction, and confirm all pass.
