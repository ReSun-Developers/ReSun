# Proposal

## Why

Missions are script-driven: the first GDI mission carries 52 triggers built from events
(elapsed time, entity destroyed/built/attacked, flag changes, cell-tagged entity state) and
actions (reveal, spawn reinforcements, camera scroll, sound, destroy, meteor, win/lose). ReSun
has no trigger system, so none of that content can run. This change adds the mission-scripting
runtime that the mission layer (#236 boot, #238 teams, #240 objectives, #248 wiring) builds on.

The engine follows the classic C&C trigger model — data-driven event/action records addressed
by stable ids — rather than a bespoke scripting language, so a converted map's scripting data
maps over without translation.

## What Changes

- Add a **fixed 30 Hz logic clock** (`MatchClock`) that owns an integer frame counter and a
  deadline scheduler; it is the single time source for simulation and triggers.
- Add a **scenario state** store (`ScenarioState`): global flags, per-house local flags, a
  waypoint registry, and the mission timer — all resettable per mission and save-friendly.
- Add a **trigger engine** that:
  - parses trigger/tag/event/action definitions from map JSON (`triggers` array), with an
    optional `.tres` overlay;
  - routes occurrences to attached tags via a push bus, latches event bits, and evaluates only
    dirty triggers once per logic tick;
  - supports the three tag persistence modes (volatile / semi-persistent / persistent) and
    event remembering;
  - dispatches actions through a deferred journal drained at the tick boundary, so an action
    that spawns, destroys, or flags something cannot corrupt an in-progress evaluation;
  - validates every definition at load (known numeric ids, parameter arity, resolvable flag and
    waypoint references) and rejects bad content before the mission runs;
  - implements the GDI1 subset of events and actions, with the catalog extensible to the full
    set as data, not code.
- Extend the **map JSON schema** with optional `triggers`, `waypoints`, and `variables` keys,
  preserved and surfaced by `MapLoader`/`TerrainSystem` round-trip.
- Wire a minimal set of real offer sources (entity destroyed, entity placed, building placed,
  credits changed, flag changed) so a mission can be authoritatively driven end-to-end.

## Capabilities

### New Capabilities
- `match-clock`: the fixed-rate logic clock and integer deadline scheduler.
- `scenario-state`: global/per-house local flags, waypoint registry, mission timer.
- `trigger-engine`: trigger/tag/event/action definitions, offer bus, evaluation, persistence,
  deferred action dispatch, and load-time validation.

### Modified Capabilities
- `map-loader`: map JSON gains optional top-level `triggers`, `waypoints`, and `variables`
  keys that load, round-trip, and are surfaced to the trigger engine.

## Impact

- New autoloads/nodes: `MatchClock`, `ScenarioState`, `TriggerEngine`.
- New data/scripts under `scripts/triggers/` (definitions, catalog, bus, runtime).
- `MapLoader` and `TerrainSystem.export_to_json`/schema gain three optional keys.
- `MissionBoot` starts the trigger engine when a mission starts.
- `HealthComponent`/`EntityFactory`, `EntityPlacer`, `BuildingManager`, and `EconomyManager`
  gain small offer hooks (emit to the bus on the relevant occurrence).
- Tests: unit coverage for clock, scenario state, catalog parsing/validation, evaluation
  (persistence, remembering, cascades) and an integration test booting a scripted fixture.
