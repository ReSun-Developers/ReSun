# Spec Delta

## MODIFIED Requirements

### Requirement: SelectionManager tracks selected entities

`SelectionManager` SHALL be an autoload singleton maintaining `selected_entities: Array[SelectComponent]`. It emits `selection_changed(selected_entities)` whenever the selection set changes. Click selection SHALL accept only entities that pass the selectability gate (see "Selection honors SelectComponent.is_selectable"); the scenarios below assume a selectable entity, except the shift-click removal scenario.

#### Scenario: Select single entity

- **WHEN** `select_entity(entity)` is called without shift on a selectable entity
- **THEN** all previously selected entities are deselected, the new entity is selected, and `selection_changed` emits with the new selection

#### Scenario: Shift-click adds to selection

- **WHEN** `select_entity(entity, shift_pressed=true)` is called on a selectable entity
- **THEN** the entity is added to the existing selection without deselecting others

#### Scenario: Shift-click removes from selection

- **WHEN** `select_entity(entity, shift_pressed=true)` is called on an already-selected entity
- **THEN** the entity is removed from the selection, even if it is not selectable

#### Scenario: Deselect all

- **WHEN** `deselect_all()` is called
- **THEN** all entities are deselected and `selection_changed` emits with empty array

### Requirement: Hover preview

SelectionManager SHALL manage hover preview state. `set_hover_preview(enabled, entity)` toggles hover visual on the hovered entity and emits `hover_changed(entity)`. A non-selectable component SHALL be treated as no hover target: any previously hovered entity is unhovered and `is_hovering` is `false`.

#### Scenario: Hover entity

- **WHEN** `set_hover_preview(true, entity)` is called for a selectable entity
- **THEN** `entity.set_is_hovering(true)` is called and `hover_changed` emits

#### Scenario: Unhover entity

- **WHEN** `set_hover_preview(false)` is called
- **THEN** the previously hovered entity's `set_is_hovering(false)` is called

### Requirement: Visual selection synchronization

SelectionManager SHALL synchronize its internal selection list with the visual `is_selected` state on selectable SelectComponents (those in the "selectable" group) and on components explicitly added through `add_entity`. The primary path SHALL be event-driven: `SelectComponent.set_is_selected()` emits a selection-state signal and SelectionManager reconciles that entity immediately. A low-frequency reconcile (at most 10 Hz) SHALL remain as a safety net for external direct writes to `is_selected` on selectable components. The list SHALL NOT be rescanning the "selectable" group every frame.

#### Scenario: Visual selection out of sync (event-driven)

- **WHEN** a SelectComponent sets `is_selected = true` via `set_is_selected()` and is not in `selected_entities`
- **THEN** it is added to `selected_entities` on the same frame

#### Scenario: List contains visually unselected (event-driven)

- **WHEN** a SelectComponent sets `is_selected = false` via `set_is_selected()` while in `selected_entities`
- **THEN** it is removed from `selected_entities` on the same frame

#### Scenario: External mutation reconciled at low frequency

- **WHEN** a selectable SelectComponent's `is_selected` is written directly (not via `set_is_selected()`)
- **THEN** `selected_entities` is reconciled within 100 ms

## ADDED Requirements

### Requirement: Selection honors SelectComponent.is_selectable

`SelectionManager` SHALL reject a `SelectComponent` whose `is_selectable` is `false` on click (`select_entity`), except when shift-click removes an already-selected entity, on hover preview (`set_hover_preview`), and on box selection (the `_is_entity_selectable` gate used by `MouseHandler`). Programmatic `add_entity` SHALL remain ungated, matching the existing visible-bounds rule, and SHALL connect the entity's selection-state signal so a later visual deselect is reconciled. `is_drag_selectable` SHALL NOT bypass the `is_selectable` gate: an entity that is drag-eligible but not selectable SHALL still be rejected.

#### Scenario: Click rejects a non-selectable entity

- **WHEN** `select_entity` is called on an in-bounds, revealed entity with `is_selectable = false`
- **THEN** the entity is not added to `selected_entities`

#### Scenario: Click on a non-selectable entity leaves the selection unchanged

- **WHEN** an entity is selected and `select_entity` is called without shift on a non-selectable entity
- **THEN** the previously selected entity remains selected and the non-selectable entity is not added

#### Scenario: Box select skips a non-selectable entity

- **WHEN** a drag rectangle covers a `drag_selectable` entity with `is_selectable = false`
- **THEN** the entity is not added to `selected_entities`

#### Scenario: Hover ignores a non-selectable entity

- **WHEN** `set_hover_preview(true, entity)` is called for an entity with `is_selectable = false`
- **THEN** the entity's `is_hovering` stays `false`, `SelectionManager.is_hovering` is `false`, and no hover preview is set

#### Scenario: Hover moves off a selectable entity

- **WHEN** a selectable entity is hovered and `set_hover_preview(true, other)` is called with a non-selectable `other`
- **THEN** the first entity's `is_hovering` becomes `false`, `SelectionManager.is_hovering` is `false`, and `other` is not hovered

#### Scenario: Programmatic add stays ungated

- **WHEN** `add_entity` is called directly for an entity with `is_selectable = false`
- **THEN** the entity is added to `selected_entities`

#### Scenario: Programmatic add can be visually removed

- **WHEN** an entity added via `add_entity` later calls `set_is_selected(false)`
- **THEN** it is removed from `selected_entities`
