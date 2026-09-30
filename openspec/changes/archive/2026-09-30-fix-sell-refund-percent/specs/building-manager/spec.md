# Spec Delta

## MODIFIED Requirements

### Requirement: Building sell
`sell_building(building_node)` SHALL refund the building's cost multiplied by `refund_percent` from the active `GlobalRules` (default 0.5), credited as free credits with the active resource category, unregister from PrerequisiteSystem, unregister cells from SpatialHash, deselect the building, emit `building_sold`, and free the node.

#### Scenario: Sell building
- **WHEN** `sell_building(building)` is called on a placed building whose cost is 100, with active rules `refund_percent = 0.5`
- **THEN** 50 credits are added to the player's free credits
- **AND** building is removed from game

#### Scenario: Sell building honors tuned refund_percent
- **WHEN** `sell_building(building)` is called on a placed building whose cost is 100, with active rules `refund_percent = 0.25`
- **THEN** 25 credits are added to the player's free credits

#### Scenario: Sell building not found
- **WHEN** `sell_building(node)` is called on a node not in the buildings list
- **THEN** returns false
