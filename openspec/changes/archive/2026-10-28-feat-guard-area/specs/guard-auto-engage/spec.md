# Spec Delta

## ADDED Requirements

### Requirement: Guard-area stance
A `GuardComponent` SHALL expose a guard-area stance entered when the guard-area order moves its entity: the stance records the entity's assigned destination as its anchor, keeps the existing idle stand-and-shoot acquisition (weapon-range radius, hold-ground, visibility, throttle), and walks the unit back to the anchor when the unit is idle, not engaged, and farther from the anchor than a small displacement threshold. The stance SHALL be cleared by a player-issued move to a destination farther from the anchor than the displacement threshold, by the Stop command, and by a failed return move (so an unreachable anchor does not retry forever). Guard Area SHALL NOT add a second targeting path: acquisition remains the existing Mode A scan.

#### Scenario: Unit guards the ordered area after arriving
- **WHEN** a unit with a `GuardComponent` receives the guard-area order and finishes moving to its assigned destination
- **THEN** it SHALL be in the guard-area stance and acquire a hostile that enters weapon range with the existing hold-ground behavior

#### Scenario: Displaced unit returns to the anchor
- **WHEN** a unit in the guard-area stance is idle, not engaged, and farther from its anchor than the displacement threshold
- **THEN** it SHALL request a move back to the anchor position

#### Scenario: Player move clears the stance
- **WHEN** the player issues a normal move to a unit in the guard-area stance to a destination farther from the anchor than the displacement threshold
- **THEN** the guard-area stance SHALL be cleared and the unit SHALL NOT return to the old anchor

#### Scenario: Stop clears the stance
- **WHEN** the Stop command is applied to a unit in the guard-area stance
- **THEN** the stance SHALL be cleared

#### Scenario: Unreachable anchor abandons the stance
- **WHEN** the stance's return move fails to find a path to the anchor
- **THEN** the stance SHALL be cleared instead of retrying every tick

#### Scenario: Unarmed selection has no stance
- **WHEN** a unit has no `GuardComponent` and receives the guard-area order
- **THEN** it SHALL only move to the target; no guard-area stance SHALL exist
