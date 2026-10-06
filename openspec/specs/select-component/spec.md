## Purpose

Defines `SelectComponent`'s selection visuals: select boxes, health bar and color thresholds, hover/select visibility, rally lines, group registration, and move target lines and their timing.

## Requirements

### Requirement: SelectComponent manages selection visuals
`SelectComponent` SHALL be an `Area3D`-based component that manages selection visual feedback: selection box, health bar, hover/select visibility toggling, and rally line drawing.

#### Scenario: Component attached to entity
- **WHEN** EntityFactory creates an entity with `entity_type != TERRAIN`
- **THEN** a SelectComponent child node is added with `SelectionHitbox` and `SelectOutline` collision shapes

### Requirement: Select box types
SelectComponent SHALL support three visual modes via `select_box_type`: Infantry, Vehicle, and Structure. Each mode determines the visual style of the selection indicator.

#### Scenario: Structure select box
- **WHEN** `select_box_type == SelectBoxType.Structure`
- **THEN** a 3D selection box is rendered using ImmediateMesh L-shaped corner lines (12 bottom corners + 6 top corners)

#### Scenario: Vehicle/Infantry select box
- **WHEN** `select_box_type` is Infantry or Vehicle
- **THEN** the entity registers in "selectable", "entities", and "drag_selectable" groups

### Requirement: Health bar for structures
When a Structure entity has a HealthComponent, SelectComponent SHALL render a segmented health bar at the top of the selection box using BoxMesh with a grid overlay.

#### Scenario: Health bar visibility
- **WHEN** entity is selected or hovered AND has HealthComponent
- **THEN** health bar and grid are visible

#### Scenario: Health bar hidden when not selected
- **WHEN** entity is neither selected nor hovered
- **THEN** health bar and grid are hidden

#### Scenario: Health bar updates on damage
- **WHEN** HealthComponent emits `health_changed`
- **THEN** `update_health_bar()` resizes the bar proportionally and updates color

### Requirement: Health color thresholds
SelectComponent SHALL color the health bar based on health percentage:
- Green: health > 50%
- Yellow: health > 25% and ≤ 50%
- Red: health > 0% and ≤ 25%
- Dark red (0.5, 0.0, 0.0): health = 0 (dead)

#### Scenario: Full health is green
- **WHEN** health percentage is 100%
- **THEN** health bar color is green

#### Scenario: Half health is yellow
- **WHEN** health percentage is 40%
- **THEN** health bar color is yellow

#### Scenario: Critical health is red
- **WHEN** health percentage is 10%
- **THEN** health bar color is red

#### Scenario: Dead unit is dark red
- **WHEN** health percentage is 0%
- **THEN** health bar color is dark red

### Requirement: Hover and select visibility
SelectComponent SHALL toggle visibility of all child meshes based on hover and selection state. The building select box is only visible when selected (not on hover). Rally line is only visible when selected AND a rally point is set.

#### Scenario: Hover shows outline
- **WHEN** `is_hovering = true` and `is_selected = false`
- **THEN** selection outline and health bar are visible, building select box is hidden

#### Scenario: Select shows everything
- **WHEN** `is_selected = true`
- **THEN** all selection visuals are visible

#### Scenario: Neither hover nor select hides all
- **WHEN** `is_hovering = false` and `is_selected = false`
- **THEN** all selection visuals are hidden

### Requirement: Rally line drawing
When a building has a RallyPointComponent, SelectComponent SHALL draw a green line from the building center to the rally point cell with a diamond marker at the endpoint.

#### Scenario: Rally line visible when selected with rally point
- **WHEN** entity is selected AND RallyPointComponent has a set rally point
- **THEN** a green line extends from building center to rally point with a diamond marker

#### Scenario: Rally line hidden when no rally point
- **WHEN** entity is selected but RallyPointComponent has no rally point
- **THEN** rally line is hidden

#### Scenario: Rally line updates on change
- **WHEN** RallyPointComponent emits `rally_point_changed`
- **THEN** rally line is redrawn to the new position

### Requirement: Group registration
SelectComponent SHALL register its parent entity in scene tree groups based on its type and selectability flags:
- "selectable": if `is_selectable == true`
- "drag_selectable": if `is_drag_selectable == true`
- "entities": always (for iteration by core systems)

#### Scenario: Selectable unit registered
- **WHEN** a Vehicle entity with `is_selectable = true` enters the scene tree
- **THEN** parent is in "selectable", "drag_selectable", and "entities" groups

#### Scenario: Structure not in drag_selectable
- **WHEN** a Structure entity enters the scene tree
- **THEN** parent is NOT in "drag_selectable" group (structures can't be box-selected)

### Requirement: Move target line drawing
When a selected unit has a `MovementController` and is executing a move order, `SelectComponent` SHALL register a green line with the shared `MoveLineRenderer` autoload, drawn from the unit to the final cell of its current move order, with a small filled marker at the destination cell center. When the unit has an active attack target (`CombatComponent.get_target()`), the line SHALL end at the attack target's current position instead of the move order's destination cell, so the marker tracks the enemy entity as it moves. The line SHALL use the same layer treatment as the rally line (unshaded, `no_depth_test`, `render_priority = 100`), provided by the shared renderer material. When the per-game `move_target_line` setting is off, `SelectComponent` SHALL NOT register the move-target line; rally lines are governed by their own requirement and are unaffected by this setting.

#### Scenario: Line appears when a selected unit is ordered to move
- **WHEN** a selected unit's `MovementController` starts a new move order from a genuine player order (not an internal re-path or a scatter/nudge triggered by another unit)
- **THEN** a green move target line is shown from the unit to its destination cell with a filled marker at the destination

#### Scenario: Line points at the enemy during an attack
- **WHEN** a selected unit with an active attack target (`CombatComponent.get_target()` is valid) issues a move toward that target
- **THEN** the move target line is shown from the unit to the attack target's current position, and the marker tracks the target as it moves

#### Scenario: Line does not appear or restart on internal re-paths
- **WHEN** a selected unit's `MovementController` re-paths internally (repair/wait re-path) or is scattered/nudged by another unit
- **THEN** the move target line is not shown or restarted by that re-path

#### Scenario: Line appears when a moving unit is selected
- **WHEN** a unit that is already executing a move order becomes selected
- **THEN** the move target line is shown

#### Scenario: Line follows the unit while visible
- **WHEN** the move target line is visible and the unit is moving
- **THEN** the renderer redraws the line each frame so its origin tracks the unit's current position

#### Scenario: Setting off suppresses move-target lines
- **WHEN** the `move_target_line` setting is off and a selected unit has an active move order
- **THEN** `SelectComponent` registers no move-target line for that unit

#### Scenario: Setting re-enabled restores lines
- **WHEN** the `move_target_line` setting is turned back on after being off
- **THEN** move-target lines register again for selected units with active move orders

### Requirement: Move target line timing
The move target line SHALL be visible for 0.3 seconds, controlled by a one-shot timer, fading out over the tail of that window, and SHALL hide (unregister) automatically when the timer elapses.

#### Scenario: Line hides after 0.3 seconds with fade
- **WHEN** the move target line has been visible for 0.3 seconds
- **THEN** the line fades out and is hidden

#### Scenario: Reselecting a moving unit restarts the timer
- **WHEN** a still-moving unit is deselected and then selected again
- **THEN** the 0.3-second timer restarts and the line is shown again

#### Scenario: Reselecting an attacking unit shows the line
- **WHEN** a unit with an active attack target is deselected and then selected again, even if it is stationary (already in weapon range)
- **THEN** the move target line is shown pointing at the attack target

### Requirement: Move target line hidden on deselect
When the unit is not selected, the move target line SHALL be hidden immediately and its timer reset.

#### Scenario: Deselect hides the line
- **WHEN** a unit showing its move target line is deselected
- **THEN** the line is hidden immediately and the timer is stopped

#### Scenario: No line without a movement controller
- **WHEN** a selected entity has no `MovementController` (e.g. a structure)
- **THEN** no move target line is created or shown
