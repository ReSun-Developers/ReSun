extends Node

# Combat SFX tests — warhead impact report on damaging hits, unvoiced death
# sound fallback, and die-voice precedence. Fixture-backed so they pass without
# the gitignored external_assets/ audio.

var _ef: Node = null
var _am: Node = null

const TEST_TONE_PATH: String = "res://test/fixtures/audio/test_tone.wav"


func _ready() -> void:
    if has_node("/root/EntityFactory"):
        _ef = get_node("/root/EntityFactory")
    if has_node("/root/AudioManager"):
        _am = get_node("/root/AudioManager")


## Registers the committed fixture tone under a custom id, bypassing the
## retrigger window so each test observes a fresh playback.
func _register_tone(id: String, bus: String = "SFX") -> void:
    _am._last_played_at[id] = -100000
    var audio := AudioData.new()
    audio.id = id
    audio.path = TEST_TONE_PATH
    audio.bus = bus
    _am._audio_cache[id] = audio


func _register_warhead(id: String, impact: String) -> void:
    var warhead := WarheadData.new()
    warhead.id = id
    warhead.sound_impact = impact
    warhead.armor_damage_multipliers = {"none": 1.0}
    _ef._global_rules.warheads[id] = warhead


func _count_bus_players(bus: String) -> int:
    var count := 0
    for child in _am.get_children():
        var is_player := child is AudioStreamPlayer or child is AudioStreamPlayer3D
        if is_player and child.get("bus") == bus:
            count += 1
    return count


func test_damaging_hit_plays_warhead_impact():
    TestHelper.assert_true(
        _ef != null and _am != null and _ef._global_rules != null, "autoloads and rules present"
    )
    TestHelper.assert_true(_ef and _am and _ef._global_rules, "autoloads and rules present")
    if not _ef or not _am or not _ef._global_rules:
        return
    _register_tone("TEST_IMPACT_SFX", "SFX")
    _register_warhead("TEST_IMPACT_WH", "TEST_IMPACT_SFX")
    var entity := _ef.create_entity("GDI_LIGHT_INFANTRY") as Node3D
    TestHelper.assert_true(entity != null, "entity created")
    if entity:
        var health := entity.get_node_or_null("HealthComponent") as HealthComponent
        TestHelper.assert_true(health != null, "entity has HealthComponent")
        if health:
            var before := _count_bus_players("SFX")
            var weapon := WeaponData.new()
            weapon.damage = 1
            weapon.warhead = "TEST_IMPACT_WH"
            WeaponDetonation.detonate(weapon, null, weapon.damage, entity)
            TestHelper.assert_eq(
                _count_bus_players("SFX"), before + 1, "impact report plays on the SFX bus"
            )
        entity.free()
    _ef._global_rules.warheads.erase("TEST_IMPACT_WH")


func test_non_warhead_damage_is_silent():
    TestHelper.assert_true(_ef != null and _am != null, "autoloads present")
    if not _ef or not _am:
        return
    var entity := _ef.create_entity("GDI_LIGHT_INFANTRY") as Node3D
    if entity:
        var health := entity.get_node_or_null("HealthComponent") as HealthComponent
        if health:
            var before := _count_bus_players("SFX")
            var weapon := WeaponData.new()
            weapon.damage = 1
            weapon.warhead = "crush"
            WeaponDetonation.detonate(weapon, null, weapon.damage, entity)
            TestHelper.assert_eq(
                _count_bus_players("SFX"), before, "non-warhead damage plays no impact sound"
            )
        entity.free()


func test_unvoiced_entity_death_plays_sound_die():
    TestHelper.assert_true(_ef != null and _am != null, "autoloads present")
    if not _ef or not _am:
        return
    _register_tone("TEST_DEATH_UNVOICED", "SFX")
    var entity := Node3D.new()
    var health := HealthComponent.new()
    health.name = "HealthComponent"
    entity.add_child(health)
    var data := EntityData.new()
    data.id = "TEST_UNVOICED"
    data.sound_die = "TEST_DEATH_UNVOICED"
    var before := _count_bus_players("SFX")
    _ef._on_entity_death(entity, data)
    TestHelper.assert_eq(
        _count_bus_players("SFX"), before + 1, "unvoiced death plays sound_die on the SFX bus"
    )
    TestHelper.assert_true(entity.is_queued_for_deletion(), "entity freed normally on death")


func test_die_voice_takes_precedence_over_sound_die():
    TestHelper.assert_true(_ef != null and _am != null, "autoloads present")
    if not _ef or not _am:
        return
    _register_tone("TEST_DEATH_VOICE", "Voice")
    _register_tone("TEST_DEATH_FALLBACK", "SFX")
    var entity := Node3D.new()
    var voice_comp := VoiceComponent.new()
    voice_comp.name = "VoiceComponent"
    entity.add_child(voice_comp)
    var voice := VoiceData.new()
    voice.id = "TEST_VOICE_PREC"
    voice.die = ["TEST_DEATH_VOICE"]
    voice_comp.voice_data = voice
    _am._voice_cache[voice.id] = voice
    var health := HealthComponent.new()
    health.name = "HealthComponent"
    entity.add_child(health)
    var data := EntityData.new()
    data.id = "TEST_BOTH"
    data.sound_die = "TEST_DEATH_FALLBACK"
    var sfx_before := _count_bus_players("SFX")
    var voice_before := _count_bus_players("Voice")
    _ef._on_entity_death(entity, data)
    TestHelper.assert_eq(
        _count_bus_players("Voice"), voice_before + 1, "die voice plays when both are set"
    )
    TestHelper.assert_eq(
        _count_bus_players("SFX"), sfx_before, "sound_die is suppressed by the die voice"
    )


func test_entity_without_death_sound_is_silent():
    TestHelper.assert_true(_ef != null and _am != null, "autoloads present")
    if not _ef or not _am:
        return
    var entity := Node3D.new()
    var health := HealthComponent.new()
    health.name = "HealthComponent"
    entity.add_child(health)
    var data := EntityData.new()
    data.id = "TEST_SILENT"
    data.sound_die = ""
    var before := _count_bus_players("SFX") + _count_bus_players("Voice")
    _ef._on_entity_death(entity, data)
    (
        TestHelper
        . assert_eq(
            _count_bus_players("SFX") + _count_bus_players("Voice"),
            before,
            "no death sound when neither voice nor sound_die is set",
        )
    )
    TestHelper.assert_true(entity.is_queued_for_deletion(), "entity freed normally")


func test_unknown_impact_and_death_ids_stay_silent():
    TestHelper.assert_true(
        _ef != null and _am != null and _ef._global_rules != null, "autoloads and rules present"
    )
    TestHelper.assert_true(_ef and _am and _ef._global_rules, "autoloads and rules present")
    if not _ef or not _am or not _ef._global_rules:
        return
    _register_warhead("TEST_MISSING_WH", "NO_SUCH_IMPACT_ID")
    var entity := _ef.create_entity("GDI_LIGHT_INFANTRY") as Node3D
    if entity:
        var health := entity.get_node_or_null("HealthComponent") as HealthComponent
        if health:
            var before := _count_bus_players("SFX")
            var weapon := WeaponData.new()
            weapon.damage = 1
            weapon.warhead = "TEST_MISSING_WH"
            WeaponDetonation.detonate(weapon, null, weapon.damage, entity)
            TestHelper.assert_eq(
                _count_bus_players("SFX"), before, "unknown impact id stays silent"
            )
        entity.free()
    _ef._global_rules.warheads.erase("TEST_MISSING_WH")

    var corpse := Node3D.new()
    var data := EntityData.new()
    data.id = "TEST_MISSING_DIE"
    data.sound_die = "NO_SUCH_DEATH_ID"
    var before_die := _count_bus_players("SFX")
    _ef._on_entity_death(corpse, data)
    TestHelper.assert_eq(_count_bus_players("SFX"), before_die, "unknown death id stays silent")


func test_random_impact_plays_exactly_one_entry():
    TestHelper.assert_true(_ef != null and _am != null, "autoloads present")
    if not _ef or not _am or not _ef._global_rules:
        return
    _register_tone("TEST_RAND_A", "SFX")
    _register_tone("TEST_RAND_B", "SFX")
    _register_warhead("TEST_RAND_WH", "TEST_RAND_A,TEST_RAND_B")
    var entity := _ef.create_entity("GDI_LIGHT_INFANTRY") as Node3D
    if entity:
        var health := entity.get_node_or_null("HealthComponent") as HealthComponent
        if health:
            var before := _count_bus_players("SFX")
            var weapon := WeaponData.new()
            weapon.damage = 1
            weapon.warhead = "TEST_RAND_WH"
            WeaponDetonation.detonate(weapon, null, weapon.damage, entity)
            TestHelper.assert_eq(
                _count_bus_players("SFX"), before + 1, "random impact plays exactly one entry"
            )
        entity.free()
    _ef._global_rules.warheads.erase("TEST_RAND_WH")


func test_random_death_plays_exactly_one_entry():
    TestHelper.assert_true(_ef != null and _am != null, "autoloads present")
    if not _ef or not _am:
        return
    _register_tone("TEST_RD_A", "SFX")
    _register_tone("TEST_RD_B", "SFX")
    var entity := Node3D.new()
    var health := HealthComponent.new()
    health.name = "HealthComponent"
    entity.add_child(health)
    var data := EntityData.new()
    data.id = "TEST_RAND_DIE"
    data.sound_die = "TEST_RD_A,TEST_RD_B"
    var before := _count_bus_players("SFX")
    _ef._on_entity_death(entity, data)
    TestHelper.assert_eq(
        _count_bus_players("SFX"), before + 1, "random death plays exactly one entry"
    )
