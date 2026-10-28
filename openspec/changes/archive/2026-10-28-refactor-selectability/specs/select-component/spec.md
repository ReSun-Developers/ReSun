# Spec Delta

## MODIFIED Requirements

### Requirement: Select box types

SelectComponent SHALL support three visual modes via `select_box_type`: Infantry, Vehicle, and Structure. Each mode determines the visual style of the selection indicator.

#### Scenario: Structure select box

- **WHEN** `select_box_type == SelectBoxType.Structure`
- **THEN** a 3D selection box is rendered using ImmediateMesh L-shaped corner lines (12 bottom corners + 6 top corners)

#### Scenario: Vehicle/Infantry select box

- **WHEN** `select_box_type` is Infantry or Vehicle
- **THEN** the Infantry/Vehicle selection indicator style is used; group membership is governed by the Group registration requirement

### Requirement: Group registration

SelectComponent SHALL register its parent entity in scene tree groups based on its type and selectability flags when the entity enters the tree, unless the entity is detached:
- "selectable": if `is_selectable == true`
- "drag_selectable": if `is_drag_selectable == true` and the component is not a Structure box
- "entities": always (for iteration by core systems)

Detached entities SHALL join no groups.

#### Scenario: Selectable unit registered

- **WHEN** a Vehicle entity with `is_selectable = true` enters the scene tree
- **THEN** parent is in "selectable", "drag_selectable", and "entities" groups

#### Scenario: Structure not in drag_selectable

- **WHEN** a Structure entity enters the scene tree
- **THEN** parent is in "selectable" and "entities" groups, but NOT in "drag_selectable"

#### Scenario: Non-selectable unit registers no selection group

- **WHEN** a non-structure entity with `is_selectable = false` and `is_drag_selectable = false` enters the scene tree
- **THEN** parent is NOT in "selectable" and NOT in "drag_selectable", but is in "entities"

#### Scenario: Drag opt-out registers no drag group

- **WHEN** a non-structure entity with `is_selectable = true` and `is_drag_selectable = false` enters the scene tree
- **THEN** parent is in "selectable" but NOT in "drag_selectable"
