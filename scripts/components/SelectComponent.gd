@tool
class_name SelectComponent extends Area3D

signal selection_state_changed(select_comp: SelectComponent)

@export_group("Selection")
@export var health_component: HealthComponent
@export var is_selectable: bool = true
@export var is_drag_selectable: bool = true
@export var is_selected: bool = false
@export var is_hovering: bool = false
@export_enum("Infantry", "Vehicle", "Structure") var select_box_type: int = 0
@export var selection_size := Vector3(2.0, 0.01, 2.0)
@export var outline_size := Vector3(2.0, 2.0, 2.0)
@export var outline_2d_size := Vector2.ZERO
@export var vertical_offset: float = 0.0

enum SelectBoxType { Infantry, Vehicle, Structure }

const HEALTH_BAR_CUBE_SIZE = 0.33333333
## Move-target line lifetime and fade tail (seconds). The line is an order
## acknowledgement glyph: short-lived, fading out over the tail.
const MOVE_LINE_DURATION := 0.3
const FADE_WINDOW := 0.1
## Shared white unshaded material for building select boxes — one per game
## instead of one fresh material per building.
static var _shared_select_box_material: ORMMaterial3D = null
var health_bar: MeshInstance3D
var _building_select_box: MeshInstance3D
var _health_bar_grid: MeshInstance3D
var _storage_bar: MeshInstance3D = null
var _storage_bar_grid: MeshInstance3D = null
var _storage_owner_id: int = -1
var _storage_bar_span: float = 0.0
var _storage_bar_span_min: float = 0.0
var _rally_component: RallyPointComponent = null
var _move_line_timer: Timer = null
var _movement_controller: MovementController = null
var _combat_component: CombatComponent = null


func _update_selection_shape():
    $SelectionHitbox.shape.size = selection_size


func _update_outline_shape():
    $SelectOutline.shape.size = outline_size
    $SelectOutline.position = Vector3(0, outline_size.y / 2.0, 0)


func _ready():
    # _process only drives the move-target line; keep it off until the line shows
    # so every SelectComponent (units + structures) isn't ticked just to early-return.
    set_process(false)
    self._update_selection_shape()
    self._update_outline_shape()

    if select_box_type != SelectBoxType.Structure:
        var entity_root := get_parent()
        if entity_root:
            if not entity_root.is_in_group("selectable"):
                entity_root.add_to_group("selectable")
            if not entity_root.is_in_group("entities"):
                entity_root.add_to_group("entities")
            if not entity_root.is_in_group("drag_selectable"):
                entity_root.add_to_group("drag_selectable")

    if health_component is HealthComponent:
        health_component.connect("health_changed", _on_health_changed)
        update_health_bar()

    var select_outline_shape = $SelectOutline.shape

    if select_box_type == SelectBoxType.Structure:
        var hit_box_size = select_outline_shape.size
        var min_x: float = hit_box_size.x / -2
        var max_x: float = hit_box_size.x / 2
        var min_y: float = 0.01
        var max_y: float = hit_box_size.y
        var min_z: float = hit_box_size.z / -2
        var max_z: float = hit_box_size.z / 2

        var x_line_length = min((max_x - min_x) / 4, 1)
        var y_line_length = min((max_y - min_y) / 4, 0.5)
        var z_line_length = min((max_z - min_z) / 4, 1)

        if _shared_select_box_material == null:
            _shared_select_box_material = ORMMaterial3D.new()
            _shared_select_box_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            _shared_select_box_material.albedo_color = Color.WHITE
        var select_box_material: ORMMaterial3D = _shared_select_box_material

        # Create a 3D select box for buildings
        var building_select_box = MeshInstance3D.new()
        var immediate_mesh = ImmediateMesh.new()
        building_select_box.name = "BuildingSelectBox"
        building_select_box.mesh = immediate_mesh
        building_select_box.cast_shadow = MeshInstance3D.SHADOW_CASTING_SETTING_OFF

        # Generate the lines for the select box
        var lines = [
            [Vector3(min_x, min_y, min_z), Vector3(min_x, min_y + y_line_length, min_z)],
            [Vector3(min_x, min_y, min_z), Vector3(min_x + x_line_length, min_y, min_z)],
            [Vector3(min_x, min_y, min_z), Vector3(min_x, min_y, min_z + z_line_length)],
            [Vector3(max_x, min_y, min_z), Vector3(max_x, min_y + y_line_length, min_z)],
            [Vector3(max_x, min_y, min_z), Vector3(max_x - x_line_length, min_y, min_z)],
            [Vector3(max_x, min_y, min_z), Vector3(max_x, min_y, min_z + z_line_length)],
            [Vector3(min_x, min_y, max_z), Vector3(min_x, min_y + y_line_length, max_z)],
            [Vector3(min_x, min_y, max_z), Vector3(min_x + x_line_length, min_y, max_z)],
            [Vector3(min_x, min_y, max_z), Vector3(min_x, min_y, max_z - z_line_length)],
            [Vector3(max_x, min_y, max_z), Vector3(max_x, min_y + y_line_length, max_z)],
            [Vector3(max_x, min_y, max_z), Vector3(max_x - x_line_length, min_y, max_z)],
            [Vector3(max_x, min_y, max_z), Vector3(max_x, min_y, max_z - z_line_length)],
            # top up
            [
                Vector3(min_x, max_y - HEALTH_BAR_CUBE_SIZE, min_z),
                Vector3(min_x, max_y - y_line_length, min_z)
            ],
            [
                Vector3(min_x + HEALTH_BAR_CUBE_SIZE, max_y, min_z),
                Vector3(min_x + x_line_length, max_y, min_z)
            ],
            # top right
            [Vector3(max_x, max_y, min_z), Vector3(max_x, max_y - y_line_length, min_z)],
            [Vector3(max_x, max_y, min_z), Vector3(max_x - x_line_length, max_y, min_z)],
            [Vector3(max_x, max_y, min_z), Vector3(max_x, max_y, min_z + z_line_length)],
            # top left
            [
                Vector3(min_x, max_y - HEALTH_BAR_CUBE_SIZE, max_z),
                Vector3(min_x, max_y - y_line_length, max_z)
            ],
            [
                Vector3(min_x + HEALTH_BAR_CUBE_SIZE, max_y, max_z),
                Vector3(min_x + x_line_length, max_y, max_z)
            ],
        ]

        for line in lines:
            immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, select_box_material)
            immediate_mesh.surface_add_vertex(line[0])
            immediate_mesh.surface_add_vertex(line[1])
            immediate_mesh.surface_end()

            # draw health bar
            # health bar length that is stepped by HEALTH_BAR_CUBE_SIZE

            # draw health bar grid

            # Create vertex for each health bar cube segment
        add_child(building_select_box)
        _building_select_box = building_select_box

        if health_component:
            # draw health bar
            # health bar length that is stepped by HEALTH_BAR_CUBE_SIZE
            var health_value: float = (
                float(health_component.current_health) / float(health_component.max_health)
            )
            var health_parts := _build_segmented_bar(
                min_z,
                max_z,
                min_x,
                min_x + HEALTH_BAR_CUBE_SIZE,
                max_y - HEALTH_BAR_CUBE_SIZE,
                max_y,
                health_value,
                get_health_color(health_value),
                false,
            )
            health_bar = health_parts.fill as MeshInstance3D
            health_bar.name = "HealthBar"
            health_bar.visible = false
            add_child(health_bar)
            _health_bar_grid = health_parts.grid as MeshInstance3D
            _health_bar_grid.name = "HealthBarGrid"
            _health_bar_grid.visible = false
            add_child(_health_bar_grid)

        # Refinery storage bar — full-width bar at the building's base showing
        # tiberium storage fill. Mesh + data lookups are runtime-only (@tool).
        if not Engine.is_editor_hint():
            var stats := get_parent().get_node_or_null("StatsComponent") as StatsComponent
            if stats and not stats.id.is_empty() and stats.player_id >= 0:
                var data := EntityFactory.get_entity_data(stats.id)
                if data and data.refinery:
                    _build_storage_bar(hit_box_size, stats.player_id)

    # Rally line — green line from building center to rally point, drawn via the
    # shared MoveLineRenderer (change-only: re-registered when the rally point moves).
    var building := get_parent()
    if building:
        _rally_component = (building.get_node_or_null("RallyPointComponent") as RallyPointComponent)
        if _rally_component:
            _rally_component.rally_point_changed.connect(_on_rally_point_changed)

    # Move target line — green line from a moving unit to its destination cell,
    # drawn via the shared MoveLineRenderer. It flashes on a player order
    # (acknowledge_order) or when the entity is (re)selected while busy; it
    # never appears on its own for automatic moves or auto-acquired targets.
    var entity := get_parent()
    if entity:
        _movement_controller = entity.get_node_or_null("MovementController") as MovementController
        _combat_component = entity.get_node_or_null("CombatComponent") as CombatComponent
        if _movement_controller:
            var timer := Timer.new()
            timer.name = "MoveTargetLineTimer"
            timer.one_shot = true
            timer.wait_time = MOVE_LINE_DURATION
            timer.timeout.connect(_on_move_line_timeout)
            add_child(timer)
            _move_line_timer = timer

    _update_visibility()


func update_health_bar():
    if not is_instance_valid(health_bar) or not health_component:
        return

    if select_box_type == SelectBoxType.Structure:
        var select_outline_shape = $SelectOutline.shape
        var hit_box_size = select_outline_shape.size
        var min_z: float = hit_box_size.z / -2
        var max_z: float = hit_box_size.z / 2
        var health_value = (
            float(health_component.current_health) / float(health_component.max_health)
        )
        var length: float = (max_z - min_z) * health_value
        health_bar.scale.x = maxf(length, 0.001)
        health_bar.position.z = min_z + length / 2.0
        health_bar.material_override.albedo_color = get_health_color(health_value)


## Builds a segmented bar: a fill BoxMesh plus a black unshaded grid channel
## spanning the given world axis (X or Z). The fill runs from span_min, growing
## toward span_max by `ratio`. Returns {"fill": MeshInstance3D, "grid": MeshInstance3D}.
func _build_segmented_bar(
    span_min: float,
    span_max: float,
    cross_min: float,
    cross_max: float,
    y_lo: float,
    y_hi: float,
    ratio: float,
    fill_color: Color,
    span_is_x: bool,
) -> Dictionary:
    var grid_material := ORMMaterial3D.new()
    grid_material.albedo_color = Color(0, 0, 0)
    grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

    var grid := MeshInstance3D.new()
    var grid_mesh := ImmediateMesh.new()
    grid.mesh = grid_mesh
    grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    var segments: int = int(ceil((span_max - span_min) / HEALTH_BAR_CUBE_SIZE))
    for i in segments:
        var u: float = span_min + i * HEALTH_BAR_CUBE_SIZE
        var cross_lines := [
            [
                _bar_point(u, y_lo, cross_min, span_is_x),
                _bar_point(u, y_hi, cross_min, span_is_x),
            ],
            [
                _bar_point(u, y_lo, cross_max, span_is_x),
                _bar_point(u, y_hi, cross_max, span_is_x),
            ],
            [
                _bar_point(u, y_lo, cross_min, span_is_x),
                _bar_point(u, y_lo, cross_max, span_is_x),
            ],
            [
                _bar_point(u, y_hi, cross_min, span_is_x),
                _bar_point(u, y_hi, cross_max, span_is_x),
            ],
        ]
        for line in cross_lines:
            grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES, grid_material)
            grid_mesh.surface_add_vertex(line[0])
            grid_mesh.surface_add_vertex(line[1])
            grid_mesh.surface_end()

    var edge_lines := [
        [
            _bar_point(span_min, y_hi, cross_min, span_is_x),
            _bar_point(span_max, y_hi, cross_min, span_is_x),
        ],
        [
            _bar_point(span_min, y_hi, cross_max, span_is_x),
            _bar_point(span_max, y_hi, cross_max, span_is_x),
        ],
        [
            _bar_point(span_min, y_lo, cross_min, span_is_x),
            _bar_point(span_max, y_lo, cross_min, span_is_x),
        ],
        [
            _bar_point(span_min, y_lo, cross_max, span_is_x),
            _bar_point(span_max, y_lo, cross_max, span_is_x),
        ],
    ]
    for line in edge_lines:
        grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES, grid_material)
        grid_mesh.surface_add_vertex(line[0])
        grid_mesh.surface_add_vertex(line[1])
        grid_mesh.surface_end()

    var length: float = (span_max - span_min) * ratio
    var fill := MeshInstance3D.new()
    fill.mesh = BoxMesh.new()
    fill.scale = Vector3(
        maxf(length, 0.001), HEALTH_BAR_CUBE_SIZE - 0.02, HEALTH_BAR_CUBE_SIZE - 0.02
    )
    if span_is_x:
        fill.position = Vector3(
            span_min + length / 2.0, (y_lo + y_hi) / 2.0, (cross_min + cross_max) / 2.0
        )
    else:
        fill.position = Vector3(
            (cross_min + cross_max) / 2.0, (y_lo + y_hi) / 2.0, span_min + length / 2.0
        )
        fill.rotation_degrees.y = -90.0
    fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var fill_material := ORMMaterial3D.new()
    fill_material.albedo_color = fill_color
    fill.material_override = fill_material

    return {"fill": fill, "grid": grid}


func _bar_point(u: float, y: float, v: float, span_is_x: bool) -> Vector3:
    if span_is_x:
        return Vector3(u, y, v)
    return Vector3(v, y, u)


func _build_storage_bar(hit_box_size: Vector3, owner_id: int) -> void:
    var min_x: float = hit_box_size.x / -2
    var max_x: float = hit_box_size.x / 2
    var min_y: float = 0.01
    var max_z: float = hit_box_size.z / 2

    var fill_color := Color(0.2, 0.8, 0.2, 1)
    var rules := EntityFactory.get_global_rules()
    var category: String = EconomyManager.get_default_category()
    var rt: ResourceType = rules.get_resource_type(category) if rules else null
    if rt:
        fill_color = rt.color

    _storage_owner_id = owner_id
    _storage_bar_span = max_x - min_x
    _storage_bar_span_min = min_x

    var parts := _build_segmented_bar(
        min_x,
        max_x,
        max_z - HEALTH_BAR_CUBE_SIZE,
        max_z,
        min_y,
        min_y + HEALTH_BAR_CUBE_SIZE,
        0.0,
        fill_color,
        true,
    )
    _storage_bar = parts.fill as MeshInstance3D
    _storage_bar.name = "StorageBar"
    _storage_bar.visible = false
    add_child(_storage_bar)
    _storage_bar_grid = parts.grid as MeshInstance3D
    _storage_bar_grid.name = "StorageBarGrid"
    _storage_bar_grid.visible = false
    add_child(_storage_bar_grid)
    update_storage_bar()
    EconomyManager.credits_changed.connect(_on_credits_changed)
    # Capacity is now summed from owned buildings, so a place/sell/destroy/deploy
    # must re-scale the bar; registration fires after add_child, so connecting
    # here also catches the refinery's own registration.
    PrerequisiteSystem.prerequisites_changed.connect(_on_prerequisites_changed)


func update_storage_bar() -> void:
    if not is_instance_valid(_storage_bar) or _storage_owner_id < 0:
        return
    var capacity: int = EconomyManager.get_storage_capacity(_storage_owner_id)
    var ratio := 0.0
    if capacity > 0:
        var category: String = EconomyManager.get_default_category()
        ratio = clampf(
            float(EconomyManager.get_balance(_storage_owner_id, category)) / float(capacity),
            0.0,
            1.0,
        )
    var length: float = _storage_bar_span * ratio
    _storage_bar.scale.x = maxf(length, 0.001)
    _storage_bar.position.x = _storage_bar_span_min + length / 2.0


func _on_prerequisites_changed(player_id: int) -> void:
    if is_instance_valid(_storage_bar) and player_id == _storage_owner_id:
        update_storage_bar()


func _on_credits_changed(player_id: int, _balance: int, _reason: String, category: String) -> void:
    if (
        is_instance_valid(_storage_bar)
        and player_id == _storage_owner_id
        and category == EconomyManager.get_default_category()
    ):
        update_storage_bar()


func _on_health_changed(_new_health, _old_health) -> void:
    update_health_bar()


func get_health_color(health_value: float) -> Color:
    if health_value > 0.5:
        return Color.GREEN
    elif health_value > 0.25:
        return Color.YELLOW
    elif health_value > 0.0:
        return Color.RED
    else:
        return Color(0.5, 0.0, 0.0)  # dark red for dead units instead of green


func set_is_hovering(value: bool):
    is_hovering = value
    _update_visibility()


func set_is_selected(value: bool):
    is_selected = value
    _update_visibility()
    _update_move_line_on_select()
    selection_state_changed.emit(self)


func _update_move_line_on_select() -> void:
    # Show the line while the unit is moving OR while it has an active combat
    # engagement (entity or ground), so an in-range attacker re-selected
    # mid-fight still shows it.
    if is_selected and _movement_controller:
        if _movement_controller.is_moving() or _is_engaged():
            _show_move_line()
            return
    _hide_move_line()


## Player-issued order acknowledgement: flash the target line. Only the order
## funnel calls this. Automatic behaviour — guard auto-acquire, harvester
## auto-seek, docking, combat chase — never does, so its line appears only when
## the entity is selected.
func acknowledge_order() -> void:
    if is_selected:
        _show_move_line()


func _on_move_line_timeout() -> void:
    _unregister_line()


func _show_move_line() -> void:
    if not _move_line_timer or not _move_target_line_enabled():
        return
    _register_line()
    _move_line_timer.start()


func _hide_move_line() -> void:
    if _move_line_timer:
        _move_line_timer.stop()
    if not _rally_line_active():
        _unregister_line()


func _is_engaged() -> bool:
    return _combat_component != null and _combat_component.is_engaged()


func _get_move_line_endpoint() -> Vector3:
    # While engaged, point the line at the firing target (tracking an entity as
    # it moves, or the ordered ground cell) instead of the approach stop
    # position the unit is pathfinding to.
    if _is_engaged():
        return _combat_component.get_engagement_position()
    return _movement_controller.get_target_position()


## Pulled each frame by the shared MoveLineRenderer for registered sources.
## Returns the world-space line geometry (or {} when nothing should be drawn).
## The move-target endpoint is snapped to its destination cell center (y kept);
## the rally endpoint is the raw rally position.
func get_line_render_data() -> Dictionary:
    if not is_selected:
        return {}
    if _rally_line_active():
        return {
            "origin": _line_origin(),
            "target": _rally_component.get_target_position(),
            "alpha": 1.0,
            "marker_half": 0.6,
            "marker_diamond": true,
        }
    if _move_line_active():
        var target := _get_move_line_endpoint()
        var center := CellUtil.cell_to_world(CellUtil.world_to_cell(target))
        center.y = target.y  # cell_to_world zeroes y; keep the waypoint's terrain height
        return {
            "origin": _line_origin(),
            "target": center,
            "alpha": _line_alpha(),
            "marker_half": 0.125,
            "marker_diamond": false,
        }
    return {}


func _line_origin() -> Vector3:
    var parent := get_parent() as Node3D
    if is_instance_valid(parent):
        return parent.global_position
    return Vector3.ZERO


## Fade the line out over the tail of its one-shot lifetime.
func _line_alpha() -> float:
    if not _move_line_timer:
        return 1.0
    var remaining := _move_line_timer.time_left
    if remaining >= FADE_WINDOW:
        return 1.0
    return maxf(remaining / FADE_WINDOW, 0.0)


func _move_line_active() -> bool:
    if not _move_target_line_enabled():
        return false
    return _movement_controller != null and (_movement_controller.is_moving() or _is_engaged())


## Per-game toggle; move-target lines only, rally lines are unaffected.
func _move_target_line_enabled() -> bool:
    var tree := get_tree()
    if tree == null:
        return true
    var settings := tree.root.get_node_or_null("GameSettings")
    if settings == null:
        return true
    return bool(settings.get_value("move_target_line"))


func _rally_line_active() -> bool:
    return _rally_component != null and _rally_component.has_rally_point()


func _register_line() -> void:
    var renderer := _line_renderer()
    if renderer:
        renderer.register(self)


func _unregister_line() -> void:
    var renderer := _line_renderer()
    if renderer:
        renderer.unregister(self)


func _line_renderer() -> Node:
    var tree := get_tree()
    if tree:
        return tree.get_root().get_node_or_null("MoveLineRenderer")
    return null


func _update_visibility():
    var vis := is_selected or is_hovering
    if _building_select_box:
        _building_select_box.visible = is_selected
    if health_bar:
        health_bar.visible = vis
    if _health_bar_grid:
        _health_bar_grid.visible = vis
    for child in get_children():
        if (
            child != _building_select_box
            and child != health_bar
            and child != _health_bar_grid
            and child != _move_line_timer
        ):
            child.visible = vis
    if _rally_component:
        var has_rally := is_selected and _rally_component.has_rally_point()
        if has_rally:
            _register_line()
        elif not _move_line_active():
            _unregister_line()


func _on_rally_point_changed(_point: Vector2i) -> void:
    if _rally_component:
        var has_rally := is_selected and _rally_component.has_rally_point()
        if has_rally:
            _register_line()
        else:
            _unregister_line()
