# Tasks

## 1. World root

- [x] 1.1 Create the `World` root scene and script (per-match container) and verify it instantiates as a single node under `MainScene/Gameplay`
- [x] 1.2 Change `MissionBoot` to host `MissionMap` inside a newly created World root and release the previous World root; verify a started mission's map entities are descendants of that World root
- [x] 1.3 Add tests that start two matches and assert exactly one World root remains and the previous match's map nodes are gone: a unit test on the swap seam (`test/unit/test_world_root.gd`) and a real-tree test through `GameContext.start_mission` (`test/integration/test_match_swap.gd`); verify they pass
- [x] 1.4 Add the `match root` term to `GLOSSARY.md` and verify its anchor resolves to the new `match-root` spec

## 2. UI session shell

- [x] 2.1 Add the `SessionShell` node with a `SessionMode` (`Menu`, `Match`) and verify the shell starts in `Menu` mode
- [x] 2.2 Move `BootScreen`, `MainMenu01`, and `LoadingScreen` under a `MenuSurface` owned by the shell and verify the menu shows in `Menu` mode with no World root present
- [x] 2.3 Build the `HudSurface` scene from the map's current HUD children and remove the `HUD` CanvasLayer from `MapBase01.tscn`; verify no HUD nodes remain in the map scene
- [x] 2.4 Mount/unmount surfaces on mode switch so exactly one top-level surface exists; add a test asserting `Menu` → `Match` clears the menu surface and mounts the HUD, and verify it passes
- [x] 2.5 Update every `.tscn` and script that referenced the map's HUD children, and verify those scenes load with no missing-node errors
- [x] 2.6 Add `session mode` and `UI session shell` to `GLOSSARY.md` and verify their anchors resolve to the new `ui-session-shell` spec

## 3. Mission boot integration

- [x] 3.1 Replace `MissionBoot._hide_menu_overlays()` with setting session mode `Match`; verify the boot seam requests match mode (`test/integration/test_mission_boot.gd`) and that a real two-match boot leaves the match HUD mounted (`test/integration/test_match_swap.gd`). The campaign dialog and `--mission` share this boot seam.
- [x] 3.2 Verify `MissionMap` map loading and the `MapConfig` lookup still resolve when the map is hosted under the World root (update the lookup path if needed)
- [x] 3.3 Update the `mission boot` glossary entry and `mission-boot` spec text from `MainScene/Gameplay` to the World root, and verify the wording matches the delta

## 4. Integration checks

- [x] 4.1 Run `redot --headless -s test/run_tests.gd` and verify the full suite passes
- [x] 4.2 Run `gdlint scripts/**/*.gd test/**/*.gd` and `gdformat --check scripts/**/*.gd test/**/*.gd`; verify clean
- [x] 4.3 Run `openspec validate add-world-root-and-ui-shell --strict` and verify it passes

## 5. Review follow-ups

- [x] 5.1 Fix stale camera pivot on match replacement: `BoundsSystem` re-resolves a pivot that is no longer in the tree and guards the centering helpers; verify `test/integration/test_match_swap.gd` asserts the pivot belongs to the active World root
- [x] 5.2 Fix a detached `BriefingDialog` reacting to `mission_started` after its HUD surface is released: disconnect the global signal in `_exit_tree` and guard `show_for_mission`; verify a two-match run logs no `show_for_mission` error
- [x] 5.3 Make `test_lighting_controls` cleanup free the HUD/map immediately (no leaked `DebugMenu` `node_added` connection or root-viewport camera) and guard its node lookups against null
- [x] 5.4 Correct the proposal, design, specs, and task wording to match the implementation (swap detaches then frees at frame end; the HUD is not given a World reference; there is no match-end path; runtime-spawn routing is deferred) and re-run `openspec validate --strict`
- [x] 5.5 Remove the hardcoded `/root/MainScene/...` camera path in `EntityMaskManager` and use the viewport camera only
- [x] 5.6 Discover the cloud-shadow overlay by group (`cloud_shadow_overlay`) instead of `current_scene` in `BoundsSystem`, and register the group on `CloudShadowPlane.tscn`; assert it in `test_match_swap.gd`
- [x] 5.7 Resolve `SelectionOverlay` by its autoload identifier in `DebugMenu` (delete the dead recursive finder) and make the `BuildingManager`/`EntityPlacer` camera fallbacks search the active scene recursively
- [x] 5.8 Renumber the scene `index=` overrides shifted by the HUD removal (`MissionMap`, `TestMap01`, `TestMap02`) and disambiguate the `World` node name against **World frame** in the glossary
