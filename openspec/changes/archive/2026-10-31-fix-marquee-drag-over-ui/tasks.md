# Tasks

## 1. Regression tests

- [x] 1.1 `test_drag_over_ui_keeps_updating_rect`: mount a `Sidebar` overlay covering the pointer, set `mouse_dragging` with `drag_start_position` offset from the viewport mouse position, tick `_process(0.0)`, and assert `active_rect` matches the rectangle derived from the mouse position and the box is visible. Confirm it fails on the current code.
- [x] 1.2 `test_release_over_sidebar_uses_rect_extended_over_ui`: same setup, then release; assert the recorded box equals the rectangle extended over the UI, not the pre-UI rectangle. Confirm it fails on the current code.
- [x] 1.3 `test_drag_uses_default_cursor`: seed `_current_cursor = SELECT`, drag past the threshold over the world, tick `_process(0.0)`, and assert `_current_cursor == DEFAULT`. Confirm it fails on the current code.
- [x] 1.4 Keep the existing marquee-release cases green.

## 2. Fix

- [x] 2.1 Move the drag-rectangle update out of the `if not over_ui:` guard in `scripts/hud/MouseHandler.gd` so it runs whenever `mouse_dragging`; leave press, right-click/ESC, and hover preview gated.
- [x] 2.2 In `_update_cursor`, return `CursorState.Type.DEFAULT` from the dragging branch instead of `SELECT`.

## 3. Verification

- [x] 3.1 Run the marquee tests and the full headless suite.
- [x] 3.2 Run gdlint, gdformat --check, and the tab grep.
- [x] 3.3 Sync the delta into `openspec/specs/selection-manager/spec.md` and archive the change.
