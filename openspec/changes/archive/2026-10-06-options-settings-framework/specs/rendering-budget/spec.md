# rendering-budget Specification (Delta)

## MODIFIED Requirements

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
