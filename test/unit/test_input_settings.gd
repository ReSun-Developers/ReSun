extends Node

# InputSettings unit tests — per-game config load/save, migration, remap_action.

const SCRATCH_CONFIG: String = "user://test_input_settings_scratch.cfg"

var _gc: Node


func _get_is() -> Node:
    var tree := Engine.get_main_loop() as SceneTree
    if not tree:
        return null
    return tree.root.get_node_or_null("InputSettings")


func _remove_scratch() -> void:
    if FileAccess.file_exists(SCRATCH_CONFIG):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_CONFIG))


## Redirects both persistence seams to the scratch file; returns the saved paths.
func _redirect(is_node: Node) -> Array:
    _remove_scratch()
    var saved := [is_node._config_path, _gc._config_path]
    is_node._config_path = SCRATCH_CONFIG
    _gc._config_path = SCRATCH_CONFIG
    return saved


func _restore(is_node: Node, saved: Array) -> void:
    is_node._config_path = saved[0]
    _gc._config_path = saved[1]
    _remove_scratch()
    is_node._apply_bindings()


func test_default_edge_scroll_enabled():
    var is_node := _get_is()
    if is_node == null:
        TestHelper.fail("InputSettings not injected")
        return
    var saved := _redirect(is_node)
    is_node._load()
    TestHelper.assert_eq(is_node.edge_scroll_enabled, true, "edge_scroll_enabled defaults to true")
    _restore(is_node, saved)


func test_remap_action_applies_binding():
    var is_node := _get_is()
    if is_node == null:
        TestHelper.fail("InputSettings not injected")
        return
    var saved := _redirect(is_node)
    is_node.remap_action("camera_up", "Kp 8")
    var events := InputMap.action_get_events("camera_up")
    var has_key := events.size() == 1 and events[0] is InputEventKey
    var applied := has_key and (events[0] as InputEventKey).physical_keycode == KEY_KP_8
    TestHelper.assert_true(applied, "remap_action applies Numpad8 binding")
    _restore(is_node, saved)


func test_remap_action_invalid_key():
    var is_node := _get_is()
    if is_node == null:
        TestHelper.fail("InputSettings not injected")
        return
    var saved := _redirect(is_node)
    var original_size := InputMap.action_get_events("camera_up").size()
    is_node.remap_action("camera_up", "NotARealKey")
    var rejected := InputMap.action_get_events("camera_up").size() == original_size
    TestHelper.assert_true(rejected, "remap_action rejects invalid key name")
    _restore(is_node, saved)


func test_get_key_text():
    var is_node := _get_is()
    if is_node == null:
        TestHelper.fail("InputSettings not injected")
        return
    var saved := _redirect(is_node)
    is_node.remap_action("camera_up", "W")
    var text: String = is_node.get_key_text("camera_up")
    TestHelper.assert_eq(text, "W", "get_key_text returns W")
    _restore(is_node, saved)


func test_remap_preserves_game_choice():
    var is_node := _get_is()
    if is_node == null:
        TestHelper.fail("InputSettings not injected")
        return
    var saved := _redirect(is_node)
    _gc.save_game_choice("ra2")
    is_node.remap_action("camera_up", "Kp 8")
    var cfg := ConfigFile.new()
    var loaded := cfg.load(SCRATCH_CONFIG)
    TestHelper.assert_eq(loaded, OK, "config saved")
    TestHelper.assert_eq(cfg.get_value("game", "id", ""), "ra2", "game choice preserved")
    TestHelper.assert_eq(
        cfg.get_value("input", "camera_up", ""), "Kp 8", "binding written to [input]"
    )
    _restore(is_node, saved)


func test_migrates_legacy_camera_and_keybinds():
    var is_node := _get_is()
    if is_node == null:
        TestHelper.fail("InputSettings not injected")
        return
    var saved := _redirect(is_node)
    var legacy := ConfigFile.new()
    legacy.set_value("camera", "edge_scroll_enabled", false)
    legacy.set_value("keybinds", "camera_up", "Numpad8")
    legacy.save(SCRATCH_CONFIG)
    is_node._load()
    TestHelper.assert_eq(is_node.edge_scroll_enabled, false, "legacy [camera] edge scroll read")
    TestHelper.assert_eq(
        is_node.resolve_key_name("camera_up"), "Numpad8", "legacy [keybinds] key read"
    )
    var migrated := ConfigFile.new()
    migrated.load(SCRATCH_CONFIG)
    TestHelper.assert_eq(
        migrated.get_value("input", "camera_up", ""), "Numpad8", "legacy key migrated to [input]"
    )
    _restore(is_node, saved)


func test_game_override_wins_and_reverts():
    var is_node := _get_is()
    if is_node == null:
        TestHelper.fail("InputSettings not injected")
        return
    var saved := _redirect(is_node)
    is_node.remap_action("camera_up", "W")
    is_node.remap_action("camera_up", "Kp 8", "ts")
    TestHelper.assert_eq(
        is_node.resolve_key_name("camera_up", "ts"), "Kp 8", "ts override wins over base"
    )
    TestHelper.assert_eq(
        is_node.resolve_key_name("camera_up", "ra2"), "W", "other game inherits base"
    )
    _restore(is_node, saved)
