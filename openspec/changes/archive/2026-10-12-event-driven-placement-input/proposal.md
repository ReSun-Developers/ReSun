# Proposal

## Why

Placement sessions (build mode, free placement) drive commit and cancel by polling raw
`Input.is_action_just_pressed` inside `_process`, guarded by a one-frame `_skip_input_frames`
counter. The spec justifies the poll by claiming "mouse events do not reach `_unhandled_input` at
runtime in this codebase" (`openspec/specs/debug-menu/spec.md`). That observation was real, but its
cause was a bug: the always-mounted FPS counter is a full-rect `Control` left at the default
`mouse_filter = STOP`, so it swallowed every pointer event over the world (keyboard events are not
GUI-consumed, which is why ESC worked but mouse clicks did not). Once the FPS counter stops
consuming, `_unhandled_input` receives mouse input (proven by `test/integration/test_input_pipeline.gd`),
so the raw poll is no longer needed — and it is what makes the placement path untestable
(`test_input_seam_probe.gd`: `just_pressed` cannot be cleared without a real frame advance).

## What Changes

- **BuildingManager**: commit (select) and cancel (deselect/ESC) move to `_unhandled_input`, mirroring
  `EntityPlacer`. `_skip_input_frames` and the `_process` input branch are deleted; `_process` keeps
  only preview repositioning (mouse motion does not fire during camera pans).
- **EntityPlacer**: delete `_skip_input_frames` and the `_process` input-poll branch. `_unhandled_input`
  (already present as the keyboard/test fallback) becomes the sole commit/cancel path and gains the
  minimap gate the poll branch held; `_process` keeps only preview repositioning.
- **MouseHandler** keeps polling raw `Input` (out of scope) and is verify-only: its existing guards
  (`exiting_build_mode`, `EntityPlacer.did_consume_click_this_frame()`) already cover the commit
  click, and right-click in build mode already deselects today (the mode-exit and the deselect both
  occur), so no cancel latch is added — behavior is preserved.
- **FpsCounter**: its full-rect root `Control` switches from the default `mouse_filter = STOP` to
  `IGNORE` (label too), so it no longer consumes pointer input intended for the world. This is the
  root cause of the "mouse placement does nothing" symptom the event-driven change exposed.
- Remove the now-obsolete "mouse events do not reach `_unhandled_input`" rationale from specs.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `building-manager`: build-mode commit/cancel behavior is restated without the `_skip_input_frames`
  detail, and a new requirement ("Build mode input handling") captures the commit/cancel/minimap/
  no-double-fire/preview-tracking contract.
- `debug-menu`: the EntityPlacer placement requirement drops the poll-based mandate and the
  `_skip_input_frames` clause; the "Commit/Cancel is poll-driven" scenarios become event-driven.

## Impact

- **Scripts**: `scripts/buildings/BuildingManager.gd`, `scripts/entities/EntityPlacer.gd`.
  `scripts/hud/MouseHandler.gd` is verified only (no change expected).
- **Scenes**: `scenes/ui/FPSCounter01.tscn` and `scenes/ui/CreditsLabel.tscn` (non-interactive HUD
  readouts set to `mouse_filter = IGNORE`). Additive; no node/property removals, so existing packed
  scenes keep loading.
- **Specs**: `openspec/specs/building-manager/spec.md`, `openspec/specs/debug-menu/spec.md`.
- **Tests**: `test/integration/test_input_pipeline.gd` (Phase 0 probe + FpsCounter regression guard);
  new `test/unit/test_building_manager_input.gd` (dispatch + a real placement asserting the latch);
  `test/unit/test_placing_session.gd` additions (minimap gate, armed-without-preview). Cross-handler
  ordering (BuildingManager vs PauseMenu) is verified by the live check, not a headless test.
- **No new autoloads.** Runtime behavior is intended to be unchanged apart from the FpsCounter fix;
  the difference is *which* input phase consumes the event.
