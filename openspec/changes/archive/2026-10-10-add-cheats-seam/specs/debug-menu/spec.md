## MODIFIED Requirements

### Requirement: Cheat toggles

The system SHALL provide 5 independent cheat toggles in the Cheats section: No prerequisites, No build time, No cost, Place anywhere, Force radar online. Each toggle SHALL persist its state across panel open/close cycles. Cheat flags are stored on the shared `Cheats` value, which the debug panel writes and other systems read directly by identifier — the panel holds no cheat state and consumers do not read it via group reference. The Force radar online toggle SHALL set `RadarSystem.force_online` (the single source of truth for the override), and resetting it SHALL restore normal radar availability.

#### Scenario: No prerequisites toggle
- **WHEN** the "No prerequisites" toggle is enabled
- **THEN** PrerequisiteSystem.can_build() returns true for all entities, bypassing both prerequisite checks and build_limit checks
- **AND** the Sidebar build menu refreshes to show all entities

#### Scenario: No build time toggle
- **WHEN** the "No build time" toggle is enabled
- **THEN** entity build_time is treated as 0, causing ProductionManager to complete production immediately

#### Scenario: No cost toggle
- **WHEN** the "No cost" toggle is enabled
- **THEN** EconomyManager.deduct() is a no-op (returns true without deducting credits)

#### Scenario: Place anywhere toggle
- **WHEN** the "Place anywhere" toggle is enabled
- **THEN** BuildingManager.can_place() returns true for any cell (skips foundation, terrain, and bib checks)
- **AND** EntityPlacer arms the free-placement session for any entity type clicked in the build menu

#### Scenario: Non-building entity placement
- **WHEN** "Place anywhere" is enabled and user clicks a unit/infantry cameo in the build menu
- **THEN** the unit enters placement mode with a preview ghost via EntityPlacer, and clicking a non-blocked ground cell spawns the unit

#### Scenario: Force radar online toggle
- **WHEN** the "Force radar online" toggle is enabled while the local player owns no radar structure
- **THEN** `RadarSystem.force_online` becomes true and the gameplay minimap renders live instead of the offline placeholder

#### Scenario: Force radar toggle reset
- **WHEN** the scene changes (new map loaded)
- **THEN** the "Force radar online" toggle is unchecked and `RadarSystem.force_online` is false

#### Scenario: Cheat reset on scene change
- **WHEN** the scene changes (new map loaded)
- **THEN** all cheat toggles reset to off and debug place mode is exited
