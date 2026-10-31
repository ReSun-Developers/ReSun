# Design

## Context

See `proposal.md` — Why. Two bookkeeping seams in `TriggerEngine` are fed only by notification hooks,
and two lifecycle paths skip those hooks:

- `_credits` is written only by `notify_credits` (from `EconomyManager.credits_changed`) and cleared
  by `reset()`. `PlayerManager.begin_mission` writes `free_credits` directly and emits
  `players_changed`, not `credits_changed`. Arming also schedules no evaluation, so a credits trigger
  waits for the first credit occurrence.
- `BuildingManager.sell_building` and `BuildingManager.unregister_building_entity` (called by
  `DeployComponent` on undeploy) remove a structure without calling `TriggerEngine.notify_destroyed`;
  only `EntityFactory._on_entity_death` (health zero) does.
- `_alive` / `_built` are aggregate counters per owner and entity id. No event reads `_alive` today;
  event 32 (`building_exists`) reads `_built`. The counters are still the bookkeeping the issue asks
  to keep correct.

## Goals / Non-Goals

**Goals:**
- A credits trigger sees the starting balance and fires on the first logic tick after arming.
- A counted structure that is sold or undeployed stops counting as alive/built, without inventing a
  destruction, and without corrupting the count of a counted sibling of the same id.

**Non-Goals:**
- Replacing the per-house credit mirror with a direct `EconomyManager` read (#473). The mirror stays;
  this change seeds it and schedules its first evaluation.
- A full per-entity structure ledger with removal reasons (#518). The counted marker below is a
  minimal identity guard, not a ledger.
- Counting map-loaded or deploy-created structures. They remain uncounted until #518; the marker
  only ensures their removal does not decrement counts they never added.
- Removing a vehicle that deploys into a structure (`DeployComponent._do_deploy`). That is a unit
  transform, not a structure removal; #518's ledger owns transform-source bookkeeping.
- A general "evaluate every standing condition at arm" semantic change. Only credits-event triggers
  are scheduled, because the starting-credit write is the state change that lacks an occurrence.

## Decisions

### #524: seed the mirror and schedule one credits evaluation at arm

`arm()` calls `_seed_credits()` and `_mark_credits_dirty()` after `_build_indices()` and `_armed =
true`.

- `_seed_credits()` iterates `PlayerManager.get_all_players()` and stores
  `EconomyManager.get_balance(player_id)` under `data.faction_id`. `get_balance` (free plus
  displayable stored) is the same figure `notify_credits` receives, so the seed and later updates
  share one definition of "balance". Stored values are empty at mission start, so this equals the
  starting free credits. The local player seeds last, so a house shared with another player reads the
  local balance instead of whichever player iterated last.
- `_mark_credits_dirty()` marks only live triggers whose event list contains event 12. It does not
  mark other standing triggers, so globals, build-exists and time triggers keep their existing
  occurrence-driven evaluation. This avoids changing mission-author-visible behavior beyond #524.
- `MissionBoot` already calls `PlayerManager.begin_mission` before `_arm_scripting`, so the seed runs
  after starting credits exist.
- Alternative rejected: read `EconomyManager` directly inside the credits event. It removes a copy of
  state (#473) but still needs the initial dirty pass, and it must choose a player when several share
  a house. `_players_for_house` already exists, but it falls back to the local player, which would be
  wrong for another house. The mirror already has last-writer-wins semantics; #473 can replace it.

### #525: counted marker plus count-only `notify_removed`

Add `const COUNTED_META := "trigger_counted"`. The meta has three states: absent (never counted),
`true` (counted), and `false` (removed). `notify_built` sets it to `true` on the entity node when it
records the entity. `notify_removed(owner, entity_id, node = null)` decrements
`_built[owner][entity_id]` and `_alive[owner]` (clamped at zero), calls `_mark_owner_dirty(owner)`,
then sets the marker to `false`. It is a no-op when the node is absent, invalid, never counted, or
already removed, and it offers no events.

- `notify_destroyed` returns early for an already-removed node, otherwise calls `notify_removed` and
  then offers events 7 and 48. This preserves the old event behavior for uncounted entities and empty
  owners while making a death during the sale `queue_free` window or the undeploy `call_deferred`
  window a no-op for both the counts and the events.
- `BuildingManager.sell_building` calls `notify_removed(house_for_player(owner_id), entity_data.id,
  building_node)` before `queue_free()`.
- `BuildingManager.unregister_building_entity` (the undeploy seam) calls the same with the node it is
  removing.
- Why the marker: `_alive` / `_built` are aggregates. A map-loaded or deploy-created structure is not
  counted, so decrementing on its removal would steal one from a counted structure of the same id.
  The marker gives the removal seam a per-entity "was counted / already removed" fact without
  building the #518 ledger. It also makes death bookkeeping consistent: an uncounted entity's death
  no longer decrements a counted sibling.
- The marker is set only in `notify_built`; map-loaded structures are spawned before `arm()` (the
  engine is disarmed, so `notify_built` no-ops) and deploy-created structures use `EntityFactory.spawn`
  without a `notify_built` call, so both stay uncounted.

**TS behavior on sale:** Tiberian Sun removes a sold structure rather than killing it; the destroyed
event family is attached to object death. No authoritative TS source for this exact trigger behavior
is checked into the repo (`docs/research/deep/ts-*` describes sell refunds and survivors, not trigger
events). The conservative decision is recorded: sale and undeploy are removals, not destructions —
counts change, events 7 and 48 do not fire. If a later reference shows TS raises destroyed on sale,
only the event offers at the removal seam change; the counts are already correct.

## Regression tests that must fail on the base commit

New `test/integration/test_trigger_bookkeeping.gd` (uses the `TriggerEngine` autoload; resets it and
restores the player credits, `ScenarioState`, and building registry each test). The base run fails 13
assertions across eight tests; the rest are pairs/guards that pass on base.

- `test_credits_trigger_reads_starting_balance_at_arm`: clear the local player's stored categories,
  set free credits to 5000, arm a threshold-1000 credits trigger, tick once with no credit change →
  fires. Base: no arm-time credits pass, so nothing fires.
- `test_credits_trigger_fires_at_exact_balance`: threshold exactly 5000 against 5000 → fires. Base:
  silent.
- `test_credits_trigger_waits_above_starting_balance`: threshold 9000 against 5000 → silent on first
  tick, then `EconomyManager.add` and tick → fires. Pair, passes on base too.
- `test_shared_house_reads_local_balance`: add a second player with the local faction and 9000 credits
  while the local player has 5000, arm a threshold-6000 trigger, assert the mirror is 5000 and the
  trigger stays silent. Base: the mirror is 0.
- `test_arm_leaves_non_credits_standing_trigger_clean`: after arm the mirror equals the starting
  balance and the credits trigger is dirty while a global-set trigger is not; `reset()` clears both
  `_credits` and `_dirty`. Base: mirror is 0 and the credits trigger is not queued.
- `test_sold_structure_drops_trigger_counts`: arm, `notify_built` with the node, assert `_alive == 1`
  and `_built[id] == 1`, register the node in `BuildingManager`, sell it, assert both are 0. Base:
  the counts stay at 1.
- `test_undeployed_structure_drops_trigger_counts`: same setup, call
  `BuildingManager.unregister_building_entity`, assert both are 0. Base: the counts stay at 1.
- `test_removing_uncounted_structure_keeps_counted_sibling`: count one structure of an id, register a
  second uncounted node of the same id, remove the second, assert the count is still 1. Guards the
  marker.
- `test_destroyed_structure_drops_trigger_counts`: `notify_built` then `notify_destroyed`, assert both
  are 0. Pair, passes on base.
- `test_sale_does_not_offer_destroyed_events`: arm a trigger watching events 7 and 48, count and sell
  a structure, tick → silent; then count and `notify_destroyed` another structure, tick → fires. The
  second half is the positive control so the test cannot pass vacuously.
- `test_double_removal_does_not_decrement_or_offer_destroyed`: count two structures, sell one, then
  call `notify_destroyed` on the same still-valid node; assert the sibling keeps `_alive == 1` /
  `_built == 1` and no destroyed event fires. Base: the sale does not decrement and the second call
  offers the event.
- `test_sold_structure_clears_building_exists_condition`: an event-32 + global-set trigger fires only
  if the building still exists after the sale; assert `_built == 1` before the sale as the positive
  control. Base: the sale leaves `_built` at 1, so it fires.

Every count assertion is preceded by a positive-count assertion so a disarmed engine or a missing
`notify_built` cannot make the test pass at zero.

## Risks / Trade-offs

- [Seeded mirror goes stale if something writes `free_credits` directly after arm] → no such writer
  exists today; every post-arm change goes through `EconomyManager` and emits `credits_changed`.
  #473 removes the mirror entirely.
- [A counted structure removed through a path that passes no node is not decremented] → all
  production removal call sites pass the node; a node-less call is treated as uncounted, which is the
  conservative choice. Death with no node still offers the destroyed events.
- [Map-loaded and deploy-created structures still do not count] → pre-existing #518 gap; the marker
  ensures their removal cannot corrupt counted structures.
- [Deploying a counted vehicle frees it without a removal notification] → unit transform, explicitly
  out of scope; #518's ledger owns transform-source bookkeeping.
- [Sale no longer looks "destroyed" to mission authors who expected event 7] → recorded as the TS
  decision above; changing it later is a one-line offer addition at the removal seam.

## Migration Plan

None. No data or scene schema changes. Reverting removes the arm-time seed/dirty pass, the
`notify_removed` calls in `sell_building` and `unregister_building_entity`, and the `notify_destroyed`
refactor.

## Open Questions

None blocking. Whether TS raises destroyed on sale is the only external-behavior unknown; the counts
are correct either way and the event choice is isolated at the removal seam.
