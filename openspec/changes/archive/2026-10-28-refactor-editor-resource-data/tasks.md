# Tasks

## 1. Regression tests (written first, must fail on base)

- [x] 1.1 Add `test/unit/test_editor_resource_data.gd` with a minimal editor stub and injected synthetic `EntityData`; assert `ResourcePainter._paint_resource_cell` stores the injected crystal id (not `TIBERIUM_RIPARIUS`), health scales from its `strength`, and the spawned `ResourceComponent.resource_type_id` is the injected type; verify the test fails on base with `flock /tmp/opencode/redot.lock redot --headless -s test/run_tests.gd`, and commit the generated `.uid`
- [x] 1.2 Add tests that changing the primary tree's spawned crystal changes the id painted on the next cell, and that `EntityPlacer._place_tree_on_cell` stores the injected spawner id (not `TIBERIUM_TREE`); verify each fails on base for the intended reason
- [x] 1.3 Add a `has_method`-guarded resolver-null test: with no matching registered entity, both queries return null and the tools leave `_painted_entities` unchanged (no entry added, existing tree entry preserved); verify it fails on base (missing method) and passes after implementation

## 2. Catalog queries

- [x] 2.1 Add `get_primary_resource_tree_entity()` (first id-ordered spawner whose `spawned_entity_id` is a typed non-spawner in `primary_resource_category`) and `get_primary_resource_entity()` (that spawner's spawned entity, else first id-ordered typed non-spawner in the category) to `scripts/entities/EntityFactory.gd`; verify the new unit tests for both queries pass
- [x] 2.2 Assert the real TS catalog resolves `TIBERIUM_TREE` / `TIBERIUM_RIPARIUS` and ignores `TIBERIUM_BLUE_01`; verify the assertion passes

## 3. Editor tools

- [x] 3.1 Rewire `ResourcePainter._paint_resource_cell` to spawn `EntityFactory.get_primary_resource_entity().id`, derive the health default from its `strength`, drop the `resource_type_id` override, warn and no-op when null, and rename `tib`/`TIB_DEFAULT_STRENGTH` to neutral `res_comp` names; verify the paint tests pass
- [x] 3.2 Rewire `EntityPlacer._place_tree_on_cell` to resolve `EntityFactory.get_primary_resource_tree_entity()` before touching `_painted_entities`, spawn its id, and warn/no-op when null so an existing entity is preserved; verify the tree tests pass
- [x] 3.3 Rename the remaining `tib` locals in `scripts/editor/MapEditor.gd` to `res_comp`; verify `grep -rniE '\btib\b|TIB_[A-Z]|tiberium' scripts/editor/` shows no id/identifier literals left
- [x] 3.4 Add the `primary resource entity` row to `GLOSSARY.md` under Resources & Economy and verify it renders in the table

## 4. Integration

- [x] 4.1 Run `gdlint scripts/**/*.gd test/**/*.gd`, `gdformat --check scripts/**/*.gd test/**/*.gd`, and `grep -P '\t' scripts/**/*.gd test/**/*.gd`; verify all clean
- [x] 4.2 Run `flock /tmp/opencode/redot.lock redot --headless -s test/run_tests.gd`; verify the full suite passes, including `test/integration/test_map_editor_e2e.gd` unchanged
