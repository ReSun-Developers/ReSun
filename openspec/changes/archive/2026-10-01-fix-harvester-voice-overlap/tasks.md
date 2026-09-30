# Tasks

## 1. Order voice event on `OrderResult`

- [x] 1.1 Add `voice_event: String = VoiceData.EVENT_MOVE` to `scripts/orders/OrderResult.gd` and verify `test/unit/test_order_resolver.gd` asserts a synthesized MOVE order carries `VoiceData.EVENT_MOVE`
- [x] 1.2 Set `voice_event = VoiceData.EVENT_ATTACK` on the three `CombatComponent.get_order_for_target` ATTACK orders (force-fire ground, force-fire entity, normal enemy) in `scripts/components/CombatComponent.gd`, and verify `test/unit/test_order_resolver.gd` / `test/unit/test_force_fire_ground.gd` assert `attack` for each
- [x] 1.3 Set `voice_event = ""` on the sell and repair orders in `scripts/orders/SellOrderGenerator.gd` and `RepairOrderGenerator.gd`, and verify a unit test asserts an empty event for each
- [x] 1.4 Verify a `HarvestComponent.get_order_for_target` harvest order and its dock `ENTER` order carry the default `move` event (extend `test/unit/test_harvest_dock.gd`)

## 2. Order confirmation voice reads the order event

- [x] 2.1 Delete `MouseHandler.voice_event_for_cursor` and change `play_order_voices` to read `orders[0].voice_event` (skip when empty) in `scripts/hud/MouseHandler.gd`, and verify `grep -rn "voice_event_for_cursor" scripts/ test/` returns no hits
- [x] 2.2 Add integration coverage in `test/integration/test_audio_voice_routing.gd`: a harvest order plays the `move` variant and not `attack`; an attack order plays `attack`; an empty-event order plays nothing

## 3. Acknowledgment overlap in `AudioManager`

- [x] 3.1 Add `SELECT_DEBOUNCE_MS` and a voice-set-keyed deferred-slot dictionary to `scripts/core/AudioManager.gd`; `play_voice` defers `select`, any non-die `move`/`attack`/`feedback` for the same set discards it, `_process(delta)` flushes on expiry through `play_sound`, repeated selects coalesce, `die` is never deferred, and `0` disables
- [x] 3.2 Add unit tests in `test/unit/test_audio_manager.gd`: select-then-move leaves only the move line active; select alone flushes after the window; two rapid selects coalesce; die is not deferred; window `0` plays immediately — assert via `get_active_count` with the window set explicitly (no real-time waits)
- [x] 3.3 Update `test_stack_voice_path_normalized` in `test/unit/test_audio_manager.gd` to exercise the Voice-bus stack with `die` (select is now deferred) and verify it passes
- [x] 3.4 Add an integration case in `test/integration/test_audio_voice_routing.gd`: `select_entity` then a harvest order yields exactly one active voice line for that voice set

## 4. Verification

- [x] 4.1 Run `redot --headless -s test/run_tests.gd` and verify all tests pass
- [x] 4.2 Run `gdlint scripts/**/*.gd test/**/*.gd` and `gdformat --check scripts/**/*.gd test/**/*.gd`, then `grep -P '\t' scripts/**/*.gd` to confirm no tabs were introduced
- [x] 4.3 Verify `openspec validate fix-harvester-voice-overlap --strict` reports no errors

## 5. Review follow-ups

- [x] 5.1 Stop a `select` that is already playing when the acknowledgment arrives after the debounce window: track the voice set's active select player and stop it (`AudioManager._active_select_by_voice`, `_stop_player`, `play_sound` returns its player), verified by `test_ack_cancels_in_flight_select` and `test_order_after_window_cancels_playing_select`
- [x] 5.2 Pick the confirmation speaker among selected units that can voice the event (`MouseHandler.play_ack_voice`), verified by `test_ack_voice_skips_speaker_without_event`
- [x] 5.3 Acknowledge the Ctrl+D / Ctrl+S hotkeys with the move voice via the shared `play_ack_voice`
- [x] 5.4 Harden the new `voice_event` assertions against abort-and-pass (`.get("voice_event")`) and add empty-variant-ack, cross-voice-set, partial-window, and highest-priority tests
- [x] 5.5 Set `AudioManager.process_mode = PROCESS_MODE_ALWAYS` so a pending select still flushes while the tree is paused
- [x] 5.6 Align the audio-system/order-system deltas, `design.md`, and `proposal.md` with the in-flight cancellation, speaker selection, and hotkey voice
- [x] 5.7 Documented but not fixed: `test/run_tests.gd` records a test that aborts on a script error as PASS (no error hook); the zero-assert guard is unsafe (40 legitimate smoke tests have zero asserts), so a completion-marker convention is a separate change
