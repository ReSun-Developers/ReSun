extends Node

# BuildingManager tests — placement validation

var _bm: Node = null


func _setup_2x2_terrain(origin: Vector2i) -> void:
    TerrainSystem.init_grid(64, 64)
    for dx in 2:
        for dz in 2:
            TerrainSystem.set_cell_type(origin + Vector2i(dx, dz), "clear")


func _make_2x2_building() -> EntityData:
    var building_type := EntityData.new()
    building_type.foundation = Vector2i(2, 2)
    return building_type


## Registers a temporary friendly 1x1 building with its single foundation cell
## at (3, 3) and a StatsComponent for the local player, runs check, then
## restores the previous registry and frees the node. Returns check's result.
func _with_friendly_neighbor(check: Callable) -> bool:
    var pid: int = PlayerManager.get_local_player_id()
    var node := Node3D.new()
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = pid
    node.add_child(stats)
    var neighbor_type := EntityData.new()
    neighbor_type.foundation = Vector2i(1, 1)
    var saved: Array = _bm._buildings.duplicate()
    _bm._buildings.clear()
    _bm._buildings.append(
        {"node": node, "type": neighbor_type, "origin": Vector2i(3, 3), "cells": [Vector2i(3, 3)]}
    )
    var result: bool = check.call()
    _bm._buildings.assign(saved)
    node.free()
    return result


func test_can_place_returns_true_on_valid_centered_cells() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var building_type := _make_2x2_building()
    var origin := Vector2i(64, 64)
    _setup_2x2_terrain(origin)
    var result: bool = _bm.can_place(building_type, origin)
    TestHelper.assert_true(
        result == true, "can_place returns true on valid cells: expected true, got false"
    )


func test_can_place_rejects_building_overlap() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    SpatialHash.instance._building_cells.clear()
    var building_type := _make_2x2_building()
    var origin := Vector2i(64, 64)
    _setup_2x2_terrain(origin)
    var valid_before_overlap: bool = _bm.can_place(building_type, origin)
    var cells: Array[Vector2i] = [Vector2i(64, 64), Vector2i(65, 64)]
    SpatialHash.instance.register_building_cells(cells)
    var result: bool = _bm.can_place(building_type, origin)
    SpatialHash.instance._building_cells.clear()
    (
        TestHelper
        . assert_true(
            valid_before_overlap and result == false,
            "can_place rejects building overlap: expected false, got true",
        )
    )


func test_can_place_rejects_tiberium_cell() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    SpatialHash.instance._building_cells.clear()
    var building_type := _make_2x2_building()
    var origin := Vector2i(64, 64)
    _setup_2x2_terrain(origin)
    var valid_before_resource: bool = _bm.can_place(building_type, origin)
    var tib_cell := Vector2i(64, 64)
    var tib_node := Node3D.new()
    var tib_comp := Node.new()
    tib_comp.name = "ResourceComponent"
    tib_node.add_child(tib_comp)
    tib_node.add_to_group("resources")
    _bm.add_child(tib_node)
    tib_node.global_position = CellUtil.cell_to_world(tib_cell)
    var world_cell: Vector2i = CellUtil.world_to_cell(tib_node.global_position)
    SpatialHash.instance.register_resource_cell(world_cell)
    var result: bool = _bm.can_place(building_type, origin)
    SpatialHash.instance.unregister_resource_cell(world_cell)
    _bm.remove_child(tib_node)
    tib_node.queue_free()
    (
        TestHelper
        . assert_true(
            valid_before_resource and result == false,
            "can_place rejects tiberium cell: expected false, got true",
        )
    )


func test_can_place_rejects_moving_unit() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    SpatialHash.instance._building_cells.clear()
    SpatialHash.instance._blocked_cells.clear()
    SpatialHash.instance._grid.clear()
    var building_type := _make_2x2_building()
    var origin := Vector2i(64, 64)
    _setup_2x2_terrain(origin)
    var valid_before_unit: bool = _bm.can_place(building_type, origin)
    var unit_cell := Vector2i(64, 64)
    var unit_key: int = CellUtil.cell_key(unit_cell)
    var fake_mc := MovementController.new()
    fake_mc._state = MovementController.State.MOVING
    SpatialHash.instance._grid[unit_key] = [
        {
            "node": Node3D.new(),
            "mc": fake_mc,
            "state": MovementController.State.MOVING,
            "shares": false,
            "level": 0,
        }
    ]
    var result: bool = _bm.can_place(building_type, origin)
    SpatialHash.instance._grid.erase(unit_key)
    SpatialHash.instance._building_cells.clear()
    fake_mc.queue_free()
    (
        TestHelper
        . assert_true(
            valid_before_unit and result == false,
            "can_place rejects moving unit: expected false, got true",
        )
    )


func test_adjacency_no_requirement_passes() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var building_type := _make_2x2_building()
    building_type.adjacent = 0
    var result: bool = _bm._is_adjacency_satisfied(building_type, Vector2i(5, 5))
    TestHelper.assert_true(
        result == true, "adjacency no-op when adjacent <= 0: expected true, got false"
    )


func test_adjacency_rejected_without_neighbor() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var building_type := _make_2x2_building()
    building_type.adjacent = 1
    var saved: Array = _bm._buildings.duplicate()
    _bm._buildings.clear()
    var result: bool = _bm._is_adjacency_satisfied(building_type, Vector2i(5, 5))
    _bm._buildings.assign(saved)
    TestHelper.assert_true(
        result == false, "adjacency rejected with no friendly building: expected false, got true"
    )


func test_adjacency_accepted_near_friendly() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var building_type := _make_2x2_building()
    building_type.adjacent = 1
    var pid: int = PlayerManager.get_local_player_id()
    var node := Node3D.new()
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = pid
    node.add_child(stats)
    var saved: Array = _bm._buildings.duplicate()
    _bm._buildings.clear()
    _bm._buildings.append(
        {"node": node, "type": building_type, "origin": Vector2i(3, 3), "cells": [Vector2i(3, 3)]}
    )
    # Footprint at (4,3) includes cell (4,3), Chebyshev distance 1 from (3,3)
    var result: bool = _bm._is_adjacency_satisfied(building_type, Vector2i(4, 3))
    _bm._buildings.assign(saved)
    node.free()
    TestHelper.assert_true(
        result == true, "adjacency accepted near a friendly building: expected true, got false"
    )


func test_adjacency_ignores_building_without_stats() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var building_type := _make_2x2_building()
    building_type.adjacent = 1
    # Building has no StatsComponent → must NOT count as a friendly neighbor
    var node := Node3D.new()
    var saved: Array = _bm._buildings.duplicate()
    _bm._buildings.clear()
    _bm._buildings.append(
        {"node": node, "type": building_type, "origin": Vector2i(3, 3), "cells": [Vector2i(3, 3)]}
    )
    var result: bool = _bm._is_adjacency_satisfied(building_type, Vector2i(4, 3))
    _bm._buildings.assign(saved)
    node.free()
    TestHelper.assert_true(
        result == false, "adjacency ignores stats-less building: expected false, got true"
    )


func test_adjacent_1_allows_one_cell_gap() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var building_type := _make_2x2_building()
    building_type.adjacent = 1
    # Nearest footprint cell (5,3) is Chebyshev distance 2 from (3,3) = 1 empty cell gap
    var result: bool = _with_friendly_neighbor(
        func() -> bool: return _bm._is_adjacency_satisfied(building_type, Vector2i(5, 3))
    )
    TestHelper.assert_true(result == true, "adjacent=1 allows 1-cell gap: expected true, got false")


func test_adjacent_1_rejects_two_cell_gap() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var building_type := _make_2x2_building()
    building_type.adjacent = 1
    # Nearest footprint cell (6,3) is Chebyshev distance 3 from (3,3) = 2 empty cell gap
    var result: bool = _with_friendly_neighbor(
        func() -> bool: return _bm._is_adjacency_satisfied(building_type, Vector2i(6, 3))
    )
    TestHelper.assert_true(
        result == false, "adjacent=1 rejects 2-cell gap: expected false, got true"
    )


func test_adjacent_2_allows_two_cell_gap() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var building_type := _make_2x2_building()
    building_type.adjacent = 2
    # Nearest footprint cell (6,3) is Chebyshev distance 3 from (3,3) = 2 empty cell gap
    var result: bool = _with_friendly_neighbor(
        func() -> bool: return _bm._is_adjacency_satisfied(building_type, Vector2i(6, 3))
    )
    TestHelper.assert_true(result == true, "adjacent=2 allows 2-cell gap: expected true, got false")


func test_adjacent_2_rejects_three_cell_gap() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var building_type := _make_2x2_building()
    building_type.adjacent = 2
    # Nearest footprint cell (7,3) is Chebyshev distance 4 from (3,3) = 3 empty cell gap
    var result: bool = _with_friendly_neighbor(
        func() -> bool: return _bm._is_adjacency_satisfied(building_type, Vector2i(7, 3))
    )
    TestHelper.assert_true(
        result == false, "adjacent=2 rejects 3-cell gap: expected false, got true"
    )


func test_enter_build_mode_refreshes_white_region_on_type_switch() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    # Regression: switching ghost type mid-session must re-dilate the white
    # region with the new foundation — the overlay survives the switch.
    TerrainSystem.init_grid(64, 64)
    var saved_type: EntityData = _bm.current_building_type
    var saved_buildings: Array = _bm._buildings.duplicate()
    _bm._buildings.clear()
    var pid: int = PlayerManager.get_local_player_id()
    var neighbor := Node3D.new()
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.player_id = pid
    neighbor.add_child(stats)
    var neighbor_type := EntityData.new()
    neighbor_type.foundation = Vector2i(1, 1)
    _bm._buildings.append(
        {
            "node": neighbor,
            "type": neighbor_type,
            "origin": Vector2i(63, 60),
            "cells": [Vector2i(63, 60)]
        }
    )
    var type_a := _make_2x2_building()
    type_a.adjacent = 1
    var type_b := EntityData.new()
    type_b.foundation = Vector2i(4, 4)
    type_b.adjacent = 1
    _bm.enter_build_mode(type_a)
    var white_a: Dictionary = _bm._grid_overlay._white_cells.duplicate()
    _bm.enter_build_mode(type_b)
    var white_b: Dictionary = _bm._grid_overlay._white_cells.duplicate()
    _bm.exit_build_mode()
    _bm.current_building_type = saved_type
    _bm._buildings.assign(saved_buildings)
    neighbor.free()
    TestHelper.assert_eq(white_a.size(), 49, "2x2 ghost -> radii (3,3): 7x7 white rect")
    TestHelper.assert_eq(white_b.size(), 121, "4x4 ghost after switch -> radii (5,5): 11x11 rect")
    (
        TestHelper
        . assert_true(
            white_b.has(Vector2i(63, 55)) and not white_a.has(Vector2i(63, 55)),
            "switched white region reflects the new foundation, not the stale one",
        )
    )


func test_build_mode_renders_no_line_grid() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    # Regression (#352): the line grid is gone; the highlight overlay is the
    # only placement feedback node added to the preview.
    TestHelper.assert_true(
        not _bm.has_method("_add_grid_and_indicators"), "line-grid builder removed"
    )
    TerrainSystem.init_grid(64, 64)
    var saved_type: EntityData = _bm.current_building_type
    var saved_buildings: Array = _bm._buildings.duplicate()
    _bm._buildings.clear()
    # Headless runner never pumps frames, so queue_free'd previews from other
    # suites may linger — purge before counting.
    for child in _bm._preview.get_children():
        _bm._preview.remove_child(child)
        child.free()
    _bm.current_building_type = _make_2x2_building()
    _bm._update_preview_mesh(true, Vector2i(64, 64))
    var children: Array = _bm._preview.get_children()
    var overlay_count := 0
    var stray_meshes := 0
    for child in children:
        if child is PlacementGridOverlay:
            overlay_count += 1
        elif child is MeshInstance3D:
            stray_meshes += 1
    TestHelper.assert_eq(overlay_count, 1, "exactly one PlacementGridOverlay in the preview")
    TestHelper.assert_eq(stray_meshes, 0, "no per-cell or line-grid MeshInstance3D nodes")
    _bm.current_building_type = saved_type
    _bm._buildings.assign(saved_buildings)
    for child in _bm._preview.get_children():
        child.queue_free()
    _bm._grid_overlay = null


## Regression: resolve the gameplay camera from the viewport. Mission boot nests
## the map under MainScene/Gameplay, so it is no longer `current_scene` and the
## old current_scene/Camera/Camera3D lookup returned null — breaking placement.
func test_get_camera_3d_resolves_nested_viewport_camera() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var host := Node3D.new()
    host.name = "NestedMapHost"
    (Engine.get_main_loop() as SceneTree).root.add_child(host)
    var camera := Camera3D.new()
    camera.current = true
    host.add_child(camera)
    var resolved: Camera3D = _bm._get_camera_3d()
    TestHelper.assert_true(
        resolved == camera, "BuildingManager resolves a map camera nested under another node"
    )
    host.free()


## Player-built structures route through the match World root's Entities
## container; no per-match `Main/Buildings` container is created.
func test_buildings_parent_routes_to_world_entities() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    var tree := Engine.get_main_loop() as SceneTree
    var world: Node = World.new()
    world.name = "BuildingManagerTestWorld"
    tree.root.add_child(world)

    var parent: Node = _bm._get_buildings_parent()
    TestHelper.assert_true(parent != null, "the buildings parent resolves with a World active")
    (
        TestHelper
        . assert_true(
            parent == world.get_node_or_null(World.ENTITIES_NAME),
            "the buildings parent is the World Entities container",
        )
    )
    (
        TestHelper
        . assert_true(
            tree.current_scene == null or tree.current_scene.get_node_or_null("Buildings") == null,
            "no Main/Buildings container is created",
        )
    )

    world.free()
