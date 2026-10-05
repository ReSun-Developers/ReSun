extends Node

# OptionsView + OptionsResume tests — sections, per-surface theming, modal ESC,
# restart-only gating, input table columns, and the one-shot resume marker.

const OptionsView := preload("res://scripts/ui/OptionsView.gd")
const OptionsResume := preload("res://scripts/ui/OptionsResume.gd")
const SCRATCH_CONFIG: String = "user://test_options_resume_scratch.cfg"
const SCRATCH_PRESET: String = "user://test_options_preset_scratch.cfg"

var _gc: Node = null


func _gs() -> Node:
    return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GraphicsSettings")


func _remove_scratch_preset() -> void:
    if FileAccess.file_exists(SCRATCH_PRESET):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_PRESET))


func _host() -> Control:
    var host := Control.new()
    (Engine.get_main_loop() as SceneTree).root.add_child(host)
    return host


func _dispose(host: Node) -> void:
    if is_instance_valid(host) and host.get_parent() != null:
        host.get_parent().remove_child(host)
    if is_instance_valid(host):
        host.free()


func _remove_scratch() -> void:
    if FileAccess.file_exists(SCRATCH_CONFIG):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_CONFIG))


func test_open_named_section_and_switch():
    var host := _host()
    var view = OptionsView.open(host, "input")
    TestHelper.assert_eq(view.current_section(), "input", "opens the requested section")
    var before = _gc.current
    view._show_section("graphics")
    TestHelper.assert_eq(view.current_section(), "graphics", "switches section")
    TestHelper.assert_true(view.field_control("aa") != null, "graphics controls built")
    TestHelper.assert_eq(_gc.current, before, "opening/switching changes no game")
    _dispose(host)


func test_theming_keyed_to_surface():
    var host := _host()
    var neutral = OptionsView.open(host, "graphics", null, true)
    TestHelper.assert_true(neutral.is_neutral(), "boot selector opens neutral")
    var themed = OptionsView.open(host, "graphics", _gc.current, true)
    TestHelper.assert_true(not themed.is_neutral(), "menu/pause opens themed")
    _dispose(host)


func test_pause_modal_esc_closes_without_resume():
    var host := _host()
    var tree := Engine.get_main_loop() as SceneTree
    tree.paused = true
    var view = OptionsView.open(host, "graphics", _gc.current, false)
    var fired := [false]
    view.closed.connect(func(_section: String) -> void: fired[0] = true)
    var esc := InputEventKey.new()
    esc.keycode = KEY_ESCAPE
    esc.pressed = true
    view._unhandled_input(esc)
    TestHelper.assert_true(fired[0], "ESC closes the options view")
    TestHelper.assert_true(tree.paused, "match stays paused after ESC")
    tree.paused = false
    _dispose(host)


func test_restart_only_gated_by_surface():
    var host := _host()
    var pause_view = OptionsView.open(host, "graphics", _gc.current, false)
    var tex = pause_view.field_control("texture_quality")
    TestHelper.assert_true(tex != null, "texture quality control exists")
    TestHelper.assert_true(tex.disabled, "restart-only disabled from the pause menu")
    var menu_view = OptionsView.open(host, "graphics", _gc.current, true)
    TestHelper.assert_true(
        not menu_view.field_control("texture_quality").disabled, "enabled from the menu"
    )
    _dispose(host)


func test_input_table_has_a_column_per_game():
    var host := _host()
    var view = OptionsView.open(host, "input", _gc.current, true)
    var games = _gc.list_games()
    TestHelper.assert_true(games.size() >= 1, "at least one game discovered")
    for action in ["camera_up", "camera_down", "camera_left", "camera_right"]:
        TestHelper.assert_true(
            view.input_cell(games[0].id, action) != null, "cell exists for %s" % action
        )
    _dispose(host)


func test_restart_marker_record_and_consume():
    _remove_scratch()
    OptionsResume.record(SCRATCH_CONFIG, "input")
    TestHelper.assert_eq(OptionsResume.consume(SCRATCH_CONFIG), "input", "resumes section")
    TestHelper.assert_eq(OptionsResume.consume(SCRATCH_CONFIG), "", "marker is one-shot")
    _remove_scratch()


func test_display_section_has_window_and_resolution_controls():
    var host := _host()
    var view = OptionsView.open(host, "display")
    TestHelper.assert_eq(view.current_section(), "display", "opens the display section")
    TestHelper.assert_true(view.field_control("window_mode") != null, "window mode control")
    TestHelper.assert_true(view.field_control("resolution") != null, "resolution control")
    _dispose(host)


func test_graphics_section_exposes_every_field_control():
    var host := _host()
    var gs := _gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    var view = OptionsView.open(host, "graphics")
    for field: String in gs.schema():
        TestHelper.assert_true(view.field_control(field) != null, "control for %s" % field)
    TestHelper.assert_true(view.field_control("exposure") != null, "exposure is editable")
    _dispose(host)


func test_panel_is_centered():
    var host := _host()
    var view = OptionsView.open(host, "graphics")
    var panel: PanelContainer = view.panel_control()
    TestHelper.assert_true(panel != null, "panel exists")
    var parent := panel.get_parent()
    TestHelper.assert_true(parent is CenterContainer, "panel is centered by a CenterContainer")
    var center := parent as CenterContainer
    TestHelper.assert_true(
        is_equal_approx(center.anchor_right, 1.0) and is_equal_approx(center.anchor_bottom, 1.0),
        "center container fills the view"
    )
    _dispose(host)


func test_preset_picker_reflects_choice_and_custom():
    var host := _host()
    var gs := _gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    var saved: String = gs._config_path
    _remove_scratch_preset()
    gs._config_path = SCRATCH_PRESET
    gs._load()
    var view = OptionsView.open(host, "graphics")
    var picker: OptionButton = view.preset_control()
    TestHelper.assert_eq(
        picker.get_item_text(picker.item_count - 1), "Custom", "Custom item is offered"
    )
    var high_index: int = gs.preset_names().find("high")
    picker.item_selected.emit(high_index)
    var aa_control: OptionButton = view.field_control("aa")
    TestHelper.assert_eq(
        aa_control.get_item_text(aa_control.selected), "SMAA", "aa widget reflects the High preset"
    )
    var gi_control: OptionButton = view.field_control("gi")
    gi_control.item_selected.emit(0)
    var current: OptionButton = view.preset_control()
    TestHelper.assert_eq(
        current.get_item_text(current.selected), "Custom", "divergence shows Custom"
    )
    gs._config_path = saved
    _remove_scratch_preset()
    gs._load()
    _dispose(host)


func test_restart_offered_after_restart_only_change():
    var host := _host()
    var gs := _gs()
    if gs == null:
        TestHelper.fail("GraphicsSettings not injected")
        return
    var saved: String = gs._config_path
    _remove_scratch_preset()
    gs._config_path = SCRATCH_PRESET
    var view = OptionsView.open(host, "graphics", _gc.current, true)
    TestHelper.assert_true(not view.restart_visible(), "no restart offered before a change")
    var tex: OptionButton = view.field_control("texture_quality")
    var target: int = 1 if tex.selected != 1 else 2
    tex.item_selected.emit(target)
    TestHelper.assert_true(view.restart_visible(), "restart offered after a restart-only change")
    gs._config_path = saved
    _remove_scratch_preset()
    gs._load()
    _dispose(host)
