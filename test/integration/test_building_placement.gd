extends Node

# Building placement integration test — placement registers cells, pathfinder avoids them

var _bm: Node = null


func test_centered_building_foundation_can_be_placed_and_registered() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    SpatialHash.instance._building_cells.clear()
    TerrainSystem.init_grid(64, 64)
    var building_type := EntityData.new()
    building_type.id = "test_building"
    building_type.foundation = Vector2i(2, 2)
    building_type.entity_type = EntityData.EntityType.BUILDING
    building_type.strength = 100
    building_type.owner = ["GDI"]
    # A 64x64 map is centered around cell coordinate (64,64), not (32,32).
    var origin := Vector2i(64, 64)
    for dx in 2:
        for dz in 2:
            var cell := origin + Vector2i(dx, dz)
            var key := "%d,%d" % [cell.x, cell.y]
            TerrainSystem._cells[key] = {
                "height": 0, "type": "clear", "variant": 1, "direction": "", "rotation": 0.0
            }
    var can_place: bool = _bm.can_place(building_type, origin)
    if can_place:
        var cells: Array[Vector2i] = []
        for dx in 2:
            for dz in 2:
                cells.append(origin + Vector2i(dx, dz))
        SpatialHash.instance.register_building_cells(cells)
    var blocked := SpatialHash.instance.get_blocked_cells()
    var sh := SpatialHash.instance
    var has_origin: bool = blocked.has(CellUtil.cell_key(Vector2i(64, 64)))
    var has_east: bool = blocked.has(CellUtil.cell_key(Vector2i(65, 64)))
    var has_south: bool = blocked.has(CellUtil.cell_key(Vector2i(64, 65)))
    var has_south_east: bool = blocked.has(CellUtil.cell_key(Vector2i(65, 65)))
    SpatialHash.instance._building_cells.clear()
    (
        TestHelper
        . assert_true(
            can_place and has_origin and has_east and has_south and has_south_east,
            (
                "centered foundation placement registers its four real cells: "
                + (
                    "can_place=%s, cells=%s%s%s%s"
                    % [can_place, has_origin, has_east, has_south, has_south_east]
                )
            ),
        )
    )


func test_pathfinder_routes_around_centered_building_cell() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    SpatialHash.instance._building_cells.clear()
    TerrainSystem.init_grid(64, 64)
    var cells: Array[Vector2i] = [Vector2i(64, 64)]
    SpatialHash.instance.register_building_cells(cells)
    var blocked: Dictionary = SpatialHash.instance.get_blocked_cells()
    var start_cell: Vector2i = Vector2i(60, 64)
    var end_cell: Vector2i = Vector2i(68, 64)
    var start_world: Vector3 = CellUtil.cell_to_world(start_cell)
    var end_world: Vector3 = CellUtil.cell_to_world(end_cell)
    var path: PackedVector3Array = Pathfinder.find_path(start_world, end_world, blocked)
    var avoids_building: bool = not path.is_empty()
    var reaches_destination: bool = false
    var bad_cell: Vector2i = Vector2i.ZERO
    var gc: Vector2i = TerrainSystem.grid_cells
    for waypoint: Vector3 in path:
        var cell: Vector2i = CellUtil.world_to_cell(waypoint, gc)
        var key: int = CellUtil.cell_key(cell)
        if blocked.has(key):
            avoids_building = false
            bad_cell = cell
            break
        if cell == end_cell:
            reaches_destination = true
    SpatialHash.instance._building_cells.clear()
    (
        TestHelper
        . assert_true(
            avoids_building and reaches_destination,
            (
                "pathfinder reaches destination around centered building cell: "
                + "reaches=%s, blocked cell=%s, path=%s" % [reaches_destination, bad_cell, path]
            ),
        )
    )


func test_building_foundation_registers_cells_on_ready():
    SpatialHash.instance._building_cells.clear()
    TerrainSystem.init_grid(64, 64)
    var origin := Vector2i(60, 60)
    var entity := Node3D.new()
    entity.name = "TestBuilding"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.entity_type = EntityData.EntityType.BUILDING
    entity.add_child(stats)
    var fc := FoundationComponent.new()
    fc.foundation = Vector2i(3, 3)
    entity.add_child(fc)
    entity.position = CellUtil.cell_origin_to_world(origin, fc.foundation)
    SpatialHash.instance.add_child(entity)
    var sh := SpatialHash.instance
    var blocked := sh.get_blocked_cells()
    var has_origin: bool = blocked.has(CellUtil.cell_key(origin))
    var has_edge: bool = blocked.has(CellUtil.cell_key(origin + Vector2i(2, 2)))
    SpatialHash.instance.remove_child(entity)
    var cleared: bool = not sh.get_blocked_cells().has(CellUtil.cell_key(origin))
    entity.free()
    SpatialHash.instance._building_cells.clear()
    (
        TestHelper
        . assert_true(
            has_origin and has_edge and cleared,
            (
                "building FoundationComponent registers foundation cells on _ready: "
                + (
                    "has_origin=%s has_edge=%s cleared=%s (should all be true)"
                    % [has_origin, has_edge, cleared]
                )
            ),
        )
    )


func test_non_building_foundation_does_not_register_cells():
    SpatialHash.instance._building_cells.clear()
    TerrainSystem.init_grid(64, 64)
    var entity := Node3D.new()
    entity.name = "TestUnit"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.entity_type = EntityData.EntityType.VEHICLE
    entity.add_child(stats)
    var fc := FoundationComponent.new()
    fc.foundation = Vector2i(3, 3)
    entity.add_child(fc)
    entity.position = Vector3(11.0, 0.0, 11.0)
    SpatialHash.instance.add_child(entity)
    var sh := SpatialHash.instance
    var building_cell_count := sh.get_building_cells().size()
    SpatialHash.instance.remove_child(entity)
    entity.free()
    SpatialHash.instance._building_cells.clear()
    (
        TestHelper
        . assert_true(
            building_cell_count == 0,
            (
                "non-building FoundationComponent does not register cells: "
                + "FC registered %d cells for non-building (should be 0)" % building_cell_count
            ),
        )
    )


func test_preview_building_does_not_register_cells():
    SpatialHash.instance._building_cells.clear()
    TerrainSystem.init_grid(64, 64)
    var entity := Node3D.new()
    entity.name = "TestPreview"
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.entity_type = EntityData.EntityType.BUILDING
    entity.add_child(stats)
    var fc := FoundationComponent.new()
    fc.foundation = Vector2i(3, 3)
    entity.add_child(fc)
    entity.set_meta("detached", true)
    entity.position = Vector3(11.0, 0.0, 11.0)
    SpatialHash.instance.add_child(entity)
    var sh := SpatialHash.instance
    var building_cell_count := sh.get_building_cells().size()
    SpatialHash.instance.remove_child(entity)
    entity.free()
    SpatialHash.instance._building_cells.clear()
    (
        TestHelper
        . assert_true(
            building_cell_count == 0,
            (
                "preview building FoundationComponent does not register cells: "
                + "preview FC registered %d cells (should be 0)" % building_cell_count
            ),
        )
    )


func test_map_loaded_building_registers_foundation_cells():
    SpatialHash.instance._building_cells.clear()
    TerrainSystem.init_grid(64, 64)
    var building := EntityFactory.create_entity("GDI_CONSTRUCTION_YARD")
    if building == null:
        TestHelper.fail("EntityFactory could not create GDI_CONSTRUCTION_YARD")
        return
    var origin := Vector2i(60, 60)
    building.position = CellUtil.cell_origin_to_world(origin, Vector2i(3, 3))
    SpatialHash.instance.add_child(building)
    var sh := SpatialHash.instance
    var blocked := sh.get_blocked_cells()
    var has_origin: bool = blocked.has(CellUtil.cell_key(origin))
    var has_center: bool = blocked.has(CellUtil.cell_key(origin + Vector2i(1, 1)))
    var has_corner: bool = blocked.has(CellUtil.cell_key(origin + Vector2i(2, 2)))
    SpatialHash.instance.remove_child(building)
    building.free()
    SpatialHash.instance._building_cells.clear()
    (
        TestHelper
        . assert_true(
            has_origin and has_center and has_corner,
            (
                "map-loaded building registers all 3x3 foundation cells: "
                + (
                    "origin=%s center=%s corner=%s (should all be true)"
                    % [has_origin, has_center, has_corner]
                )
            ),
        )
    )


func test_map_loaded_building_blocks_pathfinding():
    SpatialHash.instance._building_cells.clear()
    TerrainSystem.init_grid(64, 64)
    var building := EntityFactory.create_entity("GDI_CONSTRUCTION_YARD")
    if building == null:
        TestHelper.fail("EntityFactory could not create GDI_CONSTRUCTION_YARD")
        return
    var origin := Vector2i(60, 60)
    building.position = CellUtil.cell_origin_to_world(origin, Vector2i(3, 3))
    SpatialHash.instance.add_child(building)
    var blocked: Dictionary = SpatialHash.instance.get_blocked_cells()
    var start_world: Vector3 = CellUtil.cell_to_world(Vector2i(57, 60))
    var end_world: Vector3 = CellUtil.cell_to_world(Vector2i(63, 60))
    var path: PackedVector3Array = Pathfinder.find_path(start_world, end_world, blocked)
    var avoids_building := not path.is_empty()
    var bad_cell: Vector2i = Vector2i.ZERO
    for waypoint: Vector3 in path:
        var cell: Vector2i = CellUtil.world_to_cell(waypoint)
        if blocked.has(CellUtil.cell_key(cell)):
            avoids_building = false
            bad_cell = cell
            break
    SpatialHash.instance.remove_child(building)
    building.free()
    SpatialHash.instance._building_cells.clear()
    (
        TestHelper
        . assert_true(
            avoids_building,
            (
                "pathfinder routes around map-loaded building foundation: "
                + "path=%s bad_cell=%s (should route around building)" % [path, bad_cell]
            ),
        )
    )


func test_map_loaded_refinery_bibs_not_building_blocked():
    SpatialHash.instance._building_cells.clear()
    SpatialHash.instance._bib_cells.clear()
    TerrainSystem.init_grid(64, 64)
    var building := EntityFactory.create_entity("GDI_REFINERY")
    if building == null:
        TestHelper.fail("EntityFactory could not create GDI_REFINERY")
        return
    var origin := Vector2i(60, 60)
    building.position = CellUtil.cell_origin_to_world(origin, Vector2i(4, 3))
    SpatialHash.instance.add_child(building)
    var sh := SpatialHash.instance
    var bib_cells := [origin + Vector2i(3, 0), origin + Vector2i(3, 1), origin + Vector2i(3, 2)]
    var bib_not_blocked: bool = true
    for cell in bib_cells:
        if sh.get_blocked_cells().has(CellUtil.cell_key(cell)):
            bib_not_blocked = false
            break
    var bib_tracked: bool = true
    for cell in bib_cells:
        if not sh.is_bib_cell(cell):
            bib_tracked = false
            break
    var non_bib_blocked: bool = (
        sh.get_blocked_cells().has(CellUtil.cell_key(origin))
        and sh.get_blocked_cells().has(CellUtil.cell_key(origin + Vector2i(2, 2)))
    )
    SpatialHash.instance.remove_child(building)
    building.free()
    var cleared: bool = not sh.get_blocked_cells().has(CellUtil.cell_key(origin))
    SpatialHash.instance._building_cells.clear()
    SpatialHash.instance._bib_cells.clear()
    (
        TestHelper
        . assert_true(
            bib_not_blocked and bib_tracked and non_bib_blocked and cleared,
            (
                "refinery bib cells are bib-tracked, not building-blocked; "
                + "non-bib foundation blocked; unregistered on exit: "
                + (
                    "bib_not_blocked=%s bib_tracked=%s non_bib_blocked=%s cleared=%s"
                    % [bib_not_blocked, bib_tracked, non_bib_blocked, cleared]
                )
            ),
        )
    )
