# Tasks

## 1. Typed value and gate API

- [x] 1.1 Add a nested `class BuildDecision extends RefCounted` (`enabled: bool`, `reason: BuildReason`,
      `cost: int`, `owned_factory: bool`) to `scripts/production/PrerequisiteSystem.gd`; retype
      `evaluate_build` to return it and make `can_build` `return evaluate_build(...).enabled`.
      Verify the script parses (no type error on the nested class / enum field) and
      `test/integration/test_build_gate_shared.gd` still passes.
- [x] 1.2 Add a field-value test in `test/unit/test_prerequisite_system.gd` that calls
      `evaluate_build` for a known input and asserts the reported `enabled`, `reason`, `cost`,
      and `owned_factory` via property access (values derived from the fixture, not the query).
      Verify the new test passes.
- [x] 1.3 Record `BuildDecision` in `GLOSSARY.md` under the `build gate` entry and fix that
      entry's stale spec link (`openspec/changes/add-build-gate-query/...` → the canonical
      `openspec/specs/build-gate/spec.md` path). Verify `rg BuildDecision GLOSSARY.md` finds it.

## 2. Production consumers

- [x] 2.1 Switch `scripts/ui/CreditCounter.gd:108` and `scripts/ui/Sidebar.gd:251` from
      `["enabled"]` to `.enabled` (leave `ProductionManager.gd:665`'s `.owned_factory` as is).
      Verify `test/unit/test_credit_counter.gd` and the sidebar build-order suite pass.
- [x] 2.2 Add a `# ponytail:` comment at `CreditCounter._update_credits_color` recording that the
      gate + balance + `no_cost` join stays inline until a second affordability consumer exists.
      Verify the comment is present and `test_credit_counter` remains green.

## 3. Test migration

- [x] 3.1 Retype the `_reason` / `_assert_rejected` helper parameters and the `var result: Dictionary`
      annotations in `test/unit/test_prerequisite_system.gd` to `BuildDecision`, switching
      `result["x"]` reads to property access. Verify the suite passes.
- [x] 3.2 Retype `test/unit/test_credit_counter.gd:199` and the inline `evaluate_build(...)["enabled"]`
      reads in `test/integration/test_build_gate_shared.gd:70,74`. Verify both suites pass.

## 4. Integration verification

- [x] 4.1 Run `redot --headless -s test/run_tests.gd` and verify the full suite is green (anchor:
      `test_build_gate_shared`, `test_credit_counter.test_unaffordable_type_is_still_enabled`).
- [x] 4.2 Run `gdlint scripts/**/*.gd test/**/*.gd` and `gdformat --check scripts/**/*.gd test/**/*.gd`,
      then `grep -P '\t' scripts/**/*.gd` to confirm no tabs were introduced; verify all clean.
