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


# Runtime content spawned during match 1 (units, one-shot effects) must be a
# descendant of the active World root and gone from the scene tree once match 2
# starts. Spawns after the swap resolve to the incoming match.
func test_runtime_content_is_released_on_match_swap() -> void:
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
    var first_world: Node = gameplay.get_node_or_null("World")
    TestHelper.assert_true(first_world != null, "the first match created a World root")

    var data := EntityFactory.get_entity_data("GDI_LIGHT_INFANTRY")
    if data == null:
        TestHelper.fail("GDI_LIGHT_INFANTRY fixture missing")
        _teardown(scene)
        return
    var unit := EntityPlacer.place_entity(data, CellUtil.cell_to_world(Vector2i(10, 10)), 0)
    TestHelper.assert_true(unit != null, "a unit spawned through the seam")
    TestHelper.assert_true(
        first_world.is_ancestor_of(unit), "the unit is under the first match World root"
    )

    var fx := FxData.new()
    fx.id = "swap_test_fx"
    fx.kind = FxData.Kind.SPRITE
    fx.animation = &"default"
    fx.sprite_frames = SpriteFrames.new()
    var effect := FxSystem.play(fx, Transform3D.IDENTITY, true)
    TestHelper.assert_true(effect != null, "an effect spawned through the seam")
    if effect != null:
        TestHelper.assert_true(
            first_world.is_ancestor_of(effect), "the effect is under the first match World root"
        )

    _gc.start_mission(MISSION_ID)

    TestHelper.assert_true(
        first_world.is_queued_for_deletion(), "the outgoing World root is released"
    )
    if is_instance_valid(unit):
        TestHelper.assert_true(not unit.is_inside_tree(), "the spawned unit left the scene tree")
    if is_instance_valid(effect):
        TestHelper.assert_true(
            not effect.is_inside_tree(), "the spawned effect left the scene tree"
        )

    var second_world: Node = gameplay.get_node_or_null("World")
    TestHelper.assert_true(second_world != null, "the second match created a World root")
    TestHelper.assert_true(second_world != first_world, "a new World root is active")
    (
        TestHelper
        . assert_true(
            second_world.get_node_or_null("MissionMap") != null,
            "the incoming World root still hosts the mission map",
        )
    )

    var late := EntityPlacer.place_entity(data, CellUtil.cell_to_world(Vector2i(12, 12)), 0)
    TestHelper.assert_true(late != null, "a spawn after the swap resolves")
    TestHelper.assert_true(
        second_world.is_ancestor_of(late), "the later unit belongs to the incoming World root"
    )

    _teardown(scene)
