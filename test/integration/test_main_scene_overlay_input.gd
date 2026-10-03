extends Node

# Regression test for the MainScene menu-overlay click blocker.
#
# The menu surface (`SessionShell/MenuSurface/UI`) sits above the gameplay HUD
# (both CanvasLayers use layer 256; the menu surface is mounted first and the
# match HUD replaces it). When that container kept the default Control mouse
# filter (STOP) it swallowed every mouse click aimed at gameplay UI — the
# mission briefing's button was visible but unclickable.
#
# The container MUST NOT intercept mouse input; only its own visible children
# (menus, dialogs) may. This test fails on the broken scene and passes once the
# container ignores the mouse.

const MAIN_SCENE: String = "res://scenes/MainScene.tscn"


func _tree() -> SceneTree:
    return Engine.get_main_loop() as SceneTree


## MainScene mounted in the tree so SessionShell mounts the menu surface in
## _ready. The caller owns cleanup via `_drop`.
func _mounted_scene() -> Node:
    var scene := (load(MAIN_SCENE) as PackedScene).instantiate()
    _tree().root.add_child(scene)
    return scene


func _drop(scene: Node) -> void:
    if is_instance_valid(scene):
        _tree().root.remove_child(scene)
        scene.free()


func test_menu_overlay_container_ignores_mouse() -> void:
    var scene := _mounted_scene()
    var ui := scene.get_node_or_null("SessionShell/MenuSurface/UI") as Control
    TestHelper.assert_true(ui != null, "the menu surface has a UI overlay container")
    if ui != null:
        (
            TestHelper
            . assert_eq(
                ui.mouse_filter,
                Control.MOUSE_FILTER_IGNORE,
                "menu overlay container must not consume gameplay clicks",
            )
        )
    _drop(scene)


func test_menu_overlay_container_is_full_rect() -> void:
    var scene := _mounted_scene()
    var ui := scene.get_node_or_null("SessionShell/MenuSurface/UI") as Control
    if ui == null:
        TestHelper.fail("the menu surface has no UI overlay container")
    else:
        # Full-rect is why an overlay with the default filter blocked gameplay
        # everywhere, not just under a visible menu. The container stays
        # full-rect; the mouse filter is what makes it safe.
        TestHelper.assert_true(ui.anchor_right == 1.0, "overlay spans the width")
        TestHelper.assert_true(ui.anchor_bottom == 1.0, "overlay spans the height")
    _drop(scene)


func test_main_menu_still_loads() -> void:
    # Guard against a fix that removes the menu: MainMenu01 is still mounted.
    var scene := _mounted_scene()
    var menu := scene.get_node_or_null("SessionShell/MenuSurface/UI/MainMenu01") as Control
    TestHelper.assert_true(menu != null, "MainMenu01 is still mounted in the menu surface")
    _drop(scene)


func test_main_scene_root_is_not_a_subviewport() -> void:
    # A Window/SubViewport root renders gameplay into its own viewport, so the
    # autoload overlays that live in the root viewport (SelectionOverlay brackets,
    # MoveLineRenderer move lines, FogRenderer) resolve no camera and draw
    # underneath gameplay. The entry scene must be a plain Node so gameplay and
    # the overlays share the root viewport.
    var scene := (load(MAIN_SCENE) as PackedScene).instantiate()
    (
        TestHelper
        . assert_true(
            not (scene is Window) and not (scene is SubViewport),
            "MainScene root must not be a sub-viewport",
        )
    )
    TestHelper.assert_true(scene is Node, "MainScene root is a Node")
    scene.free()
