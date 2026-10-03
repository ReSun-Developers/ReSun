@tool
extends Node3D

enum Tool {
    NONE,
    PAINT_HEIGHT,
    PAINT_RESOURCE,
    PLACE_TREE,
    ERASE,
    PLACE_ENTITY,
    PLAYER_START,
    CELL_TAG,
}

@export var map_size: Vector2 = Vector2(50.0, 50.0)
@export var show_grid: bool = true

var _hovered_cell: Vector2i = Vector2i(-999, -999)
var _camera: Camera3D
var _camera_pivot: Node3D
var _height_painter: Node
var _tool_buttons: Dictionary = {}
var _active_tool: int = Tool.NONE
var _painted_entities: Dictionary = {}

var _grid: Node
var _entity_placer: Node
var _resource_painter: Node
var _save_load: Node
var _entity_selector: Node
var _entity_properties: Node
var _settings_popup: PopupMenu
var _player_start_tool: Node
var _cell_tag_tool: Node
var _selected_start_player: int = 0
var _player_count: int = 2


func _ready() -> void:
    if Engine.is_editor_hint():
        return
    set_meta("is_map_editor", true)
    _setup_camera()
    TerrainSystem.init_grid(ceili(map_size.x), ceili(map_size.y))
    BoundsSystem.camera_pivot = _camera_pivot
    BoundsSystem._center_camera_on_diamond()
    _setup_grid()
    _setup_height_painter()
    _height_painter.height_changed.connect(_on_height_changed)
    TerrainSystem.cell_changed.connect(_on_terrain_cell_changed)
    _prefill_terrain()
    _setup_ui()
    # Pre-warm BatchLoader with all entity models for the editor.
    var all_model_paths: PackedStringArray = []
    for data in EntityFactory._entity_cache.values():
        if data.art_data and not data.art_data.model_path.is_empty():
            var mp: String = data.art_data.model_path
            if mp not in all_model_paths:
                all_model_paths.append(mp)
    if not all_model_paths.is_empty():
        BatchLoader.preload_batch(all_model_paths)


func _exit_tree() -> void:
    if Engine.is_editor_hint():
        return
    _entity_placer.cleanup()
    _entity_selector.cleanup()
    _player_start_tool.cleanup()
    if _cell_tag_tool and is_instance_valid(_cell_tag_tool):
        _cell_tag_tool.cleanup()
    _painted_entities.clear()
    TerrainSystem.clear()
    var renderer := get_node_or_null("TerrainRenderer")
    if renderer and renderer.has_method("clear_all"):
        renderer.clear_all()


func _process(_delta: float) -> void:
    if Engine.is_editor_hint():
        return
    _update_hovered_cell()
    _grid.update()


func _input(event: InputEvent) -> void:
    if Engine.is_editor_hint() or _camera == null:
        return
    if get_viewport().gui_get_hovered_control() != null:
        return

    if _active_tool == Tool.PAINT_HEIGHT:
        return
    elif _active_tool == Tool.NONE:
        _entity_selector.handle_input(event)
    elif _active_tool == Tool.PLAYER_START:
        _handle_player_start_input(event)
    elif _active_tool == Tool.CELL_TAG:
        _handle_cell_tag_input(event)
    elif _active_tool == Tool.PLACE_TREE:
        _entity_placer.handle_tree_input(event)
    elif _active_tool == Tool.PLACE_ENTITY:
        _entity_placer.handle_input(event)
    elif _active_tool in [Tool.PAINT_RESOURCE, Tool.ERASE]:
        _resource_painter.handle_input(event)


func _handle_player_start_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton or not event.pressed:
        return
    var cell := _hovered_cell
    if event.button_index == MOUSE_BUTTON_LEFT:
        if not CellUtil.is_in_diamond(cell, TerrainSystem.grid_cells):
            push_warning("PlayerStartTool: start placement outside map diamond ignored")
            return
        _player_start_tool.assign(_selected_start_player, cell)
    elif event.button_index == MOUSE_BUTTON_RIGHT:
        if _player_start_tool.has_override(_selected_start_player):
            var assigned: Vector2i = _player_start_tool.effective_cell(_selected_start_player)
            if assigned == cell:
                _player_start_tool.reset(_selected_start_player)


func _handle_cell_tag_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton or not event.pressed:
        return
    if event.button_index == MOUSE_BUTTON_LEFT:
        _cell_tag_tool.assign(_hovered_cell)
    elif event.button_index == MOUSE_BUTTON_RIGHT:
        _cell_tag_tool.clear_at(_hovered_cell)


func _setup_camera() -> void:
    var camera_scene := preload("res://scenes/hud/Camera01.tscn")
    var camera_instance := camera_scene.instantiate()
    add_child(camera_instance)
    _camera = camera_instance.get_node("Camera3D")
    _camera_pivot = camera_instance
    BoundsSystem.show_bounds = true


func _setup_grid() -> void:
    _grid = preload("res://scripts/editor/EditorGrid.gd").new()
    _grid.name = "EditorGrid"
    _grid.editor = self
    add_child(_grid)
    _grid.setup()


func _setup_height_painter() -> void:
    _height_painter = preload("res://scripts/editor/HeightPainter.gd").new()
    _height_painter.name = "HeightPainter"
    _height_painter.editor = self
    add_child(_height_painter)


func _prefill_terrain() -> void:
    var extent: Vector2i = CellUtil.get_diamond_extent(TerrainSystem.grid_cells)
    var cells_x: int = extent.x
    var cells_z: int = extent.y
    for x in range(cells_x):
        for z in range(cells_z):
            var cell := Vector2i(x, z)
            if not CellUtil.is_in_diamond(cell, TerrainSystem.grid_cells):
                continue
            if TerrainSystem.get_cell(cell).is_empty():
                TerrainSystem.compute_and_emit_cell(cell)


func _clear_terrain_renderer() -> void:
    var renderer := get_node_or_null("TerrainRenderer")
    if renderer and renderer.has_method("clear_all"):
        renderer.clear_all()


func _setup_ui() -> void:
    var ui := CanvasLayer.new()
    ui.name = "EditorUI"
    add_child(ui)

    var tool_bar := HBoxContainer.new()
    tool_bar.name = "ToolBar"
    tool_bar.position = Vector2(10, 10)
    ui.add_child(tool_bar)

    _save_load = preload("res://scripts/editor/EditorSaveLoad.gd").new()
    _save_load.name = "EditorSaveLoad"
    _save_load.editor = self
    add_child(_save_load)
    _save_load.setup(ui)

    # File menu
    var file_menu_btn := MenuButton.new()
    file_menu_btn.text = "File"
    var file_popup: PopupMenu = file_menu_btn.get_popup()
    file_popup.add_item("New", 0)
    file_popup.add_item("Load", 1)
    file_popup.add_item("Save", 2)
    file_popup.id_pressed.connect(_on_file_menu_pressed)
    tool_bar.add_child(file_menu_btn)

    # Settings menu
    var settings_menu_btn := MenuButton.new()
    settings_menu_btn.text = "Settings"
    _settings_popup = settings_menu_btn.get_popup()
    _settings_popup.add_item("Map Settings", 0)
    _settings_popup.add_check_item("Show Grid", 1)
    _settings_popup.set_item_checked(1, false)
    _settings_popup.id_pressed.connect(_on_settings_menu_pressed)
    tool_bar.add_child(settings_menu_btn)

    var sep1 := VSeparator.new()
    tool_bar.add_child(sep1)

    var tools := [
        {"name": "Paint Height", "tool": Tool.PAINT_HEIGHT},
        {"name": "Paint Resource", "tool": Tool.PAINT_RESOURCE},
        {"name": "Place Tree", "tool": Tool.PLACE_TREE},
        {"name": "Set Player Start", "tool": Tool.PLAYER_START},
        {"name": "Cell Tags", "tool": Tool.CELL_TAG},
        {"name": "Erase", "tool": Tool.ERASE},
    ]
    for t in tools:
        var btn := Button.new()
        btn.text = t.name
        btn.toggle_mode = true
        var tool_id: int = t.tool
        btn.pressed.connect(_on_tool_toggled.bind(btn, tool_id))
        _tool_buttons[tool_id] = btn
        tool_bar.add_child(btn)

    var sep2 := VSeparator.new()
    tool_bar.add_child(sep2)

    var player_label := Label.new()
    player_label.text = "Player:"
    tool_bar.add_child(player_label)
    var player_spin := SpinBox.new()
    player_spin.name = "PlayerSpinBox"
    player_spin.min_value = 1.0
    player_spin.max_value = 8.0
    player_spin.step = 1.0
    player_spin.value = 1.0
    player_spin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    player_spin.custom_minimum_size = Vector2(60, 0)
    player_spin.value_changed.connect(func(v: float) -> void: _selected_start_player = int(v) - 1)
    tool_bar.add_child(player_spin)

    var tag_label := Label.new()
    tag_label.text = "Tag:"
    tool_bar.add_child(tag_label)
    var tag_edit := LineEdit.new()
    tag_edit.name = "CellTagLineEdit"
    tag_edit.placeholder_text = "tag id"
    tag_edit.custom_minimum_size = Vector2(90, 0)
    tag_edit.text_changed.connect(func(text: String) -> void: _cell_tag_tool.set_tag_id(text))
    tool_bar.add_child(tag_edit)

    _player_start_tool = preload("res://scripts/editor/PlayerStartTool.gd").new()
    _player_start_tool.name = "PlayerStartTool"
    add_child(_player_start_tool)
    _player_start_tool.setup(self)
    _player_start_tool.set_player_count(_player_count)

    _cell_tag_tool = preload("res://scripts/editor/CellTagTool.gd").new()
    _cell_tag_tool.name = "CellTagTool"
    add_child(_cell_tag_tool)
    _cell_tag_tool.setup(self)

    _resource_painter = preload("res://scripts/editor/ResourcePainter.gd").new()
    _resource_painter.name = "ResourcePainter"
    _resource_painter.editor = self
    add_child(_resource_painter)

    var str_label := Label.new()
    str_label.text = "Strength:"
    tool_bar.add_child(str_label)
    var str_slider := HSlider.new()
    str_slider.name = "StrengthSlider"
    str_slider.min_value = 0.0
    str_slider.max_value = 100.0
    str_slider.value = _resource_painter._paint_strength
    str_slider.step = 1.0
    str_slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    str_slider.custom_minimum_size = Vector2(100, 0)
    str_slider.value_changed.connect(_resource_painter.set_strength)
    tool_bar.add_child(str_slider)

    var rad_label := Label.new()
    rad_label.text = "Radius:"
    tool_bar.add_child(rad_label)
    var rad_spin := SpinBox.new()
    rad_spin.name = "RadiusSpinBox"
    rad_spin.min_value = 1.0
    rad_spin.max_value = 20.0
    rad_spin.value = _resource_painter._paint_radius
    rad_spin.value_changed.connect(_resource_painter.set_radius)
    tool_bar.add_child(rad_spin)

    var sep3 := VSeparator.new()
    tool_bar.add_child(sep3)

    var h_label := Label.new()
    h_label.text = "Height: 0"
    _grid._height_label = h_label
    tool_bar.add_child(h_label)

    # Grid defaults to off
    _grid.set_grid_visible(false)

    var minimap_script = load("res://scripts/editor/Minimap.gd")
    if minimap_script:
        var minimap: SubViewportContainer = minimap_script.new()
        minimap.name = "Minimap"
        minimap.position = Vector2(get_viewport().size.x - 210, 10)
        ui.add_child(minimap)
        minimap.set_game_camera(_camera, _camera_pivot)

    _entity_placer = preload("res://scripts/editor/EntityPlacer.gd").new()
    _entity_placer.name = "EntityPlacer"
    _entity_placer.editor = self
    add_child(_entity_placer)
    _entity_placer.setup(ui)

    _entity_selector = preload("res://scripts/editor/EntitySelector.gd").new()
    _entity_selector.name = "EntitySelector"
    _entity_selector.editor = self
    add_child(_entity_selector)
    _entity_selector.setup(_camera, ui)
    _entity_selector.selection_changed.connect(_on_editor_selection_changed)

    _entity_properties = preload("res://scripts/editor/EntityProperties.gd").new()
    _entity_properties.name = "EntityProperties"
    _entity_properties.position = Vector2(get_viewport().size.x - 230, 220)
    ui.add_child(_entity_properties)
    _entity_properties.setup(_entity_selector)


func _on_file_menu_pressed(id: int) -> void:
    match id:
        0:
            _show_new_map_dialog()
        1:
            _save_load.on_load_pressed()
        2:
            _save_load.on_save_pressed()


func _on_settings_menu_pressed(id: int) -> void:
    match id:
        0:
            _show_map_settings_dialog()
        1:
            var checked: bool = _settings_popup.is_item_checked(1)
            _settings_popup.set_item_checked(1, not checked)
            _grid.set_grid_visible(not checked)


# ========================================
# New Map Dialog
# ========================================


func _show_new_map_dialog() -> void:
    var dialog := PopupPanel.new()
    dialog.name = "NewMapDialog"
    dialog.title = "New Map"
    dialog.size = Vector2i(400, 680)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 8)
    dialog.add_child(vbox)

    var name_label := Label.new()
    name_label.text = "Map Name:"
    vbox.add_child(name_label)
    var name_edit := LineEdit.new()
    name_edit.text = "Untitled"
    name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(name_edit)

    var width_label := Label.new()
    width_label.text = "Width (X):"
    vbox.add_child(width_label)
    var width_spin := SpinBox.new()
    width_spin.min_value = 20.0
    width_spin.max_value = 512.0
    width_spin.step = 1.0
    width_spin.value = 50.0
    width_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(width_spin)

    var height_label := Label.new()
    height_label.text = "Height (Z):"
    vbox.add_child(height_label)
    var height_spin := SpinBox.new()
    height_spin.min_value = 20.0
    height_spin.max_value = 512.0
    height_spin.step = 1.0
    height_spin.value = 50.0
    height_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(height_spin)

    var start_h_label := Label.new()
    start_h_label.text = "Starting Height:"
    vbox.add_child(start_h_label)
    var start_h_spin := SpinBox.new()
    start_h_spin.min_value = 0.0
    start_h_spin.max_value = 12.0
    start_h_spin.step = 4.0
    start_h_spin.value = 0.0
    start_h_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(start_h_spin)

    var players_label := Label.new()
    players_label.text = "Player Count:"
    vbox.add_child(players_label)
    var players_spin := SpinBox.new()
    players_spin.min_value = 2.0
    players_spin.max_value = 8.0
    players_spin.step = 1.0
    players_spin.value = 2.0
    players_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(players_spin)

    var left_label := Label.new()
    left_label.text = "Left Inset:"
    vbox.add_child(left_label)
    var left_spin := SpinBox.new()
    left_spin.min_value = 0.0
    left_spin.step = 1.0
    left_spin.value = 5.0
    left_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(left_spin)

    var right_label := Label.new()
    right_label.text = "Right Inset:"
    vbox.add_child(right_label)
    var right_spin := SpinBox.new()
    right_spin.min_value = 0.0
    right_spin.step = 1.0
    right_spin.value = 5.0
    right_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(right_spin)

    var top_label := Label.new()
    top_label.text = "Top Inset:"
    vbox.add_child(top_label)
    var top_spin := SpinBox.new()
    top_spin.min_value = 0.0
    top_spin.step = 1.0
    top_spin.value = 4.0
    top_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(top_spin)

    var bottom_label := Label.new()
    bottom_label.text = "Bottom Inset:"
    vbox.add_child(bottom_label)
    var bottom_spin := SpinBox.new()
    bottom_spin.min_value = 0.0
    bottom_spin.step = 1.0
    bottom_spin.value = 4.0
    bottom_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(bottom_spin)

    var bounds_label := Label.new()
    vbox.add_child(bounds_label)

    var update_bounds := func() -> void:
        var w: int = int(width_spin.value)
        var h: int = int(height_spin.value)
        var l: int = int(left_spin.value)
        var r: int = int(right_spin.value)
        var t: int = int(top_spin.value)
        var b: int = int(bottom_spin.value)
        left_spin.max_value = maxf(2.0 * w - r - 1.0, 0.0)
        right_spin.max_value = maxf(2.0 * w - l - 1.0, 0.0)
        top_spin.max_value = maxf(2.0 * h - b - 1.0, 0.0)
        bottom_spin.max_value = maxf(2.0 * h - t - 1.0, 0.0)
        left_spin.value = minf(left_spin.value, left_spin.max_value)
        right_spin.value = minf(right_spin.value, right_spin.max_value)
        top_spin.value = minf(top_spin.value, top_spin.max_value)
        bottom_spin.value = minf(bottom_spin.value, bottom_spin.max_value)
        var vw: int = maxi(w - l - r, 1)
        var vh: int = maxi(h - t - b, 1)
        bounds_label.text = "Visible Bounds: %d × %d" % [vw, vh]

    width_spin.value_changed.connect(func(_v: float) -> void: update_bounds.call())
    height_spin.value_changed.connect(func(_v: float) -> void: update_bounds.call())
    left_spin.value_changed.connect(func(_v: float) -> void: update_bounds.call())
    right_spin.value_changed.connect(func(_v: float) -> void: update_bounds.call())
    top_spin.value_changed.connect(func(_v: float) -> void: update_bounds.call())
    bottom_spin.value_changed.connect(func(_v: float) -> void: update_bounds.call())
    update_bounds.call()

    var btn_row := HBoxContainer.new()
    btn_row.alignment = BoxContainer.ALIGNMENT_END
    btn_row.add_theme_constant_override("separation", 8)
    vbox.add_child(btn_row)

    var cancel_btn := Button.new()
    cancel_btn.text = "Cancel"
    cancel_btn.pressed.connect(func() -> void: dialog.queue_free())
    btn_row.add_child(cancel_btn)

    var create_btn := Button.new()
    create_btn.text = "Create"
    create_btn.pressed.connect(
        func() -> void:
            var w: int = int(width_spin.value)
            var h: int = int(height_spin.value)
            var start_h: int = int(start_h_spin.value)
            var players: int = int(players_spin.value)
            var l: int = int(left_spin.value)
            var r: int = int(right_spin.value)
            var t: int = int(top_spin.value)
            var b: int = int(bottom_spin.value)
            _apply_new_map(w, h, start_h, players, l, r, t, b)
            dialog.queue_free()
    )
    btn_row.add_child(create_btn)

    get_node("EditorUI").add_child(dialog)
    dialog.popup_centered(Vector2i(400, 680))


func _apply_new_map(
    width: int,
    height: int,
    _start_height: int,
    player_count: int,
    left: int = 5,
    right: int = 5,
    top: int = 4,
    bottom: int = 4
) -> void:
    _clear_terrain_renderer()
    TerrainSystem.clear()
    TerrainSystem.init_grid(width, height)
    BoundsSystem.left_inset = left
    BoundsSystem.right_inset = right
    BoundsSystem.top_inset = top
    BoundsSystem.bottom_inset = bottom
    _prefill_terrain()
    _grid._draw_grid()
    _player_count = maxi(player_count, 1)
    _player_start_tool.set_player_count(_player_count)
    _player_start_tool.clear()


# ========================================
# Map Settings Dialog
# ========================================


func _show_map_settings_dialog() -> void:
    var dialog := PopupPanel.new()
    dialog.name = "MapSettingsDialog"
    dialog.title = "Map Settings"
    dialog.size = Vector2i(400, 620)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 8)
    dialog.add_child(vbox)

    var width_label := Label.new()
    width_label.text = "Width (X):"
    vbox.add_child(width_label)
    var width_spin := SpinBox.new()
    width_spin.min_value = 20.0
    width_spin.max_value = 512.0
    width_spin.step = 1.0
    width_spin.value = float(TerrainSystem.grid_cells.x)
    width_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(width_spin)

    var height_label := Label.new()
    height_label.text = "Height (Z):"
    vbox.add_child(height_label)
    var height_spin := SpinBox.new()
    height_spin.min_value = 20.0
    height_spin.max_value = 512.0
    height_spin.step = 1.0
    height_spin.value = float(TerrainSystem.grid_cells.y)
    height_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(height_spin)

    var left_label := Label.new()
    left_label.text = "Left Inset:"
    vbox.add_child(left_label)
    var left_spin := SpinBox.new()
    left_spin.min_value = 0.0
    left_spin.step = 1.0
    left_spin.value = float(BoundsSystem.left_inset)
    left_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(left_spin)

    var right_label := Label.new()
    right_label.text = "Right Inset:"
    vbox.add_child(right_label)
    var right_spin := SpinBox.new()
    right_spin.min_value = 0.0
    right_spin.step = 1.0
    right_spin.value = float(BoundsSystem.right_inset)
    right_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(right_spin)

    var top_label := Label.new()
    top_label.text = "Top Inset:"
    vbox.add_child(top_label)
    var top_spin := SpinBox.new()
    top_spin.min_value = 0.0
    top_spin.step = 1.0
    top_spin.value = float(BoundsSystem.top_inset)
    top_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(top_spin)

    var bottom_label := Label.new()
    bottom_label.text = "Bottom Inset:"
    vbox.add_child(bottom_label)
    var bottom_spin := SpinBox.new()
    bottom_spin.min_value = 0.0
    bottom_spin.step = 1.0
    bottom_spin.value = float(BoundsSystem.bottom_inset)
    bottom_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(bottom_spin)

    var bounds_label := Label.new()
    vbox.add_child(bounds_label)

    var update_bounds := func() -> void:
        var w: int = int(width_spin.value)
        var h: int = int(height_spin.value)
        var l: int = int(left_spin.value)
        var r: int = int(right_spin.value)
        var t: int = int(top_spin.value)
        var b: int = int(bottom_spin.value)
        left_spin.max_value = maxf(2.0 * w - r - 1.0, 0.0)
        right_spin.max_value = maxf(2.0 * w - l - 1.0, 0.0)
        top_spin.max_value = maxf(2.0 * h - b - 1.0, 0.0)
        bottom_spin.max_value = maxf(2.0 * h - t - 1.0, 0.0)
        left_spin.value = minf(left_spin.value, left_spin.max_value)
        right_spin.value = minf(right_spin.value, right_spin.max_value)
        top_spin.value = minf(top_spin.value, top_spin.max_value)
        bottom_spin.value = minf(bottom_spin.value, bottom_spin.max_value)
        var vw: int = maxi(w - l - r, 1)
        var vh: int = maxi(h - t - b, 1)
        bounds_label.text = "Visible Bounds: %d × %d" % [vw, vh]

    width_spin.value_changed.connect(func(_v: float) -> void: update_bounds.call())
    height_spin.value_changed.connect(func(_v: float) -> void: update_bounds.call())
    left_spin.value_changed.connect(func(_v: float) -> void: update_bounds.call())
    right_spin.value_changed.connect(func(_v: float) -> void: update_bounds.call())
    top_spin.value_changed.connect(func(_v: float) -> void: update_bounds.call())
    bottom_spin.value_changed.connect(func(_v: float) -> void: update_bounds.call())
    update_bounds.call()

    var btn_row := HBoxContainer.new()
    btn_row.alignment = BoxContainer.ALIGNMENT_END
    btn_row.add_theme_constant_override("separation", 8)
    vbox.add_child(btn_row)

    var cancel_btn := Button.new()
    cancel_btn.text = "Cancel"
    cancel_btn.pressed.connect(func() -> void: dialog.queue_free())
    btn_row.add_child(cancel_btn)

    var apply_btn := Button.new()
    apply_btn.text = "Apply"
    apply_btn.pressed.connect(
        func() -> void:
            var w: int = int(width_spin.value)
            var h: int = int(height_spin.value)
            var l: int = int(left_spin.value)
            var r: int = int(right_spin.value)
            var t: int = int(top_spin.value)
            var b: int = int(bottom_spin.value)
            _apply_map_settings(w, h, l, r, t, b)
            dialog.queue_free()
    )
    btn_row.add_child(apply_btn)

    get_node("EditorUI").add_child(dialog)
    dialog.popup_centered(Vector2i(400, 620))


func _apply_map_settings(
    width: int, height: int, left: int = 5, right: int = 5, top: int = 4, bottom: int = 4
) -> void:
    _clear_terrain_renderer()
    TerrainSystem.clear()
    TerrainSystem.init_grid(width, height)
    BoundsSystem.left_inset = left
    BoundsSystem.right_inset = right
    BoundsSystem.top_inset = top
    BoundsSystem.bottom_inset = bottom
    _prefill_terrain()
    _grid._draw_grid()
    _player_start_tool.clear()


func _on_tool_toggled(btn: Button, tool_id: int) -> void:
    if btn.button_pressed:
        _active_tool = tool_id
        for tid in _tool_buttons:
            _tool_buttons[tid].button_pressed = (tid == tool_id)
        _entity_placer.on_tool_toggled()
        if tool_id != Tool.NONE:
            _entity_selector.deselect_all()
            _entity_properties.hide_panel()
    else:
        _active_tool = Tool.NONE
        _entity_placer.on_tool_toggled()


func _update_hovered_cell() -> void:
    if not _camera:
        return
    var mouse_pos := get_viewport().get_mouse_position()
    var ray_origin := _camera.project_ray_origin(mouse_pos)
    var ray_direction := _camera.project_ray_normal(mouse_pos)
    var ground_plane := Plane(Vector3.UP, 0.0)
    var intersection = ground_plane.intersects_ray(ray_origin, ray_direction)
    if not intersection:
        return
    var hit_pos := intersection as Vector3
    var terrain_y := TerrainSystem.get_height_at_world_smooth(hit_pos)
    if terrain_y > 0.01:
        var t := (terrain_y - ray_origin.y) / ray_direction.y
        hit_pos = ray_origin + ray_direction * t
    var cell := CellUtil.world_to_cell(hit_pos)
    if cell != _hovered_cell and not TerrainSystem.get_cell(cell).is_empty():
        _hovered_cell = cell
        _grid.update()
    _entity_placer.on_cell_changed()


func _cell_world_pos(cell: Vector2i) -> Vector3:
    var pos := CellUtil.cell_to_world(cell)
    var cell_data: Dictionary = TerrainSystem.get_cell(cell)
    if not cell_data.is_empty():
        var h: int = cell_data.get("max_height", cell_data.get("height", 0))
        pos.y = float(h) * TerrainSystem.HEIGHT_STEP
    return pos


func _cell_origin_world_pos(origin: Vector2i, footprint: Vector2i) -> Vector3:
    var pos := CellUtil.cell_origin_to_world(origin, footprint)
    var max_h := 0
    for dx in footprint.x:
        for dz in footprint.y:
            var cell := origin + Vector2i(dx, dz)
            var cell_data: Dictionary = TerrainSystem.get_cell(cell)
            if not cell_data.is_empty():
                var h: int = cell_data.get("max_height", cell_data.get("height", 0))
                if h > max_h:
                    max_h = h
    pos.y = float(max_h) * TerrainSystem.HEIGHT_STEP
    return pos


func get_hovered_cell() -> Vector2i:
    return _hovered_cell


func _on_height_changed(cell: Vector2i, new_height: int) -> void:
    if cell == _hovered_cell:
        _grid.update()
    var key := str(cell.x) + "," + str(cell.y)
    var entry := _painted_entities.get(key, {}) as Dictionary
    var node := entry.get("node") as Node3D
    if is_instance_valid(node):
        node.position.y = float(new_height) * TerrainSystem.HEIGHT_STEP
        var tib := node.get_node_or_null("ResourceComponent") as ResourceComponent
        if tib:
            tib.update_slope_positions()
    if _entity_selector.is_entity_selected(key):
        _entity_selector.refresh_slope_tilt()


func _on_terrain_cell_changed(key: String, data: Dictionary) -> void:
    var entry := _painted_entities.get(key, {}) as Dictionary
    var node := entry.get("node") as Node3D
    if not is_instance_valid(node):
        return
    var h: int = data.get("max_height", data.get("height", 0))
    node.position.y = float(h) * TerrainSystem.HEIGHT_STEP
    var tib := node.get_node_or_null("ResourceComponent") as ResourceComponent
    if tib:
        tib.update_slope_positions()
    if _entity_selector.is_entity_selected(key):
        _entity_selector.refresh_slope_tilt()


func _on_editor_selection_changed(selected_count: int) -> void:
    if selected_count == 0:
        _entity_properties.hide_panel()
        return
    var entries: Array[Dictionary] = _entity_selector.get_selected_entries()
    if entries.is_empty():
        _entity_properties.hide_panel()
        return
    var first: Dictionary = entries[0]
    _entity_properties.rebuild(first.get("cell_key", ""), first.get("data", {}))
