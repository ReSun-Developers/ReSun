# Tasks

## 1. Add the spawn seam

- [x] 1.1 Add `EntityFactory.spawn(entity_id, placement)` that reuses the existing assembly path and owns insertion: resolve data (`placement.overrides`), assign `placement.player_id` and `placement.world_pos` before tree entry, attach under `placement.parent` (default `World.spawn_container(ENTITIES)`, then current scene), and return the entity. Verify: a new `test/unit/test_entity_factory_spawn.gd` spawns a unit and asserts it is in the tree, positioned, and player-assigned.
- [x] 1.2 Add `placement.detached` handling: set the shared detached marker, add no `entities`/`selectable`/`drag_selectable` groups, assign no player, and emit no spawn event. Verify: the same test spawns a detached building and asserts it is in the tree, joins no groups, carries the detached marker, and emits nothing.
- [x] 1.3 Emit a `spawned(entity, data, player_id)` signal for every non-detached spawn. Verify: the test connects, spawns one detached and one non-detached entity, and asserts exactly one event with the correct player id.
- [x] 1.4 In the same test assert the ordering contract: player id and position are set before the entity enters the tree (spawn a building and a vehicle and assert `StatsComponent.player_id` and the derived origin cell are correct on `_ready`). Verify: the assertions pass and the entity-factory spec scenarios are covered.

## 2. Unify occupancy registration and the detached marker

- [x] 2.1 Make `FoundationComponent` the single occupancy registrant, skipping registration when the entity carries the detached marker. Verify: rewrite `test/integration/test_building_placement.gd` so a detached building registers no cells, a non-detached building registers on entry and clears on exit, and refinery bib cells are tracked but not blocked.
- [x] 2.2 Remove the manual `register_building_cells`/`register_bib_cells` calls from `BuildingManager.place_building` and `DeployComponent._do_deploy`. Verify: a test places then frees a building and asserts the register call count equals the footprint once (count calls, not set size — `SpatialHash` registration is set-semantics and hides duplicates); add a deploy assertion that bib cells are absent from the blocked set after deploy.
- [x] 2.3 Migrate the five `_preview` consumers to the detached marker: `FoundationComponent`, `UnitMeshRenderer._can_register` and `UnitMeshRenderer._physics_process`, `GuardComponent`, `FreeUnitComponent`, and `FogRenderer`. Verify: `test/unit/test_unit_mesh_renderer.gd` and `test/unit/test_guard_component.gd` pass with the marker, and a detached producer spawns no free unit.

## 3. Uniform, owner-scoped building registration

- [x] 3.1 Add `BuildingManager._register_building_entity(entity, data, player_id)` that appends `{node, type, origin, cells}` to `_buildings` with `cells` = `FoundationComponent.occupied_cells(foundation, bib_cells, origin)`, registers the building for `player_id` in `PrerequisiteSystem`, and connects `health_zero` to `_on_building_destroyed`; connect it once to `EntityFactory.spawned` for building entities and remove the self-listening `_on_building_placed` prereq registration. Verify: a test spawns a building for player 2 and asserts it is in `_buildings`, counted for player 2, and death-wired.
- [x] 3.2 In `place_building`, delete the `_buildings.append(...)` block and the `health_zero` connect that the registrar now owns, so a placed building is registered exactly once. Verify: `test/unit/test_building_manager.gd` passes and a placed building yields a single registry entry.
- [x] 3.3 Make `sell_building` and `_on_building_destroyed` read the owner from the building's `StatsComponent` (null-guarded) for the refund and prerequisite unregister instead of the local player, and remove the redundant occupancy unregister (the component owns it on world exit). Verify: a test sells a pre-placed building owned by player 2 and asserts player 2 is credited and unregistered.
- [x] 3.4 Gate the sell order path to the acting player's own buildings: update `SellOrderGenerator` (and the cursor/targeting check it feeds) so a building owned by another player neither shows the sell cursor nor can be sold. Verify: a test asserts an enemy-owned building is refused and no credits move.
- [x] 3.5 Route `place_building` through `spawn`, retaining cost deduction, `flatten_footprint`, build-up animation, production-queue resume, and the `building_placed` emit. Verify: `test/unit/test_building_manager.gd` and the placement integration tests pass unchanged in outcome.
- [x] 3.6 Migrate the build-mode schematic preview in `BuildingManager._create_building_preview` to `spawn(current_building_type.id, {detached: true})` and delete its `set_meta("_preview", …)` call. Verify: entering build mode shows the ghost and places no occupancy cells (a test enters build mode and asserts `_building_cells` is unchanged).

## 4. Migrate the remaining insertion sites

- [x] 4.1 Migrate `EntityPlacer.place_entity` and `start_preview` to `spawn` (preview detached); keep the movement sub-slot assignment after insertion and remove the group-stripping/collision toggles that only suppressed registration. Verify: placement and preview tests pass, a `shares_cell` unit still receives its sub-slot, and `EntityPlacer.entity_placed` is still emitted for final placements.
- [x] 4.2 Migrate `MapLoader.load_map_into` to `spawn`, assigning the player before insertion and keeping rotation-with-slope, deck-height, `house_id` meta, and health overrides caller-side. Verify: `test/unit/test_map_loader_placement.gd` and `test/integration/test_bridge_persistence.gd` pass, and a loaded building is in `_buildings`.
- [x] 4.3 Migrate `DeployComponent._do_deploy` and `_do_undeploy` to `spawn`, delete their manual `_buildings` append, cell registration, and direct `PrerequisiteSystem.register_building` calls, and cover `_complete_undeploy`'s teardown so a transformed-away building is unregistered exactly once. Verify: `test/unit/test_deploy_component.gd` passes and a deployed building is registered exactly once, with no bib cell blocked.
- [x] 4.4 Migrate `ResourceGrowthSystem._spawn_at_cell` to `spawn` (position before insertion preserved). Verify: `test/unit/test_resource_growth_system.gd` passes.

## 5. Detach the editor and editor-load paths

- [x] 5.1 Make `editor/EntityPlacer` preview and stamps (`_place_entity_on_cell`, `_place_tree_on_cell`) spawn detached. Verify: a test stamps a building into the editor and asserts no occupancy cells are registered.
- [x] 5.2 Make `editor/ResourcePainter._paint_resource_cell` spawn detached. Verify: a test asserts the painted node is present in `editor._painted_entities[key]["node"]` and no occupancy is registered.
- [x] 5.3 Add a detached branch to `MapLoader.load_map_into` keyed on the map editor parent (its `_painted_entities` content store), so editor loads spawn detached while gameplay loads register. Verify: an editor load round-trip test asserts zero registered building cells, and a gameplay load test still registers.

## 6. Integration verification

- [x] 6.1 Add an integration test proving runtime-placed, map-loaded, and deployed buildings register identically: present in `_buildings` exactly once, counted for their own owner's prerequisites, occupancy registered exactly once, sellable by their owner, and not notifying `building_placed` unless runtime-placed. Verify: the test passes.
- [x] 6.2 Rewrite `test/unit/test_entity_death.gd` to drive death cleanup through the registered path (including a null `StatsComponent` case) instead of hand-appending to `_buildings`. Verify: the rewritten test passes.
- [x] 6.3 Run `redot --headless -s test/run_tests.gd` and confirm the full suite is green.
- [x] 6.4 Run `gdlint scripts/**/*.gd test/**/*.gd` and `gdformat --check scripts/**/*.gd test/**/*.gd`; confirm clean.
- [x] 6.5 Update `GLOSSARY.md`: add an "insertion seam" / `EntityFactory.spawn` term and disambiguate it from the existing match-root "spawn seam" (`World.spawn_container`); define the "detached" marker and the `spawned` event. Verify: `serena memories check` or a manual read confirms the new terms are present and unambiguous.
