extends Node

# Map JSON scripting keys — load, round-trip, and absent-key handling.

const MAP_LOADER: GDScript = preload("res://scripts/maps/MapLoader.gd")

const PATH := "user://test_map_scripting.json"


func _write(data: Dictionary) -> void:
    var file := FileAccess.open(PATH, FileAccess.WRITE)
    file.store_string(JSON.stringify(data))
    file.close()


func _cleanup() -> void:
    if FileAccess.file_exists(PATH):
        DirAccess.remove_absolute(PATH)


func test_read_scripting_block() -> void:
    _write(
        {
            "version": 4,
            "triggers": [{"id": "t1"}],
            "waypoints": {"A": "70,51"},
            "variables": {"globals": ["FlagA"], "locals": ["LocalA"]},
        }
    )
    var scripting: Dictionary = MAP_LOADER.read_scripting(PATH)
    TestHelper.assert_eq((scripting["triggers"] as Array).size(), 1, "triggers read")
    TestHelper.assert_eq((scripting["waypoints"] as Dictionary).get("A"), "70,51", "waypoint read")
    var variables: Dictionary = scripting["variables"]
    TestHelper.assert_eq((variables["globals"] as Array)[0], "FlagA", "global name read")
    _cleanup()


func test_absent_keys_load_clean() -> void:
    _write({"version": 4})
    var scripting: Dictionary = MAP_LOADER.read_scripting(PATH)
    TestHelper.assert_true((scripting["triggers"] as Array).is_empty(), "no triggers")
    TestHelper.assert_true((scripting["waypoints"] as Dictionary).is_empty(), "no waypoints")
    TestHelper.assert_true((scripting["variables"] as Dictionary).is_empty(), "no variables")
    _cleanup()


func test_export_preserves_scripting_keys() -> void:
    (
        TerrainSystem
        . export_to_json(
            PATH,
            {
                "triggers": [{"id": "x"}],
                "waypoints": {"B": "1,2"},
                "variables": {"globals": ["G"], "locals": []},
            },
        )
    )
    var scripting: Dictionary = MAP_LOADER.read_scripting(PATH)
    TestHelper.assert_eq((scripting["triggers"] as Array).size(), 1, "triggers preserved")
    TestHelper.assert_eq(
        (scripting["waypoints"] as Dictionary).get("B"), "1,2", "waypoints preserved"
    )
    var variables: Dictionary = scripting["variables"]
    TestHelper.assert_eq((variables["globals"] as Array)[0], "G", "variables preserved")
    _cleanup()
