# Design

## Context

See `proposal.md` — Why. Current state that shapes the approach:

- `MouseHandler._handle_single_click` sends every left click through `OrderProbe` →
  `OrderSystem.resolve_probe` → `UnitOrderGenerator.resolve`. The only pre-emption is
  Alt on a selection with a `RallyPointComponent`.
- `OrderSystem.build_modifiers` maps Ctrl → `force_attack`, Alt → `force_move`,
  Shift → `queued`. Both Ctrl and Alt set both flags today.
- `UnitOrderGenerator.resolve` short-circuits on `force_move` before any component
  targeter runs, so Ctrl+Alt currently resolves to a synthesized MOVE.
- `SelectionManager.request_move` owns formation, cell reservation, target level and
  the path cache, and drains queued moves over several frames in `_process`.
- `GuardComponent` already implements Mode A: when idle, unengaged, powered and not
  moving, it scans `SpatialHash` for the nearest visible hostile in weapon range and
  calls `CombatComponent.set_target(target, hold_ground = true)`.
- `CursorState.Type.GUARD` and its shield texture already exist but no generator
  returns it.

## Goals / Non-Goals

**Goals:**

- Ctrl+Alt+Click issues a guard-area order for a guard-capable local selection.
- The selection moves to the clicked position, then guards it using the existing
  GuardComponent acquisition, returning to its assigned slot if displaced.
- Ctrl, Alt and Alt-on-a-factory keep their current behavior.
- The cursor is `GUARD` over a valid guard-area target.

**Non-Goals:**

- Force fire and force move behavior (owned by #493).
- Rally point behavior (existing).
- A second targeting/scan path or a new guard component.
- Pathing/formation changes: the order reuses `SelectionManager.request_move`.
- A guard-area anchor for entity clicks beyond the moved-to destination; the entity
  click still carries no surface level, exactly like move-to-entity.

## Decisions

### Decision: a new `MOD_GUARD_AREA` flag, resolved before force-move

`OrderSystem.build_modifiers` adds `MOD_GUARD_AREA = Ctrl && Alt`. `resolve()` checks
it before the `force_move` short-circuit. Both `force_move` and `force_attack` remain
set, but guard area wins while it applies.

Alternative considered: make `GuardComponent` a component order targeter and filter
the force-move short-circuit. Rejected — the short-circuit exists to bypass every
component targeter, and routing guard area through the component would either need
that short-circuit weakened for all components or a second special case. One early
branch is smaller and leaves force-move semantics untouched.

The branch deliberately pre-empts component orders the same way force-move does: a
guard-capable selection Ctrl+Alt+clicking a refinery moves instead of docking.
Unarmed selections (no `GuardComponent`, including harvesters) fall through to the
existing force-move branch, so Ctrl+Alt on them still moves.

### Decision: rally receivers suppress the guard-area flag

`MouseHandler._handle_single_click` intercepts Alt (Ctrl+Alt included) when the
selection owns a `RallyPointComponent`. `build_modifiers` therefore clears
`MOD_GUARD_AREA` when `SelectionManager.has_rally_receiver()` is true, so the hover
cursor cannot show GUARD for a click that will set a rally point. Plain Alt keeps its
existing cursor behavior.

### Decision: synthesize the order in `UnitOrderGenerator`, like the ground MOVE

The guard order is built by `_synthesized_guard_area`, mirroring `_synthesized_move`:
it reuses `SelectionManager.request_move` (formation, cell reservation, target level,
path cache) and additionally marks the batch as a guard-area batch. Priority is a new
`GUARD_AREA_PRIORITY = 6`, above `GROUND_MOVE_PRIORITY = 5` and below deploy/enter, so
the order is a command in its own right rather than a move. `OrderResult.target_level`
is carried like the move order.

Alternative considered: a dedicated `GuardAreaOrderGenerator`. Rejected — the order
is a unit order with the same target/formation pipeline; a generator would duplicate
`resolve()` and `_synthesized_move`.

### Decision: anchor is the unit's assigned destination, captured when the move runs

`request_guard_area()` sets a batch flag on `SelectionManager`; `_execute_move()`
reads it after `set_target_position()` and calls
`GuardComponent.set_guard_area(mc.get_target_position())` for that entity. This makes
the anchor the slot the unit actually walks to (formation, fallback relocation or a
failed path's current position), not the shared click point.

Alternative considered: anchor the shared clicked point. Rejected — infantry sharers
spiral up to 4 cells and blocked vehicle slots fall back up to 8 cells, so a shared
anchor would drag those units back immediately. Per-unit anchors keep formation and
need only a small displacement threshold.

The batch flag is reset at the start of `request_move()`, so a newer order supersedes
a queued guard-area marking. Entities `request_move` skips (transitioning,
undeployable) never enter the stance.

### Decision: stance clearing is signal-driven, no approach phase

`GuardComponent` activates the stance at move start and clears it on:

- `movement_started` whose destination is not the anchor (within the leash radius) —
  a player move. The stance's own return move uses `internal = true`, which emits no
  `movement_started`, and the initial approach move started before the stance existed.
- `pathfinding_failed` while idle — an unreachable return anchor clears the stance
  instead of retrying every tick.
- `MouseHandler.apply_selection_hotkey(stop)` calling `clear_guard_area()` alongside
  `mc.stop()` and `combat.clear_target()`.

No `arrived` bookkeeping is needed: the leash decision is just `is_moving()`, the
distance to the anchor, and `is_engaged()`.

### Decision: reuse the existing GUARD cursor

`CursorState.Type.GUARD` already maps to `shield.svg`; the generator returns it on
the order. `CURSOR_PRIORITY` is unused by the resolver, so it is left untouched.

## Risks / Trade-offs

- [A ground force-fire (no movement) does not clear the stance] → After the
  engagement clears, the unit resumes guarding its anchor. This matches the stance's
  purpose; a player move still clears it. Documented in the spec.
- [An unreachable anchor abandons the stance] → `pathfinding_failed` clears it rather
  than retrying forever; the unit keeps its existing idle guard behavior.
- [MouseHandler merge conflict with #514] → The MouseHandler change is confined to
  the stop branch; merge after #514 and re-run the suite.

## Migration Plan

No data or scene migration. Behavior change is limited to the Ctrl+Alt click
combination, which previously fell back to force-move.

## Open Questions

None.
