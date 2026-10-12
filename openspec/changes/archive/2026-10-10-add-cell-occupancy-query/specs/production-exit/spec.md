# Spec Delta

## MODIFIED Requirements

### Requirement: ExitComponent defines exit point for units leaving buildings

The system SHALL provide an ExitComponent that defines where units spawn and exit from a
building. ExitComponent SHALL specify `exit_offset: Vector3` (local-space offset from building
origin for exit position), `spawn_offset: Vector3` (local-space offset for spawn position), and
`exit_facing: int` (degrees). When a building has no ExitComponent, the unit SHALL spawn at the
nearest free cell adjacent to the building.

Every free-cell search connected to producing or exiting a unit — `ExitComponent`,
`FactoryComponent`, and `ProductionManager`'s fallback spawner — SHALL evaluate candidate cells
through the shared unit-exit occupancy intent (`SpatialHash.is_cell_free_for_unit_exit`) rather
than a private per-class predicate, so all spawn paths agree on what blocks a cell. A candidate
SHALL be refused when it holds a building or bib cell, an idle non-sharer, or a moving unit —
matching the original TS engine where `Find_Exit_Cell` demands a `MOVE_OK` result and a moving
occupant yields `MOVE_MOVING_BLOCK` — or when idle sharers have reached `shared_slots_per_cell`. A
resource (tiberium) cell SHALL NOT be refused, and non-`"clear"` terrain SHALL NOT be refused
either: the exit test is a movement test, tiberium is driveable, and a slope is walkable.
Locomotor-aware exit passability (water, per-locomotor reach) is deferred to the movement/
passability work and is out of scope here.

The `ProductionManager` fallback spawner SHALL retain the unit in the ready-to-spawn state with a
warning when no exit cell is free within the search radius, and SHALL NOT spawn the unit inside
the building's own cell. When `ExitComponent`/`FactoryComponent` find no free candidate they
retain their existing fallback (they spawn at the best candidate, which may be the building's own
cell); unifying that fallback with the retained-retry behavior is a follow-up, not part of the
predicate convergence.

#### Scenario: Unit exits from war factory
- **WHEN** a vehicle is produced at a war factory with ExitComponent configured
- **THEN** the vehicle SHALL spawn at `spawn_offset` in the building's local space, transformed to world coordinates
- **THEN** the vehicle SHALL be positioned at `exit_offset` in the building's local space after exit
- **THEN** the vehicle SHALL face `exit_facing` degrees

#### Scenario: Building without ExitComponent spawns unit at free cell
- **WHEN** a unit is produced at a building without ExitComponent and a free adjacent cell exists
- **THEN** the unit SHALL spawn at the nearest cell the shared exit intent reports free

#### Scenario: Moving unit blocks a candidate exit cell
- **WHEN** a candidate exit cell holds a moving unit
- **THEN** the shared exit intent SHALL refuse it

#### Scenario: Idle unit blocks a candidate exit cell
- **WHEN** a candidate exit cell holds an idle non-sharer
- **THEN** the shared exit intent SHALL refuse it

#### Scenario: Idle sharer below capacity is a valid exit cell
- **WHEN** a candidate exit cell holds fewer idle sharers than `shared_slots_per_cell` and no other unit
- **THEN** the shared exit intent SHALL accept it

#### Scenario: Walkable slope is a valid exit cell
- **WHEN** a candidate exit cell's terrain type is `"slope"` and it holds no unit or building
- **THEN** the shared exit intent SHALL accept it (walkability is a locomotor concern)

#### Scenario: Tiberium cell is a valid exit cell
- **WHEN** a candidate exit cell holds a resource (tiberium) entity and no unit or building
- **THEN** the shared exit intent SHALL accept it

#### Scenario: No free cell available near building
- **WHEN** the `ProductionManager` fallback spawner finds no free exit cell within the search radius
- **THEN** the unit SHALL NOT be placed on the building's own cell
- **THEN** a warning SHALL be logged and the unit SHALL be retained in the ready-to-spawn retry state

#### Scenario: No private availability predicate
- **WHEN** the ExitComponent and FactoryComponent exit paths are inspected
- **THEN** neither defines its own cell-availability predicate; both delegate to the shared exit intent
