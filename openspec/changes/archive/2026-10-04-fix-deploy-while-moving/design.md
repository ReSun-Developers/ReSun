# Design

## Context

See `proposal.md` for motivation. Current state relevant to the approach:

- `execute_deploy()` (`scripts/components/DeployComponent.gd`) is the single
  chokepoint both deploy entry points route through: the Ctrl+D hotkey
  (`MouseHandler.apply_selection_hotkey`) and the click-self order
  (`DeployComponent.get_order_for_target`).
- The deploy needs a free foundation. `_are_foundation_cells_free()` already
  tests a foundation against buildings, blocked cells, resources, terrain, and
  other entities, excluding the source.
- `MovementController` exposes `set_target_position()` and the `arrived` /
  `pathfinding_failed` signals, used by `DockClientComponent` for the same
  "drive to a cell, then act" pattern.
- A pathfinder move to the unit's *own* cell yields an empty path, so a same-cell
  settle cannot go through `set_target_position`.

## Goals / Non-Goals

**Goals:**
- Deploy on a moving/blocked unit drives it to the centre of a valid foundation
  cell, then rotates and transforms.
- One shared flow through the single `execute_deploy()` entry.
- A failed deploy leaves the unit's orders and position untouched.

**Non-Goals:**
- Changing Stop-command semantics.
- Undeploy seeking — buildings are stationary and have no live orders.
- Reworking the snapshot/deferred transform mechanism.

## Decisions

### Choose the next free-foundation cell along the unit's path
`_find_deploy_cell()` first walks the unit's remaining path cells
(`MovementController.get_remaining_path_cells()`) and returns the first whose
whole foundation is free — the Stop command's forward stop, so a moving unit
never reverses to the cell it is leaving. When idle (or no path cell fits), it
uses the current cell when valid, otherwise scans the square out to
`deploy_search_radius_cells` for the nearest free cell. The "foundation free"
predicate lives in one place (`_is_deploy_cell_valid` →
`_are_foundation_cells_free`); the search radius is data-driven.

Alternatives considered:
- *Start from the unit's current cell always (previous behaviour)* — a moving
  unit at the edge of a cell was routed back to the cell centre it had almost
  left, visibly reversing.
- *Scatter in place only* — cannot deploy when a unit is packed against
  buildings and leaves the unit mid-cell.
- *Reuse `stop()` to drive* — it can halt the controller without emitting
  `arrived`, and does not re-validate the chosen foundation.

### Seek via the movement controller; direct glide for the current cell
For a different cell, set the movement target to `CellUtil.cell_to_world(cell)`
and wait for `arrived`. When the unit is already within the chosen cell, a
pathfinder query from and to the same cell yields no path, so a straight-line
glide to the centre is issued instead (`MovementController.move_to_point`) —
still a normal movement step that emits `arrived`, never a teleport. The
rotation begins only once the unit is at the centre.

Alternatives considered:
- *Snap/teleport to the cell centre* — visibly abrupt and bypasses the movement
  system; rejected.
- *Reuse `set_target_position` for the same cell* — empty path, would emit
  `pathfinding_failed`.

### Cancel non-movement activity only
Combat, harvesting, and transport unloading are cancelled so they do not resume
after the transform. Movement is repurposed by the seek. The cancel runs only
after a cell is confirmed, so a failed search leaves orders intact.

### Guard scatter/nudge against mid-deploy units
While seeking, the controller is non-IDLE and already skipped by scatter. While
rotating it is IDLE, so `MovementController._scatter_blockers` /
`nudge_from_cell` and `DeployComponent._scatter_single_cell` skip any entity with
a transitioning `DeployComponent` (`DeployComponent.is_entity_transitioning`).

### Stop cancels an in-flight deploy; a stalled seek self-aborts
A seek relies on the movement controller's `arrived` / `pathfinding_failed`
signals, but `stop()` can halt the controller without emitting either, which
would strand the unit in `SEEKING_DEPLOY` (and `is_transitioning()` would refuse
every later order). `cancel_deploy()` resets the transition, and the Stop
command's cancel sequence calls it alongside harvest/transport. As a safety net,
`_process` watches a seeking unit and aborts if its controller is no longer
moving, so any external stop (e.g. combat engagement) also recovers.

## Risks / Trade-offs

- [Deploy clears an active attack/harvest] → Intended: deploy is a new order.
- [A blocker can take the chosen cell during the approach] → `_on_arrived`
  re-validates the cell and aborts cleanly rather than placing an invalid
  building.
- [Larger search radius costs more cell checks on a crowded map] → Bounded by
  `deploy_search_radius_cells` (default 6).

## Migration Plan

Code-only. No scene, resource, or save-data changes. Rollback is reverting the
commit.
