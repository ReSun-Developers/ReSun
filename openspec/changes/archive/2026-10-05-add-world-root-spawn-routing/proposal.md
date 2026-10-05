# Proposal

## Why

The per-match World root (`MainScene/Gameplay/World`) exists, but content created
**during** a match still parents to `get_tree().current_scene` (which is `Main`) or
creates a `Main/Buildings` node. A second match therefore inherits produced units,
built structures, projectiles, effects and grown resources from the first, defeating
the teardown guarantee the World root was introduced to provide. Mission boot, the
session shell, the trigger engine and scripted spawns are now in place, so the next
spawn producer (reinforcements/droppods) would invent yet another parent path unless
one shared seam exists first.

## What Changes

- Add a single world-root access seam: the World node resolves the active match root,
  and all runtime spawning goes through one `World.spawn(node, category)` method that
  owns the destination, validates the target, and handles the headless/no-World
  fallback. No per-system `instance` shims.
- Route every runtime spawner through the seam: `EntityPlacer` default parent,
  `BuildingManager` / `DeployComponent` structures, `CombatComponent` projectiles,
  `FxSystem` one-shot effects, and `ResourceGrowthSystem` growth.
- Replace the runtime-created `Main/Buildings` container with a World-owned container.
  Group runtime content under a small set of lifetime buckets (`Entities` / `Effects`);
  classification stays on the entity's `entity_type`, not on the node path (the map is
  parented directly under the World root, as today). **BREAKING**: runtime content's
  parent path changes; code that walks `current_scene` children or expects
  `Main/Buildings` breaks.
- Remove the now-dead `Buildings` node from `MapBase01.tscn`. **BREAKING** for any
  packed scene that references it by path (none do today).
- Fix `ResourceGrowthSystem`'s cached spawn parent, which points at a freed node after
  a match boundary and silently stops resource growth.
- Add a two-phase teardown test that starts two missions on the real `MainScene`,
  spawns/produces content in the first, and asserts none of it survives the swap.

Non-goals: no match-end/return-to-menu flow (tracked separately); no per-player or
per-team nesting; no data-driven draw-layer field (noted in design as future work); no
autoload moves.

## Capabilities

### New Capabilities
<!-- none: this closes a documented gap in an existing capability -->

### Modified Capabilities

- `match-root`: runtime-spawned content (units, structures, projectiles, effects,
  grown resources) SHALL be descendants of the single World root and SHALL be released
  when the match is replaced; the World root SHALL expose the spawn access seam used by
  every runtime spawner.
- `fx-system`: one-shot effects SHALL parent under the match World root instead of
  `get_tree().current_scene`, keeping the existing fallback for trees with no World.
- `projectile-runtime`: projectiles SHALL parent under the match World root instead of
  the gameplay root resolved as `current_scene`.
- `resource-growth-system`: runtime resource spawns SHALL resolve the World root at
  spawn time rather than reusing a cached parent, so growth survives a match boundary
  and is released with the match.

## Impact

- **Scripts:** `scripts/core/World.gd` (accessor + spawn), `scripts/entities/EntityPlacer.gd`
  (`place_entity` default parent and `start_preview`),
  `scripts/buildings/BuildingManager.gd`, `scripts/components/DeployComponent.gd`,
  `scripts/components/CombatComponent.gd`, `scripts/core/FxSystem.gd`,
  `scripts/core/ResourceGrowthSystem.gd`. `FactoryComponent.gd` needs no edit — it routes
  through `EntityPlacer`.
- **Scenes:** `scenes/maps/MapBase01.tscn` (remove dead `Buildings` node);
  `scenes/core/World.tscn` (buckets created lazily, so likely unchanged).
- **Tests:** `test/integration/test_match_swap.gd` (extend to runtime content),
  `test/unit/test_world_root.gd` (accessor + fallback), and the subsystem tests that
  assert parenting: `test_fx_system.gd`, `test_projectile_flight.gd`,
  `test_resource_growth_system.gd`, `test_placing_session.gd`.
- **Specs:** `match-root`, `fx-system`, `projectile-runtime`, `resource-growth-system`.
