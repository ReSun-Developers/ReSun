# Design

## Context

See `proposal.md` — Why. Current constraints that shape the approach:

- No simulation clock exists; `GlobalRules.logic_fps = 30.0` is only a conversion constant, and every
  system runs its own `_process`/`_physics_process`. Triggers need one deterministic time source.
- No flag, waypoint, or mission-timer store exists anywhere (`PlayerData` carries only identity/tech).
- Systems already expose the occurrences a trigger engine needs as signals: entity death
  (`HealthComponent.health_zero`/`killed`), placement (`EntityPlacer.entity_placed`,
  `BuildingManager.building_placed`), damage (`HitboxComponent.received_damage`), credits
  (`EconomyManager.credits_changed`), movement completion (`MovementController.arrived`).
- Action sinks already exist as public methods: `EntityPlacer.place_entity`, `ShroudSystem`
  `reveal_area`/`explore_area`, `BoundsSystem.center_camera_on_cell`, `AudioManager.play_sound`/
  `play_voice`, `HealthComponent.kill`/`take_damage`.
- A sparse cell→tag overlay already exists on `TerrainSystem` and round-trips through map JSON.
- Map JSON is versioned (v4) and `TerrainSystem.export_to_json(extra_data)` / `MapLoader` are the
  insertion seams; `MissionBoot` starts a mission into a per-match World root.
- The engine is single-threaded GDScript; there is no build system.

## Goals / Non-Goals

**Goals:**
- One deterministic time source for scripting at 30 logic ticks/second.
- Mission-scoped variables, waypoints, and timer with clean reset.
- Data-driven triggers evaluated only when occurrences reach their attachments.
- Classic persistence semantics so imported scripting data behaves as authored.
- A mission can be exercised end to end from a scripted fixture in a headless test.

**Non-Goals:**
- The `.map` importer (tracked separately) and full parity with every classic event/action.
- AI teams, task forces, skirmish AI, and reinforcements beyond a spawn hook (issues #238/#239).
- Save/load of live trigger state (proposal does not require it; state is reset per match).
- Networking/determinism hashing for multiplayer.

## Decisions

### Decision: Offer model with edge-latched bits, not per-tick polling
A trigger is never scanned every tick. `TriggerEngine.offer(event_id, payload)` resolves the
reachable triggers, sets a bit in each trigger's latched event mask, and adds it to a dirty set. On
each `MatchClock` tick only the dirty set is evaluated: `(latch & required) == required`, plus
standing conditions that have no push source.

- Why: evaluation cost is proportional to activity, not `triggers × events`; it matches the classic
  trigger model, so converted maps behave; and offers can only reach triggers whose tag rides on the
  offered object/cell.
- Alternatives: per-tick poll of every trigger (simpler, but O(n) every tick and diverges from
  authored semantics); compiling predicates against a per-tick world snapshot (cleaner isolation but
  heavier and still a poll).

### Decision: Standing conditions are sampled as transitions, not polled raw
Conditions with no natural push source (credits above/below, all-destroyed, building-exists) are
owned by a small sampler that runs on the tick and offers their event only when the evaluated value
crosses from false to true (an XOR against the previous sample). This keeps them edge-shaped so a
held-true condition does not re-fire a persistent trigger every tick.

- Why: avoids both per-system plumbing for every condition and threshold chatter.
- Alternative: require each owning system to push on change (more wiring, easy to miss a source).

### Decision: Actions go through a deferred journal drained at the tick boundary
Firing appends typed action commands; a single dispatcher drains them after all systems and all
evaluations for the tick have settled, in author order, resolving targets at drain time based on
stable ids. Same-tick cascades are handled by a bounded fixed point with a per-tick command budget.

- Why: an action may spawn, destroy, flag, or enable something an occurrence source is iterating;
  deferral removes re-entrancy and makes cascades deterministic and replayable.
- Alternative: execute inline with re-entrancy guards (simpler, but order-dependent and fragile).
- Risk note: deferred targets must be identity-stable (entity id + validity), not Node references.

### Decision: Definitions are immutable and keyed by stable id; runtime state is a separate overlay
Loaded trigger definitions are not mutated. A parallel runtime record per trigger id holds `enabled`,
`latched`, `marked`, countdown, and per-tag attachment counts. Control actions write to the runtime
record; validation reads only definitions.

- Why: map edits do not shift meaning; force/enable/disable/destroy can address triggers by id; the
  overlay is small and serializable later.
- Alternative: mutate definition objects (breaks on reload and makes ids unstable).

### Decision: One `MatchClock` owns time; elapsed and random delays are deadlines
Elapsed-time and random-delay events register an integer deadline on the clock via the scheduler. When
the deadline fires the clock emits `deadline_reached(key)` and the engine offers the corresponding
event. Countdown restart semantics (enable, linked-variable change, satisfying remembering offer) are
implemented by rescheduling.

- Why: integer ticks avoid float drift and make timing exact and testable; a single scheduler also
  hosts the mission timer and future spawns.
- Alternative: per-trigger float accumulators (drift, no single source, hard to test).

### Decision: Persistence as state transitions with remembering and consumption
`volatile` destroys the tag and its trigger after the first fire. `persistent` keeps the tag and
re-arms. `semi-persistent` decrements attachment counts and fires on the last. Remembering is enabled
for an evaluation when the tag is persistent, so satisfied temporal events set a mark that is never
cleared. `match-clock` countdowns restart on the three documented triggers.

- Why: this is the authored behavior authors and imported maps rely on; encoding it as transitions
  avoids scattered boolean guards and makes "fire once / fire on last / fire repeatedly" one table.

### Decision: Autoloads with explicit reset, not World-scoped nodes
`MatchClock`, `ScenarioState`, and `TriggerEngine` are registered as autoloads (like the existing
per-match managers) and expose `reset()`. `MissionBoot` calls `reset()` then `arm(definitions)` on
mission start.

- Why: matches the existing manager pattern and the `GameContext`/`MissionBoot` lifecycle; the
  per-match World root holds map entities, not mission-wide managers.
- Alternative: child nodes under the World root (tied closer to #473) but would require every
  consumer to look up the current World and complicates headless tests.

### Decision: Catalog is a GDScript table of numeric ids
Events and actions are declared once in a catalog table: `{id, key, arity, kind, params}`. Runtime
handlers are a separate dictionary keyed by id. Unknown ids and arity mismatches fail at load.
Unimplemented-but-known ids are accepted and log a one-time warning at arm time.

- Why: numeric ids preserve imported-map data; adding an event/action is a table row plus a handler,
  not a new subsystem.

### Decision: Minimal real offer hooks for the first slice
Wire: `HealthComponent.killed` → destroyed offers (attached object tags), `EntityPlacer.entity_placed`
and `BuildingManager.building_placed` → build offers, `EconomyManager.credits_changed` → credit
sampler invalidation, `ScenarioState` flag changes → variable offers, `MovementController.arrived` →
cell-entry offers. Remaining events are catalogued and reachable through `offer()` but not yet wired.

- Why: proves the engine end to end while keeping the diff reachable and reviewable.

## Risks / Trade-offs

- [Re-entrancy and ordering during the dirty walk] → two-phase tick: offenders only latch during
  evaluation are queued; the journal drains once and any new occurrence is processed against the next
  evaluation or a bounded fixed point with a command budget.
- [Deferred target outlives its referent] → commands carry entity/trigger ids and validity is checked
  at drain; a dead target is dropped with a diagnostic.
- [Standing samplers are stale within a tick] → the sampler runs at a fixed point in the tick before
  evaluation, and push-on-change is used for credits so the common case is exact.
- [Clock budget under slow frames] → cap the number of logic ticks advanced per rendered frame to avoid
  a spiral of death; excess time is discarded with a diagnostic.
- [Catalog drift from imported maps] → validation lists unknown ids explicitly at arm time; the catalog
  is the single source of truth.

## Migration Plan

- Register `MatchClock`, `ScenarioState`, `TriggerEngine` in `project.godot`; keep `GameContext` first.
- New optional map JSON keys default to empty; existing maps load unchanged.
- `MissionBoot` gains `reset()` + `arm()` calls; no existing scene changes required.
- Rollback: remove the three autoloads and the `MissionBoot` calls; map keys are inert data.

## Open Questions

- Exact mapping of imported event/action numeric ids beyond the implemented subset is finalised with
  the importer issue; the catalog is designed to accept new rows without code changes.
- Whether semi-persistent attachment counting should include entities that leave play without
  satisfying the trigger is deferred to the importer wiring; the first slice counts cells and objects.
