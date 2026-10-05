extends Node

# GameSettings unit tests — per-game toggle isolation and defaults.

const SCRATCH_CONFIG: String = "user://test_game_settings_scratch.cfg"


func _get_gs() -> Node:
    var tree := Engine.get_main_loop() as SceneTree
    if not tree:
        return null
    return tree.root.get_node_or_null("GameSettings")


func _remove_scratch() -> void:
    if FileAccess.file_exists(SCRATCH_CONFIG):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_CONFIG))


func _redirect(gs: Node) -> String:
    _remove_scratch()
    var saved: String = gs._config_path
    gs._config_path = SCRATCH_CONFIG
    return saved


func _restore(gs: Node, saved: String) -> void:
    gs._config_path = saved
    _remove_scratch()
    gs._load("ts")


func test_registry_has_move_target_line_default_on():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GameSettings not injected")
        return
    TestHelper.assert_true(gs.registry().has("move_target_line"), "registry lists toggle")
    TestHelper.assert_eq(
        gs.registry()["move_target_line"]["default"], true, "move_target_line defaults on"
    )


func test_per_game_isolation_and_defaults():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GameSettings not injected")
        return
    var saved := _redirect(gs)
    gs._load("ts")
    gs.set_value("move_target_line", false)
    gs._load("ts")
    TestHelper.assert_eq(gs.get_value("move_target_line"), false, "ts value persisted")
    gs._load("ra2")
    TestHelper.assert_eq(gs.get_value("move_target_line"), true, "ra2 keeps its own default")
    _restore(gs, saved)


func test_toggle_survives_reload():
    var gs := _get_gs()
    if gs == null:
        TestHelper.fail("GameSettings not injected")
        return
    var saved := _redirect(gs)
    gs._load("ts")
    gs.set_value("move_target_line", false)
    gs._load("ts")
    TestHelper.assert_eq(gs.get_value("move_target_line"), false, "value survives reload")
    _restore(gs, saved)
