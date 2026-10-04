# deploy-undeploy

## Purpose

DeployComponent transforms a deployable unit into a building and back, and
exposes the order targeter the order funnel uses for click-self deploy and
terrain undeploy.

## Requirements

### Requirement: DeployComponent order targeter
DeployComponent SHALL implement `get_order_for_target()`. When target is the same entity (self) and `can_deploy()` is true, it SHALL return DEPLOY cursor, priority 15, and execute callback that calls `execute_deploy(parent)`. When target is null and `can_undeploy()` is true, it SHALL return MOVE cursor and execute callback that calls `execute_undeploy(parent, target_pos)`. The undeploy execute callback SHALL compute its own cell offset from the selection center at execution time, not at resolution time. Otherwise returns null.

#### Scenario: Click self to deploy
- **WHEN** an MCV with DeployComponent is selected and cursor is over itself
- **THEN** cursor SHALL be DEPLOY and clicking SHALL deploy the MCV

#### Scenario: Click self without DeployComponent
- **WHEN** a unit without DeployComponent is selected and cursor is over itself
- **THEN** get_order_for_target() SHALL return null (no deploy capability)

#### Scenario: Click ground to undeploy
- **WHEN** a deployed building is selected and cursor is over terrain
- **THEN** cursor SHALL be MOVE and clicking SHALL undeploy the building to that position

#### Scenario: Undeploy offset calculation
- **WHEN** multiple buildings are selected and one clicks terrain to undeploy
- **THEN** each building's execute callback SHALL compute its own offset from the selection center using its own global_position, not a shared target_pos

#### Scenario: Cannot deploy
- **WHEN** an entity has DeployComponent but `can_deploy()` returns false
- **THEN** get_order_for_target() SHALL return null for self-target

#### Scenario: Cannot undeploy
- **WHEN** an entity has DeployComponent but `can_undeploy()` returns false
- **THEN** get_order_for_target() SHALL return null for terrain-target

### Requirement: DeployComponent removes get_cursor_for_target
DeployComponent SHALL remove the existing `get_cursor_for_target()` method. Cursor behavior is now provided by `get_order_for_target()`. During the migration period, both methods may coexist temporarily — the old method is removed in the final cleanup task.

#### Scenario: Old method removed
- **WHEN** `get_cursor_for_target()` is called on DeployComponent after migration
- **THEN** it SHALL not exist (method removed)

### Requirement: Deploy-on-click via order system
MouseHandler SHALL no longer check for DeployComponent directly when an already-selected entity is clicked. Instead, the normal order resolution path via OrderSystem.get_orders() SHALL handle deploy via DeployComponent's get_order_for_target().

#### Scenario: Deploy via order system
- **WHEN** an already-selected MCV is clicked again
- **THEN** OrderSystem.get_orders() SHALL return the deploy OrderResult from DeployComponent

#### Scenario: No hardcoded deploy check
- **WHEN** MouseHandler._handle_left_click_normal() processes a click on a selected entity
- **THEN** it SHALL NOT contain a direct check for DeployComponent

### Requirement: Deploy selects a free foundation cell and centres there
Issuing deploy to a deployable entity SHALL first choose a cell whose entire
building foundation is free. A moving entity SHALL follow its current path
forward and take the first cell ahead that fits, never reversing to the cell it
is leaving; an idle entity SHALL use its own cell when valid, otherwise the
nearest valid cell within a bounded search radius. The entity SHALL move to the
centre of the chosen cell before rotating to the deploy orientation and
transforming. Deploy SHALL cancel the entity's combat engagement, harvesting, and
transport unloading so they do not resume after the transform. When no valid
cell exists, deploy SHALL fail and leave the entity's current orders untouched.

#### Scenario: Deploy while moving
- **WHEN** a deploying entity is moving and a cell ahead on its path has a free
  foundation
- **THEN** it SHALL continue forward to that cell's centre and rotate there, and
  SHALL NOT reverse to the cell it is leaving

#### Scenario: Deploy when the current cell is blocked
- **WHEN** a deploying entity's current cell foundation is blocked and a free
  cell exists within the search radius
- **THEN** it SHALL select the nearest free cell and drive to that cell's centre
  before rotating

#### Scenario: Deploy when already stationary
- **WHEN** an idle deployable entity stands on a valid cell but off its centre
- **THEN** it SHALL drive to the centre (not teleport) and rotate

#### Scenario: Deploy while engaging
- **WHEN** a deploying entity is attacking or harvesting and deploy is issued
- **THEN** it SHALL clear the engagement/harvest before the seek

#### Scenario: Deploying unit is not displaced
- **WHEN** a unit is mid-deploy and other units attempt to scatter or nudge it
- **THEN** it SHALL hold its position until the transform completes

#### Scenario: No free cell
- **WHEN** no cell within the search radius has a free foundation
- **THEN** deploy SHALL fail and the entity SHALL keep its current orders and
  position

#### Scenario: Stop cancels an in-flight deploy
- **WHEN** the player issues Stop while a unit is seeking or rotating to deploy
- **THEN** the deploy SHALL be cancelled, the unit SHALL become commandable
  again, and it SHALL NOT resume the deploy
