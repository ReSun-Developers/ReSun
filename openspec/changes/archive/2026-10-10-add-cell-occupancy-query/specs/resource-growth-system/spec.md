# Spec Delta

## ADDED Requirements

### Requirement: Tiberium target cells ignore units and respect terrain

When tiberium germinates or spreads onto a cell, the target-cell test SHALL refuse the cell only
for permanent obstructions and terrain: a building, a bib cell, or non-buildable terrain. It
SHALL NOT refuse a cell because a unit is standing on it. This matches the original TS engine,
whose target test (`CellClass::Can_Tiberium_Germinate`) consults buildings, terrain objects, and
`Ground[Land_Type()].Build`, but has no occupant check — tiberium spreads and thickens under
units. The test SHALL route through the shared resource-intent occupancy query
(`SpatialHash.is_cell_free_for_resource`). The existing separate rule that a cell already
containing a resource grows that resource instead of spawning a new one is unchanged and is
evaluated by the caller, not by the occupancy intent.

#### Scenario: Tiberium spreads under an idle unit
- **WHEN** a spread or tree-seed target cell has buildable terrain, no building or bib, and an idle unit standing on it
- **THEN** the cell is accepted and tiberium appears there

#### Scenario: Tiberium grows under a unit
- **WHEN** an existing resource cell with a unit standing on it receives growth
- **THEN** its amount increases as normal

#### Scenario: Water and slope cells reject tiberium
- **WHEN** a candidate target cell's terrain type is neither `""` nor `"clear"`
- **THEN** the cell is refused

#### Scenario: Building and bib cells reject tiberium
- **WHEN** a candidate target cell is a building footprint or a bib cell
- **THEN** the cell is refused

### Requirement: Tiberium spread source must be unoccupied

Tiberium SHALL NOT spread from a source cell that is occupied by any unit. This matches the
original TS engine, where `CellClass::Can_Tiberium_Spread` returns false when `Cell_Occupier()`
is non-null — a patch covered by a unit stops seeding neighbors until that unit leaves, while
the covered patch itself may still grow. The spread driver SHALL consult the shared composite
snapshot's `units` fact for the source cell before attempting any spread. This rule SHALL apply
only to resource-to-resource spread; tree seeding (`_spawn_in_radius`) SHALL NOT be gated by it.

#### Scenario: A unit on a tiberium cell stops it spreading
- **WHEN** a tiberium cell has a unit standing on it and its neighbors are free
- **THEN** no spread originates from that cell while the unit remains

#### Scenario: Removing the unit resumes spread
- **WHEN** the unit leaves the tiberium source cell
- **THEN** that cell may spread to its neighbors again

#### Scenario: Growth of the covered patch is unaffected
- **WHEN** a unit stands on a tiberium cell
- **THEN** the covered patch still grows (thickens) as usual

#### Scenario: Tree seeding is not gated by an occupied source
- **WHEN** a tree's own cell is occupied by a unit
- **THEN** tree seeding within its radius is unaffected by the source-occupied rule
