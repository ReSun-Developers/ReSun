# Proposal

## Why

The build-gate query is the one per-player decision the sidebar, production, and
HUD all read, but its result is an untyped `Dictionary` accessed by string key at
22 call sites (4 production + 18 test reads). The archived `add-build-gate-query`
design (D1) chose a `Dictionary` over a typed object *"to avoid a one-use class"*
and named the revisit trigger explicitly: *"revisit only if key access becomes
error-prone."* With 22 call sites that trigger is now met — a typo in `"enabled"`
or a renamed key fails at runtime, not at parse time, and the result's four-field
shape is asserted nowhere.

## What Changes

- `PrerequisiteSystem.evaluate_build` returns a typed `BuildDecision` value
  (nested `RefCounted`: `enabled: bool`, `reason: BuildReason`, `cost: int`,
  `owned_factory: bool`) instead of a `Dictionary`.
- `can_build` becomes a projection: `return evaluate_build(...).enabled`.
- Production consumers switch from string-key reads to property access —
  `CreditCounter` and `Sidebar` `["enabled"]` → `.enabled`; `ProductionManager`'s
  existing `.owned_factory` is unchanged.
- **BREAKING (internal):** `evaluate_build`'s return type changes. Any caller or
  test that typed the result as `Dictionary` is retyped to `BuildDecision`.
  Behaviour is identical; no public signature other than the return type changes.
- Add one field-value test in `test/unit/test_prerequisite_system.gd` asserting
  `evaluate_build` reports the expected enabled/reason/cost/owned_factory values
  for a known input via property access.
- Affordability feedback (the gate + balance + `no_cost` join) is deliberately
  **not** touched here — it has a single consumer and already lives in one place.

## Capabilities

### New Capabilities

None. This is a pure representation refactor — the build-gate query reports the
same fields for the same inputs; only their in-memory container changes.

### Modified Capabilities

None. The `build-gate` spec constrains *what* the query reports (enabled, reason,
cost, a raw `owned_factory` fact) and never its return type, so no requirement
text changes. The change opts out of specs via `skip_specs: true`.

## Impact

- `scripts/production/PrerequisiteSystem.gd` — new `BuildDecision`; retyped
  `evaluate_build`; `can_build` projection.
- `scripts/ui/CreditCounter.gd`, `scripts/ui/Sidebar.gd` — property access.
- `scripts/production/ProductionManager.gd` — unchanged (already property access).
- `test/unit/test_prerequisite_system.gd`, `test/unit/test_credit_counter.gd`,
  `test/integration/test_build_gate_shared.gd` — retype result annotations and
  access; `test/unit/test_tech_level_gate.gd` unaffected (uses `can_build`).
- No `.tscn`, data, or dependency changes.
