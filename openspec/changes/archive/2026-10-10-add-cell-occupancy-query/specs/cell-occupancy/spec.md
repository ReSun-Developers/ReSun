# Spec Delta

## ADDED Requirements

### Requirement: Composite cell-occupancy snapshot

`SpatialHash` SHALL expose a single composite occupancy query that reports every fact about a
cell's occupancy at once, so consumers stop enumerating individual registries. The query SHALL
return a typed result carrying, for a given `(cell, level)` and an optional excluded entity:

- permanent (ground-only) facts: `building` (a non-bib building footprint cell), `bib` (a bib
  cell), `resource` (a resource overlay cell), and `terrain_buildable` (the cell's terrain admits
  construction, and the cell is within the grid);
- momentary (level-scoped) facts: `units` (the entity roots with a `MovementController` on that
  level, minus the excluded entity), `blocked` (any such unit is IDLE and does not share the
  cell), `moving` (any such unit is not IDLE), `shared_count` (the count of such units that are
  IDLE and share the cell), and `reserved` (the cell is reserved for a unit).

`blocked`, `moving`, and `shared_count` SHALL partition `units`, so a caller can distinguish an
idle sharer (below capacity) from a moving unit. `units` SHALL hold entity roots, not raw grid
entries. `terrain_buildable` SHALL be the value of a single `TerrainSystem` buildability
predicate that owns the `""`/`"clear"` convention and returns false for a cell outside the grid;
no consumer SHALL re-inline that comparison. Buildings and resource overlays SHALL NOT appear in
`units` (buildings have no `MovementController`; overlays are excluded from the entity group) —
they are reported as the permanent facts.

#### Scenario: Empty clear cell reports nothing occupied
- **WHEN** `get_cell_occupancy(cell)` is called for an in-bounds cell with no building, bib,
  resource, unit, or reservation and clear terrain
- **THEN** every permanent and momentary fact is false/empty and `terrain_buildable` is true

#### Scenario: Building footprint cell reported
- **WHEN** a building registers a footprint cell
- **THEN** `building` is true, `units` is empty, and `terrain_buildable` reflects the cell's terrain

#### Scenario: Unit body classified by state and sharing
- **WHEN** a unit occupies a cell at level `L`
- **THEN** its root appears in `units` for level `L`, and it contributes to exactly one of
  `blocked`, `moving`, or `shared_count` according to its state and sharing

#### Scenario: Terrain convention lives in one place
- **WHEN** the composite query evaluates an in-bounds cell whose terrain type is neither `""` nor `"clear"`
- **THEN** `terrain_buildable` is false

#### Scenario: Out-of-bounds cell is not buildable terrain
- **WHEN** the composite query evaluates a cell outside the grid extent
- **THEN** `terrain_buildable` is false

### Requirement: Occupancy intents

The system SHALL encode each consumer intent exactly once as a projection of the composite
snapshot, so no two consumers re-derive a different subset. The intents SHALL be:

- **build** — a structure may occupy the cell: buildable terrain, no building/bib/resource, and
  no unit body of any state (idle, moving, or sharing). This matches TS `Is_Clear_To_Build`.
- **unit exit** — a produced or free unit may appear on the cell: no building/bib, no idle
  non-sharer and no moving unit, and idle sharers below `shared_slots_per_cell`. A cell holding
  idle sharers up to capacity SHALL be free; a cell at capacity, or holding a moving unit, SHALL
  be refused. A resource cell SHALL NOT be refused (the exit test is a movement test and tiberium
  is driveable), and non-`"clear"` terrain SHALL NOT be refused either — walkability is a
  locomotor concern, not buildability (a slope is walkable). This matches TS
  `Can_Enter_Cell == MOVE_OK`.
- **resource** — tiberium may seed the cell: buildable terrain, no building/bib. Units SHALL be
  ignored (tiberium grows under units, matching TS `Can_Tiberium_Germinate`).

The exit intent's sharing capacity SHALL be the physical idle-sharer count, matching the current
`is_cell_full_for_shared` used by the exit paths. In-flight `CellReservation` claims remain the
capacity source for sharing-unit targeting (`CellReservation.is_cell_full`); exit candidate
selection does not consult claims.

#### Scenario: Build intent refuses any unit
- **WHEN** a cell holds a moving unit, an idle non-sharer, or an idle sharer
- **THEN** the build intent reports it not free

#### Scenario: Exit intent allows an idle sharer below capacity
- **WHEN** a cell holds one idle sharer and `shared_slots_per_cell` is 3
- **THEN** the exit intent reports it free

#### Scenario: Exit intent refuses at sharing capacity
- **WHEN** a cell holds `shared_slots_per_cell` idle sharers
- **THEN** the exit intent reports it not free

#### Scenario: Exit intent refuses a moving unit
- **WHEN** a cell holds a moving unit
- **THEN** the exit intent reports it not free

#### Scenario: Exit intent allows a resource cell
- **WHEN** a cell holds only tiberium
- **THEN** the exit intent reports it free

#### Scenario: Resource intent ignores units
- **WHEN** a cell has buildable terrain, no building or bib, and a unit standing on it
- **THEN** the resource intent reports it free

### Requirement: Occupant exclusion

The composite query SHALL accept an optional `exclude` entity whose momentary contribution is
ignored, so a caller can ask "is this cell free apart from me" without reading the raw grid.
`exclude` SHALL affect only the momentary facts (`units`, `blocked`, `moving`, `shared_count`)
and SHALL NOT affect `reserved` or the permanent facts. When the excluded entity is the only
momentary occupant the cell SHALL report free.

#### Scenario: Sole occupant excluded
- **WHEN** a unit queries its own cell with itself as `exclude`
- **THEN** `units` is empty and the cell reports free

#### Scenario: A second occupant is not excluded
- **WHEN** the same cell also holds another unit
- **THEN** the cell reports occupied despite the exclusion

#### Scenario: Exclusion does not hide a reservation
- **WHEN** a cell reserved for an inbound unit is queried with an unrelated `exclude`
- **THEN** `reserved` remains true
