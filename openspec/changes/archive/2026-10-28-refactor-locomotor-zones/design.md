# Design

## Context

See `proposal.md` - Why. Today `EntityData.LOCOMOTOR_ZONES` (`scripts/data/EntityData.gd:350-383`) is a static id-keyed dictionary, `is_movement_zone_compatible()` (`:387-391`) reads it, and `validate()` (`:427-440`) is the only caller. `Locomotor` (`scripts/data/Locomotor.gd`) already owns terrain speeds, slope factors, and behavior flags. `GlobalRules.get_locomotor(id)` resolves the registry, and `GlobalRules.get_current()` returns null outside the running game (editor, and tests that explicitly clear the registry). `validate()` runs from `EntityFactory.create_entity()` and directly in unit tests.

The nine TS locomotor resources live at `games/ts/locomotors/*.tres` and are registered through the active game's `global_rules.tres`.

## Goals / Non-Goals

**Goals:**
- One source of truth for zone compatibility: the resolved `Locomotor` resource.
- Preserve every existing validation outcome for registered locomotor ids when `GlobalRules` is available.
- Preserve the current skip when `GlobalRules` is unavailable.
- Keep resource files backward compatible: a missing `zones` key loads as an empty array.

**Non-Goals:**
- Making `movement_zone` gate pathfinding or passability.
- Adding a built-in fallback zone table for pre-registry validation.
- Changing the zone vocabulary or entity `.tres` data.
- Reworking `GlobalRules` registry loading.

## Decisions

### D1. `zones: PackedStringArray` on `Locomotor`

Add `@export var zones: PackedStringArray = []` beside `crushes`. A `PackedStringArray` matches the existing crush-list style and serializes cleanly in `.tres`. Empty means "accepts no non-empty zone"; the empty zone is handled by the caller, matching today's `is_movement_zone_compatible()` early return.

*Alternative:* keep a dictionary on `GlobalRules`. Rejected: it moves the map without attaching it to the resource that owns movement, so the split persists.

### D2. Populate the nine TS resources from the current table

Each `.tres` gains a `zones = PackedStringArray(...)` line with the exact list from `LOCOMOTOR_ZONES`. No entity data changes: every current entity with a non-empty zone already passes its locomotor's list.

### D3. Validation resolves the locomotor and checks membership

`EntityData.validate()` replaces the static call with:

```gdscript
var rules := GlobalRules.get_current()
if rules:
    var lm := rules.get_locomotor(locomotor)
    if not locomotor.is_empty() and lm == null:
        errors.append("%s: unknown locomotor %s" % [id, locomotor])
    if not movement_zone.is_empty():
        if locomotor.is_empty() or (lm != null and not lm.zones.has(movement_zone)):
            errors.append("%s: movement_zone %s contradicts locomotor %s" % [id, movement_zone, locomotor])
```

When the id resolves, this preserves the current accept/reject outcome, including empty-zone acceptance. A non-empty zone with no locomotor id remains a contradiction, as on base. When the id does not resolve, the zone check is skipped: an unknown non-empty id already reports `unknown locomotor`, and an empty registry (no locomotor data available) cannot judge compatibility. A custom locomotor that declares no zones rejects every non-empty zone, which is the correct data contract.

*Alternative:* a `Locomotor.accepts_zone()` helper. Rejected: one caller, and the empty-zone rule already lives at the call site.

### D4. Pre-GlobalRules path: skip, do not relocate

`validate()` already guards the registry checks with `if rules:`, and for a non-empty locomotor id the zone check requires a resolved Locomotor (`lm != null`). When rules or the unit's locomotor resource are unavailable, zone compatibility is skipped. A fallback table would reintroduce the misplaced data this change removes and could disagree with a game's own resources. The skip is documented in the spec and covered by a test.

### D5. Remove the static API

Delete `LOCOMOTOR_ZONES` and `is_movement_zone_compatible()`. Update `test_locomotor_registry.gd` to assert against `rules.get_locomotor(id).zones`. This forces any future consumer onto the resource and prevents drift.

### D6. Regression tests that fail on base

- `test_ts_locomotor_zones` asserts `Locomotor.zones` on all nine TS resources. Base has no property, so it fails.
- `test_entity_zone_checked_against_resolved_locomotor` injects a custom `Foot` locomotor whose zones contain only `Fly` and validates an EntityData with `locomotor = "Foot"`, `movement_zone = "Fly"`. The test sets `zones` via `lm.set("zones", ...)` so it still loads and runs on base; base's static table rejects Foot+Fly, so the assertion fails for the intended reason, and the resource-driven check accepts it after the change.
- `test_entity_zone_not_borrowed_from_other_locomotor` registers a second locomotor that accepts `Subterannean` and validates an EntityData whose own locomotor does not; the contradiction is still reported.
- `test_entity_contradictory_zone_validation` uses real TS rules with Track + Subterannean, asserts the Track zone list is non-empty, and expects the contradiction error.
- `test_entity_valid_zone_validation` uses real TS rules with Track + Normal and expects no contradiction.
- `test_entity_zone_without_locomotor` validates an EntityData with an empty `locomotor` and a non-empty zone and expects the contradiction error, preserving base behavior.
- `test_entity_unknown_locomotor_zone_not_checked` injects a non-null rules object with an empty locomotor registry, uses a non-empty zone, and expects the unknown-locomotor error but no contradiction.
- `test_entity_zone_validation_without_rules` explicitly injects a null `GlobalRules` (the runner boots autoloads, so rules otherwise exist) with a non-empty zone and expects no contradiction, proving the documented skip.

### D7. Spec and glossary impact

Archive syncs one MODIFIED and one ADDED locomotor requirement plus one MODIFIED entity-data requirement. `GLOSSARY.md` line 208 changes `LOCOMOTOR_ZONES` to `Locomotor.zones`.

## Risks / Trade-offs

- A custom locomotor that forgets `zones` now rejects every non-empty zone → Mitigation: the error names the entity and zone, and the data lives next to the locomotor definition where the author is already editing.
- Tests that inject ad-hoc locomotors need a `zones` list when testing non-empty zones → Mitigation: update the existing contradiction test and assert its list is populated; unrelated tests use empty zones and are unaffected.
- `PackedStringArray` cannot express "accept all" other than listing every zone → Accepted: the zone vocabulary is small and the empty-zone case already covers units with no domain class.

## Migration Plan

1. Add `zones` to `Locomotor.gd`.
2. Populate the nine `games/ts/locomotors/*.tres`.
3. Replace the validation branch in `EntityData.gd`; delete the static map and helper.
4. Update and extend `test/unit/test_locomotor_registry.gd`.
5. Update `GLOSSARY.md`, then archive the change to sync specs.

Rollback: restore the static dictionary/helper and drop `zones` from the resources; validation behavior is otherwise unchanged.

## Open Questions

None.
