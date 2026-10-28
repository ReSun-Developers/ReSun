# Design

## Context

See proposal.md for motivation. Current shape of `scripts/hud/MouseHandler.gd` `_process()`:

```
over_ui = sidebar | debug | build | minimap
if not over_ui:
    press  -> mouse_dragging = true
    release-> resolve box/click, mouse_dragging = false, rect.hide()
    right  -> deselect/cancel
    drag   -> update active_rect + rect
    hover  -> raycast preview
_update_cursor()
```

Both drag start and drag end live inside the `not over_ui` guard. The guard exists so UI clicks never fall through to the world (selection or orders). A drag that starts in the world but ends over UI never reaches the release branch.

Other drag-state owners already reset it: `_notification(NOTIFICATION_PAUSED)` clears `mouse_dragging`, hides the rect, clears `active_rect`; build-mode exit sets `_skip_release`. There is no reset on entering UI, and none is needed once release handling is unconditional.

## Goals / Non-Goals

**Goals:**
- One release path for every drag, regardless of cursor position at release.
- Keep UI hover blocking world clicks (no click-through).
- A regression test that fails on the base implementation.

**Non-Goals:**
- Centralized UI input gating (#391) — not implemented here.
- Changing when a drag may *start* (still world-only).
- Changing box-selection rules (ownership, bounds, shroud, voice).

## Decisions

**D1 — Move release handling out of the UI guard; keep everything else inside.**
Only the release branch is position-independent: the button release is the terminal event of a drag. Press, right-click, drag-rect updates, and hover preview remain world-only. Alternative: reset drag state when the cursor enters UI — rejected, because it would end a legitimate marquee the moment the cursor clips the sidebar and would also hide the box while the button is still held.

**D2 — Resolve box selection on release over UI; suppress single-click.**
The marquee rectangle is built in gameplay-view coordinates and already reflects the last in-world cursor position. Resolving it on release preserves the player's action instead of silently discarding the drag. A sub-threshold release over UI is treated as a cancelled click: `_handle_single_click` would otherwise select a unit behind the sidebar or issue a move order through it.
Alternative: cancel the box selection too — rejected as surprising and it would make a drag over the sidebar behave differently from a drag released at the same rectangle inside the view.

**D2b — Use one threshold predicate (x or y) for display and release.**
The drag display shows the box when either axis passes `MOUSE_DRAG_THRESHOLD`, but the old release check looked only at `size.x`, so a vertical marquee was displayed and then treated as a click. Release now checks `active_rect` on either axis, matching what the player sees, and the press branch resets `active_rect` so a same-frame click cannot reuse a stale rectangle. A threshold-crossing rectangle with zero area on the other axis is a no-op (not a click and not a selection), so the player never gets a move order from a degenerate marquee.

**D3 — Gate release handling on `mouse_dragging`.**
A release only resolves a click when this handler saw the matching press. This closes the pre-existing "press on sidebar, release over map" click-through and removes the release's dependency on `mouse_dragging` being false. `_skip_release` and the unpause debounce still run earlier in `_process`; both paths already clear the drag (build-mode exit and `NOTIFICATION_PAUSED`).

**D4 — Extract `_end_select_drag(over_ui, shift_pressed)` and clear `active_rect`.**
Small seam for the regression test; mirrors the pause reset. `active_rect` is otherwise stale after a release. No new class, signal, or config.

**D5 — Test through `_process`, not just the helper.**
The regression is a routing bug (release skipped by the guard). The test installs a UI overlay as `SceneTree.current_scene`, resets `UIUtil` caches, covers the mouse position, asserts the overlay is detected, sets the drag state, releases `select_entity`, and ticks `_process(0.0)`. On base the release is skipped and `mouse_dragging` stays true. A helper-only test would keep passing if the guard came back. A test-local `MouseHandler` subclass records whether the click or box branch ran, so the assertion is not vacuous without pulling in the bounds/shroud fixture; the selection algorithm itself stays covered by `test_selection_manager`. Extra cases lock the press-over-UI guard, the no-press gate, same-frame press+release, and the degenerate zero-area marquee.


## Risks / Trade-offs

- [Box select fires on release over UI] → It uses the rectangle drawn in the world, matching a release at the same rectangle inside the view. Documented in the spec; can be revisited if playtesting disagrees.
- [Headless fixture is not detected, making the test vacuous] → The test sets `SceneTree.current_scene`, resets `UIUtil._cached_sidebar`/`_cached_minimap`, covers the pointer, and asserts the overlay is detected before ticking; teardown restores `current_scene` and the caches.
- [`active_rect` clearing could affect cursor resolution] → `_update_cursor` only reads it while `mouse_dragging` is true, which is cleared in the same step.

## Migration Plan

None — runtime behavior only. Rollback is reverting the commit.

## Open Questions

None.
