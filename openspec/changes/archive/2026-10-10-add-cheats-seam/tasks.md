# Tasks

## 1. Repair the target spec and add `Cheats`

- [x] 1.1 Repair `openspec/specs/debug-menu/spec.md:1` (`## ADDED Requirements` →
      `## Requirements`) and verify `openspec validate add-cheats-seam --strict` reports no
      "debug-menu target spec is structurally invalid" archive INFO.
- [x] 1.2 Create `scripts/core/Cheats.gd` (`class_name Cheats`) with `static var no_prereqs`,
      `no_build_time`, `no_cost`, `place_anywhere` (all `= false`) and a static `reset()`; add its
      `.uid`. Add `test/unit/test_cheats.gd` that calls `Cheats.reset()`, asserts every flag is
      false, sets one flag, then asserts `reset()` clears it; run
      `redot --headless -s test/run_tests.gd`.
- [x] 1.3 Add a `Cheats` entry to `GLOSSARY.md` (shared debug cheat-flag state, node-free, false
      default, single writer); verify the entry is present and cross-links the `cheats` spec.

## 2. Make the debug panel the writer

- [x] 2.1 Point `DebugMenu`'s checkbox handlers (`_on_no_prereqs_toggled`, the `no_build_time`/
      `no_cost` lambdas, `_on_place_anywhere_toggled`) and `reset_state()` at `Cheats`; delete the
      four node fields. Add a `test_cheats.gd` case that instantiates `scenes/ui/DebugMenu.tscn`
      (the pattern in `test/unit/test_debug_menu_radar.gd`), toggles `cb_no_cost`, asserts
      `Cheats.no_cost`, calls `reset_state()`, and asserts the flags are false; run it plus
      `test/unit/test_debug_menu_radar.gd`.

## 3. Point readers at `Cheats`

- [x] 3.1 Replace the group lookup with direct reads in `PrerequisiteSystem.can_build`,
      `EconomyManager.deduct`, and `AudioManager._on_production_stalled`; verify
      `test/unit/test_tech_level_gate.gd` and the economy suites pass.
- [x] 3.2 Replace the group lookup with direct reads in `ProductionManager._process` and
      `handle_cameo_left_click`, `BuildingManager._place_anywhere_active`, and
      `Sidebar._on_cameo_gui_input`; verify the production, placing, and sidebar suites pass.

## 4. Remove the fakes and lock test isolation

- [x] 4.1 Extend `TestHelper.reset()` (`test/test_helper.gd`) to also call `Cheats.reset()`; verify
      `test_cheats.gd`'s defaults-false case still passes when run after the flag-setting suites
      (run the full suite and confirm no cross-suite leakage).
- [x] 4.2 Delete the `FakeDebugMenu` classes in `test/unit/test_cameo_click_policy.gd`,
      `test/unit/test_placing_session.gd`, and `test/unit/test_tech_level_gate.gd`; run all three
      suites and confirm they pass with no `debug_menu` group node created.

## 5. Guard the seam

- [x] 5.1 Add `test/unit/test_cheats_seam.gd`, a source scan over `scripts/` asserting
      `get_first_node_in_group("debug_menu")` appears only in `UIUtil.gd` and
      `FPSCounterLabel01.gd`; prove it fails against a scratch reintroduction, then confirm it
      passes on the real tree.

## 6. Integration verification

- [x] 6.1 Run `gdformat --check` + `gdlint` on `scripts/` and `test/`, plus the full
      `redot --headless -s test/run_tests.gd` suite, and confirm all green.
