# Proposal

## Why

`BuildingManager.sell_building()` hardcodes the refund as `cost * 0.5` (`scripts/buildings/BuildingManager.gd:525`) while `GlobalRules.refund_percent` (`scripts/data/GlobalRules.gd:32`) exists as a data knob with zero readers — and the `building-manager` spec separately pins sell at "50%", contradicting the `global-rules` spec which lists `refund_percent=0.5` as an active rules value. The hardcoded value happens to match the default, hiding the bug until a game author tunes the rules.

## What Changes

- `sell_building()` reads `refund_percent` from the active `GlobalRules` instead of a literal `0.5`
- The `building-manager` spec's sell requirement changes from a fixed "50%" to the rules-driven value
- The existing sell test (`test/unit/test_feature_flags.gd:154`) is parameterized to set a non-default `refund_percent` and assert the non-default result, so the wiring is actually verified (the current test passes either way)
- Production-cancel refunds in `ProductionManager` are explicitly **out of scope** — they refund the actual deducted amount by design, which stays

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `building-manager`: The "Building sell" requirement's refund amount becomes `refund_percent` from the active `GlobalRules` (default 0.5) instead of a hardcoded 50%; scenario updated to prove a non-default rules value changes the payout.

## Impact

- **Code**: `scripts/buildings/BuildingManager.gd` (`sell_building`, ~line 525) — one expression; reads active rules via the same rules-access pattern used elsewhere in the function's neighborhood
- **Tests**: `test/unit/test_feature_flags.gd` — `test_sell_refund_uses_active_category` gains a non-default `refund_percent` assertion (or a sibling test); `TestHelper`/`GlobalRules` snapshot-restore pattern already in use there
- **Specs**: `openspec/specs/building-manager/spec.md` (via delta), no change to `global-rules` spec
- **Data/compat**: no `.tscn` or `.tres` schema changes; default `0.5` means existing games behave identically — non-breaking
