# Design

## Context

`OrderSystem.resolve(target, target_cell, target_pos, modifiers)` is the order-intake funnel: bounds gate → fog filter → shroud gate → active generator, returning an `OrderResolution` (cursor + orders decided together). The tuple's *construction* lives outside it, scattered across four call sites that re-derive cells/positions and mutate `MOD_TARGET_LEVEL` by hand. Hover preview and left-click each carry a twin copy of the same 2-pass raycast (layer 16 → 17). See proposal.md for motivation.

Constraints from #508: keep `resolve` + both projections (zero spec deltas), don't touch right-click cancel, hover lag/miss-count semantics, or `MOD_TARGET_LEVEL`-into-hover (archived rejection), and don't move pre-intake mode gates.

## Goals / Non-Goals

**Goals:**

- One typed input (`OrderProbe`) so every intake caller builds the quadruple through named factories; level/modifier policy becomes impossible to forget
- One mouse probe for the duplicated hover/click raycast, with policy staying at call sites
- Behavior-identical diff guarded by the existing order/hover test suites

**Non-Goals:**

- Hover-resolution caching (invalidation drift risk, not a measured cost)
- Removing `get_cursor`/`get_orders` (spec-mandated; separate change)
- Changing `resolve()`'s tuple signature (see Decisions)
- Unifying hover and click *policy* (fog gate, miss-count, select-vs-order) — only the raycast is shared

## Decisions

### D1: `OrderProbe` with three factories, policy encoded in names

`OrderProbe` holds the quadruple; factories map to the three real call-site shapes:

- `from_entity(target, shift)` — cell/pos from `target.global_position`, no `MOD_TARGET_LEVEL` (hover must not gain it; click entity path doesn't set it either)
- `from_ground(ground_pos, level, shift)` — ground or deck position; always sets `MOD_TARGET_LEVEL` (level 0 included, matching today's move-order tail and hover ground path behavior once routed here)
- `from_cell(cell, target, world_pos, level, shift)` — minimap; always sets `MOD_TARGET_LEVEL` from `_top_surface_level`

**Alternatives considered:**

- *Loose helper functions returning a 4-tuple* — no type, callers can still mutate `modifiers` afterward. Rejected: the whole bug class is post-hoc dict mutation.
- *Only `from_ground`/`from_cell`, keep entity sites hand-building* — leaves 2 of 4 sites outside the seam. Rejected.

**Note on hover ground path:** today hover's ground pick does not set `MOD_TARGET_LEVEL` (defaults to 0 inside `UnitOrderGenerator`). Routing it through `from_ground(..., level)` with level 0 is observationally identical — factory always sets the key, generator already reads `.get(key, 0)`.

### D2: `resolve_probe()` is seam glue, not a second funnel — why not change `resolve()`'s signature

`openspec/specs/order-system/spec.md` requires `OrderSystem` to expose `resolve()`, `get_cursor()`, `get_orders()` where the projections "return the corresponding field of `resolve()` for the same input." The spec does not constrain how *callers* build the tuple, but it does make the tuple-shaped surface the contract that ~37 test call sites and the projection-parity scenario depend on.

Options:

| Option | Verdict |
|---|---|
| **A. `resolve_probe(probe)` wraps tuple `resolve()`** (chosen) | Spec surface untouched, zero deltas, projections unchanged. Cost: one shallow method. |
| B. Change `resolve(probe)` + rewrite projections and all callers | "Same input" contract re-specified; ~37 test sites rewritten; spec delta required. Bigger diff, zero behavior gain. |
| C. `probe.resolve()` method on the data class | Inverts dependency (data class → OrderSystem autoload); resolution logic stops living at the order seam. Rejected. |

`resolve_probe` fails the deletion test *in isolation* (pure pass-through), but it exists to keep the probe as the only thing callers touch — the depth lives in the factories (modifier policy) and the existing funnel. Justified as the adapter at the seam; if a future change kills the tuple surface (the `get_cursor` removal follow-up), `resolve` absorbs the probe and this method disappears.

### D3: `_probe_pointer` in MouseHandler; policy stays at call sites

One private method returns the raw probe facts as nested dicts — `{"unit": {select_comp, entity}, "interact": {entity}}` — doing the shared 2-pass raycast. Ground picks stay at the call sites (`_get_ground_position_at_mouse*`); `MouseHandler` owns the probe because raycasting needs the camera/`DirectSpaceState` — that knowledge must not cross into the order side.

- `_handle_hover_preview` keeps its fog gate and `_hover_miss_count` logic around the probe result
- `_handle_left_click_normal` keeps select-vs-order ordering and shift semantics around it
- `_update_cursor` keeps reading lagged `_hovered_entity` (no fresh raycast — preserves #499-era lag semantics)

**Alternative considered:** probe owned by OrderSystem — rejected; would drag camera/physics into the order module for no caller benefit (minimap doesn't raycast).

### D4: No cache

Caching cursor resolutions keyed on (selection epoch, modifiers, hover identity) was issue option 2. Skipped: invalidation mistakes reintroduce cursor/click drift — the exact #499 bug class — and the hot path is one `resolve()` per frame only when not over UI. Add only if profiling shows churn.

## Risks / Trade-offs

- [_probe_pointer subtly changes raycast behavior (mask order, `collide_with_areas`)] → Copy semantics verbatim from both existing sites; `test_mouse_handler_hover` must pass **unchanged** — it pins lag/miss-count.
- [Ground-move tail argument drift (`null` target, `Vector2i.ZERO`, leveled pos)] → `from_ground` must reproduce today's exact arguments; regression covered by existing move-order tests.
- [New shallow method `resolve_probe` accumulates "just one more entry point"] → design.md names its deletion condition (tuple surface dies with the `get_cursor` follow-up); do not add further wrappers.
- [Factory test becomes tautological (asserting the factory does what it does)] → Assert *policy differences between factories* (entity omits level, ground/cell set it), which is the drift class the refactor kills.

## Migration Plan

Single PR, behavior-identical. Order: add `OrderProbe` + factories + test → add `resolve_probe` → extract `_probe_pointer` (hover first, verify hover test) → rewire click → rewire minimap → delete now-dead inline assembly. Rollback = revert PR; no data/migration concerns.

## Open Questions

None — level policy, seam placement, and scope are settled above.