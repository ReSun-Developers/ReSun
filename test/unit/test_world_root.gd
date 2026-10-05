extends Node

# World root — every per-match scene node lives under one container that is
# replaced wholesale on the next match, so nothing from the previous match
# (map, entities) survives. Drives MissionBoot's swap seam directly.

const MISSION_BOOT_SCRIPT: GDScript = preload("res://scripts/maps/MissionBoot.gd")


func _gameplay() -> Node:
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    var gameplay := Node.new()
    gameplay.name = "WorldRootTestGameplay"
    tree.root.add_child(gameplay)
    return gameplay


func _drop(gameplay: Node) -> void:
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    if is_instance_valid(gameplay):
        tree.root.remove_child(gameplay)
        gameplay.free()


func test_world_root_hosts_the_map():
    var boot: Node = MISSION_BOOT_SCRIPT.new()
    var gameplay := _gameplay()
    var map := Node.new()
    map.name = "MissionMap"

    var world: Node = boot._swap_world(gameplay, map)

    TestHelper.assert_true(world != null, "swap returns a World root")
    TestHelper.assert_eq(world.name, "World", "the root is named World")
    TestHelper.assert_eq(gameplay.get_child_count(), 1, "exactly one World root under Gameplay")
    TestHelper.assert_true(gameplay.get_child(0) == world, "the World root is Gameplay's child")
    TestHelper.assert_true(map.get_parent() == world, "the map is hosted under the World root")

    _drop(gameplay)
    boot.free()


func test_second_match_replaces_the_world_root():
    var boot: Node = MISSION_BOOT_SCRIPT.new()
    var gameplay := _gameplay()
    var first: Node = boot._swap_world(gameplay, Node.new())
    var first_map: Node = first.get_child(0)
    TestHelper.assert_eq(gameplay.get_child_count(), 1, "one World root after the first match")

    var second: Node = boot._swap_world(gameplay, Node.new())

    TestHelper.assert_true(gameplay.get_child(0) == second, "the new World root is active")
    TestHelper.assert_eq(gameplay.get_child_count(), 1, "only one World root after the swap")
    TestHelper.assert_true(first.get_parent() == null, "the previous World root is detached")
    TestHelper.assert_true(
        not first_map.is_inside_tree(), "the previous map is out of the scene tree"
    )
    TestHelper.assert_true(first.is_queued_for_deletion(), "the previous World root is freed")

    _drop(gameplay)
    boot.free()


func test_accessor_rejects_detached_world():
    var boot: Node = MISSION_BOOT_SCRIPT.new()
    var gameplay := _gameplay()
    var world: Node = boot._swap_world(gameplay, Node.new())

    TestHelper.assert_true(World.get_active() == world, "the live World root is active")

    world.queue_free()
    gameplay.remove_child(world)
    TestHelper.assert_true(World.get_active() == null, "a detached World root is no longer active")

    _drop(gameplay)
    boot.free()


func test_spawn_container_prefers_the_live_world():
    var boot: Node = MISSION_BOOT_SCRIPT.new()
    var gameplay := _gameplay()
    var world: Node = boot._swap_world(gameplay, Node.new())

    var entity := Node3D.new()
    var container: Node = World.spawn_container(World.Bucket.ENTITIES)
    (
        TestHelper
        . assert_true(
            container == world.get_node_or_null(World.ENTITIES_NAME),
            "spawn container is the active World's Entities bucket",
        )
    )
    container.add_child(entity)
    TestHelper.assert_true(
        world.is_ancestor_of(entity), "the spawned node is a descendant of the World root"
    )

    _drop(gameplay)
    boot.free()


func test_spawn_container_falls_back_without_world():
    if World.get_active() != null:
        TestHelper.fail("a World was left active by an earlier test")
        return
    var host := Node3D.new()
    (Engine.get_main_loop() as SceneTree).root.add_child(host)

    var container: Node = World.spawn_container(World.Bucket.ENTITIES, host)
    TestHelper.assert_true(
        container == host, "spawn container falls back to the explicit parent with no World"
    )

    host.free()


func test_accessor_rejects_queued_world():
    var boot: Node = MISSION_BOOT_SCRIPT.new()
    var gameplay := _gameplay()
    var world: Node = boot._swap_world(gameplay, Node.new())

    # Queued but not yet detached: the accessor must reject it so a swap in
    # progress does not route spawns into the outgoing match.
    world.queue_free()
    TestHelper.assert_true(World.get_active() == null, "a World queued for deletion is not active")

    gameplay.remove_child(world)
    _drop(gameplay)
    boot.free()


func test_spawn_container_uses_current_scene_without_world():
    if World.get_active() != null:
        TestHelper.fail("a World was left active by an earlier test")
        return
    var tree := Engine.get_main_loop() as SceneTree
    var previous := tree.current_scene
    var scene := Node3D.new()
    tree.root.add_child(scene)
    tree.current_scene = scene

    var container: Node = World.spawn_container(World.Bucket.ENTITIES)
    TestHelper.assert_true(
        container == scene, "spawn container falls back to the current scene with no World"
    )

    tree.current_scene = previous
    scene.free()


func test_preview_ghost_is_parented_under_the_world():
    var data := EntityFactory.get_entity_data("GDI_LIGHT_INFANTRY")
    if data == null:
        TestHelper.fail("GDI_LIGHT_INFANTRY fixture missing")
        return
    var boot: Node = MISSION_BOOT_SCRIPT.new()
    var gameplay := _gameplay()
    var world: Node = boot._swap_world(gameplay, Node.new())

    EntityPlacer.start_preview(data)
    var preview: Node = EntityPlacer._preview
    (
        TestHelper
        . assert_true(
            preview != null and world.is_ancestor_of(preview),
            "the placement preview ghost is parented under the World root",
        )
    )
    EntityPlacer.cancel_preview()

    _drop(gameplay)
    boot.free()
