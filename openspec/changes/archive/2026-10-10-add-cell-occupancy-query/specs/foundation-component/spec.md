# Spec Delta

## MODIFIED Requirements

### Requirement: Single-cell buildability predicate

`FoundationComponent` SHALL expose a static `is_cell_buildable(cell)` that delegates to the
shared build-intent occupancy query (`SpatialHash.is_cell_free_for_build`), returning its
result. The predicate SHALL NOT enumerate spatial registries or inline the `""`/`"clear"`
terrain comparison itself; those live in the composite query and the `TerrainSystem`
buildability predicate respectively. This predicate remains the single implementation reused by
placement validation and preview rendering, so `BuildingManager.can_place` and
`_resolve_highlight_cell_state` agree by construction.

#### Scenario: Free clear cell is buildable
- **WHEN** a cell has no buildings, entities, resources, or reservation and its terrain type is `"clear"`
- **THEN** `is_cell_buildable(cell)` returns `true`

#### Scenario: Building cell is not buildable
- **WHEN** a cell is registered as a building cell in `SpatialHash`
- **THEN** `is_cell_buildable(cell)` returns `false`

#### Scenario: Predicate delegates to the shared query
- **WHEN** `is_cell_buildable(cell)` is called
- **THEN** it returns `SpatialHash.is_cell_free_for_build(cell)`

#### Scenario: No private registry access
- **WHEN** the buildability path is inspected
- **THEN** it reads no `SpatialHash` private field directly
