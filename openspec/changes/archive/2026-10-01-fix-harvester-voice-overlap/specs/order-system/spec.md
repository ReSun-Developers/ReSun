# Spec Delta

## MODIFIED Requirements

### Requirement: OrderResult data class
The system SHALL provide an `OrderResult` class with fields: `cursor` (CursorState.Type), `priority` (int), `target` (Node3D, nullable), `target_pos` (Vector3), `queued` (bool), `execute` (Callable), and `voice_event` (String). The `execute` callback SHALL be a Callable bound to the specific entity instance (closure capturing the component's parent node). `voice_event` SHALL identify the voice event the order acknowledges with, chosen by the component that produced the order; it SHALL default to `move` so non-attack orders acknowledge with the move voice. A component MAY leave it empty to suppress the order voice. Modifiers SHALL be defined as constants: `MOD_FORCE_ATTACK = "force_attack"`, `MOD_FORCE_MOVE = "force_move"`, `MOD_QUEUED = "queued"`.

#### Scenario: OrderResult creation
- **WHEN** a component creates an OrderResult
- **THEN** it MUST populate cursor, priority, and execute fields

#### Scenario: Non-attack order defaults to the move voice event
- **WHEN** a component creates an OrderResult without setting `voice_event`
- **THEN** `voice_event` SHALL be `move`

#### Scenario: Attack order declares the attack voice event
- **WHEN** `CombatComponent` creates an ATTACK OrderResult (including force-fire)
- **THEN** `voice_event` SHALL be `attack`

#### Scenario: OrderResult with an empty voice event
- **WHEN** a component creates an OrderResult with an empty `voice_event` (for example the sell or repair order)
- **THEN** no order voice SHALL play for that order

#### Scenario: OrderResult with null target
- **WHEN** the order targets terrain (no entity)
- **THEN** target SHALL be null and target_pos SHALL contain the world position

#### Scenario: Execute is bound to entity
- **WHEN** execute.call() is invoked
- **THEN** it SHALL operate on the specific entity instance whose component created the OrderResult, not on any other entity

### Requirement: Order confirmation voices
After order resolution in `MouseHandler`, the system SHALL play one confirmation voice per order event from the NW-most selected local unit that has a `VoiceComponent` with a variant for the event, using the voice event carried by the resolved `OrderResult.voice_event` (the highest-priority resolved order). The voice event SHALL be chosen by the order-producing component, not derived from the cursor: `MOVE`, `HARVEST`, `ENTER`, and `DEPLOY` orders SHALL carry `move`; `ATTACK` orders SHALL carry `attack`; an empty `voice_event` SHALL produce no voice. Playback SHALL be a single `AudioManager.play_voice` call (camera-centered), never one per selected unit. A selected unit whose voice set lacks a variant for the event SHALL be skipped so the confirmation never lands on a speaker that would be silent.

#### Scenario: Move order plays move voice
- **WHEN** a player issues a `MOVE` order with a local unit selected
- **THEN** one `move` voice variant SHALL play

#### Scenario: Harvest order plays move voice
- **WHEN** a player issues a `HARVEST` order with a local harvester selected
- **THEN** one `move` voice variant SHALL play and no `attack` variant

#### Scenario: Attack-class order plays attack voice
- **WHEN** a player issues an `ATTACK` order with a local combat unit selected
- **THEN** one `attack` voice variant SHALL play

#### Scenario: Unmapped cursor is silent
- **WHEN** the resolved order carries an empty `voice_event` (no voice event mapped for the order)
- **THEN** no order voice SHALL play

#### Scenario: One voice per order, not per unit
- **WHEN** a multi-unit selection issues one order
- **THEN** exactly one confirmation voice plays (from the NW-most local unit)

#### Scenario: Deploy and stop hotkeys acknowledge with the move voice
- **WHEN** the player presses Ctrl+D (deploy) or Ctrl+S (stop) with a local unit selected and the command applies
- **THEN** one `move` voice variant plays from the NW-most selected unit that can voice it

#### Scenario: Voiceless or non-local selection is silent
- **WHEN** the NW-most local unit has no `VoiceComponent`, or the selection is entirely non-local
- **THEN** no order voice SHALL play

#### Scenario: Speaker is chosen among units that can voice the event
- **WHEN** a mixed selection issues an order whose event is missing from the NW-most unit's voice set but present on another selected local unit
- **THEN** the confirmation plays from the NW-most selected unit that has a variant for the event
