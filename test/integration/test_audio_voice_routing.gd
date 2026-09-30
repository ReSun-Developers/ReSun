extends Node

# Integration tests — voice event routing on selection/orders and weapon fire sound
# report parsing. Uses the real AudioManager autoload to observe playback decisions
# without relying on the audio driver.

var _am: Node = null
var _sm: Node = null
var _ts: Node = null
var _bounds_saved: bool = false
var _saved_grid_cells: Vector2i
var _saved_insets: Vector4i

const TEST_TONE_PATH: String = "res://test/fixtures/audio/test_tone.wav"


## The select-voice tests spawn a unit at the world origin and select it; that
## requires a real playable map — selection is gated to the visible diamond.
## BoundsSystem statics are process-wide, so the first call snapshots them and
## _restore_bounds puts them back after the tests that touched the grid.
func _ensure_playable_grid() -> void:
    if not _bounds_saved:
        _bounds_saved = true
        _saved_grid_cells = BoundsSystem.grid_cells
        _saved_insets = Vector4i(
            BoundsSystem.left_inset,
            BoundsSystem.right_inset,
            BoundsSystem.top_inset,
            BoundsSystem.bottom_inset,
        )
    if _ts:
        _ts.init_grid(50, 50)
    BoundsSystem.grid_cells = Vector2i(50, 50)
    BoundsSystem.left_inset = BoundsSystem.DEFAULT_VISIBLE_INSETS.x
    BoundsSystem.right_inset = BoundsSystem.DEFAULT_VISIBLE_INSETS.y
    BoundsSystem.top_inset = BoundsSystem.DEFAULT_VISIBLE_INSETS.z
    BoundsSystem.bottom_inset = BoundsSystem.DEFAULT_VISIBLE_INSETS.w


func _restore_bounds() -> void:
    if not _bounds_saved:
        return
    _bounds_saved = false
    BoundsSystem.grid_cells = _saved_grid_cells
    BoundsSystem.left_inset = _saved_insets.x
    BoundsSystem.right_inset = _saved_insets.y
    BoundsSystem.top_inset = _saved_insets.z
    BoundsSystem.bottom_inset = _saved_insets.w


func _ready() -> void:
    if has_node("/root/AudioManager"):
        _am = get_node("/root/AudioManager")
    if has_node("/root/SelectionManager"):
        _sm = get_node("/root/SelectionManager")


## Bypass the retrigger throttle so a test observes a fresh playback — these
## tests verify routing/parsing, not rate throttling. Mirrors the helper in
## the audio_manager unit tests.
func _expire_retrigger(id: String) -> void:
    _am._last_played_at[id] = -100000


## Registers a committed-fixture tone + a voice set that routes every event to it,
## so playback assertions pass without the gitignored external_assets/ .ogg files.
func _register_test_voice() -> VoiceData:
    var voice := VoiceData.new()
    voice.id = "TEST_VOICE"
    voice.select = ["TEST_TONE"]
    voice.move = ["TEST_TONE"]
    voice.attack = ["TEST_TONE"]
    voice.die = ["TEST_TONE"]
    if _am:
        _expire_retrigger("TEST_TONE")
        var audio := AudioData.new()
        audio.id = "TEST_TONE"
        audio.path = TEST_TONE_PATH
        audio.bus = "Voice"
        _am._audio_cache[audio.id] = audio
        _am._voice_cache[voice.id] = voice
    return voice


## Registers the committed-fixture tone under a custom id so report-selection
## tests can seed and count per-id stacks without the gitignored .ogg files.
func _register_tone_id(id: String) -> void:
    if not _am:
        return
    _expire_retrigger(id)
    var audio := AudioData.new()
    audio.id = id
    audio.path = TEST_TONE_PATH
    audio.bus = "Voice"
    _am._audio_cache[id] = audio


## Builds an out-of-tree CombatComponent wired to a single weapon with the given
## sound_report plus a damageable target. Returns [entity, combat, weapon, target].
func _make_fire_setup(report: String) -> Array:
    var entity := Node3D.new()
    entity.name = "CombatEntity"
    var combat := CombatComponent.new()
    combat.name = "CombatComponent"
    entity.add_child(combat)
    var weapon := WeaponData.new()
    weapon.id = "TEST_WEAPON"
    weapon.damage = 1
    weapon.attack_range = 1.0
    weapon.rate_of_fire = 1.0
    weapon.sound_report = report
    combat.weapons = [weapon]
    combat._init_cooldowns()
    var target := Node3D.new()
    var health := HealthComponent.new()
    health.name = "HealthComponent"
    health.max_health = 100
    health.current_health = 100
    target.add_child(health)
    entity.global_position = Vector3(1, 0, 1)
    return [entity, combat, weapon, target]


func _give_test_voice(entity: Node3D) -> void:
    var voice_comp := entity.get_node_or_null("VoiceComponent") as VoiceComponent
    if voice_comp:
        voice_comp.voice_data = _register_test_voice()


func _make_unit_with_voice(player_id: int = 0) -> Node3D:
    var entity := EntityFactory.create_entity("GDI_LIGHT_INFANTRY")
    if entity:
        _give_test_voice(entity)
        var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
        if stats:
            stats.player_id = player_id
    return entity


func test_select_voice_plays_for_local_unit():
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    _ensure_playable_grid()
    var rules := GlobalRules.get_current()
    var saved_shroud: bool = rules.shroud_enabled
    var saved_fog: bool = rules.fog_of_war
    rules.shroud_enabled = false
    rules.fog_of_war = false
    var entity := _make_unit_with_voice(0)
    TestHelper.assert_true(entity != null, "unit created")
    if not entity or not _am:
        return
    var before := _am.get_child_count()
    var sc := entity.get_node_or_null("SelectComponent") as SelectComponent
    TestHelper.assert_true(sc != null, "unit has SelectComponent")
    if sc:
        _sm.select_entity(sc)
        # The select line is deferred by SELECT_DEBOUNCE_MS; flush the window.
        _am._process(1.0)
        (
            TestHelper
            . assert_true(
                _am.get_child_count() >= before + 1,
                "select voice playback spawned a player for local unit",
            )
        )
        _sm.remove_entity(sc)
    entity.queue_free()
    rules.shroud_enabled = saved_shroud
    rules.fog_of_war = saved_fog
    _restore_bounds()


func test_select_voice_silent_for_enemy_unit():
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    _ensure_playable_grid()
    var entity := _make_unit_with_voice(1)
    TestHelper.assert_true(entity != null, "enemy unit created")
    if not entity or not _am:
        return
    var before := _am.get_child_count()
    var sc := entity.get_node_or_null("SelectComponent") as SelectComponent
    if sc:
        _sm.select_entity(sc)
        (
            TestHelper
            . assert_eq(
                _am.get_child_count(),
                before,
                "selecting an enemy unit plays no voice",
            )
        )
        _sm.remove_entity(sc)
    entity.queue_free()
    _restore_bounds()


func test_weapon_fire_parses_comma_report():
    # Stacking-driven report selection (original Report= behavior): with no
    # stacked copies, the FIRST entry of a comma-separated report plays and
    # later entries stay silent. Both ids resolve to the committed fixture.
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    _register_tone_id("TEST_REPORT_FIRST_A")
    _register_tone_id("TEST_REPORT_FIRST_B")
    var setup := _make_fire_setup("TEST_REPORT_FIRST_A,TEST_REPORT_FIRST_B")

    var setup_combat: CombatComponent = setup[1]
    var setup_weapon: WeaponData = setup[2]
    setup_combat._fire_weapon(setup_weapon, setup[3])
    TestHelper.assert_eq(
        _am.get_active_count("TEST_REPORT_FIRST_A"), 1, "first report entry plays when unstacked"
    )
    TestHelper.assert_eq(
        _am.get_active_count("TEST_REPORT_FIRST_B"), 0, "later entries stay silent when unstacked"
    )
    setup[0].queue_free()
    setup[3].queue_free()


func test_report_rotates_when_first_entry_saturated():
    # Seeding the rotation threshold of live copies on the first entry forces
    # the next fire onto the later entry — the stacking-driven rotation.
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    _register_tone_id("TEST_REPORT_ROT_A")
    _register_tone_id("TEST_REPORT_ROT_B")
    for i in _am.REPORT_STACK_PER_ID:
        _expire_retrigger("TEST_REPORT_ROT_A")
        _am.play_sound("TEST_REPORT_ROT_A")
    (
        TestHelper
        . assert_eq(
            _am.get_active_count("TEST_REPORT_ROT_A"),
            _am.REPORT_STACK_PER_ID,
            "first entry seeded to the rotation threshold",
        )
    )
    var setup := _make_fire_setup("TEST_REPORT_ROT_A,TEST_REPORT_ROT_B")

    var setup_combat: CombatComponent = setup[1]
    var setup_weapon: WeaponData = setup[2]
    setup_combat._fire_weapon(setup_weapon, setup[3])
    TestHelper.assert_eq(
        _am.get_active_count("TEST_REPORT_ROT_B"), 1, "stacked fire rotates to the later entry"
    )
    (
        TestHelper
        . assert_eq(
            _am.get_active_count("TEST_REPORT_ROT_A"),
            _am.REPORT_STACK_PER_ID,
            "saturated first entry gains no copy",
        )
    )
    setup[0].queue_free()
    setup[3].queue_free()


func test_report_all_saturated_plays_last_entry():
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    _register_tone_id("TEST_REPORT_SAT_A")
    _register_tone_id("TEST_REPORT_SAT_B")
    for id in ["TEST_REPORT_SAT_A", "TEST_REPORT_SAT_B"]:
        for i in _am.REPORT_STACK_PER_ID:
            _expire_retrigger(id)
            _am.play_sound(id)
    # The seeded stacks represent already-ringing fire; the new shot must not
    # be swallowed by the same-frame retrigger window of the last seed.
    _expire_retrigger("TEST_REPORT_SAT_A")
    _expire_retrigger("TEST_REPORT_SAT_B")
    var setup := _make_fire_setup("TEST_REPORT_SAT_A,TEST_REPORT_SAT_B")

    var setup_combat: CombatComponent = setup[1]
    var setup_weapon: WeaponData = setup[2]
    setup_combat._fire_weapon(setup_weapon, setup[3])
    (
        TestHelper
        . assert_eq(
            _am.get_active_count("TEST_REPORT_SAT_B"),
            _am.REPORT_STACK_PER_ID + 1,
            "fully saturated report plays the last entry",
        )
    )
    (
        TestHelper
        . assert_eq(
            _am.get_active_count("TEST_REPORT_SAT_A"),
            _am.REPORT_STACK_PER_ID,
            "saturated earlier entry gains no copy",
        )
    )
    setup[0].queue_free()
    setup[3].queue_free()


func test_report_skips_unknown_id():
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    _register_tone_id("TEST_REPORT_SKIP_B")
    var setup := _make_fire_setup("NO_SUCH_REPORT_ID,TEST_REPORT_SKIP_B")

    var setup_combat: CombatComponent = setup[1]
    var setup_weapon: WeaponData = setup[2]
    setup_combat._fire_weapon(setup_weapon, setup[3])
    TestHelper.assert_eq(
        _am.get_active_count("TEST_REPORT_SKIP_B"), 1, "unknown id is skipped, later entry plays"
    )
    setup[0].queue_free()
    setup[3].queue_free()


func test_single_entry_report_unchanged():
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    _register_tone_id("TEST_REPORT_ONE_A")
    var setup := _make_fire_setup("TEST_REPORT_ONE_A")

    var setup_combat: CombatComponent = setup[1]
    var setup_weapon: WeaponData = setup[2]
    setup_combat._fire_weapon(setup_weapon, setup[3])
    TestHelper.assert_eq(
        _am.get_active_count("TEST_REPORT_ONE_A"), 1, "single-entry report spawns one player"
    )
    setup[0].queue_free()
    setup[3].queue_free()


func test_weapon_fire_empty_report_silent():
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    var entity := Node3D.new()
    entity.name = "CombatEntity"
    var combat := CombatComponent.new()
    combat.name = "CombatComponent"
    entity.add_child(combat)
    var weapon := WeaponData.new()
    weapon.id = "TEST_WEAPON"
    weapon.damage = 1
    weapon.attack_range = 1.0
    weapon.rate_of_fire = 1.0
    weapon.sound_report = ""
    var target := Node3D.new()
    var health := HealthComponent.new()
    health.name = "HealthComponent"
    health.max_health = 100
    health.current_health = 100
    target.add_child(health)

    var before := _am.get_child_count()
    combat._fire_weapon(weapon, target)
    TestHelper.assert_eq(_am.get_child_count(), before, "empty report plays no sound")
    entity.queue_free()
    target.queue_free()


func test_group_select_plays_one_voice():
    # C&C rule: a multi-unit selection event plays exactly ONE select voice
    # (the NW-most unit), never one per unit.
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    var sm: Node = _sm
    var a := _make_unit_with_voice(0)
    var b := _make_unit_with_voice(0)
    var c := _make_unit_with_voice(0)
    a.global_position = Vector3(0, 0, 0)
    b.global_position = Vector3(5, 0, 0)
    c.global_position = Vector3(0, 0, 5)
    var sc_a := a.get_node_or_null("SelectComponent") as SelectComponent
    var sc_b := b.get_node_or_null("SelectComponent") as SelectComponent
    var sc_c := c.get_node_or_null("SelectComponent") as SelectComponent
    var before := _am.get_child_count()
    for sc in [sc_a, sc_b, sc_c]:
        sm.add_entity(sc)
    var after_add := _am.get_child_count()
    TestHelper.assert_eq(after_add, before, "add_entity alone plays no voice (deferred to event)")
    sm.play_select_voice_for_entities([sc_a, sc_b, sc_c])
    # The select line is deferred by SELECT_DEBOUNCE_MS; flush the window.
    _am._process(1.0)
    TestHelper.assert_eq(
        _am.get_child_count(), after_add + 1, "group select event plays exactly one voice"
    )
    for sc in [sc_a, sc_b, sc_c]:
        sm.remove_entity(sc)
    a.queue_free()
    b.queue_free()
    c.queue_free()
    _restore_bounds()


func test_northwest_most_picks_screen_top_unit():
    # With no camera in headless tests the picker falls back to world-space
    # ordering: smallest +Z (top-most), then largest +X (right-most).
    var sm: Node = _sm
    var a := _make_unit_with_voice(0)
    var b := _make_unit_with_voice(0)
    var c := _make_unit_with_voice(0)
    a.position = Vector3(0, 0, 0)
    b.position = Vector3(0, 0, 5)
    c.position = Vector3(7, 0, 2)
    var sc_a := a.get_node_or_null("SelectComponent") as SelectComponent
    var sc_b := b.get_node_or_null("SelectComponent") as SelectComponent
    var sc_c := c.get_node_or_null("SelectComponent") as SelectComponent
    var picked := sm.get_northwest_most([sc_a, sc_b, sc_c]) as SelectComponent
    TestHelper.assert_eq(picked, sc_a, "smallest +Z is top-most (NW-most)")
    var picked2 := sm.get_northwest_most([sc_b, sc_c]) as SelectComponent
    TestHelper.assert_eq(picked2, sc_c, "tie-break goes to largest +X (NE-most)")
    a.queue_free()
    b.queue_free()
    c.queue_free()
    _restore_bounds()


## A voice set whose select/move/attack/die events resolve to distinct ids (all
## pointing at the committed fixture tone), so order-voice routing is observable.
func _register_distinct_voice() -> VoiceData:
    var voice := VoiceData.new()
    voice.id = "TEST_VOICE_DISTINCT"
    voice.select = ["TEST_VOICE_SEL"]
    voice.move = ["TEST_VOICE_MOV"]
    voice.attack = ["TEST_VOICE_ATK"]
    voice.die = ["TEST_VOICE_DIE"]
    for id in ["TEST_VOICE_SEL", "TEST_VOICE_MOV", "TEST_VOICE_ATK", "TEST_VOICE_DIE"]:
        _register_tone_id(id)
    if _am:
        _am._voice_cache[voice.id] = voice
    return voice


func _make_distinct_unit(player_id: int = 0) -> Node3D:
    var entity := _make_unit_with_voice(player_id)
    var voice_comp := entity.get_node_or_null("VoiceComponent") as VoiceComponent
    if voice_comp:
        voice_comp.voice_data = _register_distinct_voice()
    return entity


func _order(event: String, cursor: CursorState.Type) -> OrderResult:
    return OrderResult.new(cursor, 10, null, Vector3.ZERO, false, Callable(), event)


func test_harvest_order_plays_move_voice_not_attack():
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    var unit := _make_distinct_unit(0)
    TestHelper.assert_true(unit != null, "unit created")
    if not unit or not _am:
        return
    var sc := unit.get_node_or_null("SelectComponent") as SelectComponent
    _sm.add_entity(sc)
    var before_move: int = _am.get_active_count("TEST_VOICE_MOV")
    var before_atk: int = _am.get_active_count("TEST_VOICE_ATK")
    MouseHandler.play_order_voices(
        [_order(VoiceData.EVENT_MOVE, CursorState.Type.HARVEST)] as Array[OrderResult], _sm
    )
    TestHelper.assert_eq(
        _am.get_active_count("TEST_VOICE_MOV"), before_move + 1, "harvest plays the move voice"
    )
    TestHelper.assert_eq(
        _am.get_active_count("TEST_VOICE_ATK"), before_atk, "harvest does not play the attack voice"
    )
    _sm.remove_entity(sc)
    unit.queue_free()


func test_attack_order_plays_attack_voice_not_move():
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    var unit := _make_distinct_unit(0)
    TestHelper.assert_true(unit != null, "unit created")
    if not unit or not _am:
        return
    var sc := unit.get_node_or_null("SelectComponent") as SelectComponent
    _sm.add_entity(sc)
    var before_move: int = _am.get_active_count("TEST_VOICE_MOV")
    var before_atk: int = _am.get_active_count("TEST_VOICE_ATK")
    MouseHandler.play_order_voices(
        [_order(VoiceData.EVENT_ATTACK, CursorState.Type.ATTACK)] as Array[OrderResult], _sm
    )
    TestHelper.assert_eq(
        _am.get_active_count("TEST_VOICE_ATK"), before_atk + 1, "attack plays the attack voice"
    )
    TestHelper.assert_eq(
        _am.get_active_count("TEST_VOICE_MOV"), before_move, "attack does not play the move voice"
    )
    _sm.remove_entity(sc)
    unit.queue_free()


## Mixed-selection routing: the confirmation event must come from the
## highest-priority resolved order, not from selection order.
func test_order_voice_event_uses_highest_priority():
    var move_order := OrderResult.new(
        CursorState.Type.DEPLOY, 15, null, Vector3.ZERO, false, Callable(), VoiceData.EVENT_MOVE
    )
    var attack_order := OrderResult.new(
        CursorState.Type.ATTACK, 30, null, Vector3.ZERO, false, Callable(), VoiceData.EVENT_ATTACK
    )
    (
        TestHelper
        . assert_eq(
            MouseHandler._voice_event_for_orders([move_order, attack_order] as Array[OrderResult]),
            VoiceData.EVENT_ATTACK,
            "attack (priority 30) wins over an earlier move (priority 15)",
        )
    )
    (
        TestHelper
        . assert_eq(
            MouseHandler._voice_event_for_orders([attack_order, move_order] as Array[OrderResult]),
            VoiceData.EVENT_ATTACK,
            "result does not depend on batch order",
        )
    )


## The speaker is the NW-most selected unit that can voice the event; a unit
## without a variant for it is skipped rather than silencing the confirmation.
func test_ack_voice_skips_speaker_without_event():
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    var voiceless := _make_distinct_unit(0)
    var voiceless_voice := voiceless.get_node_or_null("VoiceComponent") as VoiceComponent
    var no_attack := VoiceData.new()
    no_attack.id = "TEST_VOICE_NO_ATTACK"
    no_attack.select = ["TEST_VOICE_SEL"]
    if voiceless_voice:
        voiceless_voice.voice_data = no_attack
    var speaker := _make_distinct_unit(0)
    # NW-most (world fallback) = smallest +Z, so the event-less unit is NW-most.
    voiceless.position = Vector3(0, 0, 0)
    speaker.position = Vector3(0, 0, 5)
    var sc_v := voiceless.get_node_or_null("SelectComponent") as SelectComponent
    var sc_s := speaker.get_node_or_null("SelectComponent") as SelectComponent
    _sm.add_entity(sc_v)
    _sm.add_entity(sc_s)
    var before: int = _am.get_active_count("TEST_VOICE_ATK")
    MouseHandler.play_ack_voice(_sm, VoiceData.EVENT_ATTACK)
    (
        TestHelper
        . assert_eq(
            _am.get_active_count("TEST_VOICE_ATK"),
            before + 1,
            "the NW-most unit that has the event's voice speaks",
        )
    )
    _sm.remove_entity(sc_v)
    _sm.remove_entity(sc_s)
    voiceless.queue_free()
    speaker.queue_free()


func test_empty_voice_event_order_is_silent():
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    var unit := _make_distinct_unit(0)
    TestHelper.assert_true(unit != null, "unit created")
    if not unit or not _am:
        return
    var sc := unit.get_node_or_null("SelectComponent") as SelectComponent
    _sm.add_entity(sc)
    var before := _am.get_child_count()
    MouseHandler.play_order_voices([_order("", CursorState.Type.MOVE)] as Array[OrderResult], _sm)
    TestHelper.assert_eq(_am.get_child_count(), before, "empty voice event plays nothing")
    _sm.remove_entity(sc)
    unit.queue_free()


## GH #305, realistic cadence: the order arrives after the debounce window, so
## the select is already playing — the acknowledgment must stop it, not overlap.
func test_order_after_window_cancels_playing_select():
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    _ensure_playable_grid()
    var rules := GlobalRules.get_current()
    var saved_shroud: bool = rules.shroud_enabled
    var saved_fog: bool = rules.fog_of_war
    rules.shroud_enabled = false
    rules.fog_of_war = false
    var unit := _make_distinct_unit(0)
    TestHelper.assert_true(unit != null, "unit created")
    if not unit or not _am:
        rules.shroud_enabled = saved_shroud
        rules.fog_of_war = saved_fog
        _restore_bounds()
        return
    var sc := unit.get_node_or_null("SelectComponent") as SelectComponent
    var before_sel: int = _am.get_active_count("TEST_VOICE_SEL")
    var before_mov: int = _am.get_active_count("TEST_VOICE_MOV")
    _sm.select_entity(sc)
    # Window elapses: the select starts playing before the order arrives.
    _am._process(1.0)
    TestHelper.assert_eq(
        _am.get_active_count("TEST_VOICE_SEL"), before_sel + 1, "select is playing"
    )
    MouseHandler.play_order_voices(
        [_order(VoiceData.EVENT_MOVE, CursorState.Type.HARVEST)] as Array[OrderResult], _sm
    )
    TestHelper.assert_eq(
        _am.get_active_count("TEST_VOICE_SEL"), before_sel, "the playing select is stopped"
    )
    TestHelper.assert_eq(
        _am.get_active_count("TEST_VOICE_MOV"), before_mov + 1, "only the ack line remains"
    )
    _sm.remove_entity(sc)
    unit.queue_free()
    rules.shroud_enabled = saved_shroud
    rules.fog_of_war = saved_fog
    _restore_bounds()


## GH #305: a select immediately followed by an order must yield one voice line,
## not two overlapped ones. The deferred select is discarded by the order ack.
func test_select_then_order_yields_one_voice_line():
    TestHelper.assert_true(_am != null, "AudioManager autoload present")
    _ensure_playable_grid()
    var rules := GlobalRules.get_current()
    var saved_shroud: bool = rules.shroud_enabled
    var saved_fog: bool = rules.fog_of_war
    rules.shroud_enabled = false
    rules.fog_of_war = false
    var unit := _make_distinct_unit(0)
    TestHelper.assert_true(unit != null, "unit created")
    if not unit or not _am:
        rules.shroud_enabled = saved_shroud
        rules.fog_of_war = saved_fog
        _restore_bounds()
        return
    var sc := unit.get_node_or_null("SelectComponent") as SelectComponent
    var before_sel: int = _am.get_active_count("TEST_VOICE_SEL")
    var before_mov: int = _am.get_active_count("TEST_VOICE_MOV")
    _sm.select_entity(sc)
    MouseHandler.play_order_voices(
        [_order(VoiceData.EVENT_MOVE, CursorState.Type.HARVEST)] as Array[OrderResult], _sm
    )
    # Flush the debounce window: a surviving select would play here and overlap.
    _am._process(1.0)
    TestHelper.assert_eq(
        _am.get_active_count("TEST_VOICE_SEL"), before_sel, "select line discarded by the ack"
    )
    TestHelper.assert_eq(
        _am.get_active_count("TEST_VOICE_MOV"), before_mov + 1, "only the acknowledgment plays"
    )
    _sm.remove_entity(sc)
    unit.queue_free()
    rules.shroud_enabled = saved_shroud
    rules.fog_of_war = saved_fog
    _restore_bounds()
