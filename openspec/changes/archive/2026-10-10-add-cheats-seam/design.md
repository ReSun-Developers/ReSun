# Design

## Context

See `proposal.md` — Why. The current cheat state is four `var` fields on the `DebugMenu`
`Control`. Seven read sites across six scripts (five simulation autoloads plus `Sidebar`;
`ProductionManager` reads twice) fetch the node via
`get_tree().get_first_node_in_group("debug_menu")` and duck-type those fields; `DebugMenu` is
freed in release, so every read silently falls through a null node. The project's autoload work
(`2026-10-02-make-autoload-dependencies-explicit`) established two constraints this design must
respect: autoloads accessed by registered identifier (not `/root` strings), and **no new
autoload / service locator** without a second implementation to justify it. Issue #473 is trying
to *reduce* the autoload count, so adding a singleton is undesirable.

## Goals / Non-Goals

**Goals:**

- Cheat state is readable and writable with no scene node present.
- One writer (the panel); readers read by identifier.
- Remove the three duplicated `FakeDebugMenu` test nodes.

**Non-Goals:**

- The two UI-only `_is_open` reads (`UIUtil.is_mouse_over_debug_menu`, `FPSCounterLabel01`)
  stay on the `debug_menu` group.
- No write-side change events: `DebugMenu` keeps owning its side effects (arming
  `EntityPlacer`, refreshing the sidebar). No `Cheats.changed` signal.
- No change to `RadarSystem.force_online` or the fog/shroud cheats.

## Decisions

### D1: `class_name Cheats` with static fields, not an autoload

`Cheats` is a script with four `static var`s and a static `reset()`. Access is `Cheats.no_cost`
exactly like a singleton, but there is no node, no `project.godot` entry, and no lifecycle. This
keeps the autoload count at 36 (aligned with #473) and sidesteps the "no second registry" rule
from the archived autoload change — `Cheats` is a named set of statics, not a keyed lookup.

*Alternatives considered:*

- **New `Cheats` autoload** — matches the issue's literal wording, but adds another singleton for
  four booleans and runs against #473. Rejected.
- **`Cheats` RefCounted held by an existing global** (e.g. `DebugVisualizer.cheats`) — avoids a
  new autoload but needs an arbitrary host and reads as indirection for no gain, since there is
  no second implementation to swap. Rejected.
- **Keep a node + group, just rename** — does not remove the simulation→UI dependency. Rejected.

### D2: No test stub replaces the fakes — a reset seam instead

The three `FakeDebugMenu` classes exist only to satisfy the group lookup; with static fields
there is nothing to fake, so all three are deleted. That makes `Cheats` process-global static
state, and the runner runs every suite in one process (`test/run_tests.gd:58-60`) with **no
per-suite teardown hook** — it only calls `TestHelper.reset()` before each test method
(`test/run_tests.gd:87`). Leaking a set flag would corrupt later suites that assert rejection
(e.g. `test_tech_level_gate.gd`).

`TestHelper.reset()` is therefore extended to also call `Cheats.reset()`. This is the smallest
shared seam that makes isolation order-independent: it is not a fake (no object stands in for
production), just a reset call at the one point the runner already invokes. Suites that set a
flag simply set it within the test method, and it is cleared before the next method.

*Alternatives considered:* a shared `FakeCheats` instance swapped into a holder — unnecessary
without an instance to swap. Per-suite `_setup`/`_teardown` methods — the runner does not call
them and adding that hook is a larger change than one reset line. Rejected.

### D3: Keep the `debug_menu` group

`DebugMenu` keeps `add_to_group("debug_menu")` because `_is_open` hover reads still use it. This
change only removes *cheat-flag* reads from the group, matching the issue's acceptance ("no
simulation read of the `debug_menu` group") and its stated out-of-scope.

### D4: Defaults live on the fields

`static var ... = false` gives the release default and the no-node case for free; no reset-on-boot
logic is needed. `DebugMenu.reset_state()` calls `Cheats.reset()`, then sets the checkboxes to
unchecked (re-emitting `toggled`, which writes false again — idempotent). Automatic reset on map
load stays a panel behaviour (wired through `DebugMenu._on_node_added`); in release the panel is
absent, but nothing writes flags there either, so the defaults hold without it.

### D5: Guard the seam with a source scan

The acceptance "no simulation read of the `debug_menu` group" is a lint-shaped invariant, like the
existing `test/unit/test_autoload_access.gd`. Add `test/unit/test_cheats_seam.gd`, which parses
`scripts/` and asserts `get_first_node_in_group("debug_menu")` appears only in `UIUtil.gd` and
`FPSCounterLabel01.gd`. A runtime probe cannot catch a reintroduced lookup, so the scan is the
only check that fails on the regression.

### D6: Repair the canonical `debug-menu` spec header in this change

`openspec/specs/debug-menu/spec.md:1` currently reads `## ADDED Requirements` (a prior archive
left a delta header in the merged spec), so the parser hides every requirement — including the
"Cheat toggles" requirement this change modifies — and `openspec archive` refuses the delta.
Normalize it to `## Requirements` as the first task, before the code work, so the change is
archiveable. (This defect affects ~24 other specs; repairing those is out of scope.)

## Risks / Trade-offs

- **Static state leaks between test suites (single process).** → `TestHelper.reset()` clears
  `Cheats` before every test method (`test/run_tests.gd:87`), so isolation is order-independent
  and does not rely on each suite remembering to reset.
- **A future writer bypasses the single-writer contract.** → `debug-menu`'s spec states the panel
  is the only writer; reviewers can grep for `Cheats.<flag> =` (assignments) outside `DebugMenu`.
- **`class_name` is registered in the global class list, so the first access is parse-time.**
  → No runtime initialization exists to order; nothing reads flags in `_ready`.
- **Removing the flags from `DebugMenu` breaks any `.tscn` that stored them.** → The fields are
  plain `var`s (not `@export`), so `scenes/ui/DebugMenu.tscn` does not persist them; verified no
  references.

## Migration Plan

Strangler, suite green between steps:

1. Repair `openspec/specs/debug-menu/spec.md:1` (`## ADDED Requirements` → `## Requirements`).
2. Add `scripts/core/Cheats.gd` (+ `.uid`) with the four flags and `reset()`.
3. Extend `TestHelper.reset()` to clear `Cheats`.
4. Point `DebugMenu` writes (checkbox handlers, `reset_state`) at `Cheats`; drop its fields.
5. Point the seven reader sites at `Cheats`.
6. Delete the three `FakeDebugMenu` classes.
7. Add the seam-guard scan test and the `Cheats` entry to `GLOSSARY.md`.
8. Run `gdformat` + `gdlint` and the full suite.

Rollback: revert the commit; no scene, autoload, or data-format change to unwind.
