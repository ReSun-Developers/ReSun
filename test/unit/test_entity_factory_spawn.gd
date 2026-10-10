extends Node

# EntityFactory.spawn — single insertion seam, detached mode, and the spawn event.

var _ef: Node = null
var _root: Node3D = null
var _saved_buildings: Array = []
var _saved_prereqs: Dictionary = {}
var _saved_building_cells: Dictionary = {}


func _setup() -> void:
    _root = Node3D.new()
    Engine.get_main_loop().root.add_child(_root)
    # A non-detached spawn fires `spawned`, which registers into global
    # singletons; snapshot and restore them so this suite cannot leak state.
    _saved_buildings = BuildingManager._buildings.duplicate()
    BuildingManager._buildings.clear()
    _saved_prereqs = PrerequisiteSystem._player_buildings.duplicate(true)
    PrerequisiteSystem._player_buildings.clear()
    _saved_building_cells = SpatialHash.instance._building_cells.duplicate()
    SpatialHash.instance._building_cells.clear()


func _teardown() -> void:
    if is_instance_valid(_root):
        _root.free()
    _root = null
    BuildingManager._buildings.clear()
    for entry in _saved_buildings:
        BuildingManager._buildings.append(entry)
    PrerequisiteSystem._player_buildings = _saved_prereqs
    SpatialHash.instance._building_cells = _saved_building_cells


func test_spawn_inserts_positioned_player_entity() -> void:
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    _setup()
    var origin := Vector2i(10, 12)
    var world_pos: Vector3 = CellUtil.cell_to_world(origin)
    var entity := (
        _ef.spawn("GDI_LIGHT_INFANTRY", {"world_pos": world_pos, "player_id": 3, "parent": _root})
        as Node3D
    )
    TestHelper.assert_true(entity != null, "spawn returns an entity")
    if entity:
        TestHelper.assert_true(entity.is_inside_tree(), "spawned entity is in the tree")
        TestHelper.assert_true(
            entity.global_position.is_equal_approx(world_pos), "spawned entity is positioned"
        )
        var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
        TestHelper.assert_eq(stats.player_id if stats else -1, 3, "player assigned")
        TestHelper.assert_true(entity.is_in_group("entities"), "world entity joins groups")
    _teardown()


func test_detached_spawn_registers_no_groups_or_events() -> void:
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    _setup()
    var events: Array = []
    var handler := func(e: Node3D, _d: EntityData, p: int) -> void: events.append(p)
    _ef.spawned.connect(handler)
    var entity := (
        _ef.spawn("GDI_LIGHT_INFANTRY", {"detached": true, "player_id": 3, "parent": _root})
        as Node3D
    )
    TestHelper.assert_true(entity != null, "detached spawn returns an entity")
    if entity:
        TestHelper.assert_true(entity.is_inside_tree(), "detached entity is in the tree")
        TestHelper.assert_true(
            entity.has_meta(_ef.DETACHED_META), "detached entity carries the marker"
        )
        TestHelper.assert_true(not entity.is_in_group("entities"), "detached joins no groups")
        var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
        TestHelper.assert_eq(stats.player_id if stats else -2, -1, "detached has no player")
    TestHelper.assert_eq(events.size(), 0, "detached emits no spawn event")
    _ef.spawned.disconnect(handler)
    _teardown()


func test_spawn_event_fires_once_for_world_entity() -> void:
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    _setup()
    var events: Array = []
    var handler := func(_e: Node3D, _d: EntityData, p: int) -> void: events.append(p)
    _ef.spawned.connect(handler)
    _ef.spawn("GDI_LIGHT_INFANTRY", {"detached": true, "parent": _root})
    _ef.spawn("GDI_LIGHT_INFANTRY", {"player_id": 5, "parent": _root})
    TestHelper.assert_eq(events.size(), 1, "one event for one world entity")
    if events.size() == 1:
        TestHelper.assert_eq(events[0], 5, "event carries the player id")
    _ef.spawned.disconnect(handler)
    _teardown()


func test_ordering_player_and_origin_set_before_tree_entry() -> void:
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    _setup()
    var origin := Vector2i(20, 22)
    var foundation := Vector2i(3, 3)
    var world_pos: Vector3 = CellUtil.cell_origin_to_world(origin, foundation)
    var building := (
        _ef.spawn(
            "GDI_CONSTRUCTION_YARD", {"world_pos": world_pos, "player_id": 2, "parent": _root}
        )
        as Node3D
    )
    TestHelper.assert_true(building != null, "building spawned")
    if building:
        var stats := building.get_node_or_null("StatsComponent") as StatsComponent
        TestHelper.assert_eq(stats.player_id if stats else -1, 2, "building player before entry")
        var derived := CellUtil.world_to_cell_origin(building.global_position, foundation)
        TestHelper.assert_eq(derived, origin, "origin cell derived from pre-entry position")
    _teardown()
