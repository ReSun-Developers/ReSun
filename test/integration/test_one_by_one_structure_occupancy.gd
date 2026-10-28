extends Node

# 1x1 structure occupancy regression (issue #522). A structure with a 1x1
# foundation must register its cell like every larger structure.

var _ef: Node = null
var _sh: Node = null
var _root: Node3D = null
var _saved_buildings: Array = []
var _saved_prereqs: Dictionary = {}
var _saved_building_cells: Dictionary = {}
var _saved_bib_cells: Dictionary = {}

const CELL: Vector2i = Vector2i(60, 60)
const SIDE_A: Vector2i = Vector2i(57, 60)
const SIDE_B: Vector2i = Vector2i(63, 60)


func _setup() -> void:
    _root = Node3D.new()
    Engine.get_main_loop().root.add_child(_root)
    TerrainSystem.init_grid(64, 64)
    _clear_corridor()
    _saved_buildings = BuildingManager._buildings.duplicate()
    BuildingManager._buildings.clear()
    _saved_prereqs = PrerequisiteSystem._player_buildings.duplicate(true)
    PrerequisiteSystem._player_buildings.clear()
    _saved_building_cells = SpatialHash.instance._building_cells.duplicate()
    SpatialHash.instance._building_cells.clear()
    _saved_bib_cells = SpatialHash.instance._bib_cells.duplicate()
    SpatialHash.instance._bib_cells.clear()
    SpatialHash.instance.rebuild()


func _teardown() -> void:
    if is_instance_valid(_root):
        _root.free()
    _root = null
    BuildingManager._buildings.clear()
    for entry in _saved_buildings:
        BuildingManager._buildings.append(entry)
    PrerequisiteSystem._player_buildings = _saved_prereqs
    SpatialHash.instance._building_cells = _saved_building_cells
    SpatialHash.instance._bib_cells = _saved_bib_cells
    SpatialHash.instance.rebuild()


func _clear_corridor() -> void:
    for x in range(SIDE_A.x - 1, SIDE_B.x + 1):
        for z in range(CELL.y - 2, CELL.y + 3):
            TerrainSystem.set_cell_type(Vector2i(x, z), "clear")


func _spawn(entity_id: String) -> Node3D:
    return (
        (
            _ef
            . spawn(
                entity_id,
                {"world_pos": CellUtil.cell_to_world(CELL), "player_id": 0, "parent": _root},
            )
        )
        as Node3D
    )


func _path_avoids_cell() -> bool:
    var blocked: Dictionary = SpatialHash.instance.get_blocked_cells()
    var path: PackedVector3Array = Pathfinder.find_path(
        CellUtil.cell_to_world(SIDE_A), CellUtil.cell_to_world(SIDE_B), blocked
    )
    if path.is_empty():
        return false
    for waypoint: Vector3 in path:
        if CellUtil.world_to_cell(waypoint) == CELL:
            return false
    return true


func test_one_by_one_silo_registers_its_cell() -> void:
    if _ef == null or _sh == null:
        TestHelper.fail("EntityFactory/SpatialHash not injected")
        return
    _setup()
    var free_before: bool = _sh.is_cell_free_for_build(CELL)
    var building_before: bool = _sh.get_cell_occupancy(CELL).building
    var silo := _spawn("GDI_SILO")
    var has_component: bool = silo != null and silo.get_node_or_null("FoundationComponent") != null
    var occ: SpatialHash.CellOccupancy = _sh.get_cell_occupancy(CELL)
    var build_blocked: bool = not _sh.is_cell_free_for_build(CELL)
    var exit_blocked: bool = not _sh.is_cell_free_for_unit_exit(CELL)
    var listed: bool = _sh.get_blocked_cells().has(CellUtil.cell_key(CELL))
    var avoids: bool = _path_avoids_cell()
    _teardown()
    TestHelper.assert_true(
        free_before and not building_before, "1x1 cell is free before the silo spawns"
    )
    TestHelper.assert_true(has_component, "1x1 silo carries a FoundationComponent")
    TestHelper.assert_true(occ.building, "1x1 silo reports building occupancy")
    TestHelper.assert_true(build_blocked, "1x1 silo blocks building placement")
    TestHelper.assert_true(exit_blocked, "1x1 silo blocks unit exit")
    TestHelper.assert_true(listed, "1x1 silo cell appears in blocked cells")
    TestHelper.assert_true(avoids, "pathfinder routes around the 1x1 silo cell")


func test_one_by_one_wall_registers_its_cell() -> void:
    if _ef == null or _sh == null:
        TestHelper.fail("EntityFactory/SpatialHash not injected")
        return
    _setup()
    var wall := _spawn("GDI_WALL")
    var is_building: bool = false
    if wall != null:
        var stats := wall.get_node_or_null("StatsComponent") as StatsComponent
        is_building = stats != null and stats.entity_type == EntityData.EntityType.BUILDING
    var occ: SpatialHash.CellOccupancy = _sh.get_cell_occupancy(CELL)
    var build_blocked: bool = not _sh.is_cell_free_for_build(CELL)
    _teardown()
    TestHelper.assert_true(is_building, "GDI_WALL resolves to the BUILDING structure")
    TestHelper.assert_true(occ.building, "1x1 wall reports building occupancy")
    TestHelper.assert_true(build_blocked, "1x1 wall blocks building placement")


func test_ground_shot_resolves_one_by_one_structure() -> void:
    if _ef == null or _sh == null:
        TestHelper.fail("EntityFactory/SpatialHash not injected")
        return
    _setup()
    var silo := _spawn("GDI_SILO")
    var spawned: bool = silo != null
    _sh.rebuild()
    var victim: Node3D = _sh.resolve_cell_victim(CELL, CellUtil.cell_to_world(CELL), null)
    var resolved: bool = victim != null and victim == silo
    _teardown()
    TestHelper.assert_true(spawned, "silo spawns for the ground-shot case")
    TestHelper.assert_true(resolved, "ground shot at the 1x1 cell resolves the structure")


func test_non_solid_one_by_one_building_does_not_block() -> void:
    if _ef == null or _sh == null:
        TestHelper.fail("EntityFactory/SpatialHash not injected")
        return
    _setup()
    var pavement := _spawn("GDI_PAVEMENT")
    var spawned: bool = pavement != null
    var occ: SpatialHash.CellOccupancy = _sh.get_cell_occupancy(CELL)
    var build_free: bool = _sh.is_cell_free_for_build(CELL)
    var exit_free: bool = _sh.is_cell_free_for_unit_exit(CELL)
    var listed: bool = _sh.get_blocked_cells().has(CellUtil.cell_key(CELL))
    _teardown()
    TestHelper.assert_true(spawned, "pavement spawns")
    TestHelper.assert_true(not occ.building, "pavement registers no building occupancy")
    TestHelper.assert_true(build_free, "pavement cell stays buildable")
    TestHelper.assert_true(exit_free, "pavement cell stays walkable")
    TestHelper.assert_true(not listed, "pavement cell is not a blocked cell")
