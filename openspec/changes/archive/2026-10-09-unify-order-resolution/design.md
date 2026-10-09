# Design

## Context

Components already return an `OrderResult` carrying `cursor` (the 2026-07-25 decision #1). The split is one
layer up: `UnitOrderGenerator` exposes `get_cursor` and `get_orders` as independent trees, and
`MouseHandler._update_cursor:634` re-decides `SELECT` for an empty selection because `get_cursor` returns
`DEFAULT` before consulting selection. The dispatch tail (`play_order_voices` -> execute loop ->
`acknowledge_target_lines`) exists in `MouseHandler._try_execute_orders:348`, the ground path `:338`, and
`Minimap._handle_click:769`; the minimap imports the MouseHandler statics.

## Goals / Non-Goals

**Goals:**

- One decision that yields both cursor and orders, at every generator.
- Finish the 2026-07-25 cleanup: remove `get_cursor_for_target` from the four remaining components.
- Move the dispatch tail onto the order funnel.
- Make `MOD_FORCE_MOVE` functional.

**Non-Goals:**

- `OrderResolver._is_better` tie-breaking (spec `:82` says earlier entity index wins; current code returns
  false on ties). Left as-is except for deterministic iteration; not part of this change.
- Netcode/order serialization, order queue UI, animated cursors.
- Routing the deploy/stop hotkeys through the order funnel — they are target-less commands, a separate seam.

## Decisions

### 1. `OrderResolution` value, with `get_cursor`/`get_orders` as projections

`OrderSystem.resolve()` returns `OrderResolution { cursor, orders }`; the two existing methods project it.
Retaining the views keeps every existing direct caller and test (`get_cursor`/`get_orders`) green while the
decision is unified. Alternatives: (a) a private shared resolver with no new type — rejected, no vocabulary
for the concept; (b) `get_cursor` derives from `get_orders` — rejected, forces full-order allocation on the
per-frame cursor path.

### 2. Cursor computed in the same pass as orders, with a single-result fast path

`resolve()` collects per-entity orders via `OrderResolver.resolve_all()` and takes the max for the cursor. To
avoid retaining a full array on the per-frame cursor path, the generator MAY compute the best only when the
caller requests cursor-only; `OrderResolution.orders` is then empty. Mitigation documented under Risks.

### 3. Cursor-only affordances live in the resolution

`SELECT`, `GENERIC_BLOCKED`, and the move fallback become the resolution's cursor when no order is produced,
including the empty-selection `SELECT` case. `MouseHandler._update_cursor` stops re-deciding it. This makes
the affordance testable through `OrderSystem` without constructing a HUD node.

### 4. Dispatch ownership: `OrderSystem.issue()`

The voice/execute/acknowledge tail moves to `OrderSystem`, which already owns the funnel and can reach
`SelectionManager`. `MouseHandler` and `Minimap` call `issue()`. `build_modifiers()` moves alongside it since
the minimap already imports it. Alternative: a separate dispatcher node — rejected, YAGNI; two callers.

### 5. Force-move is self-declared per component

`CombatComponent.get_order_for_target` returns null while `MOD_FORCE_MOVE` is held; `MovementController`
returns a MOVE order for entity and ground targets using the click position. This mirrors 2026-07-25
decision #1 (each component declares its own behavior) instead of priority inversion. Alternative: raise the
MOVE priority above ATTACK — rejected; priority is for disambiguation (deploy vs move), not modifier
overrides.

Note: the resolver short-circuits a force-move by synthesizing the move itself, so no component targeter
(including Passenger/Harvest/Deploy/Transport) can outrank it. Ctrl+Alt+Click is the original's **Guard
Area** (unimplemented here) — not force-fire — so while both modifiers are held the move wins as a fallback;
implementing Guard Area is a separate change.

## Risks / Trade-offs

- **Per-frame cursor cost**: merged resolution retains N results vs `resolve_single`'s one. Today both already
  allocate one `OrderResult` (with closure) per component per selected entity, so the delta is an array of
  references. Add a cursor-only fast path if profiling shows a regression.
- **Behavior parity**: the two trees differ on tail cases (cursor-only affordances produce no orders). Each
  merged branch needs a characterization assertion before deletion; the existing `test_unit_order_generator`
  and `test_order_bounds` suites are the guard.
- **Test churn**: removing `get_cursor_for_target` touches ~37 call sites across 4 test files; each is
  re-expressed as `get_order_for_target(...).cursor`.
- **Empty-selection SELECT move** could shift cursor behavior if the resolution sees different state than
  `_update_cursor` did; covered by a dedicated scenario.
