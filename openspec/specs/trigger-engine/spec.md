# trigger-engine Specification

## Purpose
Runs mission scripting: parses trigger, tag, event and action definitions, routes occurrences to
attached tags, evaluates triggers on the logic clock, and dispatches actions with classic
persistence semantics so missions can be driven by data rather than bespoke code.

## Requirements

### Requirement: Definitions are data-driven and validated at load

`TriggerEngine` SHALL load trigger definitions from the map JSON `triggers` array and MAY apply an
optional `.tres` overlay that patches them by trigger id. Every trigger SHALL be addressed by a
stable string id, and its events and actions SHALL be addressed by stable numeric ids with fixed
parameter arity. At load the engine SHALL validate every definition and reject the mission's triggers
with a diagnostic when any of the following hold: a duplicate trigger id; an unknown event or action
numeric id; a parameter list whose length does not match the catalog arity; or a reference to an
undeclared waypoint, variable, or trigger id. Loading SHALL be all-or-nothing: if any definition is
invalid, no trigger is armed.

#### Scenario: Valid definitions load
- **WHEN** a map's `triggers` array contains only catalogued events and actions with correct arity
- **THEN** every trigger is armed and no diagnostic is produced

#### Scenario: Unknown event id rejected
- **WHEN** a trigger names an event id that is not in the catalog
- **THEN** loading is rejected with a diagnostic naming the trigger and event, and no trigger is armed

#### Scenario: Wrong arity rejected
- **WHEN** an event or action supplies fewer or more parameters than the catalog arity
- **THEN** loading is rejected with a diagnostic

#### Scenario: Unresolved reference rejected
- **WHEN** a trigger references a waypoint or variable not declared by the map
- **THEN** loading is rejected with a diagnostic

#### Scenario: `.tres` overlay patches by id
- **WHEN** a `.tres` overlay changes the actions of a trigger that exists in the map JSON
- **THEN** the overlay's actions replace that trigger's actions and all other triggers are unchanged

### Requirement: Tags attach triggers to locations

A trigger SHALL carry one or more tags. Each tag SHALL declare a persistence mode and an attachment
kind: `general`, `house`, `cell`, or `object`. A `cell` tag SHALL list the cells it rides on. A
`general` tag SHALL be reachable by every occurrence offer; a `house` tag SHALL be attached to the
house that owns its trigger and reachable by that house's offers. A trigger with no tag SHALL be
rejected at load with a diagnostic.

#### Scenario: Cell tag attaches to cells
- **WHEN** a tag with attachment `cell` lists cell `(37, 46)`
- **THEN** occurrences offered for that cell reach the trigger

#### Scenario: General tag is reachable by any offer
- **WHEN** an occurrence is offered and a trigger has a `general` tag
- **THEN** that occurrence can latch its events, so a standing condition is re-checked when the state it watches changes

#### Scenario: Trigger without a tag is rejected
- **WHEN** a trigger definition declares no tags
- **THEN** loading is rejected with a diagnostic and no trigger is armed

### Requirement: Occurrences are offered to tags

`TriggerEngine.offer(event_id, payload)` SHALL route an occurrence to every armed trigger whose tags
make it reachable, latch the matching event on those triggers, and mark them dirty. Offering SHALL NOT
evaluate or execute anything. An occurrence offered to a trigger whose event list does not include
that event id SHALL leave it unchanged. Offers for an object or cell SHALL only reach triggers attached
to that object or cell.

#### Scenario: Subscribed trigger latches
- **WHEN** an occurrence with an event id is offered and a reachable trigger's event list includes it
- **THEN** that trigger becomes dirty and its matching event is latched

#### Scenario: Unsubscribed trigger untouched
- **WHEN** an occurrence is offered and a trigger's event list does not include that event id
- **THEN** that trigger does not become dirty and nothing is latched

#### Scenario: Cell occurrence is scoped
- **WHEN** an occurrence is offered for a cell that carries no tag
- **THEN** no cell-attached trigger is affected

### Requirement: Evaluation runs once per logic tick

On each `MatchClock` tick the engine SHALL evaluate only the triggers currently marked dirty, in a
deterministic order, and SHALL clear the dirty marking for each evaluated trigger. A trigger SHALL
fire when it is enabled, is not marked for destruction, and every one of its events is satisfied. Its
events SHALL be examined in the reverse of their declared order. After the dirty set is processed,
latched events that did not result in a fire SHALL be handled according to the trigger's persistence
(see remembering).

#### Scenario: All events satisfied fires
- **WHEN** every event of an enabled dirty trigger is satisfied in this evaluation
- **THEN** the trigger fires and its actions are queued

#### Scenario: Partial satisfaction does not fire
- **WHEN** only some events of a dirty trigger are satisfied and none are remembered
- **THEN** the trigger does not fire

#### Scenario: Disabled trigger does not fire even when dirty
- **WHEN** a trigger is disabled and its events become satisfied
- **THEN** it does not fire until it is enabled

### Requirement: Persistence governs repeated firing

Tag persistence SHALL control what happens after a trigger fires. `volatile` SHALL fire on the first
satisfying evaluation and then destroy the tag together with its trigger. `persistent` SHALL fire on
every satisfying evaluation and stay armed. `semi-persistent` SHALL decrement the tag's attachment
count on each satisfying evaluation for an object or cell that holds it and SHALL fire only when the
count reaches one remaining attachment; a semi-persistent tag attached to no object or cell SHALL
never fire.

#### Scenario: Volatile fires once
- **WHEN** a volatile trigger's events are satisfied and it fires
- **THEN** its tag and trigger are destroyed and it never fires again

#### Scenario: Persistent repeats
- **WHEN** a persistent trigger's events are satisfied on two separate evaluations
- **THEN** it fires once per satisfying evaluation

#### Scenario: Semi-persistent fires on the last holder
- **WHEN** a semi-persistent tag rides on three cells and each satisfies the trigger in turn
- **THEN** the first two evaluations detach and do not fire, and the third fires

### Requirement: Temporal events are remembered on persistent tags

An offer SHALL be a remembering offer when its tag is persistent. During a remembering offer, a
satisfied temporal event SHALL be marked satisfied and SHALL count as satisfied on every later
evaluation without being tested again. A volatile or semi-persistent tag SHALL NOT remember, so every
event must be satisfied during a single evaluation for such a tag to fire. A mark SHALL persist until
the trigger fires (a persistent fire clears marks so it can re-arm) or the tag is destroyed. Elapsed-time countdowns SHALL restart on trigger enable, on a linked variable change, and on
every remembering evaluation that satisfies all of the trigger's events.

#### Scenario: Cross-offer combination on a persistent tag
- **WHEN** two distinct temporal events occur in separate offers on a persistent tag
- **THEN** the first is remembered and the trigger fires on the offer that delivers the second

#### Scenario: Volatile tag requires one offer
- **WHEN** two distinct temporal events occur in separate offers on a volatile tag
- **THEN** the trigger never fires from those offers

### Requirement: Actions dispatch through a deferred journal

Actions of every trigger that fires during a tick SHALL be appended to a per-tick journal and SHALL
NOT execute while evaluation or occurrence offering is in progress. The journal SHALL be drained once
at the tick boundary, in ascending trigger id then declaration order, with each action's target
resolved at drain time. An action
that causes a further occurrence SHALL be routed back through offering after the current drain
completes or via a bounded same-tick fixed point; a per-tick command budget SHALL cap cascades and
SHALL emit a diagnostic when exceeded. An action targeting the object or cell that sprang its trigger
SHALL apply to that object or cell.

#### Scenario: Firing does not mutate during evaluation
- **WHEN** a trigger fires and one of its actions spawns an entity whose event another trigger watches
- **THEN** the spawn happens at the tick boundary and no trigger is evaluated during the action itself

#### Scenario: Author order preserved
- **WHEN** one trigger fires several actions
- **THEN** they are dispatched in the order declared

#### Scenario: Cascade is bounded
- **WHEN** actions cause occurrences that fire further triggers in a loop
- **THEN** the per-tick command budget stops the cascade and a diagnostic is emitted

### Requirement: Trigger control actions

The engine SHALL implement actions to enable, disable, force, and destroy a trigger by id, and to
destroy a tag by id. `force` SHALL fire every trigger of the named id without evaluating its events
and without changing tag persistence or attachment. A disabled trigger SHALL ignore every offer until
enabled; a trigger already marked for destruction SHALL not be forced.

#### Scenario: Disable stops firing
- **WHEN** an enabled trigger is disabled and its events become satisfied
- **THEN** it does not fire until enabled again

#### Scenario: Force fires without events
- **WHEN** force is applied to a trigger whose events can never be satisfied
- **THEN** the trigger fires and its actions are queued

#### Scenario: Destroy removes permanently
- **WHEN** a trigger is destroyed by id
- **THEN** it can no longer be offered events, enabled, or forced

### Requirement: Scenario variable events and actions

The engine SHALL implement the set/clear actions for global and local (per-house) variables, and the
corresponding set/clear events. Setting or clearing a variable SHALL offer the matching event to the
general list (global) or to the owning house's list (local). A global variable SHALL be observable by
every house; a local variable SHALL be observable only by its own house.

#### Scenario: Setting a global satisfies a global-set event
- **WHEN** an action sets global `"BridgeDown"` and a trigger watches the global-set event for it
- **THEN** that event is satisfied on the next evaluation

#### Scenario: Local events are house-scoped
- **WHEN** a local `"BaseAttacked"` is set for `GDI` and a `Nod`-owned trigger watches that local
- **THEN** the `Nod` trigger does not observe the change

### Requirement: Mission outcome actions

The engine SHALL implement win, lose, and allow-win actions. Win and lose SHALL report the outcome to
the mission layer without directly freeing the world. Allow-win SHALL hold its house's victory; the
hold is released when a trigger of that house is destroyed.

#### Scenario: Win reports the outcome
- **WHEN** a trigger fires the win action
- **THEN** the mission layer is notified that the local player's mission is won

#### Scenario: Allow-win holds until released
- **WHEN** a trigger fires allow-win
- **THEN** the corresponding house's victory is held

#### Scenario: Destroying the holding trigger releases the hold
- **WHEN** a trigger of the held house is destroyed after allow-win
- **THEN** the house's victory hold is released

### Requirement: Cell entry event

The engine SHALL implement a cell-entry event. When an uncloaked infantry or vehicle finishes moving
into a cell, the engine SHALL offer the cell-entry event for that cell, reaching only triggers whose
tag rides on that cell. Flying aircraft SHALL NOT produce cell-entry offers.

#### Scenario: Entering a tagged cell satisfies the event
- **WHEN** a ground unit finishes moving into a cell whose tag watches cell entry
- **THEN** that trigger's cell-entry event is satisfied

#### Scenario: Untagged cell produces no offer
- **WHEN** a ground unit finishes moving into a cell with no tag
- **THEN** no cell-entry trigger is affected

### Requirement: Engine lifecycle

`TriggerEngine` SHALL arm triggers when a mission starts, after the mission's map and scenario state
are loaded, and SHALL be reset when a new match starts so no trigger, tag, latch, mark, or attachment
count survives from the previous match.

#### Scenario: Arms on mission start
- **WHEN** a mission with trigger definitions starts
- **THEN** its triggers are armed and receive offers

#### Scenario: New match clears state
- **WHEN** a new match starts after a previous one
- **THEN** no trigger from the previous match is armed and no latch, mark, or attachment count remains
