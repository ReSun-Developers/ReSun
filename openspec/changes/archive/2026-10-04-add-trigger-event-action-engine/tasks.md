# Tasks

## 1. Match clock

- [x] 1.1 Add `scripts/core/MatchClock.gd` autoload with a 30 Hz frame accumulator, `tick(frame)` and `deadline_reached(key)` signals, `frame`, `schedule(key, frames_ahead)`, `cancel(key)`, `reset()`, and pause handling; register it in `project.godot` after `GameContext`. Verify with `test/unit/test_match_clock.gd`: one tick per interval, several ticks for a long frame, no tick below an interval, reset, pause/resume.
- [x] 1.2 Implement deterministic deadline ordering (ascending deadline, tie broken by schedule order) and replace-on-reschedule. Verify with `test_match_clock.gd`: single fire, cancel, same-frame ordering, reschedule replaces.
- [x] 1.3 Cap ticks advanced per rendered frame and discard excess with a diagnostic. Verify with a clock test that feeds an extreme delta and asserts the per-frame cap.

## 2. Scenario state

- [x] 2.1 Add `scripts/core/ScenarioState.gd` autoload with declared global flags (`set_global`/`clear_global`/`get_global`/`has_global`, edge-only `global_changed`), rejection of undeclared names, and `reset()`. Verify with `test/unit/test_scenario_state.gd`: set/read, clear, edge-only signal, undeclared rejected, reset.
- [x] 2.2 Add per-house local flags (`set_local`/`clear_local`/`get_local`/`has_local`, edge-only `local_changed`) independent per house. Verify with `test_scenario_state.gd`: house scoping, edge-only, undeclared rejected.
- [x] 2.3 Add the waypoint registry (`set_waypoint`/`get_waypoint`/`has_waypoint`) and bulk load from a `waypoints` object of `"x,y"` strings that discards malformed entries with a diagnostic. Verify with `test_scenario_state.gd`: set/read, unknown, malformed discarded, in-diamond check.
- [x] 2.4 Add the mission timer (`start_timer`/`stop_timer`/`set_timer`/`add_timer`/`get_timer`/`is_timer_running`/`mission_timer_expired`), advanced by `MatchClock.tick`. Verify with `test_scenario_state.gd`: countdown to expiry, stopped stays put, add extends.

## 3. Trigger catalog and definitions

- [x] 3.1 Add `scripts/triggers/TriggerCatalog.gd` declaring the event and action tables (numeric id, key, arity, kind) for the implemented subset and a lookup by id. Verify with `test/unit/test_trigger_catalog.gd`: every implemented id resolves with the expected arity, and an unknown id returns nothing.
- [x] 3.2 Add `scripts/triggers/TriggerDefinition.gd` (or a typed parser) that parses a map `triggers` array into trigger definitions with stable ids, owner, tags, events, actions, and difficulty flags. Verify with `test/unit/test_trigger_parse.gd`: a valid fixture parses to the expected ids, arities and tag attachments.
- [x] 3.3 Implement load-time validation (duplicate id, unknown event/action id, wrong arity, unresolved waypoint/variable/trigger reference), all-or-nothing, with diagnostics. Verify with `test_trigger_parse.gd`: each invalid fixture is rejected for the right reason and a valid set arms.
- [x] 3.4 Support an optional `.tres` overlay that patches a trigger's events/actions by id. Verify with `test_trigger_parse.gd`: overlay replaces the targeted trigger and leaves others unchanged.

## 4. Trigger runtime

- [x] 4.1 Add `scripts/triggers/TriggerEngine.gd` autoload with `arm(definitions)`, `reset()`, and the runtime overlay (`enabled`, `latched`, `marked`, countdown, tag attachment counts) keyed by trigger id. Verify with `test/unit/test_trigger_engine.gd`: arm/reset clears state; a re-arm replaces definitions.
- [x] 4.2 Implement `offer(event_id, payload)` that resolves reachable triggers by attachment (general, house, cell via `TerrainSystem`, object by id), latches the event bit, and marks dirty without evaluating. Verify with `test_trigger_engine.gd`: subscribed latches and dirties, unsubscribed untouched, cell scope honoured.
- [x] 4.3 Implement the per-tick dirty evaluation: fire when enabled, not marked for destruction, and all events satisfied; events examined in reverse declared order; latched-only events cleared after evaluation. Verify with `test_trigger_engine.gd`: all-satisfied fires, partial does not, disabled does not.
- [x] 4.4 Implement persistence: volatile destroys tag+trigger after firing, persistent re-arms and fires repeatedly, semi-persistent decrements cell/object attachment counts and fires on the last. Verify with `test_trigger_engine.gd`: once, repeat, fire-on-last.
- [x] 4.5 Implement remembering: persistent tags mark satisfied temporal events across offers; volatile/semi require single-offer satisfaction; countdown restart on enable, variable change, and satisfying remembering offer. Verify with `test_trigger_engine.gd`: cross-offer combination on persistent, never on volatile, countdown restart.

## 5. Action journal and dispatch

- [x] 5.1 Add a per-tick action journal in `TriggerEngine` that queues typed commands from firing triggers and drains them at the tick boundary in author order, resolving targets at drain time. Verify with `test/unit/test_trigger_actions.gd`: queued actions dispatch in order, and a spawn action does not run during evaluation.
- [x] 5.2 Add the per-tick command budget and bounded same-tick cascade handling with a diagnostic on overflow. Verify with `test_trigger_actions.gd`: a self-triggering cascade stops at the budget and logs once.
- [x] 5.3 Implement control actions (enable, disable, force, destroy trigger; destroy tag) against the runtime overlay. Verify with `test_trigger_actions.gd`: disable stops firing, force fires without events, destroy is permanent.

## 6. Variable, timer and outcome actions and events

- [x] 6.1 Implement the set/clear global and local actions and the corresponding set/clear events, routing a change to the correct general or house offer, house-scoped for locals. Verify with `test/unit/test_trigger_variables.gd`: set global satisfies global-set, local events stay house-scoped.
- [x] 6.2 Implement mission timer actions (start, stop, set) and the timer-expired event. Verify with `test_trigger_variables.gd`: start/set/stop drive `ScenarioState` and expiry satisfies the event.
- [x] 6.3 Implement win, lose, and allow-win actions emitting mission outcome signals (allow-win holds until its tag is destroyed while still holding a trigger). Verify with `test_trigger_variables.gd`: win/lose emit the outcome, allow-win holds then releases.

## 7. Map integration and wiring

- [x] 7.1 Extend map JSON handling so `triggers`, `waypoints`, and `variables` load, round-trip through `TerrainSystem.export_to_json`, and are surfaced to `TriggerEngine`/`ScenarioState`. Verify with `test/unit/test_map_scripting_keys.gd`: round-trip, absent keys load clean, waypoints surfaced.
- [x] 7.2 Wire `MissionBoot` to `reset()` then `arm()` the trigger engine and load waypoints/variables when a mission starts; reset on new match. Verify with an integration test (`test/integration/test_trigger_mission_boot.gd`) that a mission fixture arms triggers and clears them on the next boot.
- [x] 7.3 Wire minimal real offers: `HealthComponent.killed` → destroyed, `EntityPlacer.entity_placed` and `BuildingManager.building_placed` → build, `EconomyManager.credits_changed` → credit sampler, flag changes → variable offers, `MovementController.arrived` → cell entry. Verify with `test/integration/test_trigger_offers.gd`: a placed building satisfies a build event and a destroyed entity satisfies a destroyed event for a tagged trigger.
- [x] 7.4 Update `AGENTS.md` autoload table and `project.godot` ordering annotations for `MatchClock`, `ScenarioState`, `TriggerEngine`, and add glossary entries for trigger, tag, event, action, persistence, waypoint, global/local flag, mission timer. Verify by reading the docs and running `openspec validate`.

## 8. Integration verification

- [x] 8.1 Run the full suite (`redot --headless -s test/run_tests.gd`) and confirm all trigger, clock, scenario-state and map tests pass with no regressions.
- [x] 8.2 Run `gdlint` and `gdformat --check` on all new and changed scripts, then `grep -P '\t'` on changed scripts to confirm no tabs.
- [x] 8.3 Author a hand-written JSON mission fixture exercising a persistent cross-offer trigger, a cell-entry trigger, a variable cascade, and a win action; verify end to end with `test/integration/test_trigger_mission_boot.gd`.
