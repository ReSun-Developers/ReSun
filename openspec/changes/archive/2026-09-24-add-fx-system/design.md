## Context

ReSun has no visual-effects layer. `plans/9-2_final_polish.md` records
zero particle systems; `WeaponData.attached_particle_system`,
`WarheadData.hit_animation`/`kill_animation`, `ProjectileData.graphic_name`, and
`EntityData.death_explosion_ids` are schema-only with no consumers. This change
introduces the reusable foundation plus an MVP: a Light Infantry muzzle flash
and a warhead-driven "bullet hit" effect.

Constraints discovered while tracing the codebase:

- **Pixel-art rendering.** `PixelArtManager` renders the world through a 960×540
  orthographic `SubViewport` (camera `cull_mask = 0b01`), upscaled with
  `TEXTURE_FILTER_NEAREST`. FX must use visual layer 1 and nearest filtering to
  match the look.
- **Fog is depth-based.** `FogRenderer` lifts an opaque shroud sheet
  (`40 * HEIGHT_STEP` ≈ 32.6 world units) and lets the depth pass occlude
  ground-level objects; units/buildings are additionally culled in
  `UnitMeshRenderer`/`FogRenderer`. A tall FX in a shrouded cell could poke
  through the sheet, so FX need explicit gating.
- **Damage has one choke point.** `HitboxComponent.receive_damage_source` →
  `HealthComponent.take_damage` → `damage_taken(damage_type)` →
  `EntityFactory._on_entity_damaged`, which already resolves the warhead for
  impact sound. This covers projectile and hitscan paths.
- **Data-driven conventions.** Typed `Resource` data referenced directly (e.g.
  `EntityData.art_data`, `AnimClipData`) plus autoload services
  (`AudioManager`, `EntityFactory`, `TerrainCatalog`). String-id registries exist
  for legacy `.ini`-derived data (warheads, projectiles); new FX data has no
  legacy id, so direct typed references fit better.

## Goals / Non-Goals

**Goals:**
- A reusable `FxData` resource: one `.tres` per effect, two primitives (animated
  sprite billboard, GPU particles), with animated-texture (PNG sequence /
  sprite-sheet) support.
- An `FxSystem` autoload that plays one-shot effects deterministically and gates
  them against fog of war.
- Wire `muzzle_fx` on weapons and `impact_fx` on warheads.
- Content for the Light Infantry muzzle flash and the small-arms "bullet hit".
- An AssetBrowser preview so effects are authorable without guessing.

**Non-Goals:**
- Persistent/looping effects, fire, burning, damage-over-time (issue #457).
- Projectile flight FX, entity death FX, projectile ground-impact FX.
- FX instance pooling / spawn-stutter work (issue #456).
- Composite/layered effects, scorch decals, terrain deformation, screen shake,
  damage flash overlays.
- Importing the full Tiberian Sun art set.

## Decisions

### D1 — Two primitives mapped to native Godot nodes
`FxData.kind` selects either an `AnimatedSprite3D` (`SpriteFrames`) or a
`GPUParticles3D`. The Tiberian Sun hit puff is fundamentally a short animated
sprite; fire/smoke/sparks are particle work. Mapping each to the engine's native
node keeps behavior (one-shot, billboard, sheet animation) free.

*Alternatives:* a single custom shader solving both; a `PackedScene` per effect.
A custom shader reinvents `SpriteFrames` and particle animation. A scene per
effect contradicts the "one `.tres` per effect" requirement, though `FxData`
could later gain an optional scene kind without breaking the schema.

### D2 — Embed native sub-resources, do not mirror parameters
`FxData` embeds a `SpriteFrames`, a `ParticleProcessMaterial`, and a
`StandardMaterial3D` (all `.tres`-serializable) instead of re-declaring dozens
of particle/material properties. `FxData` only carries lifecycle scalars
(`id`, `kind`, `duration`) and the few node-level knobs
(`amount`, `lifetime`, `explosiveness`, `local_coords`, `pixel_size`,
`modulate`). There is deliberately no `one_shot` field: every effect this change
plays is one-shot, and persistent/looping effects belong to #457.

*Alternatives:* mirror every `ParticleProcessMaterial` property as an exported
field (huge, drifts from the engine); reference a separate `.tscn` (not a
`.tres`). Embedding keeps effects self-contained in one file and reuses the
Redot inspector for the heavy parameters.

### D3 — Direct `FxData` references, no id catalog
`WeaponData.muzzle_fx` and `WarheadData.impact_fx` are typed `FxData` references.
Resources cascade-load through `EntityData` → `WeaponData`/`GlobalRules`, so no
scanner or registry is required, and assignment is visible in the inspector.

*Alternatives:* an `FxCatalog` autoload id→`FxData` scanner like `AudioManager`.
That indirection exists for legacy `.ini` string ids; FX has none, so it adds a
lookup and a second source of truth for no benefit.

### D4 — Deterministic duration timer for cleanup
`FxSystem.play` frees a one-shot via a per-frame lifetime accumulator on the
autoload: it records `duration` (or a value derived from the effect — total
sprite frame time; for particles a ceiling of `2 * lifetime`, which bounds the
emission spread for any `explosiveness`) and decrements in `_process`. GPU
`PARTICLES.finished` is connected as an accurate early-out in-game but is not
relied on (it does not fire under the headless dummy renderer). A
`SceneTreeTimer` is not observable from the synchronous test runner; the
accumulator is deterministic, testable by driving `_process` directly, and gives
one owner for later pooling (issue #456).

*Alternatives:* free only on `finished` (untestable headless, can leak if
emission never finishes); a `SceneTreeTimer` per effect (engine-managed, but not
synchronously testable and one object per effect); never free (leaks).

### D5 — Warhead impact fires from the damage choke point
`EntityFactory._on_entity_damaged` resolves the warhead and plays `impact_fx` at
the victim. This is the single point both projectile and hitscan damage pass
through and already hosts the warhead impact sound.

*Alternatives:* play from `ProjectileController.impacted` (misses hitscan, which
never creates a projectile) plus a hitscan call site (two places to keep in
sync); play from `HitboxComponent` (wrong layer). The choke point is the
root-cause location.

### D6 — Fog gating at spawn plus freeze on transition
`FxSystem.play` skips spawning when the effect's cell is not visible to the local
player (`ShroudSystem.is_cell_visible_to_local`), but only when a shroud grid
exists (`ShroudSystem.is_grid_ready()`): scenes without a grid (pre-boot, editor)
must not suppress effects. Each live effect subscribes to
`ShroudSystem.state_changed`; when its cell leaves local visibility it freezes
(sprite paused, particle processing stopped), and resumes when visible again.
A frozen effect's total age is still accumulated and it is freed at a bounded
retention cap, so an unrevealed cell cannot retain effects forever. With fog
disabled, no gating applies.

*Alternatives:* rely on the shroud depth sheet only (tall FX leak intel); poll
every effect every frame (needless cost). Cell granularity is the shroud's own
resolution, so it matches the grid the player sees.

### D7 — `FxSystem` as an autoload
An autoload service mirrors `AudioManager`/`EntityFactory`, is globally reachable
from `CombatComponent` and `EntityFactory`, and gives one owner for the effect
pool later (issue #456). Registered after `GameContext` in `project.godot`.

*Alternatives:* static helper class (no lifecycle/tree access model); a scene
node in each map (duplicated wiring).

### D8 — MVP bullet-hit authoring
The "bullet hit" is a SPRITE effect: a short (≈0.15–0.3 s) nearest-filtered
billboard, scaled to roughly one cell, with a few frames that flare outward and
fade. It is spawned once per damaging hit at the victim, matching the
Tiberian Sun look of a flat burst that reads at a glance. The muzzle flash is a
brief effect at the muzzle transform (sprite or particle decided during
authoring; the schema supports both).

### D9 — AssetBrowser preview, not AssetPreview
`AssetPreview` is deprecated; the preview is added to the `AssetBrowser` as an
`FxData` category that plays the effect on the preview stage with a replay
action.

## Risks / Trade-offs

- **Headless rendering.** GPU particles cannot be visually asserted in the test
  runner → tests assert node type, materials, and transforms, and rely on the
  deterministic timer for lifecycle.
- **Freeze extends a one-shot's wall-clock life.** A short effect frozen by fog
  resumes later; for MVP this is acceptable and matches "don't render under
  fog". Retention is bounded by a frozen-age cap so an unrevealed cell cannot
  leak effects. → Documented in the spec.
- **Per-effect `state_changed` connections.** Chained combat could connect many
  short-lived effects → MVP authoring keeps effect counts low; revisit with
  pooling (#456) if it shows.
- **Sprite scale/pixel alignment.** `pixel_size` must match the game's pixel
  scale or sprites look off → tune one sprite effect first, reuse the value.
- **Embedded sub-resources inflate `.tres` size.** Acceptable for a handful of
  effects; split to separate resources only if a shared material is reused.
- **Warhead impact position is the victim center.** A projectile's precise
  detonation point is not carried on `damage_taken`; offsetting to the impact
  point is deferred unless the signal is extended.

## Migration Plan

- **Additive only.** No field, scene, or requirement is removed or renamed.
  `project.godot` gains one autoload; existing resources are unaffected
  (`muzzle_fx`/`impact_fx` default `null`).
- **Content rollout.** Add `games/ts/fx/*.tres` + textures, then assign
  `muzzle_fx` on the Light Infantry weapon (`minigun.tres`) and `impact_fx` on
  the small-arms warhead (`sa.tres`). The rest of the roster stays effectless
  until authored.
- **Rollback.** Remove the autoload registration and the two data fields; effects
  are then never spawned. No data migration required.
- **Archive.** CI rejects open changes, so the change is archived after merge.

## Open Questions

- Should warhead impact FX use the victim's center or a per-warhead offset for
  tall structures? (Lean center for MVP.)
- Local visibility for FX caused by remote players' hits is gated by the local
  player's own shroud — confirm this matches the intended read of fog.
- Does the bullet-hit effect need a ground-plane orientation (flat decal burst)
  in addition to a billboard? The described TS look is billboard-flat; revisit
  if it reads wrong from the isometric angle.
