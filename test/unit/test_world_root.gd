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
