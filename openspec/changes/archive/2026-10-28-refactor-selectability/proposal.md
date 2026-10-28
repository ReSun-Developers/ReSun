# Proposal

## Why

`SelectComponent.is_selectable` and `is_drag_selectable` read as data-driven selectability knobs but neither is honored: `is_selectable` is never assigned or read, `EntityData` has no matching field, and selection-group membership ignores `is_drag_selectable`. A `.tres` with `is_drag_selectable = false` is still box-selected. The API lies about being configurable.

## What Changes

- Add `EntityData.is_selectable: bool = true` next to the existing `is_drag_selectable`.
- Assign both flags from data in `EntityFactory._add_select_component`.
- Make selection-group membership honor the flags in `EntityFactory.create_entity`, `EntityPlacer` preview restoration, and `SelectComponent._ready`.
- Honor `is_selectable` in `SelectionManager`'s selectability gate (`_is_entity_selectable`) for click and box select, and in `set_hover_preview` for hover.
- Keep programmatic `add_entity` ungated, mirroring the existing visible-bounds rule, and connect its selection-state signal so programmatically added entities stay reconciled.
- Update `select-component`, `selection-manager`, `entity-data`, and `entity-factory` specs.

Explicitly out of scope: #166 enemy-selection/command-blocking rules; changing any `.tres` content to actually set the flags false; a UI badge for unselectable entities; per-player selectability.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `entity-data`: add the `is_selectable` data field alongside `is_drag_selectable`.
- `entity-factory`: selection group membership derives from the data flags.
- `select-component`: component-entry group registration honors the flags.
- `selection-manager`: click, hover, and box select honor `is_selectable`.

## Impact

- **Scripts:** `scripts/data/EntityData.gd`, `scripts/entities/EntityFactory.gd`, `scripts/entities/EntityPlacer.gd`, `scripts/components/SelectComponent.gd`, `scripts/core/SelectionManager.gd`
- **Cursor affordance:** `scripts/orders/UnitOrderGenerator.gd` reads the `selectable` group, so a non-selectable entity no longer shows the SELECT cursor. Over a non-selectable unit the cursor falls back to the ground probe (MOVE when the selection can move, otherwise DEFAULT). This is the intended consequence of honoring the flag, not a separate change.
- **Tests:** new cases in `test_entity_data.gd`, `test_entity_factory_spawn.gd`, `test_select_component.gd`, `test_selection_manager.gd`
- **Resources:** `EntityData` gains one exported field; existing `.tres` files keep the default `true`
- **Scenes:** no scene edits; standalone structure scenes (e.g. `GDIConyard01.tscn`) now join `selectable`/`entities` at `SelectComponent._ready`, matching factory-built buildings
- **Backward compatibility:** factory-built entities keep today's behavior because both flags default to `true`; standalone structure scenes gain the selection groups they already had when factory-built. `civ_guardtower.tres` already opts out of drag select and is a building, so it is unaffected.
