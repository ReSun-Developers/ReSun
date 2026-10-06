# Spec Delta

## Purpose

Defines the global (all-games) graphics settings: the configurable rendering fields and their allowed values, the Low/Medium/High/Ultra quality presets, persistence, boot/runtime/scene-load/editor application, restart-only classification, and the change notification that lets runtime systems react.

## ADDED Requirements

### Requirement: Graphics settings schema
The system SHALL expose these global graphics settings, shared across every game, with these allowed values: antialiasing mode (Off, MSAA 2x, MSAA 4x, SMAA, SMAA+MSAA), shadow quality (Off, Low, Medium, High), cloud shadows (on/off), GI mode (Off, SDFGI, High), tone-mapping mode (Linear, Reinhard, Filmic, ACES), exposure (a number, default 1.0), and texture quality (Low, Medium, High). The schema SHALL be defined in one place so the Options view and the applier cannot drift. Each field SHALL declare a human-readable label, a description, and the domain it belongs to.

#### Scenario: Fields are enumerable
- **WHEN** the graphics settings schema is requested
- **THEN** it lists every field above with its allowed values and current value

#### Scenario: Round-trip through the config file
- **WHEN** each graphics field is set and saved, then reloaded
- **THEN** every field retains its saved value

#### Scenario: Invalid values are refused
- **WHEN** a value outside a field's allowed set is written
- **THEN** the field keeps its previous value and a numeric field is clamped to its declared range

### Requirement: Display settings schema
The system SHALL expose these global display settings, shared across every game: window mode (Windowed, Borderless, Fullscreen) and resolution (a window size, defaulting to the project's base resolution). Display settings SHALL belong to a distinct `display` domain so the quality presets never change them.

#### Scenario: Display fields are enumerable
- **WHEN** the display settings schema is requested
- **THEN** it lists window mode and resolution with their allowed values and current value

#### Scenario: Presets leave display untouched
- **WHEN** any quality preset is applied
- **THEN** the window mode and resolution are unchanged

### Requirement: Display settings apply live
Changing the window mode or resolution SHALL take effect immediately without a restart: Windowed resizes and centers the window to the chosen resolution (or to the screen when the chosen size exceeds it), Borderless and Fullscreen switch the window mode. On a headless host with no window, display application SHALL be a no-op.

#### Scenario: Windowed resolution applies
- **WHEN** the player selects a windowed resolution
- **THEN** the window is resized to that resolution and centered

#### Scenario: Fullscreen mode applies
- **WHEN** the player selects fullscreen
- **THEN** the window switches to fullscreen without a restart

#### Scenario: Headless host is a no-op
- **WHEN** the game runs on a headless host
- **THEN** applying display settings does not error


### Requirement: Antialiasing maps to the viewport
The antialiasing setting SHALL map to the viewport's multisample and screen-space antialiasing modes: Off disables both, MSAA 2x/4x enable the matching multisample level, SMAA enables screen-space SMAA, and SMAA+MSAA enables both.

#### Scenario: Off disables both
- **WHEN** antialiasing is Off
- **THEN** the viewport's multisample mode and screen-space AA mode are both disabled

#### Scenario: MSAA 4x
- **WHEN** antialiasing is MSAA 4x
- **THEN** the viewport's multisample mode is 4x and screen-space AA is disabled

#### Scenario: SMAA+MSAA
- **WHEN** antialiasing is SMAA+MSAA
- **THEN** the viewport's screen-space AA is SMAA and its multisample mode is enabled

### Requirement: Quality presets apply atomically
The system SHALL provide Low, Medium, High, and Ultra presets. Selecting a preset SHALL set every graphics field to that preset's value in one operation, then apply once; it SHALL NOT apply partially. Individual field edits SHALL be permitted independently of the active preset.

#### Scenario: Preset sets all fields
- **WHEN** the player selects the High preset
- **THEN** every graphics field equals the High preset's defined value

#### Scenario: Preset application is observable as one change
- **WHEN** a preset is selected
- **THEN** the graphics-change notification fires once for the batch, not once per field

#### Scenario: Individual override
- **WHEN** the player changes one field after selecting a preset
- **THEN** only that field changes and the others keep the preset's values

#### Scenario: Selecting a preset updates every option control
- **WHEN** the player selects a preset in the Options view
- **THEN** every option control in the section is refreshed to the preset's values in the same interaction

#### Scenario: Divergence reports a Custom state
- **WHEN** the graphics field values do not equal any named preset
- **THEN** the preset picker reports a Custom state rather than a named preset

#### Scenario: Returning to preset values clears Custom
- **WHEN** individual edits are undone so the fields again equal a named preset
- **THEN** the preset picker reports that named preset again

### Requirement: Low preset is minimum-spec safe
The Low preset SHALL exclude expensive features: GI Off, antialiasing Off, cloud shadows off, and shadow quality Off. It SHALL target the project's minimum specification.

#### Scenario: Low excludes SDFGI
- **WHEN** the Low preset is applied
- **THEN** GI mode is Off

#### Scenario: Low excludes SMAA and MSAA
- **WHEN** the Low preset is applied
- **THEN** antialiasing mode is Off

#### Scenario: Low excludes high shadow quality
- **WHEN** the Low preset is applied
- **THEN** shadow quality is Off

### Requirement: Fresh-install default is minimum-spec safe
On a first run with no persisted graphics settings, the active preset SHALL be the Low preset, whose values do not enable SDFGI, SMAA, or high shadow quality.

#### Scenario: First boot has no expensive feature enabled
- **WHEN** the game boots with no `[graphics]` section in the config file
- **THEN** the active preset is Low, GI is not SDFGI, antialiasing is not SMAA, and shadow quality is not high

### Requirement: Graphics settings apply on boot and on scene load
The system SHALL load persisted graphics settings on boot and apply them to the viewport, the world environment, the directional light, the cloud-shadow overlay, and the rendering server before or during the first rendered frame. It SHALL re-apply the persisted settings whenever an environment scene is (re)instantiated — including each mission/world swap — so the preset is never reset to scene defaults.

#### Scenario: Persisted value is applied at boot
- **WHEN** the config file stores cloud shadows off and the game boots
- **THEN** the cloud-shadow overlay is not rendered

#### Scenario: Environment reflects persisted GI
- **WHEN** the config file stores GI mode High and the game boots
- **THEN** the world environment enables SDFGI with the High preset's settings

#### Scenario: Preset survives a mission/world swap
- **WHEN** the match world is replaced and a new environment scene is instantiated
- **THEN** the persisted graphics settings are re-applied to the new scene without requiring a restart

### Requirement: Graphics settings apply in the runtime editor scenes
The Map Editor and Asset Browser scenes SHALL receive the persisted graphics settings on load, applied through the same applier as gameplay, so authoring previews match what the player will see.

#### Scenario: Map Editor reflects the preset
- **WHEN** the Map Editor scene is loaded with a non-default graphics preset persisted
- **THEN** its environment, light, and cloud-shadow overlay reflect the persisted preset

#### Scenario: Asset Browser reflects the preset
- **WHEN** the Asset Browser scene is loaded with a non-default graphics preset persisted
- **THEN** its environment and light reflect the persisted preset

### Requirement: Runtime application and restart classification
The system SHALL apply every graphics setting at runtime without restart where the engine supports it. Shadow quality (including the directional shadow map size via the rendering server) and antialiasing SHALL apply live. Texture quality SHALL be classified as restart-only because no runtime API exists for it, and SHALL be surfaced as such in the Options view. The graphics schema SHALL declare, per field, whether it applies live or requires a restart.

#### Scenario: Live setting changes behavior without restart
- **WHEN** antialiasing or shadow quality is changed while a match is running
- **THEN** the viewport's antialiasing and the directional shadow quality update without a restart

#### Scenario: Restart-only setting is classified
- **WHEN** the graphics schema is inspected
- **THEN** texture quality is marked restart-only and every other field is marked live

#### Scenario: Restart-only value is stored for the next launch
- **WHEN** a restart-only value is chosen and the game restarts
- **THEN** the value is read from the user config on the next boot and applied then

### Requirement: Graphics change notification
The system SHALL emit a change notification carrying the set of changed graphics keys after a settings change has been applied, so runtime systems can react. Subscribers SHALL be able to react without polling.

#### Scenario: Dependent system reacts
- **WHEN** a graphics setting changes
- **THEN** a subscribed runtime system receives the notification with the changed keys

#### Scenario: No spurious notification
- **WHEN** the game boots and applies persisted settings once
- **THEN** the notification fires for that application and not repeatedly on idle frames
