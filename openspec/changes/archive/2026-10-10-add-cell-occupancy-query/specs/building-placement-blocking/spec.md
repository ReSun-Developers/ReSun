# Spec Delta

## MODIFIED Requirements

### Requirement: Building placement blocks on moving units

`BuildingManager._is_cell_free()` and `FoundationComponent.is_cell_buildable()` SHALL resolve
through the shared build-intent occupancy query, and SHALL return `false` for any foundation cell
that is a building or bib cell, a resource cell, non-buildable terrain, or holds any unit body
regardless of movement state (IDLE, MOVING, ROTATING, etc.). The reject set is unchanged except
that a cell outside the grid extent is now non-buildable terrain (it read as buildable before the
bounds guard); the checks are centralized, not otherwise altered. (A cell reserved for an inbound
unit is **not** part of this test — ReSun reservations include each selected unit's own origin
cell, so folding them in would refuse freshly-vacated empty cells; see the change design D6.)

#### Scenario: Moving unit blocks placement
- **WHEN** a unit is in MOVING state on cell (5, 5)
- **AND** SpatialHash has been rebuilt this frame (entity is registered in _grid)
- **AND** the player attempts to place a building whose foundation covers cell (5, 5)
- **THEN** `_is_cell_free(Vector2i(5, 5))` returns `false`
- **AND** the foundation preview shows red for that cell

#### Scenario: Idle unit still blocks placement
- **WHEN** a unit is in IDLE state on cell (5, 5)
- **AND** SpatialHash has been rebuilt this frame
- **AND** the player attempts to place a building whose foundation covers cell (5, 5)
- **THEN** `_is_cell_free(Vector2i(5, 5))` returns `false`

#### Scenario: Empty cell allows placement
- **WHEN** no entity occupies cell (5, 5)
- **AND** the cell is not a building, resource, or bib cell
- **THEN** `_is_cell_free(Vector2i(5, 5))` returns `true`

#### Scenario: Resource entity does not double-block
- **WHEN** a resource pod entity occupies cell (5, 5)
- **AND** no other entity occupies the cell
- **THEN** `_is_cell_free(Vector2i(5, 5))` returns `false` (via the resource permanent fact in the shared query)
- **AND** `units` is empty, so the entity-occupancy term does not additionally flag it
