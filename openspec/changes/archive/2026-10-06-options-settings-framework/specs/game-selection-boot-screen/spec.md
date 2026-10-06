# game-selection-boot-screen Specification (Delta)

## MODIFIED Requirements

### Requirement: Selecting a game resolves and persists it
The system SHALL treat activating a game row as: calling `GameContext.select_game(id)` (skipped when that id is already active), then `GameContext.save_game_choice(id)`, then hiding the boot screen and showing the main menu. The persisted choice SHALL NOT be written when the selection is refused. The `Options` row SHALL NOT select a game; activating it SHALL open the Options view without selecting a game or changing the persisted choice.

#### Scenario: Picking a different game
- **WHEN** the player activates the row of a game whose id differs from the active one
- **THEN** `GameContext.current.id` equals the picked id, exactly one `game_changed` was emitted, the persisted setting contains the picked id, the boot screen is hidden, and the main menu is visible

#### Scenario: Picking the already-active game
- **WHEN** the player activates the row of the game that is already active
- **THEN** no `game_changed` is emitted (consumers do not re-register), the picked id is persisted, and the boot screen proceeds to the main menu

#### Scenario: Quit row exits the app
- **WHEN** the player activates the `Quit` row
- **THEN** the application exits

#### Scenario: Options row opens the options view
- **WHEN** the player activates the `Options` row
- **THEN** the Options view opens over the boot screen and no game selection occurs
