extends SubViewportContainer

@export_group("Minimap")
@export var minimap_size: Vector2i = Vector2i(200, 200)
@export var terrain_color: Color = Color(0.3, 0.6, 0.3)
@export var slope_color: Color = Color(0.5, 0.4, 0.3)
@export var water_color: Color = Color(0.2, 0.4, 0.8)

var _sub_viewport: SubViewport
var _camera: Camera3D
var _terrain_mesh: MeshInstance3D
var _viewport_rect_mesh: MeshInstance3D
var _entity_dots_mesh: MeshInstance3D
var _entity_dots_material: ORMMaterial3D
var _needs_rebuild: bool = false
var _game_camera: Camera3D = null
var _game_camera_pivot: Node3D = null


func _ready() -> void:
    _setup_container()
    _setup_viewport()
    _setup_camera()
    _setup_terrain_visualization()
    _setup_viewport_rect()
    _setup_entity_dots()
    TerrainSystem.cell_changed.connect(_on_cell_changed)
    TerrainSystem.grid_initialized.connect(_on_grid_initialized)


func _process(_delta: float) -> void:
    if _needs_rebuild:
        _needs_rebuild = false
        _update_visualization()
    _update_camera_size()
    _update_viewport_rect()
    _update_entity_dots()


func set_game_camera(cam: Camera3D, pivot: Node3D) -> void:
    _game_camera = cam
    _game_camera_pivot = pivot


func _setup_container() -> void:
    custom_minimum_size = minimap_size
    size = minimap_size
    stretch = false
    size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    size_flags_vertical = Control.SIZE_SHRINK_BEGIN


func _setup_viewport() -> void:
    _sub_viewport = SubViewport.new()
    _sub_viewport.name = "MinimapViewport"
    _sub_viewport.size = minimap_size
    _sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    _sub_viewport.own_world_3d = true
    add_child(_sub_viewport)


func _setup_camera() -> void:
    _camera = Camera3D.new()
    _camera.name = "MinimapCamera"
    _camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    _camera.rotation_degrees = Vector3(-90, 45, 0)
    _camera.position = Vector3(0.0, 100.0, 0.0)
    _update_camera_size()
    _sub_viewport.add_child(_camera)


func _update_camera_size() -> void:
    var cells := TerrainSystem.grid_cells
    var total: float = float(cells.x + cells.y) * CellUtil.CELL_SIZE
    _camera.size = total


func _setup_terrain_visualization() -> void:
    _terrain_mesh = MeshInstance3D.new()
    _terrain_mesh.name = "TerrainVisualization"
    _sub_viewport.add_child(_terrain_mesh)
    _update_visualization()


func _setup_viewport_rect() -> void:
    _viewport_rect_mesh = MeshInstance3D.new()
    _viewport_rect_mesh.name = "ViewportRect"
    var mat := ORMMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color.WHITE
    mat.no_depth_test = true
    mat.render_priority = 10
    _viewport_rect_mesh.material_override = mat
    _sub_viewport.add_child(_viewport_rect_mesh)
    _update_viewport_rect()


func _is_in_diamond(world_pos: Vector3) -> bool:
    var cell := CellUtil.world_to_cell(world_pos)
    return CellUtil.is_in_diamond(cell, TerrainSystem.grid_cells)


func _setup_entity_dots() -> void:
    _entity_dots_mesh = MeshInstance3D.new()
    _entity_dots_mesh.name = "EntityDots"
    _entity_dots_material = ORMMaterial3D.new()
    _entity_dots_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _entity_dots_material.vertex_color_use_as_albedo = true
    _sub_viewport.add_child(_entity_dots_mesh)
    _update_entity_dots()


## One small world-axis-aligned quad per entity that resolves to a minimap
## color (see ArtData.minimap_color). Rebuilt every frame like the viewport
## rect — entity counts in the editor are small.
func _update_entity_dots() -> void:
    var mesh := ImmediateMesh.new()
    var half: float = CellUtil.CELL_SIZE * 0.25
    var added := false
    for entry in _minimap_entities():
        var entity: Node3D = entry.get("node")
        if not is_instance_valid(entity) or not entity is Node3D:
            continue
        var color: Variant = _resolve_entity_color(entity, entry.get("player_id", -1))
        if color == null:
            continue
        if not added:
            mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _entity_dots_material)
            added = true
        _add_dot(mesh, (entity as Node3D).global_position + Vector3(0.0, 0.3, 0.0), half, color)
    if added:
        mesh.surface_end()
    _entity_dots_mesh.mesh = mesh


## Editor entities for minimap dots. The MapEditor tracks its content in
## `_painted_entities` (detached entities are not in the live `entities` group),
## so read that set from the owning editor when present, else the live group.
func _minimap_entities() -> Array:
    var ancestor := get_parent()
    while ancestor:
        var painted: Variant = ancestor.get("_painted_entities")
        if painted is Dictionary:
            var out: Array = []
            for key in painted:
                var entry: Variant = painted[key]
                if not entry is Dictionary:
                    continue
                var node: Variant = entry.get("node")
                if not is_instance_valid(node):
                    continue
                var pid: int = -1
                var data: Variant = entry.get("data")
                if data is Dictionary:
                    pid = int(data.get("player_id", -1))
                out.append({"node": node, "player_id": pid})
            return out
        ancestor = ancestor.get_parent()
    var live: Array = []
    for entity in get_tree().get_nodes_in_group("entities"):
        live.append({"node": entity, "player_id": -1})
    return live


## (entity) → minimap Color or null, combining ArtData resolution with the
## owner player's color lookup. Prefers the owner id from the painted data,
## falling back to the live StatsComponent.
func _resolve_entity_color(entity: Node, player_id_hint: int = -1) -> Variant:
    var art_comp := entity.get_node_or_null("ArtComponent")
    var art: ArtData = (art_comp as ArtComponent).art_data if art_comp else null
    var owner_color: Variant = null
    var pid := player_id_hint
    if pid < 0:
        var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
        if stats:
            pid = stats.player_id
    if pid >= 0:
        var player := PlayerManager.get_player_data(pid)
        if player:
            owner_color = player.color
    return ArtData.minimap_color(art, owner_color)


func _add_dot(mesh: ImmediateMesh, center: Vector3, half: float, color: Variant) -> void:
    var x0 := center.x - half
    var x1 := center.x + half
    var z0 := center.z - half
    var z1 := center.z + half
    var c: Color = color
    for corner in [
        Vector3(x0, center.y, z0),
        Vector3(x1, center.y, z0),
        Vector3(x1, center.y, z1),
        Vector3(x0, center.y, z0),
        Vector3(x1, center.y, z1),
        Vector3(x0, center.y, z1),
    ]:
        mesh.surface_add_color(c)
        mesh.surface_add_vertex(corner)


func _update_visualization() -> void:
    var cells: Dictionary = TerrainSystem.get_all_cells()
    if cells.is_empty():
        return
    var mesh := ImmediateMesh.new()
    var terrain_material := ORMMaterial3D.new()
    terrain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    var added := false
    for key in cells:
        var parts: PackedStringArray = key.split(",")
        if parts.size() != 2:
            continue
        var cell := Vector2i(int(parts[0]), int(parts[1]))
        var world_pos := CellUtil.cell_to_world(cell)
        if not _is_in_diamond(world_pos):
            continue
        if not added:
            mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, terrain_material)
            added = true
        var data: Dictionary = cells[key]
        var height: int = data.get("height", 0)
        var terrain_type: String = data.get("type", "clear")
        var color := terrain_color
        if terrain_type == "slope":
            color = slope_color
        elif terrain_type == "water":
            color = water_color
        terrain_material.albedo_color = color
        var half_size := CellUtil.CELL_SIZE * 0.5
        var y: float = float(height) * TerrainSystem.HEIGHT_STEP + 0.1
        mesh.surface_add_vertex(Vector3(world_pos.x - half_size, y, world_pos.z - half_size))
        mesh.surface_add_vertex(Vector3(world_pos.x + half_size, y, world_pos.z - half_size))
        mesh.surface_add_vertex(Vector3(world_pos.x + half_size, y, world_pos.z + half_size))
        mesh.surface_add_vertex(Vector3(world_pos.x - half_size, y, world_pos.z - half_size))
        mesh.surface_add_vertex(Vector3(world_pos.x + half_size, y, world_pos.z + half_size))
        mesh.surface_add_vertex(Vector3(world_pos.x - half_size, y, world_pos.z + half_size))
    if added:
        mesh.surface_end()
    _terrain_mesh.mesh = mesh


func _update_viewport_rect() -> void:
    var y: float = 10.0
    var half_size: float = 10.0
    var center := Vector3.ZERO
    if _game_camera_pivot:
        center = _game_camera_pivot.global_position
    if _game_camera:
        half_size = _game_camera.size
    var mesh := ImmediateMesh.new()
    var mat := ORMMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color.WHITE
    mat.no_depth_test = true
    mat.render_priority = 10
    mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
    # Rotated 45° so it reads as an axis-aligned square under the 45°-yawed camera.
    var d: float = half_size * CellUtil.SQRT2
    mesh.surface_add_vertex(Vector3(center.x, y, center.z - d))
    mesh.surface_add_vertex(Vector3(center.x + d, y, center.z))
    mesh.surface_add_vertex(Vector3(center.x, y, center.z + d))
    mesh.surface_add_vertex(Vector3(center.x - d, y, center.z))
    mesh.surface_add_vertex(Vector3(center.x, y, center.z - d))
    mesh.surface_end()
    _viewport_rect_mesh.mesh = mesh


func _on_cell_changed(_cell_key: String, _cell_data: Dictionary) -> void:
    _needs_rebuild = true


func _on_grid_initialized() -> void:
    _update_camera_size()
    _needs_rebuild = true


func get_clicked_world_pos(click_pos: Vector2) -> Vector3:
    var viewport_click: Vector2 = click_pos * Vector2(size) / Vector2(minimap_size)
    var ray_origin := _camera.project_ray_origin(viewport_click)
    var ray_direction := _camera.project_ray_normal(viewport_click)
    var plane := Plane(Vector3.UP, 0.0)
    var intersection: Variant = plane.intersects_ray(ray_origin, ray_direction)
    return intersection if intersection else Vector3.ZERO
