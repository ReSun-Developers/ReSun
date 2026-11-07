# Tasks

## 1. Regression tests first

- [x] 1.1 Add `test/integration/test_trigger_bookkeeping.gd` with the tests from design.md, each arming `TriggerEngine`, asserting the pre-removal counts are 1 before asserting they drop, and restoring the player credits, `ScenarioState`, and building registry it touched; verify `gdlint test/integration/test_trigger_bookkeeping.gd` reports no errors
- [x] 1.2 Run the new suite on the unmodified production code and capture the expected failures: the credits-at-arm, exact-balance, shared-house, arm-clean, sold, undeployed, double-removal, and building-exists tests fail; the above-starting pair, the destroyed pair, the uncounted-sibling guard, and the sale-silent test pass
- [x] 1.3 Record the base-run output in the change report so the failing-before-fix evidence is explicit

## 2. Credits read the starting balance (#524)

- [x] 2.1 Add `_seed_credits()` to `TriggerEngine.arm()` that stores `EconomyManager.get_balance(player_id)` per `PlayerData.faction_id`, and verify `_credits[house]` equals the starting balance immediately after arm
- [x] 2.2 Add `_mark_credits_dirty()` to `arm()` so live triggers with event 12 are evaluated on the first tick, and verify the credits-at-arm tests pass while temporal-only and cell-scope triggers stay clean
- [x] 2.3 Confirm `reset()` still clears `_credits` and `_dirty`, and verify `test_arm_and_reset`, `test_new_match_clears_previous`, `test_credits_standing_event`, and `test_standing_persistent_fires_once_per_hold` pass

## 3. Structure removals update counts (#525)

- [x] 3.1 Add `COUNTED_META` and set it in `notify_built` for a valid node, and verify the existing build/destroy offer tests still pass
- [x] 3.2 Add `TriggerEngine.notify_removed(owner, entity_id, node)` that guards `!_armed`, no-ops unless the node carries the counted marker as `true`, decrements (clamped at zero), marks the owner dirty without offering events, and flips the marker to `false`; refactor `notify_destroyed` to return for an already-removed node and otherwise call `notify_removed` before offering 7 / 48, and verify the destroyed pair still passes
- [x] 3.3 Call `notify_removed` from `BuildingManager.sell_building` with the owner's house, entity id, and building node, and verify the sold-structure test passes
- [x] 3.4 Call `notify_removed` from `BuildingManager.unregister_building_entity`, and verify the undeployed-structure test passes
- [x] 3.5 Verify the uncounted-sibling guard passes (an uncounted removal leaves a counted structure's counts at 1) and the sale-silent test passes with its death positive control

## 4. Integration gates

- [x] 4.1 Run `gdlint scripts/**/*.gd test/**/*.gd` and `gdformat --check scripts/**/*.gd test/**/*.gd` and verify both exit clean
- [x] 4.2 Run `grep -P '\t' scripts/**/*.gd test/**/*.gd` and verify no tabs were introduced
- [x] 4.3 Run `flock /tmp/opencode/redot.lock redot --headless -s test/run_tests.gd` and verify the full suite passes with the new tests included
- [x] 4.4 Run `openspec validate fix-trigger-bookkeeping --strict` and verify the change is apply-ready
