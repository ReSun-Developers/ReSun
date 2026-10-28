# Tasks

## 1. Tests first (must fail on base)

- [x] 1.1 Add a guard-capable fixture and the Ctrl+Alt guard-area test to `test/unit/test_unit_order_generator.gd`; verify it fails on base (`flock /tmp/opencode/redot.lock redot --headless -s test/run_tests.gd`)
- [x] 1.2 Keep the existing Ctrl+Alt force-move fallback test and add enemy-selection rejection, Ctrl force-fire, Alt force-move, rally-point regression and mixed-selection stance tests; verify the new expectations fail on base
- [x] 1.3 Add guard-area stance tests to `test/unit/test_guard_component.gd` (guards after arrival, leashes to anchor, no leash while moving, player move clears, stop clears, unreachable anchor clears) and verify they fail on base

## 2. Order intake

- [x] 2.1 Add `OrderResult.MOD_GUARD_AREA` and set it in `OrderSystem.build_modifiers` for Ctrl+Alt, suppressed when `SelectionManager.has_rally_receiver()`; verify the guard-area generator tests pass (`build_modifiers` reads `Input`, so headless tests drive explicit modifier dicts)
- [x] 2.2 Add the guard-area branch and `_synthesized_guard_area` ahead of the force-move short-circuit in `UnitOrderGenerator`, carrying `target_level` at `GUARD_AREA_PRIORITY`, and update the stale Ctrl+Alt comment; verify the generator tests pass
- [x] 2.3 Add the `SelectionManager.request_guard_area` batch flag and the `_execute_move` stance wiring; verify the mixed-selection test gives the guard unit a stance and leaves the unarmed unit without one

## 3. Guard-area stance

- [x] 3.1 Add anchor, leash and clear-on-move/failure behavior to `GuardComponent` and verify the stance tests pass
- [x] 3.2 Clear the stance from the Stop hotkey in `MouseHandler.apply_selection_hotkey` and verify the stop test passes

## 4. Integration

- [x] 4.1 Run `gdlint scripts/**/*.gd test/**/*.gd`, `gdformat --check scripts/**/*.gd test/**/*.gd`, and `grep -P '\t' scripts/**/*.gd test/**/*.gd`; fix all findings
- [x] 4.2 Run `flock /tmp/opencode/redot.lock redot --headless -s test/run_tests.gd` and confirm zero failures
- [x] 4.3 Update `GLOSSARY.md` with the guard-area term and verify the entry anchors to the order-system spec
