extends Node

# Regression for #514: a marquee drag that ends over UI (sidebar/minimap) must
# still end. The drag release is position-independent; world click resolution
# stays suppressed while the cursor is over UI.


class RecordingMouseHandler:
    extends MouseHandler

    var click_count: int = 0
    var box_count: int = 0
    var last_box: Rect2 = Rect2()

    func _handle_single_click(_mouse_pos: Vector2, _shift_pressed: bool) -> void:
        click_count += 1

    func _select_entities_2d_projected(rect: Rect2) -> void:
        box_count += 1
        last_box = rect


func _tree() -> SceneTree:
    return Engine.get_main_loop() as SceneTree


func _mount_scene() -> Node3D:
    var scene_root := Node3D.new()
    scene_root.name = "MarqueeTestScene"
    _tree().root.add_child(scene_root)
    _tree().current_scene = scene_root
    return scene_root


func _unmount_scene(scene_root: Node3D) -> void:
    _tree().current_scene = null
    UIUtil._cached_sidebar = null
    UIUtil._cached_minimap = null
    if is_instance_valid(scene_root):
        scene_root.free()


func _make_handler(parent: Node3D) -> RecordingMouseHandler:
    var handler := RecordingMouseHandler.new()
    handler.name = "MouseHandler"
    var rect := ReferenceRect.new()
    rect.name = "SelectionRect"
    handler.add_child(rect)
    var controller := CameraController.new()
    controller.name = "CameraController"
    var camera := Camera3D.new()
    camera.name = "Camera3D"
    controller.add_child(camera)
    handler.camera_controller = controller
    handler.add_child(controller)
    parent.add_child(handler)
    return handler


func _add_ui_overlay(parent: Node3D, node_name: String) -> Control:
    var overlay := Control.new()
    overlay.name = node_name
    overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    overlay.position = Vector2(-10000, -10000)
    overlay.size = Vector2(30000, 30000)
    parent.add_child(overlay)
    return overlay


func _set_drag(handler: RecordingMouseHandler, rect: Rect2) -> void:
    handler.mouse_dragging = true
    handler.drag_start_position = rect.position
    handler.active_rect = rect
    handler.selection_rect.position = rect.position
    handler.selection_rect.size = rect.size
    handler.selection_rect.show()


func _release_select() -> void:
    Input.action_release("select_entity")
    Input.action_press("select_entity")
    Input.action_release("select_entity")


func _begin(ui_name: String) -> Dictionary:
    var saved_build_mode: bool = BuildingManager.is_build_mode
    var saved_exiting: bool = BuildingManager.exiting_build_mode
    BuildingManager.is_build_mode = false
    BuildingManager.exiting_build_mode = false
    EntityPlacer.exit_placing_mode()
    var scene_root := _mount_scene()
    if ui_name != "":
        _add_ui_overlay(scene_root, ui_name)
    UIUtil._cached_sidebar = null
    UIUtil._cached_minimap = null
    var handler := _make_handler(scene_root)
    return {
        "scene": scene_root,
        "handler": handler,
        "build_mode": saved_build_mode,
        "exiting": saved_exiting,
    }


func _end(setup: Dictionary) -> void:
    Input.action_release("select_entity")
    BuildingManager.is_build_mode = setup["build_mode"]
    BuildingManager.exiting_build_mode = setup["exiting"]
    _unmount_scene(setup["scene"] as Node3D)


func _assert_drag_cleared(handler: RecordingMouseHandler, label: String) -> void:
    TestHelper.assert_true(not handler.mouse_dragging, label + ": drag state clears")
    TestHelper.assert_true(not handler.selection_rect.visible, label + ": selection box hides")
    TestHelper.assert_eq(handler.active_rect, Rect2(), label + ": active rect clears")


func test_release_over_sidebar_ends_drag() -> void:
    var setup := _begin("Sidebar")
    var handler := setup["handler"] as RecordingMouseHandler
    TestHelper.assert_true(UIUtil.is_mouse_over_sidebar(), "fixture: cursor is over the sidebar")
    var drag_rect := Rect2(Vector2(100, 100), Vector2(40, 40))
    _set_drag(handler, drag_rect)

    _release_select()
    handler._process(0.0)

    _assert_drag_cleared(handler, "release over sidebar")
    TestHelper.assert_eq(handler.box_count, 1, "release over sidebar resolves the box selection")
    TestHelper.assert_eq(handler.last_box, drag_rect, "box selection uses the drawn rectangle")
    _end(setup)


func test_release_over_minimap_ends_drag() -> void:
    var setup := _begin("Minimap")
    var handler := setup["handler"] as RecordingMouseHandler
    TestHelper.assert_true(UIUtil.is_mouse_over_minimap(), "fixture: cursor is over the minimap")
    _set_drag(handler, Rect2(Vector2(100, 100), Vector2(40, 40)))

    _release_select()
    handler._process(0.0)

    _assert_drag_cleared(handler, "release over minimap")
    TestHelper.assert_eq(handler.box_count, 1, "release over minimap resolves the box selection")
    _end(setup)


func test_sub_threshold_release_over_ui_does_not_click_through() -> void:
    var setup := _begin("Sidebar")
    var handler := setup["handler"] as RecordingMouseHandler
    TestHelper.assert_true(UIUtil.is_mouse_over_sidebar(), "fixture: cursor is over the sidebar")
    _set_drag(handler, Rect2(Vector2(100, 100), Vector2(1, 1)))

    _release_select()
    handler._process(0.0)

    _assert_drag_cleared(handler, "sub-threshold release over sidebar")
    TestHelper.assert_eq(handler.click_count, 0, "no world click resolves through the sidebar")
    TestHelper.assert_eq(handler.box_count, 0, "no box selection below the drag threshold")

    if not handler.has_method("_end_select_drag"):
        TestHelper.fail("release helper is missing; cannot prove the click path is reachable")
        _end(setup)
        return
    handler.mouse_dragging = true
    handler.active_rect = Rect2(Vector2(100, 100), Vector2(1, 1))
    handler._end_select_drag(false, false)
    TestHelper.assert_eq(handler.click_count, 1, "the same release clicks once over the world")
    _end(setup)


func test_press_over_ui_does_not_start_drag() -> void:
    var setup := _begin("Sidebar")
    var handler := setup["handler"] as RecordingMouseHandler
    TestHelper.assert_true(UIUtil.is_mouse_over_sidebar(), "fixture: cursor is over the sidebar")
    Input.action_release("select_entity")
    Input.action_press("select_entity")
    handler._process(0.0)
    TestHelper.assert_true(not handler.mouse_dragging, "press over UI does not start a drag")
    TestHelper.assert_true(not handler.selection_rect.visible, "press over UI shows no box")
    Input.action_release("select_entity")
    _end(setup)


func test_release_without_press_does_not_click_through() -> void:
    var setup := _begin("")
    var handler := setup["handler"] as RecordingMouseHandler
    if not handler.has_method("_end_select_drag"):
        TestHelper.fail("release helper is missing; cannot prove the no-press gate")
        _end(setup)
        return
    handler.mouse_dragging = false
    handler._end_select_drag(false, false)
    TestHelper.assert_eq(handler.click_count, 0, "release without an observed press does not click")
    TestHelper.assert_eq(handler.box_count, 0, "release without a drag does not box-select")
    _end(setup)


func test_same_frame_press_and_release_still_clicks() -> void:
    var setup := _begin("")
    var handler := setup["handler"] as RecordingMouseHandler
    var saved_edge_scroll: bool = InputSettings.edge_scroll_enabled
    InputSettings.edge_scroll_enabled = false
    handler.mouse_dragging = false
    _release_select()
    handler._process(0.0)
    TestHelper.assert_eq(handler.click_count, 1, "a press+release in one frame resolves a click")
    _assert_drag_cleared(handler, "same-frame click")
    InputSettings.edge_scroll_enabled = saved_edge_scroll
    _end(setup)


func test_degenerate_marquee_does_not_click() -> void:
    var setup := _begin("")
    var handler := setup["handler"] as RecordingMouseHandler
    if not handler.has_method("_end_select_drag"):
        TestHelper.fail("release helper is missing; cannot prove the degenerate box path")
        _end(setup)
        return
    handler.mouse_dragging = true
    handler.active_rect = Rect2(Vector2(100, 100), Vector2(40, 0))
    handler._end_select_drag(false, false)
    TestHelper.assert_eq(handler.click_count, 0, "zero-height marquee does not click")
    TestHelper.assert_eq(handler.box_count, 0, "zero-height marquee selects nothing")
    _assert_drag_cleared(handler, "degenerate marquee")
    _end(setup)


func test_world_release_still_resolves() -> void:
    var setup := _begin("")
    var handler := setup["handler"] as RecordingMouseHandler
    if not handler.has_method("_end_select_drag"):
        TestHelper.fail("release helper is missing; cannot prove the world path")
        _end(setup)
        return
    var drag_rect := Rect2(Vector2(100, 100), Vector2(40, 40))
    handler.mouse_dragging = true
    handler.active_rect = drag_rect
    handler.selection_rect.size = drag_rect.size
    handler._end_select_drag(false, false)
    _assert_drag_cleared(handler, "world release")
    TestHelper.assert_eq(handler.box_count, 1, "world release still box-selects")
    TestHelper.assert_eq(handler.last_box, drag_rect, "world release uses the drawn rectangle")
    _end(setup)
