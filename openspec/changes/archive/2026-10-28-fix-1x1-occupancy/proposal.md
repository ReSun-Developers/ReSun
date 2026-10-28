# Proposal

## Why

Structures with a 1×1 foundation are invisible to the cell-occupancy system. `EntityFactory` attaches `FoundationComponent` only when `data.foundation != Vector2i(1, 1)`, and that component is the only writer of `SpatialHash._building_cells`. A 1×1 silo, wall, or turret therefore reports `building == false`, can be built over, can be pathed through, can be exited onto, and is missed by the sell/repair cursor gate. The issue names 22 gdi/nod/neutral structures; the worktree has 65 1×1 `BUILDING` entities in total, most of them civilian decorations that should also block.

## What Changes

- Attach `FoundationComponent` to every solid `EntityData.EntityType.BUILDING` regardless of footprint size, preserving the existing attach rule for non-building entities whose footprint is larger than 1×1 (smudges use it for footprint geometry).
- Add an `EntityData.blocks_cells` flag (default `true`) so non-solid buildings keep their current walkable behaviour. `GDI_PAVEMENT` and the six invisible light emitters set it to `false`; every other building keeps blocking.
- A 1×1 building now registers its single foundation cell through the existing `FoundationComponent._ready` path, so `get_cell_occupancy().building`, `is_cell_free_for_build`, `get_blocked_cells`/pathfinding, `is_cell_free_for_unit_exit`, and the `FoundationComponent`-based sell/repair gate all see it.
- Resolve the `GDI_WALL`/`NOD_WALL` duplicate id: the structure (`entity_type = BUILDING`) and the map overlay (`entity_type = OVERLAY`) share an id, and the overlay currently wins the factory cache, so the issue's wall case is unreachable. Rename the overlay ids to `GDI_WALL_OVERLAY`/`NOD_WALL_OVERLAY`; no shipped map references either.
- Add regression coverage that spawns real 1×1 structures through `EntityFactory.spawn` and asserts each consequence; migrate `test_order_system_modes._make_building` to a factory-built 1×1 structure.
- Record the invariants in the `entity-factory`, `foundation-component`, and `combat-firing` specs.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `entity-factory`: the `FoundationComponent` attach rule changes from "footprint larger than 1×1" to "solid BUILDING (plus the existing non-building footprint case)".
- `foundation-component`: states the invariant that every solid BUILDING carries the component, so occupancy registration is independent of footprint size; non-solid buildings register nothing.
- `combat-firing`: a 1×1 building now has a footprint, so range is measured to its nearest footprint point instead of its `global_position`.

## Impact

- `scripts/entities/EntityFactory.gd` (`_add_foundation_component`).
- `scripts/data/EntityData.gd` (new `blocks_cells` flag), `scripts/components/FoundationComponent.gd` (configure + skip registration).
- Data: `gdi_pavement.tres` and six `civ_invisible_*_light*.tres` set `blocks_cells = false`; `overlay/gdi_wall.tres` and `overlay/nod_wall.tres` ids renamed.
- No change to `SpatialHash` registration, query, or pathfinding code.
- Behavioural side effects, all intended: 1×1 buildings become sellable/repairable (#519 cursor gate), report a nearest-footprint impact point, and gain the existing half-diagonal projectile range allowance.
- Tests: new `test/integration/test_one_by_one_structure_occupancy.gd`, `test/unit/test_order_system_modes.gd` fixture migration, comment updates in `test/unit/test_combat_component.gd`.
- Out of scope: #519 cursor-side changes and #528 (`EntityData`-assembled fixtures); they share the root cause but are tracked separately. Also out of scope: the overlay wall (`GAWALL`) never blocking — separate overlay-occupancy bug.

## Notes on the ground-shot consequence

The issue lists "ground shot on the cell misses the structure". `SpatialHash.rebuild` already indexes every `"entities"`-group member in `_grid` (including buildings), and `resolve_cell_victim` checks `_grid` before the footprint fallback, so a 1×1 structure at the cell centre already resolves on base. The regression suite still asserts victim resolution as a consumer check, but that assertion passes on base; it is not the failing driver.
