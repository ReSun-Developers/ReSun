# Proposal

## Why

Releasing the left mouse button over the sidebar, minimap, or debug menu while a marquee selection box is in progress leaves the drag latched: the selection box stays visible and the handler keeps treating the mouse as dragging until another press/release cycle. The drag-end branch is nested inside the "cursor is not over UI" guard, so the release never reaches it.

## What Changes

- End the marquee drag on left-button release no matter where the cursor is, including over the sidebar, minimap, or debug menu.
- Keep world click resolution (single-click select/order) suppressed while the cursor is over UI so the release cannot click through the sidebar or minimap.
- A marquee that exceeded the drag threshold still resolves its box selection from the rectangle formed in the gameplay view when released over UI.
- Clear the drag rectangle state on every drag end, matching the pause reset.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `selection-manager`: add a marquee drag lifecycle requirement — the drag ends on release regardless of UI hover, and a release over UI never resolves as a world click.

## Impact

- `scripts/hud/MouseHandler.gd` — drag release handling moves out of the UI-hover guard; drag end extracted into a small helper for testability.
- `test/integration/` — new regression test driving `_process` with the cursor over a sidebar-like UI overlay.
- No scene or data changes; no input-map changes.
- Out of scope: the centralized UI input gating work (#391).
