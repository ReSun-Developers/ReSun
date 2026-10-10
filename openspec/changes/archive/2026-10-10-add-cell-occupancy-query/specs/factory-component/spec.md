# Spec Delta

## MODIFIED Requirements

### Requirement: FactoryComponent orchestrates exit process

FactoryComponent SHALL have `on_unit_produced(entity_data: EntityData, player_id: int)` method.
When called, FactoryComponent SHALL:

1. Create the unit via EntityFactory
2. If ExitComponent exists, call `ExitComponent.on_unit_produced(unit)`
3. Else, find the nearest cell the shared unit-exit occupancy intent
   (`SpatialHash.is_cell_free_for_unit_exit`) reports free, and spawn the unit there
4. Emit `exit_in_progress` signal

The nearest-free-cell search SHALL NOT use a private occupancy predicate; it SHALL share the
exit intent with `ExitComponent.on_unit_produced` and `ProductionManager`'s fallback spawner, so
all spawn paths agree on what blocks a cell. The existing fallback when no cell is free (the
building's own cell) is unchanged by this change.

#### Scenario: Unit exits via ExitComponent
- **WHEN** FactoryComponent.on_unit_produced() is called on building with ExitComponent
- **THEN** FactoryComponent SHALL create the unit
- **THEN** FactoryComponent SHALL call ExitComponent.on_unit_produced(unit)
- **THEN** FactoryComponent SHALL emit `exit_in_progress`

#### Scenario: Unit exits without ExitComponent
- **WHEN** FactoryComponent.on_unit_produced() is called on building without ExitComponent
- **THEN** FactoryComponent SHALL create the unit
- **THEN** FactoryComponent SHALL find the nearest cell the shared exit intent reports free
- **THEN** FactoryComponent SHALL spawn the unit at that cell
- **THEN** FactoryComponent SHALL emit `exit_in_progress`
- **THEN** a warning SHALL be logged

#### Scenario: No private availability predicate
- **WHEN** the FactoryComponent exit path is inspected
- **THEN** it does not define its own cell-availability predicate and delegates to the shared exit intent
