# Design

## Context

`SelectComponent` exports `is_selectable` (default true) and `is_drag_selectable` (default true). Today `EntityFactory` adds selection groups from the entity type alone, `SelectComponent._ready` adds them again for non-structures, and `MouseHandler._select_entities_2d_projected` iterates `drag_selectable` without consulting the flag. `SelectionManager._is_entity_selectable` gates only on visible bounds and shroud. `EntityData` has `is_drag_selectable` but no `is_selectable`, and the drag flag is assigned but never read.

## Decision Log

**The lie.** Two exported knobs and one data field read as functional configuration. `is_selectable` has no data source and no reader. `is_drag_selectable` is copied onto the component and never read; a `.tres` with `is_drag_selectable = false` still joins `drag_selectable` and is box-selected.

**Chosen option: honor the flags.** OpenTS makes selectability a real `Class_Of()->IsSelectable` property, the wiring is small (five scripts), both defaults are `true` so existing content is unchanged, and the specs already promise flag-driven group registration. Removing the fields would delete a documented data concept and foreclose non-selectable mission props. Cost is a handful of guarded group adds plus one predicate; benefit is the data model stops lying.

**Rejected: remove the dead fields.** Smaller diff, but it deletes a capability the spec already describes and the reference engine has, and it would need a follow-up to re-add when a non-selectable prop is wanted.

## Exact Wiring

- `EntityData.is_selectable` added next to `is_drag_selectable`, default `true`.
- `EntityFactory._add_select_component` sets `component.is_selectable = data.is_selectable` and `component.is_drag_selectable = data.is_drag_selectable` before tree entry.
- `EntityFactory.create_entity`: units join `selectable` only if `data.is_selectable`, `drag_selectable` only if `data.is_drag_selectable`; buildings join `selectable` only if `data.is_selectable` and never `drag_selectable`.
- `EntityPlacer._add_preview_groups`: same rule for restored previews, preferring the restored entity's `SelectComponent` flags over the passed data so a caller-supplied `EntityData` duplicate cannot make the component and groups disagree.
- `SelectComponent._ready`: unless detached, join `selectable` only if `is_selectable` and `entities` always (both for units and structures); join `drag_selectable` only if `is_drag_selectable` and the box is not a Structure. This covers entities instantiated outside the factory, including standalone structure scenes.
- `SelectionManager._is_entity_selectable`: return false when `entity.is_selectable` is false, before the parent/bounds/shroud checks. This gates `select_entity` (click) and `MouseHandler._select_entities_2d_projected` (box).
- `SelectionManager.select_entity`: check the gate after the shift-click removal branch, so an already-selected entity can still be shift-click removed.
- `SelectionManager.set_hover_preview`: a non-selectable component coerces `enabled` to `false` and `entity` to `null`, so the previous hover clears and `is_hovering` ends `false`. `MouseHandler._handle_hover_preview` also requires `select_comp.is_selectable` so a non-selectable unit is not stored as `_hovered_entity` (which drives the cursor probe); the interact pass for resource/dock entities is unaffected because those are not selectable units.
- `SelectionManager.add_entity`: remains ungated, and connects `selection_state_changed` if not already connected so programmatic selections stay reconciled.

Because `is_selectable` is checked in the shared selection gate, a `drag_selectable` entity with `is_selectable = false` still cannot be box-selected even if both flags disagree; `is_drag_selectable` only controls group membership.

## Scope Cuts

- #166 enemy selection and command-blocking rules are untouched.
- No `.tres` content is changed; both flags default to `true`, so no existing entity changes behavior.
- No UI badge for unselectable entities, no per-player selectability, no hover-tooltip wording change.
- `UnitOrderGenerator` reads the `selectable` group, so a non-selectable entity stops showing the SELECT cursor. Over a non-selectable unit the unit probe no longer sets `_hovered_entity`, so the cursor falls back to the ground probe: MOVE when the selection can move, otherwise DEFAULT. Accepted as the intended consequence; no new cursor code.

## Tests That Must Fail On Base

1. `test_entity_data`: `EntityData.is_selectable` exists, defaults to `true`, and survives an explicit `false`.
2. `test_select_component`: a non-structure component with `is_selectable = false` does not join `selectable`; one with `is_drag_selectable = false` does not join `drag_selectable`; a Structure with `is_selectable = true` joins `selectable`/`entities` but never `drag_selectable`; a Structure with `is_selectable = false` joins only `entities`.
3. `test_entity_factory_spawn`: a unit spawned with `is_selectable = false` does not join `selectable`; one with `is_drag_selectable = false` does not join `drag_selectable` but still joins `selectable`; a building with `is_selectable = false` does not join `selectable`; preview group restoration applies the same rule from the restored component flags.
4. `test_selection_manager`: click-select rejects an in-bounds, revealed entity with `is_selectable = false`; a non-shift click on it leaves the current selection unchanged; box-select skips it; `set_hover_preview` does not hover it, clears the previous hover, and leaves `is_hovering == false`.
5. `test_selection_manager`: box-select skips an entity whose `is_drag_selectable = false` (it never joins the drag group) while click-select still selects it when `is_selectable = true`.

## Tests That Must Keep Passing

- Shift-click removal of a programmatically selected non-selectable entity (the gate sits after the removal branch).
- `add_entity` of a non-selectable entity, then `set_is_selected(false)` removes it (new signal connection).

## Spec Impact

- `entity-data`: adds the `is_selectable` field requirement.
- `entity-factory`: group membership is data-driven.
- `select-component`: entry-time group registration honors the flags and now covers structures.
- `selection-manager`: click, hover, and box selection honor `is_selectable`; programmatic add stays ungated but is signal-connected.

## Risks

- `SelectComponent` now registers structures as `selectable`/`entities` at entry. Factory-built buildings already did; standalone structure scenes change, and they become consistently selectable.
- Group membership is snapshotted at `SelectComponent._ready`; click and hover read `is_selectable` live. A runtime flag change therefore affects click/hover immediately but not box-select membership until the component re-enters the tree.
- A non-selectable entity that is already selected programmatically stays selected until a visual deselect or `deselect_all`; `add_entity` now connects the state signal so the former works.
