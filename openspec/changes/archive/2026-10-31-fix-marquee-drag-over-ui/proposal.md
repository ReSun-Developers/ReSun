# Proposal

## Why

A marquee drag that passes over the sidebar, minimap, or debug menu freezes: the drag-rectangle update in `MouseHandler._process()` is nested inside the "cursor is not over UI" guard, so `active_rect` and the visible box stop tracking the cursor while it is over UI. Releasing over UI (already handled since #514) then resolves that stale, undersized rectangle, so units whose screen projection lies under the UI are never selected.

Separately, the drag forces the custom `SELECT` cursor, which is inconsistent with the UI regions it now spans and with the default pointer the player expects while holding a selection box.

## What Changes

- Keep the marquee rectangle tracking the cursor while the button is held, including while the cursor is over the sidebar, minimap, or debug menu.
- Allow the rectangle to cover UI; a release over UI resolves box selection over the full rectangle, so entities projected behind the UI are selected.
- Show the default pointer cursor for the duration of the drag (over the world and over UI), instead of the `SELECT` cursor.
- Drag start remains world-only: a press over UI never begins a marquee.
- World click resolution stays suppressed while the cursor is over UI.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `selection-manager`: the marquee requirement now covers tracking over UI, box resolution over the UI-covered rectangle, and the default pointer cursor during the drag.

## Impact

- `scripts/hud/MouseHandler.gd` — drag-rect update moves out of the UI-hover guard; the drag cursor branch returns `DEFAULT`.
- `test/integration/test_marquee_release.gd` — regression tests for tracking over UI, release over UI using the extended rectangle, and the drag cursor.
- No scene, data, or input-map changes.
