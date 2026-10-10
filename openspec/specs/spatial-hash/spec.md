# spatial-hash Specification

## Purpose

`SpatialHash` is the autoload spatial grid rebuilt each physics frame, providing occupancy, blocked cells, cell reservation, building/bib/resource cell tracking, and crush queries.

## Requirements

### Requirement: SpatialHash rebuilt every physics frame
`SpatialHash` SHALL be an autoload singleton whose grid is maintained incrementally rather than fully rebuilt every physics frame. It SHALL cache a pooled entry per entity (root Node3D, MovementController/StatsComponent references, entity type, player ID, cell, movement state) and reconcile those entries each `_physics_process()` frame, moving an entry to a new cell or flipping its blocked/shared contribution only when the entity's cell or state actually changed. A full rebuild SHALL occur when entities or ice enter/leave the "entities"/"ice" groups or on explicit refresh. Query results SHALL match what a full rebuild would have produced within the same physics tick.

#### Scenario: Grid populated on rebuild
- **WHEN** a full rebuild runs after an entity is added to the "entities" group
- **THEN** `_grid` is populated with all entities in the "entities" group

#### Scenario: Entity without Node3D root
- **WHEN** an entity in the "entities" group is not a Node3D and has no Node3D parent
- **THEN** it is skipped (not added to grid)

#### Scenario: Idle unit does not trigger a full rebuild
- **WHEN** an idle unit remains in the same cell across physics frames
- **THEN** no full rebuild occurs and `_grid` keeps its existing entries

### Requirement: SpatialHash cell-change updates
When an entity's cell changes, `SpatialHash` SHALL move that entity's entry from its previous cell key to the new one without rebuilding the grid. When an entity's movement state changes, `SpatialHash` SHALL add or remove the entity's blocked/shared-cell contribution accordingly. Within the same physics tick, the resulting `_grid`, `_blocked_cells`, and `_shared_cell_counts` SHALL be identical to what a full rebuild would have produced.

#### Scenario: Moving unit crosses a cell boundary
- **WHEN** a unit moves from cell (5, 3) to cell (5, 4)
- **THEN** its entry is removed from `_grid[(5,3)]` and appended to `_grid[(5,4)]`

#### Scenario: Unit enters idle state
- **WHEN** a unit transitions from MOVING to IDLE
- **THEN** its cell's contribution is updated: `_blocked_cells` gains the cell if `shares_cell()` is false, or `_shared_cell_counts` increments if true

#### Scenario: Unit leaves idle state
- **WHEN** a unit transitions from IDLE to MOVING
- **THEN** its blocked/shared contribution is removed from the previous cell

#### Scenario: Entry ordering preserved
- **WHEN** an entry moves to a cell that already has entries
- **THEN** it is appended after existing entries (per-cell order preserved)

### Requirement: SpatialHash entry references are cached
`SpatialHash` SHALL cache each entity's MovementController and StatsComponent references in its pooled entry at rebuild time and SHALL NOT re-resolve child nodes during per-frame reconciliation.

#### Scenario: No per-frame node lookups
- **WHEN** the `_physics_process()` reconcile runs over N entities
- **THEN** no `get_node`/`get_node_or_null` child lookups are performed for those N entities

### Requirement: Blocked cells from idle units
During rebuild, SpatialHash SHALL populate `_blocked_cells` with cells containing IDLE units whose MovementController `shares_cell()` returns false. Sharing cells are tracked separately in `_shared_cell_counts`.

#### Scenario: Idle vehicle blocks cell
- **WHEN** a vehicle with `shares_cell() == false` is IDLE at cell (5, 3)
- **THEN** `_blocked_cells` contains key for (5, 3)

#### Scenario: Idle sharer counted, not blocked
- **WHEN** a unit with `shares_cell() == true` is IDLE at cell (5, 3)
- **THEN** `_shared_cell_counts[(5,3)]` increments, `_blocked_cells` does NOT contain (5, 3)

#### Scenario: Moving units not counted
- **WHEN** a unit is in MOVING or ROTATING state
- **THEN** it is neither blocked nor counted in shared cells

### Requirement: Blocked cell merging
`get_blocked_cells()` SHALL return a merged dictionary of idle-unit blocked cells AND building footprint cells.

#### Scenario: Building cells included
- **WHEN** building cells are registered via `register_building_cells()`
- **THEN** `get_blocked_cells()` includes both idle-unit cells and building cells

### Requirement: Crusher-aware blocking
`get_crusher_blocking_cells(player_id)` SHALL return cells that a crusher vehicle cannot crush through: cells containing friendly infantry, non-crushable infantry, or zero infantry.

#### Scenario: Enemy crushable infantry not blocking
- **WHEN** a cell contains only enemy infantry with `crushable = true`
- **THEN** the cell is NOT in crusher-blocking cells (vehicle can crush through)

#### Scenario: Friendly infantry blocking
- **WHEN** a cell contains infantry owned by the same player
- **THEN** the cell IS in crusher-blocking cells

#### Scenario: Non-crushable infantry blocking
- **WHEN** a cell contains enemy infantry with `crushable = false`
- **THEN** the cell IS in crusher-blocking cells

### Requirement: Crushable enemy queries
`get_crushable_enemies_on_cell(cell, player_id)` SHALL return an array of enemy infantry nodes on the given cell that are crushable.

#### Scenario: Find crushable enemies
- **WHEN** cell (5, 3) contains 2 enemy infantry with `crushable = true`
- **THEN** `get_crushable_enemies_on_cell((5, 3), player_id)` returns both nodes

#### Scenario: No crushable enemies
- **WHEN** cell (5, 3) contains only friendly infantry
- **THEN** `get_crushable_enemies_on_cell((5, 3), player_id)` returns empty array

### Requirement: Cell reservation system
SpatialHash SHALL provide a reservation system for cells. `reserve_cell(cell)` returns true if the cell is free (not blocked, not building, not already reserved). `release_cell(cell)` removes the reservation. `force_reserve(cell)` reserves regardless of occupancy.

#### Scenario: Reserve free cell
- **WHEN** `reserve_cell(cell)` is called on an unoccupied cell
- **THEN** returns true and cell is reserved

#### Scenario: Reserve occupied cell fails
- **WHEN** `reserve_cell(cell)` is called on a cell that is blocked, a building cell, or already reserved
- **THEN** returns false

#### Scenario: Force reserve bypasses checks
- **WHEN** `force_reserve(cell)` is called
- **THEN** cell is reserved regardless of current occupancy

#### Scenario: Release cell
- **WHEN** `release_cell(cell)` is called on a reserved cell
- **THEN** the reservation is removed

### Requirement: Building cell registration
Buildings SHALL register their footprint cells via `register_building_cells(cells)` and unregister via `unregister_building_cells(cells)`. These cells appear in `get_blocked_cells()`.

#### Scenario: Register building cells
- **WHEN** a building is placed at cells [(2,3), (3,3), (2,4), (3,4)]
- **THEN** `register_building_cells()` adds all 4 cells to `_building_cells`

#### Scenario: Unregister building cells
- **WHEN** a building is destroyed
- **THEN** `unregister_building_cells()` removes its cells from `_building_cells`

### Requirement: Bib cell tracking
`register_bib_cells(cells)` SHALL track foundation extension cells (bibs). `is_bib_cell(cell)` returns true for bib cells.

#### Scenario: Bib cell registered
- **WHEN** `register_bib_cells([(5, 5)])` is called
- **THEN** `is_bib_cell((5, 5))` returns true

### Requirement: Resource cell tracking
`register_resource_cell(cell)` and `unregister_resource_cell(cell)` SHALL track cells containing resource entities. `has_resource_cell(cell)` queries this tracking.

#### Scenario: Resource cell registered
- **WHEN** a tiberium crystal is placed at cell (3, 7)
- **THEN** `register_resource_cell((3, 7))` and `has_resource_cell((3, 7))` returns true

#### Scenario: Resource cell unregistered
- **WHEN** tiberium at cell (3, 7) is depleted
- **THEN** `unregister_resource_cell((3, 7))` and `has_resource_cell((3, 7))` returns false

### Requirement: Entity queries
`get_entries(cell)` SHALL return the array of entity entries at a cell. `all_entries()` SHALL return all entries across all cells. `is_any_entity_on_cell(cell)` SHALL return true if any entity with a MovementController exists on the cell.

#### Scenario: Get entries at cell
- **WHEN** 2 units are at cell (5, 3)
- **THEN** `get_entries((5, 3))` returns an array of 2 entries

#### Scenario: Empty cell
- **WHEN** no entities are at cell (0, 0)
- **THEN** `get_entries((0, 0))` returns empty array

#### Scenario: Any entity check
- **WHEN** a vehicle is on cell (5, 3)
- **THEN** `is_any_entity_on_cell((5, 3))` returns true

### Requirement: Shared cell capacity
Each cell SHALL support up to `CellSubPositions.get_slot_count()` idle sharers. `is_cell_full_for_shared(cell)` SHALL return true when count >= the capacity.

#### Scenario: Cell below capacity not full
- **WHEN** `_shared_cell_counts[cell]` is one less than `CellSubPositions.get_slot_count()`
- **THEN** `is_cell_full_for_shared(cell)` returns false

#### Scenario: Cell at capacity is full
- **WHEN** `_shared_cell_counts[cell]` equals `CellSubPositions.get_slot_count()`
- **THEN** `is_cell_full_for_shared(cell)` returns true

### Requirement: FoundationComponent registers only non-bib cells as building cells
`FoundationComponent._ready()` SHALL register the entity's foundation cells as building cells EXCLUDING its bib cells. Bib cells SHALL be registered only via `register_bib_cells()` and SHALL NOT appear in `_building_cells` (and therefore SHALL NOT be returned by `get_blocked_cells()` as building-blocked). This SHALL match the exclusion already performed by `BuildingManager.place_building`.

#### Scenario: Map-loaded refinery dock cell is not building-blocked
- **WHEN** a refinery with bib cells is added to the tree and its FoundationComponent registers
- **THEN** its bib cells (including the dock pad) SHALL be absent from `_building_cells`
- **AND** present in `_bib_cells` (via `is_bib_cell`)

#### Scenario: Non-bib foundation cells remain blocked
- **WHEN** a multi-cell building registers its foundation
- **THEN** all foundation cells that are not bib cells SHALL be present in `_building_cells`

#### Scenario: Unregistration matches registration
- **WHEN** the building leaves the tree
- **THEN** the same non-bib foundation cells SHALL be unregistered from `_building_cells`
- **AND** the bib cells SHALL be unregistered from `_bib_cells`

#### Scenario: Non-buildings still skip registration
- **WHEN** the entity is not a BUILDING (vehicle/infantry)
- **THEN** `FoundationComponent._ready` SHALL register no cells

### Requirement: Level-aware occupancy and blocking
`SpatialHash` occupancy and blocking queries SHALL be scoped by surface level. Each entity entry SHALL carry the level it occupies; `get_blocked_cells(level)`, `get_entries(cell, level)`, and `is_cell_blocked(cell, level)` SHALL return results for that level only, with `level` defaulting to `0`. `is_any_entity_on_cell(cell, level = -1)` SHALL accept `-1` to mean any level (legacy probes) and an exact level otherwise. A unit on a deck SHALL NOT block or count toward the ground level beneath it, and a unit on the ground SHALL NOT block the deck. The per-level results SHALL match what a full rebuild would have produced.

#### Scenario: Deck unit does not block ground
- **WHEN** an idle unit sits on a high deck over a cell and the ground level is queried
- **THEN** the ground cell is not blocked by that unit

#### Scenario: Ground unit does not block deck
- **WHEN** an idle unit sits on the ground under a high deck and the deck level is queried
- **THEN** the deck cell is not blocked by that unit

#### Scenario: Default level is ground
- **WHEN** `get_blocked_cells()` / `get_entries(cell)` are called without a level
- **THEN** they return level-0 results, matching pre-change behavior

#### Scenario: Same-level blocking preserved
- **WHEN** an idle non-sharing vehicle sits at a cell on level 0
- **THEN** level 0 reports that cell blocked, as before

### Requirement: Live bridge cell registry is level-aware
`SpatialHash` SHALL maintain a live registry of bridge cells, rebuilt with the existing membership scan alongside the ice registry. Bridge entities SHALL be discovered by their `"bridge"` group membership and keyed by `(cell, level)`, and the registry SHALL expose whether a cell has a bridge at a level (`has_bridge_on_cell(cell, level)`) and that surface's metadata (bridge kind, end flag, piece identifier, walkable surface height). Multiple deck levels over the same cell SHALL coexist as separate entries. Removing or destroying a bridge entity SHALL remove its `(cell, level)` entry on the next rebuild.

#### Scenario: Bridge cell registered at its level
- **WHEN** a bridge entity occupies a cell at level `L` and the registry rebuilds
- **THEN** `has_bridge_on_cell(cell, L)` returns true

#### Scenario: Stacked decks are separate entries
- **WHEN** two decks occupy the same cell at different levels
- **THEN** the registry reports a surface for each level independently

#### Scenario: Removed bridge leaves the registry
- **WHEN** a bridge entity is removed and the registry rebuilds
- **THEN** `has_bridge_on_cell` for its former `(cell, level)` returns false

#### Scenario: Metadata exposed
- **WHEN** a bridge cell is registered
- **THEN** its kind, end flag, piece identifier, and surface height are queryable from the registry

#### Scenario: Rebuild empty
- **WHEN** no bridge entities exist
- **THEN** the registry reports no bridge cells at any level

### Requirement: Level-aware cell reservation
`SpatialHash` cell reservation SHALL be scoped by level: `reserve_cell(cell, level)`, `release_cell(cell, level)`, and `force_reserve(cell, level)` SHALL operate on the `(cell, level)` reservation, with `level` defaulting to 0. A reservation on a deck SHALL NOT block a reservation on the ground beneath it, and existing callers that pass no level SHALL reserve level 0 exactly as today.

#### Scenario: Deck reservation independent of ground
- **WHEN** the ground level of a cell is reserved
- **THEN** the deck level of the same cell can still be reserved

#### Scenario: Default level reservation
- **WHEN** `reserve_cell(cell)` is called without a level
- **THEN** it reserves the level-0 cell, matching pre-change behavior

#### Scenario: Same-level reservation still fails when taken
- **WHEN** a `(cell, level)` is already reserved and reserved again
- **THEN** the second reservation fails

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
