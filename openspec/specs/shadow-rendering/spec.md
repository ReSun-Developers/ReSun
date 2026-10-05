## Purpose

Defines the directional shadow configuration: camera far clip for shadow concentration, shadow mode, light angular distance, blur, and shadow map resolution.

## Requirements

### Requirement: Camera far clip for shadow concentration
The Camera3D SHALL use a `far` clip value that concentrates shadow resolution on the visible gameplay area. For a 512×512 map with orthogonal projection, `far` SHALL be set to 400.0 units.

#### Scenario: Shadow map covers visible area
- **WHEN** the camera renders the scene with `far = 400.0`
- **THEN** the shadow map covers only the visible gameplay area (~400 units depth)

#### Scenario: Map edges not clipped
- **WHEN** the camera is positioned at any valid map location
- **THEN** terrain and entities at map edges are not clipped by the far plane

### Requirement: Orthogonal shadow mode
The DirectionalLight3D SHALL default to orthogonal shadow mode (`directional_shadow_mode = 0`) instead of PSSM 4-split. Shadow mode SHALL be selectable through the active graphics preset's shadow quality, with orthogonal mode as the default when no override is active.

#### Scenario: Shadow mode configuration
- **WHEN** the DirectionalLight3D is configured with no graphics preset override
- **THEN** `directional_shadow_mode` is set to 0 (Orthogonal)

#### Scenario: Shadow mode follows shadow quality
- **WHEN** the active graphics preset selects a shadow quality that specifies a different mode
- **THEN** `directional_shadow_mode` follows the selected shadow quality

### Requirement: Light angular distance preserved
The DirectionalLight3D SHALL retain `light_angular_distance = 1.1` to maintain soft shadow edges appropriate for the game's visual style.

#### Scenario: Angular distance configuration
- **WHEN** the DirectionalLight3D is configured
- **THEN** `light_angular_distance` is set to 1.1

### Requirement: Shadow blur preserved
The DirectionalLight3D SHALL retain `shadow_blur = 0.9` to maintain soft shadow edges appropriate for the game's visual style.

#### Scenario: Shadow blur configuration
- **WHEN** the DirectionalLight3D is configured
- **THEN** `shadow_blur` is set to 0.9

### Requirement: Shadow map resolution
The project SHALL default to a shadow map resolution of 4096 for the directional light. The resolution SHALL be selectable through the active graphics preset's shadow quality, with 4096 as the default when no override is active.

#### Scenario: Shadow map size configuration
- **WHEN** the project settings are loaded with no graphics preset override
- **THEN** `rendering/lights_and_shadows/directional_shadow/size` is 4096

#### Scenario: Shadow map size follows shadow quality
- **WHEN** the active graphics preset selects a lower shadow quality
- **THEN** the directional shadow map resolution follows the selected shadow quality
