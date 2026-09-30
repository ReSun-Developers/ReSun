# Tasks

## 1. Wire refund_percent into sell_building

- [x] 1.0 Fix `openspec/specs/building-manager/spec.md` line 1: `## ADDED Requirements` → `## Requirements` (leftover delta header from a past archive makes the spec structurally invalid; `openspec validate fix-sell-refund-percent --strict` reports "Archive would refuse this delta") and verify re-running that validate command no longer reports the structural error

- [x] 1.1 In `scripts/buildings/BuildingManager.gd` `sell_building()` (line ~525), replace `entity_data.cost * 0.5` with `entity_data.cost * rules.refund_percent` using the active `GlobalRules` (fall back to `0.5` when rules are absent, mirroring the `rules.repair_step if rules else 8` pattern) and verify with `gdlint scripts/buildings/BuildingManager.gd` (no errors)

## 2. Test the wiring

- [x] 2.1 In `test/unit/test_feature_flags.gd`, set `refund_percent = 0.25` on the test's `GlobalRules` in `test_sell_refund_uses_active_category` (or add a sibling test), assert balance increases by 25 for a cost-100 building, and verify the test fails when production code is temporarily reverted to `0.5`
- [x] 2.2 Run `redot --headless -s test/run_tests.gd` and verify the full suite passes (test count unchanged or grown; no failures)

## 3. Integration checks

- [x] 3.1 Run `gdlint scripts/**/*.gd test/**/*.gd` and `gdformat --check scripts/**/*.gd test/**/*.gd` and verify both exit clean
- [x] 3.2 Confirm `openspec validate --change fix-sell-refund-percent --strict` passes and the archived behavior matches the spec delta (default rules still pay 50, tuned rules pay the tuned amount)
