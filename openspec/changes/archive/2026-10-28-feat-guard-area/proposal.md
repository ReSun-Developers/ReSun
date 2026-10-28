# Proposal

## Why

Tiberian Sun's Ctrl+Alt+Click issues Guard Area: the selection moves to the clicked
spot and then guards that area, re-engaging anything that comes into range. ReSun has
no Guard Area. Because Alt also means force-move, Ctrl+Alt currently resolves to a
plain move, so a documented original command is silently missing.

## What Changes

- Add a guard-area order: Ctrl+Alt+Click moves the selection to the target position
  and then guards the clicked area, re-engaging hostiles in weapon range.
- Add `OrderResult.MOD_GUARD_AREA`, set when both Ctrl and Alt are held; the unit
  generator resolves it ahead of the force-move short-circuit.
- Reuse `GuardComponent` for the guard stance and acquisition. Guard Area stores the
  clicked anchor, keeps the existing stand-and-shoot acquisition, and walks a
  displaced unit back to the anchor.
- Return `CursorState.Type.GUARD` (the existing shield cursor) over a valid
  guard-area target.
- Stop command clears an active guard area alongside the existing stop behaviour.
- Force fire (Ctrl), force move (Alt), and rally points (Alt on a factory) are
  unchanged.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `order-system`: add the guard-area modifier, its resolution ahead of force-move,
  and the GUARD cursor.
- `guard-auto-engage`: add the guard-area stance (anchor, leash back, clear on player
  move/stop) on top of the existing stand-and-shoot acquisition.

## Impact

- `scripts/orders/OrderResult.gd`, `scripts/orders/UnitOrderGenerator.gd`,
  `scripts/core/OrderSystem.gd`, `scripts/core/SelectionManager.gd`
- `scripts/components/GuardComponent.gd`
- `scripts/hud/MouseHandler.gd` (stop hotkey clears guard area)
- `scripts/hud/CursorState.gd` (GUARD cursor priority)
- Tests: `test/unit/test_unit_order_generator.gd`, `test/unit/test_guard_component.gd`
- No scene or data changes; existing packed scenes keep working.
