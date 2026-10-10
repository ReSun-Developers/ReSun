# Spec Delta

## MODIFIED Requirements

### Requirement: MapLoader reads JSON v3 with entities
`MapLoader.gd` SHALL read a JSON map file and restore both terrain data and entities. Each entity SHALL enter the world through the `EntityFactory` spawn seam, with the player id assigned before insertion, so loaded buildings register identically to runtime placements. When loading into the map editor, entities SHALL be spawned detached so they register no live occupancy.

#### Scenario: Load terrain
- **WHEN** MapLoader reads a JSON file with `"vertices"` and `"cells"`
- **THEN** it calls `TerrainSystem.import_from_json()` with those values

#### Scenario: Load entities
- **WHEN** MapLoader reads a JSON file with an `"entities"` array
- **THEN** it spawns each entry through the `EntityFactory` seam with the entry's overrides and player, and the entity is added to the scene

#### Scenario: Loaded buildings register
- **WHEN** a building entry is loaded into a gameplay scene for a given owner
- **THEN** its footprint is registered in SpatialHash and it is registered for that owner's prerequisites, identically to a runtime placement

#### Scenario: Editor load detaches
- **WHEN** MapLoader loads a map into the map editor
- **THEN** each entity is spawned detached and registers no live occupancy

#### Scenario: Empty entities array
- **WHEN** the `"entities"` array is empty or missing
- **THEN** MapLoader skips entity creation (no error)
