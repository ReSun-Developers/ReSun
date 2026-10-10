# Design

## Context

See `proposal.md` for motivation. Two current properties shape the approach:

- **Insertion is duplicated.** `EntityFactory.create_entity` assembles an entity but stops
  before the tree; twelve call sites repeat `add_child` plus position, player assignment,
  group membership, and registration. The routines diverge, and each caller re-derives
  which registries to touch. The twelfth is `BuildingManager._create_building_preview`.
- **Registration is split and implicit.** `FoundationComponent` registers occupancy on
  `_ready`/`_exit_tree`, but `place_building` and `_do_deploy` *also* register cells by
  hand; `BuildingManager` owns `_buildings` and prerequisite counts; deployed buildings are
  wired to prerequisites but not to death cleanup; map-loaded buildings bypass the registry
  and prerequisites entirely. Preview suppression uses three different mechanisms. The
  `_preview` meta is read by five consumers: `FoundationComponent`, `UnitMeshRenderer`
  (`_can_register` and `_physics_process`), `GuardComponent`, `FreeUnitComponent`, and
  `FogRenderer`.

Two ordering facts constrain any seam:

```
player_id  MUST be set before add_child   → MovementController._ready caches it (crush filter)
position   MUST be set before add_child   → FoundationComponent._ready derives the origin cell
```

Callers also do essential work **after** insertion that the seam must leave intact:
`EntityPlacer` assigns the movement sub-slot; `MapLoader` applies rotation-with-slope,
`house_id` meta, and health overrides; `DeployComponent` applies the state snapshot and a
pending move; `place_building` flattens terrain, plays build-up, and resumes production.

## Goals / Non-Goals

**Goals:**

- A single insertion seam, `EntityFactory.spawn`, that all twelve sites call.
- Occupancy registered exactly once per building, by one owner, for every source.
- One detached marker replaces the `_preview` flag everywhere, set only by the seam.
- Every building — runtime, map-loaded, deployed — registered identically and
  owner-scoped, so a pre-placed building owned by a player is sellable by that player.

**Non-Goals:**

- Map JSON / editor save format changes.
- Replacing the building registry or prerequisite counters with live world queries
  (a larger, behavior-adjacent follow-up).
- Changing trigger semantics: only runtime placement notifies the "built" triggers.
- Changing repair behaviour (repair consumes no credits and is not owner-scoped here).
- Unifying the two preview *renderers* (`BuildingManager` schematic vs placement ghost);
  only their registration behaviour is unified.

## Decisions

### D1: `spawn` owns assembly and insertion, not domain registration

`spawn(entity_id, placement)` assembles (reusing the existing `create_entity` path),
assigns `player_id` and `world_pos` before insertion, attaches under `placement.parent`
(defaulting to `World.spawn_container(ENTITIES)`, then the current scene), and emits a
spawn event. Callers keep policy: cost, `can_place`, `flatten_footprint`, build-up
animation, map rotation/deck height, health overrides, and their post-insertion steps.

- **Why:** the duplicated part is insertion; the divergent part is policy. Centralizing
  registration *inside* `spawn` would force the global `EntityFactory` autoload to call
  `BuildingManager` and `PrerequisiteSystem` directly, coupling the factory to gameplay
  systems that are slated to become per-map children (the match `World`).
- **Alternative rejected:** a "thick" `spawn` that calls registries directly — couples
  the factory to gameplay systems; **alternative rejected:** a registrar `Callable` passed
  per call — spreads policy back across callers.

### D2: Keep occupancy registration in `FoundationComponent`; one detached marker suppresses it

`FoundationComponent` continues to register on entry and unregister on exit (its current
lifecycle), but the duplicate `register_building_cells`/`register_bib_cells` calls in
`place_building` and `_do_deploy` are deleted. It skips registration when the entity
carries the detached marker.

- **Why:** registration and unregistration are naturally symmetric around the node
  lifecycle, and the component already owns the exact cell set it registers. Moving this
  into `spawn` would orphan `_exit_tree` cleanup and require re-deriving the cell set.
- **Alternative rejected:** moving registration into `spawn` and removing `_ready` —
  breaks the symmetric teardown and the tests that construct a raw `FoundationComponent`.

### D3: Uniform registration driven by one spawn event, owner-scoped

`EntityFactory` emits `spawned(entity, data, player_id)` when a non-detached entity enters
the world. `BuildingManager` connects once and, for building entities, performs the
registry insert: append `{node, type, origin, cells}` to `_buildings` (with `cells` =
`FoundationComponent.occupied_cells(foundation, bib_cells, origin)`, i.e. bib-excluded),
register the building for `player_id` in `PrerequisiteSystem`, and connect `health_zero`
to `_on_building_destroyed`. `place_building` therefore drops its own `_buildings.append`
and its `health_zero` connect; it keeps cost, flatten, build-up, and the `building_placed`
emit.

- **Why:** one owner, one trigger, every source. Map-loaded and deployed buildings get the
  same registration as runtime placements without each caller calling three systems.
  Scoping to the entity's `StatsComponent.player_id` fixes the current local-player
  assumption.
- **Alternative rejected:** manual `register_building_entity` calls at each caller —
  reproduces the twelve-site problem; **deferred:** deriving registries live from the world
  actor set — removes registration entirely but is a larger change to progression.

### D4: Registration is separate from trigger notification

The registry insert is driven by the spawn event; the trigger-facing `building_placed`
signal is still emitted only by `place_building` (runtime placement). Map-authored and
detached entities neither register for triggers nor fire "built" events.

- **Why:** map-authored structures must not fire mission "built" triggers at boot, and
  registration (occupancy, tech, sell) is a different concern from gameplay events.

### D5: Detached entities live in the tree but are excluded from the world

`placement.detached = true` inserts the entity for rendering but adds no `entities`,
`selectable`, or `drag_selectable` groups, registers no occupancy, assigns no player, and
emits no spawn event. `spawn` applies the detached marker before insertion; all five
`_preview` consumers (`FoundationComponent`, both `UnitMeshRenderer` sites,
`GuardComponent`, `FreeUnitComponent`, `FogRenderer`) recognise it. Every preview and
editor path adopts it, and the per-caller `set_meta("_preview", …)` sites are removed.

- **Why:** a preview must be rendered, so it cannot be kept out of the tree; the marker is
  the minimal shared signal that registration, guard/auto-spawn suppression, fog, and
  multimesh exclusion all read.
- **Alternative rejected:** `PROCESS_MODE_DISABLED` as the registration signal — it is
  also used for input/collision inertness, conflating two concerns; it remains available
  for inertness but is no longer the registration gate.

### D6: Owner-scoped sell behind an acting-player gate

`sell_building` and `_on_building_destroyed` read the building's owner from its
`StatsComponent` (null-guarded) for the refund and the prerequisite unregister instead of
`PlayerManager.get_local_player_id()`. The sell order path is gated so only the acting
(local) player's own buildings can be sold or show the sell cursor; the current generators
check only that a building exists, with no ownership filter.

- **Why:** a pre-placed building owned by a player must be sellable by that player, while
  an enemy or third-party structure must not be. Without the gate, owner-scoping refunds
  and deletes another player's building.
- **Alternative rejected:** restricting sell to the local player only — contradicts the
  requested pre-placed-sellable behaviour.

### D7: Editor loads detach through the shared loader

`MapLoader.load_map_into` gains a detached branch keyed on the parent being the map
editor (detected by its `_painted_entities` content store, not the `is_map_editor` meta
that non-editor callers also set to skip camera framing), so entities loaded into the
editor enter detached and register no occupancy, while gameplay loads register normally.

- **Why:** the loader is shared by gameplay and editor; only the editor must avoid
  polluting the live world.
- **Alternative rejected:** a separate editor loader — duplicates terrain and override
  handling for one flag.

## Risks / Trade-offs

- **[Double registration if a caller is missed]** → delete the manual registration in the
  same task that adds the seam; assert register-call counts or node identity, not set size,
  because `SpatialHash` registration is set-semantics and hides duplicates.
- **[Deploy's bib divergence]** → `_do_deploy` stops registering cells and relies on
  `FoundationComponent`; the registrar stores bib-excluded cells. Covered by the existing
  refinery bib test plus a deploy-specific assertion.
- **[Preview consumers left on the old flag]** → D5 lists all five consumers and the
  migration task updates each and its tests.
- **[Ownership gate omitted]** → the sell order generators are updated in the same task as
  the refund change; a test asserts an enemy building is not sellable.
- **[Spawn event ordering with triggers]** → registration via the spawn event is
  independent of `building_placed`; triggers keep their current wiring.
- **[Test churn]** → the listed tests are rewritten to drive `spawn`/the detached marker,
  not weakened.

## Migration Plan

1. Add `spawn` + detached + the `spawned` signal; leave `create_entity` in place.
2. Migrate the twelve insertion sites (including `BuildingManager._create_building_preview`)
   to `spawn`; delete the manual cell/registry/death-wiring registration in `place_building`
   and `_do_deploy`.
3. Add the uniform registrar in `BuildingManager`; gate sell to the acting player and scope
   refund/unregister to the owner.
4. Migrate the five `_preview` consumers to the detached marker; detach editor preview,
   stamp, and load paths.
5. Rewrite affected tests; update `GLOSSARY.md`; run the suite, `gdlint`, and `gdformat`.

Rollback is a revert of the branch; the seam is additive until step 2, so a partial revert
is safe.

## Open Questions

- Whether to later replace `_buildings` and the prerequisite counters with live world-set
  queries (removing registration entirely). Deferrable — it does not change the spec
  deltas, this approach, or the task breakdown, and can land as its own change.
- Whether the map editor should eventually host entities in a distinct editor world rather
  than the live one. Deferrable; the detached marker already covers the registration
  concern.
