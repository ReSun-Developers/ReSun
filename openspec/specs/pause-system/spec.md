## Purpose

The pause system lets the player suspend an in-progress game: the ESC key toggles a global pause that freezes gameplay processing, a pause menu stays interactive while the rest of the tree is paused, and resuming with the mouse does not leak a gameplay command. ESC first belongs to active cancel-modes (build/sell/repair/debug-place).
## Requirements
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

### Requirement: Game simulation halts while paused
While the pause menu is open, the game SHALL pause all gameplay processing: unit movement and combat, production timers, economy timers, and resource growth. Nodes with the default (pausable) process mode MUST stop processing.

#### Scenario: Units and timers freeze during pause
- **WHEN** the game is paused
- **THEN** a node with default pausable process mode reports it cannot process, and no gameplay timer advances

#### Scenario: Resuming restores processing
- **WHEN** the game is unpaused
- **THEN** nodes with default pausable process mode resume processing

### Requirement: Pause menu stays interactive while paused
The pause menu UI SHALL remain interactive while the game is paused. Its root node SHALL use `process_mode = PROCESS_MODE_ALWAYS`.

#### Scenario: Pause menu processes while paused
- **WHEN** the game is paused
- **THEN** the pause menu node reports it can process, and its buttons remain clickable

### Requirement: Return to game button
The pause menu SHALL provide a "Return to game" button that resumes the game and hides the pause menu.

#### Scenario: Clicking Return to game
- **WHEN** the player clicks "Return to game"
- **THEN** the pause menu hides and `get_tree().paused` is `false`

### Requirement: Quit to desktop button
The pause menu SHALL provide a "Quit to desktop" button that exits the game.

#### Scenario: Clicking Quit to desktop
- **WHEN** the player clicks "Quit to desktop"
- **THEN** the game quits to the operating system

### Requirement: ESC conflict with cancel modes
When a mode that already consumes ESC is active (building placement, sell mode, repair mode, or debug-place mode), pressing ESC SHALL cancel that mode and MUST NOT open the pause menu. The pause menu SHALL only open when none of these modes is active.

#### Scenario: ESC cancels build mode without pausing
- **WHEN** the player is in building-placement mode and presses ESC
- **THEN** build mode is cancelled and the pause menu does not open

#### Scenario: ESC exits sell mode without pausing
- **WHEN** the player is in sell mode and presses ESC
- **THEN** sell mode is exited and the pause menu does not open

#### Scenario: ESC opens pause after cancel mode cleared
- **WHEN** the player is in building-placement mode, presses ESC once to cancel it, and presses ESC again
- **THEN** the pause menu opens on the second ESC press

### Requirement: Default cursor while paused
While the pause menu is open, the game SHALL show the default system cursor, regardless of the cursor that was active at the moment of pausing.

#### Scenario: Non-default cursor becomes default on pause
- **WHEN** the player pauses while a non-default cursor (e.g. attack, move, or select) is showing
- **THEN** the cursor becomes the default system cursor while the pause menu is open

#### Scenario: Cursor re-resolves after resume
- **WHEN** the player resumes the game
- **THEN** the cursor is re-resolved by normal gameplay logic

### Requirement: Resume click does not pass through to gameplay
Resuming the game with the mouse MUST NOT issue a gameplay command (e.g. a move or select order) from the click that pressed the resume button. Input immediately after unpausing SHALL be debounced long enough to swallow that click.

#### Scenario: No move order from the resume click
- **WHEN** the player has units selected, pauses, and clicks "Return to game" to resume
- **THEN** the selected units receive no move order from the resume click

#### Scenario: Next click issues orders normally
- **WHEN** the player resumes the game and then clicks on the map
- **THEN** that click issues orders as normal

### Requirement: Briefing button in the pause menu
The pause menu SHALL provide a "Briefing" button that opens the mission briefing dialog for the
active mission. Activating it SHALL NOT resume the game — the game SHALL stay paused while the
briefing is shown. When no mission is active the button SHALL be disabled.

#### Scenario: Briefing opens without resuming
- **WHEN** the player clicks Briefing while the game is paused during a mission
- **THEN** the briefing dialog is shown and `get_tree().paused` remains `true`

#### Scenario: Briefing disabled without a mission
- **WHEN** the pause menu is open and no mission is active
- **THEN** the Briefing button is disabled

