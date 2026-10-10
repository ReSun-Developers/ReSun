# Spec Delta

## ADDED Requirements

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

## MODIFIED Requirements

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
