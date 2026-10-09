## MODIFIED Requirements

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
