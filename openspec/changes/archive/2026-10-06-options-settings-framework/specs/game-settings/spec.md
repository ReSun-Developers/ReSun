# Spec Delta

## Purpose

Defines per-game gameplay and interface toggles that each title (Tiberian Sun, Firestorm, Red Alert 2, Yuri's Revenge) can store independently while sharing the global graphics configuration, applied on game switch and persisted per game id.

## ADDED Requirements

### Requirement: Per-game settings registry
The system SHALL expose a registry of gameplay/interface toggles that are stored independently for each game id. Each toggle SHALL have an id, a default value, and a description, defined in one place.

#### Scenario: Toggle is enumerable
- **WHEN** the game-settings registry is requested
- **THEN** it lists each toggle with its id, default, and description

#### Scenario: Toggles are independent per game
- **WHEN** a toggle is changed while game `ts` is active and then the active game becomes `ra2`
- **THEN** `ra2` reports its own stored value for that toggle, unaffected by the `ts` change

### Requirement: Game settings persist per game id
The system SHALL persist each game's toggles to a section namespaced by the game id in the user-config file, and SHALL load the active game's values when that game becomes active. Writing one game's toggles SHALL NOT disturb another game's toggles or any other settings section.

#### Scenario: Value survives a restart
- **WHEN** a toggle is changed for the active game and the game restarts
- **THEN** the toggle reports the stored value for that game

#### Scenario: Other games untouched
- **WHEN** a toggle is changed for game `ts`
- **THEN** the stored toggles for game `ra2` are unchanged

### Requirement: Game settings apply on game switch
When the active game changes, the system SHALL apply that game's stored toggles, so consumers observe the correct value for the newly active game.

#### Scenario: Consumer reflects the switch
- **WHEN** the active game changes to a game whose stored toggle differs from the previous game
- **THEN** the consumer of that toggle observes the new game's value

#### Scenario: Unknown game falls back to defaults
- **WHEN** a game with no stored settings section becomes active
- **THEN** every toggle uses its registry default

### Requirement: Move-target-line toggle
The game-settings registry SHALL include a `move_target_line` toggle (default on) that gates move-target line rendering only. Rally lines SHALL NOT be affected by this toggle.

#### Scenario: Toggle off suppresses move-target lines
- **WHEN** `move_target_line` is off and a unit is selected with an active move order
- **THEN** no move-target line is registered or rendered for that unit

#### Scenario: Toggle on renders move-target lines
- **WHEN** `move_target_line` is on and a unit is selected with an active move order
- **THEN** the move-target line is rendered as before

#### Scenario: Rally lines unaffected
- **WHEN** `move_target_line` is off and a selected building has a rally point
- **THEN** the rally line is still drawn
