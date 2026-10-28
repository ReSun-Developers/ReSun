# Proposal

## Why

`EntityData.LOCOMOTOR_ZONES` is the last locomotor-id-keyed map in `EntityData`. Locomotor already owns movement behavior (terrain speeds, slope factors, behavior flags), so zone compatibility belongs on the resource it describes. Keeping it on `EntityData` means movement data is split across two resources and every new locomotor edits a core data class.

## What Changes

- Add `zones: PackedStringArray` to `Locomotor`, listing the movement zones that locomotor accepts.
- Populate `zones` on the nine `games/ts/locomotors/*.tres` resources from today's `LOCOMOTOR_ZONES` table.
- `EntityData.validate()` resolves the unit's Locomotor from `GlobalRules` and checks `movement_zone` membership in `Locomotor.zones`; remove the static dictionary and static compatibility helper.
- Validation still skips zone compatibility when `GlobalRules` is unavailable, preserving today's behavior for editor/test contexts where no registry exists.
- Update the entity-data and locomotor specs and the glossary entry that names `LOCOMOTOR_ZONES`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `locomotor`: Locomotor gains `zones` and owns movement-zone compatibility; TS resources carry the zone lists.
- `entity-data`: zone validation resolves the locomotor resource instead of reading a static `EntityData` dictionary.

## Impact

- `scripts/data/Locomotor.gd` — new `zones` property.
- `scripts/data/EntityData.gd` — remove `LOCOMOTOR_ZONES` and `is_movement_zone_compatible`; validation reads the resolved Locomotor.
- `games/ts/locomotors/*.tres` — nine resources gain `zones`.
- `test/unit/test_locomotor_registry.gd` — replace static-helper assertions with resource-data assertions; add pre-GlobalRules and per-locomotor coverage.
- `GLOSSARY.md`, `openspec/specs/entity-data/spec.md`, `openspec/specs/locomotor/spec.md` — terminology and requirement updates.
- No scene changes; the new `Locomotor` property defaults to empty, so existing resources stay loadable.
