## Purpose

Defines the shipped rendering budget: the default world environment's feature set, the shared building select-box material, and the rule that release builds ship no debug geometry.

## Requirements

### Requirement: SSAO disabled in default environment
The default world environment SHALL have SSAO disabled (`ssao_enabled = false`). Glow SHALL remain enabled and fog SHALL remain enabled in the shipped defaults. The directional shadow size SHALL default to 4096, and SHALL be overridable at runtime by the active graphics preset's shadow quality (the user-selectable setting defined by `graphics-settings`).

#### Scenario: Environment configuration
- **WHEN** the default world environment is loaded in MainScene, MapEditor, or AssetBrowser
- **THEN** `ssao_enabled` is false on the environment resource

#### Scenario: Shadow resolution preserved
- **WHEN** no graphics preset override is active
- **THEN** `project.godot` `lights_and_shadows/directional_shadow/size` is 4096

#### Scenario: Shadow resolution is preset-selectable
- **WHEN** the active graphics preset selects a shadow quality other than the default
- **THEN** the directional shadow resolution follows the selected shadow quality instead of being pinned at 4096

### Requirement: Shared building select-box material
Building select boxes SHALL use a single cached material shared across all buildings instead of allocating a fresh material per building. Box geometry SHALL remain generated per building from its foundation size.

#### Scenario: Material sharing
- **WHEN** two buildings with different foundation sizes each display their select box
- **THEN** both select boxes share the same `ORMMaterial3D` instance while rendering geometry sized to each foundation

#### Scenario: Geometry per foundation
- **WHEN** a building select box is drawn
- **THEN** its line geometry matches the building's `SelectComponent.outline_size` foundation dimensions

### Requirement: Release builds ship no debug geometry
Debug overlay meshes and debug-only scene nodes SHALL not exist or render in a non-debug build. The shipped HUD SHALL not contain an active DebugMenu in a non-debug build.

#### Scenario: No debug geometry in release
- **WHEN** the game runs from a non-debug build
- **THEN** no path lines, bounds meshes, or debug grid overlays are created or rendered

#### Scenario: No debug menu in release
- **WHEN** the game runs from a non-debug build
- **THEN** the DebugMenu node does not process input or render
