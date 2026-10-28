# Tasks

## 1. Regression tests first

- [x] 1.1 Add `test_entity_data` cases: `is_selectable` defaults true and survives an explicit false
- [x] 1.2 Add `test_select_component` cases: `is_selectable = false` skips `selectable`; `is_drag_selectable = false` skips `drag_selectable`; a Structure with `is_selectable = true` joins `selectable`/`entities` but not `drag_selectable`; a Structure with `is_selectable = false` joins only `entities`
- [x] 1.3 Add `test_entity_factory_spawn` cases: spawn honors both flags for a unit and `is_selectable = false` for a building; `EntityPlacer._add_preview_groups` honors the restored component's flags
- [x] 1.4 Add `test_selection_manager` cases: click rejects a non-selectable in-bounds entity; a non-shift click leaves the current selection unchanged; box-select skips it; hover ignores it, clears the previous hover, and leaves `is_hovering == false`; box-select skips an `is_drag_selectable = false` entity while click still selects it; shift-click removes a programmatically selected non-selectable entity; `add_entity` + `set_is_selected(false)` removes it
- [x] 1.5 Run the new tests before editing production code and capture the failures (property lookup errors and assertion failures both count)

## 2. Data model

- [x] 2.1 Add `EntityData.is_selectable: bool = true` next to `is_drag_selectable` with a doc comment
- [x] 2.2 Assign `component.is_selectable = data.is_selectable` in `EntityFactory._add_select_component` beside the drag flag

## 3. Group membership

- [x] 3.1 Gate `EntityFactory.create_entity` selection-group adds on `data.is_selectable` / `data.is_drag_selectable`
- [x] 3.2 Gate `EntityPlacer._add_preview_groups` the same way, preferring the restored entity's `SelectComponent` flags
- [x] 3.3 In `SelectComponent._ready`, keep the detached guard; add `selectable` only if `is_selectable`, `entities` always, and `drag_selectable` only if `is_drag_selectable` and the box is not a Structure

## 4. Selection gate

- [x] 4.1 Return false from `SelectionManager._is_entity_selectable` when `entity.is_selectable` is false, before parent/bounds/shroud checks; update its doc comment
- [x] 4.2 Move the `select_entity` gate after the shift-click removal branch so removal still works
- [x] 4.3 Coerce `enabled = false` and `entity = null` for a non-selectable component in `SelectionManager.set_hover_preview`; add the `is_selectable` check to `MouseHandler._handle_hover_preview`
- [x] 4.4 Keep `add_entity` ungated and connect `selection_state_changed` when absent

## 5. Specs and docs

- [x] 5.1 Validate the four capability deltas with `openspec validate refactor-selectability`
- [x] 5.2 Confirm no glossary term is new (selectability already uses existing vocabulary)

## 6. Gates

- [x] 6.1 `gdlint scripts/**/*.gd test/**/*.gd`
- [x] 6.2 `gdformat --check scripts/**/*.gd test/**/*.gd`
- [x] 6.3 `grep -P '\t' scripts/**/*.gd test/**/*.gd`
- [x] 6.4 `flock /tmp/opencode/redot.lock redot --headless -s test/run_tests.gd`

## 7. Archive

- [x] 7.1 `openspec archive refactor-selectability --yes` and confirm no open change dirs remain
