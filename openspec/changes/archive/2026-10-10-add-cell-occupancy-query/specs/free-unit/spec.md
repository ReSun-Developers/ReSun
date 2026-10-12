# Spec Delta

## MODIFIED Requirements

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
