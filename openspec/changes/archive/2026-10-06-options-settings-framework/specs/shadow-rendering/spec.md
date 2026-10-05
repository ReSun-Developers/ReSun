# shadow-rendering Specification (Delta)

## MODIFIED Requirements

### Requirement: Orthogonal shadow mode
The DirectionalLight3D SHALL default to orthogonal shadow mode (`directional_shadow_mode = 0`) instead of PSSM 4-split. Shadow mode SHALL be selectable through the active graphics preset's shadow quality, with orthogonal mode as the default when no override is active.

#### Scenario: Shadow mode configuration
- **WHEN** the DirectionalLight3D is configured with no graphics preset override
- **THEN** `directional_shadow_mode` is set to 0 (Orthogonal)

#### Scenario: Shadow mode follows shadow quality
- **WHEN** the active graphics preset selects a shadow quality that specifies a different mode
- **THEN** `directional_shadow_mode` follows the selected shadow quality

### Requirement: Shadow map resolution
The project SHALL default to a shadow map resolution of 4096 for the directional light. The resolution SHALL be selectable through the active graphics preset's shadow quality, with 4096 as the default when no override is active.

#### Scenario: Shadow map size configuration
- **WHEN** the project settings are loaded with no graphics preset override
- **THEN** `rendering/lights_and_shadows/directional_shadow/size` is 4096

#### Scenario: Shadow map size follows shadow quality
- **WHEN** the active graphics preset selects a lower shadow quality
- **THEN** the directional shadow map resolution follows the selected shadow quality
