# select-component Specification (Delta)

## MODIFIED Requirements

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
