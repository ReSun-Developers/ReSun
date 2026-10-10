# Spec Delta

## ADDED Requirements

### Requirement: Composite cell-occupancy query

`SpatialHash` SHALL expose `get_cell_occupancy(cell: Vector2i, level: int = 0, exclude: Node3D =
null) -> SpatialHash.CellOccupancy`. `CellOccupancy` SHALL be an inner class of `SpatialHash`
(a `RefCounted`; GDScript permits one `class_name` per file, so it is not a second top-level
`class_name`). Its fields and their meanings are defined in the `cell-occupancy` capability
(`building`, `bib`, `resource`, `terrain_buildable`, `units`, `blocked`, `moving`,
`shared_count`, `reserved`, `cell`, `level`).

`SpatialHash` SHALL also expose the intent projections `is_cell_free_for_build(cell, level = 0,
exclude = null)`, `is_cell_free_for_unit_exit(cell, level = 0, exclude = null)`, and
`is_cell_free_for_resource(cell, level = 0)`, each defined as a projection of the composite
result (see `cell-occupancy`). The query SHALL read terrain buildability from the single
`TerrainSystem` predicate and momentary occupancy from the level-scoped grid, reservation, and
shared-count registries.

The existing per-registry queries (`is_cell_blocked`, `is_any_entity_on_cell`, `has_resource_cell`,
`is_bib_cell`, `get_building_cells`, `has_bridge_on_cell`, `is_cell_full_for_shared`) SHALL keep
their current contracts and SHALL NOT be removed.

#### Scenario: Snapshot fields present
- **WHEN** `get_cell_occupancy(cell)` is called
- **THEN** it returns a `SpatialHash.CellOccupancy` exposing `building`, `bib`, `resource`,
  `terrain_buildable`, `units`, `blocked`, `moving`, `shared_count`, and `reserved`

#### Scenario: Intent projections delegate
- **WHEN** `is_cell_free_for_build`, `is_cell_free_for_unit_exit`, or
  `is_cell_free_for_resource` is called
- **THEN** it returns the result of applying that intent's rule to the composite snapshot

#### Scenario: Level scoping preserved
- **WHEN** a unit occupies a deck at level `L`
- **THEN** `units` for level 0 is empty and `units` for level `L` contains the unit

#### Scenario: Existing queries unchanged
- **WHEN** `is_any_entity_on_cell`, `is_cell_blocked`, or `is_cell_full_for_shared` is called
- **THEN** it returns the same result as before this change
