extends Control
class_name DebugMenu

## Panel state
var _is_open: bool = false
var _sidebar: Control = null
var _selection_overlay: CanvasLayer = null
var _inspected_entity: Node3D = null
var _inspected_health: HealthComponent = null

## Node references
@onready var content: Control = $Content
@onready var overlays_header: Button = %OverlaysHeader
@onready var overlays_content: VBoxContainer = %OverlaysContent
@onready var lighting_header: Button = %LightingHeader
@onready var lighting_content: VBoxContainer = %LightingContent
@onready var cheats_header: Button = %CheatsHeader
@onready var cheats_content: VBoxContainer = %CheatsContent
@onready var inspect_header: Button = %InspectHeader
@onready var inspect_content: VBoxContainer = %InspectContent

## Overlay checkboxes
@onready var cb_pathfinding: CheckBox = %CBPathfinding
@onready var cb_spatial_hash: CheckBox = %CBSpatialHash
@onready var cb_entity_bounds: CheckBox = %CBEntityBounds
@onready var cb_health_bars: CheckBox = %CBHealthBars
@onready var cb_entity_ids: CheckBox = %CBEntityIds
@onready var cb_occupied_cells: CheckBox = %CBOccupiedCells
@onready var cb_map_bounds: CheckBox = %CBMapBounds

## Cheat checkboxes
@onready var cb_no_prereqs: CheckBox = %CBNoPrereqs
@onready var cb_no_build_time: CheckBox = %CBNoBuildTime
@onready var cb_no_cost: CheckBox = %CBNoCost
@onready var cb_place_anywhere: CheckBox = %CBPlaceAnywhere
@onready var cb_force_radar: CheckBox = %CBForceRadar

## Fog / shroud controls
@onready var fog_header: Button = %FogHeader
@onready var fog_content: VBoxContainer = %FogContent
@onready var cb_shroud: CheckBox = %CBShroud
@onready var cb_fog: CheckBox = %CBFog
@onready var reveal_shroud_btn: Button = %RevealShroudBtn
@onready var cover_shroud_btn: Button = %CoverShroudBtn

## Lighting controls
@onready var lighting_controls: LightingControls = null

## Tracks whether the lighting slider signals are wired.
var _lighting_sliders_wired := false

## Stats label
@onready var stats_label: Label = %StatsLabel

## Inspect section
@onready var inspect_label: RichTextLabel = %InspectLabel


func _ready() -> void:
    # Debug panel never exists in a non-debug (release) build.
    if not OS.is_debug_build():
        queue_free()
        return
    add_to_group("debug_menu")
    set_process_input(true)
    set_process(true)
    content.visible = false

    # Cache sidebar reference
    _sidebar = UIUtil.find_sidebar()

    # Cache selection overlay
    _selection_overlay = _find_selection_overlay()

    # Connect header buttons
    overlays_header.pressed.connect(_toggle_section.bind(overlays_content))
    lighting_header.pressed.connect(_toggle_section.bind(lighting_content))
    cheats_header.pressed.connect(_toggle_section.bind(cheats_content))
    fog_header.pressed.connect(_toggle_section.bind(fog_content))
    inspect_header.pressed.connect(_toggle_section.bind(inspect_content))

    # Connect overlay checkboxes
    cb_pathfinding.toggled.connect(_on_pathfinding_toggled)
    cb_spatial_hash.toggled.connect(_on_spatial_hash_toggled)
    cb_entity_bounds.toggled.connect(_on_entity_bounds_toggled)
    cb_health_bars.toggled.connect(_on_health_bars_toggled)
    cb_entity_ids.toggled.connect(_on_entity_ids_toggled)
    cb_occupied_cells.toggled.connect(_on_occupied_cells_toggled)
    cb_map_bounds.toggled.connect(_on_map_bounds_toggled)

    # Connect cheat checkboxes
    cb_no_prereqs.toggled.connect(_on_no_prereqs_toggled)
    cb_no_build_time.toggled.connect(func(v: bool) -> void: Cheats.no_build_time = v)
    cb_no_cost.toggled.connect(func(v: bool) -> void: Cheats.no_cost = v)
    cb_place_anywhere.toggled.connect(_on_place_anywhere_toggled)
    cb_force_radar.toggled.connect(_on_force_radar_toggled)

    # Connect buttons
    var clear_paths_btn: Button = %ClearPathsBtn
    var add_credits_btn: Button = %AddCreditsBtn
    clear_paths_btn.pressed.connect(_on_clear_paths)
    add_credits_btn.pressed.connect(_on_add_credits)

    # Fog / shroud controls
    _sync_fog_toggles()
    cb_shroud.toggled.connect(_on_fog_toggle.bind(&"shroud_enabled"))
    cb_fog.toggled.connect(_on_fog_toggle.bind(&"fog_of_war"))
    reveal_shroud_btn.pressed.connect(_on_reveal_shroud)
    cover_shroud_btn.pressed.connect(_on_cover_shroud)

    # Initialize lighting sliders
    _init_lighting_sliders()

    # Reset on scene change
    get_tree().node_added.connect(_on_node_added)

    # Sync inspection with selection
    SelectionManager.selection_changed.connect(_on_selection_changed)


func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_QUOTELEFT or event.physical_keycode == KEY_QUOTELEFT:
            _toggle_panel()
            get_viewport().set_input_as_handled()
            return


func _process(_delta: float) -> void:
    if _is_open:
        _update_stats()


func _toggle_panel() -> void:
    _is_open = not _is_open
    content.visible = _is_open
    if _is_open:
        _on_selection_changed(SelectionManager.selected_entities)
    else:
        clear_inspection()


func _toggle_section(section: Control) -> void:
    section.visible = not section.visible
    if section == lighting_content:
        _init_lighting_sliders()


func _update_stats() -> void:
    if not stats_label:
        return
    var entities := get_tree().get_nodes_in_group("entities")
    var counts: Dictionary = {}
    for entity: Node3D in entities:
        if not is_instance_valid(entity):
            continue
        var stats := entity.get_node_or_null("StatsComponent")
        if stats:
            var etype: int = stats.get("entity_type") if stats.get("entity_type") else 0
            counts[etype] = counts.get(etype, 0) + 1

    var type_names := ["INF", "VEH", "BLD", "ARC", "TER", "OVR"]
    var lines: PackedStringArray = []
    for i in range(6):
        if counts.has(i):
            lines.append("%s:%d" % [type_names[i], counts[i]])

    var fps_text := "FPS: %d" % Engine.get_frames_per_second()
    stats_label.text = " ".join(lines) + " | " + fps_text


# --- Overlay toggles ---


func _on_pathfinding_toggled(pressed: bool) -> void:
    DebugVisualizer.enabled = pressed
    for entity in get_tree().get_nodes_in_group("entities"):
        if not is_instance_valid(entity):
            continue
        var mc := entity.get_node_or_null("MovementController")
        if mc:
            mc.debug_show_path = pressed


func _on_spatial_hash_toggled(pressed: bool) -> void:
    DebugVisualizer.show_spatial_hash = pressed


func _on_entity_bounds_toggled(pressed: bool) -> void:
    DebugVisualizer.show_entity_bounds = pressed


func _on_health_bars_toggled(pressed: bool) -> void:
    if _selection_overlay:
        _selection_overlay.visible = pressed


func _on_entity_ids_toggled(pressed: bool) -> void:
    DebugVisualizer.show_entity_ids = pressed


func _on_occupied_cells_toggled(pressed: bool) -> void:
    DebugVisualizer.show_occupied_cells = pressed


func _on_map_bounds_toggled(pressed: bool) -> void:
    BoundsSystem.show_bounds = pressed


# --- Action buttons ---


func _on_clear_paths() -> void:
    DebugVisualizer.clear_all()


func _on_add_credits() -> void:
    var player_id := PlayerManager.get_local_player_id()
    EconomyManager.add(player_id, 100000, "debug_menu", EconomyManager.get_default_category(), true)


# --- Fog / shroud controls ---


func _sync_fog_toggles() -> void:
    var rules := GlobalRules.get_current()
    if rules == null:
        return
    cb_shroud.set_pressed_no_signal(rules.shroud_enabled)
    cb_fog.set_pressed_no_signal(rules.fog_of_war)


func _on_fog_toggle(pressed: bool, field: StringName) -> void:
    var rules := GlobalRules.get_current()
    if rules:
        rules.set(field, pressed)
    _refresh_fog_renderer()


func _on_reveal_shroud() -> void:
    var local := PlayerManager.get_local_player_id()
    ShroudSystem.explore_all(local)
    ShroudSystem.resolve_dirty()


func _on_cover_shroud() -> void:
    ShroudSystem.cover_shroud(PlayerManager.get_local_player_id())


func _refresh_fog_renderer() -> void:
    FogRenderer.refresh()
    # Toggling fog/shroud changes effective state with no dirty cells, so ghost
    # membership is swept explicitly (mirrors FogRenderer.refresh()).
    UnitMeshRenderer.sweep_ghosts()


# --- Entity inspection ---


func _on_selection_changed(selected: Array[SelectComponent]) -> void:
    if not _is_open:
        return
    if selected.is_empty():
        clear_inspection()
        return
    var select_comp: SelectComponent = selected[0]
    if not is_instance_valid(select_comp):
        clear_inspection()
        return
    var entity := select_comp.get_parent() as Node3D
    if entity and is_instance_valid(entity):
        _show_inspection(entity)
    else:
        clear_inspection()


func _show_inspection(entity: Node3D) -> void:
    if not inspect_content or not inspect_label:
        return
    _disconnect_inspection_signals()
    inspect_content.visible = true

    var text := ""

    # Health summary at top
    var health := entity.get_node_or_null("HealthComponent") as HealthComponent
    if health:
        text += "[b]Health[/b] %d / %d\n\n" % [health.current_health, health.max_health]

    var children := entity.get_children()
    for child: Node in children:
        if child is Node and child.name.ends_with("Component"):
            text += "[b]%s[/b]\n" % child.name
            var props := child.get_property_list()
            for prop: Dictionary in props:
                var prop_name: String = prop.get("name", "")
                if prop_name.begins_with("_") or prop_name in ["script", "name"]:
                    continue
                var usage: int = prop.get("usage", 0)
                if usage & PROPERTY_USAGE_STORAGE:
                    var value = child.get(prop_name)
                    text += "  %s = %s\n" % [prop_name, str(value)]
            text += "\n"

    if text.is_empty():
        text = "No components found"

    inspect_label.text = text

    _inspected_entity = entity
    _inspected_health = health
    if _inspected_health:
        _inspected_health.health_changed.connect(_on_inspected_health_changed)


func _on_inspected_health_changed(_new_health: int, _old_health: int) -> void:
    if is_instance_valid(_inspected_entity):
        _show_inspection(_inspected_entity)


func clear_inspection() -> void:
    _disconnect_inspection_signals()
    _inspected_entity = null
    _inspected_health = null
    if inspect_content:
        inspect_content.visible = false
    if inspect_label:
        inspect_label.text = ""


func _disconnect_inspection_signals() -> void:
    if _inspected_health and is_instance_valid(_inspected_health):
        if _inspected_health.health_changed.is_connected(_on_inspected_health_changed):
            _inspected_health.health_changed.disconnect(_on_inspected_health_changed)


# --- Lighting sliders ---


func _find_selection_overlay() -> CanvasLayer:
    # SelectionOverlay is a registered autoload in the root viewport, not a child
    # of the gameplay scene, so it is referenced by its singleton identifier.
    return SelectionOverlay as CanvasLayer


func _init_lighting_sliders() -> void:
    if _lighting_sliders_wired:
        return
    # Resolve lazily: LightingControls registers in its group during _ready,
    # which may not have happened yet when this panel readied first.
    if not lighting_controls:
        lighting_controls = (
            get_tree().get_first_node_in_group("lighting_controls") as LightingControls
        )
    if not lighting_controls:
        return

    _connect_lighting_slider("SunElevationSlider", "sun_elevation", 0, 90)
    _connect_lighting_slider("SunRotationSlider", "sun_rotation", 0, 360)
    _connect_lighting_slider("SunIntensitySlider", "sun_intensity", 0, 5)
    _connect_lighting_slider("ShadowStrengthSlider", "shadow_strength", 0, 1)
    _connect_lighting_slider("AmbientLightSlider", "ambient_light", 0, 2)
    _connect_lighting_slider("FogDensitySlider", "fog_density", 0, 0.01)
    _connect_lighting_slider("SkyRotationSlider", "sky_rotation", -1, 1)
    _connect_lighting_slider("GlowIntensitySlider", "glow_intensity", 0, 2)

    # Sun color picker
    var color_picker := lighting_content.get_node_or_null("SunColorPicker") as ColorPickerButton
    if color_picker:
        color_picker.color = lighting_controls.sun_color
        color_picker.color_changed.connect(
            func(c: Color) -> void:
                if lighting_controls:
                    lighting_controls.sun_color = c
        )

    _lighting_sliders_wired = true


func _connect_lighting_slider(
    slider_name: String, property: String, min_val: float, max_val: float
) -> void:
    var slider := lighting_content.get_node_or_null(slider_name) as Slider
    if not slider:
        return
    slider.min_value = min_val
    slider.max_value = max_val
    slider.value = lighting_controls.get(property)
    slider.value_changed.connect(
        func(v: float) -> void:
            if lighting_controls:
                lighting_controls.set(property, v)
    )


# --- Cheat toggles ---


func _on_no_prereqs_toggled(v: bool) -> void:
    Cheats.no_prereqs = v
    if _sidebar and _sidebar.has_method("_refresh_grid"):
        _sidebar._refresh_grid()


func _on_force_radar_toggled(v: bool) -> void:
    RadarSystem.force_online = v


# --- Scene change reset ---


func reset_state() -> void:
    Cheats.reset()
    cb_no_prereqs.button_pressed = false
    cb_no_build_time.button_pressed = false
    cb_no_cost.button_pressed = false
    cb_place_anywhere.button_pressed = false
    cb_force_radar.button_pressed = false
    RadarSystem.force_online = false
    var rules := GlobalRules.get_current()
    if rules:
        rules.shroud_enabled = true
        rules.fog_of_war = false
    _sync_fog_toggles()
    _refresh_fog_renderer()
    EntityPlacer.exit_placing_mode()
    cb_pathfinding.button_pressed = true
    cb_spatial_hash.button_pressed = false
    cb_entity_bounds.button_pressed = false
    cb_health_bars.button_pressed = false
    cb_entity_ids.button_pressed = false
    cb_occupied_cells.button_pressed = false
    DebugVisualizer.reset_overlays()
    if _selection_overlay:
        _selection_overlay.visible = false
    clear_inspection()


func _on_place_anywhere_toggled(v: bool) -> void:
    Cheats.place_anywhere = v
    if v:
        EntityPlacer.enter_placing_mode()
    else:
        EntityPlacer.exit_placing_mode()


func _on_node_added(node: Node) -> void:
    if node.name.begins_with("Map"):
        reset_state()
