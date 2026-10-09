# Tasks

## 1. Build-gate query on PrerequisiteSystem

- [x] 1.1 Add the `BuildReason` enum and `evaluate_build(player_id, data) -> Dictionary` to
  `scripts/production/PrerequisiteSystem.gd`, extracting the existing `can_build` body and
  folding the `buildable` menu flag in as the first gate (`not_buildable`); return
  `enabled`, `reason`, `cost`, and `owned_factory`. In the same task set
  `data.buildable = true` in `test/unit/test_tech_level_gate.gd._data()` so the suite stays
  green. Verify `test/unit/test_prerequisite_system.gd` and `test/unit/test_tech_level_gate.gd`
  both pass via `redot --headless -s test/run_tests.gd`.
- [x] 1.2 Reduce `can_build` to `return evaluate_build(player_id, data).enabled` and confirm
  no caller changed behavior. Verify `test/unit/test_production_manager.gd` and
  `test/unit/test_cameo_click_policy.gd` still pass.
- [x] 1.3 Extend `test/unit/test_prerequisite_system.gd` to assert the reason per gate
  (`never`, `tech_level`, `build_limit`, `prerequisite`, `prerequisite_necessary`,
  `no_factory`, `not_buildable`), the happy-path `none`, and the gate-order rule (a type both
  above tech level and missing a prerequisite reports `tech_level`). Verify the new assertions
  fail before 1.1 lands and pass after.
- [x] 1.4 Update `test/unit/test_tech_level_gate.gd` for the new `not_buildable` rejection
  (a `buildable = false` type is refused when `no_prereqs` is off and accepted when it is on).
  Verify the suite passes.
- [x] 1.5 Add the `build gate` term to `GLOSSARY.md` (pointing at the new capability) and
  verify the link target exists.

## 2. Player-scoped ownership

- [x] 2.1 Source `owned_factory` in `evaluate_build` from the owned-buildings registry
  (`_player_buildings`), computed unconditionally **before** the `no_prereqs` early-return;
  return `false` when `buildable_queue` is empty and skip the `no_factory` gate there. Verify
  with `test_prerequisite_system` cases: player A owns the producer and player B does not
  (A enabled with `owned_factory` true, B `no_factory` with `owned_factory` false); under
  `no_prereqs` with no producer, `enabled` true and `owned_factory` false; a building
  (empty queue) reports `owned_factory` false and is not failed on `no_factory`.
- [x] 2.2 Delete `ProductionManager.has_factory_for` and route
  `handle_cameo_left_click`'s direct-deploy fallback through
  `PrerequisiteSystem.evaluate_build(clicking_player, data).owned_factory`. Verify
  `test/unit/test_cameo_click_policy.gd` passes after updating `_make_real_factory_node` to
  register an owned building (real `EntityData` with a matching `factory`) instead of a bare
  `FactoryComponent` node.
- [x] 2.3 Add a `test_cameo_click_policy` case proving the fallback fires for the clicking
  player when only another player owns a matching producer. Verify the case fails against the
  old group-scan behavior and passes against the registry source.

## 3. Sidebar and credit warning

- [x] 3.1 Switch `Sidebar._get_current_entities` to `evaluate_build`; delete the `data.buildable`
  pre-filter and the dead `build_limit` grey branch in `_create_cameo`. Verify
  `test/unit/test_sidebar_build_order.gd`, `test/unit/test_sidebar_cameo.gd`, and
  `test/unit/test_sidebar_tabs.gd` pass, and that a non-buildable type is absent without the
  cheat and present with `no_prereqs` on.
- [x] 3.2 Make `CreditCounter._compute_cheapest_cost` keep only types where
  `evaluate_build(local_player, data).enabled` and `cost > 0`, and recompute `_cheapest_cost`
  on `prerequisites_changed`, `players_changed`, and `GameContext.game_changed` (not
  `credits_changed`). Register a local-player producer fixture in `test_credit_counter.gd` so
  the set is non-empty, and fix the existing threshold test's "no buildable entity" guard.
  Add the missing assertions: a cheap but locked item does not trigger the warning, the warning
  is off when the player can build nothing, and the cached cheapest refreshes when
  `prerequisites_changed` fires. Verify `test/unit/test_credit_counter.gd` passes.
- [x] 3.3 Give `EconomyManager.can_afford` (still a pure `balance >= cost`) its first caller:
  use `not Cheats.no_cost and not can_afford(...)` in `CreditCounter._update_credits_color`,
  and assert in `test_credit_counter.gd` that `evaluate_build` reports an unaffordable type
  enabled (affordability is not a gate). Verify `test/unit/test_economy_manager.gd` and
  `test_credit_counter.gd` pass.
- [x] 3.4 Correct the stale `tech_level = -1` "always available" wording to "never buildable"
  in the archived `sidebar-build-order` spec and in the `test/unit/test_sidebar_build_order.gd`
  comments, keeping the sort behavior (`-1` first) unchanged. Verify
  `test/unit/test_sidebar_build_order.gd` still passes.

## 4. Integration verification

- [x] 4.1 Add an integration check proving the build list and the production gate share one
  decision: a type failing the gate for a player is absent from that player's list and refused
  by `start_production`, and a gated-in type is both shown and accepted. Verify `test/` gains
  the case and it passes.
- [x] 4.2 Run the full suite: `redot --headless -s test/run_tests.gd`. Verify all suites pass
  with no new failures.
- [x] 4.3 Run `gdlint scripts/**/*.gd test/**/*.gd` and
  `gdformat --check scripts/**/*.gd test/**/*.gd`; fix any findings.
- [ ] 4.4 Manually confirm in-game: a type behind an unmet prerequisite is hidden; an
  affordable-but-unlocked type shows and, when unaffordable, stays clickable and funds
  gradually as credits accrue; the credit counter reds only against types the player can
  build.
