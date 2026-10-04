# Spec Delta

## ADDED Requirements

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
