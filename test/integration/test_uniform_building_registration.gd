extends Node

# Uniform building registration — every building that enters the world through
# the spawn seam is registered once (registry + owner-scoped prerequisites +
# occupancy), and a detached spawn registers nothing.

var _ef: Node = null
var _bm: Node = null
var _root: Node3D = null
var _saved_buildings: Array = []
var _saved_prereqs: Dictionary = {}
var _saved_building_cells: Dictionary = {}


func _setup() -> void:
    _root = Node3D.new()
    Engine.get_main_loop().root.add_child(_root)
    _saved_buildings = _bm._buildings.duplicate()
    _bm._buildings.clear()
    _saved_prereqs = PrerequisiteSystem._player_buildings.duplicate(true)
    PrerequisiteSystem._player_buildings.clear()
    _saved_building_cells = SpatialHash.instance._building_cells.duplicate()
    SpatialHash.instance._building_cells.clear()


func _teardown() -> void:
    if is_instance_valid(_root):
        _root.free()
    _root = null
    _bm._buildings.clear()
    for entry in _saved_buildings:
        _bm._buildings.append(entry)
    PrerequisiteSystem._player_buildings = _saved_prereqs
    SpatialHash.instance._building_cells = _saved_building_cells


func _spawn_building(player_id: int, origin: Vector2i, detached: bool = false) -> Node3D:
    var data: EntityData = _ef.get_entity_data("GDI_CONSTRUCTION_YARD")
    var world_pos: Vector3 = CellUtil.cell_origin_to_world(origin, data.foundation)
    return (
        _ef.spawn(
            "GDI_CONSTRUCTION_YARD",
            {"world_pos": world_pos, "player_id": player_id, "parent": _root, "detached": detached}
        )
        as Node3D
    )


func _registry_count(node: Node3D) -> int:
    var count := 0
    for entry in _bm._buildings:
        if entry.get("node") == node:
            count += 1
    return count


func test_spawn_registers_building_once_for_owner() -> void:
    if _ef == null or _bm == null:
        TestHelper.fail("EntityFactory/BuildingManager not injected")
        return
    _setup()
    var building := _spawn_building(2, Vector2i(10, 10))
    TestHelper.assert_true(building != null, "building spawned")
    if building:
        TestHelper.assert_eq(_registry_count(building), 1, "registered exactly once")
        (
            TestHelper
            . assert_eq(
                PrerequisiteSystem.get_build_count(2, "GDI_CONSTRUCTION_YARD"),
                1,
                "counted for its owner",
            )
        )
        (
            TestHelper
            . assert_eq(
                PrerequisiteSystem.get_build_count(0, "GDI_CONSTRUCTION_YARD"),
                0,
                "not counted for another player",
            )
        )
        (
            TestHelper
            . assert_true(
                not SpatialHash.instance._building_cells.is_empty(),
                "occupancy registered",
            )
        )
    _teardown()


func test_detached_spawn_registers_nothing() -> void:
    if _ef == null or _bm == null:
        TestHelper.fail("EntityFactory/BuildingManager not injected")
        return
    _setup()
    var building := _spawn_building(2, Vector2i(20, 20), true)
    TestHelper.assert_true(building != null, "detached building spawned")
    if building:
        TestHelper.assert_eq(_registry_count(building), 0, "detached not in registry")
    (
        TestHelper
        . assert_eq(
            PrerequisiteSystem.get_build_count(2, "GDI_CONSTRUCTION_YARD"),
            0,
            "detached adds no prerequisite",
        )
    )
    TestHelper.assert_true(
        SpatialHash.instance._building_cells.is_empty(), "detached registers no occupancy"
    )
    _teardown()


func test_registry_cells_exclude_bib() -> void:
    if _ef == null or _bm == null:
        TestHelper.fail("EntityFactory/BuildingManager not injected")
        return
    _setup()
    var ref: EntityData = _ef.get_entity_data("GDI_REFINERY")
    var world_pos: Vector3 = CellUtil.cell_origin_to_world(Vector2i(50, 50), ref.foundation)
    var building := (
        _ef.spawn("GDI_REFINERY", {"world_pos": world_pos, "player_id": 1, "parent": _root})
        as Node3D
    )
    var entry: Dictionary = {}
    for e in _bm._buildings:
        if e.get("node") == building:
            entry = e
            break
    var expected: int = ref.foundation.x * ref.foundation.y - ref.bib_cells.size()
    TestHelper.assert_true(not entry.is_empty(), "refinery registered")
    if not entry.is_empty():
        (
            TestHelper
            . assert_eq(
                (entry.get("cells", []) as Array).size(),
                expected,
                "registry cells exclude bib cells",
            )
        )
    _teardown()


func test_owner_scoped_prereq_counts_two_owners() -> void:
    if _ef == null or _bm == null:
        TestHelper.fail("EntityFactory/BuildingManager not injected")
        return
    _setup()
    _spawn_building(1, Vector2i(30, 30))
    _spawn_building(2, Vector2i(40, 40))
    (
        TestHelper
        . assert_eq(
            PrerequisiteSystem.get_build_count(1, "GDI_CONSTRUCTION_YARD"),
            1,
            "player 1 counted",
        )
    )
    (
        TestHelper
        . assert_eq(
            PrerequisiteSystem.get_build_count(2, "GDI_CONSTRUCTION_YARD"),
            1,
            "player 2 counted",
        )
    )
    TestHelper.assert_eq(_bm._buildings.size(), 2, "two registry entries")
    _teardown()
