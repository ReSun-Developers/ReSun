extends CanvasLayer

## Draws selection brackets, health bars, cargo/passenger pips, and the
## selected-producer power label directly via CanvasItem primitives —
## zero per-selection node allocations.

const LINE_WIDTH := 1.0
const MAX_CARGO_SLOTS := 10
const MAX_PASSENGER_SLOTS := 5
const PIP_GAP_RATIO := 0.002
const RANK_COLOR := Color(1.0, 0.85, 0.2)
## Fixed-px gap between the bottom pip row and the bracket line. Strokes are
## fixed-width, so a ratio would shrink below the line width on small rects.
const PIP_BRACKET_CLEARANCE_PX := 2.0
const SEGMENT_PX_PER_UNIT := 20.0
## Selected-producer power readout: green "POWER = {output}\nDRAIN = {drain}"
## grid totals, centered in the bracket (power-grid change). Tiny5, white
## outline; the font scales with camera zoom (16px at the default camera size).
const TINY5_FONT: FontFile = preload("res://assets/fonts/Tiny5/Tiny5-Regular.ttf")
const POWER_LABEL_COLOR := Color(0.3, 1.0, 0.35)
const POWER_LABEL_FONT_SIZE := 16
## Outline weight = 50% of the current font size (matches sidebar styling).
const OUTLINE_RATIO := 0.5
## Camera size at which the power label renders at POWER_LABEL_FONT_SIZE.
## Ortho camera zooms by shrinking `size`, so font scale = reference / size —
## the same 1/size relationship the projected health bar gets for free.
const REFERENCE_CAMERA_SIZE := 20.0
const POWER_LABEL_MIN_SCALE := 0.5


class DrawNode:
    extends Node2D

    func _draw():
        var overlay := get_parent() as SelectionOverlay
        if overlay:
            overlay._do_draw(self)


class HealthBarNode:
    extends Node2D

    func _draw():
        var overlay := get_parent() as SelectionOverlay
        if overlay:
            overlay._do_draw_health_bars(self)


var _draw_node: Node2D
var _health_bar_node: Node2D
var _entities: Array[Dictionary] = []
var _tracked: Array[SelectComponent] = []
## Perf-guard counter: the per-frame `_collect_entities()` must never scan the
## "selectable" group (test/unit/test_perf_guard.gd asserts it stays 0).
## ponytail: catches a regression that reintroduces a scan through this counter
## only; a raw `get_nodes_in_group` in `_collect_entities` escapes it.
var perf_group_scans: int = 0
var _selection_manager: SelectionManager = null


func _ready():
    layer = 128
    _health_bar_node = HealthBarNode.new()
    _health_bar_node.name = "HealthBarNode"
    add_child(_health_bar_node)

    _draw_node = DrawNode.new()
    add_child(_draw_node)

    _connect_to_selection_manager()


func _connect_to_selection_manager():
    _selection_manager = SelectionManager
    if not _selection_manager.selection_changed.is_connected(_on_selection_changed):
        _selection_manager.selection_changed.connect(_on_selection_changed)
    if not _selection_manager.hover_changed.is_connected(_on_hover_changed):
        _selection_manager.hover_changed.connect(_on_hover_changed)


func _on_selection_changed(selected: Array[SelectComponent]):
    _rebuild_tracked(selected)


func _on_hover_changed(_h: Node3D):
    var selected: Array[SelectComponent] = (
        _selection_manager.selected_entities if _selection_manager else []
    )
    _rebuild_tracked(selected)


func _rebuild_tracked(selected: Array[SelectComponent]):
    _tracked = selected.duplicate()
    if (
        _selection_manager
        and is_instance_valid(_selection_manager.hovered_entity)
        and not _tracked.has(_selection_manager.hovered_entity)
    ):
        _tracked.append(_selection_manager.hovered_entity)


func _process(_delta):
    _collect_entities()
    _draw_node.queue_redraw()
    _health_bar_node.queue_redraw()


func _do_draw(node: Node2D):
    for e in _entities:
        # Structures draw their own 3D wireframe select box (SelectComponent),
        # so the overlay only contributes the power label for them.
        if e.is_structure:
            _draw_power_label(node, e)
            continue
        _draw_health_bar_outline(node, e.bracket_rect)
        _draw_brackets(node, e.bracket_rect, e.is_selected)
        _draw_pips(node, e.cargo_pips, e.cargo_color, e.pass_pips)
        _draw_rank_insignia(node, e)
        _draw_power_label(node, e)


## "POWER = {output}\nDRAIN = {drain}" centered in the bracket for selected
## producers. Lines are centered individually — clamping to the bracket width
## autowraps mid-value on small buildings. Font scales with camera zoom;
## outline weight tracks the live font size (50%).
func _draw_power_label(node: Node2D, e: Dictionary) -> void:
    var label: String = e.get("power_label", "")
    if label.is_empty():
        return
    var font: FontFile = TINY5_FONT
    # No camera (headless/tests) falls back to default zoom, not min scale.
    var zoom_scale := 1.0
    var cam := node.get_viewport().get_camera_3d()
    if cam:
        zoom_scale = maxf(REFERENCE_CAMERA_SIZE / cam.size, POWER_LABEL_MIN_SCALE)
    var font_size := int(POWER_LABEL_FONT_SIZE * zoom_scale)
    var outline_size := int(font_size * OUTLINE_RATIO)
    var rect: Rect2 = e.bracket_rect
    var lines := label.split("\n")
    var line_h := font_size * 1.2
    var center_x := rect.position.x + rect.size.x * 0.5
    var y := rect.position.y + rect.size.y * 0.5 - line_h * (lines.size() - 1) * 0.5
    for line in lines:
        var text_width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
        (
            node
            . draw_string_outline(
                font,
                Vector2(center_x - text_width * 0.5, y),
                line,
                HORIZONTAL_ALIGNMENT_LEFT,
                -1,
                font_size,
                outline_size,
                Color.BLACK,
            )
        )
        (
            node
            . draw_string(
                font,
                Vector2(center_x - text_width * 0.5, y),
                line,
                HORIZONTAL_ALIGNMENT_LEFT,
                -1,
                font_size,
                POWER_LABEL_COLOR,
            )
        )
        y += line_h


## "POWER = {output}\nDRAIN = {drain}" only for a SELECTED building whose
## PowerComponent reports positive power (a producer). Numbers are the
## owner's live grid totals pulled from PowerGrid each frame.
func _power_label_for(entity: Node3D, is_selected: bool) -> String:
    if not is_selected:
        return ""
    var pc := entity.get_node_or_null("PowerComponent") as PowerComponent
    if pc == null or pc.power <= 0:
        return ""
    var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
    if stats == null:
        return ""
    return (
        "POWER = %d\nDRAIN = %d"
        % [PowerGrid.get_output(stats.player_id), PowerGrid.get_drain(stats.player_id)]
    )


func _do_draw_health_bars(node: Node2D):
    for e in _entities:
        if e.is_structure:
            continue
        var bar_height: float = e.rect.size.y * 0.053
        var bar_y: float = e.bracket_rect.position.y - bar_height - e.rect.size.y * 0.02
        var bar_width: float = e.rect.size.x
        var num_segs: int = int(max(e.world_size.x * SEGMENT_PX_PER_UNIT, 1.0))
        var seg_width: float = bar_width / num_segs
        var health_width: float = bar_width * e.health_ratio
        var base_color: Color = e.health_color
        var half_h: float = bar_height / 2.0

        for i in num_segs:
            var seg_x: float = e.rect.position.x + i * seg_width
            if seg_x >= e.rect.position.x + health_width:
                break
            var is_even: bool = i % 2 == 0
            var top_col := Color(
                base_color.r * (1.0 if is_even else 0.8),
                base_color.g * (1.0 if is_even else 0.8),
                base_color.b * (1.0 if is_even else 0.8),
            )
            var bot_col := Color(
                base_color.r * (0.8 if is_even else 0.6),
                base_color.g * (0.8 if is_even else 0.6),
                base_color.b * (0.8 if is_even else 0.6),
            )
            node.draw_rect(Rect2(seg_x, bar_y, seg_width, half_h), top_col)
            node.draw_rect(Rect2(seg_x, bar_y + half_h, seg_width, half_h), bot_col)


func _collect_entities():
    # Self-cleaning so direct callers (unit tests) see exactly one pass —
    # _process relies on the same guarantee every frame.
    _entities.clear()
    var camera := get_viewport().get_camera_3d()
    if not camera:
        return

    for ent in _tracked:
        if not is_instance_valid(ent):
            continue
        if not (ent.is_selected or ent.is_hovering):
            continue

        var parent: Node3D = ent.get_parent() as Node3D
        if not parent:
            continue
        if camera.is_position_behind(parent.global_position):
            continue

        var size := _get_selection_size(ent, parent)
        var rect: Variant = _project_entity(parent, camera, size, ent.vertical_offset)
        if not rect:
            continue

        var bracket_rect: Rect2 = rect
        bracket_rect.position.y -= rect.size.y * 0.1

        var health_ratio := 1.0
        var health_color := Color.WHITE
        if is_instance_valid(ent.health_component):
            health_ratio = (
                float(ent.health_component.current_health) / float(ent.health_component.max_health)
            )
            health_color = ent.get_health_color(health_ratio)

        var cargo_pips: Array[Dictionary] = []
        var cargo_color := Color.WHITE
        var pass_pips: Array[Dictionary] = []

        var transport := parent.get_node_or_null("TransportComponent") as TransportComponent
        if transport and transport.storage > 0 and transport.cargo.size() > 0:
            var rules := EntityFactory.get_global_rules()
            if rules:
                var first_type: String = transport.cargo.keys()[0]
                var rt := rules.get_resource_type(first_type)
                if rt:
                    cargo_color = rt.color

        _gather_pips(parent, rect, bracket_rect, cargo_pips, pass_pips)

        (
            _entities
            . append(
                {
                    "rect": rect,
                    "bracket_rect": bracket_rect,
                    "is_selected": ent.is_selected,
                    "is_structure": ent.select_box_type == SelectComponent.SelectBoxType.Structure,
                    "health_ratio": health_ratio,
                    "health_color": health_color,
                    "cargo_pips": cargo_pips,
                    "cargo_color": cargo_color,
                    "pass_pips": pass_pips,
                    "world_size": size,
                    "power_label": _power_label_for(parent, ent.is_selected),
                    "veteran_level": _visible_veteran_level(parent),
                }
            )
        )


## Rank chevrons for allied/local veterans and elites. Enemy and unowned ranks stay hidden.
func _visible_veteran_level(entity: Node3D) -> int:
    var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
    if stats == null or stats.veteran_level <= 0:
        return 0
    if stats.player_id < 0:
        return 0
    var local := PlayerManager.get_local_player_id()
    if stats.player_id != local and PlayerManager.is_enemy(local, stats.player_id):
        return 0
    return stats.veteran_level


func _draw_rank_insignia(node: Node2D, e: Dictionary) -> void:
    var level: int = e.get("veteran_level", 0)
    if level <= 0:
        return
    var rect: Rect2 = e.bracket_rect
    var w: float = maxf(rect.size.x * 0.14, 6.0)
    var h: float = w * 0.5
    var x: float = rect.position.x + rect.size.x - w * 1.2
    var y: float = rect.position.y + h * 1.6
    for i in level:
        var apex := Vector2(x + w * 0.5, y - h)
        node.draw_line(Vector2(x, y), apex, RANK_COLOR, 2.0)
        node.draw_line(apex, Vector2(x + w, y), RANK_COLOR, 2.0)
        y += h * 1.7


func _get_selection_size(ent: SelectComponent, parent: Node3D) -> Vector2:
    if ent.outline_2d_size != Vector2.ZERO:
        return ent.outline_2d_size

    var art := parent.get_node_or_null("ArtComponent") as ArtComponent
    if art and art.art_data and art.art_data.outline_2d_size != Vector2.ZERO:
        return art.art_data.outline_2d_size

    return Vector2(2.0, 2.0)


func _project_entity(
    parent: Node3D, camera: Camera3D, size: Vector2, v_offset: float = 0.0
) -> Variant:
    var center := parent.global_position + Vector3(0, v_offset, 0)
    var center_screen := camera.unproject_position(center)
    var ref_x_screen := camera.unproject_position(parent.global_position + Vector3(size.x, 0, 0))
    var ref_z_screen := camera.unproject_position(parent.global_position + Vector3(0, 0, size.y))
    var screen_half_x: float = center_screen.distance_to(ref_x_screen) / 2.0
    var screen_half_y: float = center_screen.distance_to(ref_z_screen) / 2.0

    var corners_screen := PackedVector2Array(
        [
            center_screen + Vector2(-screen_half_x, -screen_half_y),
            center_screen + Vector2(screen_half_x, -screen_half_y),
            center_screen + Vector2(screen_half_x, screen_half_y),
            center_screen + Vector2(-screen_half_x, screen_half_y),
        ]
    )

    var corners := PackedVector3Array()
    for cs in corners_screen:
        var ray_origin := camera.project_ray_origin(cs)
        var ray_dir := camera.project_ray_normal(cs)
        if absf(ray_dir.y) < 0.001:
            corners.append(parent.global_position)
            continue
        var t: float = -ray_origin.y / ray_dir.y
        corners.append(ray_origin + ray_dir * t)

    var screen_corners: Array[Vector2] = []
    for c in corners:
        screen_corners.append(camera.unproject_position(c))

    var min_s := screen_corners[0]
    var max_s := screen_corners[0]
    for p in screen_corners:
        min_s = min_s.min(p)
        max_s = max_s.max(p)

    var rect_size := max_s - min_s
    var min_size := 12.0
    rect_size.x = max(rect_size.x, min_size)
    rect_size.y = max(rect_size.y, min_size)

    return Rect2(min_s, rect_size)


func _draw_brackets(node: Node2D, rect: Rect2, is_selected: bool):
    if not is_selected:
        return

    var corner_inset: float = min(rect.size.x, rect.size.y) * 0.35
    var col := Color.WHITE

    var corners := [
        rect.position,
        Vector2(rect.end.x, rect.position.y),
        Vector2(rect.position.x, rect.end.y),
        rect.end,
    ]
    for c: Vector2 in corners:
        var sign_x := 1.0 if c.x == rect.position.x else -1.0
        var sign_y := 1.0 if c.y == rect.position.y else -1.0
        node.draw_line(c, c + Vector2(corner_inset * sign_x, 0), col, LINE_WIDTH)
        node.draw_line(c, c + Vector2(0, corner_inset * sign_y), col, LINE_WIDTH)


func _draw_health_bar_outline(node: Node2D, rect: Rect2):
    var bar_height: float = rect.size.y * 0.053
    var bar_width: float = rect.size.x
    var bar_y: float = rect.position.y - bar_height - rect.size.y * 0.02
    (
        node
        . draw_rect(
            Rect2(rect.position.x - 1, bar_y - 1, bar_width + 2, bar_height + 2),
            Color.BLACK,
            false,
            1.0,
        )
    )


func _gather_pips(
    parent: Node3D,
    rect: Rect2,
    bracket_rect: Rect2,
    cargo_pips: Array[Dictionary],
    pass_pips: Array[Dictionary],
):
    var transport := parent.get_node_or_null("TransportComponent") as TransportComponent
    # Cargo pips are for resource haulers (harvesters, trucks). A passenger
    # transport shows only its seat pips even if data carries a stray storage.
    var has_cargo := transport and transport.storage > 0 and transport.passengers == 0
    var has_passengers := transport and transport.passengers > 0

    if not has_cargo and not has_passengers:
        return

    var num_cargo_pips := MAX_CARGO_SLOTS
    var art := parent.get_node_or_null("ArtComponent") as ArtComponent
    if art and art.art_data and art.art_data.pip_count > 0:
        num_cargo_pips = clampi(art.art_data.pip_count, 1, MAX_CARGO_SLOTS)

    var pip_w := rect.size.x * 0.075
    var pip_h := pip_w * 0.8
    var pip_gap: float = rect.size.x * PIP_GAP_RATIO

    var grid_h := pip_h
    var grid_left := bracket_rect.position.x + pip_w * 0.2
    var grid_top := bracket_rect.end.y - grid_h - PIP_BRACKET_CLEARANCE_PX

    var cargo_filled: float = transport.get_cargo_total() if has_cargo else 0.0
    var filled_pips := 0
    if has_cargo and transport.storage > 0:
        var ratio := float(cargo_filled) / float(transport.storage)
        filled_pips = int(ceil(ratio * float(num_cargo_pips)))

    if has_cargo:
        for i in num_cargo_pips:
            var pip_x: float = grid_left + float(i) * (pip_w + pip_gap)
            cargo_pips.append(_make_pip(pip_x, grid_top, pip_w, pip_h, i < filled_pips))

    var pass_row_y := grid_top

    for i in MAX_PASSENGER_SLOTS:
        var pip_x: float = grid_left + float(i) * (pip_w + pip_gap)
        var visible_pip := has_passengers and i < transport.passengers
        if visible_pip:
            var filled := i < transport.current_passengers
            var color := Color.WHITE
            if i < transport.passenger_colors.size():
                color = transport.passenger_colors[i]
            pass_pips.append(_make_pip(pip_x, pass_row_y, pip_w, pip_h, filled, color))


func _make_pip(
    x: float, y: float, w: float, h: float, filled: bool, color: Color = Color.WHITE
) -> Dictionary:
    return {"rect": Rect2(x, y, w, h), "filled": filled, "color": color}


func _draw_pips(
    node: Node2D,
    cargo_pips: Array[Dictionary],
    cargo_color: Color,
    pass_pips: Array[Dictionary],
):
    for pip in cargo_pips:
        var r: Rect2 = pip.rect
        node.draw_rect(r, Color.BLACK, false, 1.0)
        if pip.filled:
            (
                node
                . draw_rect(
                    Rect2(r.position + Vector2(1, 1), r.size - Vector2(2, 2)),
                    cargo_color,
                )
            )

    for pip in pass_pips:
        var r: Rect2 = pip.rect
        node.draw_rect(r, Color.BLACK, false, 1.0)
        if pip.filled:
            var color: Color = pip.get("color", Color.WHITE)
            (
                node
                . draw_rect(
                    Rect2(r.position + Vector2(1, 1), r.size - Vector2(2, 2)),
                    color,
                )
            )
