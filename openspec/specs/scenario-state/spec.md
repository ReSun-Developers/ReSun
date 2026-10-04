# scenario-state Specification

## Purpose
Holds mission-scoped scripting state — global flags, per-house local flags, a waypoint registry,
and the mission timer — and resets cleanly between missions so no state leaks across a match.

## Requirements

### Requirement: Global flags

`ScenarioState` SHALL store named boolean global flags, addressed by declared name. It SHALL expose
`set_global(name)`, `clear_global(name)`, `get_global(name) -> bool` (defaulting to `false`), and
`has_global(name)`. Setting or clearing SHALL emit `global_changed(name, value)` only when the value
actually changes. A flag addressed by a name not declared in the variable table SHALL be rejected
with a diagnostic.

#### Scenario: Set and read a global
- **WHEN** a declared global `"EnemySighted"` is set
- **THEN** `get_global("EnemySighted")` is true

#### Scenario: Clear a global
- **WHEN** a set global is cleared
- **THEN** `get_global` is false

#### Scenario: Change signal is edge-only
- **WHEN** an already-set global is set again
- **THEN** `global_changed` is not emitted

#### Scenario: Undeclared global rejected
- **WHEN** `set_global` is called for a name that is not in the declared variable table
- **THEN** the call is rejected with a diagnostic and no flag is recorded

### Requirement: Per-house local flags

`ScenarioState` SHALL store named boolean local flags scoped to a house, addressed by declared local
name and house id. Locals for different houses SHALL be independent. Setting or clearing SHALL emit
`local_changed(house_id, name, value)` only on a value change, and an undeclared local name SHALL be
rejected with a diagnostic.

#### Scenario: Locals are house-scoped
- **WHEN** local `"BaseAttacked"` is set for `GDI`
- **THEN** `get_local("GDI", "BaseAttacked")` is true and `get_local("Nod", "BaseAttacked")` is false

#### Scenario: Local change is edge-only
- **WHEN** an already-set local is set again for the same house
- **THEN** `local_changed` is not emitted

#### Scenario: Undeclared local rejected
- **WHEN** a local is set with a name not in the declared local table
- **THEN** the call is rejected with a diagnostic

### Requirement: Waypoint registry

`ScenarioState` SHALL store named waypoints mapping a waypoint id to a grid cell. It SHALL expose
`set_waypoint(id, cell)`, `get_waypoint(id) -> Variant` (a cell or null when unset), and
`has_waypoint(id)`. Waypoints SHALL be loadable in bulk from the map JSON `waypoints` object, whose
values are `"x,y"` strings, and an entry with a malformed value SHALL be discarded with a diagnostic
without aborting the load.

#### Scenario: Set and read a waypoint
- **WHEN** waypoint `"A"` is set to cell `(70, 51)`
- **THEN** `get_waypoint("A")` is `(70, 51)` and `has_waypoint("A")` is true

#### Scenario: Unknown waypoint
- **WHEN** `get_waypoint` is called for an unset id
- **THEN** it returns null and `has_waypoint` is false

#### Scenario: Malformed entry discarded
- **WHEN** waypoints are loaded from a map whose `waypoints` contains a non-`"x,y"` value
- **THEN** that entry is discarded with a diagnostic and the remaining entries load

### Requirement: Mission timer

`ScenarioState` SHALL provide a mission timer measured in whole logic seconds, advanced by
`MatchClock` ticks. It SHALL expose `start_timer()`, `stop_timer()`, `set_timer(seconds)`,
`add_timer(seconds)`, `get_timer() -> int`, and `is_timer_running() -> bool`, and SHALL emit
`mission_timer_expired` once when a running timer reaches zero.

#### Scenario: Timer counts down
- **WHEN** the timer is set to three seconds and started
- **THEN** after three logic seconds `get_timer()` is zero and `mission_timer_expired` has been emitted once

#### Scenario: Stopped timer does not advance
- **WHEN** the timer is stopped
- **THEN** further logic ticks do not change `get_timer()`

#### Scenario: Adding time extends a running timer
- **WHEN** `add_timer(5)` is called while the timer is running
- **THEN** the remaining time increases by five seconds

### Requirement: Reset

`ScenarioState.reset()` SHALL clear all global flags, all per-house local flags, all waypoints, and
the mission timer, returning every flag to its default `false`.

#### Scenario: Reset clears everything
- **WHEN** `reset()` is called after globals, locals, waypoints and a timer were set
- **THEN** no flag is set, no waypoint resolves, and the timer is stopped at zero
