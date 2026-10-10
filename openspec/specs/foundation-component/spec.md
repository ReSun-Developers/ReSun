## Purpose

`FoundationComponent` is the canonical source for a building footprint's geometry: its cell set, buildability predicates, and world-space queries derived from the foundation rectangle.
## Requirements
### Requirement: Canonical footprint cell queries
`FoundationComponent` SHALL be the canonical source for a building footprint's cell set. It SHALL expose `get_foundation_cells(origin_cell)` returning every cell in the `foundation` rectangle, and `get_occupied_cells(origin_cell)` returning the foundation cells minus `bib_cells` (the cells that are registered as solid building cells in `SpatialHash`).

#### Scenario: Foundation cells for a 2×2 footprint
- **WHEN** `get_foundation_cells(Vector2i(5, 3))` is called on a 2×2 foundation
- **THEN** it returns `(5,3), (6,3), (5,4), (6,4)`

#### Scenario: Occupied cells exclude bib cells
- **WHEN** a footprint has `bib_cells` containing offset `(0, 1)` and `get_occupied_cells(origin)` is called
- **THEN** the returned cells include every foundation cell EXCEPT `origin + (0, 1)`

#### Scenario: Occupied cells equal foundation cells when no bib
- **WHEN** `bib_cells` is empty
- **THEN** `get_occupied_cells(origin)` equals `get_foundation_cells(origin)`

### Requirement: Single-cell buildability predicate
`FoundationComponent` SHALL expose a static `is_cell_buildable(cell)` returning `false` when the cell is occupied by a building cell, a bib cell, a blocked cell, an entity with a `MovementController`, or a resource, or when its terrain type is neither `""` nor `"clear"`; otherwise `true`. This predicate SHALL be the single implementation reused by placement validation and preview rendering.

#### Scenario: Free clear cell is buildable
- **WHEN** a cell has no buildings, entities, or resources and its terrain type is `"clear"`
- **THEN** `is_cell_buildable(cell)` returns `true`

#### Scenario: Building cell is not buildable
- **WHEN** a cell is registered as a building cell in `SpatialHash`
- **THEN** `is_cell_buildable(cell)` returns `false`

### Requirement: Per-footprint buildability
`FoundationComponent` SHALL expose `is_buildable(origin_cell)` returning `true` only when every foundation cell is `is_cell_buildable` AND the terrain height variation across the footprint (max cell height − min cell height) is at most `TerrainSystem.HEIGHT_STEP`.

#### Scenario: Flat, free footprint is buildable
- **WHEN** all foundation cells are buildable and level
- **THEN** `is_buildable(origin)` returns `true`

#### Scenario: One occupied cell blocks the footprint
- **WHEN** any foundation cell is not `is_cell_buildable`
- **THEN** `is_buildable(origin)` returns `false`

#### Scenario: Excessive height variation blocks the footprint
- **WHEN** the max−min cell height across the footprint exceeds `TerrainSystem.HEIGHT_STEP`
- **THEN** `is_buildable(origin)` returns `false`

### Requirement: Nearest world point on foundation footprint
`FoundationComponent` SHALL expose `nearest_world_point(from: Vector3) -> Vector3` returning the world-space point on the foundation footprint rectangle nearest to `from`. The footprint rectangle SHALL be the axis-aligned XZ rectangle centered on the owning entity's `global_position` with half-extents `foundation * CellUtil.CELL_SIZE * 0.5`; the returned point SHALL be the per-axis clamp of `from` onto that rectangle, with the Y component taken from the entity. When `from` projects inside the rectangle the method SHALL return `from` itself (clamped), so an attacker standing on or inside the footprint reports zero distance. The method SHALL be O(1) and SHALL NOT iterate foundation cells.

#### Scenario: Nearest point outside a face
- **WHEN** `nearest_world_point(from)` is called with `from` directly beyond one face of a 4x4 foundation
- **THEN** it returns the point on that face at `from`'s lateral offset, one half-depth from the center along the normal

#### Scenario: Nearest point outside a corner
- **WHEN** `from` is beyond a corner diagonally
- **THEN** it returns that corner of the footprint rectangle

#### Scenario: Point inside the footprint returns itself
- **WHEN** `from` projects inside the footprint rectangle
- **THEN** it returns `from` clamped to the rectangle (equal to `from`)

#### Scenario: Single-cell footprint
- **WHEN** the foundation is 1x1
- **THEN** the rectangle is the single cell and the nearest point is the clamp onto that cell's square

### Requirement: Occupancy follows world entry and exit

A building's footprint cells SHALL be registered in `SpatialHash` exactly once when the building enters the world and unregistered when it leaves. Registration SHALL be driven by the component's lifecycle (entry and exit), not by individual placement callers, so runtime-placed, map-loaded, and deployed buildings register identically. A detached entity SHALL NOT register. The non-bib foundation cells SHALL be registered as blocked building cells, and the bib cells SHALL be registered as bib cells excluded from blocked.

#### Scenario: Building registers on entry
- **WHEN** a building with a 3x3 foundation enters the world at a cell
- **THEN** all nine foundation cells are registered and block pathfinding

#### Scenario: Bib cells are tracked, not blocked
- **WHEN** a building with bib cells enters the world
- **THEN** its bib cells are registered as bib cells and are not registered as blocked building cells

#### Scenario: Building unregisters on exit
- **WHEN** a registered building leaves the world
- **THEN** its foundation and bib cells are unregistered

#### Scenario: Detached entity does not register
- **WHEN** a detached building enters the scene
- **THEN** it registers no building or bib cells

#### Scenario: Non-building with a StatsComponent does not register
- **WHEN** an entity whose `StatsComponent.entity_type` is not BUILDING enters the world with a FoundationComponent
- **THEN** it registers no building cells

