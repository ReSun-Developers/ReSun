extends Control

## OptionsView — the single reusable options overlay with Display, Graphics,
## Input, and Game sections. Opened by the boot selector, the pre-match main
## menu, and the in-match pause menu. Presentation only: it reads and writes
## through GraphicsSettings / InputSettings / GameSettings. Modal over a paused
## match (process_mode = ALWAYS) and consumes ESC to close.

signal closed(section: String)

const OptionsResume := preload("res://scripts/ui/OptionsResume.gd")

const SECTIONS: Array[String] = ["graphics", "display", "input", "game"]
const SECTION_TITLES: Dictionary = {
    "graphics": "Graphics",
    "display": "Display",
    "input": "Input",
    "game": "Game",
}
const CUSTOM_PRESET_LABEL: String = "Custom"

var _section: String = "graphics"
var _theme_def: GameDefinition = null
var _allow_restart: bool = true
var _panel: PanelContainer = null
var _preset_picker: OptionButton = null
var _content: VBoxContainer = null
var _section_buttons: Dictionary = {}
var _restart_button: Button = null
var _status: Label = null
var _capturing: Dictionary = {}
var _field_controls: Dictionary = {}
var _input_cells: Dictionary = {}
var _boot_restart_values: Dictionary = {}


## The control for a graphics/display field (for tests/inspection).
func field_control(field: String) -> Control:
    return _field_controls.get(field)


## The quality-preset picker (for tests/inspection).
func preset_control() -> OptionButton:
    return _preset_picker


## True when the Restart button is currently offered.
func restart_visible() -> bool:
    return _restart_button != null and _restart_button.visible


## The centered dialog panel (for tests/inspection).
func panel_control() -> PanelContainer:
    return _panel


## The table button for (game_id, action), or null for the base column.
func input_cell(game_id: String, action: String) -> Button:
    return _input_cells.get("%s:%s" % [game_id, action])


## Creates and mounts an options overlay on `host`.
static func open(
    host: Node,
    section: String = "graphics",
    theme_def: GameDefinition = null,
    allow_restart: bool = true
) -> Control:
    var view: Control = (load("res://scripts/ui/OptionsView.gd") as GDScript).new()
    view._section = section if SECTIONS.has(section) else "graphics"
    view._theme_def = theme_def
    view._allow_restart = allow_restart
    host.add_child(view)
    return view


func _ready() -> void:
    add_to_group("options_view")
    process_mode = Node.PROCESS_MODE_ALWAYS
    mouse_filter = Control.MOUSE_FILTER_STOP
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _capture_boot_restart_values()
    _build()
    _show_section(_section)


func current_section() -> String:
    return _section


## True when opened without a game theme (boot selector surface).
func is_neutral() -> bool:
    return _theme_def == null


func close() -> void:
    if not visible:
        return
    visible = false
    _capturing = {}
    closed.emit(_section)
    queue_free()


# --- UI construction --------------------------------------------------------


func _build() -> void:
    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.65)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(dim)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(center)

    _panel = PanelContainer.new()
    _panel.custom_minimum_size = Vector2(820, 0)
    _panel.add_theme_stylebox_override("panel", _panel_style())
    center.add_child(_panel)

    _add_panel_background()

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 20)
    margin.add_theme_constant_override("margin_top", 16)
    margin.add_theme_constant_override("margin_right", 20)
    margin.add_theme_constant_override("margin_bottom", 16)
    _panel.add_child(margin)

    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 12)
    margin.add_child(root)

    var title := Label.new()
    title.text = "Options"
    title.add_theme_font_size_override("font_size", 26)
    title.add_theme_color_override("font_color", _accent())
    root.add_child(title)

    var body := HBoxContainer.new()
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 16)
    root.add_child(body)

    var nav := VBoxContainer.new()
    nav.custom_minimum_size = Vector2(160, 0)
    body.add_child(nav)
    for section in SECTIONS:
        var button := Button.new()
        button.text = SECTION_TITLES[section]
        button.toggle_mode = true
        button.pressed.connect(_show_section.bind(section))
        nav.add_child(button)
        _section_buttons[section] = button

    var scroll := ScrollContainer.new()
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.custom_minimum_size = Vector2(600, 440)
    body.add_child(scroll)
    _content = VBoxContainer.new()
    _content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _content.add_theme_constant_override("separation", 8)
    scroll.add_child(_content)

    _status = Label.new()
    _status.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
    root.add_child(_status)

    var footer := HBoxContainer.new()
    footer.alignment = BoxContainer.ALIGNMENT_END
    footer.add_theme_constant_override("separation", 8)
    root.add_child(footer)

    _restart_button = Button.new()
    _restart_button.text = "Restart now"
    _restart_button.visible = false
    _restart_button.pressed.connect(_on_restart_pressed)
    footer.add_child(_restart_button)

    var close_button := Button.new()
    close_button.text = "Close"
    close_button.pressed.connect(close)
    footer.add_child(close_button)


## Themed backdrop texture behind the dialog (main-menu/pause surfaces only).
func _add_panel_background() -> void:
    if _theme_def == null or _theme_def.menu_background.is_empty():
        return
    var texture := load(_theme_def.menu_background) as Texture2D
    if texture == null:
        return
    var backdrop := TextureRect.new()
    backdrop.texture = texture
    backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    backdrop.modulate = Color(1, 1, 1, 0.35)
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _panel.add_child(backdrop)


func _panel_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.05, 0.06, 0.075, 0.96)
    style.border_color = _accent()
    style.set_border_width_all(1)
    style.set_corner_radius_all(4)
    style.content_margin_left = 12
    style.content_margin_right = 12
    style.content_margin_top = 12
    style.content_margin_bottom = 12
    return style


func _show_section(section: String) -> void:
    if not SECTIONS.has(section):
        return
    _section = section
    _preset_picker = null
    for key in _section_buttons:
        (_section_buttons[key] as Button).button_pressed = key == section
    for child in _content.get_children():
        child.queue_free()
    match section:
        "graphics":
            _build_graphics()
        "display":
            _build_display()
        "input":
            _build_input()
        "game":
            _build_game()


func _build_graphics() -> void:
    _field_controls.clear()
    var preset_row := _add_row("Quality preset")
    _preset_picker = OptionButton.new()
    _populate_preset_picker(_preset_picker)
    _preset_picker.tooltip_text = "Presets set every graphics option at once."
    _preset_picker.item_selected.connect(_on_preset_selected)
    preset_row.add_child(_preset_picker)

    for field in GraphicsSettings.schema():
        _add_field_row(field)


func _build_display() -> void:
    _field_controls.clear()
    for field in GraphicsSettings.display_schema():
        _add_field_row(field)


func _add_field_row(field: String) -> void:
    var info: Dictionary = GraphicsSettings.all_schema()[field]
    var label_text: String = String(info.get("label", String(field).capitalize()))
    var restart_only: bool = bool(info.get("restart_only", false))
    if restart_only:
        label_text = "%s (requires restart)" % label_text
    var row := _add_row(label_text)
    var label := row.get_child(0) as Label
    var description: String = String(info.get("description", ""))
    if not description.is_empty():
        label.tooltip_text = description

    var values: Variant = info.get("values")
    var is_bool_field: bool = (
        values is Array and not (values as Array).is_empty() and (values as Array)[0] is bool
    )
    if is_bool_field:
        var check := CheckButton.new()
        check.button_pressed = bool(GraphicsSettings.get_value(field))
        check.disabled = restart_only and not _allow_restart
        if not description.is_empty():
            check.tooltip_text = description
        check.toggled.connect(
            func(pressed: bool) -> void:
                GraphicsSettings.set_value(field, pressed)
                _sync_preset_picker()
                _refresh_restart()
        )
        row.add_child(check)
        _field_controls[field] = check
    elif values is Array:
        var options: Array = values
        var labels: Dictionary = info.get("option_labels", {})
        var picker := OptionButton.new()
        for i in options.size():
            picker.add_item(String(labels.get(str(options[i]), options[i])), i)
            if str(GraphicsSettings.get_value(field)) == str(options[i]):
                picker.select(i)
        picker.disabled = restart_only and not _allow_restart
        if not description.is_empty():
            picker.tooltip_text = description
        picker.item_selected.connect(
            func(index: int) -> void:
                GraphicsSettings.set_value(field, options[index])
                _sync_preset_picker()
                _refresh_restart()
        )
        row.add_child(picker)
        _field_controls[field] = picker
    elif values is String and values == "number":
        var spin := SpinBox.new()
        spin.min_value = float(info.get("min", 0.0))
        spin.max_value = float(info.get("max", 2.0))
        spin.step = float(info.get("step", 0.05))
        spin.value = float(GraphicsSettings.get_value(field))
        spin.editable = not (restart_only and not _allow_restart)
        if not description.is_empty():
            spin.tooltip_text = description
        spin.value_changed.connect(
            func(number: float) -> void:
                GraphicsSettings.set_value(field, number)
                _sync_preset_picker()
                _refresh_restart()
        )
        row.add_child(spin)
        _field_controls[field] = spin
    elif values is String and values == "resolutions":
        var resolutions: PackedStringArray = GraphicsSettings.resolution_options()
        var picker := OptionButton.new()
        for i in resolutions.size():
            picker.add_item(resolutions[i], i)
            if resolutions[i] == str(GraphicsSettings.get_value(field)):
                picker.select(i)
        picker.disabled = restart_only and not _allow_restart
        if not description.is_empty():
            picker.tooltip_text = description
        picker.item_selected.connect(
            func(index: int) -> void:
                GraphicsSettings.set_value(field, resolutions[index])
                _refresh_restart()
        )
        row.add_child(picker)
        _field_controls[field] = picker


func _build_input() -> void:
    _input_cells.clear()
    if not _capturing.is_empty():
        _set_status("Press a key for %s, ESC to cancel" % _capture_target_label())
    var grid := GridContainer.new()
    grid.columns = 2 + GameContext.list_games().size()
    grid.add_theme_constant_override("h_separation", 12)
    _content.add_child(grid)

    grid.add_child(_header("Action"))
    grid.add_child(_header("Base"))
    for def in GameContext.list_games():
        grid.add_child(_header(def.display_name if not def.display_name.is_empty() else def.id))

    for action in InputSettings.CAMERA_ACTIONS:
        grid.add_child(_header(String(action)))
        grid.add_child(_binding_button(action, "", null))
        for def in GameContext.list_games():
            grid.add_child(_binding_button(action, def.id, def))


func _binding_button(action: String, target: String, def: GameDefinition) -> Button:
    var button := Button.new()
    if target.is_empty():
        var base := InputSettings.get_base_binding(action)
        button.text = base if not base.is_empty() else InputSettings.get_key_text(action)
    else:
        var override := InputSettings.get_game_binding(action, target)
        button.text = override if not override.is_empty() else "(inherit)"
    if def != null and not def.supports_input(action):
        button.disabled = true
        button.tooltip_text = "Not supported by this game"
    else:
        button.pressed.connect(
            func() -> void:
                _capturing = {"action": action, "target": target}
                _show_section("input")
        )
    _input_cells["%s:%s" % [target, action]] = button
    return button


func _capture_target_label() -> String:
    if _capturing.is_empty():
        return ""
    var target: String = _capturing["target"]
    return "%s (%s)" % [_capturing["action"], target if not target.is_empty() else "base"]


func _build_game() -> void:
    for key in GameSettings.registry():
        var row := _add_row(String(key).capitalize())
        var check := CheckButton.new()
        check.button_pressed = bool(GameSettings.get_value(key))
        check.tooltip_text = String(GameSettings.registry()[key].get("description", ""))
        check.toggled.connect(func(pressed: bool) -> void: GameSettings.set_value(key, pressed))
        row.add_child(check)


func _add_row(label_text: String) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    var label := Label.new()
    label.text = label_text
    label.custom_minimum_size = Vector2(220, 0)
    row.add_child(label)
    _content.add_child(row)
    return row


func _header(text: String) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_color_override("font_color", _accent())
    return label


func _accent() -> Color:
    return _theme_def.menu_accent_color if _theme_def != null else Color.WHITE


# --- Preset picker ----------------------------------------------------------


func _populate_preset_picker(picker: OptionButton) -> void:
    picker.clear()
    var names: PackedStringArray = GraphicsSettings.preset_names()
    for i in names.size():
        picker.add_item(String(names[i]).capitalize(), i)
    picker.add_item(CUSTOM_PRESET_LABEL, names.size())
    _select_matching_preset(picker, names)


func _select_matching_preset(picker: OptionButton, names: PackedStringArray) -> void:
    var matched: String = GraphicsSettings.matching_preset()
    var index := names.find(matched)
    picker.select(index if index >= 0 else names.size())


## Re-selects Custom when the current values match no named preset.
func _sync_preset_picker() -> void:
    if _preset_picker != null:
        _select_matching_preset(_preset_picker, GraphicsSettings.preset_names())


func _on_preset_selected(index: int) -> void:
    var names: PackedStringArray = GraphicsSettings.preset_names()
    if index >= names.size():
        _select_matching_preset(_preset_picker, names)
        return
    GraphicsSettings.apply_preset(names[index])
    _show_section("graphics")
    _refresh_restart()


# --- Restart / input --------------------------------------------------------


func _capture_boot_restart_values() -> void:
    for field in GraphicsSettings.all_schema():
        if GraphicsSettings.is_restart_only(field):
            _boot_restart_values[field] = GraphicsSettings.get_value(field)


func _refresh_restart() -> void:
    var dirty := false
    for field in _boot_restart_values:
        if GraphicsSettings.get_value(field) != _boot_restart_values[field]:
            dirty = true
            break
    _restart_button.visible = _allow_restart and not _boot_restart_values.is_empty() and dirty


func _on_restart_pressed() -> void:
    _record_restart(_section)
    OS.set_restart_on_exit(true)
    get_tree().quit()


## Writes the one-shot resume marker (separated so tests can call it).
func _record_restart(section: String) -> void:
    OptionsResume.record(OptionsResume.CONFIG_PATH, section)


func _unhandled_input(event: InputEvent) -> void:
    if not visible:
        return
    if not _capturing.is_empty():
        if event is InputEventKey and event.pressed:
            if event.keycode == KEY_ESCAPE:
                _capturing = {}
                _set_status("")
            else:
                InputSettings.remap_action(
                    _capturing["action"], OS.get_keycode_string(event.keycode), _capturing["target"]
                )
                _capturing = {}
                _show_section("input")
            get_viewport().set_input_as_handled()
        return
    var key_event := event as InputEventKey
    var is_esc: bool = key_event != null and key_event.pressed and key_event.keycode == KEY_ESCAPE
    if event.is_action_pressed("pause") or is_esc:
        close()
        get_viewport().set_input_as_handled()


func _set_status(text: String) -> void:
    if _status != null:
        _status.text = text
