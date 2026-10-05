# pause-system Specification (Delta)

## MODIFIED Requirements

### Requirement: Pause toggle via ESC
The game SHALL provide a `pause` input action bound to the ESC key. Pressing ESC while gameplay is running SHALL pause the game and show the pause menu. Pressing ESC while already paused SHALL resume the game and hide the pause menu. When the Options view is open over the pause menu, ESC SHALL close the Options view and return to the pause menu without resuming the game.

#### Scenario: ESC opens the pause menu
- **WHEN** the player presses ESC during normal gameplay (no build/sell/repair/debug-place mode active)
- **THEN** the pause menu becomes visible and `get_tree().paused` is `true`

#### Scenario: ESC closes the pause menu
- **WHEN** the player presses ESC while the pause menu is open and no Options view is open
- **THEN** the pause menu becomes hidden and `get_tree().paused` is `false`

#### Scenario: ESC closes the Options view without resuming
- **WHEN** the player presses ESC while the Options view is open over the pause menu
- **THEN** the Options view closes, the pause menu remains visible, and `get_tree().paused` remains `true`
