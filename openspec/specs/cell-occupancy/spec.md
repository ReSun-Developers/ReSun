# cell-occupancy Specification

## Purpose
TBD - created by archiving change locomotor-shares-cell. Update Purpose after archive.

## Requirements

### Requirement: Shared cell capacity
The system SHALL allow up to `GlobalRules.shared_slots_per_cell` units whose Locomotor has `shares_cell = true` to occupy the same cell. Capacity SHALL combine physical idle sharers (from the SpatialHash grid) with in-flight sub-slot claims held by `CellReservation`, and SHALL be sharing-scoped (vehicle blocking uses physical presence only). Idle sharer cells SHALL block pathfinding for non-sharing entities (vehicles cannot path through) when at least 1 idle sharer is present.

#### Scenario: Vehicle blocked by single sharer
- **WHEN** a vehicle attempts to pathfind through a cell with 1 idle `shares_cell = true` unit
- **THEN** the cell is treated as blocked for the vehicle

#### Scenario: Sharer enters cell with 2 sharers
- **WHEN** a `shares_cell = true` unit attempts to enter a cell with 2 idle sharers and no claims
- **THEN** the cell is treated as not blocked (capacity not reached)

#### Scenario: Sharer blocked at capacity
- **WHEN** a `shares_cell = true` unit attempts to enter a cell with `shared_slots_per_cell` idle sharers, or a combination of idle sharers and in-flight claims totaling the capacity
- **THEN** the cell is treated as full and the unit spreads to a neighboring cell

#### Scenario: In-flight claims count toward capacity
- **WHEN** a cell has fewer than the capacity in idle sharers but in-flight claims bring the total to the capacity
- **THEN** the cell is treated as full for sharing-unit targeting

#### Scenario: Capacity follows rules
- **WHEN** `shared_slots_per_cell = 4` is configured
- **THEN** the cell is full at 4 sharers, not at 3

### Requirement: Sub-slot positioning
The system SHALL assign each sharer a deterministic sub-slot position. Positions SHALL be generated per-cell using a seeded PRNG (Mulberry32) with trigonometric placement: `CellSubPositions.get_slot_count()` positions evenly spaced at equal angular intervals on a circle of radius `(half_cell - 0.15) * 0.7`, with a random base angle seeded from cell coordinates. `CellSubPositions` SHALL expose `get_slot_count()` resolving `GlobalRules.shared_slots_per_cell` with a fallback of 3, and SHALL perform no occupancy tracking; slot occupancy is the responsibility of the SpatialHash grid (present units) and `CellReservation` (in-flight claims).

#### Scenario: Deterministic positions
- **WHEN** `CellSubPositions.get_sub_positions(cell)` is called twice with the same cell
- **THEN** both calls return identical positions

#### Scenario: Margin enforcement
- **WHEN** sub-positions are generated for any cell
- **THEN** all positions are at least 0.15 units from the cell edge

#### Scenario: Slot spacing
- **WHEN** sub-positions are generated for any cell
- **THEN** all positions are at least `min_slot_dist` apart from each other

#### Scenario: Geometry follows capacity
- **WHEN** `shared_slots_per_cell = 4` is configured
- **THEN** `get_sub_positions(cell)` returns 4 positions

### Requirement: Sharing repulsion bypass
The system SHALL NOT apply repulsion forces between two `shares_cell = true` units during movement. Sharers SHALL freely overlap with other sharers while moving.

#### Scenario: Two sharers moving nearby
- **WHEN** two `shares_cell = true` units are both in MOVING state and within repulsion range
- **THEN** neither unit receives a repulsion push from the other

#### Scenario: Sharer repelled by vehicle
- **WHEN** a `shares_cell = true` unit is in MOVING state near a moving non-sharing vehicle
- **THEN** the sharer receives normal repulsion from the vehicle

### Requirement: Per-level shared cell capacity
Cell capacity SHALL be evaluated per surface level. Each level of a cell (ground and each deck) SHALL have its own `shared_slots_per_cell` places, combining physical idle sharers at that level with in-flight `CellReservation` claims for that level. A deck's capacity SHALL NOT be reduced by ground occupants beneath it, and vice versa. Idle sharer cells SHALL block pathfinding for non-sharing entities at that level only. When no level is supplied, capacity SHALL resolve at level 0.

#### Scenario: Deck capacity independent of ground
- **WHEN** a cell's ground level has `shared_slots_per_cell` idle sharers and its deck level is empty
- **THEN** the deck level is not full

#### Scenario: Ground capacity independent of deck
- **WHEN** a cell's deck level has `shared_slots_per_cell` idle sharers and its ground level is empty
- **THEN** the ground level is not full

#### Scenario: Ground level blocks at capacity
- **WHEN** a cell's ground level reaches `shared_slots_per_cell` idle sharers
- **THEN** the ground level is full for sharing-unit targeting

#### Scenario: Default level is ground
- **WHEN** a capacity query is made without a level
- **THEN** it resolves against level 0

### Requirement: Per-level sub-slot positions
`CellSubPositions` SHALL generate sub-slot positions per surface level, so a deck's places are positioned independently of the ground's. `CellSubPositions.get_sub_positions(cell, level, slot_count)` and `get_sub_position(cell, level, slot)` SHALL include the level in their seeded placement, and SHALL default to level 0. Positions SHALL remain deterministic for a given `(cell, level)` and satisfy the existing margin and spacing guarantees.

#### Scenario: Deck positions differ from ground
- **WHEN** sub-slot positions are generated for the same cell at level 0 and a deck level
- **THEN** the two sets are independent and do not have to coincide

#### Scenario: Deterministic per level
- **WHEN** `get_sub_positions(cell, level)` is called twice for the same cell and level
- **THEN** both calls return identical positions

#### Scenario: Default level preserves positions
- **WHEN** `get_sub_positions(cell)` is called without a level
- **THEN** it returns the level-0 positions, matching pre-change behavior

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
