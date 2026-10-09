# Design

## Context

See `proposal.md` (Why) for the problem. The relevant current state:

- `PrerequisiteSystem.can_build(player_id, data) -> bool` (`scripts/production/PrerequisiteSystem.gd:46`)
  is the de-facto gate: cheat bypass, tech level, build limit, prerequisite OR, necessary
  prerequisite AND, and an owned-producer check against the player-keyed registry
  `_player_buildings`. It discards the reason.
- The sidebar filters its list through `can_build` (`scripts/ui/Sidebar.gd:252`), so a
  gate-failed cameo never exists; the `build_limit` grey branch (`:404`) is unreachable in
  normal play and under the cheat is bypassed — dead code.
- `CreditCounter._compute_cheapest_cost` (`scripts/ui/CreditCounter.gd:82`) uses
  `data.buildable and cost > 0` over the whole catalog — player-agnostic.
- `ProductionManager.has_factory_for` (`scripts/production/ProductionManager.gd:650`) scans
  the live `factories` group with no `player_id`; used only by the direct-deploy fallback
  (`:681`).
- `EconomyManager.can_afford` (`scripts/economy/EconomyManager.gd:32`) has no callers.
- Production funding is gradual and is out of scope (`ProductionManager._process`/`_pay`).

## Goals / Non-Goals

**Goals:**
- One query answers "can this player build this type, and if not why" for every UI and
  gameplay consumer.
- Preserve `can_build`'s signature and the existing production/tech behavior, so no caller
  and no `.tscn` needs restructuring.
- Make ownership player-scoped in exactly one place.

**Non-Goals:**
- Moving systems under a World root (#473) or fixing map-load building registration (#495).
- Changing production funding timing (`_process`/`_pay`) or the stall/resume behavior.
- Adding new cameo visuals; affordability stays a credit-counter signal.
- New tooltips. The reason is exposed by the query for tests and future use; with locked
  items hidden it has no current surface beyond the gate itself.

## Decisions

### D1 — The query lives on `PrerequisiteSystem` and returns `enabled`, `reason`, `cost`, `owned_factory`

`PrerequisiteSystem` already owns every player-conditional gate despite its name, and is an
autoload with existing callers and tests. Renaming/relocating it is #473's job. Add:

```
enum BuildReason { NONE, NOT_BUILDABLE, NEVER, TECH_LEVEL, BUILD_LIMIT,
                   PREREQUISITE, PREREQUISITE_NECESSARY, NO_FACTORY }

func evaluate_build(player_id: int, data: EntityData) -> Dictionary
func can_build(player_id: int, data: EntityData) -> bool   # = evaluate_build(...).enabled
```

Result shape is a `Dictionary` (`{ "enabled": bool, "reason": BuildReason, "cost": int,
"owned_factory": bool }`). Alternative: a typed `class_name BuildGate` data object — rejected
for now to avoid a one-use class; revisit only if key access becomes error-prone. `reason` is
the first failing gate in fixed order (matches today's sequential short-circuit).
`owned_factory` is computed **unconditionally, before** the cheat early-return, so the
`no_prereqs` bypass falsifies neither the gate's fact nor the direct-deploy fallback. For a
type with an empty `buildable_queue` (only some entities; most structures carry
`buildable_queue = "BuildingType"`), `owned_factory` is `false` and the `no_factory` gate does
not apply — mirroring the existing `buildable_queue.is_empty()` guard rather than comparing
two empty strings.

### D2 — Fold the `buildable` menu flag into the gate

A type that is not in the build menu is not buildable, so `NOT_BUILDABLE` is the first gate
and `can_build` rejects it too. Consequence: `can_build` for `buildable = false` data now
returns false. The only in-repo fixture that relies on the old behavior is
`test_tech_level_gate._data()` (builds `EntityData.new()`, default `buildable = false`); set
`data.buildable = true` there. This is a fidelity fix, not a weakened test — the test intends
a real buildable type. Alternative: leave `buildable` as a caller-side check — rejected
because it keeps two notions and contradicts hiding non-menu items.

### D3 — Factory ownership resolves from the owned-buildings registry

`owned_factory` = "player owns a registered building whose data's `factory == the type's
queue" — the same source `can_build` already uses. This replaces `has_factory_for`'s global
group scan and deletes it. The live `factories` group is a separate subsystem (used by
`_find_factories` for production) and is not the ownership source. Consequence:
`test_cameo_click_policy._make_real_factory_node` must register a building in the registry
(via a real `EntityData` with a matching `factory`), not just add a `FactoryComponent` node.
Alternative: a player-scoped group scan (`FactoryComponent.player_id` exists) keeps the test
untouched but leaves two implementations of the same question — rejected.

Registry write paths differ: `BuildingManager._on_building_placed` registers the **local**
player (`get_local_player_id`), because cameo placement is local-only, while
`DeployComponent` (MCV deploy) registers the deployed entity's own player. So a non-local
player's ownership is representable only for deploy-created buildings; the spec's
"another player's factory does not count" scenario is exercised in tests by direct
registration, not by simulating an AI base.

### D4 — Affordability is feedback, computed against the same player-scoped set

- `EconomyManager.can_afford` stays a **pure** balance check (`get_balance(player_id) >= cost`)
  and gains its first caller in `CreditCounter`. The `no_cost` special-case stays in the UI:
  `insufficient := _cheapest_cost > 0 and not Cheats.no_cost and not can_afford(...)`. Making
  `can_afford` itself cheat-shaped would turn a general affordability query into a lie.
- `CreditCounter._compute_cheapest_cost` iterates the catalog keeping only types where
  `evaluate_build(local_player, data).enabled` and `cost > 0`; takes the min. This is the
  set the build menu is *drawn from* — gate-eligible across every tab for the local player,
  not the currently-visible tab page.
- Empty-set behavior: if the local player can build no costed item, `_cheapest_cost` stays
  `-1` and the warning is off (there is nothing to be unable to afford). On a map-loaded base
  this is the pre-#495 state — the registry is empty, the gate hides factory/prereq-gated
  items — so the warning is off until #495 populates registration. Tests must register a
  local producer fixture for the set to be non-empty (the existing threshold test's current
  "no buildable entity" guard will otherwise fail spuriously).
- Recompute `_cheapest_cost` on `prerequisites_changed`, `players_changed`, **and
  `GameContext.game_changed` directly**. Correction to an earlier assumption:
  `PrerequisiteSystem._on_game_changed` emits `prerequisites_changed` only for players
  already in the registry, so a game switch with no owned buildings emits nothing — hooking
  only the signal would leak a stale cache. Do **not** recompute on `credits_changed` — that
  fires near-every-frame during a drain; the per-frame path stays `balance >= cached_cost`.

### D5 — Remove the dead sidebar grey branch

`Sidebar._create_cameo` `build_limit` grey (`:404-409`) is deleted: capped items are already
filtered out by the gate before a cameo is built, and under `no_prereqs` the gate is bypassed.
No test references it.

## Risks / Trade-offs

- [Registry-empty on loaded maps] → `owned_factory` is false for map-placed factories until
  #495 registers them; the fallback and `no_factory` gate then behave as "not owned". This is
  the known #495 gap, not new; note the dependency rather than patch it here.
- [Ownership registry is local-player-biased] → the placement path registers only the local
  player, so a non-local player's ownership exists only for deploy-created buildings. Accepted:
  the fact is best-effort and the player-scoping still fixes the reported divergence.
- [Affordability warning can go silent] → with a player-scoped set, a base that owns no
  registered producer (map-loaded, or a fresh test fixture) has no eligible item and shows no
  warning until #495 / a registered fixture. This is the correct "nothing to afford" state, but
  it changes current always-on behavior; covered by a test fixture and called out in D4.
- [`can_build` now rejects non-menu types] → any programmatic queue of a `buildable = false`
  type is refused. Intended (D2); covered by a new tech-level scenario.
- [Per-frame cost of the warning] → caching cheapest on prereq/roster change only keeps the
  `credits_changed` path O(1); `_compute_cheapest_cost` is O(catalog) but rare.
- [#473 relocation] → keep the query API on `PrerequisiteSystem` (no hardcoded absolute node
  paths beyond the existing autoload identifiers) so the World-root move can carry it.

## Migration Plan

No data or scene migration. Land as one change; rollback is a revert. `can_build` stays
source-compatible throughout, so the change can be applied incrementally (add the query and
delegate first, then switch consumers).
