# Tasks

## 1. OrderProbe module

- [x] 1.1 Create `scripts/orders/OrderProbe.gd` with the quadruple fields and `from_entity(target, shift)`, `from_ground(ground_pos, level, shift)`, `from_cell(cell, target, world_pos, level, shift)` factories; verify the script parses (`redot --headless --check-only` on the file or open without errors)
- [x] 1.2 Add `test/unit/test_order_probe.gd` asserting the policy differences between factories: `from_entity` omits `MOD_TARGET_LEVEL`, `from_ground` and `from_cell` always set it (including level 0), shift propagates; verify `redot --headless -s test/run_tests.gd` passes including the new file
- [x] 1.3 Add `OrderProbe` entry to GLOSSARY.md under Orders & Selection (input counterpart of `OrderResolution`, anchors: `scripts/orders/OrderProbe.gd`); verify `grep OrderProbe GLOSSARY.md` shows the row

## 2. OrderSystem entry

- [x] 2.1 Add `resolve_probe(probe: OrderProbe) -> OrderResolution` to `scripts/core/OrderSystem.gd` splatting into the existing tuple `resolve()`; verify existing `test/unit/test_order_bounds.gd` and `test/unit/test_force_fire_ground.gd` still pass unchanged

## 3. Mouse probe extraction

- [x] 3.1 Extract the shared 2-pass raycast (layer 16 → 17, `collide_with_areas`, `raycast_distance`) into private `MouseHandler._probe_pointer(mouse_pos)` returning nested `{unit, interact}` probe dicts; call it from `_handle_hover_preview` keeping fog gate and `_hover_miss_count` logic byte-identical in effect; verify `test/unit/test_mouse_handler_hover.gd` passes **unchanged**
- [x] 3.2 Call `_probe_pointer` from `_handle_left_click_normal` replacing its inline raycasts while keeping select-vs-order ordering and shift semantics; verify left-click behavior: `test_mouse_handler_hover` still passes and manual/entity selection tests (`test/unit/test_selection_manager.gd` if affected) pass

## 4. Rewire assembly sites

- [x] 4.1 Rewire hover cursor (`_update_cursor`) to `OrderProbe.from_entity(_hovered_entity, false)` / ground fallback via `from_ground` with level 0 → `OrderSystem.resolve_probe`; verify hover cursor behaves as before (`test_mouse_handler_hover` unchanged) — the explicit level 0 is design-sanctioned (sole reader `UnitOrderGenerator` defaults to 0); no *real* level ever rides the hover path
- [x] 4.2 Rewire click entity path (`_try_execute_orders`) and the ground-move tail of `_handle_left_click_normal` through `OrderProbe` factories (`from_entity` / `from_ground` with the leveled pick's level); verify move orders still carry the picked surface level (`test/unit/test_order_bounds.gd` and move-order tests pass)
- [x] 4.3 Rewire `Minimap._handle_click` to `OrderProbe.from_cell(cell, target, world, target_level, shift)` → `resolve_probe`, preserving center-camera fallback when orders are empty; verify minimap order issuance behaves as before and `test/unit/test_minimap.gd` passes
- [x] 4.4 Delete the now-dead inline quadruple assembly and confirm no remaining hand-mutation of `MOD_TARGET_LEVEL` outside factories; verify `grep -n "MOD_TARGET_LEVEL" scripts/` shows only `OrderProbe.gd`, `OrderResult.gd`, `UnitOrderGenerator.gd` (read), and no MouseHandler/Minimap writes

## 5. Integration

- [x] 5.1 Run full suite `redot --headless -s test/run_tests.gd`; verify all tests pass with zero modifications to `test_mouse_handler_hover`, `test_force_fire_ground`, `test_order_bounds`, `test_order_resolver`
- [x] 5.2 Run `gdlint scripts/orders/OrderProbe.gd scripts/core/OrderSystem.gd scripts/hud/MouseHandler.gd scripts/ui/Minimap.gd test/unit/test_order_probe.gd` and `gdformat --check` on the same files; verify clean, and `grep -P '\t'` on touched files finds no tabs