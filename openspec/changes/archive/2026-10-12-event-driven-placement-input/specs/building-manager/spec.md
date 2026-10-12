# Spec Delta

## MODIFIED Requirements

### Requirement: BuildingManager manages build mode lifecycle
`BuildingManager` SHALL be an autoload singleton managing build mode entry, preview, placement, selling, and repairing. It emits `build_mode_changed(is_active, player_id)`, `building_placed(building, entity_data)`, `building_sold(building, entity_data)`, and `building_repaired(building, entity_data)` signals.

#### Scenario: Enter build mode
- **WHEN** `enter_build_mode(building_type)` is called
- **THEN** `is_build_mode` becomes true, preview appears, `build_mode_changed(true)` emits
- **AND** the click that triggered entry (a cameo button press, consumed as GUI input) SHALL NOT also place a building

#### Scenario: Toggle off same building
- **WHEN** `enter_build_mode(building_type)` is called while already in build mode for the same type
- **THEN** build mode exits

#### Scenario: Exit build mode
- **WHEN** `exit_build_mode()` is called or right-click/Escape is pressed
- **THEN** `is_build_mode` becomes false, preview is freed, `build_mode_changed(false)` emits

## ADDED Requirements

### Requirement: Build mode input handling
While `is_build_mode` is active, `BuildingManager` SHALL attempt placement on a primary (`select_entity`) press outside the gameplay minimap, and SHALL exit build mode without placing on a secondary (`deselect_entity`) press or `ui_cancel` (Escape). Preview repositioning SHALL continue to track the pointer every frame, independent of input events (camera pans emit no motion events). A commit click consumed by build mode SHALL NOT additionally resolve as a unit order in the same frame.

#### Scenario: Select presses attempt placement
- **WHEN** the primary button is pressed in build mode outside the minimap over a valid target
- **THEN** the building is placed and build mode exits

#### Scenario: Invalid target refuses and keeps build mode
- **WHEN** the primary button is pressed in build mode over an invalid target
- **THEN** no building is placed and build mode stays active

#### Scenario: Minimap press does not place
- **WHEN** the primary button is pressed while the pointer is over the gameplay minimap
- **THEN** no building is placed and build mode stays active

#### Scenario: Cancel exits without placing
- **WHEN** the secondary button is pressed or Escape is pressed in build mode
- **THEN** build mode exits and no building is placed

#### Scenario: Commit click does not double-fire as an order
- **WHEN** a commit click places a building
- **THEN** the same physical click SHALL NOT additionally resolve as a unit order in the same frame

#### Scenario: Preview tracks the pointer between events
- **WHEN** build mode is active and the pointer or camera moves without any button event
- **THEN** the preview position tracks the pointer
