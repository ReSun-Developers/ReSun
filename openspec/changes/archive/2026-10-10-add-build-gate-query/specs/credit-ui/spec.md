# Spec Delta

## MODIFIED Requirements

### Requirement: Insufficient funds visual feedback

The Label SHALL change color when the local player's credit balance is below the cost of the
cheapest item that player can currently build. The set used for the comparison SHALL be the
same build gate the sidebar build list is drawn from, scoped to the local player and spanning
every build-menu tab (not only the currently-visible page): an item that is not buildable for
the local player SHALL NOT influence the warning, even if it is cheap. An item with zero or
negative cost SHALL NOT influence the warning. When the player can build no costed item, no
warning SHALL appear. When the `no_cost` cheat is active, the warning SHALL NOT appear.

#### Scenario: Sufficient funds
- **WHEN** the local balance is at or above the cost of the cheapest item the local player can build
- **THEN** the Label color is white

#### Scenario: Insufficient funds
- **WHEN** the local balance is below the cost of the cheapest item the local player can build
- **THEN** the Label color turns red

#### Scenario: Locked cheap item does not trigger the warning
- **WHEN** a cheap item exists in the catalog but is not buildable by the local player (unmet gate), and the balance covers every item the player can build
- **THEN** the Label color is white

#### Scenario: No-cost cheat disables the warning
- **WHEN** the `no_cost` cheat is active
- **THEN** the Label color is white regardless of balance

#### Scenario: Nothing buildable means no warning
- **WHEN** the local player can build no costed item
- **THEN** the Label color is white regardless of balance
