extends Node

# EntityData resource field tests — sound_die default and round-trip.


func test_sound_die_default_and_round_trip():
    var data := EntityData.new()
    TestHelper.assert_eq(data.sound_die, "", "sound_die defaults empty")
    data.sound_die = "EXPNEW01,EXPNEW05"
    TestHelper.assert_eq(data.sound_die, "EXPNEW01,EXPNEW05", "sound_die round-trips comma list")


func test_sound_die_independent_of_voice_data():
    var data := EntityData.new()
    data.sound_die = "EXPNEW01"
    TestHelper.assert_true(data.voice_data == null, "sound_die does not require a voice set")


func test_selectability_defaults_to_true():
    var data := EntityData.new()
    TestHelper.assert_eq(data.get("is_selectable"), true, "is_selectable defaults true")
    TestHelper.assert_eq(data.get("is_drag_selectable"), true, "is_drag_selectable defaults true")


func test_selectability_opt_out_round_trips():
    var data := EntityData.new()
    data.set("is_selectable", false)
    var path := "user://test_entity_data_selectability.tres"
    var err := ResourceSaver.save(data, path)
    var loaded := load(path) as EntityData
    if FileAccess.file_exists(path):
        DirAccess.open("user://").remove("test_entity_data_selectability.tres")
    var result: bool = err == OK and loaded != null and loaded.get("is_selectable") == false
    TestHelper.assert_true(result, "is_selectable = false survives a resource save/load")
