## Purpose

Manage the player's structure build-mode lifecycle: enter and exit build mode, render and
footprint-snap a placement preview, validate a footprint against map bounds, occupancy, terrain
height, and adjacency, and place, sell, and repair buildings.

## Requirements

### Requirement: BuildingManager manages build mode lifecycle
`BuildingManager` SHALL be an autoload singleton managing build mode entry, preview, placement, selling, and repairing. It emits `build_mode_changed(is_active)`, `building_placed(building, entity_data)`, `building_sold(building, entity_data)`, and `building_repaired(building, entity_data)` signals.

#### Scenario: Enter build mode
- **WHEN** `enter_build_mode(building_type)` is called
- **THEN** `is_build_mode` becomes true, preview appears, `build_mode_changed(true)` emits
- **AND** `_skip_input_frames = 1` prevents the triggering click from placing

#### Scenario: Toggle off same building
- **WHEN** `enter_build_mode(building_type)` is called while already in build mode for the same type
- **THEN** build mode exits

#### Scenario: Exit build mode
- **WHEN** `exit_build_mode()` is called or right-click/Escape is pressed
- **THEN** `is_build_mode` becomes false, preview is freed, `build_mode_changed(false)` emits

### Requirement: Placement validation

`can_place(building_type, origin_cell)` SHALL check every foundation cell for map bounds and play-area bounds, SHALL delegate cell availability and terrain height variation to `FoundationComponent.footprint_buildable(building_type.foundation, origin_cell)`, and SHALL enforce the adjacency requirement `building_type.adjacent`. The adjacency requirement SHALL measure the number of empty cells between the new footprint and existing friendly footprints (Chebyshev, nearest cells): a building with `adjacent = N > 0` SHALL be placeable when and only when some friendly occupied cell lies within Chebyshev distance `N + 1` of some footprint cell (gap `<= N`). This diverges from Tiberian Sun, where `Adjacent = 0` means must-touch and negative values disable placement — in this remake `adjacent <= 0` SHALL mean no requirement (relied on by construction yard placement). Under debug place-anywhere mode only the map-bounds check applies.

#### Scenario: Valid placement
- **WHEN** all foundation cells are free, in bounds, height variation is within limit, and any adjacency requirement is satisfied
- **THEN** `can_place()` returns true

#### Scenario: Cell occupied by building
- **WHEN** any foundation cell overlaps an existing building's footprint
- **THEN** `can_place()` returns false

#### Scenario: Cell has resource
- **WHEN** any foundation cell contains a resource entity
- **THEN** `can_place()` returns false

#### Scenario: Height variation too steep
- **WHEN** max height - min height across foundation cells exceeds `TerrainSystem.HEIGHT_STEP`
- **THEN** `can_place()` returns false

#### Scenario: Adjacency gap exceeds requirement
- **WHEN** `building_type.adjacent = N > 0` and no friendly building has an occupied cell within Chebyshev distance `N + 1` of any footprint cell (every friendly footprint is more than `N` empty cells away)
- **THEN** `can_place()` returns false

#### Scenario: Adjacency gap within requirement
- **WHEN** `building_type.adjacent = N > 0` and a friendly building has an occupied cell at Chebyshev distance `d` from some footprint cell with `d - 1 <= N` (touching, `d = 1`, always qualifies)
- **THEN** the adjacency check passes

#### Scenario: Adjacent = 2 boundary
- **WHEN** `building_type.adjacent = 2` and the nearest friendly occupied cell is exactly 3 cells (2-cell gap) from the nearest footprint cell
- **THEN** the adjacency check passes
- **WHEN** the nearest friendly occupied cell is exactly 4 cells (3-cell gap) away
- **THEN** the adjacency check fails

#### Scenario: No adjacency requirement
- **WHEN** `building_type.adjacent <= 0`
- **THEN** the adjacency check always passes

#### Scenario: Debug place-anywhere mode
- **WHEN** `Cheats.place_anywhere == true`
- **THEN** only bounds check is enforced, cell/height/adjacency checks are skipped

### Requirement: Uniform building registration

Every building that enters the world — runtime-placed, map-loaded, or deployed — SHALL be registered once into the building registry, into `PrerequisiteSystem` counts for its owner, and to its `HealthComponent.health_zero` death cleanup. The registry entry SHALL store the bib-excluded occupied cells (`FoundationComponent.occupied_cells`). Registration SHALL be scoped to the building's own owning player (read from its `StatsComponent`), never the local player, and SHALL be triggered by the spawn seam rather than by each placement caller, so map-loaded and deployed buildings register identically to runtime placements.

#### Scenario: Runtime building registers
- **WHEN** a building is placed through build mode
- **THEN** it is added to the building registry, counted for its owner's prerequisites, and wired to death cleanup

#### Scenario: Map-loaded building registers
- **WHEN** a building is loaded from a map for a given owner
- **THEN** it is added to the building registry and counted for that owner's prerequisites, exactly as a runtime placement

#### Scenario: Deployed building registers
- **WHEN** a unit deploys into a building
- **THEN** the deployed building is registered once and wired to death cleanup, with no duplicate foundation registration

#### Scenario: Registry stores bib-excluded cells
- **WHEN** a building with bib cells is registered
- **THEN** its registry entry lists the foundation cells excluding the bib cells

#### Scenario: Prerequisites are owner-scoped
- **WHEN** an enemy building is registered
- **THEN** its prerequisite count is attributed to the enemy owner, not the local player

#### Scenario: Death unregisters
- **WHEN** a registered building reaches zero health
- **THEN** it is removed from the building registry and its owner's prerequisite counts

### Requirement: Building placement
`place_building(building_type, origin_cell)` SHALL validate placement, deduct cost (unless the entity is production-paid), enter the entity through the spawn seam, flatten terrain under the footprint via `TerrainSystem.flatten_footprint`, and emit `building_placed`. Footprint occupancy, building-registry entry, prerequisite counts, and death wiring SHALL be established by the spawn seam and the building's own registration lifecycle, not by `place_building`, so map-loaded and deployed buildings receive the same registration.

#### Scenario: Place building with deduction
- **WHEN** `place_building()` is called for a building not already paid through the production queue
- **THEN** cost is deducted from the player's credits via EconomyManager

#### Scenario: Place building with skip deduction
- **WHEN** the building's ready entry already exists in the production queue
- **THEN** cost is NOT deducted again

#### Scenario: Place building registers cells
- **WHEN** a 2×2 building is placed at cell (5, 3)
- **THEN** cells (5,3), (6,3), (5,4), (6,4) are registered in SpatialHash

#### Scenario: Place building registers bib cells
- **WHEN** a building with bib cells is placed
- **THEN** bib cells are registered separately in SpatialHash and are excluded from the occupied building cells

#### Scenario: Place building flattens terrain
- **WHEN** a building is placed over a footprint with a one-step height variation
- **THEN** the footprint region is levelled to its maximum height

#### Scenario: Place building resumes production
- **WHEN** a building from the production queue is placed
- **THEN** `ProductionManager.clear_waiting_for_placement()` is called

#### Scenario: Placement does not register twice
- **WHEN** a building is placed through build mode
- **THEN** its footprint is registered exactly once, by its entry into the world, and it appears in the building registry exactly once

### Requirement: Cell availability check
`_is_cell_free(cell)` SHALL delegate to `FoundationComponent.is_cell_buildable(cell)`, returning false if the cell is a building cell, blocked, has an entity with MovementController, a bib cell, has a resource, or terrain type is not "" or "clear".

#### Scenario: Free cell
- **WHEN** a cell has no buildings, entities, resources, and is "clear" terrain
- **THEN** `_is_cell_free()` returns true

#### Scenario: Occupied cell
- **WHEN** a cell has a building footprint
- **THEN** `_is_cell_free()` returns false

### Requirement: Building sell
`sell_building(building_node)` SHALL refund, to the building's owning player, the building's cost multiplied by `refund_percent` from the active `GlobalRules` (default 0.5), credited as free credits with the active resource category; SHALL unregister the building from `PrerequisiteSystem` for that owner and remove its registry entry; SHALL deselect the building; SHALL emit `building_sold`; and SHALL free the node. Occupancy cells SHALL be unregistered by the building's world-exit lifecycle. Selling SHALL be refused unless the acting player owns the building. A pre-placed building owned by a real player SHALL be sellable by that owner.

#### Scenario: Sell building
- **WHEN** `sell_building(building)` is called by its owner on a placed building whose cost is 100, with active rules `refund_percent = 0.5`
- **THEN** 50 credits are added to the owning player's free credits
- **AND** building is removed from game

#### Scenario: Sell building honors tuned refund_percent
- **WHEN** `sell_building(building)` is called by its owner on a placed building whose cost is 100, with active rules `refund_percent = 0.25`
- **THEN** 25 credits are added to the owning player's free credits

#### Scenario: Sell pre-placed building to its owner
- **WHEN** `sell_building(building)` is called on a map-loaded building owned by the acting player, player 2
- **THEN** the refund is credited to player 2, and the building is unregistered from player 2's prerequisites

#### Scenario: Enemy building is not sellable
- **WHEN** the sell order is issued against a building owned by another player
- **THEN** the sale is refused and no credits are exchanged

#### Scenario: Sell building not found
- **WHEN** `sell_building(node)` is called on a node not in the buildings list
- **THEN** returns false

### Requirement: Building repair
`repair_building(building_node)` SHALL heal the building by 8 HP (capped at max health). Returns false if already at full health.

#### Scenario: Repair damaged building
- **WHEN** `repair_building(building)` is called on a building with 80/100 HP
- **THEN** health increases to 88/100

#### Scenario: Repair at full health
- **WHEN** `repair_building(building)` is called on a building at full health
- **THEN** returns false, no change

#### Scenario: Repair capped at max
- **WHEN** `repair_building(building)` is called on a building with 96/100 HP
- **THEN** health increases to 100/100 (capped, not 104)

### Requirement: Building lookup
`get_building_at_cell(cell)` SHALL return the building node occupying the given cell, or null if no building is on that cell. `get_all_buildings()` SHALL return the full list of placed buildings.

#### Scenario: Get building at occupied cell
- **WHEN** a building occupies cells (5,3) and (6,3)
- **THEN** `get_building_at_cell((5,3))` returns that building's node

#### Scenario: Get building at empty cell
- **WHEN** no building is at cell (0, 0)
- **THEN** `get_building_at_cell((0,0))` returns null

### Requirement: Building type catalog
On startup, BuildingManager SHALL load all buildable EntityData resources of type BUILDING into `building_types`. Only entities with `buildable == true` are included.

#### Scenario: Load building types
- **WHEN** `_ready()` runs
- **THEN** `building_types` contains all EntityData with `entity_type == BUILDING` and `buildable == true`
