extends Node

# EntityPlacer free-placement session tests (sidebar-ui-thinning, debug-menu
# spec). The session is one nullable placing mode on EntityPlacer; commit and
# cancel are event-driven via _unhandled_input, and the commit click leaves a
# same-frame latch so MouseHandler does not double-fire it as a unit order.
# start_preview parents the ghost to current_scene, so every session test
# mounts a minimal scene exposing the "Camera" → "Camera3D" chain the placer
# resolves. Expected surface heights come from the terrain fixture, never
# from the code under test.

const INFANTRY_ID: String = "test_placing_infantry"

var _ts: Node = null


func _placer() -> Node:
    # The suite never enters the tree; resolve through an injected sibling.
    var placer: Node = _ts.get_node_or_null("/root/EntityPlacer") if _ts else null
    if not placer:
        TestHelper.fail("EntityPlacer autoload not reachable")
    return placer


func _make_infantry_data() -> EntityData:
    var data := EntityData.new()
    data.id = INFANTRY_ID
    data.entity_type = EntityData.EntityType.INFANTRY
    data.display_name = "Test Placing Infantry"
    EntityFactory._entity_cache[INFANTRY_ID] = data
    return data


func _drop_infantry_data() -> void:
    EntityFactory._entity_cache.erase(INFANTRY_ID)


func _action_event(action: String) -> InputEventAction:
    var ev := InputEventAction.new()
    ev.action = action
    ev.pressed = true
    return ev


func _mount_camera_scene(eye: Vector3, look_at_point: Vector3) -> Node3D:
    var scene_root := Node3D.new()
    scene_root.name = "PlacingTestScene"
    var cam_rig := Node3D.new()
    cam_rig.name = "Camera"
    var cam := Camera3D.new()
    cam.name = "Camera3D"
    var dir: Vector3 = (look_at_point - eye).normalized()
    var up: Vector3 = Vector3(0.0, 0.0, -1.0) if absf(dir.dot(Vector3.UP)) > 0.999 else Vector3.UP
    cam_rig.add_child(cam)
    scene_root.add_child(cam_rig)
    (Engine.get_main_loop() as SceneTree).root.add_child(scene_root)
    cam.look_at_from_position(eye, look_at_point, up)
    (Engine.get_main_loop() as SceneTree).current_scene = scene_root
    return scene_root


func _unmount_camera_scene(scene_root: Node3D) -> void:
    (Engine.get_main_loop() as SceneTree).current_scene = null
    if scene_root and is_instance_valid(scene_root):
        scene_root.free()


func test_enter_arms_mode_without_preview() -> void:
    var placer := _placer()
    if not placer:
        return
    placer.exit_placing_mode()
    placer.enter_placing_mode()
    TestHelper.assert_true(placer.is_placing(), "enter_placing_mode arms the mode")
    TestHelper.assert_true(not placer.has_preview(), "arming the mode alone shows no preview yet")
    placer.exit_placing_mode()
    TestHelper.assert_true(not placer.is_placing(), "exit_placing_mode disarms the mode")
    TestHelper.assert_true(not placer.has_preview(), "exit leaves no preview behind")


func test_commit_is_event_driven() -> void:
    var placer := _placer()
    if not placer:
        return
    placer.exit_placing_mode()
    var data := _make_infantry_data()
    var scene_root := _mount_camera_scene(Vector3(2.0, 20.0, 2.0), Vector3(2.0, 0.0, 2.0))
    placer.start_placing(data)
    TestHelper.assert_true(placer.is_placing(), "start_placing arms the session")
    TestHelper.assert_true(placer.has_preview(), "start_placing shows a preview ghost")
    placer._unhandled_input(_action_event("select_entity"))
    TestHelper.assert_true(not placer.is_placing(), "commit disarms the session")
    TestHelper.assert_true(not placer.has_preview(), "commit consumes the preview")
    TestHelper.assert_true(
        placer.did_consume_click_this_frame(), "commit click latches for order routing"
    )
    # Drop the latch: exit_placing_mode invalidates it, keeping the shared
    # autoload clean for suites that run later in the same synthetic frame.
    placer.exit_placing_mode()
    TestHelper.assert_true(
        not placer.did_consume_click_this_frame(), "exiting the session clears the latch"
    )
    _unmount_camera_scene(scene_root)
    _drop_infantry_data()


func test_cancel_is_event_driven() -> void:
    var placer := _placer()
    if not placer:
        return
    placer.exit_placing_mode()
    var data := _make_infantry_data()
    var scene_root := _mount_camera_scene(Vector3(2.0, 20.0, 2.0), Vector3(2.0, 0.0, 2.0))
    placer.start_placing(data)
    placer._unhandled_input(_action_event("deselect_entity"))
    TestHelper.assert_true(not placer.is_placing(), "cancel via deselect disarms the session")
    TestHelper.assert_true(not placer.has_preview(), "cancel drops the preview")
    TestHelper.assert_true(
        not placer.did_consume_click_this_frame(), "cancel does not latch the commit click"
    )
    placer.start_placing(data)
    placer._unhandled_input(_action_event("ui_cancel"))
    TestHelper.assert_true(not placer.is_placing(), "cancel via ESC disarms the session")
    _unmount_camera_scene(scene_root)
    _drop_infantry_data()


func test_reposition_tracks_terrain() -> void:
    var placer := _placer()
    if not placer:
        return
    placer.exit_placing_mode()
    var data := _make_infantry_data()
    var aim := Vector3(2.0, 0.0, 2.0)
    var scene_root := _mount_camera_scene(Vector3(aim.x, 20.0, aim.z), aim)
    placer.start_placing(data)
    placer._process(0.016)
    var preview: Node3D = placer._preview
    TestHelper.assert_true(preview != null, "session drives a live preview")
    if preview:
        TestHelper.assert_true(
            absf(preview.position.y - _ts.get_height_at_world_smooth(preview.position)) < 0.05,
            "ghost rests on the terrain surface after repositioning"
        )
    placer.exit_placing_mode()
    _unmount_camera_scene(scene_root)
    _drop_infantry_data()


func test_direct_deploy_is_a_named_start_path() -> void:
    var placer := _placer()
    if not placer:
        return
    placer.exit_placing_mode()
    var data := _make_infantry_data()
    var scene_root := _mount_camera_scene(Vector3(2.0, 20.0, 2.0), Vector3(2.0, 0.0, 2.0))
    placer.start_direct_deploy(data)
    TestHelper.assert_true(placer.is_placing(), "direct deploy arms the placing session")
    TestHelper.assert_true(placer.has_preview(), "direct deploy shows a preview ghost")
    placer.exit_placing_mode()
    _unmount_camera_scene(scene_root)
    _drop_infantry_data()


const BUILDING_ID: String = "test_placing_bldg"


func _make_building_data() -> EntityData:
    var data := EntityData.new()
    data.id = BUILDING_ID
    data.entity_type = EntityData.EntityType.BUILDING
    data.display_name = "Test Placing Building"
    data.foundation = Vector2i(2, 2)
    data.cost = 250
    EntityFactory._entity_cache[BUILDING_ID] = data
    return data


func _drop_building_data() -> void:
    EntityFactory._entity_cache.erase(BUILDING_ID)


# World↔cell mapping comes from the terrain fixture grid (oracle: CellUtil +
# _ts.grid_cells); the spec under test is the half-footprint origin offset.
func test_building_origin_snaps_to_foundation() -> void:
    var placer := _placer()
    if not placer or not _ts:
        TestHelper.fail("EntityPlacer/TerrainSystem not reachable")
        return
    var data := _make_building_data()
    var gc: Vector2i = _ts.grid_cells
    var mouse_cell := Vector2i(gc.x >> 1, gc.y >> 1)
    var ground := CellUtil.cell_to_world(mouse_cell, gc)
    data.foundation = Vector2i(2, 2)
    TestHelper.assert_eq(
        placer.building_origin_for(data, ground),
        mouse_cell - Vector2i(1, 1),
        "2x2 foundation origin = mouse cell minus half footprint"
    )
    data.foundation = Vector2i(3, 3)
    TestHelper.assert_eq(
        placer.building_origin_for(data, ground),
        mouse_cell - Vector2i(1, 1),
        "3x3 foundation offsets by one cell per axis"
    )
    data.foundation = Vector2i(1, 1)
    TestHelper.assert_eq(
        placer.building_origin_for(data, ground),
        mouse_cell,
        "1x1 foundation keeps the mouse cell as origin"
    )
    _drop_building_data()


func test_building_commit_routes_through_building_manager() -> void:
    var placer := _placer()
    var bm: Node = _ts.get_node_or_null("/root/BuildingManager") if _ts else null
    if not placer or not bm:
        TestHelper.fail("EntityPlacer/BuildingManager autoloads not reachable")
        return
    placer.exit_placing_mode()
    var data := _make_building_data()
    Cheats.place_anywhere = true
    Cheats.no_cost = true
    var scene_root := _mount_camera_scene(Vector3(2.0, 20.0, 2.0), Vector3(2.0, 0.0, 2.0))
    placer.start_placing(data)
    var registry_before: int = (bm.get_all_buildings() as Array).size()
    # Oracle-driven target: first origin whose full 2x2 footprint is in map
    # bounds, with the ground point derived from its mouse cell.
    var gc: Vector2i = _ts.grid_cells
    var origin := Vector2i(-1, -1)
    for x in gc.x - 1:
        for y in gc.y - 1:
            if (
                BoundsSystem.is_in_map_bounds(Vector2i(x, y))
                and BoundsSystem.is_in_map_bounds(Vector2i(x + 1, y))
                and BoundsSystem.is_in_map_bounds(Vector2i(x, y + 1))
                and BoundsSystem.is_in_map_bounds(Vector2i(x + 1, y + 1))
            ):
                origin = Vector2i(x, y)
                break
        if origin.x >= 0:
            break
    TestHelper.assert_true(origin.x >= 0, "setup: fixture grid has a placeable 2x2 origin")
    if origin.x < 0:
        placer.exit_placing_mode()
        _unmount_camera_scene(scene_root)
        _drop_building_data()
        return
    var ground := CellUtil.cell_to_world(origin + Vector2i(1, 1), gc)
    placer._commit_building(data, ground)
    var registry_after: Array = bm.get_all_buildings() as Array
    TestHelper.assert_eq(
        registry_after.size(), registry_before + 1, "building commit registers in BuildingManager"
    )
    TestHelper.assert_true(not placer.is_placing(), "building commit disarms the session")
    TestHelper.assert_true(not placer.has_preview(), "building commit drops the ghost")
    TestHelper.assert_true(
        placer.did_consume_click_this_frame(), "building commit latches the commit click"
    )
    # Drop the latch and the registry entry: the shared autoloads must stay
    # clean for suites that run later in the same synthetic frame.
    placer.exit_placing_mode()
    if registry_after.size() == registry_before + 1:
        (bm as Node)._buildings.pop_back()
    _unmount_camera_scene(scene_root)
    _drop_building_data()


func test_place_anywhere_commit_charges() -> void:
    # place_anywhere bypasses validity (bounds-only can_place) but NOT the
    # charge: cheat placement costs credits like any other placement.
    var placer := _placer()
    var bm: Node = _ts.get_node_or_null("/root/BuildingManager") if _ts else null
    var em: Node = _ts.get_node_or_null("/root/EconomyManager") if _ts else null
    var pmgr: Node = _ts.get_node_or_null("/root/PlayerManager") if _ts else null
    if not placer or not bm or not em or not pmgr:
        TestHelper.fail("EntityPlacer/BuildingManager/EconomyManager/PlayerManager unreachable")
        return
    placer.exit_placing_mode()
    var data := _make_building_data()
    Cheats.place_anywhere = true
    Cheats.no_cost = false
    var scene_root := _mount_camera_scene(Vector3(2.0, 20.0, 2.0), Vector3(2.0, 0.0, 2.0))
    var pid: int = pmgr.get_local_player_id()
    em.add(pid, data.cost, "test")
    var balance_before: int = em.get_balance(pid)
    placer.start_placing(data)
    var registry_before: int = (bm.get_all_buildings() as Array).size()
    var gc: Vector2i = _ts.grid_cells
    var origin := Vector2i(-1, -1)
    for x in gc.x - 1:
        for y in gc.y - 1:
            if (
                BoundsSystem.is_in_map_bounds(Vector2i(x, y))
                and BoundsSystem.is_in_map_bounds(Vector2i(x + 1, y))
                and BoundsSystem.is_in_map_bounds(Vector2i(x, y + 1))
                and BoundsSystem.is_in_map_bounds(Vector2i(x + 1, y + 1))
            ):
                origin = Vector2i(x, y)
                break
        if origin.x >= 0:
            break
    TestHelper.assert_true(origin.x >= 0, "setup: fixture grid has a placeable 2x2 origin")
    if origin.x < 0:
        placer.exit_placing_mode()
        _unmount_camera_scene(scene_root)
        _drop_building_data()
        return
    var ground := CellUtil.cell_to_world(origin + Vector2i(1, 1), gc)
    placer._commit_building(data, ground)
    TestHelper.assert_eq(
        (bm.get_all_buildings() as Array).size(),
        registry_before + 1,
        "place-anywhere commit lands under the cheat"
    )
    TestHelper.assert_eq(
        em.get_balance(pid), balance_before - data.cost, "cheat placement charges the full cost"
    )
    TestHelper.assert_true(not placer.is_placing(), "charged cheat commit disarms the session")
    placer.exit_placing_mode()
    if (bm.get_all_buildings() as Array).size() == registry_before + 1:
        (bm as Node)._buildings.pop_back()
    _unmount_camera_scene(scene_root)
    _drop_building_data()


func test_cheat_commit_of_paid_building_does_not_double_charge() -> void:
    # A production-paid ready building committed through the place-anywhere
    # ghost must reuse the payment and consume the entry (#339 review follow-up).
    var placer := _placer()
    var bm: Node = _ts.get_node_or_null("/root/BuildingManager") if _ts else null
    var em: Node = _ts.get_node_or_null("/root/EconomyManager") if _ts else null
    var pmgr: Node = _ts.get_node_or_null("/root/PlayerManager") if _ts else null
    var pm: Node = _ts.get_node_or_null("/root/ProductionManager") if _ts else null
    if not placer or not bm or not em or not pmgr or not pm:
        TestHelper.fail("required autoloads unreachable")
        return
    placer.exit_placing_mode()
    var data := _make_building_data()
    Cheats.place_anywhere = true
    Cheats.no_cost = false
    var scene_root := _mount_camera_scene(Vector3(2.0, 20.0, 2.0), Vector3(2.0, 0.0, 2.0))
    var pid: int = pmgr.get_local_player_id()
    pm._add_ready_to_place(pid, data, data.cost)
    em.add(pid, data.cost, "test")
    var balance_before: int = em.get_balance(pid)
    var gc: Vector2i = _ts.grid_cells
    var origin := Vector2i(-1, -1)
    for x in gc.x - 1:
        for y in gc.y - 1:
            if (
                BoundsSystem.is_in_map_bounds(Vector2i(x, y))
                and BoundsSystem.is_in_map_bounds(Vector2i(x + 1, y))
                and BoundsSystem.is_in_map_bounds(Vector2i(x, y + 1))
                and BoundsSystem.is_in_map_bounds(Vector2i(x + 1, y + 1))
            ):
                origin = Vector2i(x, y)
                break
        if origin.x >= 0:
            break
    TestHelper.assert_true(origin.x >= 0, "setup: fixture grid has a placeable 2x2 origin")
    if origin.x < 0:
        placer.exit_placing_mode()
        pm.cancel_ready_building(pid, BUILDING_ID)
        _unmount_camera_scene(scene_root)
        _drop_building_data()
        return
    placer.start_placing(data)
    var registry_before: int = (bm.get_all_buildings() as Array).size()
    var ground := CellUtil.cell_to_world(origin + Vector2i(1, 1), gc)
    placer._commit_building(data, ground)
    TestHelper.assert_eq(
        (bm.get_all_buildings() as Array).size(),
        registry_before + 1,
        "paid building lands through the cheat session"
    )
    TestHelper.assert_eq(
        em.get_balance(pid), balance_before, "production-paid building is not charged a second time"
    )
    TestHelper.assert_true(
        not pm.is_ready_to_place(pid, BUILDING_ID), "ready entry consumed once the building lands"
    )
    TestHelper.assert_true(not placer.is_placing(), "commit disarms the session")
    placer.exit_placing_mode()
    if (bm.get_all_buildings() as Array).size() == registry_before + 1:
        (bm as Node)._buildings.pop_back()
    _unmount_camera_scene(scene_root)
    _drop_building_data()


func test_building_commit_refusal_keeps_session_armed() -> void:
    var placer := _placer()
    var bm: Node = _ts.get_node_or_null("/root/BuildingManager") if _ts else null
    if not placer or not bm:
        TestHelper.fail("EntityPlacer/BuildingManager autoloads not reachable")
        return
    placer.exit_placing_mode()
    var data := _make_building_data()
    Cheats.place_anywhere = true
    Cheats.no_cost = true
    var scene_root := _mount_camera_scene(Vector3(2.0, 20.0, 2.0), Vector3(2.0, 0.0, 2.0))
    placer.start_placing(data)
    # Far outside the terrain grid: even the place-anywhere bounds check refuses.
    placer._commit_building(data, Vector3(99999.0, 0.0, 99999.0))
    TestHelper.assert_true(placer.is_placing(), "refused building commit keeps the session armed")
    TestHelper.assert_true(placer.has_preview(), "refused commit keeps the ghost")
    TestHelper.assert_true(
        not placer.did_consume_click_this_frame(), "refused commit does not latch"
    )
    placer.exit_placing_mode()
    _unmount_camera_scene(scene_root)
    _drop_building_data()
