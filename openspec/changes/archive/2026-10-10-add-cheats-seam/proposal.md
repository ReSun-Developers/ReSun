# Proposal

## Why

Five simulation autoloads (`PrerequisiteSystem`, `EconomyManager`, `ProductionManager`,
`AudioManager`, `BuildingManager`) and the `Sidebar` read the four cheat flags by looking up
a **UI node** through `get_tree().get_first_node_in_group("debug_menu")` and duck-typing its
fields. In release, `DebugMenu._ready` frees itself, so the lookup returns null and cheat state
silently falls back through a node that is not there — simulation depends on presentation via a
string that fails quietly. The shape is re-implemented three times — four-field `FakeDebugMenu`
classes in `test_cameo_click_policy.gd` and `test_placing_session.gd`, plus a single-flag inline
fake in `test_tech_level_gate.gd` — purely to satisfy that lookup.

## What Changes

- Add `Cheats`, a `class_name` global that holds the four cheat flags as `static var`s — no
  node, no autoload, no scene, defaults false — plus `reset()`.
- `DebugMenu` becomes the **only writer**: its checkbox handlers and scene reset write `Cheats`
  instead of local fields; it holds no cheat state.
- Simulation and UI consumers read `Cheats.<flag>` directly by identifier.
- Keep `DebugMenu`'s `debug_menu` group membership: the two UI-only `_is_open` hover reads
  (`UIUtil.is_mouse_over_debug_menu`, `FPSCounterLabel01`) stay group-based and are out of scope.
- Delete the three `FakeDebugMenu` test copies; suites set `Cheats` directly.
- Extend `TestHelper.reset()` — already invoked before every test method by the runner
  (`test/run_tests.gd:87`) — to also clear `Cheats`, so the process-global statics cannot leak
  between suites (the runner runs them all in one process).
- Add a source-scan guard test forbidding `get_first_node_in_group("debug_menu")` outside the two
  UI `_is_open` files, so the seam cannot silently regress.
- Repair the canonical `openspec/specs/debug-menu/spec.md` header (a botched prior archive left
  `## ADDED Requirements` at line 1), which hides every requirement from the parser and would make
  this change un-archiveable.
- No new autoload (stays at 36), no scene change, no data format change.

## Capabilities

### New Capabilities

- `cheats`: a single node-free shared value for the debug cheat flags — false defaults, one
  writer, direct-read contract, group-independent.

### Modified Capabilities

- `debug-menu`: cheat flags are no longer stored on the `DebugMenu` node nor read through the
  `debug_menu` group; the panel writes the shared `Cheats` value, and a release build with no
  panel reads every flag false.
- `building-manager`: the debug place-anywhere scenario conditions on `Cheats.place_anywhere`
  instead of `debug_menu.place_anywhere`.
- `production-manager`: the debug instant-build requirement conditions on `Cheats.no_build_time`
  instead of `debug_menu.no_build_time`.

## Impact

- New: `scripts/core/Cheats.gd` (and its `.uid`); new `test/unit/test_cheats.gd` and
  `test/unit/test_cheats_seam.gd`.
- Writer: `scripts/ui/DebugMenu.gd`.
- Readers: `scripts/production/PrerequisiteSystem.gd`, `scripts/economy/EconomyManager.gd`,
  `scripts/production/ProductionManager.gd` (two sites), `scripts/core/AudioManager.gd`,
  `scripts/buildings/BuildingManager.gd`, `scripts/ui/Sidebar.gd`.
- Test infra: `test/test_helper.gd` (`reset()` also clears `Cheats`).
- Tests: fakes removed from `test/unit/test_cameo_click_policy.gd`,
  `test/unit/test_placing_session.gd`, `test/unit/test_tech_level_gate.gd`;
  `test/unit/test_debug_menu_radar.gd` is unaffected.
- Spec repair: `openspec/specs/debug-menu/spec.md:1` (`## ADDED Requirements` → `## Requirements`).
- Docs: `GLOSSARY.md` gains a `Cheats` entry.
- No autoload, scene, or data-format change; single-player behavior unchanged.
