# Spec Delta

## MODIFIED Requirements

### Requirement: Mission map loading

Starting a mission SHALL load the mission's `map_path` JSON into the match's
World root under `MainScene/Gameplay` using the existing `MapLoader`, after the
mission's overrides are applied. A missing or unreadable map file SHALL log an
error and leave the World root without map entities.

#### Scenario: Mission map loads entities

- **WHEN** a mission whose map JSON contains entities is started
- **THEN** those entities are instantiated under the match's World root and
  `GameContext.current_mission` remains the started mission

#### Scenario: Missing map reported

- **WHEN** a mission's `map_path` does not exist
- **THEN** an error is logged, the World root is left without map entities, and no
  map entities are created

### Requirement: Mission start occludes menu overlays

Starting a mission SHALL switch the UI session shell to `Match` mode so the
running match is the only visible surface: the main menu and the boot screen
SHALL no longer be shown, and the in-game HUD surface SHALL be mounted.

#### Scenario: Boot screen hidden on mission start

- **WHEN** a mission starts with the boot screen visible
- **THEN** session mode is `Match`, so neither the boot screen nor the main menu
  is shown, and the in-game HUD surface is mounted

#### Scenario: Main menu hidden on mission start

- **WHEN** a mission starts with the main menu visible
- **THEN** session mode is `Match`, so neither the main menu nor the boot screen
  is shown, and the in-game HUD surface is mounted
