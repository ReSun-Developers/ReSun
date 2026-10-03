extends Node

# Match replacement on the real scene tree. Booting a second mission through the
# real MainScene must leave exactly one World root, keep the camera pivot on a
# live node of the *active* match (the released match's pivot is detached, not
# reused), and keep the match HUD mounted. The per-slice tests miss this path:
# one drives `_swap_world` with bare maps, the other uses a stub session shell.

const MAIN_SCENE: PackedScene = preload("res://scenes/MainScene.tscn")
const MISSION_ID: String = "gdi01"

var _gc: Node = null


func _bounds() -> Node:
    return _tree().root.get_node_or_null("BoundsSystem")


func _guard() -> bool:
    if _gc == null:
        TestHelper.fail("GameContext not injected")
        return false
    if _bounds() == null:
        TestHelper.fail("BoundsSystem autoload not found")
        return false
    return true


func _tree() -> SceneTree:
    return Engine.get_main_loop() as SceneTree


func _teardown(scene: Node) -> void:
    _gc.current_mission = null
    _tree().paused = false
    var bounds := _bounds()
    if bounds != null:
        bounds.camera_pivot = null
    if is_instance_valid(scene):
        _tree().root.remove_child(scene)
        scene.free()


func test_second_mission_replaces_world_and_rebinds_camera() -> void:
    if not _guard():
        return
    _gc.select_game("ts")
    var scene := MAIN_SCENE.instantiate()
    _tree().root.add_child(scene)

    var gameplay := scene.get_node_or_null("Gameplay") as Node
    TestHelper.assert_true(gameplay != null, "MainScene has a Gameplay node")
    if gameplay == null:
        _teardown(scene)
        return

    _gc.start_mission(MISSION_ID)
    _gc.start_mission(MISSION_ID)

    TestHelper.assert_eq(
        gameplay.get_child_count(), 1, "exactly one World root after a second match"
    )
    var world: Node = gameplay.get_child(0)
    TestHelper.assert_eq(world.name, "World", "the active container is a World root")

    var map := world.get_node_or_null("MissionMap")
    TestHelper.assert_true(map != null, "the second mission map is hosted under the World root")

    var cloud := _tree().get_first_node_in_group("cloud_shadow_overlay")
    TestHelper.assert_true(
        cloud != null, "the map's cloud shadow overlay is registered in its group"
    )
    if cloud != null:
        (
            TestHelper
            . assert_true(
                world.is_ancestor_of(cloud),
                "the cloud shadow overlay belongs to the active World, not the released match",
            )
        )

    var pivot: Node3D = _bounds().get("camera_pivot") as Node3D
    TestHelper.assert_true(is_instance_valid(pivot), "the camera pivot is a live node")
    if is_instance_valid(pivot):
        TestHelper.assert_true(pivot.is_inside_tree(), "the camera pivot is in the scene tree")
        (
            TestHelper
            . assert_true(
                world.is_ancestor_of(pivot),
                "the camera pivot belongs to the active World root, not the released match",
            )
        )

    var shell := scene.get_node_or_null("SessionShell")
    TestHelper.assert_true(shell != null, "MainScene has a session shell")
    if shell != null:
        var surface: Node = shell.get_surface()
        (
            TestHelper
            . assert_true(
                surface != null and surface.name == "HudSurface",
                "the match HUD surface is mounted after the swap",
            )
        )

    _teardown(scene)
