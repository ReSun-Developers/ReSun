extends Node

# Trigger engine lifecycle across mission boots (arming, declarations, reset).

const MISSION_BOOT: GDScript = preload("res://scripts/maps/MissionBoot.gd")

const PATH := "user://test_trigger_mission.json"


func _write_fixture(trigger_id: String) -> void:
    var data := {
        "version": 4,
        "variables": {"globals": ["FlagA"], "locals": []},
        "waypoints": {"A": "5,5"},
        "triggers":
        [
            {
                "id": trigger_id,
                "owner": "GDI",
                "enabled": true,
                "tags": [{"id": "tag_%s" % trigger_id, "persistence": 2, "attach": "general"}],
                "events": [{"id": 27, "params": ["FlagA"]}],
                "actions": [{"id": 11, "params": ["hi"]}],
            }
        ],
    }
    var file := FileAccess.open(PATH, FileAccess.WRITE)
    file.store_string(JSON.stringify(data))
    file.close()


func _cleanup() -> void:
    if FileAccess.file_exists(PATH):
        DirAccess.remove_absolute(PATH)


func test_arm_on_mission_start() -> void:
    _write_fixture("t1")
    var mission := Mission.new()
    mission.map_path = PATH
    var boot: Node = MISSION_BOOT.new()
    boot._arm_scripting(mission)
    TestHelper.assert_true(TriggerEngine.is_armed(), "engine armed")
    TestHelper.assert_true(TriggerEngine.has_trigger("t1"), "mission trigger armed")
    TestHelper.assert_true(ScenarioState.has_global("FlagA"), "variables declared")
    TestHelper.assert_eq(ScenarioState.get_waypoint("A"), Vector2i(5, 5), "waypoints loaded")
    boot.free()
    _cleanup()


func test_new_match_clears_previous() -> void:
    var mission := Mission.new()
    mission.map_path = PATH
    var boot: Node = MISSION_BOOT.new()
    _write_fixture("t1")
    boot._arm_scripting(mission)
    _write_fixture("t2")
    boot._arm_scripting(mission)
    TestHelper.assert_true(TriggerEngine.has_trigger("t2"), "new trigger armed")
    TestHelper.assert_true(not TriggerEngine.has_trigger("t1"), "previous trigger cleared")
    boot.free()
    _cleanup()


## End-to-end: one occurrence cascades through a variable into a second trigger
## and a win action, all driven by the autoload engine armed from a map fixture.
func test_fixture_cascade_and_win() -> void:
    var data := {
        "version": 4,
        "variables": {"globals": ["FlagA"], "locals": []},
        "waypoints": {},
        "triggers":
        [
            {
                "id": "s",
                "owner": "GDI",
                "enabled": true,
                "tags": [{"id": "ts", "persistence": 2, "attach": "general"}],
                "events": [{"id": 7, "params": []}],
                "actions": [{"id": 28, "params": ["FlagA"]}],
            },
            {
                "id": "v",
                "owner": "GDI",
                "enabled": true,
                "tags": [{"id": "tv", "persistence": 2, "attach": "general"}],
                "events": [{"id": 27, "params": ["FlagA"]}],
                "actions": [{"id": 11, "params": ["flag"]}],
            },
            {
                "id": "w",
                "owner": "GDI",
                "enabled": true,
                "tags": [{"id": "tw", "persistence": 0, "attach": "general"}],
                "events": [{"id": 7, "params": []}],
                "actions": [{"id": 1, "params": ["GDI"]}],
            },
        ],
    }
    var file := FileAccess.open(PATH, FileAccess.WRITE)
    file.store_string(JSON.stringify(data))
    file.close()
    var mission := Mission.new()
    mission.map_path = PATH
    var boot: Node = MISSION_BOOT.new()
    boot._arm_scripting(mission)

    var texts: Array = []
    var won: Array = []
    var text_sink := func(text: String) -> void: texts.append(text)
    var win_sink := func(house: String) -> void: won.append(house)
    TriggerEngine.text_requested.connect(text_sink)
    TriggerEngine.mission_won.connect(win_sink)

    TriggerEngine.offer(7, {})
    TriggerEngine._on_tick(1)
    TriggerEngine._on_tick(2)

    TestHelper.assert_true(ScenarioState.get_global("FlagA"), "action set the global")
    TestHelper.assert_true(texts.has("flag"), "variable cascade fired the second trigger")
    TestHelper.assert_true(won.has("GDI"), "win action fired")

    TriggerEngine.text_requested.disconnect(text_sink)
    TriggerEngine.mission_won.disconnect(win_sink)
    TriggerEngine.reset()
    boot.free()
    _cleanup()
