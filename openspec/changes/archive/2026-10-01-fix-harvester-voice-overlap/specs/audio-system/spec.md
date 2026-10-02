# Spec Delta

## MODIFIED Requirements

### Requirement: Event-driven voice playback
The system SHALL play a voice for a unit on two events: selection and order issue. On selection (`SelectionManager.select_entity`, `SelectionManager.play_select_voice_for_entities`), the system SHALL play a random variant from the unit's `VoiceData.select` event. On order issue (`MouseHandler.play_order_voices`), the system SHALL play a random variant of the voice event carried by the resolved `OrderResult.voice_event` — the event is chosen by the component that produced the order, not derived from the cursor. Non-attack orders (`MOVE`, `HARVEST`, `ENTER`, `DEPLOY`) SHALL carry the `move` event; `ATTACK` orders produced by `CombatComponent` SHALL carry the `attack` event; an empty `voice_event` SHALL play no order voice. Voices SHALL play as commander radio chatter, centered on the camera at full volume, regardless of the unit's world position.

#### Scenario: Selecting a unit plays its select voice
- **WHEN** a unit with a `VoiceData` whose `select` event has variants is selected
- **THEN** one variant from `select` is played on the unit's bus, centered on the camera

#### Scenario: Selecting a unit without voice data is silent
- **WHEN** a unit with no `VoiceData` or an empty `select` event is selected
- **THEN** no audio plays and no error is raised

#### Scenario: Issuing a move order plays the move voice
- **WHEN** a player issues a `MOVE` order to a unit with a `move` voice event
- **THEN** a random `move` variant is played

#### Scenario: Issuing a harvest order plays the move voice
- **WHEN** a player issues a `HARVEST` order to a harvester whose order carries the `move` event
- **THEN** a random `move` variant is played, and no `attack` variant plays

#### Scenario: Issuing a dock or deploy order plays the move voice
- **WHEN** a player issues an `ENTER` or `DEPLOY` order whose order carries the `move` event
- **THEN** a random `move` variant is played, and no `attack` variant plays

#### Scenario: Issuing an attack order plays the attack voice
- **WHEN** a player issues an `ATTACK` order produced by `CombatComponent`
- **THEN** a random `attack` variant is played

#### Scenario: Auto-acquired engagements are silent
- **WHEN** a unit engages a target without a player-issued order (guard auto-acquire or retaliation)
- **THEN** no order voice plays

#### Scenario: Orders that map to no voice event are silent
- **WHEN** an order resolves to an empty `voice_event` (for example a sell or repair order)
- **THEN** no order voice plays and no error is raised

## ADDED Requirements

### Requirement: Command acknowledgment overlap
`AudioManager` SHALL prevent a unit's command acknowledgment from overlapping the same speaker's line. Because `play_voice` receives only a voice-set id and an event name, the speaker boundary SHALL be the voice set (`VoiceData.id`).

When the event is `select`, the system SHALL defer the line for a short debounce window keyed by voice set instead of starting playback immediately. A `select` request SHALL be fulfilled by playing the chosen variant through the normal stacked playback path when the window expires with no intervening acknowledgment. If a non-select acknowledgment (`move`, `attack`, or `feedback`) for the same voice set is requested within the window, the request SHALL discard the deferred `select`; the acknowledgment SHALL play when it has a playable variant (an acknowledgment with no variant still cancels the select). Multiple `select` requests for the same voice set within the window SHALL coalesce into a single deferred line whose window is measured from the first request.

The system SHALL also prevent overlap when the acknowledgment arrives after the window: if a `select` line for the voice set is already playing, the acknowledgment SHALL stop that line before starting. The select is never superseded by `die`.

`die` events SHALL NOT be deferred or cancelled; death cries retain their normal overlapping stacked behavior. The debounce window SHALL be a configurable value for playtesting, and `0` SHALL disable deferral (play `select` immediately).

#### Scenario: Select followed by an order plays only the acknowledgment
- **WHEN** a unit is selected and its order acknowledgment is requested within the debounce window
- **THEN** no `select` line plays and the acknowledgment is the only line for that voice set

#### Scenario: Acknowledgement after the window stops the playing select
- **WHEN** a unit is selected, the debounce window elapses (the `select` line is playing), and an order acknowledgment for the voice set is then requested
- **THEN** the playing `select` line is stopped and only the acknowledgment plays for that voice set

#### Scenario: Select with no order plays after the window
- **WHEN** a unit is selected and no acknowledgment for that voice set is requested within the debounce window
- **THEN** the `select` variant plays when the window expires

#### Scenario: Death voices are never deferred
- **WHEN** a `die` event is requested while a `select` line is deferred
- **THEN** the `die` event plays immediately and does not cancel the deferred `select`

#### Scenario: Rapid selects coalesce
- **WHEN** two `select` requests for the same voice set arrive within the window
- **THEN** at most one `select` line plays for that voice set, and the second request does not extend the window

#### Scenario: Acknowledgment with no playable variant still cancels the select
- **WHEN** a `move`, `attack`, or `feedback` request for the same voice set has no playable variant within the window
- **THEN** the deferred `select` is still discarded and no `select` line plays

#### Scenario: A different voice set does not cancel the select
- **WHEN** an acknowledgment is requested for a different voice set within the window
- **THEN** the deferred `select` is unaffected and still plays when its window expires

#### Scenario: Deferral disabled
- **WHEN** the debounce window is configured to `0`
- **THEN** a `select` request plays immediately, with no deferral
