# Design

## Context

See `proposal.md` — Why. Two facts shape the approach:

1. **The spec'd rationale was real but its cause was a bug.** `openspec/specs/debug-menu/spec.md`
   mandates poll-based session input because "mouse events do not reach `_unhandled_input` at runtime
   in this codebase". The live-match check confirmed mouse placement/cancel never reached
   `_unhandled_input` while ESC did. Root cause: `scenes/ui/FPSCounter01.tscn`'s root `FpsCounter` is
   a full-rect `Control` left at the default `mouse_filter = STOP`, so it swallowed every pointer
   event over the world; keyboard events are not GUI-consumed, hence "only ESC worked". A static
   review missed it because `FpsCounter` had no explicit `mouse_filter` line. Fix: set the FpsCounter
   root and label to `MOUSE_FILTER_IGNORE`. The `Viewport.push_input` probe
   (`test/integration/test_input_pipeline.gd`) shows the mechanism works once no Control consumes the
   event, and now also guards the FpsCounter property so the regression cannot return silently.
2. **`MouseHandler` polls raw `Input` and ignores `set_input_as_handled`.** So a commit/cancel consumed
   by a session's `_unhandled_input` would *also* be seen by `MouseHandler._process` unless latched.
   The cross-module latch is not a symptom of session polling; it exists because `MouseHandler` polls.

## Goals / Non-Goals

**Goals:**
- Placement commit/cancel driven by `_unhandled_input` for both `BuildingManager` and `EntityPlacer`.
- Delete both `_skip_input_frames` counters and both `_process` input-poll branches.
- Make the placement input path testable by driving `_unhandled_input` with synthesized events.
- Correct the two specs that codify the poll mandate (its real cause — the FpsCounter eating clicks — is fixed).

**Non-Goals:**
- Converting `MouseHandler` to `_unhandled_input` (order-funnel input contract — separate change).
- Unifying the two sessions into one shared state machine (#340).
- Merging the two preview renderers (schematic vs ghost).

## Decisions

### D1: `_unhandled_input` is the commit/cancel path; `_process` keeps reposition only
Commit (`select_entity`) and cancel (`deselect_entity`/`ui_cancel`) are handled in `_unhandled_input`
with `set_input_as_handled()`, mirroring `EntityPlacer`'s existing branches. `_process` retains only
`_update_preview_position()` because camera pans emit no motion events (`sidebar-ui-thinning/design.md` D2).
*Alternative considered:* keep the poll and only extract a testable method (fallback B). Rejected once
Phase 0 disproved the premise — B would preserve the untestable seam and the false spec.

### D2: The arming-click hazard disappears; the cross-module commit latch stays, no cancel latch
The click that arms a session is a cameo `Button` press, consumed by the GUI before `_unhandled_input`,
so no skip-frame counter is needed on the event path. But `MouseHandler._process` still polls raw
`Input`, so the session must expose a same-frame "consumed click" latch for the **commit** click
(`exiting_build_mode` for `BuildingManager`, `did_consume_click_this_frame()` for `EntityPlacer`).
**No cancel latch is added.** Right-click in build mode already deselects today: the press frame exits
build mode via `BuildingManager._process`, then the release frame reaches `MouseHandler`'s
`deselect_all()`; the event-driven path produces the same sequence because `set_input_as_handled()`
does not affect `MouseHandler`'s raw `Input` poll. A cancel latch would *change* behavior and break the
"identical at runtime" invariant, so it is explicitly out of scope. A characterization test pins the
existing behavior.

### D3: Ordering assumption — input phase precedes `_process`
An autoload's `_unhandled_input` runs in the input phase, before scene-node `_process`. So a latch set
during commit is visible to `MouseHandler._process` in the same frame. This is the assumption
`EntityPlacer` already relies on (asserted by `test_placing_session`'s commit tests) and the change
extends it to `BuildingManager`. Cross-handler *ordering* (BuildingManager vs PauseMenu ESC, and
autoload vs scene-node) cannot be reproduced by the headless `push_input` harness, so it is verified
by the live check rather than a unit test.

### D4: Spec scenario names are retained, not renamed
OpenSpec treats scenario names as stable anchors: a MODIFIED requirement that drops a scenario name
fails `validate` (a rename reads as a drop). So the two `debug-menu` scenarios keep their original
names (`Commit is poll-driven`, `Cancel is poll-driven`) with rewritten, mechanism-accurate content.
The stale-sounding labels are a tooling constraint; correcting the names would require a separate
mechanism the schema does not provide. Follow-up: rename once the tool supports scenario renames.

### D5: Requirement prose states behavior, not mechanism
The deltas state the observable contract (commit/cancel resolve from input events) without re-mandating
a specific phase ("rather than per-frame polling"), so the spec does not repeat the coupling this
change removes. The `stop_placing()` typo inherited from the current spec is corrected to
`exit_placing_mode()`, and `build_mode_changed` is documented with its real signature
`(is_active: bool, player_id: int)`.

### D6: Test seam is `_unhandled_input`, not a new injection method
Tests synthesize `InputEventAction` and call `_unhandled_input` directly (the pattern in
`test_placing_session.gd`). No new "handle input" method is introduced, so the public surface does not
grow. Fallback B's `_handle_build_mode_input(...)` is only needed if the premise had held.

## Risks / Trade-offs

- **The harness cannot model GUI consumption, so live-check matters.** Headless `push_input` reaches
  `_unhandled_input` even under a full-rect `STOP` Control, so it could not catch the FpsCounter bug;
  the live check did. → The FpsCounter `mouse_filter` is now pinned by
  `test_fps_counter_does_not_consume_pointer`, and any future full-rect HUD `Control` at `STOP` is the
  first suspect for "mouse input works via poll but not via events". The explicit
  `UIUtil.is_mouse_over_minimap()` gate stays (mandatory, not belt-and-braces).
- **Right-click cancel already deselects.** → Not a regression: pinned by
  `test_building_manager_input.gd`; no cancel latch (D2).
- **Escape ordering with the pause menu.** `PauseMenu._esc_busy()` reads `is_build_mode` from its own
  `_unhandled_input`; ESC must exit build mode without also pausing. → Covered by `PauseMenu`'s own
  `_esc_busy` path and the live check (headless `push_input` cannot reproduce the input-phase order).
- **EntityPlacer's commit-click latch only covers the press frame (pre-existing).** `MouseHandler`
  processes the *release* on a later frame, so a single click can still resolve on release;
  `BuildingManager` avoids this via `MouseHandler`'s `_skip_release`. Not introduced by this change
  (the removed poll set the same same-frame latch), but the delta's "commit click does not leak"
  scenario overstates the guarantee. Left as-is; a release-frame suppression is a separate fix.
- **`exiting_build_mode` is only cleared by `MouseHandler`** (`MouseHandler.gd:132`), so a headless
  commit test can leak it into later suites. → Reset it in `enter_build_mode()` (not in
  `exit_build_mode()`, which the commit handshake calls after setting the flag).
- **Minimap is `mouse_filter = STOP`,** so it already consumes left-clicks; the explicit
  `UIUtil.is_mouse_over_minimap()` gate is retained in both sessions (harmless, matches
  `gameplay-minimap/spec.md` wording). `EntityPlacer._unhandled_input` must gain the gate the deleted
  poll branch held.
- **`process_mode`/pause interactions.** `PauseMenu` runs with `process_mode = 3`; the session is
  inactive when paused, so its `_unhandled_input` should not fire then. → Covered by the pause tests.

## Migration Plan

Single change, no data migration. Land scripts + spec deltas + tests together; the suite and the live
match are the gates. Rollback is reverting the scripts (spec deltas are additive/corrective and stay).

## Open Questions

- Whether `MouseHandler` should also move to `_unhandled_input` (removing the last raw poll in the
  placement path) is deferred to its own change; not needed for this one.
