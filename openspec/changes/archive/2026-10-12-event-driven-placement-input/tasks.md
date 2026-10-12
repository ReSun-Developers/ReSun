# Tasks

## 1. Pin existing behavior and prove the runtime premise

- [x] 1.1 Strengthened `test/integration/test_input_pipeline.gd` to mount the HUD shape (a
      `CanvasLayer` with partial-rect `STOP` Controls) and assert a pushed open-world click still
      reaches a session-shaped `Node._unhandled_input`. File documents that headless `push_input`
      cannot model GUI consumption, so ownership is asserted via the explicit minimap gate + live
      check, not here.
- [x] 1.2 Pinned right-click-in-build-mode at the dispatch level: `test_building_manager_input.gd`
      asserts a `deselect_entity` event exits build mode. No cancel latch is added (MouseHandler's
      deselect is unchanged; D2).
- [x] 1.3 Pinned the headless arming invariant: `test_enter_arms_places_nothing_and_clears_latch`
      asserts entering build mode places nothing by itself. The GUI consumption of the triggering
      cameo click is a runtime behaviour the harness cannot model → covered by the live-match check
      (5.7).

## 2. BuildingManager — event-driven input

- [x] 2.1 Added `_unhandled_input` to `scripts/buildings/BuildingManager.gd`: `select_entity` →
      `UIUtil.is_mouse_over_minimap()` gate → `_try_place_building()`; `deselect_entity`/`ui_cancel`
      → `exit_build_mode()`; `set_input_as_handled()` on each handled branch.
- [x] 2.2 Deleted `_skip_input_frames` (declaration, arm in `enter_build_mode`, drain branch) and the
      input branch of `_process`; `_process` keeps only `_update_preview_position()`.
- [x] 2.3 `enter_build_mode()` clears a stale `exiting_build_mode` latch at session start (not in
      `exit_build_mode()`, which the commit handshake calls after setting it).
- [x] 2.4 `exiting_build_mode` is still set before exit on a successful place (unchanged), so
      `MouseHandler` cannot re-handle the commit click as a unit order.

## 3. EntityPlacer — event-driven input

- [x] 3.1 Deleted `_skip_input_frames` from `scripts/entities/EntityPlacer.gd` (declaration,
      `exit_placing_mode` reset, `start_placing` arm) and the input-poll branch of `_process`; kept
      `_process` repositioning.
- [x] 3.2 Added the `UIUtil.is_mouse_over_minimap()` gate to `_unhandled_input`'s `select_entity`
      branch (the deleted poll branch held the only copy).
- [x] 3.3 `did_consume_click_this_frame()` still covers the commit click; cancel has no latch (D2).

## 4. MouseHandler guards (verify only)

- [x] 4.1 Verified `scripts/hud/MouseHandler.gd` guards (`is_build_mode`/`exiting_build_mode`,
      `EntityPlacer.is_placing()`/`did_consume_click_this_frame()`) still consume the commit click;
      the full suite (incl. `test_placing_session`, `test_cameo_click_policy`) stayed green. No change
      made.

## 5. Specs and verification

- [x] 5.1 Spec deltas applied (`building-manager`, `debug-menu`);
      `openspec validate event-driven-placement-input --strict` passes.
- [x] 5.2 Added `test/unit/test_building_manager_input.gd` driving `_unhandled_input(InputEventAction)`:
      enter arms/places nothing/clears latch, deselect exits, ESC exits, select attempts placement
      without cancelling, input ignored outside build mode.
- [x] 5.3 Added EntityPlacer assertions to `test/unit/test_placing_session.gd`:
      `test_minimap_click_does_not_commit` (explicit gate) and
      `test_select_armed_without_preview_does_nothing`.
- [x] 5.4 Added `test/unit/test_building_manager_input.gd` ESC case at the dispatch level; the
      cross-handler ordering (BuildingManager vs PauseMenu) remains covered by the live check because
      headless `push_input` does not run the real input phase ordering.
- [x] 5.5 Double-fire latch: EntityPlacer's `did_consume_click_this_frame()` is asserted by the
      existing `test_placing_session` commit tests. BuildingManager's `exiting_build_mode` latch is set
      in `_try_place_building` (unchanged) and confirmed live (5.7); preview tracking stays in
      `_process` and is covered by EntityPlacer's `test_reposition_tracks_terrain`.
- [x] 5.6 Full suite green (`11817 passed, 0 failed`); `gdlint` + `gdformat --check` clean; no tabs.
- [x] 5.7 Live-match check (manual) caught the failure: with `_unhandled_input` as the only path,
      mouse placement/cancel did nothing while ESC worked. Root cause: the full-rect FpsCounter
      `Control` was eating pointer input. Fixed in section 6; re-run the live check after that fix.

## 6. FpsCounter pointer pass-through (live-check root cause)

- [x] 6.1 Set the `FpsCounter` root `Control` (full-rect) and its label to `mouse_filter = IGNORE` in
      `scenes/ui/FPSCounter01.tscn`, so the HUD readout no longer swallows world pointer events.
- [x] 6.2 Added `test_fps_counter_does_not_consume_pointer` to `test/integration/test_input_pipeline.gd`
      as a regression guard (a full-rect STOP HUD control silently reintroduces the bug).
- [x] 6.3 Live-match check re-run after the FpsCounter fix: place, right-click cancel, ESC cancel, no
      double-place. Confirmed working.

## 7. Review follow-ups

- [x] 7.1 Threaded `screen_pos` into `BuildingManager._try_place_building(screen_pos)` and added
      `test_select_places_building_and_sets_latch`, so the place + `exiting_build_mode` latch path
      fails on reversion (the headless cursor cannot be moved, so the full `_unhandled_input` →
      placement wiring is still covered by the live check).
- [x] 7.2 Set `CreditsLabel` (`scenes/ui/CreditsLabel.tscn`) to `mouse_filter = IGNORE` — same
      full/large-rect HUD-control class as the FpsCounter bug.
- [x] 7.3 Tightened the FpsCounter guard to `== IGNORE` (not merely `!= STOP`) and removed a vacuous
      assertion in `test_input_building_*`; reworded the HUD-shape pipeline test as a positive-path
      check (headless cannot model consumption).
- [x] 7.4 Reconciled proposal/design prose with what shipped (scene changes listed; no undelivered
      test claims; D3 ordering caveat; minimap "except" scoped to commit).
