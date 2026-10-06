extends Node

# UserConfig unit tests — load-modify-save must preserve sibling sections.

const UserConfig := preload("res://scripts/core/UserConfig.gd")

const SCRATCH_CONFIG: String = "user://test_user_config_scratch.cfg"


func _remove_scratch() -> void:
    if FileAccess.file_exists(SCRATCH_CONFIG):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_CONFIG))


func test_set_value_preserves_other_sections():
    _remove_scratch()
    UserConfig.set_value(SCRATCH_CONFIG, "graphics", "preset", "high")
    UserConfig.set_value(SCRATCH_CONFIG, "game", "id", "ra2")
    UserConfig.set_value(SCRATCH_CONFIG, "input", "camera_up", "Numpad8")

    var cfg := UserConfig.read(SCRATCH_CONFIG)
    TestHelper.assert_eq(cfg.get_value("graphics", "preset", ""), "high", "graphics kept")
    TestHelper.assert_eq(cfg.get_value("game", "id", ""), "ra2", "game kept")
    TestHelper.assert_eq(cfg.get_value("input", "camera_up", ""), "Numpad8", "input kept")
    _remove_scratch()


func test_get_value_default_and_set_sections():
    _remove_scratch()
    TestHelper.assert_eq(
        UserConfig.get_value(SCRATCH_CONFIG, "missing", "key", 7), 7, "absent returns default"
    )
    UserConfig.set_sections(
        SCRATCH_CONFIG, {"graphics": {"preset": "low", "gi": "off"}, "ui": {"restart": "input"}}
    )
    var cfg := UserConfig.read(SCRATCH_CONFIG)
    TestHelper.assert_eq(cfg.get_value("graphics", "gi", ""), "off", "nested section written")
    TestHelper.assert_eq(cfg.get_value("ui", "restart", ""), "input", "second section written")
    _remove_scratch()
