# Spec Delta

## MODIFIED Requirements

### Requirement: Entity placement
Clicking a map cell SHALL place the selected entity at that cell through the `EntityFactory` spawn seam. Single-cell entities are centered on the cell. Multi-cell entities (buildings) use foundation-aware positioning. Editor stamps SHALL be detached so they do not register occupancy in the live world.

#### Scenario: Place single-cell entity
- **WHEN** user clicks cell (5, 3) with an infantry entity selected
- **THEN** entity is created at cell center (5, 3)

#### Scenario: Place multi-cell building
- **WHEN** user clicks cell (5, 3) with a 2×2 building selected
- **THEN** building is positioned via `_cell_origin_world_pos()` to account for foundation footprint

#### Scenario: Editor stamp does not pollute occupancy
- **WHEN** a building is stamped onto a cell in the editor
- **THEN** no occupancy cells are registered in the live SpatialHash

#### Scenario: Cannot place on occupied cell
- **WHEN** user clicks a cell already occupied by another entity
- **THEN** placement is rejected, no entity is created

#### Scenario: Right-click cancels
- **WHEN** user right-clicks during placement mode
- **THEN** placement mode exits, no entity is placed

### Requirement: Preview ghost
A 50% opacity preview entity SHALL follow the cursor before placement. The preview SHALL be spawned detached and SHALL use `_set_preview_transparency()` to apply alpha to all MeshInstance3D nodes. A detached preview SHALL register no occupancy and join no gameplay groups.

#### Scenario: Preview follows cursor
- **WHEN** placement mode is active
- **THEN** a semi-transparent entity follows the mouse cursor

#### Scenario: Preview registers nothing
- **WHEN** a building preview is active
- **THEN** its footprint is not registered in SpatialHash

#### Scenario: Preview hidden during height painting
- **WHEN** the MapEditor tool is not PLACE_ENTITY
- **THEN** the preview is hidden

#### Scenario: Preview removed on exit
- **WHEN** placement mode exits
- **THEN** the preview node is removed from the scene tree
