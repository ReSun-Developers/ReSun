extends Control

## Tabbed build menu sidebar with production queue, prerequisites, and angular progress.

const TAB_ENTITY_TYPES: Dictionary = {
    0: [EntityData.EntityType.BUILDING],
    1: [EntityData.EntityType.INFANTRY],
    2: [EntityData.EntityType.VEHICLE, EntityData.EntityType.AIRCRAFT],
    3: [],
}
## Default tab config used when the active game declares no sidebar_tabs.
const DEFAULT_TABS: Array[Dictionary] = [
    {"name": "Buildings", "entity_types": ["BUILDING"]},
    {"name": "Infantry", "entity_types": ["INFANTRY"]},
    {"name": "Vehicles", "entity_types": ["VEHICLE", "AIRCRAFT"]},
    {"name": "Special", "entity_types": []},
]
## Rank for entity types absent from the derived rank map (e.g. TERRAIN) —
## sorts last.
const UNKNOWN_TYPE_RANK: int = 999

## Lazily-built rank per entity type, derived from the tab config in use so
## tabs with mixed types (e.g. Vehicles = ground vehicles + aircraft) always
## list earlier tab types before later ones. Rebuilt when the config changes.
static var _type_rank: Dictionary = {}
static var _rank_key: String = ""


static func _get_type_rank(etype: EntityData.EntityType, tab_types: Variant = null) -> int:
    if tab_types == null:
        tab_types = TAB_ENTITY_TYPES
    var key := _tab_types_key(tab_types)
    if key != _rank_key:
        _rebuild_type_rank(tab_types)
        _rank_key = key
    return _type_rank.get(etype, UNKNOWN_TYPE_RANK)


static func _rebuild_type_rank(tab_types: Variant) -> void:
    _type_rank.clear()
    var next := 0
    for tab_index in range(tab_types.size()):
        for tab_type in tab_types[tab_index]:
            _type_rank[tab_type] = next
            next += 1


static func _tab_types_key(tab_types: Variant) -> String:
    var parts: Array[String] = []
    for i in range(tab_types.size()):
        parts.append(str(tab_types[i]))
    return "|".join(parts)


const CAMEO_W: int = 125
const CAMEO_H: int = 90
const GRID_COLS: int = 3
const GRID_ROWS: int = 5
## Tiny5 pixel font. Cameo text is 14px with an outline that always tracks
## 50% of the font size (7px at 14) — outline scales when the size changes.
const TINY5_FONT: FontFile = preload("res://assets/fonts/Tiny5/Tiny5-Regular.ttf")
const TINY5_CAMEO_SIZE: int = 14
const TINY5_OUTLINE_RATIO := 0.5

@onready var sell_button: Button = %SellButton
@onready var repair_button: Button = %RepairButton
## Tab buttons in display order, resolved from the active game's sidebar_tabs
## (see GameDefinition) at _ready; the scene supplies the button pool.
@onready var tab_bar: HBoxContainer = $TabBar
var tab_buttons: Array[Button] = []
@onready var grid: GridContainer = %GridContainer
@onready var scroll_up: Button = %ScrollUp
@onready var scroll_down: Button = %ScrollDown

## Resolved tab config: Array of { name: String, entity_types: Array[int] }.
var _tabs: Array[Dictionary] = []
## Per-tab entity-type arrays (parallel to `_tabs`), used for sort ranking.
var _tab_types: Array = []

var _current_tab: int = 0
var _scroll_offset: int = 0
var _cameo_buttons: Array[Button] = []
var _cameo_progress: Dictionary = {}  # button → ColorRect (shader overlay)
var _flicker_tweens: Dictionary = {}  # button → Tween
var _shader: ShaderMaterial = null
var _grid_dirty: bool = false

## Credit counter animation lives on the CreditCounter script attached to the
## CreditsLabel HUD node (scenes/ui/CreditsLabel.tscn); the Sidebar keeps no
## counter state.


func _ready() -> void:
    _shader = ShaderMaterial.new()
    _shader.shader = preload("res://shaders/ui/angular_progress.gdshader")

    _build_tabs()
    GameContext.game_changed.connect(_on_game_changed)

    scroll_up.pressed.connect(_on_scroll_up)
    scroll_down.pressed.connect(_on_scroll_down)

    sell_button.pressed.connect(_on_sell_pressed)
    repair_button.pressed.connect(_on_repair_pressed)
    # Button visuals sync from the mode owner's signal — sell/repair state is
    # OrderSystem's active generator type; the Sidebar keeps no mode booleans.
    OrderSystem.generator_changed.connect(_sync_action_buttons)
    # Placing mode refreshes the grid (all entities shown while armed).
    EntityPlacer.placing_mode_changed.connect(_on_placing_mode_changed)

    PrerequisiteSystem.prerequisites_changed.connect(_on_prerequisites_changed)

    ProductionManager.production_started.connect(_on_production_started)
    ProductionManager.production_progress.connect(_on_production_progress)
    ProductionManager.production_completed.connect(_on_production_completed)
    ProductionManager.production_cancelled.connect(_on_production_cancelled)
    ProductionManager.production_paused.connect(_on_production_paused)

    _switch_tab(0)
    _prewarm_available_models()


func _input(event: InputEvent) -> void:
    var hotkey := _hotkey_tab_index(event)
    if hotkey >= 0:
        _switch_tab(hotkey)
    elif event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            if get_global_rect().has_point(get_viewport().get_mouse_position()):
                _on_scroll_up()
                get_viewport().set_input_as_handled()
        elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            if get_global_rect().has_point(get_viewport().get_mouse_position()):
                _on_scroll_down()
                get_viewport().set_input_as_handled()


func _on_tab_pressed(tab_index: int) -> void:
    _switch_tab(tab_index)


## Resolves the tab set for the active game, falling back to the built-in
## default when the definition declares none. Feature-gated tabs are dropped
## when the feature is off.
func _resolve_tabs() -> Array[Dictionary]:
    var raw: Array = DEFAULT_TABS
    if GameContext.current and not GameContext.current.sidebar_tabs.is_empty():
        raw = GameContext.current.sidebar_tabs
    var out: Array[Dictionary] = []
    for entry in raw:
        var required := String(entry.get("requires_feature", ""))
        if not required.is_empty() and not GameContext.has_feature(required):
            continue
        var types: Array[int] = []
        for type_name: String in entry.get("entity_types", []):
            if EntityData.EntityType.has(type_name):
                types.append(EntityData.EntityType[type_name])
        out.append({"name": String(entry.get("name", "")), "entity_types": types})
    return out


## Builds the tab button row from `_tabs`, reusing the scene's buttons as a pool
## and duplicating one when the game declares more tabs than the scene provides.
func _build_tabs() -> void:
    _tabs = _resolve_tabs()
    _tab_types = []
    for tab in _tabs:
        _tab_types.append(tab["entity_types"])
    var pool: Array[Button] = []
    for child in tab_bar.get_children():
        if child is Button:
            pool.append(child)
    var template: Button = pool[0] if not pool.is_empty() else null
    tab_buttons = []
    for i in range(_tabs.size()):
        var btn: Button
        if i < pool.size():
            btn = pool[i]
        elif template:
            btn = template.duplicate() as Button
            btn.unique_name_in_owner = false
            btn.name = "TabButton%d" % i
            tab_bar.add_child(btn)
        else:
            break
        btn.text = String(_tabs[i]["name"])
        btn.visible = true
        for conn in btn.pressed.get_connections():
            btn.pressed.disconnect(conn["callable"])
        btn.pressed.connect(_on_tab_pressed.bind(i))
        tab_buttons.append(btn)
    for i in range(tab_buttons.size(), pool.size()):
        pool[i].visible = false
    _current_tab = clampi(_current_tab, 0, maxi(0, tab_buttons.size() - 1))


func _hotkey_tab_index(event: InputEvent) -> int:
    var idx := -1
    if event.is_action_pressed("tab_buildings"):
        idx = 0
    elif event.is_action_pressed("tab_infantry"):
        idx = 1
    elif event.is_action_pressed("tab_vehicles"):
        idx = 2
    elif event.is_action_pressed("tab_special"):
        idx = 3
    # A hotkey for a tab the active game does not declare is a no-op.
    return idx if idx >= 0 and idx < tab_buttons.size() else -1


func _on_game_changed(_def: GameDefinition) -> void:
    _build_tabs()
    _switch_tab(0)


func _switch_tab(tab_index: int) -> void:
    if tab_buttons.is_empty():
        _current_tab = 0
        return
    _current_tab = clampi(tab_index, 0, tab_buttons.size() - 1)
    _scroll_offset = 0
    for i in range(tab_buttons.size()):
        tab_buttons[i].button_pressed = (i == _current_tab)
    _queue_refresh()


func _on_scroll_up() -> void:
    if _scroll_offset > 0:
        _scroll_offset -= GRID_COLS
        _queue_refresh()


func _on_scroll_down() -> void:
    var entities := _get_current_entities()
    var max_offset := maxi(0, entities.size() - GRID_ROWS * GRID_COLS)
    if _scroll_offset < max_offset:
        _scroll_offset += GRID_COLS
        _queue_refresh()


func _get_current_entities() -> Array[EntityData]:
    var types: Array = []
    if _current_tab >= 0 and _current_tab < _tabs.size():
        types = _tabs[_current_tab]["entity_types"]
    var result: Array[EntityData] = []
    for etype in types:
        var all := EntityFactory.get_all_by_type(etype as EntityData.EntityType)
        for data in all:
            if not data.buildable:
                continue
            if PrerequisiteSystem.can_build(PlayerManager.get_local_player_id(), data):
                result.append(data)
    return sort_buildables(result, _tab_types)


## Returns a copy sorted into sidebar order: entity type group (rank derived
## from the tab config in use — e.g. ground vehicles before aircraft in the
## Vehicles tab), then ascending tech_level (-1 = never buildable, sorted first),
## then display_name, then id. Deterministic tie-breaking prevents load-order
## flicker between rebuilds. `tab_types` defaults to the built-in tab config.
static func sort_buildables(
    items: Array[EntityData], tab_types: Variant = null
) -> Array[EntityData]:
    var sorted := items.duplicate()
    sorted.sort_custom(
        func(a: EntityData, b: EntityData) -> bool: return _compare_build_items(a, b, tab_types) < 0
    )
    return sorted


static func _compare_build_items(a: EntityData, b: EntityData, tab_types: Variant) -> int:
    var rank_a := _get_type_rank(a.entity_type, tab_types)
    var rank_b := _get_type_rank(b.entity_type, tab_types)
    if rank_a != rank_b:
        return rank_a - rank_b
    if a.tech_level != b.tech_level:
        return a.tech_level - b.tech_level
    if a.display_name != b.display_name:
        return a.display_name.naturalnocasecmp_to(b.display_name)
    return a.id.naturalnocasecmp_to(b.id)


## Coalesce the many production/prerequisite signals into a single deferred
## grid rebuild per frame instead of rebuilding on every trigger.


func _queue_refresh() -> void:
    if _grid_dirty:
        return
    _grid_dirty = true
    _refresh_grid.call_deferred()


func _refresh_grid() -> void:
    _grid_dirty = false
    # Kill all flicker tweens
    for btn in _flicker_tweens:
        var tw: Tween = _flicker_tweens[btn]
        if tw and tw.is_valid():
            tw.kill()
    _flicker_tweens.clear()

    # Clear grid
    for child in grid.get_children():
        child.queue_free()
    _cameo_buttons.clear()
    _cameo_progress.clear()

    var entities := _get_current_entities()
    var visible_start := _scroll_offset
    var visible_end := mini(visible_start + GRID_ROWS * GRID_COLS, entities.size())

    for i in range(visible_start, visible_end):
        var data: EntityData = entities[i]
        var btn := _create_cameo(data)
        grid.add_child(btn)
        _cameo_buttons.append(btn)

    # Fill remaining slots
    var remaining := (GRID_ROWS * GRID_COLS) - (visible_end - visible_start)
    for _j in range(remaining):
        var spacer := Control.new()
        spacer.custom_minimum_size = Vector2(CAMEO_W, CAMEO_H)
        grid.add_child(spacer)


func _create_cameo(data: EntityData) -> Button:
    var btn := Button.new()
    btn.custom_minimum_size = Vector2(CAMEO_W, CAMEO_H)
    btn.size_flags_horizontal = Control.SIZE_FILL
    btn.size_flags_vertical = Control.SIZE_FILL

    var color := _get_cameo_color(data)
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.set_corner_radius_all(2)
    style.set_content_margin_all(0)
    btn.add_theme_stylebox_override("normal", style)
    btn.add_theme_stylebox_override("focus", style)

    var hover_style := style.duplicate()
    hover_style.bg_color = color.lightened(0.2)
    btn.add_theme_stylebox_override("hover", hover_style)

    var pressed_style := style.duplicate()
    pressed_style.bg_color = color.darkened(0.2)
    btn.add_theme_stylebox_override("pressed", pressed_style)

    _add_cameo_texture(btn, data.art_data)

    # Name label — Tiny5, white outline, bottom-left, uppercase. Words pack
    # toward the end ("NOD" / "POWER PLANT") so the top cameo art stays clear.
    var label := Label.new()
    label.text = _pack_words_to_end(data.display_name.to_upper(), CAMEO_W - 4.0)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.anchor_left = 0.0
    label.anchor_top = 0.0
    label.anchor_right = 1.0
    label.anchor_bottom = 1.0
    label.offset_left = 2.0
    label.offset_top = 0.0
    label.offset_right = -2.0
    label.offset_bottom = -2.0
    label.grow_horizontal = Control.GROW_DIRECTION_BOTH
    label.grow_vertical = Control.GROW_DIRECTION_END
    _apply_tiny5_style(label)
    btn.add_child(label)

    # Cost label — same Tiny5 style, stays in the top zone.
    var cost_label := Label.new()
    cost_label.text = "$%d" % data.cost
    cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    cost_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    cost_label.anchor_left = 0.0
    cost_label.anchor_top = 0.0
    cost_label.anchor_right = 1.0
    cost_label.anchor_bottom = 0.35
    cost_label.offset_left = 2.0
    cost_label.offset_top = 2.0
    cost_label.offset_right = -2.0
    cost_label.offset_bottom = -2.0
    cost_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
    cost_label.grow_vertical = Control.GROW_DIRECTION_END
    _apply_tiny5_style(cost_label)
    btn.add_child(cost_label)

    # Angular progress overlay
    var progress_rect := ColorRect.new()
    progress_rect.custom_minimum_size = Vector2(CAMEO_W, CAMEO_H)
    progress_rect.anchor_right = 1.0
    progress_rect.anchor_bottom = 1.0
    progress_rect.grow_horizontal = Control.GROW_DIRECTION_BOTH
    progress_rect.grow_vertical = Control.GROW_DIRECTION_BOTH
    progress_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    progress_rect.material = _shader.duplicate()
    progress_rect.visible = false
    btn.add_child(progress_rect)
    _cameo_progress[btn] = progress_rect

    # Check build limit
    if data.build_limit > 0:
        var count: int = PrerequisiteSystem.get_build_count(
            PlayerManager.get_local_player_id(), data.id
        )
        if count >= data.build_limit:
            btn.modulate = Color(0.4, 0.4, 0.4, 0.6)

    btn.gui_input.connect(_on_cameo_gui_input.bind(data))
    btn.set_meta("entity_id", data.id)

    # Show progress gradient if item has partial progress
    var pm := ProductionManager
    var player_id := PlayerManager.get_local_player_id()
    var current_progress := pm.get_item_progress(player_id, data)
    if current_progress > 0.0 and progress_rect.material:
        progress_rect.visible = true
        (progress_rect.material as ShaderMaterial).set_shader_parameter(
            "progress", current_progress
        )

    # Queue overlay for non-active queued items
    if _is_queued_non_active(pm, data):
        var queue_overlay := ColorRect.new()
        queue_overlay.color = Color(1, 1, 1, 0.15)
        queue_overlay.custom_minimum_size = Vector2(CAMEO_W, CAMEO_H)
        queue_overlay.anchor_right = 1.0
        queue_overlay.anchor_bottom = 1.0
        queue_overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
        queue_overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
        queue_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
        btn.add_child(queue_overlay)

    # Ready-to-place overlay for buildings
    if (
        data.entity_type == EntityData.EntityType.BUILDING
        and pm.is_ready_to_place(player_id, data.id)
    ):
        _add_ready_overlay(btn)

    # Ready-to-spawn overlay for units that failed to spawn
    elif pm.is_ready_to_spawn(player_id, data.id):
        _add_ready_overlay(btn)

    # On hold overlay for paused items
    elif _is_paused(pm, data):
        var hold_label := Label.new()
        hold_label.text = "On hold"
        hold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        hold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        hold_label.anchor_left = 0.0
        hold_label.anchor_top = 0.0
        hold_label.anchor_right = 1.0
        hold_label.anchor_bottom = 0.65
        hold_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
        hold_label.grow_vertical = Control.GROW_DIRECTION_BOTH
        hold_label.add_theme_font_size_override("font_size", 14)
        hold_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
        hold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        btn.add_child(hold_label)

    # Placing state — 2 steps brighter
    elif _is_placing(data):
        btn.modulate = Color(1.5, 1.5, 1.5, 1.0)

    # Queue count display
    var queue_count := pm.get_queue_count(player_id, data)
    if queue_count >= 1:
        var count_label := Label.new()
        count_label.text = str(queue_count)
        count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        count_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
        count_label.anchor_left = 0.7
        count_label.anchor_top = 0.0
        count_label.anchor_right = 1.0
        count_label.anchor_bottom = 0.35
        count_label.offset_left = 0.0
        count_label.offset_top = 2.0
        count_label.offset_right = -2.0
        count_label.offset_bottom = 0.0
        count_label.grow_horizontal = Control.GROW_DIRECTION_END
        count_label.grow_vertical = Control.GROW_DIRECTION_END
        count_label.add_theme_font_size_override("font_size", 14)
        count_label.add_theme_color_override("font_color", Color.WHITE)
        count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
        count_label.add_theme_constant_override("shadow_offset_x", 1)
        count_label.add_theme_constant_override("shadow_offset_y", 1)
        count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        btn.add_child(count_label)

    var rules := GlobalRules.get_current()
    var build_time := data.get_build_time(rules.build_speed) if rules else data.get_build_time()
    var time_str := "%.0fs" % build_time
    var tooltip := "%s\n$%d\nTime: %s" % [data.display_name, data.cost, time_str]
    if data.power != 0:
        tooltip += "\nPower: %+d" % data.power
    btn.tooltip_text = tooltip
    return btn


## First-child cameo image (called before the labels are added) so the name,
## cost, and progress overlays render on top of it. Entities without a cameo
## path keep the faction-color background.
func _add_cameo_texture(btn: Button, art_data: ArtData) -> void:
    if art_data == null or art_data.cameo_path.is_empty():
        return
    var texture: Texture2D = load(art_data.cameo_path)
    if texture == null:
        return
    var rect := TextureRect.new()
    rect.texture = texture
    rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    rect.stretch_mode = TextureRect.STRETCH_SCALE
    rect.anchor_right = 1.0
    rect.anchor_bottom = 1.0
    rect.grow_horizontal = Control.GROW_DIRECTION_BOTH
    rect.grow_vertical = Control.GROW_DIRECTION_BOTH
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    btn.add_child(rect)


## Shared Tiny5 styling for cameo text labels: white with an outline that
## tracks 50% of the font size (7 at 14px).
func _apply_tiny5_style(label: Label) -> void:
    label.add_theme_font_override("font", TINY5_FONT)
    label.add_theme_font_size_override("font_size", TINY5_CAMEO_SIZE)
    label.add_theme_color_override("font_color", Color.WHITE)
    label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
    label.add_theme_constant_override("outline_size", int(TINY5_CAMEO_SIZE * TINY5_OUTLINE_RATIO))


## Pack words toward the end: the LAST line takes as many words as fit the
## given width, earlier lines stay short ("NOD" / "POWER PLANT" instead of
## "NOD POWER" / "PLANT"). Autowrap stays on as a safety net for words that
## alone exceed the width. No-op for names that fit one line.
func _pack_words_to_end(display_name: String, max_width: float) -> String:
    var words := display_name.split(" ", false)
    if words.size() < 2:
        return display_name
    var lines: Array[String] = []
    var current := ""
    for i in range(words.size() - 1, -1, -1):
        var candidate := words[i] if current.is_empty() else words[i] + " " + current
        var candidate_width := (
            TINY5_FONT.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, TINY5_CAMEO_SIZE).x
        )
        if not current.is_empty() and candidate_width > max_width:
            lines.append(current)
            current = words[i]
        else:
            current = candidate
    lines.append(current)
    lines.reverse()
    return "\n".join(lines)


func _get_cameo_color(data: EntityData) -> Color:
    for faction in FactionCatalog.get_ordered():
        var f := faction as Faction
        if f and data.owner.has(f.id):
            return f.color
    return Color.GRAY


func _is_placing(data: EntityData) -> bool:
    return BuildingManager.is_build_mode and BuildingManager.current_building_type == data


func _is_paused(pm: ProductionManager, data: EntityData) -> bool:
    var items: Array = pm.get_queue_items(
        pm.get_queue_key(PlayerManager.get_local_player_id(), data.buildable_queue)
    )
    for item in items:
        var pq: ProductionQueue = item as ProductionQueue
        if pq.entity_data.id == data.id and pq.is_paused:
            return true
    return false


func _is_queued_non_active(pm: ProductionManager, data: EntityData) -> bool:
    var queue_key: String = pm.get_queue_key(
        PlayerManager.get_local_player_id(), data.buildable_queue
    )
    var items: Array = pm.get_queue_items(queue_key)
    var active_idx: int = pm.get_active_index(queue_key)
    for i in range(items.size()):
        var pq: ProductionQueue = items[i] as ProductionQueue
        if pq.entity_data.id == data.id and i != active_idx:
            return true
    return false


func _on_cameo_gui_input(event: InputEvent, data: EntityData) -> void:
    if not (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
        return
    var mb := event as InputEventMouseButton

    # Place-anywhere cheat: the cameo arms a free-placement session directly,
    # bypassing production routing entirely.
    var debug_menu := get_tree().get_first_node_in_group("debug_menu")
    if debug_menu and debug_menu.place_anywhere:
        EntityPlacer.start_placing(data)
        get_viewport().set_input_as_handled()
        return

    ProductionManager.handle_cameo_click(
        PlayerManager.get_local_player_id(), data, mb.button_index, mb.shift_pressed
    )
    get_viewport().set_input_as_handled()


func _on_prerequisites_changed(_player_id: int) -> void:
    _queue_refresh()
    _prewarm_available_models()


func _prewarm_available_models() -> void:
    var paths: PackedStringArray = []
    for entity_data in _get_current_entities():
        if entity_data.art_data and not entity_data.art_data.model_path.is_empty():
            var mp: String = entity_data.art_data.model_path
            if not BatchLoader.is_loaded(mp) and mp not in paths:
                paths.append(mp)
        # Also pre-warm deploy/undeploy target models.
        for target_id in [entity_data.deploys_into, entity_data.undeploys_into]:
            if target_id.is_empty():
                continue
            var target_data := EntityFactory.get_entity_data(target_id)
            if (
                target_data
                and target_data.art_data
                and not target_data.art_data.model_path.is_empty()
            ):
                var tp: String = target_data.art_data.model_path
                if not BatchLoader.is_loaded(tp) and tp not in paths:
                    paths.append(tp)
    if not paths.is_empty():
        BatchLoader.preload_batch(paths)


func _on_production_started(_queue_key: String) -> void:
    _queue_refresh()


func _on_production_progress(queue_key: String, progress: float) -> void:
    # Update the angular progress overlay on the matching cameo
    var pm := ProductionManager
    var active_idx := pm.get_active_index(queue_key)
    var items := pm.get_queue_items(queue_key)
    if active_idx >= items.size():
        return
    var item: ProductionQueue = items[active_idx] as ProductionQueue
    for btn in _cameo_buttons:
        if btn.get_meta("entity_id", "") == item.entity_data.id:
            var rect: ColorRect = _cameo_progress.get(btn)
            if rect and rect.material:
                rect.visible = true
                (rect.material as ShaderMaterial).set_shader_parameter("progress", progress)
            break


func _on_production_completed(_queue_key: String, _entity_data: EntityData) -> void:
    _queue_refresh()


func _on_production_cancelled(_queue_key: String) -> void:
    _queue_refresh()


func _on_production_paused(_queue_key: String) -> void:
    _queue_refresh()


func _on_sell_pressed() -> void:
    # Toggling the active mode off cancels; arming a mode only swaps the
    # generator — button visuals come back through generator_changed.
    if OrderSystem.is_sell_mode():
        OrderSystem.cancel()
    else:
        OrderSystem.set_generator(SellOrderGenerator.new())


func _on_repair_pressed() -> void:
    if OrderSystem.is_repair_mode():
        OrderSystem.cancel()
    else:
        OrderSystem.set_generator(RepairOrderGenerator.new())


func _sync_action_buttons() -> void:
    sell_button.button_pressed = OrderSystem.is_sell_mode()
    repair_button.button_pressed = OrderSystem.is_repair_mode()


func _on_placing_mode_changed(_active: bool) -> void:
    _queue_refresh()


func _add_ready_overlay(btn: Button) -> void:
    var label := Label.new()
    label.text = "Ready"
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.anchor_left = 0.0
    label.anchor_top = 0.0
    label.anchor_right = 1.0
    label.anchor_bottom = 0.65
    label.grow_horizontal = Control.GROW_DIRECTION_BOTH
    label.grow_vertical = Control.GROW_DIRECTION_BOTH
    label.add_theme_font_size_override("font_size", 16)
    label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5))
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    btn.add_child(label)
    var flicker := create_tween()
    flicker.set_loops()
    flicker.tween_property(btn, "modulate", Color(1.3, 1.3, 1.3, 1.0), 0.4)
    flicker.tween_property(btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.4)
    _flicker_tweens[btn] = flicker
