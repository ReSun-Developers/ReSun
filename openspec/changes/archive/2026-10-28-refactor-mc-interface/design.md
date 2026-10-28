# Design

## Context

`scripts/components/MovementController.gd` (1819 lines) exposes behaviour through private
fields. The 19 private-member accesses (15 statements) found in this worktree:

| File:line | Access | Intent |
|---|---|---|
| `ExitComponent.gd:78` | write `_has_sub_slot = false` | drop a stale booking |
| `ExitComponent.gd:119` | read `_state` | is idle |
| `DeployComponent.gd:250` | read `_state` | is idle |
| `SpatialHash.gd:158,202` | read `_state` | movement state for the grid entry |
| `MovementController.gd:1079,1605,1637` | read another controller's `_state` | is that neighbour idle |
| `SpatialHash.gd:160,204` | read `_surface_level` | surface level for the grid entry |
| `SelectionManager.gd:255` | read `_surface_level` | reserve the unit's own level |
| `EntityPlacer.gd:46-48` | `_assign_sub_slot_at_cell`, `_has_sub_slot`, `_sub_slot_position` | book and snap |
| `TransportComponent.gd:258-260` | same three | book and snap |
| `PassengerComponent.gd:107` | read `_exact_target` | is this a boarding move |
| `HarvestComponent.gd:327` | read `SpatialHash._reserved` | is the cell reserved |
| `DockHostComponent.gd:86-89` | read `SpatialHash._building_cells/_blocked_cells/_reserved` | is the cell available |

Plus `set_target_position` production callers: plain moves in `DockClientComponent`,
`HarvestComponent`, `DeployComponent`, `ExitComponent`, `PassengerComponent`; the bounded player
move in `SelectionManager`; `keep_zone` in `CombatComponent`; `unblock_buildings` in
`ExitComponent`; `exact_target` in `PassengerComponent`.

## Goals / Non-Goals

**Goals**
- Every production caller uses a named query or intent; no production module reads a
  `MovementController` or `SpatialHash` private.
- One arrival tail.
- One occupancy predicate for movement destinations, built on `get_cell_occupancy`.
- Tests get a Locomotor-driven factory and a public `tick`.

**Non-Goals**
- Moving path search, smoothing, or height baking. That is #527.
- Targeting policy (`_is_enemy_unit` → #520).
- Changing the reservation model or shared-slot capacity.
- Migrating the debug-only `DebugVisualizer` grid reads.

## Decisions

### D1 — Public query surface

```gdscript
func get_state() -> State
func is_idle() -> bool
func get_surface_level() -> int
func is_exact_move() -> bool
func has_sub_slot() -> bool
func get_sub_slot_position() -> Vector3
```

`is_moving()` and `is_waiting()` already exist; `get_state()` is the full snapshot.
`is_idle()` is `_state == State.IDLE`.

### D2 — Named move intents

The 9-argument `set_target_position` becomes the private `_set_target_position` (unchanged body).
Public intents:

| Intent | Mapping | Callers |
|---|---|---|
| `move_to(target)` | `_set_target_position(target)` | plain moves, `get_order_for_target` |
| `player_move(target, cost_cache, terrain, end_level)` | `bounded = true` | `SelectionManager._execute_move` |
| `exit_move(target)` | `unblock_buildings = true` | `ExitComponent` |
| `approach(target)` | `keep_zone = true` | `CombatComponent` |
| `board(target)` | `exact_target = true` | `PassengerComponent` |

Private `_retarget(target, keep_zone = false, end_level = 0)` maps to
`_set_target_position(..., internal = true)` and serves the controller's own re-targets (repair,
blocked arrival, wait scatter, scatter, nudge). `set_exact_target` is removed; `move_to_point`
stays because it is a different straight-line reposition, not a path move.

`player_move` keeps `cost_cache` and `terrain` explicit because only the player-order path
supplies them. `bounded` is player-only; `end_level` is also taken by `_retarget` (the scatter
re-target passes the current surface level).

### D3 — Occupancy rules (deliberate changes)

Current semantics:

| Predicate | Building above level 0 | Entry with no MC |
|---|---|---|
| `_is_cell_occupied_by_idle` | blocks | ignored |
| `_is_destination_clear` | does not block (buildings are ground-only in `get_blocked_cells`) | blocks |

Chosen rule, applied by one `_is_cell_occupied(cell)` built on
`get_cell_occupancy(cell, _surface_level, _parent)`:

- **Buildings are ground-only.** A deck above a building is walkable; the building is beneath it.
  This matches the existing composite-query contract (`building` is a permanent, ground-only
  fact) and the `_is_destination_clear` behaviour. It fixes the `_is_cell_occupied_by_idle` bug
  where a building blocked its own bridge deck.
- **Entries with no `MovementController` do not block a movement destination.** They are not
  mobile occupants; real buildings are reported by the footprint registry, and overlays are not
  in the `entities` group. This matches `_is_cell_occupied_by_idle` and the composite query,
  which already skips `entry["mc"] == null`.

The rule for units is preserved: any unit on the queried level blocks, except that a sharing
mover ignores other sharing units. The name `_is_cell_occupied` replaces both private names;
`find_nearest_free_cell` and the internal spirals use it. `_is_cell_unavailable_for_sub_slot`
keeps its own rule (blocked, ground-only building, bib, full capacity) and gains the ground-only
building guard for consistency with D3. Both destination predicates take an optional level so the
order path can check the resolved `end_level` rather than the unit's current surface. The
pathfinder's blocked set is level-keyed (`CellUtil.cell_level_key`), so a ground building key does
not block the same cell's deck key; `_build_blocked_cells` therefore stays at the starting level. Bib cells are not checked by the destination predicate
(they were not checked before): a dock pad remains a valid destination.

`DockHostComponent.is_cell_available` keeps its exact current rule, now expressed as
`occ.building or occ.blocked or occ.reserved`; it does not gain `moving`, `shared_moving`, or
`bib`. `find_wait_cell` keeps its separate `is_bib_cell` exclusion.

### D4 — CellOccupancy partition

`CellOccupancy` gains `shared_moving: bool`. The four momentary buckets partition `units`:

- `blocked` — IDLE non-sharer present
- `moving` — moving non-sharer present
- `shared_count` — number of IDLE sharers
- `shared_moving` — moving sharer present

`is_cell_free_for_unit_exit` refuses when `blocked`, `moving`, **or** `shared_moving`, preserving
today's behaviour (a moving sharer already refused the exit through `moving`).

### D5 — Arrival tail

One `_end_move(release_cell: Vector2i, announce: bool)` performs: clear `_has_sub_slot`, clear
`_hybrid_active`, zero `_ramp_speed`, set `IDLE`, clear `_idle_snapped`, release the SpatialHash
cell at `release_cell` and the `_surface_level`, release all `CellReservation` claims, clear the
debug path. When `announce`, it offers the trigger event and emits `arrived`. Callers keep their
distinct pre-tail (clear waypoints for `_finish_stop`; Y snap / descend for moving and wait
arrival) and post-tail (cell-entry crush/ice tracking in the moving branch). The moving branch
keeps the existing `if not _parent.is_inside_tree(): return` guard immediately after
`_end_move`, because an `arrived` subscriber (boarding) may detach or free the mover.

### D6 — Sub-slot verbs

```gdscript
func place_at_sub_slot(cell: Vector2i, level: int = -1) -> bool
func release_sub_slot() -> void
```

`place_at_sub_slot` books at `level` (default current surface), and on success moves `_parent` to
`_sub_slot_position` and returns true. `EntityPlacer` and `TransportComponent` each collapse to
one call. `release_sub_slot` clears `_has_sub_slot` and calls
`CellReservation.release_all(_parent)`; `ExitComponent` drops its separate `release_all`.

### D7 — Test surface

- `apply_locomotor(data: Locomotor, rules: GlobalRules = null)` mirrors the flags from a
  Locomotor resource. It resolves rules from `rules`, then `_rules`, then `GlobalRules.get_current()`;
  hover height uses the resource override first and the rules default second, and ice weight uses
  the rules value when available. `_resolve_locomotor` delegates with its cached `_rules`.
- `tick(delta)` calls `_physics_process(delta)`.
- `MovementFactory.make_movement_controller(locomotor, entity_type)` (`test/movement_test_factory.gd`)
  creates the entity root, stats,
  and controller, binds `_parent`, and applies the locomotor. One helper owns the private
  `_parent` write that used to be repeated in every suite.

## Characterization and regression tests

Pinned on `origin/main` before the change (see PR evidence):

1. `_is_cell_occupied_by_idle(cell)` on a building cell with `_surface_level = 1` returns
   `true`; `_is_destination_clear(cell)` returns `true` (not blocked).
2. `_is_cell_occupied_by_idle(cell)` on a grid entry with `mc = null` returns `false`;
   `_is_destination_clear(cell)` returns `false` (blocked).

The final tests assert the chosen unified rule, so tests 1 and 2 fail on base for the intended
reason (the deck case and the no-MC destination case).

Placement regressions (pass on base, guard the verb migration):
- `EntityPlacer.place_entity` with a Foot infantry lands the entity on
  `CellSubPositions.get_sub_position(cell, slot)`, not the cell centre.
- `TransportComponent._readd_passenger_at_free_cell` lands the passenger on the booked sub-slot.

## Scope cuts

- #527 (MovePlanner / path search) — untouched.
- #520 (targeting policy / `_is_enemy_unit`) — untouched.
- Debug-only `DebugVisualizer._grid` reads — untouched.
- `get_blocked_cells` keeps its allocation; the hot spiral no longer calls it because the
  predicate uses occupancy.

## Risks

- `place_at_sub_slot` assumes `_parent` is bound (`_ready` ran). Every existing caller already
  assumed that through `_assign_sub_slot_at_cell`, so no new precondition.
- `get_cell_occupancy` evaluates terrain buildability on level 0. The spiral now pays that per
  candidate cell; it replaces building a whole blocked-cell dictionary per candidate, which is
  strictly cheaper for the 81-cell worst case.
