# Spec Delta

## Purpose

Provides one authoritative place for user settings in `user://settings.cfg` and the Options view that edits them, reachable from the boot game selector, the pre-match main menu, and the in-match pause menu, with per-surface theming and a restart-and-resume path for settings that cannot apply live.

## ADDED Requirements

### Requirement: Single namespaced user-config authority
The system SHALL persist user settings to `user://settings.cfg` in INI format using sections namespaced by concern, and per-game settings namespaced by the active game id (for example a base input section plus a section per game id, and a game-settings section per game id). Every writer SHALL load the existing file, modify only its own keys, and save — so writing one concern's settings preserves every other concern's keys. The settings file SHALL remain human-readable and hand-editable. Legacy `[camera]` and `[keybinds]` sections SHALL be migrated into the input section on load.

#### Scenario: Sibling writers preserve each other's keys
- **WHEN** a graphics setting is saved and then a camera binding is remapped
- **THEN** both the graphics keys and the persisted game choice remain present and loadable on the next boot

#### Scenario: Fresh install with no config file
- **WHEN** the game starts and `user://settings.cfg` does not exist
- **THEN** every settings concern uses its defaults and no error is pushed

#### Scenario: Legacy sections migrate
- **WHEN** the file contains a legacy `[camera] edge_scroll_enabled=false` and `[keybinds]` entry
- **THEN** the value is read into the input section and the game behaves as if it had been stored there

#### Scenario: Malformed config file
- **WHEN** `user://settings.cfg` contains invalid INI syntax
- **THEN** every settings concern loads defaults, logs a warning, and does not crash at boot

### Requirement: Options view on all three surfaces
The system SHALL present an Options view reachable from the boot game selector, the pre-match main menu, and the in-match pause menu. Opening and closing the Options view SHALL NOT change the active game, the persisted game choice, or any gameplay entity.

#### Scenario: Options from the boot selector
- **WHEN** the player activates the `Options` row on the boot selector
- **THEN** the Options view opens over the selector and the active game and persisted choice are unchanged

#### Scenario: Options from the main menu
- **WHEN** the player activates the `Options` entry on the pre-match main menu
- **THEN** the Options view opens over the menu

#### Scenario: Options from the pause menu
- **WHEN** the player activates the `Options` entry on the in-match pause menu
- **THEN** the Options view opens and the match remains paused

#### Scenario: Closing returns to the opening surface
- **WHEN** the player closes the Options view without restarting
- **THEN** the surface that opened it is shown again and no gameplay state changed

### Requirement: Options view section navigation
The Options view SHALL expose four sections — Graphics, Display, Input, and Game — and SHALL let the player switch between them without leaving the view. Each section SHALL be independently addressable by name so a restart can resume on the same section.

#### Scenario: Sections are switchable
- **WHEN** the Options view is open on the Graphics section and the player selects the Input section
- **THEN** the Input controls are shown and no other setting changes

#### Scenario: Section is addressable
- **WHEN** the Options view is requested with a section name
- **THEN** it opens showing that section

### Requirement: Options dialog is centered over its surface
The Options view SHALL present its dialog as a centered panel over a dimmed full-screen backdrop, regardless of the surface it was opened from, so the dialog appears in the middle of the view.

#### Scenario: Dialog is centered
- **WHEN** the Options view is opened
- **THEN** its panel is positioned in the center of the viewport, not anchored to a corner

#### Scenario: Backdrop dims the surface
- **WHEN** the Options view is open
- **THEN** a full-screen dimmed backdrop sits behind the centered panel


### Requirement: Options view theming
The Options view SHALL be themed from the active `GameDefinition` (`menu_background`, `menu_accent_color`) when opened from the pre-match main menu or the in-match pause menu, and SHALL use a neutral theme when opened from the boot selector, whose surface must reference no per-game content. Neutrality SHALL be keyed to the opening surface, not to whether a game is active (a game is always resolved before the selector shows).

#### Scenario: Themed in a game menu or pause
- **WHEN** the Options view is opened from the main menu or pause menu while a game with declared theme values is active
- **THEN** its background and accent reflect that game's `menu_background` and `menu_accent_color`

#### Scenario: Neutral on the selector
- **WHEN** the Options view is opened from the boot selector
- **THEN** it uses the neutral placeholder theme and references no `res://games/` asset, even though a game is already resolved as active

### Requirement: Pause-menu Options overlay is modal
The Options view opened from the pause menu SHALL be modal over the paused match: it SHALL process while the tree is paused (`process_mode = ALWAYS`) and SHALL consume ESC while open, so ESC closes the Options view without resuming the match. The match SHALL remain paused until the player explicitly resumes it.

#### Scenario: ESC closes Options without resuming
- **WHEN** the Options view is open over the pause menu and the player presses ESC
- **THEN** the Options view closes, the pause menu is shown, and `get_tree().paused` remains `true`

#### Scenario: Options stays interactive while paused
- **WHEN** the match is paused and the Options view is open
- **THEN** the view reports it can process and its controls are interactive

### Requirement: Restart-and-resume marker
When a setting requires a restart, the system SHALL record the section to resume, restart the application, and on the next launch reopen the Options view on the recorded section and clear the marker once consumed. Because a relaunch preserves the original command line (which may include `--game` and skip the boot selector), the resume handler SHALL NOT depend on the boot selector being shown. The marker SHALL only be recorded when the restart is requested from the boot selector or the pre-match main menu.

#### Scenario: Resume on the same section
- **WHEN** a restart-only setting is confirmed on the Graphics section of the main menu
- **THEN** after relaunch the Options view opens on the Graphics section

#### Scenario: Resume works when the boot selector is skipped
- **WHEN** the game was launched with `--game` and a restart was requested from the main menu
- **THEN** after relaunch the Options view opens on the recorded section even though the boot selector never appears

#### Scenario: Marker is one-shot
- **WHEN** the resumed Options view is opened after a restart
- **THEN** the marker is cleared and a subsequent launch does not auto-open the view

#### Scenario: Restart not offered where it would end a session
- **WHEN** the player is in the in-match pause menu
- **THEN** controls for restart-only settings are disabled and no resume marker can be recorded

### Requirement: Settings apply without disturbing the caller
Editing a setting that can apply live SHALL take effect immediately, without restart, and without closing the Options view. Editing a restart-only setting SHALL leave current behavior untouched until the restart and SHALL be visually marked as requiring one.

#### Scenario: Live setting applies immediately
- **WHEN** the player toggles a live setting
- **THEN** the change is visible immediately and the Options view stays open

#### Scenario: Restart-only setting is marked and inert
- **WHEN** the player changes a restart-only setting
- **THEN** it is marked as requiring a restart and the running renderer is unchanged until relaunch
