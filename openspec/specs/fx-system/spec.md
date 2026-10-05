# fx-system Specification

## Purpose

Data-driven one-shot visual effects. `FxData` describes a single effect as a `.tres` — an animated billboard (`SPRITE`, via `SpriteFrames`) or a GPU particle system (`PARTICLES`, with embedded process/draw materials) — and the `FxSystem` autoload plays it, owns its deterministic lifetime, and gates it against fog of war. Weapons reference a muzzle effect (`WeaponData.muzzle_fx`) and warheads an impact effect (`WarheadData.impact_fx`) by direct `FxData` reference.

## Requirements

### Requirement: FxData resource class
The system SHALL provide an `FxData` resource class (`scripts/data/FxData.gd`, `class_name FxData extends Resource`) describing a single one-shot visual effect. It SHALL expose `id: String`, `kind: Kind` with `enum Kind { SPRITE, PARTICLES }`, and `duration: float` (default `0`, meaning derive from the effect). Every field SHALL have a sensible default so unused properties can be ignored. SPRITE effects SHALL expose `sprite_frames: SpriteFrames`, `animation: StringName`, `pixel_size: float`, and `modulate: Color`. PARTICLES effects SHALL expose `process_material: ParticleProcessMaterial`, `draw_material: StandardMaterial3D`, `amount: int`, `lifetime: float`, `explosiveness: float`, `spawn_duration: float` (default `0`), and `local_coords: bool`. The effect SHALL carry no audio field; callers retain their existing sound fields (`WeaponData.sound_report`, `WarheadData.sound_impact`, `EntityData.sound_die`).

#### Scenario: Create a sprite effect
- **WHEN** an `FxData` is created with `id = "ExplosionSmall"`, `kind = Kind.SPRITE`, and a `SpriteFrames` value
- **THEN** the resource exposes those values with defaults for every particle field

#### Scenario: Create a particle effect
- **WHEN** an `FxData` is created with `id = "MuzzleFlashSmall"`, `kind = Kind.PARTICLES`, a `ParticleProcessMaterial`, and a `StandardMaterial3D`
- **THEN** the resource exposes those values with defaults for every sprite field

### Requirement: FxData animated texture support
For SPRITE effects, `FxData` SHALL support animated texture data through `SpriteFrames`, covering both a PNG sequence (one texture per frame) and a sprite-sheet grid (frames referencing atlas regions). Playing the effect SHALL advance the frames at the `SpriteFrames` animation's configured speed. A sprite effect SHALL be rendered as a billboard so it faces the camera from the game's isometric view.

#### Scenario: PNG sequence effect
- **WHEN** a SPRITE effect's `SpriteFrames` animation contains one texture per frame
- **THEN** playing the effect advances through those frames and displays them in order

#### Scenario: Sprite-sheet effect
- **WHEN** a SPRITE effect's `SpriteFrames` animation contains frames referencing regions of a single sheet texture
- **THEN** playing the effect displays each region in order

#### Scenario: Billboard facing
- **WHEN** a SPRITE effect is spawned
- **THEN** its sprite is billboarded to face the camera

### Requirement: FxData validation
`FxData` SHALL expose `validate() -> PackedStringArray` reporting an error when `id` is empty, when `kind == Kind.SPRITE` and `sprite_frames` is null, and when `kind == Kind.PARTICLES` and `process_material` is null. A fully specified effect SHALL return an empty array.

#### Scenario: Empty id fails
- **WHEN** `validate()` is called on an `FxData` whose `id` is `""`
- **THEN** the returned array is non-empty and names the empty id

#### Scenario: Sprite effect missing frames fails
- **WHEN** `validate()` is called on a SPRITE effect with null `sprite_frames`
- **THEN** the returned array reports the missing sprite frames

#### Scenario: Particle effect missing process material fails
- **WHEN** `validate()` is called on a PARTICLES effect with null `process_material`
- **THEN** the returned array reports the missing process material

#### Scenario: Valid effect passes
- **WHEN** `validate()` is called on a SPRITE effect with an id and sprite frames, or a PARTICLES effect with an id and process material
- **THEN** the returned array is empty

### Requirement: FxSystem autoload and playback

The system SHALL provide an `FxSystem` autoload exposing `play(fx: FxData, global_transform: Transform3D) -> Node3D`. `play` SHALL instantiate the effect node, parent it to the match World root (falling back to the caller's scene root when no World root exists, so headless tests and the map editor still get a valid parent), place it at `global_transform`, and return the node. A null `fx` or one that fails `validate()` SHALL log a warning and return `null` without adding a node.

#### Scenario: Play adds a node

- **WHEN** `play` is called with a valid `FxData` and a transform during a match
- **THEN** a node exists under the match World root at that transform and is returned

#### Scenario: Null effect is a no-op

- **WHEN** `play` is called with `null`
- **THEN** no node is added, a warning is logged, and `null` is returned

#### Scenario: Play without a World root still spawns

- **WHEN** `play` is called where no match World root exists
- **THEN** the effect is parented to the available scene root and is returned, with no node dropped

#### Scenario: Cleanup on map change

- **WHEN** a match is replaced while one-shot effects are alive
- **THEN** those effects are released with the outgoing match's World root and no orphan nodes remain

### Requirement: Effect kind selection and build
`FxSystem.play` SHALL build different nodes per `FxData.kind`. For `Kind.SPRITE` it SHALL create an `AnimatedSprite3D`, assign `sprite_frames`, play `animation`, set `pixel_size` and `modulate`, enable billboard, and use nearest texture filtering. For `Kind.PARTICLES` it SHALL create a `GPUParticles3D`, assign `process_material` and `draw_material`, set `amount`, `lifetime`, `explosiveness`, and `local_coords`, set the node to one-shot when `spawn_duration` is `0` (looping it for the spawn window otherwise), connect the node's `finished` signal as an early-free, and start emitting after the hook is connected. A PARTICLES `draw_material` SHALL set `vertex_color_use_as_albedo` so the process material's `color` / color-ramp reaches the pixels.

#### Scenario: Sprite effect builds an animated sprite
- **WHEN** `play` is called with a SPRITE `FxData`
- **THEN** an `AnimatedSprite3D` is created with the effect's frames playing the named animation

#### Scenario: Particle effect builds a GPU emitter
- **WHEN** `play` is called with a PARTICLES `FxData`
- **THEN** a `GPUParticles3D` is created with the effect's process material, draw material, amount, lifetime, and explosiveness

### Requirement: One-shot effect lifecycle
A one-shot effect SHALL free itself on a deterministic timer, with the GPU `finished` signal (PARTICLES) as an optional early-out: `duration` when greater than zero, otherwise a value derived from the effect. For SPRITE the derived value SHALL be the total sprite frame time. For PARTICLES the derived value SHALL be `spawn_duration + lifetime` when `spawn_duration` is greater than zero — the spawn window plus the last particle born into it — and otherwise a ceiling of twice `lifetime`, covering the emission spread for any `explosiveness` and the full lifetime of the last particle. The timer SHALL remain the authoritative cleanup path so behavior is identical headless and with rendering disabled.

#### Scenario: Auto-free on duration
- **WHEN** a one-shot effect with `duration = 0.2` is played
- **THEN** its node is freed after approximately 0.2 seconds

#### Scenario: Sprite duration derived
- **WHEN** a SPRITE effect has `duration = 0.0` and a `SpriteFrames` animation lasting 0.3 seconds
- **THEN** its node is freed after approximately the animation length

#### Scenario: Particle duration derived as a ceiling
- **WHEN** a PARTICLES effect has `duration = 0.0` and `lifetime = 1.5`
- **THEN** its node is freed after approximately 3.0 seconds, so no particle is cut off

#### Scenario: Spawn window outlives a single particle
- **WHEN** a PARTICLES effect has `duration = 0.0`, `spawn_duration = 0.3`, and `lifetime = 0.075`
- **THEN** the emitter keeps spawning for approximately 0.3 seconds and its node is freed after approximately 0.375 seconds, so no particle is cut off

#### Scenario: Particle finished is an early-out
- **WHEN** a PARTICLES effect's engine `finished` signal fires before its timer elapses
- **THEN** its node is freed at that point

### Requirement: Fog-of-war gating of effects
`FxSystem` SHALL NOT spawn an effect whose cell is not currently visible to the local player (`ShroudSystem.is_cell_visible_to_local`) when a shroud grid is initialized (`ShroudSystem.is_grid_ready()`). Before a grid exists, effects SHALL NOT be gated. While an active effect's cell is not visible to the local player, the effect SHALL freeze (pause sprite playback and stop particle processing) rather than render; when the cell becomes visible again the effect SHALL resume. A frozen effect SHALL still be freed once its total age reaches a bounded retention cap, so an unrevealed cell cannot retain effects forever. When fog of war is disabled, effects SHALL always be visible and never gated. This requirement applies to both effect kinds.

#### Scenario: No spawn under shroud
- **WHEN** `play` is called at a cell that is not visible to the local player and a shroud grid is ready
- **THEN** no effect node is added

#### Scenario: No grid is ungated
- **WHEN** no shroud grid has been initialized and `play` is called anywhere
- **THEN** the effect spawns

#### Scenario: Freeze when the cell becomes fogged
- **WHEN** an active effect's cell transitions to not visible to the local player
- **THEN** the effect stops animating/processing and renders nothing until the cell is visible again

#### Scenario: Resume on reveal
- **WHEN** a frozen effect's cell becomes visible to the local player again
- **THEN** the effect resumes animating/processing

#### Scenario: Frozen retention is bounded
- **WHEN** an effect is frozen by fog and its cell never becomes visible
- **THEN** it is still freed once its total age reaches the retention cap

#### Scenario: Fog disabled is ungated
- **WHEN** fog of war is disabled and `play` is called anywhere
- **THEN** the effect spawns and is visible

### Requirement: Pixel-art viewport rendering
FX nodes SHALL render on visual layer 1 (the default) so the low-res orthographic pixel-art viewport (`PixelArtManager`, camera `cull_mask = 0b01`) includes them. SPRITE effects SHALL use `TEXTURE_FILTER_NEAREST` so their pixels stay crisp when the viewport is upscaled.

#### Scenario: Effect is in the pixel-art pass
- **WHEN** an effect node is spawned
- **THEN** its visual layer is 1

#### Scenario: Sprite uses nearest filtering
- **WHEN** a SPRITE effect is spawned
- **THEN** its texture filter is nearest

### Requirement: FxData assignment on combat data
`WeaponData` SHALL expose `muzzle_fx: FxData` and `WarheadData` SHALL expose `impact_fx: FxData`, both defaulting to `null` so existing resources are unchanged. A `null` value SHALL mean no effect.

#### Scenario: Default is no effect
- **WHEN** a `WeaponData` or `WarheadData` is created without an FX reference
- **THEN** `muzzle_fx` / `impact_fx` is `null`

#### Scenario: Assigned effect resolves
- **WHEN** a weapon sets `muzzle_fx` and a warhead sets `impact_fx` to `FxData` resources
- **THEN** the references are available to their consumers without a registry lookup

### Requirement: Particle quad size
A PARTICLES `FxData` SHALL expose `quad_size: float` (default `0.1`) giving the world-space edge length of the effect's particle quad. `FxSystem` SHALL size the `GPUParticles3D` draw quad from `quad_size` so particle effects are authored in world units instead of the `QuadMesh` default of one metre. The process material's `scale_min` / `scale_max` SHALL remain a per-particle variation on top of that base size.

#### Scenario: Quad sized from the effect
- **WHEN** a PARTICLES effect with `quad_size = 0.15` is played
- **THEN** its draw-pass `QuadMesh` is sized `0.15` on its width and height

#### Scenario: Default quad is small
- **WHEN** a PARTICLES effect leaves `quad_size` at its default
- **THEN** the built quad is `0.1` on its width and height

### Requirement: Effect point light
An `FxData` MAY carry a light: `light_energy: float` (default `0.0`, meaning no light), `light_color: Color`, and `light_range: float`. When `light_energy > 0.0`, `FxSystem` SHALL add an `OmniLight3D` to the effect node with those values, shadows disabled, on the effect's visual layer. The light SHALL be a child of the effect node so it is freed with the effect and disabled by the fog-freeze visibility toggle. When `light_energy <= 0.0` no light node SHALL be created.

#### Scenario: Light added when enabled
- **WHEN** a PARTICLES effect with `light_energy = 3.0`, a colour, and a range is played
- **THEN** an `OmniLight3D` child exists with that colour, energy, and range and with shadows disabled

#### Scenario: No light by default
- **WHEN** an effect leaves `light_energy` at its default
- **THEN** no `OmniLight3D` is created

#### Scenario: Light dies with the effect
- **WHEN** an effect carrying a light is freed at the end of its lifetime
- **THEN** the light is freed with it and leaves no orphan node

### Requirement: Particle draw shape
A PARTICLES `FxData` SHALL expose `particle_shape: ParticleShape` with
`enum ParticleShape { QUAD, TRIANGLE }` (default `QUAD`). `FxSystem` SHALL build
the `GPUParticles3D` draw primitive accordingly: a `QuadMesh` for `QUAD`, or a
single-triangle `ArrayMesh` for `TRIANGLE`. Both shapes SHALL be sized by
`quad_size` and SHALL use the effect's `draw_material`. The default `QUAD` SHALL
leave existing particle effects unchanged.

#### Scenario: Quad shape builds a quad
- **WHEN** a PARTICLES effect leaves `particle_shape` at its default
- **THEN** its draw pass is a `QuadMesh` sized by `quad_size`

#### Scenario: Triangle shape builds a triangle
- **WHEN** a PARTICLES effect sets `particle_shape = TRIANGLE`
- **THEN** its draw pass is a single-surface `ArrayMesh` (one triangle) with the effect's draw material
