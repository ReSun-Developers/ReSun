# free-unit Specification

## Purpose

FreeUnitComponent spawns a configured free unit (such as a refinery's harvester) in a free cell
adjacent to its parent when the parent enters the world.

## Requirements

### Requirement: FreeUnitComponent spawns free unit on placement
FreeUnitComponent SHALL spawn a free unit entity adjacent to its parent when the parent enters the scene tree, then remove itself.

#### Scenario: Spawn on real placement
- **WHEN** a building with FreeUnitComponent and `free_unit_id = "HARV"` is placed into the scene (not a preview ghost)
- **THEN** a "HARV" entity is created in an adjacent free cell, and the component queues itself for removal

#### Scenario: Skip on ghost preview
- **WHEN** the parent entity has `_preview` meta set to `true`
- **THEN** FreeUnitComponent does NOT spawn a free unit

#### Scenario: Skip in editor
- **WHEN** `Engine.is_editor_hint()` is true
- **THEN** FreeUnitComponent does NOT spawn a free unit

### Requirement: Adjacent free cell search

FreeUnitComponent SHALL find an unoccupied cell adjacent to the parent's foundation by
evaluating each candidate through the shared build-intent occupancy query
(`SpatialHash.get_cell_occupancy` plus `is_cell_free_for_build`), extended so a candidate is
also refused when it is reserved for an inbound unit. Candidate cells SHALL be refused when they
hold a building, bib, or resource cell, any unit body (moving or idle), a reservation, or
non-buildable terrain. FreeUnitComponent SHALL NOT read `SpatialHash` private registries
directly.

#### Scenario: Spiral search
- **WHEN** searching for an adjacent cell
- **THEN** cells are checked in expanding radius (1–5 cells) from the building origin, skipping building cells, bib cells, resource cells, unit-occupied cells, blocked cells, and reserved cells

#### Scenario: Bib and resource cells are skipped
- **WHEN** a candidate cell holds a bib or a resource entity
- **THEN** it is not selected as the free-unit spawn cell

#### Scenario: Terrain type filter
- **WHEN** checking a candidate cell
- **THEN** only cells with terrain type "" or "clear" are considered (not water, cliffs, etc.)

#### Scenario: Search radius
- **WHEN** no cell is free within the search radius (~5 cells)
- **THEN** the component retries every 2 seconds until a cell becomes available

### Requirement: Refinery spawns harvester
The gdi_refinery EntityData SHALL have `factory = "HarvesterType"` and `free_unit = "HARV"`.

#### Scenario: Refinery placement
- **WHEN** a GDI Refinery is placed on the map
- **THEN** a harvester entity ("HARV") is spawned in an adjacent free cell

#### Scenario: Spawned harvester auto-harvests
- **WHEN** a free harvester is spawned by FreeUnitComponent
- **THEN** it automatically finds the nearest resource node via `HarvestComponent._find_nearest_resource()` and calls `set_target_node()` to begin harvesting
