# Spec Delta

## ADDED Requirements

### Requirement: Factory-loss teardown

When the final matching factory for a player and production type is sold or
destroyed, ProductionManager SHALL cancel every active or paused item in the
unsupported queue through the normal refund path. It SHALL refund only credits
already deducted, preserve completed buildings waiting for placement, and
cancel fully paid units waiting to spawn with a full-cost refund. Losing one of
multiple matching factories SHALL preserve the queue and recompute its speed
from the remaining count.

#### Scenario: Final factory is lost

- **WHEN** the player loses the last factory matching an active or paused queue
- **THEN** every item in that queue is cancelled and only its deducted credits are refunded

#### Scenario: Matching factory remains

- **WHEN** one of two matching factories is lost
- **THEN** production remains queued and its speed is recomputed from one factory

#### Scenario: Completed building awaits placement

- **WHEN** the last matching factory is lost after a building completed
- **THEN** the building remains ready for placement and is not refunded

#### Scenario: Completed unit awaits a factory

- **WHEN** the last matching factory is lost while a fully paid unit is ready to spawn
- **THEN** the ready unit is removed and its full cost is refunded
