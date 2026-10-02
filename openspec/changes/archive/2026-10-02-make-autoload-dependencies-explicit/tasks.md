# Tasks

## 1. Regression guard

- [x] 1.1 Add `test/unit/test_autoload_access.gd` that parses autoload names from `project.godot`, walks `scripts/`, and asserts no `get_node("/root/<Autoload>")` / `get_node_or_null("/root/<Autoload>")` lookup remains; verify it fails on the current tree for at least one file and that the failure names the offending file/line
- [x] 1.2 Exclude non-autoload `/root` targets from the scan (notably `/root/MainScene/Gameplay/Camera/Camera3D` in `scripts/core/EntityMaskManager.gd:64`), and verify the test passes once only that lookup remains

## 2. Runtime-path conversions (non-`@tool` scripts)

- [x] 2.1 Convert `scripts/ui/Sidebar.gd` (11 sites) to registered-identifier access; verify the scan test no longer reports it and the sidebar suite (`test/unit/test_sidebar_*.gd`) stays green
- [x] 2.2 Convert `scripts/production/ProductionManager.gd` (9) and `scripts/buildings/BuildingManager.gd` (6); verify `test/unit/test_production_manager.gd`, `test/unit/test_building_manager.gd` stay green
- [x] 2.3 Convert `scripts/components/DeployComponent.gd` (5), `scripts/ui/CreditCounter.gd` (3), `scripts/ui/SelectionOverlay.gd` (2), and `scripts/components/DockUnloadComponent.gd` (2); verify `test/unit/test_deploy_component.gd`, `test/unit/test_credit_counter.gd`, `test/unit/test_selection_overlay.gd`, `test/unit/test_dock_client_component.gd` stay green
- [x] 2.4 Convert the remaining runtime-path files: `Minimap.gd`, `DebugMenu.gd`, `MouseHandler.gd`, `AssetBrowserController.gd`, `ShroudSystem.gd`, `ResourceGrowthSystem.gd`, `PlayerManager.gd`, `PowerBar.gd`, `PauseMenu.gd`, `MainMenu01.gd`, `HoverTooltip.gd`, `MissionMap.gd`, `MapLoader.gd`, `EntityPlacer.gd`, `EntityFactory.gd`, `TerrainSystem.gd`, `GameContext.gd`, `AudioManager.gd`, `MovementController.gd`, `HarvestComponent.gd`; verify `test/unit/` and `test/integration/` suites stay green

## 3. Editor-context conversion

- [x] 3.1 Convert `scripts/core/BoundsSystem.gd` (3 sites) using the D2 editor-guard rule: keep the `Engine.is_editor_hint()` guard for editor-reachable reads of non-`@tool` autoloads, use the identifier outside it, and do not log an error for expected editor absence; verify the scan test passes and the map editor opens without errors

## 4. Ordering annotations and docs

- [x] 4.1 Update `project.godot` `[autoload]` annotations: delete the unsupported InputSettings (`:25`) and CampaignCatalog (`:22`) comments, correct the PowerGrid note so it names its real `_ready` consumer (ProductionManager) and drop the PrerequisiteSystem reference, and delete the purpose-only VeterancySystem comment; verify each remaining annotation names a read that occurs in `_ready`/`_enter_tree`
- [x] 4.2 Update the autoload bullet in `AGENTS.md` to state the access rule (registered identifier, no `/root/<Name>` string lookups) and the annotation convention; verify the documented rule matches the regression test's assertion

## 5. Integration verification

- [x] 5.1 Run `gdlint scripts/**/*.gd test/**/*.gd` and `gdformat --check scripts/**/*.gd test/**/*.gd`; verify both are clean, then `grep -P '\t' scripts/**/*.gd` returns nothing
- [x] 5.2 Run `redot --headless -s test/run_tests.gd`; verify the full suite is green, including `test/unit/test_autoload_access.gd`
- [x] 5.3 Manual smoke: boot the game, open the map editor, and run a map load; verify no "non-existent autoload" or null-dependency errors and that existing behavior is unchanged (headless boot + `test_map_editor_e2e` / `test_mission_boot` cover this automatically; an interactive editor pass remains for a human)
