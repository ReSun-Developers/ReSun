# Tasks

## 1. Regression test

- [x] 1.1 Add `test/integration/test_marquee_release.gd`. Mount a `SceneTree.current_scene` with a `Sidebar`-named Control covering the pointer, reset `UIUtil._cached_sidebar`, assert the overlay is detected, set a past-threshold drag, release `select_entity`, and tick `_process(0.0)`. Assert the drag clears, the box hides, `active_rect` empties, and the box branch ran with the drawn rectangle. Run on base and capture the failure.
- [x] 1.2 Add the same case for a `Minimap`-named overlay (separate detection branch).
- [x] 1.3 Add the sub-threshold over-UI case: assert neither the click nor the box branch runs, then prove non-vacuity by running the same state with `over_ui = false` and asserting one click.
- [x] 1.4 Add the press-over-UI case (no drag starts, no box shows) and the no-press release case (no click, no box).
- [x] 1.5 Add the same-frame press+release case (still resolves one click) and the degenerate zero-area marquee case (no click, no selection).
- [x] 1.6 Add the over-world positive control: a past-threshold release still box-selects and clears the drag.

## 2. Fix

- [x] 2.1 Extract `_end_select_drag(over_ui, shift_pressed)` in `scripts/hud/MouseHandler.gd`: gate on `mouse_dragging`, use the `active_rect` x-or-y threshold, resolve the box on release over UI, suppress single-click over UI, treat a zero-area threshold rect as a no-op, and clear `mouse_dragging`, the box, and `active_rect`.
- [x] 2.2 Call it on `select_entity` release outside the UI-hover guard, after the press branch; keep press, right-click, drag updates, and hover preview gated. Reset `active_rect` on press and hide the box when the drag shrinks below the threshold. Verify the new tests and `test_pause_menu` pass.
- [x] 2.3 Run gdlint, gdformat --check, the tab grep, and the full headless suite; all clean.
