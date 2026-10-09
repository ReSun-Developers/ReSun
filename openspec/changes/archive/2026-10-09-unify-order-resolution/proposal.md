# Proposal

## Why

Player order intake has two decision trees that must agree but can diverge.
`UnitOrderGenerator.get_cursor()` (`scripts/orders/UnitOrderGenerator.gd:17`) and `get_orders()` (`:73`)
independently re-derive the same branches (force-fire priority gate, undeploy/move/select fallbacks).
`openspec/specs/order-system/spec.md` already requires the cursor to mirror the emitted order (`:412`) and
`get_cursor()` to delegate to the resolver (`:114`), so the split is spec-violating drift, not preference.
The change that unified this at the component level (`2026-07-25-unified-order-system`) explicitly left
"remove old methods" as a final cleanup task that never ran, leaving `get_cursor_for_target()` dead on four
components. Separately, `MOD_FORCE_MOVE` is written by `MouseHandler` and read by nothing, so ALT force-move
is inert; and the order-dispatch tail (voice + execute + acknowledge) is duplicated in `MouseHandler` and
`Minimap`.

## What Changes

- **New `OrderResolution` value** carrying `cursor` and `orders`, produced by one decision.
- **`OrderSystem.resolve()`** becomes the single decision (bounds/fog/shroud gates + active generator);
  `get_cursor()` and `get_orders()` become thin projections of it and are retained for callers/tests.
- **Collapse `UnitOrderGenerator`'s two trees** into one; the cursor-only affordances (`SELECT`,
  `GENERIC_BLOCKED`, `MOVE` fallbacks, and the empty-selection `SELECT` currently re-decided in
  `MouseHandler._update_cursor:634`) move into the resolution.
- **Delete `get_cursor_for_target()`** from Combat, Movement, Passenger and Transport components
  (finishing the 2026-07-25 cleanup; the cursor already lives on `OrderResult`).
- **Move order dispatch into `OrderSystem.issue()`** — one confirmation voice, execute each order,
  acknowledge target lines — consumed by the world-click, ground, and minimap paths.
- **Implement `MOD_FORCE_MOVE`** — ALT+click yields a MOVE order even over an entity target.
- **BREAKING (internal):** `UnitOrderGenerator.get_cursor()`'s independent branch tree is removed; its
  behavior is preserved through `resolve()`.

## Capabilities

### New Capabilities

<!-- none -->

### Modified Capabilities

- `order-system`: adds `OrderResolution` + unified `resolve()`, adds `OrderSystem.issue()` dispatch,
  changes `UnitOrderGenerator` from two independent trees to one decision.
- `entity-components`: the order-targeter contract states cursor is carried on the returned `OrderResult`,
  and components expose no separate `get_cursor_for_target()`.

## Impact

- **New file**: `scripts/orders/OrderResolution.gd`
- **Modified**: `scripts/core/OrderSystem.gd`, `scripts/orders/OrderGenerator.gd`,
  `scripts/orders/UnitOrderGenerator.gd`, `scripts/orders/SellOrderGenerator.gd`,
  `scripts/orders/RepairOrderGenerator.gd`, `scripts/hud/MouseHandler.gd`, `scripts/ui/Minimap.gd`,
  `scripts/components/CombatComponent.gd`, `scripts/components/MovementController.gd`,
  `scripts/components/PassengerComponent.gd`, `scripts/components/TransportComponent.gd`
- **Tests**: `test/unit/test_unit_order_generator.gd`, `test_combat_component.gd`,
  `test_transport_cargo.gd`, `test_transport_passengers.gd`,
  `test_movement_controller_infantry.gd`, `test/test_helper.gd`,
  `test/integration/test_audio_voice_routing.gd` (relocated voice helpers + `issue()` coverage)
- **Docs**: `GLOSSARY.md` (new term `OrderResolution`)
- **No scene changes** — script-level only
