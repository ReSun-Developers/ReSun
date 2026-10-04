# Proposal

## Why

A deployable unit (e.g. an MCV) issued a deploy while moving does not deploy
correctly. It must stand at the centre of a cell whose whole foundation is
free before transforming. Today the deploy rotation starts immediately wherever
the unit happens to be, so a mid-cell, blocked, or reversing position produces a
misaligned or invalid placement.

## What Changes

- `DeployComponent.execute_deploy()` SHALL choose a deploy cell whose entire
  building foundation is free. A moving unit follows its current path forward —
  like the Stop command — and takes the first cell ahead that fits, never
  reversing to the cell it is leaving. An idle unit uses its own cell when valid,
  otherwise the nearest free cell within `deploy_search_radius_cells`.
- The unit SHALL drive to the chosen cell's centre through the movement
  controller (never teleport), then rotate and transform. When already centred,
  it rotates directly.
- Deploy SHALL cancel combat, harvesting, and transport unloading so they do not
  resume after the transform.
- The Stop command SHALL cancel an in-flight deploy seek/rotation and return the
  unit to a commandable state; a stalled seek SHALL abort rather than lock the
  unit in `is_transitioning()`.
- If no free cell exists, deploy SHALL fail and leave the unit's current orders
  untouched.
- Regression tests SHALL cover: following the path forward, centring on the
  current cell, seeking a nearby free cell when blocked, rotating on arrival,
  Stop cancelling a seek, and failed deploy preserving the move.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `deploy-undeploy`: a deploy now selects a free-foundation cell (following the
  unit's path when moving) and drives the unit to its centre before rotating,
  instead of rotating in place.

## Impact

- `scripts/components/DeployComponent.gd` — cell selection, seeking state, arrival handling, cancel.
- `scripts/components/MovementController.gd` — `get_remaining_path_cells()`, `move_to_point()`; scatter/nudge skip deploying units.
- `scripts/hud/MouseHandler.gd` — Stop cancels an in-flight deploy.
- `test/unit/test_deploy_component.gd` — tests.
- No scene/`.tscn` changes; no `EntityData` schema changes; no new autoloads.
