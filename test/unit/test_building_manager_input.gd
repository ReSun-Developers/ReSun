extends Node

# BuildingManager build-mode input dispatch (event-driven-placement-input).
#
# Build mode commit/cancel is resolved from input events, not `_process`
# polling. These tests drive the handler directly with synthesized actions —
# the seam the old poll made untestable. A successful placement is driven
# through `_try_place_building(screen_pos)` with a mounted camera, since the
# headless cursor position cannot be moved.

var _bm: Node = null
var _saved_type: EntityData = null
var _saved_buildings: Array = []
var _saved_exiting: bool = false
var _saved_scene: Node = null

const TEST_BUILDING_ID: String = "test_input_building"


func _setup() -> void:
    _saved_type = _bm.current_building_type
    _saved_buildings = _bm._buildings.duplicate()
    _saved_exiting = _bm.exiting_build_mode
    _saved_scene = (Engine.get_main_loop() as SceneTree).current_scene


func _teardown() -> void:
    if _bm.is_build_mode:
        _bm.exit_build_mode()
    _bm.current_building_type = _saved_type
    _bm._buildings.assign(_saved_buildings)
    _bm.exiting_build_mode = _saved_exiting
    EntityFactory._entity_cache.erase(TEST_BUILDING_ID)
    (Engine.get_main_loop() as SceneTree).current_scene = _saved_scene


func _make_building() -> EntityData:
    var data := EntityData.new()
    data.id = TEST_BUILDING_ID
    data.foundation = Vector2i(2, 2)
    data.entity_type = EntityData.EntityType.BUILDING
    data.strength = 100
    data.cost = 0
    data.owner = ["GDI"]
    return data


func _action(action: String) -> InputEventAction:
    var ev := InputEventAction.new()
    ev.action = action
    ev.pressed = true
    return ev


## Mounts a scene whose `Camera3D` looks straight down at `target` (the
## BuildingManager camera fallback resolves it). Sets it as current_scene.
func _mount_camera(target: Vector3) -> Node3D:
    var scene_root := Node3D.new()
    scene_root.name = "InputTestScene"
    var cam := Camera3D.new()
    cam.name = "Camera3D"
    scene_root.add_child(cam)
    (Engine.get_main_loop() as SceneTree).root.add_child(scene_root)
    cam.look_at_from_position(target + Vector3(0, 30, 0), target, Vector3(0, 0, -1))
    (Engine.get_main_loop() as SceneTree).current_scene = scene_root
    return scene_root


func test_enter_arms_places_nothing_and_clears_latch() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    _setup()
    var before: int = _bm.get_all_buildings().size()
    _bm.exiting_build_mode = true
    _bm.enter_build_mode(_make_building())
    TestHelper.assert_true(_bm.is_build_mode, "enter_build_mode arms build mode")
    TestHelper.assert_true(
        not _bm.exiting_build_mode, "entering a fresh session clears a stale commit latch"
    )
    TestHelper.assert_eq(
        _bm.get_all_buildings().size(), before, "arming build mode places nothing by itself"
    )
    _teardown()


func test_deselect_exits_build_mode() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    _setup()
    _bm.enter_build_mode(_make_building())
    _bm._unhandled_input(_action("deselect_entity"))
    TestHelper.assert_true(not _bm.is_build_mode, "a deselect press exits build mode")
    _teardown()


func test_ui_cancel_exits_build_mode() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    _setup()
    _bm.enter_build_mode(_make_building())
    _bm._unhandled_input(_action("ui_cancel"))
    TestHelper.assert_true(not _bm.is_build_mode, "an Escape press exits build mode")
    _teardown()


func test_select_attempts_placement_without_cancelling() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    _setup()
    # No current scene => no camera => _try_place_building refuses, so the mode
    # must survive a select press rather than being silently cancelled.
    (Engine.get_main_loop() as SceneTree).current_scene = null
    _bm.enter_build_mode(_make_building())
    _bm._unhandled_input(_action("select_entity"))
    TestHelper.assert_true(
        _bm.is_build_mode,
        "a select press attempts placement and leaves build mode armed on refusal"
    )
    _teardown()


func test_input_ignored_outside_build_mode() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    _setup()
    _bm.exit_build_mode()
    _bm.exiting_build_mode = false
    var before: int = _bm.get_all_buildings().size()
    _bm._unhandled_input(_action("select_entity"))
    _bm._unhandled_input(_action("deselect_entity"))
    TestHelper.assert_eq(
        _bm.get_all_buildings().size(), before, "input outside build mode places nothing"
    )
    TestHelper.assert_true(not _bm.is_build_mode, "input outside build mode does not arm it")
    _teardown()


func test_select_places_building_and_sets_latch() -> void:
    if _bm == null:
        TestHelper.fail("BuildingManager not injected")
        return
    _setup()
    Cheats.place_anywhere = true
    Cheats.no_cost = true
    TerrainSystem.init_grid(64, 64)
    var data := _make_building()
    EntityFactory._entity_cache[TEST_BUILDING_ID] = data

    var gc: Vector2i = TerrainSystem.grid_cells
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
        _teardown()
        return

    var ground := CellUtil.cell_to_world(origin + Vector2i(1, 1), gc)
    var scene_root := _mount_camera(ground)
    var cam := scene_root.get_node("Camera3D") as Camera3D
    var screen := cam.unproject_position(ground)

    var before: int = _bm.get_all_buildings().size()
    _bm.enter_build_mode(data)
    _bm._try_place_building(screen)

    TestHelper.assert_eq(
        _bm.get_all_buildings().size(), before + 1, "a select at a valid cell places the building"
    )
    TestHelper.assert_true(not _bm.is_build_mode, "a successful place exits build mode")
    TestHelper.assert_true(
        _bm.exiting_build_mode, "a successful place sets the commit latch before exit"
    )

    # The single-frame suite cannot drain queue_free, so free the preview ghost
    # and the placed building synchronously or their collisions leak into later
    # physics/raycast suites. (`exit_build_mode` queue_frees the preview; free()
    # here overrides that and removes it now.)
    for child in _bm._preview.get_children():
        child.free()
    if is_instance_valid(scene_root):
        scene_root.free()
    SpatialHash.instance._building_cells.clear()
    _teardown()
