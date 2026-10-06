## Purpose

Defines the `InputSettings` autoload: loading and persisting per-game camera bindings (a base section plus per-game overrides) and the edge-scroll toggle, and remapping camera actions through `user://settings.cfg`.

## Requirements

### Requirement: InputSettings autoload loads settings on startup
The `InputSettings` autoload SHALL load `user://settings.cfg` on `_ready()`. Bindings SHALL be resolved as: the active game's override section (`[input.<game_id>]`), then the base section (`[input]`), then the `project.godot` default. If the file does not exist or fails to load, all settings SHALL fall back to defaults. The autoload MUST be registered in `project.godot` before scene-loading autoloads to ensure it initializes before any node reads `Input.is_action_pressed()`. Loading SHALL NOT rewrite or discard sections written by other settings concerns, and legacy `[camera]`/`[keybinds]` keys SHALL be read into `[input]`.

#### Scenario: Fresh install with no config file
- **WHEN** the game starts and `user://settings.cfg` does not exist
- **THEN** `edge_scroll_enabled` defaults to `true` and all actions use `project.godot` defaults

#### Scenario: Config file exists with valid settings
- **WHEN** the game starts and `user://settings.cfg` contains `[input] edge_scroll_enabled=false`
- **THEN** `InputSettings.edge_scroll_enabled` is `false`

#### Scenario: Base binding applies when no game override exists
- **WHEN** the file stores `[input] camera_up="Numpad8"` and the active game has no `[input.<game>]` override
- **THEN** `camera_up` resolves to Numpad8

#### Scenario: Game override wins over base
- **WHEN** the file stores base `camera_up="W"` and `[input.ts] camera_up="Numpad8"` and `ts` is active
- **THEN** `camera_up` resolves to Numpad8

#### Scenario: Config file is malformed
- **WHEN** `user://settings.cfg` contains invalid INI syntax
- **THEN** the autoload loads defaults, logs a warning, and does not discard other sections

### Requirement: InputSettings persists settings to ConfigFile
The `InputSettings` autoload SHALL save settings to `user://settings.cfg` in INI format. Base bindings SHALL be written to the `[input]` section and per-game bindings to `[input.<game_id>]`. Saving SHALL load the existing file and modify only its own keys so that every other section (graphics, game choice, other settings) is preserved. The file SHALL be human-readable and manually editable, and SHALL include a comment explaining physical layout behavior for non-QWERTY users.

#### Scenario: Save creates config file
- **WHEN** a binding is saved and `user://settings.cfg` does not exist
- **THEN** the file is created containing the `[input]` section

#### Scenario: Save preserves other concerns
- **WHEN** a binding is saved and the file already stores a `[graphics]` section and a `[game]` id
- **THEN** the `[graphics]` section and `[game]` id remain present after the save

### Requirement: Camera actions are remappable via ConfigFile
The `InputSettings` autoload SHALL read key names from the base `[input]` section and each `[input.<game_id>]` override section and apply them to `InputMap` actions (`camera_up`, `camera_down`, `camera_left`, `camera_right`). Key names SHALL use `OS.get_keycode_string()` format (e.g., `"W"`, `"Space"`, `"F1"`). `remap_action(action, key_name, target)` SHALL accept a target identifying whether the edit applies to the base binding or to a specific game's override; when the active game is not the target it SHALL still write the target section. `remap_action` SHALL erase all existing events for the action before adding the new event — previous bindings do not fire after remap.

#### Scenario: Default camera bindings
- **WHEN** no `[input]` section exists in the config file
- **THEN** camera actions use defaults from `project.godot` (W=up, A=left, S=down, D=right)

#### Scenario: Remapped camera key persists
- **WHEN** the base section stores `camera_up=Numpad8` and the game restarts
- **THEN** pressing Numpad 8 triggers the `camera_up` action and W no longer triggers it

#### Scenario: Invalid key name falls back to default
- **WHEN** the config file contains `camera_up=InvalidKey`
- **THEN** the action retains its default binding from `project.godot`

#### Scenario: Editing one game's column leaves others alone
- **WHEN** the player remaps a binding with target `ts`
- **THEN** only `[input.ts]` changes; the base section and other games' override sections are unchanged

### Requirement: Edge scroll toggle persists and takes effect immediately
The `InputSettings` autoload SHALL expose `edge_scroll_enabled` (default: `true`) loaded from the `[input]` section of `user://settings.cfg` (with the legacy `[camera]` key read as a fallback). Changes SHALL take effect immediately at runtime and persist when `_save()` is called.

#### Scenario: Edge scroll disabled via config
- **WHEN** `user://settings.cfg` contains `[input] edge_scroll_enabled=false` and the game starts
- **THEN** `InputSettings.edge_scroll_enabled` is `false`

#### Scenario: Edge scroll enabled by default
- **WHEN** no `[input]` section exists in the config file
- **THEN** `InputSettings.edge_scroll_enabled` is `true`

#### Scenario: Runtime toggle takes effect immediately
- **WHEN** `InputSettings.edge_scroll_enabled` is changed at runtime and `_save()` is called
- **THEN** edge scroll behavior updates immediately without restart and persists to disk

### Requirement: Edge scroll toggle gates panning and cursor
When `InputSettings.edge_scroll_enabled` is `false`, `CameraController.handle_border_panning()` SHALL return early and `MouseHandler._resolve_scroll_cursor()` SHALL not return scroll cursor types. Other cursor modes (sell, repair) are unaffected.

#### Scenario: Edge scroll enabled
- **WHEN** `InputSettings.edge_scroll_enabled` is `true` and the mouse is near the screen edge
- **THEN** the scroll cursor is displayed and the camera pans

#### Scenario: Edge scroll disabled
- **WHEN** `InputSettings.edge_scroll_enabled` is `false` and the mouse is near the screen edge
- **THEN** no scroll cursor is shown and the camera does not pan

### Requirement: Camera panning responds to configurable key bindings
Camera panning SHALL respond to configurable key bindings via `InputMap` actions. Default bindings are WASD. Ctrl+D SHALL block camera movement regardless of bindings.

#### Scenario: Default WASD panning
- **WHEN** the player presses W while no modifier is held
- **THEN** the camera moves forward

#### Scenario: Ctrl blocks camera movement
- **WHEN** the player holds Ctrl and presses W
- **THEN** the camera does not move

#### Scenario: Remapped key triggers panning
- **WHEN** `camera_up` is remapped to Numpad8
- **THEN** pressing Numpad8 moves the camera forward

### Requirement: Existing input is unaffected
All existing input actions and raw key checks remain unchanged.

#### Scenario: Selection input unchanged
- **WHEN** the player single left-clicks an entity
- **THEN** the entity is selected

### Requirement: Games declare supported input actions
`GameDefinition` SHALL declare the input actions a game supports via `supported_inputs`. An empty declaration SHALL mean no restriction (every managed action is supported). A non-empty declaration SHALL be an allow-list: an action absent from it is unsupported for that game and SHALL NOT be bound for it.

#### Scenario: Declared action is bound
- **WHEN** a game declares an action it supports
- **THEN** that action is bound for the game and appears enabled in the Input options view

#### Scenario: Unsupported action is inert
- **WHEN** a game's non-empty declaration omits an action
- **THEN** the action is not bound for that game and has no effect while it is active

### Requirement: Input options table with base and per-game columns
The Input options view SHALL present a table with one row per action, a base column, and one column per known game. A cell SHALL show an inherited value when the game has no override, a distinct override value when it does, and SHALL be disabled when the game does not support that action. Editing a cell SHALL write an override for that game; editing the base column SHALL change the base for every game without its own override.

#### Scenario: Inherited cell is shown
- **WHEN** the active game has no override for an action whose base is bound
- **THEN** the game's cell shows the inherited base value

#### Scenario: Override cell is shown
- **WHEN** a game has an override for an action
- **THEN** that game's cell shows the override value distinctly from the base

#### Scenario: Unsupported cell is disabled
- **WHEN** a game does not declare support for an action
- **THEN** that game's cell for the action is disabled and cannot be edited

### Requirement: Bindings apply when the active game changes
When the active game changes, the system SHALL re-resolve and apply input bindings for the newly active game, so the resolved bindings match that game's overrides and base.

#### Scenario: Switch applies the new game's bindings
- **WHEN** the active game changes from `ts` (with an override) to `ra2` (no override)
- **THEN** the overridden action reverts to the base binding for `ra2`
