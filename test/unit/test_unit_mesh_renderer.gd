extends Node

# UnitMeshRenderer must: register entities into per-region MultiMesh buckets
# (hiding the GLB tree), swap-remove slots on unregister, migrate buckets when
# units cross region boundaries, and eject preview/disabled entities back to
# node-tree rendering. Instance transforms aren't readable in headless (dummy
# rasterizer), so assertions target registry bookkeeping, visible counts, and
# the MultiMesh custom_aabb.

const MODEL_PATH := "res://games/ts/assets/models/nod_buggy01.glb"

const STATS_SCRIPT: GDScript = preload("res://scripts/components/StatsComponent.gd")

var _renderer: UnitMeshRenderer
var _container: Node3D


func _tree() -> SceneTree:
    return Engine.get_main_loop() as SceneTree


func _setup() -> void:
    _renderer = _tree().root.get_node_or_null("UnitMeshRenderer") as UnitMeshRenderer
    TestHelper.assert_true(_renderer != null, "UnitMeshRenderer autoload present")
    _renderer.clear_all()
    _container = Node3D.new()
    _container.name = "UMRTestContainer"
    _tree().root.add_child(_container)


func _teardown() -> void:
    _renderer.clear_all()
    if is_instance_valid(_container):
        _tree().root.remove_child(_container)
        _container.queue_free()


func _make_unit(pos: Vector3) -> Node3D:
    var entity := Node3D.new()
    entity.position = pos
    var model_root := Node3D.new()
    model_root.name = "ModelRoot"
    entity.add_child(model_root)
    _container.add_child(entity)
    return entity


func _make_unit_with_player(pos: Vector3, player_id: int) -> Node3D:
    var entity := _make_unit(pos)
    var stats := Node.new()
    stats.name = "StatsComponent"
    stats.set_script(STATS_SCRIPT)
    entity.add_child(stats)
    stats.player_id = player_id
    return entity


func _register(entity: Node3D) -> bool:
    return _renderer.register(
        entity, MODEL_PATH, entity.get_node("ModelRoot") as Node3D, Transform3D.IDENTITY, false
    )


func _bucket(region: Vector2i) -> Dictionary:
    var region_map: Dictionary = _renderer._buckets.get(region, {})
    return region_map.get(MODEL_PATH, {})


func test_register_hides_model_and_allocates_slot():
    _setup()
    var entity := _make_unit(Vector3(10.0, 0.0, 10.0))
    var model_root := entity.get_node("ModelRoot") as Node3D
    TestHelper.assert_true(_register(entity), "register succeeds")
    TestHelper.assert_true(_renderer._registry.has(entity), "entity registered")
    TestHelper.assert_true(not model_root.visible, "GLB node tree hidden")
    var entry: Dictionary = _renderer._registry[entity]
    TestHelper.assert_eq(entry["slot"], 0, "first slot allocated")
    var region := _renderer._region_key(entity.global_position)
    TestHelper.assert_eq(entry["region"], region, "region matches")
    var bucket := _bucket(region)
    TestHelper.assert_true(not bucket.is_empty(), "bucket created")
    TestHelper.assert_eq(int(bucket["active_count"]), 1, "one active instance")
    var mm_bucket: MultiMesh = bucket["multimesh"]
    TestHelper.assert_eq(mm_bucket.visible_instance_count, 1, "visible count 1")
    TestHelper.assert_true(_renderer.is_physics_processing(), "physics processing enabled")
    _teardown()
    _finish()


func test_register_rejects_preview_and_disabled_entities():
    _setup()
    var preview_entity := _make_unit(Vector3(5.0, 0.0, 5.0))
    preview_entity.set_meta("detached", true)
    TestHelper.assert_true(not _register(preview_entity), "detached entity rejected")
    var disabled_entity := _make_unit(Vector3(6.0, 0.0, 6.0))
    disabled_entity.process_mode = Node.PROCESS_MODE_DISABLED
    TestHelper.assert_true(not _register(disabled_entity), "PROCESS_MODE_DISABLED entity rejected")
    TestHelper.assert_eq(_renderer._active_count, 0, "nothing registered")
    _teardown()
    _finish()


func test_swap_remove_compacts_slots():
    _setup()
    var a := _make_unit(Vector3(2.0, 0.0, 2.0))
    var b := _make_unit(Vector3(4.0, 0.0, 4.0))
    var c := _make_unit(Vector3(6.0, 0.0, 6.0))
    TestHelper.assert_true(_register(a), "register a")
    TestHelper.assert_true(_register(b), "register b")
    TestHelper.assert_true(_register(c), "register c")
    TestHelper.assert_eq(_renderer._active_count, 3, "three registered")
    TestHelper.assert_eq(_renderer._registry[b]["slot"], 1, "b in middle slot")
    _renderer.unregister(b)
    TestHelper.assert_true(not _renderer._registry.has(b), "b removed")
    TestHelper.assert_eq(_renderer._active_count, 2, "two remain")
    TestHelper.assert_eq(_renderer._registry[a]["slot"], 0, "first slot unchanged")
    TestHelper.assert_eq(_renderer._registry[c]["slot"], 1, "last slot moved into freed slot")
    var region := _renderer._region_key(a.global_position)
    var bucket := _bucket(region)
    TestHelper.assert_eq(int(bucket["active_count"]), 2, "active count compacted")
    var mm_compacted: MultiMesh = bucket["multimesh"]
    TestHelper.assert_eq(mm_compacted.visible_instance_count, 2, "visible count 2")
    _teardown()
    _finish()


func test_migration_across_region_boundary():
    _setup()
    var entity := _make_unit(Vector3(2.0, 0.0, 2.0))
    var old_region := _renderer._region_key(entity.global_position)
    TestHelper.assert_true(_register(entity), "register in region %s" % old_region)
    TestHelper.assert_true(_renderer._buckets.has(old_region), "old region bucket exists")
    entity.global_position = Vector3(1000.0, 0.0, 1000.0)
    var new_region := _renderer._region_key(entity.global_position)
    TestHelper.assert_true(new_region != old_region, "position crosses region boundary")
    _renderer._physics_process(0.0)
    var entry: Dictionary = _renderer._registry[entity]
    TestHelper.assert_eq(entry["region"], new_region, "entry migrated")
    TestHelper.assert_true(_renderer._buckets.has(new_region), "new region bucket exists")
    TestHelper.assert_true(not _renderer._buckets.has(old_region), "empty old bucket removed")
    var new_bucket := _bucket(new_region)
    TestHelper.assert_eq(int(new_bucket["active_count"]), 1, "one instance in new region")
    var mm_migrated: MultiMesh = new_bucket["multimesh"]
    TestHelper.assert_eq(mm_migrated.visible_instance_count, 1, "one visible in new region")
    _teardown()
    _finish()


func test_preview_ejects_and_restores_model():
    _setup()
    var entity := _make_unit(Vector3(2.0, 0.0, 2.0))
    var model_root := entity.get_node("ModelRoot") as Node3D
    TestHelper.assert_true(_register(entity), "register")
    TestHelper.assert_true(not model_root.visible, "hidden after register")
    entity.process_mode = Node.PROCESS_MODE_DISABLED
    _renderer._physics_process(0.0)
    TestHelper.assert_true(model_root.visible, "GLB shown while previewing")
    entity.process_mode = Node.PROCESS_MODE_INHERIT
    _renderer._physics_process(0.0)
    TestHelper.assert_true(not model_root.visible, "GLB hidden after finalize")
    _teardown()
    _finish()


func test_bucket_sets_aabb_and_disables_interpolation():
    _setup()
    var entity := _make_unit(Vector3(2.0, 0.0, 2.0))
    TestHelper.assert_true(_register(entity), "register")
    var region := _renderer._region_key(entity.global_position)
    var bucket := _bucket(region)
    var multimesh: MultiMesh = bucket["multimesh"]
    var expected := _renderer._region_aabb(region)
    (
        TestHelper
        . assert_true(
            (
                multimesh.custom_aabb.position.is_equal_approx(expected.position)
                and multimesh.custom_aabb.size.is_equal_approx(expected.size)
            ),
            "custom_aabb set to region box",
        )
    )
    var mmi: MultiMeshInstance3D = bucket["mmi"]
    TestHelper.assert_eq(
        mmi.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF, "interpolation off"
    )
    _teardown()
    _finish()


func test_migration_into_full_region_keeps_entity_visible():
    _setup()
    # Fill region (0,0) with MAX_INSTANCES entities.
    var max_instances := UnitMeshRenderer.MAX_INSTANCES_PER_REGION
    var fill_a: Array[Node3D] = []
    for i in max_instances:
        var e := _make_unit(Vector3(float(i % 32), 0.0, float(i / 32)))
        fill_a.append(e)
        TestHelper.assert_true(_register(e), "register a %d" % i)
    TestHelper.assert_eq(_renderer._active_count, max_instances, "region A full")
    # Fill region (1,1) with MAX_INSTANCES entities (x,z within [32,64)).
    var fill_b: Array[Node3D] = []
    for i in max_instances:
        var e := _make_unit(Vector3(32.0 + float(i % 32), 0.0, 32.0 + float(i / 32)))
        fill_b.append(e)
        TestHelper.assert_true(_register(e), "register b %d" % i)
    TestHelper.assert_eq(_renderer._active_count, max_instances * 2, "both regions full")
    # Move one entity from region A into the full region B.
    var mover := fill_a[0]
    var model_root := mover.get_node("ModelRoot") as Node3D
    mover.global_position = Vector3(50.0, 0.0, 50.0)
    _renderer._physics_process(0.0)
    var entry: Dictionary = _renderer._registry[mover]
    TestHelper.assert_eq(entry["slot"], -1, "no slot in full target region")
    TestHelper.assert_true(model_root.visible, "GLB shown when no MultiMesh slot available")
    _teardown()
    _finish()


# ========================================
# Fog culling
# ========================================

var _ts: Node = null
var _pm: Node = null
var _ss: Node = null
var _fog_was := false
var _shroud_was := true
var _saved_insets := Vector4i(0, 0, 0, 0)


func _fog_setup() -> void:
    _ts = _tree().root.get_node_or_null("TerrainSystem")
    _pm = _tree().root.get_node_or_null("PlayerManager")
    _ss = _tree().root.get_node_or_null("ShroudSystem")
    _ts.init_grid(50, 50)
    _saved_insets = Vector4i(
        BoundsSystem.left_inset,
        BoundsSystem.right_inset,
        BoundsSystem.top_inset,
        BoundsSystem.bottom_inset,
    )
    BoundsSystem.left_inset = BoundsSystem.DEFAULT_VISIBLE_INSETS.x
    BoundsSystem.right_inset = BoundsSystem.DEFAULT_VISIBLE_INSETS.y
    BoundsSystem.top_inset = BoundsSystem.DEFAULT_VISIBLE_INSETS.z
    BoundsSystem.bottom_inset = BoundsSystem.DEFAULT_VISIBLE_INSETS.w
    _pm._players.clear()
    _pm._local_player_id = 0
    _pm._init_defaults()
    var rules := GlobalRules.get_current()
    _fog_was = rules.fog_of_war
    _shroud_was = rules.shroud_enabled
    rules.fog_of_war = true
    rules.shroud_enabled = true


func _fog_teardown() -> void:
    BoundsSystem.left_inset = _saved_insets.x
    BoundsSystem.right_inset = _saved_insets.y
    BoundsSystem.top_inset = _saved_insets.z
    BoundsSystem.bottom_inset = _saved_insets.w
    var rules := GlobalRules.get_current()
    rules.fog_of_war = _fog_was
    rules.shroud_enabled = _shroud_was


func _cell_world(cell: Vector2i) -> Vector3:
    return CellUtil.cell_to_world(cell)


func _tick(_entity: Node3D) -> void:
    _renderer._physics_process(0.0)


func test_fog_culls_enemy_unit_in_shroud():
    _setup()
    _fog_setup()
    var cell := Vector2i(40, 40)
    var enemy := _make_unit_with_player(_cell_world(cell), 1)
    TestHelper.assert_true(_register(enemy), "enemy registered")
    _tick(enemy)
    TestHelper.assert_true(_renderer._registry[enemy]["hidden"], "enemy hidden in shroud")
    TestHelper.assert_true(not _renderer._registry[enemy]["slot"] < 0, "slot retained while hidden")
    _fog_teardown()
    _teardown()
    _finish()


func test_fog_shows_enemy_when_visible():
    _setup()
    _fog_setup()
    var cell := Vector2i(40, 40)
    var enemy := _make_unit_with_player(_cell_world(cell), 1)
    TestHelper.assert_true(_register(enemy), "enemy registered")
    ShroudSystem.register_revealer(0, cell, 5, 0.0, true)
    _tick(enemy)
    TestHelper.assert_true(not _renderer._registry[enemy]["hidden"], "enemy shown when visible")
    _fog_teardown()
    _teardown()
    _finish()


func test_fog_never_hides_friendly_unit():
    _setup()
    _fog_setup()
    var cell := Vector2i(40, 40)
    var friendly := _make_unit_with_player(_cell_world(cell), 0)
    TestHelper.assert_true(_register(friendly), "friendly registered")
    _tick(friendly)
    TestHelper.assert_true(not _renderer._registry[friendly]["hidden"], "friendly never hidden")
    _fog_teardown()
    _teardown()
    _finish()


func test_fog_unhide_resumes_sync():
    _setup()
    _fog_setup()
    var cell := Vector2i(40, 40)
    var enemy := _make_unit_with_player(_cell_world(cell), 1)
    TestHelper.assert_true(_register(enemy), "enemy registered")
    _tick(enemy)
    TestHelper.assert_true(_renderer._registry[enemy]["hidden"], "hidden while shrouded")
    ShroudSystem.register_revealer(0, cell, 5, 0.0, true)
    _tick(enemy)
    TestHelper.assert_true(not _renderer._registry[enemy]["hidden"], "unhidden once cell visible")
    _fog_teardown()
    _teardown()
    _finish()


func test_fog_disabled_is_inert():
    _setup()
    _fog_setup()
    var rules := GlobalRules.get_current()
    rules.fog_of_war = false
    rules.shroud_enabled = false
    var cell := Vector2i(40, 40)
    var enemy := _make_unit_with_player(_cell_world(cell), 1)
    TestHelper.assert_true(_register(enemy), "enemy registered")
    _tick(enemy)
    TestHelper.assert_true(not _renderer._registry[enemy]["hidden"], "no culling when fog off")
    _fog_teardown()
    _teardown()
    _finish()


func test_fog_region_migration_while_hidden():
    _setup()
    _fog_setup()
    var cell_a := Vector2i(40, 40)
    var enemy := _make_unit_with_player(_cell_world(cell_a), 1)
    var old_region := _renderer._region_key(enemy.global_position)
    TestHelper.assert_true(_register(enemy), "enemy registered")
    _tick(enemy)
    TestHelper.assert_true(_renderer._registry[enemy]["hidden"], "hidden while shrouded")
    var new_pos := Vector3(-33.0, 0.0, -33.0)
    enemy.global_position = new_pos
    var new_cell := CellUtil.world_to_cell(new_pos)
    TestHelper.assert_true(BoundsSystem.is_in_play_area(new_cell), "target cell in play area")
    _tick(enemy)
    TestHelper.assert_true(
        _renderer._registry[enemy]["region"] == old_region, "no migration while hidden"
    )
    ShroudSystem.register_revealer(0, new_cell, 5, 0.0, true)
    _tick(enemy)
    var new_region := _renderer._region_key(enemy.global_position)
    TestHelper.assert_true(
        _renderer._registry[enemy]["region"] == new_region, "migrates once visible again"
    )
    TestHelper.assert_true(
        _renderer._buckets.has(new_region), "new region bucket exists after unhide"
    )
    _fog_teardown()
    _teardown()
    _finish()


func test_fog_freezes_enemy_in_explored_fog():
    _setup()
    _fog_setup()
    var cell := Vector2i(40, 40)
    var enemy := _make_unit_with_player(_cell_world(cell), 1)
    TestHelper.assert_true(_register(enemy), "enemy registered")
    ShroudSystem.explore_area(0, cell, 1)
    _ss.resolve_dirty()
    _tick(enemy)
    var entry: Dictionary = _renderer._registry[enemy]
    TestHelper.assert_true(entry["fogged"], "enemy frozen as ghost in explored fog")
    TestHelper.assert_true(not entry["hidden"], "ghost not parked off-world")
    TestHelper.assert_true(not entry["slot"] < 0, "ghost slot retained")
    _fog_teardown()
    _teardown()
    _finish()


func test_fog_off_no_ghost_in_explored_cell():
    _setup()
    _fog_setup()
    var rules := GlobalRules.get_current()
    rules.fog_of_war = false
    var cell := Vector2i(40, 40)
    var enemy := _make_unit_with_player(_cell_world(cell), 1)
    TestHelper.assert_true(_register(enemy), "enemy registered")
    ShroudSystem.explore_area(0, cell, 1)
    _ss.resolve_dirty()
    _tick(enemy)
    var entry: Dictionary = _renderer._registry[enemy]
    TestHelper.assert_true(not entry["fogged"], "no ghost when fog of war off")
    TestHelper.assert_true(not entry["hidden"], "enemy not hidden in explored cell")
    _fog_teardown()
    _teardown()
    _finish()


func test_fog_freeze_resumes_on_reveal():
    _setup()
    _fog_setup()
    var cell := Vector2i(40, 40)
    var enemy := _make_unit_with_player(_cell_world(cell), 1)
    TestHelper.assert_true(_register(enemy), "enemy registered")
    ShroudSystem.explore_area(0, cell, 1)
    _ss.resolve_dirty()
    _tick(enemy)
    TestHelper.assert_true(_renderer._registry[enemy]["fogged"], "frozen in fog")
    ShroudSystem.register_revealer(0, cell, 5, 0.0, true)
    _tick(enemy)
    TestHelper.assert_true(
        not _renderer._registry[enemy]["fogged"], "resumes syncing once cell visible"
    )
    TestHelper.assert_true(not _renderer._registry[enemy]["hidden"], "not hidden when visible")
    _fog_teardown()
    _teardown()
    _finish()


func test_fog_frozen_ghost_no_region_migration():
    _setup()
    _fog_setup()
    var cell_a := Vector2i(40, 40)
    var enemy := _make_unit_with_player(_cell_world(cell_a), 1)
    var old_region := _renderer._region_key(enemy.global_position)
    TestHelper.assert_true(_register(enemy), "enemy registered")
    ShroudSystem.explore_area(0, cell_a, 1)
    _ss.resolve_dirty()
    _tick(enemy)
    TestHelper.assert_true(_renderer._registry[enemy]["fogged"], "frozen in fog")
    var new_pos := Vector3(-33.0, 0.0, -33.0)
    enemy.global_position = new_pos
    var new_cell := CellUtil.world_to_cell(new_pos)
    TestHelper.assert_true(BoundsSystem.is_in_play_area(new_cell), "target cell in play area")
    _tick(enemy)
    TestHelper.assert_true(
        _renderer._registry[enemy]["region"] == old_region, "no migration while ghosted"
    )
    _fog_teardown()
    _teardown()
    _finish()


func _finish() -> void:
    pass


# ========================================
# Socket instances (turret track)
# ========================================

const SOCKET_KEY := "__socket:test"


func _socket_mesh() -> ArrayMesh:
    var box := BoxMesh.new()
    box.size = Vector3(0.6, 0.4, 0.8)
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.surface_get_arrays(0))
    return mesh


func _socket_desc(id: String, pivot: Transform3D) -> Dictionary:
    return {"id": id, "key": SOCKET_KEY, "mesh": _socket_mesh(), "pivot": pivot}


func _register_with_sockets(entity: Node3D, sockets: Array) -> bool:
    return (
        _renderer
        . register(
            entity,
            MODEL_PATH,
            entity.get_node("ModelRoot") as Node3D,
            Transform3D.IDENTITY,
            false,
            sockets,
        )
    )


func test_sockets_allocate_with_body():
    _setup()
    var entity := _make_unit(Vector3(2.0, 0.0, 2.0))
    var sockets := [
        _socket_desc("l", Transform3D(Basis(), Vector3(-1, 0, 0))),
        _socket_desc("r", Transform3D(Basis(), Vector3(1, 0, 0))),
    ]
    TestHelper.assert_true(_register_with_sockets(entity, sockets), "register with sockets")
    var entry: Dictionary = _renderer._registry[entity]
    TestHelper.assert_eq(entry["sockets"].size(), 2, "two socket instances registered")
    TestHelper.assert_true(int(entry["sockets"][0]["slot"]) >= 0, "socket slot allocated")
    var region: Vector2i = entry["region"]
    var bucket: Dictionary = _renderer._buckets[region].get(SOCKET_KEY, {})
    TestHelper.assert_eq(int(bucket["active_count"]), 2, "twin sockets share one bucket")
    var mm: MultiMesh = bucket["multimesh"]
    TestHelper.assert_eq(mm.visible_instance_count, 2, "two socket instances visible")
    _teardown()
    _finish()


func test_socket_world_uses_pivot_without_turret():
    _setup()
    var entity := _make_unit(Vector3(2.0, 0.0, 2.0))
    var sockets := [_socket_desc("main", Transform3D(Basis(), Vector3(1, 0, 0)))]
    _register_with_sockets(entity, sockets)
    var entry: Dictionary = _renderer._registry[entity]
    var world := _renderer._socket_world(entity, entry["sockets"][0], null)
    (
        TestHelper
        . assert_true(
            world.origin.is_equal_approx(Vector3(3.0, 0.0, 2.0)),
            "socket world = entity transform + pivot (fixed rest orientation)",
        )
    )
    _teardown()
    _finish()


func test_socket_group_migrates_across_region():
    _setup()
    var entity := _make_unit(Vector3(2.0, 0.0, 2.0))
    _register_with_sockets(entity, [_socket_desc("main", Transform3D.IDENTITY)])
    var old_region: Vector2i = _renderer._registry[entity]["sockets"][0]["region"]
    entity.global_position = Vector3(1000.0, 0.0, 1000.0)
    _renderer._physics_process(0.0)
    var entry: Dictionary = _renderer._registry[entity]
    var new_region: Vector2i = entry["region"]
    TestHelper.assert_true(new_region != old_region, "body migrated")
    TestHelper.assert_eq(entry["sockets"][0]["region"], new_region, "socket migrated with body")
    TestHelper.assert_true(not _renderer._buckets.has(old_region), "old socket bucket removed")
    _teardown()
    _finish()


func test_twin_socket_compaction_keeps_indices():
    _setup()
    var a := _make_unit(Vector3(2.0, 0.0, 2.0))
    var b := _make_unit(Vector3(4.0, 0.0, 4.0))
    var sockets := [
        _socket_desc("l", Transform3D(Basis(), Vector3(-1, 0, 0))),
        _socket_desc("r", Transform3D(Basis(), Vector3(1, 0, 0))),
    ]
    _register_with_sockets(a, sockets)
    _register_with_sockets(b, sockets)
    TestHelper.assert_eq(int(_renderer._registry[a]["sockets"][0]["slot"]), 0, "a socket 0")
    TestHelper.assert_eq(int(_renderer._registry[b]["sockets"][0]["slot"]), 2, "b socket 2")
    _renderer.unregister(a)
    var b_entry: Dictionary = _renderer._registry[b]
    var s0: int = b_entry["sockets"][0]["slot"]
    var s1: int = b_entry["sockets"][1]["slot"]
    (
        TestHelper
        . assert_true(
            (s0 == 0 and s1 == 1) or (s0 == 1 and s1 == 0),
            "both b sockets retargeted into the compacted range",
        )
    )
    TestHelper.assert_true(s0 != s1, "socket slots stay distinct after compaction")
    var bucket: Dictionary = _renderer._buckets[b_entry["region"]][SOCKET_KEY]
    TestHelper.assert_eq(int(bucket["active_count"]), 2, "bucket compacted to two")
    _teardown()
    _finish()
