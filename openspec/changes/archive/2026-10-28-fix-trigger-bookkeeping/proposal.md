# Proposal

## Why

Two standing-condition bookkeeping bugs make mission triggers read stale state:

- A `credits` event (12) reads `TriggerEngine`'s per-house mirror, which is filled only by `EconomyManager.credits_changed`. `PlayerManager.begin_mission` writes starting credits directly and emits only `players_changed`, and arming does not schedule a first evaluation, so a "credits ≥ N" trigger cannot fire until the first harvest or spend even when the house already has enough (#524).
- Selling a structure refunds it, unregisters its prerequisites and frees it, but never tells `TriggerEngine`, so `_alive` / `_built` keep counting the sold structure as present. A "building exists" condition stays wrong until an unrelated destroy notification arrives (#525). Undeploying a structure has the same gap.

## What Changes

- Seed the per-house credit mirror from the live player balances when scripting is armed, after `begin_mission` has written the starting credits, and mark credits-event triggers for one evaluation on the first logic tick.
- Add a count-only `TriggerEngine.notify_removed(owner, entity_id, node)` that decrements `_built` / `_alive` and marks the owner's triggers dirty without offering the temporal destroyed events (7 / 48).
- Mark an entity as counted when `notify_built` records it, and make `notify_removed` decrement only for an entity that was counted. This keeps the aggregate counts from stealing a counted sibling when an uncounted structure (map-loaded or deploy-created) leaves the world.
- Route structure sale and undeploy removal through `notify_removed`, so the counts drop whenever a counted structure leaves the world for a non-death reason. Death keeps offering events 7 / 48 as before.
- Record in the `trigger-engine` spec that a sale or transform is a removal, not a destruction, and that the credits event reads the starting balance.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `trigger-engine`: add requirements for the credits event reading the starting balance at arm, and for counted-structure removal bookkeeping (sale / undeploy vs. death).

## Impact

- **Code**: `scripts/triggers/TriggerEngine.gd` (`arm`, new `_seed_credits` / `_mark_credits_dirty`, new `notify_removed`, counted marker in `notify_built`, `notify_destroyed` reuses `notify_removed`); `scripts/buildings/BuildingManager.gd` (`sell_building`, `unregister_building_entity`).
- **Tests**: new integration regression suite for both issues (credits at arm with no credit change; sale and undeploy drop `_alive` / `_built`; death pair; sale does not raise destroyed events with a death positive control).
- **Specs**: `openspec/specs/trigger-engine/spec.md` via delta.
- **Out of scope**: the structure ledger from #518 (per-entity reason tracking) and the elimination of the credit mirror from #473. Map-loaded and deploy-created structures are still not counted; the counted marker only prevents removal from corrupting the counts of structures that were counted. #473 can later replace the seeded mirror with a direct balance read.
- **Data/compat**: no `.tscn` / `.tres` schema change; no public autoload API removed. `notify_removed` is additive.
