extends Node

# End-to-end MapEditor tests — instantiate the real scene, trigger _ready(),
# exercise _apply_new_map(), and verify the full pipeline including TerrainRenderer.

const MAP_EDITOR_SCENE: PackedScene = preload("res://scenes/editor/MapEditor.tscn")

var _ts: Node = null

# ── helpers ──────────────────────────────────────────────────────────


func _create_map_editor() -> Node3D:
    var editor: Node3D = MAP_EDITOR_SCENE.instantiate()
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    tree.root.add_child(editor)
    return editor


func _cleanup_map_editor(editor: Node3D) -> void:
    if is_instance_valid(editor):
        if editor.is_inside_tree():
            editor.get_parent().remove_child(editor)
        editor.queue_free()


func _find_terrain_renderer(editor: Node3D) -> Node:
    for child: Node in editor.get_children():
        if child.name == "TerrainRenderer":
            return child
    return null


func _expected_cell_count(w: int, h: int) -> int:
    return 2 * w * h


func _count_ghost_cells(cells: Dictionary, grid_cells: Vector2i) -> int:
    var ghost_count: int = 0
    for key: String in cells:
        var parts := key.split(",")
        if parts.size() != 2:
            continue
        var cell := Vector2i(int(parts[0]), int(parts[1]))
        if not CellUtil.is_in_diamond(cell, grid_cells):
            ghost_count += 1
    return ghost_count


func _renderer_ghost_count(renderer: Node, grid_cells: Vector2i) -> int:
    var instance_data: Dictionary = renderer.get("_instance_data")
    if instance_data == null:
        return 0
    var ghost_count: int = 0
    for key: String in instance_data:
        var parts := key.split(",")
        if parts.size() != 2:
            continue
        var cell := Vector2i(int(parts[0]), int(parts[1]))
        if not CellUtil.is_in_diamond(cell, grid_cells):
            ghost_count += 1
    return ghost_count


# ── A. Scene-instantiated MapEditor tests ────────────────────────────


func test_scene_ready_produces_correct_cell_count() -> void:
    if _ts == null:
        _assert_true(false, "TerrainSystem is injected")
        return
    _ts.clear()
    _ts.init_grid(50, 50)
    var editor: Node3D = _create_map_editor()
    var actual: int = _ts.get_all_cells().size()
    var expected: int = _expected_cell_count(50, 50)
    _cleanup_map_editor(editor)
    _ts.clear()
    _ts.init_grid(50, 50)
    _assert_eq(actual, expected, "50x50 _ready() produces exactly 2*W*H cells")


func test_scene_terrain_renderer_connected_and_rendered() -> void:
    if _ts == null:
        _assert_true(false, "TerrainSystem is injected")
        return
    _ts.clear()
    _ts.init_grid(50, 50)
    var editor: Node3D = _create_map_editor()
    var renderer: Node = _find_terrain_renderer(editor)
    var has_renderer: bool = renderer != null
    var connected: bool = false
    var instance_count: int = 0
    if has_renderer:
        connected = TerrainSystem.cell_changed.is_connected(Callable(renderer, "_on_cell_changed"))
        var instance_data: Dictionary = renderer.get("_instance_data")
        instance_count = instance_data.size() if instance_data != null else -1
    var expected: int = _expected_cell_count(50, 50)
    _cleanup_map_editor(editor)
    _ts.clear()
    _ts.init_grid(50, 50)
    _assert_true(has_renderer, "MapEditor.tscn has TerrainRenderer child")
    _assert_true(connected, "TerrainRenderer connected to cell_changed")
    _assert_eq(instance_count, expected, "TerrainRenderer rendered exactly 2*W*H cells")


func test_scene_no_ghost_cells_after_ready() -> void:
    if _ts == null:
        _assert_true(false, "TerrainSystem is injected")
        return
    _ts.clear()
    _ts.init_grid(50, 50)
    var editor: Node3D = _create_map_editor()
    var renderer: Node = _find_terrain_renderer(editor)
    var grid_cells: Vector2i = _ts.grid_cells
    var terrain_ghosts: int = _count_ghost_cells(_ts.get_all_cells(), grid_cells)
    var renderer_ghosts: int = _renderer_ghost_count(renderer, grid_cells) if renderer else -1
    _cleanup_map_editor(editor)
    _ts.clear()
    _ts.init_grid(50, 50)
    _assert_eq(terrain_ghosts, 0, "TerrainSystem has no cells outside diamond")
    _assert_eq(renderer_ghosts, 0, "TerrainRenderer has no instances outside diamond")


# ── B. _apply_new_map() through real instance ────────────────────────


func test_apply_new_map_cell_count_matches_formula() -> void:
    if _ts == null:
        _assert_true(false, "TerrainSystem is injected")
        return
    _ts.clear()
    _ts.init_grid(50, 50)
    var editor: Node3D = _create_map_editor()
    editor._apply_new_map(21, 20, 0, 0, 11, 12)
    var actual: int = _ts.get_all_cells().size()
    var expected: int = _expected_cell_count(21, 20)

    _cleanup_map_editor(editor)
    _ts.clear()
    _ts.init_grid(50, 50)
    _assert_eq(actual, expected, "21x20 _apply_new_map produces exactly 2*W*H cells")


func test_apply_new_map_terrain_renderer_in_sync() -> void:
    if _ts == null:
        _assert_true(false, "TerrainSystem is injected")
        return
    _ts.clear()
    _ts.init_grid(50, 50)
    var editor: Node3D = _create_map_editor()
    editor._apply_new_map(50, 50, 0, 0, 40, 42)
    var renderer: Node = _find_terrain_renderer(editor)
    var grid_cells := Vector2i(50, 50)
    var expected: int = _expected_cell_count(50, 50)
    var actual_terrain: int = _ts.get_all_cells().size()
    var instance_count: int = -1
    var renderer_ghosts: int = -1
    if renderer:
        var instance_data: Dictionary = renderer.get("_instance_data")
        instance_count = instance_data.size()
        renderer_ghosts = _renderer_ghost_count(renderer, grid_cells)
    _cleanup_map_editor(editor)
    _ts.clear()
    _ts.init_grid(50, 50)
    _assert_eq(actual_terrain, expected, "TerrainSystem cell count matches 2*W*H")
    _assert_eq(instance_count, expected, "TerrainRenderer instance count matches 2*W*H")
    _assert_eq(renderer_ghosts, 0, "TerrainRenderer has no ghost instances")


func test_apply_new_map_second_call_clears_stale() -> void:
    if _ts == null:
        _assert_true(false, "TerrainSystem is injected")
        return
    _ts.clear()
    _ts.init_grid(50, 50)
    var editor: Node3D = _create_map_editor()
    editor._apply_new_map(50, 50, 0, 0, 40, 42)
    editor._apply_new_map(21, 20, 0, 0, 11, 12)
    var renderer: Node = _find_terrain_renderer(editor)
    var grid_cells := Vector2i(21, 20)
    var expected: int = _expected_cell_count(21, 20)
    var actual_terrain: int = _ts.get_all_cells().size()
    var instance_count: int = -1
    var renderer_ghosts: int = -1
    if renderer:
        var instance_data: Dictionary = renderer.get("_instance_data")
        instance_count = instance_data.size()
        renderer_ghosts = _renderer_ghost_count(renderer, grid_cells)
    _cleanup_map_editor(editor)
    _ts.clear()
    _ts.init_grid(50, 50)
    _assert_eq(actual_terrain, expected, "Second call TerrainSystem has correct count")
    _assert_eq(instance_count, expected, "Second call TerrainRenderer has correct count")
    _assert_eq(renderer_ghosts, 0, "Second call TerrainRenderer has no ghost instances")


# ── C. BoundsSystem + EditorGrid integration ────────────────────────


## Map files authored with enemy buildings must load them into the editor
## (regression: FogRenderer._on_node_added hid buildings whose fog state was
## shrouded, since the editor has no revealers — unlike the gameplay batch
## path, the per-node hook lacked the is_map_editor guard).
func test_loaded_buildings_visible_in_editor() -> void:
    if _ts == null:
        _assert_true(false, "TerrainSystem is injected")
        return
    _ts.clear()
    _ts.init_grid(50, 50)
    var editor: Node3D = _create_map_editor()
    var saveload: Node = editor.get_node_or_null("EditorSaveLoad")
    if saveload == null:
        _assert_true(false, "EditorSaveLoad exists on MapEditor scene")
    else:
        saveload.call("_on_load_file_selected", "res://games/ts/assets/test_map01.json")
        var building_nodes: Array = []
        for child in editor.get_children():
            var stats := child.get_node_or_null("StatsComponent") as StatsComponent
            if stats and stats.entity_type == EntityData.EntityType.BUILDING:
                building_nodes.append(child)
        _assert_true(building_nodes.size() >= 4, "all four GDI buildings loaded")
        for b in building_nodes:
            var n3d := b as Node3D
            _assert_true(
                n3d.visible,
                "building '%s' is visible after load (not hidden by fog renderer)" % b.name,
            )
        var painted_count: int = editor._painted_entities.size()
        _assert_true(painted_count >= 318, "all map entities registered in _painted_entities")
        _assert_eq(
            SpatialHash.instance._building_cells.size(),
            0,
            "editor load registers no live occupancy cells",
        )
    _cleanup_map_editor(editor)
    _ts.clear()
    _ts.init_grid(50, 50)


func test_apply_new_map_bounds_and_grid_updated() -> void:
    if _ts == null:
        _assert_true(false, "TerrainSystem is injected")
        return
    _ts.clear()
    _ts.init_grid(50, 50)
    var editor: Node3D = _create_map_editor()
    editor._apply_new_map(21, 20, 0, 0, 5, 5, 4, 4)
    var gc: Vector2i = _ts.grid_cells
    var bounds_ok: bool = (
        gc == Vector2i(21, 20)
        and BoundsSystem.left_inset == 5
        and BoundsSystem.right_inset == 5
        and BoundsSystem.top_inset == 4
        and BoundsSystem.bottom_inset == 4
    )
    var grid_node: Node = editor.get_node_or_null("EditorGrid")
    var has_grid: bool = grid_node != null
    var grid_has_mesh: bool = false
    if has_grid:
        var overlay: Node3D = editor.get_node_or_null("GridOverlay")
        if overlay and overlay is MeshInstance3D:
            grid_has_mesh = overlay.mesh != null
    _cleanup_map_editor(editor)
    _ts.clear()
    _ts.init_grid(50, 50)
    _assert_true(bounds_ok, "BoundsSystem updated to 21x20 grid_cells and valid visible insets")
    _assert_true(has_grid, "EditorGrid child exists")
    _assert_true(grid_has_mesh, "EditorGrid has a grid mesh after _apply_new_map")


# ── assertions ───────────────────────────────────────────────────────


func _assert_true(value: bool, message: String) -> void:
    TestHelper.assert_true(value, message)


func _assert_eq(got: Variant, expected: Variant, message: String) -> void:
    TestHelper.assert_eq(got, expected, message)
