# Tasks

## 1. Pin current occupancy semantics

- [x] 1.1 Add characterization tests for `_is_cell_occupied_by_idle` / `_is_destination_clear`:
      building above level 0 blocks the idle predicate but not the destination predicate; a
      grid entry with `mc = null` is ignored by the idle predicate but blocks the destination
      predicate. Run `flock /tmp/opencode/redot.lock redot --headless -s test/run_tests.gd`
      and record the pass on base.
- [x] 1.2 Change the characterization expectations to the chosen rule (building ground-only,
      no-MC entry ignored, non-sharing unit blocks, sharing mover ignores sharers) and run them
      against base. Confirm the deck and no-MC destination cases fail by assertion for the
      intended reason; keep the output for the PR evidence.

## 2. Extend the occupancy snapshot

- [x] 2.1 Add `shared_moving` to `CellOccupancy`, classify moving sharers into it instead of
      `moving`, and make `is_cell_free_for_unit_exit` refuse `shared_moving`. Verify with
      `test/unit/test_cell_occupancy.gd` (add a moving-sharer case).
- [x] 2.2 Update the `cell-occupancy` and `spatial-hash` spec deltas and the class doc comment
      to describe the four-way partition; run `openspec validate refactor-mc-interface`.

## 3. Close the MovementController interface

- [x] 3.1 Add `get_state()`, `is_idle()`, `get_surface_level()`, `is_exact_move()`,
      `has_sub_slot()`, `get_sub_slot_position()`, `apply_locomotor()`, `tick()`,
      `place_at_sub_slot()` and `release_sub_slot()`; make `_resolve_locomotor` delegate to
      `apply_locomotor`. Add `MovementFactory.make_movement_controller` (`test/movement_test_factory.gd`)
      in the same step and verify it builds a working controller.
- [x] 3.2 Rename `set_target_position` to private `_set_target_position`, add `move_to`,
      `player_move`, `exit_move`, `approach`, `board`, and `_retarget`, and delete
      `set_exact_target`. Verify no production caller uses positional flags.
- [x] 3.3 Collapse `_finish_stop`, the moving arrival, and the wait arrival into `_end_move`.
      Verify movement, wait, and stop suites still pass.
- [x] 3.4 Replace both cell predicates with one `_is_cell_occupied` built on
      `get_cell_occupancy`, and make `_is_cell_unavailable_for_sub_slot` treat buildings as
      ground-only. Verify the destination tests from group 1 pass.

## 4. Migrate production callers

- [x] 4.1 `ExitComponent`: `release_sub_slot()`, `is_idle()`, `exit_move()`, and `move_to()`
      for the blocker nudge.
- [x] 4.2 `DeployComponent`: `is_idle()`, `move_to()`.
- [x] 4.3 `SelectionManager`: `get_surface_level()`, `player_move()`.
- [x] 4.4 `EntityPlacer` and `TransportComponent`: `place_at_sub_slot()`.
- [x] 4.5 `PassengerComponent`: `board()`, `is_exact_move()`, `move_to()`.
- [x] 4.6 `CombatComponent`: `approach()`; `DockClientComponent`: `move_to()` for its four
      plain moves.
- [x] 4.7 `HarvestComponent`: `get_cell_occupancy()` instead of `_reserved`, plus `move_to()`
      for its plain moves. `DockHostComponent`: `occ.building or occ.blocked or occ.reserved`
      instead of `_building_cells` / `_blocked_cells` / `_reserved`.
- [x] 4.8 `SpatialHash`: read `mc.get_state()` / `mc.get_surface_level()`. Verify
      `grep -rn "\._state\|\._surface_level\|\._has_sub_slot\|\._exact_target\|\._assign_sub_slot_at_cell\|\._sub_slot_position" scripts/` returns only `MovementController` internals.

## 5. Migrate the tests

- [x] 5.1 Replace `_make_mc` / `_infantry_like` and the hand-set `_locomotor_data` /
      `_is_jumpjet` / `_shares_cell` setup in `test_movement_locomotor_jumpjet.gd` with
      `MovementFactory.make_movement_controller` and `apply_locomotor`. Keep fixtures that need
      `instant_turn` explicit on their Locomotor.
- [x] 5.2 Replace test reads of `_state`, `_surface_level`, `_has_sub_slot`, `_exact_target`,
      and `_sub_slot_position` with the new getters, and replace `set_target_position` /
      `set_exact_target` with the named intents (or `_retarget` where the test exercises
      internal re-targeting).
- [x] 5.3 Add the EntityPlacer and Transport sub-slot placement regressions asserted by world
      position.

## 6. Gates and archive

- [x] 6.1 Run `gdlint scripts/**/*.gd test/**/*.gd`, `gdformat --check scripts/**/*.gd
      test/**/*.gd`, and `grep -P '\t' scripts/**/*.gd test/**/*.gd`; fix findings.
- [x] 6.2 Run `flock /tmp/opencode/redot.lock redot --headless -s test/run_tests.gd`; all tests
      pass.
- [x] 6.3 Run `openspec archive refactor-mc-interface --yes` and confirm no open change
      directories remain.
