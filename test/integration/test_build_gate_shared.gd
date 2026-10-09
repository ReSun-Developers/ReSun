extends Node

# Integration: the sidebar build list and the production gate share one
# per-player build decision (openspec build-gate, "Production and the build
# list share the decision"). A type the gate denies is absent from the list and
# refused by start_production; a gated-in type is both listed and accepted.

const SIDEBAR_SCRIPT: GDScript = preload("res://scripts/ui/Sidebar.gd")

const PASS_ID: String = "it_pass_type"
const FAIL_ID: String = "it_fail_type"
const FACTORY_ID: String = "it_factory"
const QUEUE: String = "InfantryType"


func _synth(id: String, prereq: Array) -> EntityData:
    var data := EntityData.new()
    data.id = id
    data.entity_type = EntityData.EntityType.BUILDING
    data.buildable = true
    data.tech_level = 1
    data.cost = 100
    data.buildable_queue = QUEUE
    data.prerequisite = PackedStringArray(prereq)
    return data


func _factory() -> EntityData:
    var data := EntityData.new()
    data.id = FACTORY_ID
    data.entity_type = EntityData.EntityType.BUILDING
    data.buildable = true
    data.tech_level = 1
    data.factory = QUEUE
    return data


func _cleanup() -> void:
    var local_id := PlayerManager.get_local_player_id()
    var key: String = ProductionManager.get_queue_key(local_id, QUEUE)
    if (
        ProductionManager._queues.has(key)
        and not (ProductionManager._queues[key] as Array).is_empty()
    ):
        ProductionManager.cancel_production(local_id, key, 0, 999)
    var factory: EntityData = EntityFactory._entity_cache.get(FACTORY_ID, null)
    if factory:
        PrerequisiteSystem.unregister_building(local_id, factory)
    EntityFactory._entity_cache.erase(PASS_ID)
    EntityFactory._entity_cache.erase(FAIL_ID)
    EntityFactory._entity_cache.erase(FACTORY_ID)


func test_build_list_and_production_share_one_decision():
    var local_id := PlayerManager.get_local_player_id()
    var previous_tech: int = PlayerManager.get_player_data(local_id).tech_level
    PlayerManager.get_player_data(local_id).tech_level = 10

    var factory := _factory()
    EntityFactory._entity_cache[FACTORY_ID] = factory
    PrerequisiteSystem.register_building(local_id, factory)

    var pass_data := _synth(PASS_ID, [])
    var fail_data := _synth(FAIL_ID, ["NEVER_OWNED_BUILDING"])
    EntityFactory._entity_cache[PASS_ID] = pass_data
    EntityFactory._entity_cache[FAIL_ID] = fail_data

    # One decision, read directly.
    TestHelper.assert_true(
        bool(PrerequisiteSystem.evaluate_build(local_id, pass_data)["enabled"]),
        "gated-in type is enabled"
    )
    TestHelper.assert_true(
        not bool(PrerequisiteSystem.evaluate_build(local_id, fail_data)["enabled"]),
        "denied type is disabled"
    )

    # Production path (can_build delegates to the same gate).
    var pass_accepted: bool = ProductionManager.start_production(local_id, pass_data)
    var fail_refused: bool = not ProductionManager.start_production(local_id, fail_data)
    TestHelper.assert_true(pass_accepted, "production accepts the gated-in type")
    TestHelper.assert_true(fail_refused, "production refuses the denied type")

    # List path (Sidebar draws from the same gate).
    var sidebar: Control = SIDEBAR_SCRIPT.new() as Control
    var tabs: Array[Dictionary] = []
    tabs.append({"entity_types": [EntityData.EntityType.BUILDING]})
    sidebar._tabs = tabs
    sidebar._current_tab = 0
    sidebar.set("_tab_types", [])
    var listed: Array[EntityData] = sidebar._get_current_entities()
    sidebar.free()
    var listed_ids: Array = []
    for entry: EntityData in listed:
        listed_ids.append(entry.id)
    TestHelper.assert_true(PASS_ID in listed_ids, "gated-in type appears in the build list")
    TestHelper.assert_true(not (FAIL_ID in listed_ids), "denied type is absent from the list")

    _cleanup()
    PlayerManager.get_player_data(local_id).tech_level = previous_tech
