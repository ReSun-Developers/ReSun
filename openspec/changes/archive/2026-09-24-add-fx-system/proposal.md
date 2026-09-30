## Why

ReSun has no visual-effects system. `plans/9-2_final_polish.md` records
zero particle systems, and fields such as `WeaponData.attached_particle_system`
and `WarheadData.hit_animation` are schema-only with no consumers. Every shot is
visually silent and every hit has no impact feedback, so combat reads as
placeholder. A data-driven FX layer is the prerequisite for all later effects
work (explosions, fire, smoke).

This change delivers a practical MVP: a **muzzle flash** for the Light
Infantry's carbine and a flat, short-lived **"bullet hit"** effect driven by the
warhead, plus the reusable `FxData`/`FxSystem` foundation underneath them.

## What Changes

- Add `FxData` (`.tres`) — one resource per effect, two primitives:
  - **SPRITE**: animated billboard (`AnimatedSprite3D` + `SpriteFrames`) for PNG
    sequences and sprite sheets (the Tiberian Sun-style hit puffs / explosions).
  - **PARTICLES**: `GPUParticles3D` with an embedded `ParticleProcessMaterial`
    and `StandardMaterial3D` (no mirroring of particle parameters).
- Add an `FxSystem` autoload: `play(fx, global_transform)` spawns a one-shot
  effect in the gameplay scene and frees it through a deterministic duration
  timer (no dependency on the GPU `finished` signal).
- Fog of war: effects SHALL NOT spawn in shroud or fog for the local player, and
  an active effect whose cell becomes fogged SHALL freeze until revealed again.
- Assignment fields: `WeaponData.muzzle_fx` and `WarheadData.impact_fx`, both
  typed `FxData`.
- Triggers: `CombatComponent` plays `weapon.muzzle_fx` at the muzzle transform
  on each shot; `EntityFactory._on_entity_damaged` plays `warhead.impact_fx` at
  the victim for every damaging hit (covers projectile and hitscan paths).
- Asset browser: preview an `FxData` effect on a dummy target.
- MVP content: the Light Infantry carbine muzzle flash and a flat, ~1-cell,
  very-short "bullet hit" warhead effect.
- Tests: unit (`FxData` validation, `FxSystem` kind selection, lifecycle,
  fog gating) and integration (muzzle on fire, impact on damaging hit).

## Capabilities

### New Capabilities
- `fx-system`: the `FxData` resource schema and `FxSystem` one-shot playback —
  effect-kind selection, animated-texture support, deterministic lifecycle,
  fog-of-war gating, and the `FxData` assignment points on combat data.

### Modified Capabilities
- `combat-firing`: play `WeaponData.muzzle_fx` at the muzzle transform on each
  successful weapon dispatch.
- `entity-factory`: play `WarheadData.impact_fx` at the victim on a damaging hit.
- `asset-browser`: preview `FxData` effects on a dummy target.

## Impact

- **New code**: `scripts/data/FxData.gd`, `scripts/core/FxSystem.gd` (+ `.uid`),
  registered as an autoload in `project.godot`; `games/ts/fx/` effect resources.
- **Modified data**: `WeaponData.muzzle_fx`, `WarheadData.impact_fx`.
- **Modified scripts**: `scripts/components/CombatComponent.gd` (muzzle spawn),
  `scripts/entities/EntityFactory.gd` (warhead impact spawn), asset-browser
  preview controller (effect mode).
- **Content**: muzzle flash + bullet-hit `.tres` and their textures; the Light
  Infantry weapon `.tres` gains `muzzle_fx`; the small-arms warhead gains
  `impact_fx`.
- **Compatibility**: additive only — no existing scene, resource field, or
  requirement is removed or renamed. FX render on default layer 1 so the
  low-res pixel-art viewport (`PixelArtManager`) draws them; they reuse the
  existing `AudioManager` through the callers that already own sounds, so
  `FxData` adds no audio field.
- **Deferred** (separate changes/issues): projectile flight FX, entity death FX,
  persistent fire/burning (#457), FX pooling (#456), composite/layered effects,
  scorch decals, screen shake.
