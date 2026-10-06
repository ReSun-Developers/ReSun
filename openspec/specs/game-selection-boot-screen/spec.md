# game-selection-boot-screen Specification

## Purpose

Defines the boot-time game-selection launcher shown before any game's main menu: the plain-placeholder boot screen listing discovered games, game selection through GameContext with persistence, the `--game` CLI skip path, the Quit/ESC exit paths, main-menu occlusion while the launcher is visible, and headless testability of both boot paths.

## Requirements

### Requirement: Boot screen lists discovered games
The system SHALL show a boot screen before the main menu on every launch without `--game`. The boot screen SHALL display one row per GameDefinition returned by `GameContext.list_games()`, labeled with the definition's `display_name` (falling back to `id` when `display_name` is empty), plus an `Options` row and a `Quit` row. The boot screen SHALL use plain placeholder controls — standard buttons on a neutral background — and SHALL NOT reference any per-game content; per-game visual theming is deferred to the content packs.

#### Scenario: Games rendered as rows
- **WHEN** the boot screen is shown and `GameContext.list_games()` returns definitions with ids `ts` and `ra2`
- **THEN** the boot screen contains rows labeled with each definition's `display_name`, plus `Options` and `Quit` rows

#### Scenario: Display name fallback
- **WHEN** a discovered GameDefinition has an empty `display_name`
- **THEN** its row is labeled with the definition's `id`

#### Scenario: Boot screen hidden under the CLI flag
- **WHEN** the game is launched with `--game ts`
- **THEN** the boot screen never becomes visible (no menu flash) and the main menu is shown, with `GameContext.current.id` equal to `"ts"`

#### Scenario: Launcher is game-agnostic
- **WHEN** the boot screen scene's external resource references are inspected
- **THEN** none of them point under `res://games/` (no per-game assets)

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

### Requirement: ESC exits the app from the boot screen
The system SHALL exit the application when the player presses ESC while the boot screen is visible, equivalent to activating the Quit row. The ESC path SHALL NOT call `select_game` or `save_game_choice`. Right-clicks SHALL NOT trigger any boot-screen action.

#### Scenario: ESC exits the app
- **WHEN** the player presses ESC while the boot screen is visible
- **THEN** the application exits exactly as if the Quit row had been activated, with no game selection and no persistence

#### Scenario: Exit is always reachable
- **WHEN** the boot screen is shown with no discovered games (zero game rows)
- **THEN** the `Quit` row is still present, so the app can always be exited from the launcher

### Requirement: Main menu occluded while the boot screen is visible
While the boot screen is visible, the main menu SHALL be hidden so its input handling cannot react to clicks aimed at boot-screen rows; dismissing the boot screen (after a pick) SHALL restore the main menu.

#### Scenario: Main menu hidden during selection
- **WHEN** the boot screen is visible after boot without `--game`
- **THEN** the main menu node is not visible

#### Scenario: Main menu restored after a pick
- **WHEN** the boot screen is dismissed by picking a game
- **THEN** the main menu node is visible again

### Requirement: Both boot paths verifiable headlessly
The flag path and the menu path SHALL be testable in-process without relaunching the engine: the skip decision SHALL be exposed as a pure static function over an argument list, and the selection flow SHALL be exercisable against the real `GameContext` autoload with persistence redirected to a scratch config path.

#### Scenario: Skip gate decides from args alone
- **WHEN** the static skip check is called with an argument list containing `--game ts`
- **THEN** it reports the boot screen should be skipped, and with arguments lacking the flag it reports the boot screen should be shown

#### Scenario: Menu path produces the expected active game
- **WHEN** a headless test instantiates the boot screen, redirects persistence to a scratch config, and invokes the selection flow for a discovered game id
- **THEN** `GameContext.current.id` equals the picked id and the scratch config contains that id
