## Purpose

The audio system loads per-game sound and voice resources from the active game's data sets, plays them through a fixed Master/Music/SFX/Voice bus layout, and routes gameplay events (weapon fire, impacts, deaths, unit voices) to spatially-appropriate playback with stacking, loudness, and graceful-failure guarantees.

## Requirements

### Requirement: AudioManager autoload with dynamic .tres loader
The system SHALL provide an `AudioManager` autoload that registers data-set directories and recursively scans them for `.tres` resources, caching `AudioData` and `VoiceData` resources by their `id`. The scan SHALL mirror the `EntityFactory._scan_directory` pattern, and loading a directory SHALL be idempotent per path. A missing or unreadable directory SHALL produce a warning and return without error. The registered directories SHALL come from the active game's `data_sets` layer roots (the `audio/` subdirectory of each root), resolved via GameContext at select time.

#### Scenario: Scan loads all audio resources by id
- **WHEN** `AudioManager.register_data_set("res://games/ts/audio/")` is called
- **THEN** every `AudioData.tres` and `VoiceData.tres` under that directory is cached, keyed by its `id`

#### Scenario: Registering the same data set twice is idempotent
- **WHEN** `register_data_set` is called twice with the same path
- **THEN** the directory is scanned only once and cached resources are not duplicated

#### Scenario: Missing directory does not crash
- **WHEN** `register_data_set` is called with a non-existent path
- **THEN** the call logs a warning and returns without raising an error

### Requirement: Audio buses (Master, Music, SFX, Voice)
The system SHALL ensure four audio buses exist at startup: `Master`, `Music`, `SFX`, and `Voice`. `Master` is the default root bus; the other three are created as children when missing. Each `AudioData` SHALL specify which bus its stream plays on.

#### Scenario: Buses exist after AudioManager ready
- **WHEN** `AudioManager` finishes `_ready()`
- **THEN** buses `Master`, `Music`, `SFX`, and `Voice` exist in the audio server

#### Scenario: Sound plays on its declared bus
- **WHEN** `play_sound` is called with an `AudioData` whose bus is `Voice`
- **THEN** the resulting player is routed to the `Voice` bus

### Requirement: AudioData resource definition
The system SHALL provide an `AudioData` resource (`scripts/data/AudioData.gd`) with fields: `id` (unique sound id matching the `sound.ini` `[SoundList]` name, e.g. `INFGUN3`, `15-I000`), `path` (res:// path to the audio stream), `bus` (one of `Master`/`Music`/`SFX`/`Voice`), `priority` (int, default 10), `volume_db` (float), and `is_spatial` (bool, default true). Each sound file SHALL have one `AudioData.tres` under `games/ts/audio/`.

#### Scenario: AudioData exposes playback fields
- **WHEN** an `AudioData` resource is loaded from a `.tres` file
- **THEN** its id, path, bus, priority, volume_db, and is_spatial fields are populated from the file

#### Scenario: Default bus and spatiality
- **WHEN** an `AudioData` is created without explicit bus or spatial values
- **THEN** `bus` defaults to `SFX` and `is_spatial` defaults to true

### Requirement: VoiceData resource definition
The system SHALL provide a standalone `VoiceData` resource (`scripts/data/VoiceData.gd`) keyed by `id`, mapping voice events to lists of audio ids. Supported events SHALL be `select`, `move`, `attack`, `die`, and `feedback`. Each event list SHALL hold one or more audio ids representing interchangeable variants. `VoiceData` SHALL be a standalone catalog item that any entity can reference by id — it is not coupled to faction or player.

#### Scenario: VoiceData maps events to variant ids
- **WHEN** a `VoiceData` resource is loaded whose `select` event lists `["15-I000", "15-I002", "15-I008"]`
- **THEN** requesting a `select` voice offers one of those three ids

#### Scenario: Missing event returns no variants
- **WHEN** a `VoiceData` has no `die` entries and the `die` event is requested
- **THEN** playback is skipped without error

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

### Requirement: Graceful failure on missing audio
The system SHALL fail silently when a requested audio id cannot be resolved or loaded: it SHALL log a warning via `push_warning` and return without raising an error or disturbing gameplay. This SHALL apply to `play_sound`, `play_voice`, and weapon/effect sounds.

#### Scenario: Unknown sound id logs a warning
- **WHEN** `play_sound` is called with an id absent from the cache
- **THEN** the call logs a warning and returns without playing anything

#### Scenario: Missing audio file logs a warning
- **WHEN** an `AudioData` whose `path` fails to load is requested
- **THEN** the call logs a warning and returns without playing anything

#### Scenario: Unit without voice data does not crash
- **WHEN** a unit without voice data is selected or ordered
- **THEN** gameplay continues normally with no audio and no error

### Requirement: VoiceComponent per-entity holder
The system SHALL provide a `VoiceComponent` that holds a unit's `VoiceData` reference and exposes voice-event playback to the audio system. It SHALL be attached to an entity only when `EntityData.voice_data` is set, following the existing conditional component pattern (`EntityFactory._add_components`). Entities without voice data SHALL have no `VoiceComponent`.

#### Scenario: VoiceComponent attached only when voice data present
- **WHEN** an entity is created from `EntityData` with a `voice_data` reference
- **THEN** the entity has a `VoiceComponent` holding that reference

#### Scenario: VoiceComponent absent without voice data
- **WHEN** an entity is created from `EntityData` without `voice_data`
- **THEN** the entity has no `VoiceComponent`

### Requirement: Weapon fire and death sounds
The system SHALL play weapon fire sounds using `WeaponData.sound_report` (a comma-separated list of audio ids) at the `CombatComponent._fire_weapon` choke point, spatially at the firing unit. When the list has multiple entries, the system SHALL select the report by stacking depth: entries SHALL be considered in list order and the first entry whose current live copy count is below the rotation threshold SHALL play; ids that do not resolve to a cached `AudioData` SHALL be skipped with a warning; when every entry is at or above the rotation threshold, the last entry SHALL play. On death (`HealthComponent.health_zero`), the system SHALL play the unit's `VoiceData.die` set when one exists; entities without a die voice set play `EntityData.sound_die` when set (see the Unvoiced destruction sounds requirement). Both SHALL honor the graceful-failure requirement when ids are missing.

#### Scenario: Weapon fire plays the first entry when unstacked
- **WHEN** a weapon with `sound_report = "INFGUN3,GOSTGUN1"` fires while fewer than the rotation threshold of `INFGUN3` copies are live
- **THEN** `INFGUN3` plays at the firing unit's position and no `GOSTGUN1` player spawns

#### Scenario: Stacked fire rotates to later entries
- **WHEN** a weapon with `sound_report = "INFGUN3,GOSTGUN1"` fires while `INFGUN3` already has the rotation threshold of live copies
- **THEN** `GOSTGUN1` plays instead of `INFGUN3`

#### Scenario: All entries saturated plays the last entry
- **WHEN** a weapon with `sound_report = "INFGUN3,GOSTGUN1"` fires while both ids are at or above the rotation threshold
- **THEN** `GOSTGUN1` plays (the last entry)

#### Scenario: Unknown report id is skipped
- **WHEN** a weapon fires with `sound_report = "NO_SUCH_ID,GOSTGUN1"` where `NO_SUCH_ID` has no cached `AudioData`
- **THEN** a warning is raised and `GOSTGUN1` plays

#### Scenario: Weapon with empty sound report is silent
- **WHEN** a weapon with an empty `sound_report` fires
- **THEN** no fire sound plays and no error is raised

#### Scenario: Death plays the unit's die voice set
- **WHEN** an entity with a non-empty `VoiceData.die` reaches zero health
- **THEN** a random die variant is played; entities without die voices play nothing

### Requirement: Viewport-aware spatial falloff
The system SHALL play spatial sounds (e.g. weapon fire) at full volume while the source is inside the camera's viewport, and attenuate with distance beyond the viewport edge. The spatial player's position SHALL be placed on the listener-relative bearing of the source at the source's distance past the viewport rectangle, using inverse-distance attenuation. Voices positioned at the camera are unaffected (distance zero → full volume). In headless/UI contexts without a camera, the sound SHALL play positionally at the source without falloff.

#### Scenario: On-screen sound plays at full volume
- **WHEN** a spatial sound source is inside the viewport footprint
- **THEN** its player is placed at the listener position (full volume, no panning)

#### Scenario: Off-screen sound attenuates with distance
- **WHEN** a spatial sound source is beyond the viewport edge
- **THEN** its player is placed past the listener along the source bearing, so the engine attenuates it by the off-screen distance

### Requirement: Content .tres files
The system SHALL author `AudioData.tres` files under the active game's `audio/` data directory (`games/ts/audio/` for Tiberian Sun) for available audio files, and `VoiceData.tres` files for units with select/order voice sets, using the available audio library and `references/sound.ini` id mapping. A `default_bus_layout.tres` SHALL define the Master/Music/SFX/Voice buses.

#### Scenario: Content matches sound.ini ids
- **WHEN** content `AudioData.tres` files are scanned
- **THEN** each id matches a `references/sound.ini` `[SoundList]` name and resolves to an existing imported audio file

#### Scenario: Voice sets reference existing audio ids
- **WHEN** a `VoiceData.tres` event lists audio ids
- **THEN** each listed id resolves to a cached `AudioData`

### Requirement: Stacked sound loudness ceiling
The system SHALL guarantee that concurrent playback on any audio bus never exceeds a configured loudness ceiling, regardless of how many sounds — same or different ids — are stacked at once. To enforce this, `AudioManager` SHALL install bus effects at startup: a compressor and a hard limiter on the `Master` bus (compressor before limiter), a hard limiter on the `SFX` bus, and a compressor on the `Voice` bus. Effect setup SHALL be idempotent (never duplicating an effect on repeated startup), and the limiter/compressor parameters SHALL be configurable constants in `AudioManager` for playtesting.

#### Scenario: Master bus carries a compressor and hard limiter
- **WHEN** `AudioManager` finishes `_ready()`
- **THEN** the `Master` bus has an `AudioEffectCompressor` followed by an `AudioEffectHardLimiter` whose ceiling is set below 0 dB

#### Scenario: SFX and Voice buses carry loudness effects
- **WHEN** `AudioManager` finishes `_ready()`
- **THEN** the `SFX` bus has an `AudioEffectHardLimiter` and the `Voice` bus has an `AudioEffectCompressor`

#### Scenario: Bus effect setup does not duplicate on repeated ready
- **WHEN** `_ensure_buses` (or equivalent startup path) runs again on an already-initialized `AudioManager`
- **THEN** no bus gains a second copy of an effect it already has

### Requirement: Fire sound retrigger throttling
The system SHALL throttle repeat playback of the same sound id so that rapid-fire weapons — which fire up to 20+ shots per second per unit — cannot flood the mix with a dense wall of gunfire. `play_sound` SHALL skip starting a sound id that was played within the previous `RETRIGGER_INTERVAL_MS`, silently (no warning — throttling is normal operation). Skipped throttling SHALL apply per sound id (distinct ids are not throttled by each other), covers `play_voice` (which routes through `play_sound`), and the interval SHALL be a configurable constant in `AudioManager` for playtesting.

#### Scenario: Rapid same-id replays are skipped
- **WHEN** the same sound id is requested more than once within `RETRIGGER_INTERVAL_MS`
- **THEN** only the first request starts playback; subsequent requests are dropped silently

#### Scenario: Distinct ids are not throttled by each other
- **WHEN** different sound ids are requested within the same interval
- **THEN** each id starts playback normally

#### Scenario: Playback resumes after the interval elapses
- **WHEN** a sound id is requested after `RETRIGGER_INTERVAL_MS` has elapsed since its last play
- **THEN** playback starts normally

### Requirement: Concurrent stack bounding
The system SHALL bound concurrent playback so that stacked sounds — identical or different ids — never play louder than a single copy. At most `MAX_STACK_PER_ID` copies of any single id SHALL play concurrently; beyond that the oldest copy SHALL be stopped and released. Each active copy SHALL have its volume scaled by the total number of concurrent copies on its bus, so that N concurrent copies on a bus sum to roughly one copy's loudness (per-copy attenuation of `-20·log10(N)` dB). Scaling SHALL be scoped per bus (`SFX`, `Voice`, `Music` normalized independently) so voice playback remains audible over stacked weapon fire. This SHALL apply to both spatial and non-spatial players and to both `play_sound` and `play_voice` (which routes through `play_sound`).

#### Scenario: Concurrent copies capped per id
- **WHEN** more than `MAX_STACK_PER_ID` copies of the same id are requested at once
- **THEN** the oldest copy is stopped and released so active copies never exceed the cap

#### Scenario: Stacked identical copies scale down in volume
- **WHEN** N copies of the same id are playing concurrently on a bus
- **THEN** each copy's `volume_db` is reduced by `20·log10(N)` dB relative to its base volume

#### Scenario: Different ids on one bus share a loudness budget
- **WHEN** N different sound ids play concurrently on the same bus
- **THEN** each copy is scaled by the bus total (`-20·log10(N)` dB) so the stack never exceeds one copy's loudness

#### Scenario: Buses are normalized independently
- **WHEN** sounds play concurrently on the `SFX` bus while a single voice plays on the `Voice` bus
- **THEN** the SFX copies are scaled by the SFX bus count and the voice keeps its base volume (not buried by the SFX stack)

#### Scenario: Copy count recovers after playback ends
- **WHEN** a copy of an id finishes playing
- **THEN** the remaining copies on its bus are re-normalized to their new count and the finished copy is released

### Requirement: Warhead impact sounds

On every damaging hit, the system SHALL play the victim's warhead impact report, read from `WarheadData.sound_impact` (a comma-separated list of audio ids), at the victim's position through `AudioManager.play_random`. The impact report SHALL use random selection with graceful failure: one id SHALL be chosen at random from the entries that resolve to a cached `AudioData`; unknown ids SHALL log a warning and be excluded; an empty `sound_impact` or a list with no known ids SHALL play nothing. The per-victim report SHALL apply only to combat entities; cell overlays (bridge span, ice, tiberium) SHALL be excluded, because their damage is applied by the warhead-gated cell pass, which plays the shot's single report once at the impact point. One resolved shot SHALL therefore play the impact report at most once, never once per damaged cell victim. Damage whose `damage_type` does not resolve to a `WarheadData` (for example vehicle crush or drowning) SHALL be silent. Impact playback SHALL NOT require the victim to have a `VoiceComponent`.

#### Scenario: Hit plays the warhead impact report

- **WHEN** a projectile or hitscan shot dealing warhead "HE" damages a victim and HE.sound_impact = "EXPNEW06"
- **THEN** "EXPNEW06" plays at the victim's position

#### Scenario: Impact picks one report at random

- **WHEN** a warhead with sound_impact = "EXPNEW06,EXPNEW10" damages a victim
- **THEN** exactly one of EXPNEW06 or EXPNEW10 plays at the victim's position

#### Scenario: Mixed entity and overlay hit plays one impact report

- **WHEN** a shot damages both a combat entity and a cell overlay at the same impact point and the warhead has a non-empty `sound_impact`
- **THEN** exactly one impact report plays at that point, not one per victim

#### Scenario: Empty impact report is silent

- **WHEN** a warhead with an empty sound_impact damages a victim
- **THEN** no impact sound plays and no error is raised

#### Scenario: Unknown impact id warns and is skipped

- **WHEN** a warhead with sound_impact = "NO_SUCH_ID,EXPNEW10" damages a victim
- **THEN** a warning is logged and EXPNEW10 plays

#### Scenario: Non-warhead damage is silent

- **WHEN** an entity takes damage whose damage_type is not a registered warhead id
- **THEN** no impact sound plays and gameplay continues normally

### Requirement: Unvoiced destruction sounds
When an entity dies, the system SHALL play the entity's `VoiceData.die` set when a `VoiceComponent` with a non-empty die event exists; otherwise it SHALL play `EntityData.sound_die` (a comma-separated list of audio ids) through `AudioManager.play_random` at the entity's position; when neither exists it SHALL play nothing. `sound_die` SHALL use random selection among known ids with the same graceful-failure behavior as warhead impacts. `sound_die` SHALL be independent of `VoiceData`: an entity may define both, in which case the die voice takes precedence and the death sound does not play. This fulfils the previously deferred requirement that explosion/effect SFX for unvoiced entities be assigned.

#### Scenario: Unvoiced building plays its death sound
- **WHEN** a building with no VoiceComponent and sound_die = "EXPNEW09,EXPNEW11" reaches zero health
- **THEN** exactly one of EXPNEW09 or EXPNEW11 plays at the building's position

#### Scenario: Die voice takes precedence over sound_die
- **WHEN** an entity with both a non-empty VoiceData.die and sound_die reaches zero health
- **THEN** the die voice plays and the death sound is not played

#### Scenario: Entity with neither is silent
- **WHEN** an entity with no VoiceComponent and empty sound_die reaches zero health
- **THEN** no death sound plays and no error is raised

#### Scenario: Missing death-sound id warns
- **WHEN** an entity with sound_die = "NO_SUCH_ID" reaches zero health and no id resolves
- **THEN** a warning is logged, no sound plays, and the entity still frees normally

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
