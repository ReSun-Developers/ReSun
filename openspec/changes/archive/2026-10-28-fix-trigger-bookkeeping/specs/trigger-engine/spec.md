# Spec Delta

## ADDED Requirements

### Requirement: Credits event reads the house's current balance

The credits event SHALL compare the trigger owner's current balance — free credits plus the stored
value of displayable categories — against its threshold. When triggers are armed after mission start,
that balance SHALL include the starting credits written by mission start, even though mission start
does not offer a credit-change occurrence. A credits trigger SHALL be evaluated on the first logic
tick after arming.

#### Scenario: Threshold at or below starting credits fires immediately
- **WHEN** a mission starts with 5000 credits, a credits trigger with threshold 1000 is armed, and no
  credit is spent or earned
- **THEN** the trigger fires on the first logic tick after arming

#### Scenario: Threshold above starting credits waits for income
- **WHEN** a mission starts with 5000 credits and a credits trigger with threshold 9000 is armed
- **THEN** the trigger does not fire until the house's balance reaches 9000

### Requirement: Counted-structure removals update bookkeeping

The engine SHALL record a structure as counted when it is notified as built. The counted state SHALL
be tracked per structure instance, so a removal or death that does not identify the counted instance
is treated as uncounted. When a counted structure leaves the world for a reason other than
destruction — being sold, or transformed by undeploy — the engine SHALL decrement the house's alive
count and that structure id's built count by one (to zero when it was the only one), and SHALL NOT
satisfy the temporal destroyed events. A counted structure destroyed by damage SHALL decrement the
same counts and SHALL offer the destroyed events. A structure that was never counted SHALL not change
the counts when it leaves the world.

#### Scenario: Sold counted structure stops counting as built and alive
- **WHEN** a structure is counted as built and then sold
- **THEN** the house's alive count and that structure id's built count each drop by one

#### Scenario: Undeployed counted structure stops counting as built and alive
- **WHEN** a structure is counted as built and then transformed into a vehicle by undeploy
- **THEN** the house's alive count and that structure id's built count each drop by one

#### Scenario: Sale does not raise a destroyed event
- **WHEN** a counted structure is sold while a trigger watches the destroyed events
- **THEN** those events are not offered, so the trigger does not fire from the sale

#### Scenario: Destroyed structure still raises destroyed events
- **WHEN** a counted structure is destroyed by damage while a trigger watches the destroyed events
- **THEN** the destroyed events are offered and the structure's counts drop by one

#### Scenario: Removing an uncounted structure leaves counted siblings intact
- **WHEN** an uncounted structure of an id is sold or undeployed while a counted structure of the same
  id still stands
- **THEN** the counted structure's built and alive counts are unchanged
