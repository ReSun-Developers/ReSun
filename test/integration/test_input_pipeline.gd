extends Node

# Headless input-pipeline probe (issue #512, Phase 0).
#
# `openspec/specs/debug-menu/spec.md` asserts that "mouse events do not reach
# `_unhandled_input` at runtime in this codebase" — the stated reason
# EntityPlacer/BuildingManager poll raw `Input` in `_process`. No test exercised
# the real `Viewport.push_input` pipeline, so the claim was never challenged.
# These probes push events through the pipeline and record whether a plain Node
# (autoload shape) and a Control under a Node3D (MouseHandler shape) see them.
#
# If these pass, the poll fallback is not load-bearing and the sessions can be
# driven by `_unhandled_input` alone.
#
# LIMIT: headless `push_input` does not reproduce GUI consumption — a full-rect
# `mouse_filter = STOP` Control (even a Button) does not stop the event reaching
# `_unhandled_input`. So this file proves the positive path only. GUI ownership
# of minimap/cameo clicks is enforced explicitly (`UIUtil.is_mouse_over_minimap`)
# and confirmed by the live-match check, not asserted here.


class NodeProbe:
    extends Node

    var seen_actions: Array[String] = []

    func _unhandled_input(event: InputEvent) -> void:
        if event.is_action_pressed("select_entity"):
            seen_actions.append("select_entity")
        if event.is_action_pressed("deselect_entity"):
            seen_actions.append("deselect_entity")


class ControlProbe:
    extends Control

    var saw_select: bool = false

    func _unhandled_input(event: InputEvent) -> void:
        if event.is_action_pressed("select_entity"):
            saw_select = true


func _root() -> Window:
    return (Engine.get_main_loop() as SceneTree).root


func _action_event(action: String) -> InputEventAction:
    var ev := InputEventAction.new()
    ev.action = action
    ev.pressed = true
    return ev


func _left_click(pos: Vector2) -> InputEventMouseButton:
    var ev := InputEventMouseButton.new()
    ev.button_index = MOUSE_BUTTON_LEFT
    ev.pressed = true
    ev.position = pos
    ev.global_position = pos
    return ev


## A HUD-shaped layer: a STOP Control on the right and one top-left, leaving the
## open world (centre) uncovered. Returns the CanvasLayer so callers can free it.
func _mount_hud_shape() -> CanvasLayer:
    var hud := CanvasLayer.new()
    _root().add_child(hud)
    var sidebar := Control.new()
    sidebar.name = "Sidebar"
    sidebar.mouse_filter = Control.MOUSE_FILTER_STOP
    sidebar.position = Vector2(1520, 244)
    sidebar.size = Vector2(400, 600)
    hud.add_child(sidebar)
    var minimap := Control.new()
    minimap.name = "Minimap"
    minimap.mouse_filter = Control.MOUSE_FILTER_STOP
    minimap.position = Vector2(10, 10)
    minimap.size = Vector2(200, 200)
    hud.add_child(minimap)
    return hud


func test_action_event_reaches_node_unhandled_input() -> void:
    var probe := NodeProbe.new()
    _root().add_child(probe)
    _root().push_input(_action_event("select_entity"))
    TestHelper.assert_true(
        probe.seen_actions.has("select_entity"),
        "a pushed InputEventAction reaches a Node._unhandled_input"
    )
    probe.free()


func test_left_click_reaches_node_unhandled_input() -> void:
    var probe := NodeProbe.new()
    _root().add_child(probe)
    _root().push_input(_left_click(Vector2(700, 500)))
    TestHelper.assert_true(
        probe.seen_actions.has("select_entity"),
        "a pushed left-click matches select_entity in a Node._unhandled_input"
    )
    probe.free()


func test_left_click_reaches_control_under_node3d() -> void:
    var node3d := Node3D.new()
    var probe := ControlProbe.new()
    node3d.add_child(probe)
    _root().add_child(node3d)
    _root().push_input(_left_click(Vector2(700, 500)))
    TestHelper.assert_true(
        probe.saw_select,
        "a Control under a Node3D still receives pushed mouse input via _unhandled_input"
    )
    node3d.free()


func test_open_world_click_reaches_handler_with_hud_mounted() -> void:
    # Positive path only: HUD Controls being present does not stop an
    # open-world click from reaching `_unhandled_input`. (Consumption cannot be
    # asserted headlessly — see LIMIT above.)
    var probe := NodeProbe.new()
    _root().add_child(probe)
    var hud := _mount_hud_shape()
    _root().push_input(_left_click(Vector2(700, 500)))
    TestHelper.assert_true(
        probe.seen_actions.has("select_entity"),
        "an open-world click reaches _unhandled_input even with HUD Controls mounted"
    )
    probe.free()
    hud.free()


func test_fps_counter_does_not_consume_pointer() -> void:
    # Regression guard for the live bug (#512): the FpsCounter is a full-rect
    # Control; with the default MOUSE_FILTER_STOP it consumed every world click,
    # so mouse placement/cancel never reached `_unhandled_input` while ESC did.
    var scene: PackedScene = load("res://scenes/ui/FPSCounter01.tscn")
    TestHelper.assert_true(scene != null, "FPSCounter scene loads")
    if scene == null:
        return
    var root := scene.instantiate() as Control
    _root().add_child(root)
    var label := root.get_node_or_null("FpsCounterLabel") as Control
    TestHelper.assert_true(
        root.mouse_filter == Control.MOUSE_FILTER_IGNORE,
        "the full-rect FpsCounter root must ignore pointer input"
    )
    if label:
        TestHelper.assert_true(
            label.mouse_filter == Control.MOUSE_FILTER_IGNORE,
            "the FpsCounter label must ignore pointer input"
        )
    root.free()
