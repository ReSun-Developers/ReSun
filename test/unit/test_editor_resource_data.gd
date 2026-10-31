extends Node

# Editor resource tools resolve their painted entity from registered data.

const _SAVE_LOAD := preload("res://scripts/editor/EditorSaveLoad.gd")

const CRYSTAL_ID: String = "TEST_PRIMARY_CRYSTAL"
const CRYSTAL_B_ID: String = "TEST_SECONDARY_CRYSTAL"
const TREE_ID: String = "TEST_PRIMARY_TREE"
const CATEGORY: String = "test_ore"

var _ef: Node = null
var _saved_rules: GlobalRules = null


class FakeEditor:
    extends Node3D
    var _painted_entities: Dictionary = {}

    func _cell_world_pos(cell: Vector2i) -> Vector3:
        return Vector3(float(cell.x), 0.0, float(cell.y))


func _register(
    id: String,
    resource_type: String,
    strength: int,
    category: String,
    spawner: bool,
    spawned_id: String
) -> void:
    var data := EntityData.new()
    data.id = id
    data.display_name = id
    data.entity_type = EntityData.EntityType.TERRAIN
    data.strength = strength
    data.owner = ["Neutral"]
    data.foundation = Vector2i(1, 1)
    data.resource_category = category
    data.resource_type_id = resource_type
    data.resource_spawner = spawner
    data.spawned_entity_id = spawned_id
    data.procedural_resource_visual = true
    EntityFactory._entity_cache[id] = data


func _setup() -> void:
    _saved_rules = EntityFactory.get_global_rules()
    var rules := GlobalRules.new()
    rules.primary_resource_category = CATEGORY
    EntityFactory.set_global_rules(rules)
    _register(CRYSTAL_ID, "test_green", 420, CATEGORY, false, "")
    _register(TREE_ID, "", 0, "test_ore_tree", true, CRYSTAL_ID)


func _teardown() -> void:
    for id in [CRYSTAL_ID, CRYSTAL_B_ID, TREE_ID]:
        EntityFactory._entity_cache.erase(id)
    EntityFactory.set_global_rules(_saved_rules)


func _make_painter(editor: Node3D) -> Node:
    var painter = preload("res://scripts/editor/ResourcePainter.gd").new()
    painter.editor = editor
    return painter


func _make_placer(editor: Node3D) -> Node:
    var placer = preload("res://scripts/editor/EntityPlacer.gd").new()
    placer.editor = editor
    return placer


func test_paint_uses_registered_crystal_id_type_and_strength() -> void:
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    _setup()
    var editor := FakeEditor.new()
    var painter := _make_painter(editor)
    painter._paint_resource_cell(Vector2i(5, 3), "5,3")
    var entry: Dictionary = editor._painted_entities.get("5,3", {})
    TestHelper.assert_eq(
        entry.get("data", {}).get("id", ""), CRYSTAL_ID, "painted id comes from registered data"
    )
    var node := entry.get("node") as Node3D
    TestHelper.assert_true(node != null, "painted entity was created")
    if node:
        TestHelper.assert_true(node.get_parent() == editor, "painted entity is parented to editor")
        var res := node.get_node_or_null("ResourceComponent") as ResourceComponent
        TestHelper.assert_true(res != null, "painted entity has a ResourceComponent")
        if res:
            TestHelper.assert_eq(
                res.resource_type_id, "test_green", "painted type comes from registered data"
            )
        var hp := node.get_node_or_null("HealthComponent") as HealthComponent
        (
            TestHelper
            . assert_eq(
                hp.current_health if hp else -1,
                210,
                "health is strength% of the registered entity's strength",
            )
        )
    var saved := _SAVE_LOAD.build_entity_entry(entry.get("data", {}))
    TestHelper.assert_eq(saved.get("id", ""), CRYSTAL_ID, "saved entry keeps the resolved id")
    TestHelper.assert_eq(
        int(saved.get("strength", 0)), 210, "saved entry keeps the painted strength"
    )
    TestHelper.assert_true(
        not saved.has("resource_type_id"), "saved entry drops the redundant type override"
    )
    painter.free()
    editor.free()
    _teardown()


func test_paint_follows_changed_primary_crystal() -> void:
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    _setup()
    var editor := FakeEditor.new()
    var painter := _make_painter(editor)
    painter._paint_resource_cell(Vector2i(1, 1), "1,1")
    (
        TestHelper
        . assert_eq(
            editor._painted_entities.get("1,1", {}).get("data", {}).get("id", ""),
            CRYSTAL_ID,
            "first paint uses the initial primary crystal",
        )
    )
    _register(CRYSTAL_B_ID, "test_blue", 250, CATEGORY, false, "")
    var tree := EntityFactory._entity_cache[TREE_ID] as EntityData
    tree.spawned_entity_id = CRYSTAL_B_ID
    painter._paint_resource_cell(Vector2i(2, 2), "2,2")
    var entry: Dictionary = editor._painted_entities.get("2,2", {})
    (
        TestHelper
        . assert_eq(
            entry.get("data", {}).get("id", ""),
            CRYSTAL_B_ID,
            "paint follows the tree's newly spawned crystal",
        )
    )
    var node := entry.get("node") as Node3D
    var res := node.get_node_or_null("ResourceComponent") as ResourceComponent if node else null
    TestHelper.assert_eq(
        res.resource_type_id if res else "", "test_blue", "paint follows the new resource type"
    )
    var hp := node.get_node_or_null("HealthComponent") as HealthComponent if node else null
    TestHelper.assert_eq(
        hp.current_health if hp else -1, 125, "paint follows the new entity's strength"
    )
    painter.free()
    editor.free()
    _teardown()


func test_place_tree_uses_registered_spawner_id() -> void:
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    _setup()
    var editor := FakeEditor.new()
    var placer := _make_placer(editor)
    placer._place_tree_on_cell(Vector2i(4, 7))
    var entry: Dictionary = editor._painted_entities.get("4,7", {})
    TestHelper.assert_eq(
        entry.get("data", {}).get("id", ""), TREE_ID, "placed tree id comes from registered data"
    )
    var node := entry.get("node") as Node3D
    TestHelper.assert_true(node != null, "placed tree was created")
    if node:
        (
            TestHelper
            . assert_true(
                node.get_node_or_null("ResourceTreeComponent") != null,
                "placed entity is a resource-tree spawner",
            )
        )
    placer.free()
    editor.free()
    _teardown()


func test_place_tree_replaces_existing_entry() -> void:
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    _setup()
    var editor := FakeEditor.new()
    var existing := Node3D.new()
    existing.name = "OldEntity"
    editor.add_child(existing)
    editor._painted_entities["4,7"] = {"node": existing, "data": {"id": "OLD_ENTITY"}}
    var placer := _make_placer(editor)
    placer._place_tree_on_cell(Vector2i(4, 7))
    var entry: Dictionary = editor._painted_entities.get("4,7", {})
    TestHelper.assert_eq(
        entry.get("data", {}).get("id", ""), TREE_ID, "occupied cell gets the resolved tree"
    )
    TestHelper.assert_true(entry.get("node") != existing, "occupied cell node is replaced")
    placer.free()
    editor.free()
    _teardown()


func test_no_candidate_leaves_tools_unchanged() -> void:
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    if (
        not EntityFactory.has_method("get_primary_resource_entity")
        or not EntityFactory.has_method("get_primary_resource_tree_entity")
    ):
        TestHelper.fail("primary resource catalog queries are missing")
        return
    var saved := EntityFactory.get_global_rules()
    var rules := GlobalRules.new()
    rules.primary_resource_category = "missing_category"
    EntityFactory.set_global_rules(rules)
    var editor := FakeEditor.new()
    var painter := _make_painter(editor)
    painter._paint_resource_cell(Vector2i(9, 9), "9,9")
    TestHelper.assert_true(
        not editor._painted_entities.has("9,9"), "paint adds nothing without a candidate"
    )
    var pod := Node3D.new()
    var pod_res := ResourceComponent.new()
    pod_res.name = "ResourceComponent"
    pod_res.resource_type_id = "test_green"
    pod.add_child(pod_res)
    var pod_hp := HealthComponent.new()
    pod_hp.name = "HealthComponent"
    pod_hp.max_health = 100
    pod_hp.current_health = 100
    pod.add_child(pod_hp)
    editor.add_child(pod)
    editor._painted_entities["7,7"] = {"node": pod, "data": {"id": "KEEP_POD", "strength": 100}}
    painter._paint_resource_cell(Vector2i(7, 7), "7,7")
    (
        TestHelper
        . assert_eq(
            editor._painted_entities["7,7"].get("data", {}).get("strength", -1),
            100,
            "repainting an existing pod is a no-op without a candidate",
        )
    )
    var existing := Node3D.new()
    existing.name = "ExistingEntity"
    editor.add_child(existing)
    editor._painted_entities["8,8"] = {"node": existing, "data": {"id": "KEEP_ME"}}
    var placer := _make_placer(editor)
    placer._place_tree_on_cell(Vector2i(8, 8))
    TestHelper.assert_true(
        editor._painted_entities.has("8,8"), "tree placement keeps the existing entry"
    )
    (
        TestHelper
        . assert_eq(
            editor._painted_entities.get("8,8", {}).get("data", {}).get("id", ""),
            "KEEP_ME",
            "tree placement keeps the existing metadata",
        )
    )
    painter.free()
    placer.free()
    editor.free()
    EntityFactory.set_global_rules(saved)


func test_fallback_without_spawner_uses_first_id() -> void:
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    if (
        not EntityFactory.has_method("get_primary_resource_entity")
        or not EntityFactory.has_method("get_primary_resource_tree_entity")
    ):
        TestHelper.fail("primary resource catalog queries are missing")
        return
    _setup()
    var rules := GlobalRules.new()
    rules.primary_resource_category = "fallback_category"
    EntityFactory.set_global_rules(rules)
    _register("TEST_Z_CRYSTAL", "test_z", 100, "fallback_category", false, "")
    _register("TEST_A_CRYSTAL", "test_a", 100, "fallback_category", false, "")
    var tree: EntityData = EntityFactory.get_primary_resource_tree_entity()
    var crystal: EntityData = EntityFactory.get_primary_resource_entity()
    TestHelper.assert_true(tree == null, "no spawner means no primary tree")
    (
        TestHelper
        . assert_eq(
            crystal.id if crystal else "",
            "TEST_A_CRYSTAL",
            "fallback picks the first id-ordered crystal",
        )
    )
    EntityFactory._entity_cache.erase("TEST_Z_CRYSTAL")
    EntityFactory._entity_cache.erase("TEST_A_CRYSTAL")
    _teardown()


func test_candidates_without_id_or_type_are_skipped() -> void:
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    if (
        not EntityFactory.has_method("get_primary_resource_entity")
        or not EntityFactory.has_method("get_primary_resource_tree_entity")
    ):
        TestHelper.fail("primary resource catalog queries are missing")
        return
    _setup()
    EntityFactory._entity_cache.erase(TREE_ID)
    _register("", "test_blank", 100, CATEGORY, false, "")
    _register("TEST_UNTYPED_CRYSTAL", "", 100, CATEGORY, false, "")
    var crystal: EntityData = EntityFactory.get_primary_resource_entity()
    (
        TestHelper
        . assert_eq(
            crystal.id if crystal else "",
            CRYSTAL_ID,
            "candidates with an empty id or type are skipped",
        )
    )
    EntityFactory._entity_cache.erase("")
    EntityFactory._entity_cache.erase("TEST_UNTYPED_CRYSTAL")
    _teardown()


func test_queries_return_null_without_rules() -> void:
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    if (
        not EntityFactory.has_method("get_primary_resource_entity")
        or not EntityFactory.has_method("get_primary_resource_tree_entity")
    ):
        TestHelper.fail("primary resource catalog queries are missing")
        return
    _setup()
    EntityFactory.set_global_rules(null)
    TestHelper.assert_true(
        EntityFactory.get_primary_resource_tree_entity() == null, "no rules means no primary tree"
    )
    (
        TestHelper
        . assert_true(
            EntityFactory.get_primary_resource_entity() == null,
            "no rules means no primary resource entity",
        )
    )
    _teardown()


func test_real_ts_catalog_resolves_canonical_pair() -> void:
    if _ef == null:
        TestHelper.fail("EntityFactory not injected")
        return
    if (
        not EntityFactory.has_method("get_primary_resource_entity")
        or not EntityFactory.has_method("get_primary_resource_tree_entity")
    ):
        TestHelper.fail("primary resource catalog queries are missing")
        return
    var snap := TestHelper.snapshot_game_context(GameContext)
    GameContext.select_game("ts")
    (
        TestHelper
        . assert_true(
            EntityFactory.get_entity_data("TIBERIUM_BLUE_01") != null,
            "TS registers an overlay crystal variant in the primary category",
        )
    )
    var tree: EntityData = EntityFactory.get_primary_resource_tree_entity()
    var crystal: EntityData = EntityFactory.get_primary_resource_entity()
    TestHelper.assert_true(tree != null, "TS registers a primary resource tree")
    TestHelper.assert_eq(tree.id if tree else "", "TIBERIUM_TREE", "TS primary tree")
    TestHelper.assert_true(crystal != null, "TS registers a primary resource entity")
    TestHelper.assert_eq(crystal.id if crystal else "", "TIBERIUM_RIPARIUS", "TS primary crystal")
    TestHelper.restore_game_context(GameContext, snap)
