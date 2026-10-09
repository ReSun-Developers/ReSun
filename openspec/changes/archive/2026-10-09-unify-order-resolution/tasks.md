# Tasks

## 1. OrderResolution type

- [x] 1.1 Create `scripts/orders/OrderResolution.gd` — `class_name OrderResolution`, fields `cursor: CursorState.Type`, `orders: Array[OrderResult]`, with a constructor
- [x] 1.2 Add `OrderResolution` to `GLOSSARY.md` under Orders & Selection

## 2. Generator unification

- [x] 2.1 Add virtual `resolve(...) -> OrderResolution` to `OrderGenerator.gd`
- [x] 2.2 Collapse `UnitOrderGenerator.get_cursor` + `get_orders` into `resolve()` as the single merged decision tree
- [x] 2.3 Reimplement `UnitOrderGenerator.get_cursor` / `get_orders` as projections of `resolve()`
- [x] 2.4 Merge `SellOrderGenerator.get_cursor` / `get_orders` into `resolve()`
- [x] 2.5 Merge `RepairOrderGenerator.get_cursor` / `get_orders` into `resolve()`

## 3. OrderSystem

- [x] 3.1 Add `resolve()` = bounds/fog/shroud gates + `active_generator.resolve()`
- [x] 3.2 Rewrite `get_cursor` / `get_orders` as projections of `resolve()`
- [x] 3.3 Add `issue(orders) -> bool` (voice + execute + acknowledge), moved from MouseHandler
- [x] 3.4 Move `build_modifiers()` and the voice helpers (`play_order_voices`, `play_ack_voice`, `acknowledge_target_lines`) onto `OrderSystem`

## 4. Component cleanup

- [x] 4.1 Delete `get_cursor_for_target` from `CombatComponent.gd:287`
- [x] 4.2 Delete `get_cursor_for_target` from `MovementController.gd:1763`
- [x] 4.3 Delete `get_cursor_for_target` from `PassengerComponent.gd:26`
- [x] 4.4 Delete `get_cursor_for_target` from `TransportComponent.gd:315`

## 5. Force-move

- [x] 5.1 `CombatComponent.get_order_for_target` returns null when `MOD_FORCE_MOVE` is held
- [x] 5.2 `MovementController.get_order_for_target` returns a MOVE order for entity targets under `MOD_FORCE_MOVE` (and keeps ground behavior)
- [x] 5.3 Remove the now-dead `UnitOrderGenerator._is_enemy` if unused

## 6. Callers

- [x] 6.1 `MouseHandler`: route world click, ground path, and `_try_execute_orders` through `OrderSystem.issue()`
- [x] 6.2 `MouseHandler._update_cursor`: drop the re-decided SELECT; use `OrderSystem.resolve().cursor`
- [x] 6.3 `Minimap._handle_click`: use `OrderSystem.resolve()` + `OrderSystem.issue()`
- [x] 6.4 Remove the cross-file MouseHandler static imports from Minimap now that the funnel owns them

## 7. Tests

- [x] 7.1 Update `test_unit_order_generator.gd` — assert via `resolve()` and projection equivalence
- [x] 7.2 Add characterization tests for each merged branch (force-fire ground, undeploy/move/select fallbacks, empty selection)
- [x] 7.3 Update `test_combat_component.gd`, `test_transport_cargo.gd`, `test_transport_passengers.gd`, `test_movement_controller_infantry.gd` — replace `get_cursor_for_target` with `get_order_for_target(...).cursor`
- [x] 7.4 Add force-move tests (ALT+click entity -> MOVE; ALT+click ground -> MOVE)
- [x] 7.5 Add `OrderSystem.issue()` tests (one voice, executes all, empty no-op)
- [x] 7.6 Confirm `test_order_bounds.gd`, `test_force_fire_ground.gd`, `test_order_system_modes.gd` pass unchanged through the `get_cursor`/`get_orders` projections (no edits needed)

## 8. Verification

- [x] 8.1 `redot --headless -s test/run_tests.gd` — full suite green
- [x] 8.2 `gdlint scripts/**/*.gd test/**/*.gd` and `gdformat --check scripts/**/*.gd test/**/*.gd`; then `grep -P '\t' scripts/**/*.gd`
- [ ] 8.3 Manual: cursor matches issued order across unit x target matrix; minimap orders play one voice; ALT force-move works
