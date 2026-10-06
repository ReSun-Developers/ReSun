extends Node

# BootScreen tests — skip gate, occlusion, row building, pick/persist (with
# same-id guard), exit reachability, and the Options entry. The runner
# runs suites OUTSIDE the scene tree and injects autoloads as members (`_gc`,
# `_ef`), so nothing here relies on _ready, viewport, or absolute node paths.
# Global state is snapshotted and restored around every mutating test so
# suite order stays irrelevant. Persistence is redirected to a scratch file.
# ESC-quit is a one-line _quit() call — untestable headlessly without killing
# the runner; the Quit row's wiring is asserted instead.

const FIXTURES: String = "res://test/fixtures/gamectx"
const BOOT_SCENE: PackedScene = preload("res://scenes/ui/BootScreen.tscn")
const MENU_SCENE: PackedScene = preload("res://scenes/ui/MainMenu01.tscn")
const SCRATCH_CONFIG: String = "user://test_bootscreen_settings.cfg"

var _gc: Node = null
var _ef: Node = null

# --- helpers -----------------------------------------------------------------


func _make_def(id: String, display_name: String) -> GameDefinition:
    var def := GameDefinition.new()
    def.id = id
    def.display_name = display_name
    def.rules = load(FIXTURES + "/rules.tres") as GlobalRules
    def.data_sets.append(FIXTURES + "/game_a/")
    return def


func _redirect_config() -> String:
    var saved_path: String = _gc._config_path
    _gc._config_path = SCRATCH_CONFIG
    return saved_path


func _cleanup_config(saved_path: String) -> void:
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_CONFIG))
    _gc._config_path = saved_path


func _track_emissions() -> Array:
    var emitted: Array = []
    _gc.game_changed.connect(func(def: GameDefinition) -> void: emitted.append(def))
    return emitted


## Builds a boot screen with a MainMenu01 sibling under one parent. The menu
## is named MainMenu01 so BootScreen's sibling lookup finds it, mirroring
## MainScene's HUD/UI layout. Nothing in the pair enters the scene tree, so
## the boot gate is driven explicitly with synthetic args (empty = no-flag
## boot; pass flag args for the skip path).
func _build_pair(injected_defs: Array, flag_args: PackedStringArray = PackedStringArray()) -> Array:
    for def: GameDefinition in injected_defs:
        _gc._defs[def.id] = def
    var parent := Node.new()
    add_child(parent)
    var menu: Control = MENU_SCENE.instantiate()
    menu.name = "MainMenu01"
    parent.add_child(menu)
    var boot: Control = BOOT_SCENE.instantiate()
    parent.add_child(boot)
    boot._apply_gate(flag_args, PackedStringArray())
    return [boot, menu, parent]


func _game_rows(boot: Control) -> Array:
    var out: Array = []
    for button: Node in boot.get_node("%Rows").get_children():
        if button.has_meta("game_id"):
            out.append(button)
    return out


func _row_by_label(boot: Control, label: String) -> Node:
    for button: Node in boot.get_node("%Rows").get_children():
        if button.get("text") == label:
            return button
    return null


# --- skip gate (static, pure) ------------------------------------------------


func test_skip_gate_true_when_flag_present():
    TestHelper.assert_true(
        BootScreen.should_skip(PackedStringArray(["--game", "ts"])), "flag skips launcher"
    )
    TestHelper.assert_true(
        BootScreen.should_skip(PackedStringArray(["--headless", "--game", "ra2"])),
        "flag among other args skips"
    )


func test_skip_gate_false_when_flag_absent_or_valueless():
    TestHelper.assert_true(
        not BootScreen.should_skip(PackedStringArray([])), "no args shows launcher"
    )
    TestHelper.assert_true(
        not BootScreen.should_skip(PackedStringArray(["--other", "x"])),
        "unrelated args show launcher"
    )
    TestHelper.assert_true(
        not BootScreen.should_skip(PackedStringArray(["--game"])), "valueless flag shows launcher"
    )


# --- gate / occlusion --------------------------------------------------------


func test_boot_without_flag_shows_launcher_and_occludes_menu():
    TestHelper.assert_true(_gc != null, "GameContext injected by runner")
    if not _gc:
        return
    var pair := _build_pair([])
    var boot: Control = pair[0]
    var menu: Control = pair[1]
    TestHelper.assert_true(boot.visible, "launcher visible without flag")
    TestHelper.assert_true(not menu.visible, "main menu hidden while launcher visible")
    pair[2].free()


func test_gate_with_flag_hides_launcher_and_keeps_menu():
    var pair := _build_pair([], PackedStringArray(["--game", "ts"]))
    var boot: Control = pair[0]
    var menu: Control = pair[1]
    TestHelper.assert_true(not boot.visible, "launcher never visible under flag")
    TestHelper.assert_true(menu.visible, "main menu shown directly")
    pair[2].free()


# --- rows --------------------------------------------------------------------


func test_rows_match_listed_games_plus_options_and_quit():
    var snap := TestHelper.snapshot_game_context(_gc)
    var def_a := _make_def("fake_a", "Fake Alpha")
    var def_b := _make_def("fake_b", "")
    var pair := _build_pair([def_a, def_b])
    var boot: Control = pair[0]
    var games: Array = _gc.list_games()
    var rows := _game_rows(boot)
    TestHelper.assert_eq(rows.size(), games.size(), "one game row per listed game")
    var labels: Array = []
    for item: Node in rows:
        labels.append(item.get("text"))
    TestHelper.assert_true(labels.has("Fake Alpha"), "display_name used as row label")
    TestHelper.assert_true(labels.has("fake_b"), "empty display_name falls back to id")
    var options: Node = _row_by_label(boot, "Options")
    var quit: Node = _row_by_label(boot, "Quit")
    TestHelper.assert_true(options != null, "Options row present")
    TestHelper.assert_true(quit != null, "Quit row present")
    if options:
        TestHelper.assert_true(not options.get("disabled"), "Options row is enabled")
        TestHelper.assert_eq(
            options.get("pressed").get_connections().size(), 1, "Options wired to a handler"
        )
    if quit:
        TestHelper.assert_eq(quit.pressed.get_connections().size(), 1, "Quit wired to a handler")
    pair[2].free()
    TestHelper.restore_game_context(_gc, snap)


# --- pick / persist ----------------------------------------------------------


func test_pick_different_game_selects_persists_and_reveals_menu():
    var snap := TestHelper.snapshot_game_context(_gc)
    var saved_path := _redirect_config()
    var def_a := _make_def("fake_a", "Fake Alpha")
    var emitted := _track_emissions()
    var pair := _build_pair([def_a])
    var boot: Control = pair[0]
    var menu: Control = pair[1]
    boot._pick_game("fake_a")
    TestHelper.assert_eq(_gc.current.id, "fake_a", "picked game active")
    TestHelper.assert_eq(emitted.size(), 1, "game_changed emitted exactly once")
    TestHelper.assert_true(_ef.get_entity_data("A_UNIT") != null, "new game roster registered")
    var cfg := ConfigFile.new()
    TestHelper.assert_eq(cfg.load(SCRATCH_CONFIG), OK, "settings file loadable after pick")
    if cfg.load(SCRATCH_CONFIG) == OK:
        TestHelper.assert_eq(cfg.get_value("game", "id", ""), "fake_a", "choice persisted")
    TestHelper.assert_true(not boot.visible, "launcher dismissed after pick")
    TestHelper.assert_true(menu.visible, "main menu revealed after pick")
    pair[2].free()
    _cleanup_config(saved_path)
    TestHelper.restore_game_context(_gc, snap)


func test_pick_same_game_persists_without_reregister():
    var snap := TestHelper.snapshot_game_context(_gc)
    _gc.select_game("ts")
    var saved_path := _redirect_config()
    var emitted := _track_emissions()
    var roster_before: int = _ef._entity_cache.size()
    var pair := _build_pair([])
    var boot: Control = pair[0]
    boot._pick_game("ts")
    TestHelper.assert_eq(emitted.size(), 0, "no game_changed for the already-active game")
    TestHelper.assert_eq(
        _ef._entity_cache.size(), roster_before, "roster untouched (no re-register)"
    )
    var cfg := ConfigFile.new()
    if cfg.load(SCRATCH_CONFIG) == OK:
        TestHelper.assert_eq(cfg.get_value("game", "id", ""), "ts", "same-id choice persisted")
    pair[2].free()
    _cleanup_config(saved_path)
    TestHelper.restore_game_context(_gc, snap)


# --- exit paths --------------------------------------------------------------


func test_empty_list_still_offers_quit():
    var snap := TestHelper.snapshot_game_context(_gc)
    _gc._defs.clear()
    var pair := _build_pair([])
    var boot: Control = pair[0]
    TestHelper.assert_eq(_game_rows(boot).size(), 0, "no game rows when nothing discovered")
    var quit: Node = _row_by_label(boot, "Quit")
    TestHelper.assert_true(quit != null, "Quit row still present — exit always reachable")
    if quit:
        TestHelper.assert_true(not quit.get("disabled"), "Quit is enabled")
    pair[2].free()
    TestHelper.restore_game_context(_gc, snap)


# --- options placeholder -----------------------------------------------------


func test_options_row_opens_view():
    var snap := TestHelper.snapshot_game_context(_gc)
    var saved_path := _redirect_config()
    var pair := _build_pair([])
    var boot: Control = pair[0]
    var options: Node = _row_by_label(boot, "Options")
    TestHelper.assert_true(options != null, "Options row present")
    if options:
        TestHelper.assert_true(not options.get("disabled"), "Options row is enabled")
    var before := boot.get_child_count()
    boot._open_options()
    TestHelper.assert_eq(boot.get_child_count(), before + 1, "Options opens the options view")
    TestHelper.assert_eq(_gc.current.id, "ts", "active game unchanged")
    TestHelper.assert_eq(
        ConfigFile.new().load(SCRATCH_CONFIG), ERR_FILE_NOT_FOUND, "nothing persisted"
    )
    TestHelper.assert_true(boot.visible, "launcher remains visible")
    pair[2].free()
    _cleanup_config(saved_path)
    TestHelper.restore_game_context(_gc, snap)
