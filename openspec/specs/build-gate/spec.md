# build-gate Specification

## Purpose

Provide one per-player decision that tells the sidebar, production, and HUD whether an
entity can be built right now, and when it cannot, why not — so a cameo's visibility, the
production gate, and the credit warning all agree.

## Requirements

### Requirement: Single per-player build decision

The system SHALL provide one build-gate query that, for a given player and entity type,
returns whether the type is buildable by that player and — when it is not — a single reason.
The query SHALL evaluate the gates in this order and report the first that fails:
`not_buildable` (the type's build-menu flag is false), `never` (`tech_level == -1`),
`tech_level` (the player's level is below the type's positive level), `build_limit` (the
player already owns the type's build limit), `prerequisite` (the player owns none of the
type's OR prerequisites), `prerequisite_necessary` (the player is missing an AND
prerequisite), and `no_factory` (the player owns no building that produces the type's queue).
The query SHALL also report the type's cost and a raw `owned_factory` fact indicating whether
the player owns a building that produces the type's queue. `owned_factory` SHALL be reported
independently of the gate outcome. For a type with no queue (`buildable_queue` empty) it SHALL
be false and the `no_factory` gate SHALL NOT apply. All gates pass when the type is buildable
and the reason is `none`.

#### Scenario: Buildable type reports enabled with no reason
- **WHEN** every gate passes for a player and type
- **THEN** the query reports the type enabled with reason `none`

#### Scenario: First failing gate determines the reason
- **WHEN** a type is above the player's tech level and also has an unmet prerequisite
- **THEN** the query reports reason `tech_level` (the earlier gate), not `prerequisite`

#### Scenario: Missing required building reports no factory
- **WHEN** a type's queue has a producing building the player does not own and all earlier gates pass
- **THEN** the query reports reason `no_factory`

#### Scenario: Permanent unavailability is distinct from a tech shortfall
- **WHEN** a type has `tech_level == -1`
- **THEN** the query reports reason `never`, regardless of the player's level

#### Scenario: Type outside the build menu is rejected
- **WHEN** an entity type's build-menu flag is false
- **THEN** the query reports reason `not_buildable`

### Requirement: Ownership is player-scoped

The `owned_factory` fact and the `no_factory` gate SHALL be evaluated against the requesting
player's own owned buildings only. A producing building owned by another player SHALL NOT
satisfy either.

#### Scenario: Another player's factory does not count
- **WHEN** player A owns a producing building for a queue and player B owns none
- **THEN** the query for player B reports `owned_factory` false and reason `no_factory`

#### Scenario: Own factory satisfies the gate
- **WHEN** the requesting player owns a producing building for the type's queue
- **THEN** the query reports `owned_factory` true and does not fail the `no_factory` gate

### Requirement: Ownership fact survives the cheat bypass

When the `no_prereqs` debug cheat is active, the query SHALL report the type enabled with
reason `none` (bypassing every gate, including `not_buildable`), yet SHALL still report the
raw `owned_factory` fact for the requesting player. The bypass SHALL NOT falsify ownership.

#### Scenario: Cheat enables while ownership stays truthful
- **WHEN** `no_prereqs` is active and the requesting player owns no producing building for the queue
- **THEN** the query reports the type enabled with reason `none` and `owned_factory` false

#### Scenario: Cheat with ownership present
- **WHEN** `no_prereqs` is active and the requesting player owns a producing building
- **THEN** the query reports the type enabled and `owned_factory` true

### Requirement: Affordability is not a gate

The build-gate query SHALL NOT consider the player's credit balance. A type the player cannot
currently afford SHALL be reported enabled and SHALL remain queueable. Affordability SHALL be
reported independently as feedback, never as a rejection. (Production funding behaviour — a
queued item deducting as credits accrue and stalling when none remain — is owned by
`production-manager`, not this capability.)

#### Scenario: Unaffordable type is still buildable
- **WHEN** every gate passes but the player's balance is below the type's cost
- **THEN** the query reports the type enabled with reason `none`

#### Scenario: Zero balance does not change the reason
- **WHEN** the player's balance is zero and every gate passes
- **THEN** the query reports the type enabled, unaffected by the balance

### Requirement: Production and the build list share the decision

Production order checks and the sidebar build list SHALL both resolve buildability through
the same per-player query, so a type hidden from the build list cannot be queued by another
path, and a type shown in the build list is accepted by the production gate.

#### Scenario: Hidden type cannot be queued
- **WHEN** a type fails the gate for a player
- **THEN** it is absent from that player's build list and a direct production order for it is refused

#### Scenario: Shown type is accepted
- **WHEN** a type passes the gate for a player
- **THEN** it appears in the build list and a production order for it is accepted
