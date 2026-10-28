# movement-controller Specification

## Purpose
TBD - created by archiving change refactor-mc-interface. Update Purpose after archive.

## Requirements

### Requirement: MovementController public query surface

`MovementController` SHALL expose public queries for every fact production callers and tests
need, so no caller reads a private field: `get_state() -> State`, `is_idle() -> bool`,
`get_surface_level() -> int`, `is_exact_move() -> bool`, `has_sub_slot() -> bool`, and
`get_sub_slot_position() -> Vector3`. `get_state()` SHALL return the current movement state;
`is_idle()` SHALL be true exactly when the state is `IDLE`; `get_surface_level()` SHALL return the
surface level the unit currently stands on or is stepping onto; `is_exact_move()` SHALL report
whether the current move keeps its occupied destination; `has_sub_slot()` and
`get_sub_slot_position()` SHALL report the current booking.

#### Scenario: Idle query
- **WHEN** the controller is in `IDLE`
- **THEN** `is_idle()` is true and `get_state()` returns `State.IDLE`

#### Scenario: Surface level query
- **WHEN** a unit stands on a bridge deck at level 1
- **THEN** `get_surface_level()` returns 1

#### Scenario: Booking query
- **WHEN** a sharing unit has booked a sub-slot on its destination cell
- **THEN** `has_sub_slot()` is true and `get_sub_slot_position()` returns that sub-slot's world
  position

### Requirement: Named move intents

`MovementController` SHALL expose one named intent per production move shape and SHALL NOT
require callers to pass positional behaviour flags:

- `move_to(target)` — plain path move;
- `player_move(target, cost_cache, terrain, end_level)` — bounded player order with the path
  cost cache, terrain source, and destination level;
- `exit_move(target)` — move that may unblock building footprints (production exit);
- `approach(target)` — move that preserves a jumpjet's current vertical zone (combat approach);
- `board(target)` — exact-target move onto an occupied destination (transport boarding).

One private implementation SHALL sit behind the intents, and a private re-target SHALL serve the
controller's own repair, blocked-arrival, wait-scatter, scatter, and nudge moves. Only the public
intents SHALL emit `movement_started`; the private re-target SHALL NOT.

#### Scenario: Plain move
- **WHEN** a caller invokes `move_to(target)`
- **THEN** the controller paths to `target` and emits `movement_started` once

#### Scenario: Player move is bounded
- **WHEN** `player_move` is called with an occupied destination outside the order area
- **THEN** the relocation spiral stays inside `BoundsSystem.is_in_order_area`

#### Scenario: Exit move unblocks buildings
- **WHEN** `exit_move` is called toward a cell covered by a building footprint
- **THEN** the building footprint does not block that path

#### Scenario: Approach keeps the zone
- **WHEN** `approach` is called on an airborne jumpjet
- **THEN** the jumpjet stays in its air zone for the approach

#### Scenario: Board keeps the occupied destination
- **WHEN** `board` is called toward an occupied transport cell
- **THEN** the destination is not relocated and arrival fires on the occupied cell

#### Scenario: Internal re-target is silent
- **WHEN** the controller re-targets itself after a blocked arrival or a nudge
- **THEN** `movement_started` is not emitted

### Requirement: Sub-slot booking verbs

`MovementController` SHALL own sub-slot booking through two public verbs.
`place_at_sub_slot(cell, level = -1)` SHALL book a sub-slot for the cell at `level` (defaulting to
the unit's current surface), move the controller's parent to the booked world position on
success, and return whether the booking succeeded. `release_sub_slot()` SHALL drop the booking
and release every `CellReservation` claim held by the parent. Callers SHALL NOT read
`CellReservation` or compute a sub-slot position to snap a unit into place.

#### Scenario: Placement books and snaps
- **WHEN** `place_at_sub_slot(cell)` succeeds
- **THEN** the parent's world position equals the booked `CellSubPositions.get_sub_position(...)`
  and `has_sub_slot()` is true

#### Scenario: Full cell refuses placement
- **WHEN** every sub-slot on the cell is claimed
- **THEN** `place_at_sub_slot(cell)` returns false and the parent does not move

#### Scenario: Release drops booking and claims
- **WHEN** `release_sub_slot()` is called on a unit holding a claim
- **THEN** `has_sub_slot()` is false and the cell's claim count drops

### Requirement: Single arrival tail

Every move that reaches its destination SHALL finish through one shared arrival helper. The
helper SHALL clear the sub-slot booking and hybrid/landing flags, zero the speed ramp, set the
state to `IDLE`, release the SpatialHash cell reservation and all `CellReservation` claims, and
clear the debug path. It SHALL offer the cell-entry trigger and emit `arrived` only for a
completed move, not for `stop()` or `_finish_stop()`.

#### Scenario: Moving arrival announces
- **WHEN** a moving unit reaches its final waypoint
- **THEN** the state becomes `IDLE`, bookings and claims are released, and `arrived` is emitted

#### Scenario: Wait arrival announces
- **WHEN** a waiting unit's destination clears and it settles onto the destination
- **THEN** the same arrival bookkeeping runs and `arrived` is emitted

#### Scenario: Stop does not announce
- **WHEN** `stop()` completes
- **THEN** the same bookkeeping runs but `arrived` is not emitted

#### Scenario: Detached subscriber is safe
- **WHEN** an `arrived` subscriber detaches the mover (boarding a transport)
- **THEN** the post-arrival cell tracking is skipped and no freed parent is read
