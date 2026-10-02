extends Node

# AudioManager tests — directory scan caching, idempotent re-register, graceful
# failure on missing ids/files, bus routing, voice variant selection.

var _am: Node = null


func _ready() -> void:
    if has_node("/root/AudioManager"):
        _am = get_node("/root/AudioManager")


func test_scan_caches_audio_by_id():
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    if not _am:
        return
    var audio: AudioData = _am.get_audio_data("INFGUN3")
    TestHelper.assert_true(audio != null, "INFGUN3 cached from resources/audio scan")
    if audio:
        TestHelper.assert_eq(audio.bus, "SFX", "weapon sound on SFX bus")
        TestHelper.assert_eq(
            audio.path, "res://games/ts/external_assets/audio/infgun3.ogg", "path resolved"
        )


func test_scan_caches_voice_by_id():
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    if not _am:
        return
    var voice: VoiceData = _am.get_voice_data("GDI_VEHICLE")
    TestHelper.assert_true(voice != null, "GDI_VEHICLE voice set cached")
    if voice:
        TestHelper.assert_true(voice.select.size() >= 4, "select has variant list")
        TestHelper.assert_eq(voice.get_event("move").size(), 5, "move variants from rules.ini")


func test_register_data_set_is_idempotent():
    if not _am:
        return
    var before: int = _am._data_sets.size()
    _am.register_data_set("res://games/ts/audio/")
    TestHelper.assert_eq(_am._data_sets.size(), before, "re-registering same path is a no-op")


func test_missing_directory_warns_without_crash():
    if not _am:
        return
    _am.register_data_set("res://games/ts/audio/missing_dir/")
    var recorded: bool = _am._data_sets.has("res://games/ts/audio/missing_dir/")
    TestHelper.assert_true(recorded, "missing dir recorded")
    TestHelper.assert_true(true, "no crash on missing dir")


func test_play_sound_unknown_id_silent():
    if not _am:
        return
    var before := _am.get_child_count()
    _am.play_sound("NO_SUCH_SOUND_XYZ")
    TestHelper.assert_eq(_am.get_child_count(), before, "unknown id spawns no player")


## EVA stall hook: with the EVA asset not yet imported the announcer stays silent
## (no player spawned, no crash) for the local player.
func test_production_stall_announcer_silent_without_asset():
    if not _am:
        return
    if _am.get_audio_data(_am.EVA_INSUFFICIENT_FUNDS) != null:
        TestHelper.fail("test expects the EVA_INSUFFICIENT_FUNDS asset to be absent")
        return
    var before := _am.get_child_count()
    _am._on_production_stalled("%d:InfantryType" % PlayerManager.get_local_player_id())
    TestHelper.assert_eq(
        _am.get_child_count(), before, "no EVA asset -> stall announcement is silent"
    )


func test_play_voice_empty_event_silent():
    if not _am:
        return
    var before := _am.get_child_count()
    _am.play_voice("GDI_VEHICLE", "feedback")
    TestHelper.assert_eq(_am.get_child_count(), before, "empty feedback event spawns no player")


func test_sound_routes_to_declared_bus():
    if not _am:
        return
    # Fixture-backed (committed) audio so this passes without the gitignored
    # external_assets/ .ogg files.
    var audio := AudioData.new()
    audio.id = "TEST_TONE"
    audio.path = "res://test/fixtures/audio/test_tone.wav"
    audio.bus = "Voice"
    _am._audio_cache[audio.id] = audio
    var before := _am.get_child_count()
    _am.play_sound(audio.id, Vector3(10, 0, 5))
    var last := _am.get_child(_am.get_child_count() - 1) as Node
    TestHelper.assert_true(last != null, "player created for known id")
    if last and last.has_method("get_bus"):
        TestHelper.assert_eq(last.get_bus(), "Voice", "player routed to declared bus")
    TestHelper.assert_true(_am.get_child_count() >= before + 1, "player added as child")
    if last is Node3D:
        (
            TestHelper
            . assert_eq(
                (last as Node3D).global_position,
                Vector3(10, 0, 5),
                "spatial player at source with no camera",
            )
        )
        (
            TestHelper
            . assert_eq(
                (last as AudioStreamPlayer3D).attenuation_model,
                AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE,
                "spatial player uses inverse-distance attenuation",
            )
        )


func test_excess_distance_geometry():
    if not _am:
        return
    var rect := Rect2(Vector2(0, 0), Vector2(100, 100))
    TestHelper.assert_eq(
        _am._excess_distance(Vector3(10, 0, 10), rect), 0.0, "on-screen has zero excess"
    )
    TestHelper.assert_eq(
        _am._excess_distance(Vector3(50, 0, 50), rect), 0.0, "center has zero excess"
    )
    var edge: float = _am._excess_distance(Vector3(50, 0, -5), rect)
    TestHelper.assert_true(
        is_equal_approx(edge, 5.0), "just outside top edge excess is 5 (got %s)" % edge
    )
    var corner: float = _am._excess_distance(Vector3(-5, 0, -5), rect)
    (
        TestHelper
        . assert_true(
            is_equal_approx(corner, 5.0 * sqrt(2.0)),
            "outside corner excess is the diagonal (got %s)" % corner,
        )
    )


func test_falloff_position_places_past_listener_on_bearing():
    if not _am:
        return
    var rect := Rect2(Vector2(0, 0), Vector2(100, 100))
    var listener := Vector3(50, 20, 50)
    var pos: Vector3 = _am._falloff_position(Vector3(50, 0, 200), rect, listener)
    TestHelper.assert_eq(
        pos, Vector3(50, 20, 150), "player placed at excess distance past the listener"
    )


# Stacked identical sounds must not sum to a louder aggregate: N concurrent
# copies of one id share a single copy's loudness budget.


func _has_bus_effect(bus_name: String, effect_class: String) -> bool:
    var bus_idx := AudioServer.get_bus_index(bus_name)
    if bus_idx == -1:
        return false
    for effect_idx in AudioServer.get_bus_effect_count(bus_idx):
        var effect: AudioEffect = AudioServer.get_bus_effect(bus_idx, effect_idx)
        if effect.get_class() == effect_class:
            return true
    return false


func test_master_bus_has_hard_limiter():
    if not _am:
        return
    (
        TestHelper
        . assert_true(
            _has_bus_effect("Master", "AudioEffectHardLimiter"),
            "Master bus carries a hard limiter",
        )
    )
    (
        TestHelper
        . assert_true(
            _has_bus_effect("Master", "AudioEffectCompressor"),
            "Master bus carries a compressor before the limiter",
        )
    )
    var bus_idx := AudioServer.get_bus_index("Master")
    for effect_idx in AudioServer.get_bus_effect_count(bus_idx):
        var effect := AudioServer.get_bus_effect(bus_idx, effect_idx) as AudioEffect
        if effect is AudioEffectHardLimiter:
            (
                TestHelper
                . assert_true(
                    effect.ceiling_db < 0.0,
                    "hard limiter ceiling below 0 dB (got %s)" % effect.ceiling_db,
                )
            )
        elif effect is AudioEffectCompressor:
            (
                TestHelper
                . assert_true(
                    effect.gain > 0.0,
                    "Master compressor has makeup gain (got %s)" % effect.gain,
                )
            )


func test_sfx_bus_has_hard_limiter():
    if not _am:
        return
    (
        TestHelper
        . assert_true(
            _has_bus_effect("SFX", "AudioEffectHardLimiter"),
            "SFX bus carries a hard limiter",
        )
    )


func test_voice_bus_has_compressor():
    if not _am:
        return
    (
        TestHelper
        . assert_true(
            _has_bus_effect("Voice", "AudioEffectCompressor"),
            "Voice bus carries a compressor",
        )
    )
    var bus_idx := AudioServer.get_bus_index("Voice")
    for effect_idx in AudioServer.get_bus_effect_count(bus_idx):
        var effect := AudioServer.get_bus_effect(bus_idx, effect_idx) as AudioEffect
        if effect is AudioEffectCompressor:
            (
                TestHelper
                . assert_true(
                    effect.gain > 0.0,
                    "Voice compressor has makeup gain (got %s)" % effect.gain,
                )
            )


func test_bus_effect_setup_idempotent():
    if not _am:
        return
    var bus_names: Array[String] = ["Master", "SFX", "Voice"]
    var counts: Array[int] = []
    for bus_name in bus_names:
        counts.append(AudioServer.get_bus_effect_count(AudioServer.get_bus_index(bus_name)))
    _am._ensure_buses()
    for i in counts.size():
        (
            TestHelper
            . assert_eq(
                AudioServer.get_bus_effect_count(AudioServer.get_bus_index(bus_names[i])),
                counts[i],
                "re-running setup adds no duplicate effects on %s" % bus_names[i],
            )
        )


func _ensure_bus(bus_name: String) -> void:
    if AudioServer.get_bus_index(bus_name) == -1:
        AudioServer.add_bus()
        AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


func _stack_fixture(id: String, volume_db: float) -> AudioData:
    var audio := AudioData.new()
    audio.id = id
    audio.path = "res://test/fixtures/audio/test_tone.wav"
    audio.bus = id + "_BUS"
    audio.volume_db = volume_db
    _ensure_bus(audio.bus)
    _am._audio_cache[id] = audio
    return audio


## Bypass the retrigger throttle so a test can force a same-id re-play. The
## stack tests target normalization; retrigger rate limiting has its own tests.
func _expire_retrigger(id: String) -> void:
    _am._last_played_at[id] = -100000


func _stack_players(bus: String) -> Array:
    var out: Array = []
    for child in _am.get_children():
        if (
            child is AudioStreamPlayer
            and child.get("bus") == bus
            and not child.is_queued_for_deletion()
        ):
            out.append(child)
        elif (
            child is AudioStreamPlayer3D
            and child.get("bus") == bus
            and not child.is_queued_for_deletion()
        ):
            out.append(child)
    return out


func _release_players(players: Array) -> void:
    for player: Node in players:
        if is_instance_valid(player):
            player.emit_signal("finished")


func test_stack_single_playback_keeps_base_volume():
    if not _am:
        return
    var fixture := _stack_fixture("STACK_SINGLE", -6.0)
    _am.play_sound(fixture.id, Vector3(0, 0, 0))
    var players := _stack_players(fixture.bus)
    TestHelper.assert_eq(players.size(), 1, "single copy spawned")
    if players.size() == 1:
        var db: float = players[0].get("volume_db")
        TestHelper.assert_true(
            is_equal_approx(db, -6.0), "single copy keeps its base volume (got %s)" % db
        )
    _release_players(players)


func test_stack_identical_sounds_scale_volume():
    if not _am:
        return
    var fixture := _stack_fixture("STACK_SCALE", 0.0)
    for i in 3:
        _expire_retrigger(fixture.id)
        _am.play_sound(fixture.id, Vector3(0, 0, 0))
        var players := _stack_players(fixture.bus)
        var expected_db: float = linear_to_db(1.0 / float(i + 1))
        TestHelper.assert_eq(players.size(), i + 1, "stack grows to %d" % (i + 1))
        for player: Node in players:
            var db: float = player.get("volume_db")
            (
                TestHelper
                . assert_true(
                    is_equal_approx(db, expected_db),
                    "each of %d copies at %s dB (got %s)" % [i + 1, expected_db, db],
                )
            )
    _release_players(_stack_players(fixture.bus))


func test_stack_total_loudness_never_exceeds_single():
    if not _am:
        return
    var fixture := _stack_fixture("STACK_BOUND", -10.0)
    for i in 8:
        _expire_retrigger(fixture.id)
        _am.play_sound(fixture.id, Vector3(0, 0, 0))
        var players := _stack_players(fixture.bus)
        var total_amplitude := 0.0
        for player: Node in players:
            total_amplitude += db_to_linear(player.get("volume_db"))
        (
            TestHelper
            . assert_true(
                total_amplitude <= db_to_linear(-10.0) + 0.001,
                "stacked amplitude never exceeds a single copy (got %s)" % total_amplitude,
            )
        )
        (
            TestHelper
            . assert_true(
                is_equal_approx(total_amplitude, db_to_linear(-10.0)),
                "stacked amplitude stays at single-copy loudness (got %s)" % total_amplitude,
            )
        )
    _release_players(_stack_players(fixture.bus))


func test_stack_caps_concurrent_instances():
    if not _am:
        return
    # Cap chosen per the issue (8-12); keep in sync with MAX_STACK_PER_ID.
    var cap := 12
    var fixture := _stack_fixture("STACK_CAP", -3.0)
    for i in cap + 5:
        _expire_retrigger(fixture.id)
        _am.play_sound(fixture.id, Vector3(0, 0, 0))
    var players := _stack_players(fixture.bus)
    TestHelper.assert_eq(players.size(), cap, "concurrent copies capped")
    var expected_db: float = -3.0 + linear_to_db(1.0 / float(cap))
    for player: Node in players:
        var db: float = player.get("volume_db")
        (
            TestHelper
            . assert_true(
                is_equal_approx(db, expected_db),
                "post-cap copies normalized to the cap count (got %s)" % db,
            )
        )
    _release_players(players)


func test_stack_cleanup_restarts_the_count():
    if not _am:
        return
    var fixture := _stack_fixture("STACK_CLEANUP", 0.0)
    for i in 3:
        _expire_retrigger(fixture.id)
        _am.play_sound(fixture.id, Vector3(0, 0, 0))
    _release_players(_stack_players(fixture.bus))
    TestHelper.assert_eq(
        _stack_players(fixture.bus).size(), 0, "no live copies after every one finishes"
    )
    _expire_retrigger(fixture.id)
    _am.play_sound(fixture.id, Vector3(0, 0, 0))
    _expire_retrigger(fixture.id)
    _am.play_sound(fixture.id, Vector3(0, 0, 0))
    var players := _stack_players(fixture.bus)
    TestHelper.assert_eq(players.size(), 2, "fresh stack starts from zero")
    var second: Node = players[players.size() - 1] as Node
    var second_db: float = second.get("volume_db")
    (
        TestHelper
        . assert_true(
            is_equal_approx(second_db, linear_to_db(0.5)),
            "second fresh copy scaled as N=2, not continuing a stale count (got %s)" % second_db,
        )
    )
    _release_players(players)


func test_stack_voice_path_normalized():
    if not _am:
        return
    var fixture := _stack_fixture("STACK_VOICE_SND", -4.0)
    fixture.is_spatial = false
    var voice := VoiceData.new()
    voice.id = "STACK_VOICE"
    # `die` is exempt from select deferral, so it exercises the voice stack path
    # immediately (a `select` would now be held for the debounce window).
    voice.die = [fixture.id]
    _am._voice_cache[voice.id] = voice
    for i in 3:
        _expire_retrigger(fixture.id)
        _am.play_voice(voice.id, "die")
        var players := _stack_players(fixture.bus)
        var expected_db: float = -4.0 + linear_to_db(1.0 / float(i + 1))
        TestHelper.assert_eq(players.size(), i + 1, "voice copy joins the stack")
        for player: Node in players:
            var db: float = player.get("volume_db")
            (
                TestHelper
                . assert_true(
                    is_equal_approx(db, expected_db),
                    "voice copy normalized like SFX (got %s)" % db,
                )
            )
    _release_players(_stack_players(fixture.bus))


## Registers a voice set whose select/move/attack/die events map to distinct
## fixture ids, so select deferral/discard can be observed via active counts.
func _defer_voice_fixture() -> VoiceData:
    var voice := VoiceData.new()
    voice.id = "DEFER_VOICE"
    voice.select = [_stack_fixture("DEFER_SEL", 0.0).id]
    voice.move = [_stack_fixture("DEFER_MOV", 0.0).id]
    voice.attack = [_stack_fixture("DEFER_ATK", 0.0).id]
    voice.die = [_stack_fixture("DEFER_DIE", 0.0).id]
    _am._voice_cache[voice.id] = voice
    return voice


func test_select_deferred_then_ack_discards_select():
    if not _am:
        return
    var voice := _defer_voice_fixture()
    _expire_retrigger("DEFER_SEL")
    _am.play_voice(voice.id, "select")
    TestHelper.assert_eq(_am.get_active_count("DEFER_SEL"), 0, "select is deferred, not played")
    _expire_retrigger("DEFER_MOV")
    _am.play_voice(voice.id, "move")
    TestHelper.assert_eq(_am.get_active_count("DEFER_SEL"), 0, "deferred select discarded by ack")
    TestHelper.assert_eq(_am.get_active_count("DEFER_MOV"), 1, "acknowledgment plays")
    _am._process(1.0)
    TestHelper.assert_eq(_am.get_active_count("DEFER_SEL"), 0, "discarded select never flushes")
    _release_players(_stack_players("DEFER_MOV_BUS"))


func test_select_flushes_without_ack():
    if not _am:
        return
    var voice := _defer_voice_fixture()
    _expire_retrigger("DEFER_SEL")
    _am.play_voice(voice.id, "select")
    TestHelper.assert_eq(_am.get_active_count("DEFER_SEL"), 0, "select is deferred")
    _am._process(1.0)
    TestHelper.assert_eq(_am.get_active_count("DEFER_SEL"), 1, "select flushes after the window")
    _release_players(_stack_players("DEFER_SEL_BUS"))


func test_rapid_selects_coalesce():
    if not _am:
        return
    var voice := _defer_voice_fixture()
    _expire_retrigger("DEFER_SEL")
    _am.play_voice(voice.id, "select")
    var first_remaining: float = float(_am._pending_select[voice.id]["remaining"])
    _am.play_voice(voice.id, "select")
    TestHelper.assert_eq(_am._pending_select.size(), 1, "two rapid selects share one pending slot")
    (
        TestHelper
        . assert_true(
            is_equal_approx(float(_am._pending_select[voice.id]["remaining"]), first_remaining),
            "a second select does not extend the window",
        )
    )
    _am._process(1.0)
    TestHelper.assert_eq(_am.get_active_count("DEFER_SEL"), 1, "coalesced selects flush one line")
    _release_players(_stack_players("DEFER_SEL_BUS"))


func test_die_not_deferred_and_does_not_cancel_select():
    if not _am:
        return
    var voice := _defer_voice_fixture()
    _expire_retrigger("DEFER_SEL")
    _expire_retrigger("DEFER_DIE")
    _am.play_voice(voice.id, "select")
    TestHelper.assert_true(
        _am._pending_select.has(voice.id), "select is pending, not playing, before the die"
    )
    _am.play_voice(voice.id, "die")
    TestHelper.assert_eq(_am.get_active_count("DEFER_DIE"), 1, "die plays immediately")
    TestHelper.assert_true(
        _am._pending_select.has(voice.id), "die does not cancel the deferred select"
    )
    _am._process(1.0)
    TestHelper.assert_eq(
        _am.get_active_count("DEFER_SEL"), 1, "the select still flushes after the die"
    )
    _release_players(_stack_players("DEFER_SEL_BUS"))
    _release_players(_stack_players("DEFER_DIE_BUS"))


func test_zero_window_disables_deferral():
    if not _am:
        return
    var voice := _defer_voice_fixture()
    var saved: float = _am.SELECT_DEBOUNCE_MS
    _am.SELECT_DEBOUNCE_MS = 0.0
    _expire_retrigger("DEFER_SEL")
    _am.play_voice(voice.id, "select")
    _am.SELECT_DEBOUNCE_MS = saved
    TestHelper.assert_eq(_am.get_active_count("DEFER_SEL"), 1, "window 0 plays select immediately")
    TestHelper.assert_true(not _am._pending_select.has(voice.id), "window 0 leaves nothing pending")
    _release_players(_stack_players("DEFER_SEL_BUS"))


func test_ack_cancels_in_flight_select():
    if not _am:
        return
    var voice := _defer_voice_fixture()
    _expire_retrigger("DEFER_SEL")
    _am.play_voice(voice.id, "select")
    _am._process(1.0)
    TestHelper.assert_eq(
        _am.get_active_count("DEFER_SEL"), 1, "select is playing once the window elapses"
    )
    _expire_retrigger("DEFER_MOV")
    _am.play_voice(voice.id, "move")
    TestHelper.assert_eq(
        _am.get_active_count("DEFER_SEL"), 0, "an in-flight select is stopped by the ack"
    )
    TestHelper.assert_eq(_am.get_active_count("DEFER_MOV"), 1, "the acknowledgment plays")
    _release_players(_stack_players("DEFER_MOV_BUS"))


func test_select_flush_respects_window_boundary():
    if not _am:
        return
    var voice := _defer_voice_fixture()
    _expire_retrigger("DEFER_SEL")
    _am.play_voice(voice.id, "select")
    _am._process(0.05)
    TestHelper.assert_eq(_am.get_active_count("DEFER_SEL"), 0, "not flushed before the window")
    _am._process(0.2)
    TestHelper.assert_eq(_am.get_active_count("DEFER_SEL"), 1, "flushed once the window elapses")
    _release_players(_stack_players("DEFER_SEL_BUS"))


## An acknowledgment that has no playable variant must still cancel the pending
## select: the request is what supersedes the line, not the sound.
func test_empty_variant_ack_still_discards_select():
    if not _am:
        return
    var voice := _defer_voice_fixture()
    voice.feedback = []
    _expire_retrigger("DEFER_SEL")
    _am.play_voice(voice.id, "select")
    TestHelper.assert_true(_am._pending_select.has(voice.id), "select pending before the ack")
    _am.play_voice(voice.id, "feedback")
    _am._process(1.0)
    (
        TestHelper
        . assert_eq(
            _am.get_active_count("DEFER_SEL"),
            0,
            "an acknowledgment with no variant still cancels the select",
        )
    )


## Scope boundary: only the same voice set supersedes the select.
func test_other_voice_set_does_not_cancel_pending_select():
    if not _am:
        return
    var voice := _defer_voice_fixture()
    var other := VoiceData.new()
    other.id = "DEFER_OTHER"
    other.move = [_stack_fixture("DEFER_OTHER_MOV", 0.0).id]
    _am._voice_cache[other.id] = other
    _expire_retrigger("DEFER_SEL")
    _am.play_voice(voice.id, "select")
    _expire_retrigger("DEFER_OTHER_MOV")
    _am.play_voice(other.id, "move")
    _am._process(1.0)
    TestHelper.assert_eq(
        _am.get_active_count("DEFER_SEL"), 1, "a different voice set does not cancel the select"
    )
    _release_players(_stack_players("DEFER_SEL_BUS"))
    _release_players(_stack_players("DEFER_OTHER_MOV_BUS"))


func test_stack_cross_id_scales_to_bus_total():
    if not _am:
        return
    var bus := "STACK_MIX_BUS"
    _ensure_bus(bus)
    var ids: Array[String] = ["STACK_MIX_A", "STACK_MIX_B", "STACK_MIX_C"]
    for id in ids:
        var audio := AudioData.new()
        audio.id = id
        audio.path = "res://test/fixtures/audio/test_tone.wav"
        audio.bus = bus
        audio.volume_db = 0.0
        _am._audio_cache[id] = audio
        _am.play_sound(id, Vector3(0, 0, 0))
    var players := _stack_players(bus)
    TestHelper.assert_eq(players.size(), 3, "three distinct ids stacked")
    var expected_db: float = linear_to_db(1.0 / 3.0)
    for player: Node in players:
        var db: float = player.get("volume_db")
        (
            TestHelper
            . assert_true(
                is_equal_approx(db, expected_db),
                "each of 3 mixed ids at -20·log10(3) dB (got %s)" % db,
            )
        )
    _release_players(players)


func test_stack_cross_id_total_never_exceeds_single():
    if not _am:
        return
    var bus := "STACK_MIX_BOUND_BUS"
    _ensure_bus(bus)
    var ids: Array[String] = ["STACK_MIXB_A", "STACK_MIXB_B", "STACK_MIXB_C", "STACK_MIXB_D"]
    for id in ids:
        var audio := AudioData.new()
        audio.id = id
        audio.path = "res://test/fixtures/audio/test_tone.wav"
        audio.bus = bus
        audio.volume_db = -8.0
        _am._audio_cache[id] = audio
        _am.play_sound(id, Vector3(0, 0, 0))
    var players := _stack_players(bus)
    var total_amplitude := 0.0
    for player: Node in players:
        total_amplitude += db_to_linear(player.get("volume_db"))
    (
        TestHelper
        . assert_true(
            total_amplitude <= db_to_linear(-8.0) + 0.001,
            "mixed stack amplitude never exceeds a single copy (got %s)" % total_amplitude,
        )
    )
    _release_players(players)


func test_stack_buses_normalize_independently():
    if not _am:
        return
    var sfx_bus := "STACK_SEP_SFX_BUS"
    var voice_bus := "STACK_SEP_VOICE_BUS"
    _ensure_bus(sfx_bus)
    _ensure_bus(voice_bus)
    var sfx := AudioData.new()
    sfx.id = "STACK_SEP_SFX"
    sfx.path = "res://test/fixtures/audio/test_tone.wav"
    sfx.bus = sfx_bus
    sfx.volume_db = 0.0
    _am._audio_cache[sfx.id] = sfx
    var voice := AudioData.new()
    voice.id = "STACK_SEP_VOICE"
    voice.path = "res://test/fixtures/audio/test_tone.wav"
    voice.bus = voice_bus
    voice.volume_db = 0.0
    _am._audio_cache[voice.id] = voice
    _expire_retrigger(sfx.id)
    _am.play_sound(sfx.id, Vector3(0, 0, 0))
    _expire_retrigger(sfx.id)
    _am.play_sound(sfx.id, Vector3(0, 0, 0))
    _am.play_sound(voice.id, Vector3(0, 0, 0))
    var sfx_players := _stack_players(sfx_bus)
    TestHelper.assert_eq(sfx_players.size(), 2, "two SFX copies stacked")
    for player: Node in sfx_players:
        var db: float = player.get("volume_db")
        (
            TestHelper
            . assert_true(
                is_equal_approx(db, linear_to_db(0.5)),
                "SFX scaled by its own bus count only (got %s)" % db,
            )
        )
    var voice_players := _stack_players(voice_bus)
    TestHelper.assert_eq(voice_players.size(), 1, "one voice copy")
    for player: Node in voice_players:
        var db: float = player.get("volume_db")
        (
            TestHelper
            . assert_true(
                is_equal_approx(db, 0.0),
                "voice at full volume, not buried by the SFX stack (got %s)" % db,
            )
        )
    _release_players(sfx_players)
    _release_players(voice_players)


func test_retrigger_throttle_skips_rapid_same_id():
    if not _am:
        return
    var fixture := _stack_fixture("RETRIGGER_A", 0.0)
    _am.play_sound(fixture.id, Vector3(0, 0, 0))
    _am.play_sound(fixture.id, Vector3(0, 0, 0))
    _am.play_sound(fixture.id, Vector3(0, 0, 0))
    var players := _stack_players(fixture.bus)
    TestHelper.assert_eq(
        players.size(), 1, "rapid same-id replays within the interval spawn one player"
    )
    _release_players(players)


func test_retrigger_allows_distinct_ids():
    if not _am:
        return
    var bus := "RETRIGGER_MIX_BUS"
    _ensure_bus(bus)
    var ids: Array[String] = ["RETRIGGER_B", "RETRIGGER_C", "RETRIGGER_D"]
    for id in ids:
        var audio := AudioData.new()
        audio.id = id
        audio.path = "res://test/fixtures/audio/test_tone.wav"
        audio.bus = bus
        audio.volume_db = 0.0
        _am._audio_cache[id] = audio
        _am.play_sound(id, Vector3(0, 0, 0))
    TestHelper.assert_eq(
        _stack_players(bus).size(), 3, "distinct ids are not throttled by each other"
    )
    _release_players(_stack_players(bus))


func test_retrigger_allows_after_interval():
    if not _am:
        return
    var fixture := _stack_fixture("RETRIGGER_E", 0.0)
    _am.play_sound(fixture.id, Vector3(0, 0, 0))
    _expire_retrigger(fixture.id)
    _am.play_sound(fixture.id, Vector3(0, 0, 0))
    (
        TestHelper
        . assert_eq(
            _stack_players(fixture.bus).size(),
            2,
            "same id plays again once the retrigger window has elapsed",
        )
    )
    _release_players(_stack_players(fixture.bus))


func test_retrigger_override_shrinks_window():
    if not _am:
        return
    var overridden := _stack_fixture("RETRIGGER_F", 0.0)
    overridden.retrigger_ms = 50.0
    TestHelper.assert_eq(
        _am._effective_retrigger_ms(overridden), 50.0, "positive override wins over global"
    )
    var global := _stack_fixture("RETRIGGER_G", 0.0)
    (
        TestHelper
        . assert_eq(
            _am._effective_retrigger_ms(global),
            _am.RETRIGGER_INTERVAL_MS,
            "zero override falls back to the global interval",
        )
    )

    # A play 60 ms ago sits inside the 100 ms default window but outside a
    # 50 ms override window — the override must allow the replay.
    _am.play_sound(overridden.id, Vector3(0, 0, 0))
    _am._last_played_at[overridden.id] = Time.get_ticks_msec() - 60
    _am.play_sound(overridden.id, Vector3(0, 0, 0))
    var override_players := _stack_players(overridden.bus)
    TestHelper.assert_eq(
        override_players.size(), 2, "50 ms override allows replay 60 ms after first play"
    )
    _release_players(override_players)

    _am.play_sound(global.id, Vector3(0, 0, 0))
    _am._last_played_at[global.id] = Time.get_ticks_msec() - 60
    _am.play_sound(global.id, Vector3(0, 0, 0))
    var global_players := _stack_players(global.bus)
    TestHelper.assert_eq(
        global_players.size(), 1, "default window still suppresses replay 60 ms after play"
    )
    _release_players(global_players)
