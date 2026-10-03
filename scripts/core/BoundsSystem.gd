@tool
extends Node3D

## Gameplay API — cell units
var grid_cells: Vector2i = Vector2i(64, 64)

const DEFAULT_VISIBLE_INSETS := Vector4i(5, 5, 4, 4)

## Two-cell inward inset applied to player-issued order targets so destinations
## land inside the visible boundary instead of riding its edge.
const ORDER_EDGE_INSET: float = 2.0

## Visible-bounds insets from each map edge, in cells.
@export var left_inset: int = DEFAULT_VISIBLE_INSETS.x:
    set = _set_left_inset
@export var right_inset: int = DEFAULT_VISIBLE_INSETS.y:
    set = _set_right_inset
@export var top_inset: int = DEFAULT_VISIBLE_INSETS.z:
    set = _set_top_inset
@export var bottom_inset: int = DEFAULT_VISIBLE_INSETS.w:
    set = _set_bottom_inset

## Visual properties
@export var line_color: Color = Color.RED:
    set = _set_line_color
@export var map_line_width: float = 8.0:
    set = _set_map_line_width
@export var visible_line_width: float = 8.0:
    set = _set_visible_line_width
@export var visible_bounds_color: Color = Color.BLUE:
    set = _set_visible_bounds_color

## Visibility toggle
var show_bounds: bool = false:
    set = _set_show_bounds

## Camera pivot used to center the camera when a map is initialized.
@export var camera_pivot: Node3D

## FinalSun-style start-location cluster offsets around the map-center cell.
## Player i defaults to center + offsets[i % 8]; the list is packed so the
## first four players take the tight 2x2 grid right next to each other.
const START_CLUSTER_OFFSETS: Array[Vector2i] = [
    Vector2i(0, 0),
    Vector2i(1, 0),
    Vector2i(0, 1),
    Vector2i(1, 1),
    Vector2i(-1, 0),
    Vector2i(0, -1),
    Vector2i(-1, -1),
    Vector2i(1, -1),
]

var map_bounds_mesh_instance: MeshInstance3D
var visible_bounds_mesh_instance: MeshInstance3D
var immediate_map_mesh: ImmediateMesh
var immediate_visible_mesh: ImmediateMesh


func _ready() -> void:
    create_bounds_nodes()
    if not Engine.is_editor_hint():
        grid_cells = TerrainSystem.grid_cells
        TerrainSystem.grid_initialized.connect(_on_grid_initialized)
        if not _has_live_pivot():
            camera_pivot = _find_camera_pivot()
        if _has_live_pivot():
            _center_camera_on_diamond()
        call_deferred("_resolve_camera_pivot")
        call_deferred("_position_cloud_overlay")
    create_bounds_edges()
    map_bounds_mesh_instance.visible = show_bounds
    visible_bounds_mesh_instance.visible = show_bounds


func _on_grid_initialized() -> void:
    grid_cells = TerrainSystem.grid_cells
    create_bounds_edges()
    _resolve_camera_pivot()
    if _has_live_pivot():
        _center_camera_on_diamond()
    call_deferred("_position_cloud_overlay")


## True when the pivot is a live node that is currently in the tree. A pivot left
## over from a released match is detached (or freed) and must be replaced.
func _has_live_pivot() -> bool:
    return is_instance_valid(camera_pivot) and camera_pivot.is_inside_tree()


func _find_camera_pivot() -> Node3D:
    var root: Window = get_tree().root
    for child in root.get_children():
        var cam: Camera3D = child.find_child("Camera3D", true, false) as Camera3D
        if cam:
            return cam.get_parent() as Node3D
    return null


## Re-resolve the camera pivot after the main scene enters the tree. The
## autoload _ready() runs before the gameplay scene exists, so the pivot can
## only be discovered here (or on grid init) in real gameplay. A pivot left over
## from a released match is detached, so it is re-resolved rather than reused.
func _resolve_camera_pivot() -> void:
    if _has_live_pivot():
        return
    camera_pivot = _find_camera_pivot()


func _center_camera_on_diamond() -> void:
    if not _has_live_pivot():
        return
    camera_pivot.global_position = Vector3(0.0, camera_pivot.global_position.y, 0.0)


## Default start cell for a player: the map-center cell plus the player's
## cluster offset. Always inside the diamond; shared by the MapEditor tool and
## the gameplay camera so both agree on what "no override" means.
func default_start_cell(player_id: int) -> Vector2i:
    var center_cell := Vector2i(
        (grid_cells.x + grid_cells.y) / 2, (grid_cells.x + grid_cells.y) / 2
    )
    var offset: Vector2i = START_CLUSTER_OFFSETS[player_id % START_CLUSTER_OFFSETS.size()]
    var cell: Vector2i = center_cell + offset
    if CellUtil.is_in_diamond(cell, grid_cells):
        return cell
    return center_cell


## Center the camera pivot on a cell's world position, preserving the pivot's
## current height (matches _center_camera_on_diamond, which only patches x/z).
func center_camera_on_cell(cell: Vector2i) -> void:
    if not _has_live_pivot():
        return
    var p := CellUtil.cell_to_world(cell)
    camera_pivot.global_position = Vector3(p.x, camera_pivot.global_position.y, p.z)


## Restore visible-bounds insets from loaded map data (JSON v4), with a v3 fallback.
func apply_saved_bounds(data: Dictionary) -> void:
    var vb: Variant = data.get("visible_bounds")
    if vb is Array and vb.size() == 4:
        left_inset = clampi(int(vb[0]), 0, grid_cells.x - 1)
        right_inset = clampi(int(vb[1]), 0, grid_cells.x - 1)
        top_inset = clampi(int(vb[2]), 0, grid_cells.y - 1)
        bottom_inset = clampi(int(vb[3]), 0, grid_cells.y - 1)
        return
    # v3 fallback: no persisted bounds — use the standard default insets.
    left_inset = DEFAULT_VISIBLE_INSETS.x
    right_inset = DEFAULT_VISIBLE_INSETS.y
    top_inset = DEFAULT_VISIBLE_INSETS.z
    bottom_inset = DEFAULT_VISIBLE_INSETS.w


# ========================================
# Setters
# ========================================


func _set_left_inset(value: int) -> void:
    left_inset = maxi(value, 0)
    if is_inside_tree():
        create_bounds_edges()


func _set_right_inset(value: int) -> void:
    right_inset = maxi(value, 0)
    if is_inside_tree():
        create_bounds_edges()


func _set_top_inset(value: int) -> void:
    top_inset = maxi(value, 0)
    if is_inside_tree():
        create_bounds_edges()


func _set_bottom_inset(value: int) -> void:
    bottom_inset = maxi(value, 0)
    if is_inside_tree():
        create_bounds_edges()


func _set_line_color(value: Color) -> void:
    line_color = value
    if is_inside_tree():
        create_bounds_edges()


func _set_map_line_width(value: float) -> void:
    map_line_width = value
    if is_inside_tree():
        create_bounds_edges()


func _set_visible_line_width(value: float) -> void:
    visible_line_width = value
    if is_inside_tree():
        create_bounds_edges()


func _set_visible_bounds_color(value: Color) -> void:
    visible_bounds_color = value
    if is_inside_tree():
        create_bounds_edges()


func _set_show_bounds(value: bool) -> void:
    show_bounds = value
    if map_bounds_mesh_instance:
        map_bounds_mesh_instance.visible = show_bounds
    if visible_bounds_mesh_instance:
        visible_bounds_mesh_instance.visible = show_bounds


# ========================================
# Gameplay API (cell units)
# ========================================


func is_in_map_bounds(cell: Vector2i) -> bool:
    return CellUtil.is_in_diamond(cell, grid_cells)


func is_in_play_area(cell: Vector2i) -> bool:
    return _in_play_diamond(cell, 0.0)


func is_in_play_area_with_margin(cell: Vector2i, inset_cells: float = 1.0) -> bool:
    return _in_play_diamond(cell, inset_cells)


## True when a cell is inside the player-order diamond — the visible outline
## shrunk inward by `ORDER_EDGE_INSET`. Player-issued order targets and
## relocation spirals are bounded to this area; AI/automatic movement is not.
func is_in_order_area(cell: Vector2i) -> bool:
    return _in_play_diamond(cell, ORDER_EDGE_INSET)


# Uses the same half-open raster ownership as CellUtil.is_in_diamond.
func _in_play_diamond(cell: Vector2i, extra_inset: float) -> bool:
    var w: float = float(grid_cells.x)
    var h: float = float(grid_cells.y)
    if w <= 0.0 or h <= 0.0:
        return false
    var t: float = float(top_inset) + extra_inset
    var b: float = float(bottom_inset) + extra_inset
    var l: float = float(left_inset) + extra_inset
    var r: float = float(right_inset) + extra_inset
    var center: float = (w + h) * 0.5
    var cx: float = float(cell.x) + 0.5 - center
    var cz: float = float(cell.y) + 0.5 - center
    var sum_axis: float = cx + cz
    var difference_axis: float = cx - cz
    return (
        sum_axis >= -h + t
        and sum_axis < h - b
        and difference_axis >= -w + l
        and difference_axis < w - r
    )


# ========================================
# Camera bounds (map diamond)
# ========================================


# Clamp a world point into the red map diamond using centered constraints:
# a ∈ [-H, H], b ∈ [-W, W], a = ux+uz, b = ux-uz
func clamp_to_map_diamond(p: Vector3) -> Vector3:
    return _clamp_to_diamond(p, grid_cells)


func clamp_to_visible_diamond(p: Vector3, inset_cells: float = 0.0) -> Vector3:
    var cs: float = CellUtil.CELL_SIZE
    var w: float = float(grid_cells.x)
    var h: float = float(grid_cells.y)
    if w <= 0.0 or h <= 0.0:
        return p
    # Visible diamond is a rectangle in the sum/diff frame with per-edge insets:
    # sum ∈ [-h + top, h - bottom], diff ∈ [-w + left, w - right]. A positive
    # `inset_cells` shrinks the diamond (clamps to a point inside the boundary).
    var ux: float = p.x / cs
    var uz: float = p.z / cs
    var a: float = clampf(
        ux + uz, -h + float(top_inset) + inset_cells, h - float(bottom_inset) - inset_cells
    )
    var b: float = clampf(
        ux - uz, -w + float(left_inset) + inset_cells, w - float(right_inset) - inset_cells
    )
    ux = (a + b) * 0.5
    uz = (a - b) * 0.5
    return Vector3(ux * cs, p.y, uz * cs)


func _clamp_to_diamond(p: Vector3, cells: Vector2i) -> Vector3:
    var cs: float = CellUtil.CELL_SIZE
    var w: float = float(cells.x)
    var h: float = float(cells.y)
    if w <= 0.0 or h <= 0.0:
        return p
    # Cell diamond uses half-open [-N, N). Clamp to these bounds.
    var ux: float = p.x / cs
    var uz: float = p.z / cs
    var a: float = clampf(ux + uz, -h, h)
    var b: float = clampf(ux - uz, -w, w)
    ux = (a + b) * 0.5
    uz = (a - b) * 0.5
    return Vector3(ux * cs, p.y, uz * cs)


func get_bounds_rect() -> Rect2:
    var half: float = float(grid_cells.x + grid_cells.y) * CellUtil.CELL_SIZE * 0.5
    return Rect2(-half, -half, half * 2.0, half * 2.0)


# ========================================
# Mesh creation
# ========================================


func create_bounds_nodes() -> void:
    for child in get_children():
        if child.name == "MapSize" or child.name == "VisibleBounds":
            remove_child(child)

    map_bounds_mesh_instance = MeshInstance3D.new()
    map_bounds_mesh_instance.name = "MapSize"
    add_child(map_bounds_mesh_instance)

    visible_bounds_mesh_instance = MeshInstance3D.new()
    visible_bounds_mesh_instance.name = "VisibleBounds"
    add_child(visible_bounds_mesh_instance)


func create_bounds_edges() -> void:
    immediate_map_mesh = ImmediateMesh.new()
    map_bounds_mesh_instance.mesh = immediate_map_mesh

    immediate_visible_mesh = ImmediateMesh.new()
    visible_bounds_mesh_instance.mesh = immediate_visible_mesh

    if not immediate_map_mesh or not immediate_visible_mesh:
        return

    # Red outer bounds: (W-0.5, H-0.5) — inside the cell diamond
    var outer_cells := Vector2(grid_cells.x - 0.5, grid_cells.y - 0.5)
    _draw_diamond_mesh(immediate_map_mesh, _compute_diamond_vertices(outer_cells), line_color)

    # Blue visible bounds: red shrunk by the four edge insets.
    _draw_diamond_mesh(
        immediate_visible_mesh, _compute_visible_diamond_vertices(), visible_bounds_color
    )


func _position_cloud_overlay() -> void:
    # The overlay lives under the loaded map (World/MissionMap/MapBase01), which
    # is not `current_scene`, so it is found by group rather than by path.
    var cloud_overlay: Node3D = get_tree().get_first_node_in_group("cloud_shadow_overlay") as Node3D
    var camera: Camera3D = get_viewport().get_camera_3d()
    if not is_instance_valid(cloud_overlay) or not is_instance_valid(camera):
        return
    cloud_overlay.global_position.x = camera.global_position.x * 0.5
    cloud_overlay.global_position.z = camera.global_position.z * 0.5


func _draw_diamond_mesh(mesh: ImmediateMesh, vertices: Array[Vector3], color: Color) -> void:
    var mat: ORMMaterial3D = ORMMaterial3D.new()
    mat.albedo_color = color
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.render_priority = 2
    mat.no_depth_test = true

    mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)

    var count: int = vertices.size()

    for i in count:
        var from: Vector3 = vertices[i]
        var to: Vector3 = vertices[(i + 1) % count]
        var edge_len: float = from.distance_to(to)
        var steps: int = maxi(ceili(edge_len / CellUtil.CELL_SIZE), 1)
        for step in steps + 1:
            var t: float = float(step) / float(steps)
            var pos: Vector3 = from.lerp(to, t)
            var terrain_h: float = _sample_terrain_height(pos)
            mesh.surface_add_vertex(Vector3(pos.x, terrain_h + 0.02, pos.z))

    mesh.surface_end()


# Diamond vertices centered on the cell diamond.
# The cell diamond uses half-open [-N, N) intervals whose center is at -0.5
# in the sum/diff frame. Converting to world coords: offset = (-CS/2, 0, 0).
func _compute_diamond_vertices(cells: Vector2) -> Array[Vector3]:
    var w: float = cells.x
    var h: float = cells.y
    var cs: float = CellUtil.CELL_SIZE
    var long: float = (w + h) * cs * 0.5
    var small: float = (h - w) * cs * 0.5
    var offset_x: float = -cs * 0.5
    var north: Vector3 = Vector3(-small + offset_x, 0.0, -long)
    var east: Vector3 = Vector3(long + offset_x, 0.0, small)
    var south: Vector3 = Vector3(small + offset_x, 0.0, long)
    var west: Vector3 = Vector3(-long + offset_x, 0.0, -small)
    return [north, east, south, west]


# Visible (blue) diamond with four independent edge insets. The diamond is a
# rectangle in the sum/diff frame bounded by sum ∈ [-h+top, h-bottom] and
# diff ∈ [-w+left, w-right]; the -1 on the upper bounds matches the half-open
# cell raster used by the red map diamond.
func _compute_visible_diamond_vertices() -> Array[Vector3]:
    var w: float = float(grid_cells.x)
    var h: float = float(grid_cells.y)
    var cs: float = CellUtil.CELL_SIZE
    var sum_lo: float = -h + top_inset
    var sum_hi: float = h - bottom_inset - 1.0
    var diff_lo: float = -w + left_inset
    var diff_hi: float = w - right_inset - 1.0
    var north := _sum_diff_to_world(sum_lo, diff_hi, cs)
    var east := _sum_diff_to_world(sum_hi, diff_hi, cs)
    var south := _sum_diff_to_world(sum_hi, diff_lo, cs)
    var west := _sum_diff_to_world(sum_lo, diff_lo, cs)
    return [north, east, south, west]


func _sum_diff_to_world(sum_axis: float, diff_axis: float, cs: float) -> Vector3:
    var cx: float = (sum_axis + diff_axis) * 0.5
    var cz: float = (sum_axis - diff_axis) * 0.5
    return Vector3(cx * cs, 0.0, cz * cs)


func _sample_terrain_height(world_pos: Vector3) -> float:
    if Engine.is_editor_hint():
        return 0.0
    return TerrainSystem.get_height_at_world_smooth(world_pos)
