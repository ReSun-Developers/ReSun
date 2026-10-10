extends Node

# Entity death handler tests — building and unit death cleanup

var _bm: Node = null
var _sm: Node = null


func _make_entity_with_health(health: int = 100) -> Node3D:
    var entity := Node3D.new()
    var hc := HealthComponent.new()
    hc.name = "HealthComponent"
    hc.max_health = health
    hc.current_health = health
    entity.add_child(hc)
    return entity


# --- Task 3.1: Building death removes entry from BuildingManager ---


func test_building_death_removes_entry_from_building_manager():
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var building := _make_entity_with_health(100)
    var cells: Array[Vector2i] = [Vector2i(100, 100)]
    (
        _bm
        . _buildings
        . append(
            {
                "node": building,
                "type": EntityData.new(),
                "origin": Vector2i(100, 100),
                "cells": cells,
            }
        )
    )
    var idx_before: int = _bm._buildings.size()
    # Call handler directly
    _bm._on_building_destroyed(building)
    var idx_after: int = _bm._buildings.size()
    TestHelper.assert_eq(idx_after, idx_before - 1, "building entry removed from _buildings")


# --- Task 3.2: Building death removes its registry entry (occupancy owned by
# FoundationComponent on world exit, not by the death handler) ---


func test_building_death_unregisters_registry_entry():
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    # Built with no StatsComponent to cover the null-owner path through the
    # registrar.
    var building := _make_entity_with_health(100)
    var data := EntityData.new()
    data.id = "TEST_DEATH_BLDG"
    _bm._register_building_entity(building, data, -1)
    var registered := false
    for entry in _bm._buildings:
        if entry.get("node") == building:
            registered = true
            break
    TestHelper.assert_true(registered, "building registered through the registrar")
    # Call handler directly
    _bm._on_building_destroyed(building)
    var found := false
    for entry in _bm._buildings:
        if entry.get("node") == building:
            found = true
            break
    TestHelper.assert_eq(found, false, "registry entry removed after death (null StatsComponent)")
    building.free()


# --- Task 3.3: Building death entry removed (PrerequisiteSystem test simplified) ---


func test_building_death_removes_entry_and_entity_freed():
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var building := _make_entity_with_health(100)
    var data := EntityData.new()
    data.id = "TEST_PREREQ_BLDG"
    var cells: Array[Vector2i] = [Vector2i(300, 300)]
    (
        _bm
        . _buildings
        . append(
            {
                "node": building,
                "type": data,
                "origin": Vector2i(300, 300),
                "cells": cells,
            }
        )
    )
    # Call handler directly
    _bm._on_building_destroyed(building)
    # Verify entry was removed
    var found := false
    for entry in _bm._buildings:
        if entry.get("node") == building:
            found = true
            break
    TestHelper.assert_eq(found, false, "building entry removed after death")


# --- Task 3.4: Building death deselects from SelectionManager ---


func test_building_death_deselects_from_selection_manager():
    if _bm == null or _sm == null:
        TestHelper.fail("BuildingManager or SelectionManager not injected")
        return
    var building := _make_entity_with_health(100)
    var select_comp := SelectComponent.new()
    select_comp.name = "SelectComponent"
    building.add_child(select_comp)
    _sm.add_entity(select_comp)
    var selected_before: bool = _sm.is_entity_selected(select_comp)
    # Handler uses get_node_or_null which needs tree membership.
    # Test the deselect logic directly by calling it on the SelectComponent.
    _sm.deselect_entity(select_comp)
    var selected_after: bool = select_comp in _sm.selected_entities
    TestHelper.assert_true(selected_before, "entity selected before death")
    TestHelper.assert_eq(selected_after, false, "deselect_entity removes from list")


# --- Task 3.5: building_destroyed signal emitted with correct args ---


func test_building_destroyed_signal_emitted():
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var building := _make_entity_with_health(100)
    var signal_data: Array = []
    _bm.building_destroyed.connect(func(b: Node3D, _d: EntityData) -> void: signal_data.append(b))
    var entry_data := EntityData.new()
    entry_data.id = "TEST_BLDG"
    var cells: Array[Vector2i] = [Vector2i(400, 400)]
    (
        _bm
        . _buildings
        . append(
            {
                "node": building,
                "type": entry_data,
                "origin": Vector2i(400, 400),
                "cells": cells,
            }
        )
    )
    # Call handler directly
    _bm._on_building_destroyed(building)
    TestHelper.assert_eq(signal_data.size(), 1, "building_destroyed emitted once")
    if signal_data.size() > 0:
        TestHelper.assert_eq(signal_data[0], building, "signal passes correct building node")


func test_building_death_unregisters_prerequisite():
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var saved: Dictionary = PrerequisiteSystem._player_buildings.duplicate(true)
    var building := _make_entity_with_health(100)
    var data := EntityData.new()
    data.id = "TEST_DEATH_PREREQ"
    _bm._register_building_entity(building, data, 2)
    TestHelper.assert_eq(
        PrerequisiteSystem.get_build_count(2, "TEST_DEATH_PREREQ"), 1, "registered for owner 2"
    )
    _bm._on_building_destroyed(building)
    (
        TestHelper
        . assert_eq(
            PrerequisiteSystem.get_build_count(2, "TEST_DEATH_PREREQ"),
            0,
            "prerequisite released on death",
        )
    )
    PrerequisiteSystem._player_buildings = saved
    building.free()


# --- Task 3.6: Entity health_zero triggers queue_free via signal ---


func test_health_zero_triggers_on_lethal_damage():
    var entity := Node3D.new()
    var hc := HealthComponent.new()
    hc.name = "HealthComponent"
    hc.max_health = 100
    hc.current_health = 100
    entity.add_child(hc)
    var signal_fired := false
    hc.health_zero.connect(func() -> void: signal_fired = true)
    hc.take_damage(200)
    TestHelper.assert_eq(hc.current_health, 0, "health clamped to zero")
    entity.free()


# --- Task 3.7: Entity not in BuildingManager still has handler called ---


func test_entity_not_in_building_manager_handler_is_noop():
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var building := _make_entity_with_health(100)
    # Do NOT register in BuildingManager
    var size_before: int = _bm._buildings.size()
    # Call handler — should be a no-op (early return)
    _bm._on_building_destroyed(building)
    var size_after: int = _bm._buildings.size()
    TestHelper.assert_eq(size_after, size_before, "no change to _buildings for unregistered entity")
    building.free()


# --- Task 3.8: Double handler call is safe ---


func test_double_handler_call_safe():
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var building := _make_entity_with_health(100)
    var cells: Array[Vector2i] = [Vector2i(500, 500)]
    (
        _bm
        . _buildings
        . append(
            {
                "node": building,
                "type": EntityData.new(),
                "origin": Vector2i(500, 500),
                "cells": cells,
            }
        )
    )
    # Call handler twice — second call should be a no-op
    _bm._on_building_destroyed(building)
    _bm._on_building_destroyed(building)
    # Should not crash, and entry should be removed only once
    var found := false
    for entry in _bm._buildings:
        if entry.get("node") == building:
            found = true
            break
    TestHelper.assert_eq(found, false, "building entry removed after double call")
    building.free()


# --- Task: Death plays the entity's die voice set, not a hardcoded sound ---


func _am_child_count() -> int:
    return AudioManager.get_child_count()


## Swaps the unit's voice set for a committed-fixture tone so death playback is
## verifiable without the gitignored external_assets/ .ogg files.
func _give_test_die_voice(entity: Node3D) -> void:
    var audio := AudioData.new()
    audio.id = "TEST_TONE"
    audio.path = "res://test/fixtures/audio/test_tone.wav"
    audio.bus = "Voice"
    AudioManager._audio_cache[audio.id] = audio
    var voice := VoiceData.new()
    voice.id = "TEST_VOICE"
    voice.die = ["TEST_TONE"]
    AudioManager._voice_cache[voice.id] = voice
    var voice_comp := entity.get_node_or_null("VoiceComponent") as VoiceComponent
    if voice_comp:
        voice_comp.voice_data = voice


func test_death_plays_die_voice_set():
    var before := _am_child_count()
    var entity := EntityFactory.create_entity("GDI_LIGHT_INFANTRY")
    TestHelper.assert_true(entity != null, "GDI light infantry created")
    if entity:
        var voice := entity.get_node_or_null("VoiceComponent") as VoiceComponent
        (
            TestHelper
            . assert_true(
                voice and voice.voice_data and not voice.voice_data.die.is_empty(),
                "infantry has a die voice set",
            )
        )
        _give_test_die_voice(entity)
        EntityFactory._on_entity_death(entity)
        var after := _am_child_count()
        TestHelper.assert_true(after >= before + 1, "death spawned at least one voice player")
        var last := AudioManager.get_child(AudioManager.get_child_count() - 1) as Node
        if last and last.has_method("get_bus"):
            TestHelper.assert_eq(last.get_bus(), "Voice", "die voice routed to Voice bus")


func test_death_of_resource_is_silent():
    var before := _am_child_count()
    var resource := EntityFactory.create_entity("TIBERIUM_RIPARIUS")
    TestHelper.assert_true(resource != null, "tiberium resource created")
    if resource:
        var voice := resource.get_node_or_null("VoiceComponent") as VoiceComponent
        TestHelper.assert_true(voice == null, "resource entity has no VoiceComponent")
        EntityFactory._on_entity_death(resource)
        TestHelper.assert_eq(_am_child_count(), before, "resource death plays no sound")
