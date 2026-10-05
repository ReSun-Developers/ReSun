# Design

## Context

See `proposal.md` — Why. The World root already exists as a bare `Node3D`
(`scripts/core/World.gd`) created by `MissionBoot._swap_world`, which does
`queue_free()` then `remove_child()` so the previous root's `_exit_tree` runs
synchronously before the incoming root is added. Runtime spawners still resolve
`get_tree().current_scene` (`Main`) or create `Main/Buildings`, so the swap does
not release them. The existing `current_scene` fallbacks exist because many unit
tests spawn with no real `MainScene`; any seam must keep those tests working.

## Goals / Non-Goals

**Goals:**
- One access seam and one spawn entry point for all runtime content, so future
  spawn producers (scripted teams, reinforcements) cannot invent a new parent path.
- A container layout under `World` that gives teardown, debug tooling, and future
  save/load one bounded subtree to walk.
- Preserve headless/editor spawning where no World exists.

**Non-Goals:**
- No match-end / return-to-menu flow (separate change; the acceptance path starts a
  second match, not ends one).
- No per-player or per-team nesting under `World` yet (add when multiplayer or
  save/load actually enumerates per-player content).
- No data-driven draw-layer field. Z-order/rendering stays a separate concern from
  ownership; introducing a render-layer attribute is future work, not a container
  decision.
- No autoload moves, no node pooling.

## Decisions

### D1 — One accessor plus one `spawn` entry point on `World`

`scripts/core/World.gd` gains `class_name World`, a static accessor that resolves
the live match root (set in `_enter_tree`, cleared in `_exit_tree`, with a validity
guard for a freed/outgoing root), and a static `spawn_container(bucket, fallback)`
plus an instance `spawn(node, bucket)`. Every spawner resolves its destination
through this rather than choosing a parent scene. This mirrors the existing
`SpatialHash.instance` / `CellReservation` convention, which are autoloads with a
`static var instance`; `World` is a scene node with a `static var _active` and the
same shape.

Alternatives considered:

- **Scene-path lookup (`current_scene/Gameplay/World`)** — rejected: the path does
  not exist in headless tests and duplicates the owner's location across callers.
- **A `GameContext.active_world` field** — rejected: `GameContext` owns content
  selection, not match scene structure; it would need two extra set/clear touch
  points and mixes concerns (design D4 of the World-root change argued against
  widening it).
- **Group lookup as the primary seam** — rejected as primary: `O(n)` and ambiguous
  if two roots ever coexist; kept only as a debug cross-check.
- **A static `instance` on each spawner** — explicitly rejected by the issue; one
  accessor is the point.

### D2 — Two lifetime buckets under `World`, classified by `entity_type`

The map is parented directly under `World` (unchanged), and `spawn()` routes
runtime content to one of two lazily-created containers:

```
World
├── MissionMap   (authored map; parented directly by MissionBoot, as today)
├── Entities     (runtime units, structures, terrain/overlay, deployed forms, grown resources)
└── Effects      (projectiles, one-shot effects)
```

Classification is carried by the entity's existing `entity_type`, not by the node
path — there is no folder per gameplay category and no separate "Resources"
container. Tiberium is an `OVERLAY` and trees are `TERRAIN`; both are runtime
entities and belong under `Entities`. A `Map` bucket was considered and dropped:
`MissionBoot` parents the map directly and no runtime spawner targets it, so a
`Map` category would be dead and would break `world.get_node_or_null("MissionMap")`
consumers. The buckets exist for bounded teardown/serialization walks, not for
classification; if a future save/load needs per-`entity_type` enumeration it can
segment `Entities` then.

The runtime-created `Main/Buildings` container is removed. Player-built structures
parent to `World/Entities`; the dead `Buildings` node in `MapBase01.tscn` (map
entities parent to `MissionMap` directly, so it is unused) is deleted.

### D3 — Validity guard, fallback, and swap-frame behavior

`spawn_container()` validates the resolved root
(`is_instance_valid && is_inside_tree() && not is_queued_for_deletion()`) and falls
back to an explicit caller-supplied parent, then `current_scene`, then
`tree.root`. This keeps headless tests and the map editor spawning without
branching at every call site and without dropping content. Because `queue_free()`
frees at frame end, `MissionBoot` keeps the `queue_free()` + `remove_child()` pair
so `_exit_tree` runs synchronously; the accessor's validity check makes a stale
reference read as invalid rather than dangling.

A spawn issued from a callback strictly during the swap window (between
`remove_child(previous)` and `add_child(world)`) can resolve to the fallback root,
not the incoming World. Order-time binding of the owning match is the correct fix
for that class of callback, but it is out of scope here; the spec guarantees only
that spawns **after** the swap resolve to the incoming match (which the accessor
gives for free once the new World enters the tree).

### D4 — `ResourceGrowthSystem` resolves its parent per spawn

Drop the cached `_resource_parent` (populated once from the first tree's parent) and
resolve the container through the seam at each spawn. The cache points at a freed
node after a match boundary, so `_spawn_at_cell` currently warns and stops growth
on the second match. This is the same seam, and folding it converts a real
match-boundary bug into coverage.

### D5 — Teardown test without frame awaiting

The test runner (`test/run_tests.gd`) calls each `test_` method synchronously and
does not await coroutines, so a test cannot `await tree.process_frame`. The proof
therefore asserts what `_swap_world` guarantees synchronously: after the second
`start_mission`, every node recorded from match 1 is `not is_inside_tree()` and the
outgoing World root `is_queued_for_deletion()`. Actual reaping happens at frame end,
which the runner does not need to observe for the release guarantee. Nodes are
recorded explicitly from the real production paths the test drives
(`EntityPlacer.place_entity` via `FactoryComponent`/`ProductionManager`,
`CombatComponent` fire, `FxSystem.play`, and a resource spawn), and a non-empty
guard prevents a vacuous pass.

## Risks / Trade-offs

- **Tests that rely on `current_scene` placement** → the fallback preserves their
  behavior; the resource-growth test is reworked to add a World and inspect its
  `Entities` bucket instead of poking a removed field.
- **Removing `MapBase01/Buildings`** → grep-verified nothing references it by name,
  group, or path; note `TestMap01.tscn` uses child-index overrides on the instance,
  so removing a child shifts indices (task checks it).
- **Static accessor leaking across the shared test process** → validity check in
  the accessor self-heals a freed/orphaned root; tests that create a World remove
  it.
- **BuildingManager's cached container across a swap** → `_get_buildings_parent`
  re-resolves when its cached node is invalid or out of tree.
- **Single-match behavior change** → guarded by the existing integration suite and
  a `test_match_swap` assertion that the second-match World still hosts
  `MissionMap`.

## Migration Plan

1. Add the accessor + `spawn_container`/`spawn` + buckets to `World.gd`.
2. Repoint `EntityPlacer` (`place_entity` and `start_preview`) and `FxSystem`, then
   `CombatComponent`, then `BuildingManager`/`DeployComponent`, then
   `ResourceGrowthSystem`.
3. Remove the dead `Buildings` node from `MapBase01.tscn`.
4. Rework the resource-growth test fixture and extend the teardown test.

Rollback: the change is additive except for the scene-node removal and parent
repointing; reverting `World.gd` and the call sites restores the previous tree.

## Open Questions

- Whether `World/Entities` should later split per player/team is deferred until
  multiplayer or save/load needs deterministic per-player enumeration; it does not
  change the seam or the specs now.
