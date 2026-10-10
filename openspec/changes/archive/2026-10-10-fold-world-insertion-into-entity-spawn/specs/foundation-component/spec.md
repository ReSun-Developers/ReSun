# Spec Delta

## ADDED Requirements

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
