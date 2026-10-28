# Proposal

## Why

`MovementController` is 1819 lines with a de facto interface made of private members: 19
private-member accesses in 7 files (15 statements) plus 16 production calls to the
9-positional-argument `set_target_position`. Three arrival tails duplicate the same stop bookkeeping, and two
SpatialHash-iterating predicates disagree about buildings above level 0 and entries with no
`MovementController`. The next movement refactor (#527) cannot move planning internals behind a
seam while callers depend on the internals.

## What Changes

- Add public `MovementController` queries: `get_state()`, `is_idle()`, `get_surface_level()`,
  `is_exact_move()`, `has_sub_slot()`.
- Add public verbs: `place_at_sub_slot(cell)` (book and snap the parent to the sub-slot),
  `release_sub_slot()` (drop the booking and release `CellReservation` claims), `apply_locomotor()`
  and `tick(delta)` for tests.
- Replace the 9-argument `set_target_position` with named intents: `move_to`, `player_move`,
  `exit_move`, `approach`, `board`. One private implementation plus a private `_retarget` for the
  controller's own internal re-targets. **BREAKING** for in-tree callers; no packed scene binds
  these methods.
- Collapse the three arrival tails (`_finish_stop`, moving arrival, wait arrival) into one
  `_end_move` helper.
- Route both `MovementController` cell predicates through `SpatialHash.get_cell_occupancy` and
  delete the raw `_grid`/`get_blocked_cells` iteration. Deliberate rules: buildings are ground-only
  (they do not block a deck above them), and entries with no `MovementController` do not block a
  movement destination.
- Extend `CellOccupancy` with `shared_moving`, so `blocked` / `moving` / `shared_count` /
  `shared_moving` partition `units` and a sharing mover can ignore other sharers.
- Migrate `HarvestComponent` and `DockHostComponent` off `_reserved` / `_blocked_cells` /
  `_building_cells` to the public occupancy query.

## Capabilities

### New Capabilities

- `movement-controller`: the public query surface, named move intents, sub-slot booking
  verbs, and the single arrival tail.

### Modified Capabilities

- `cell-occupancy`: the composite snapshot gains `shared_moving`, and the momentary facts
  partition `units` into four buckets instead of three.
- `spatial-hash`: the composite query requirement gains the `shared_moving` field.
- `cell-occupancy`: the occupant-exclusion requirement covers `shared_moving`.

## Impact

Affected scripts: `scripts/components/MovementController.gd`, `scripts/core/SpatialHash.gd`,
`scripts/components/ExitComponent.gd`, `DeployComponent.gd`, `TransportComponent.gd`,
`PassengerComponent.gd`, `HarvestComponent.gd`, `DockHostComponent.gd`, `CombatComponent.gd`,
`DockClientComponent.gd`, `scripts/core/SelectionManager.gd`,
`scripts/entities/EntityPlacer.gd`.
Affected tests: every suite that calls the move API (51 calls in 12 files), plus movement,
transport, occupancy, stacked-deck, and placement suites.
No scene or resource format changes. `SpatialHash` keeps its existing per-registry queries.
