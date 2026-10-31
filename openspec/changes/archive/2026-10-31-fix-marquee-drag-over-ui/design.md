# Design

## Context

See proposal.md. Current shape of `MouseHandler._process()` after #514:

```
over_ui = sidebar | debug | build | minimap
if not over_ui:
    press   -> mouse_dragging = true
if released:
    _end_select_drag(over_ui, shift)      # position-independent
if not over_ui:
    right   -> deselect/cancel
    drag    -> update active_rect + box   # <- freezes when over UI
    hover   -> raycast preview
_update_cursor()                          # UI -> DEFAULT, dragging -> SELECT
```

The release path is already position-independent; the rectangle it resolves is not.

## Goals / Non-Goals

**Goals:**
- The box follows the cursor for as long as the button is held, including over UI.
- A release over UI resolves the rectangle as drawn, selecting entities behind the UI.
- One cursor for the drag: the default pointer.

**Non-Goals:**
- Starting a drag over UI (a UI press is a UI click).
- Changing box-selection rules (ownership, bounds, shroud, voice).
- Changing the hover `SELECT` cursor outside a drag.

## Decisions

**D1 — Move only the drag update out of the UI guard.**
The update writes `active_rect` from the viewport mouse position, which is valid over UI. Press, right-click/ESC, and hover preview stay world-gated: those would act on UI clicks or raycast through the sidebar. Alternative: end the drag when the cursor enters UI — rejected, it would discard a legitimate marquee mid-gesture.

**D2 — Keep release-over-UI resolution, now with a current rectangle.**
`_end_select_drag` already resolves the box when the threshold was crossed and suppresses single-click/orders over UI. No change needed there; the rectangle is simply no longer stale.

**D3 — Drag cursor is `CursorState.Type.DEFAULT`.**
`_apply_cursor(DEFAULT)` clears the custom cursor, restoring the OS pointer. The drag branch already precedes the order-cursor fallback, so the pointer holds for the whole drag. The UI branches above it also yield `DEFAULT`, so the cursor no longer flips when crossing the sidebar. The `SELECT` cursor remains for hover affordance from `UnitOrderGenerator`.

**D4 — Test through `_process`, deriving expected values from the viewport mouse position.**
The tests read `get_viewport().get_mouse_position()` and set `drag_start_position` relative to it, so the expected rectangle is computed from the input rather than copied from the implementation. The cursor test seeds `_current_cursor = SELECT` first so a no-op `_update_cursor` cannot pass vacuously.

## Risks / Trade-offs

- [Box selects units visually hidden behind the sidebar] → Intended: the rectangle spans where the player dragged, matching C&C behavior. Documented in the spec.
- [Headless viewport mouse position is unexpected] → Expected values are derived from the same viewport call the implementation uses; a zero position still yields a past-threshold rectangle.

## Migration Plan

None — runtime behavior only. Rollback is reverting the commit.

## Open Questions

None.
