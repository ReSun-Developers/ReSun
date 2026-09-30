# Design

## Context

`sell_building()` in `scripts/buildings/BuildingManager.gd` computes the refund with a literal `0.5`. `GlobalRules.refund_percent` exists, defaults to `0.5`, and is never read anywhere in `scripts/`. Because the literal matches the default, all current games behave correctly and no test fails. `BuildingManager` already has access to the active rules elsewhere (repair reads `rules.repair_step` at line 591), so no new plumbing is needed. See proposal.md for motivation; specs/building-manager/spec.md for the requirement.

## Goals / Non-Goals

**Goals:**
- Sell refund amount comes from one data knob (`refund_percent`) so per-game tuning works
- A test that fails if the wiring is removed (the current test passes with either the literal or the knob)

**Non-Goals:**
- Production-cancel refunds in `ProductionManager` — those refund the actual deducted amount by design (spec: production-manager "Cancel production with refund")
- Auditing or wiring other orphaned `GlobalRules` fields (`repair_percent`, `reload_rate`, …) — tracked by #187/#185/#397
- Evacuation-of-infantries-on-sell or other sell-behavior expansion

## Decisions

- **Read `refund_percent` from the same active-rules accessor the repair path already uses**, rather than threading rules through `SellOrderGenerator` → `sell_building()`. The generator already hands a node to `BuildingManager`; changing the signature would touch an order-system contract for one float.
  - Alternative considered: pass `refund_percent` as a parameter to `sell_building()` — rejected; pushes a rules read into every caller and the spec phrases the refund as rules-driven behavior of the sell operation itself.
- **Guard against missing rules**: fall back to `0.5` (the field default) when no active rules exist, mirroring the `rules.repair_step if rules else 8` pattern at line 591, so tests that construct `BuildingManager` without a full game context don't crash.
- **Parameterize the existing test** (`test_sell_refund_uses_active_category`) by setting `refund_percent = 0.25` on its `GlobalRules` and asserting `+25`, keeping the category assertion. This reuses the snapshot/restore harness already in that test instead of adding a near-duplicate.

## Risks / Trade-offs

- [Test could regress to asserting the default] → the new assertion uses a non-default value (0.25), so reverting production code to `0.5` makes the test fail — the vacuous-pass problem in the current suite.
- [Any game `.tres` that later authors a non-default `refund_percent` changes balance] → intended; default stays 0.5 so today's games are byte-identical in behavior.
- [Rules read at sell time means a mid-game rules swap changes subsequent refunds] → acceptable; rules are loaded once per game via GameContext today.

## Migration Plan

None — default value preserves current behavior; single-session change, rollback is reverting one expression plus the test edit.

## Open Questions

None.
