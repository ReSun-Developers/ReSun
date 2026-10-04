# Tasks

## 1. Deploy cell selection and seeking

- [x] 1.1 Add `deploy_search_radius_cells` and a free-foundation-cell search: a moving unit follows its path forward (`MovementController.get_remaining_path_cells`) to the first fitting cell, an idle unit uses its current cell when valid, else the nearest free cell (`_find_deploy_cell`, `_is_deploy_cell_valid`, `_origin_for_cell`).
- [x] 1.2 Add a `SEEKING_DEPLOY` state: drive to the chosen cell centre via `MovementController.set_target_position`, then rotate on the `arrived` signal (`_on_arrived`, `_begin_deploy_rotation`); abort on `pathfinding_failed`.
- [x] 1.3 Handle the already-in-cell case by gliding to the centre through the movement controller (`MovementController.move_to_point`, no teleport) before rotating.
- [x] 1.4 Cancel combat/harvest/transport only after a cell is confirmed, so a failed deploy keeps the unit's orders.
- [x] 1.5 Guard scatter/nudge (`is_entity_transitioning`) so a rotating deployer is not displaced.
- [x] 1.6 Add `cancel_deploy()` and call it from the Stop command's cancel sequence; abort a seek whose movement controller stops without arriving (`_check_seek_interrupted`).

## 2. Tests

- [x] 2.1 `test_execute_deploy_seeks_current_cell_centre` — a unit off-centre on a valid cell moves to the centre and rotates on arrival.
- [x] 2.2 `test_execute_deploy_follows_path_forward` — a moving unit deploys at the next path cell ahead, not the cell it is leaving.
- [x] 2.2b `test_execute_deploy_seeks_nearest_free_cell_when_blocked` — a blocked current foundation selects a different free cell and enters SEEKING_DEPLOY with a free foundation.
- [x] 2.3 `test_execute_deploy_rotates_on_arrival` — arrival at the chosen cell enters ROTATING_DEPLOY.
- [x] 2.4 `test_execute_deploy_blocked_leaves_move_intact` — with no reachable free cell, deploy fails and the move path is preserved.
- [x] 2.5 `test_execute_deploy_clears_combat_target` — deploy clears an active engagement; verify with `redot --headless -s test/run_tests.gd`.
- [x] 2.6 `test_stop_cancels_deploy_seek` and `test_seek_interrupted_when_movement_stops` — a cancelled or stalled seek releases the unit and does not resume.

## 3. Verification

- [x] 3.1 Run the full suite `redot --headless -s test/run_tests.gd` and confirm no regressions.
- [x] 3.2 Run `gdlint scripts/**/*.gd test/**/*.gd` and `gdformat --check scripts/**/*.gd test/**/*.gd`; then `grep -P '\t' scripts/**/*.gd test/**/*.gd` to confirm no tabs.
- [ ] 3.3 Manually confirm: order an MCV to move, issue deploy (Ctrl+D) before arrival, and observe it drive to a free cell centre, rotate, and deploy.
