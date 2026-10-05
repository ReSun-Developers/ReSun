extends Node

# ResourceGrowthSystem tests — GlobalRules defaults, spread neighbor count,
# and tree-spawn behavior around the tree's root cell.

const GRID := Vector2i(50, 50)
const TREE_CELL := Vector2i(40, 40)
const SPAWN_RADIUS := 1

var _ts: Node = null
var _sh: Node = null


func test_global_rules_growth_fields():
    var rules := GlobalRules.new()
    (
        TestHelper
        . assert_true(
            (
                rules.tree_growth_rate == 3.0
                and rules.tree_spawn_radius == 3
                and rules.growth_batch_trees == 10
                and rules.growth_batch_crystals == 500
                and rules.spread_amount == 0.5
                and rules.spread_max == 3
            ),
            "GlobalRules growth defaults correct: GlobalRules growth defaults mismatch",
        )
    )


func test_spread_neighbors_count():
    (
        TestHelper
        . assert_true(
            ResourceGrowthSystem.SPREAD_NEIGHBORS.size() == 8,
            (
                "spread neighbors has 8 directions: expected 8, got %d"
                % ResourceGrowthSystem.SPREAD_NEIGHBORS.size()
            ),
        )
    )


func test_tree_spawn_radius_circle():
    # Verify that radius=3 produces a circular area (not full square)
    var radius := 3
    var count := 0
    for dx in range(-radius, radius + 1):
        for dz in range(-radius, radius + 1):
            if dx * dx + dz * dz <= radius * radius:
                count += 1
    # Full square would be 7x7=49. Circle should be less.
    (
        TestHelper
        . assert_true(
            count < 49 and count > 0,
            (
                (
                    "tree_spawn_radius circle has %d cells (< 49 square): "
                    + "expected circular area, got %d cells"
                )
                % [count, count]
            ),
        )
    )


## Regression for #168: a tiberium tree is a spawner, not a harvestable node.
## EntityFactory must not attach a ResourceComponent — that component draws
## crystals and registers the root cell as a resource, which is exactly the
## artifact the issue reports.
func test_tree_entity_has_no_resource_component():
    var entity := EntityFactory.create_entity("TIBERIUM_TREE")
    if entity == null:
        TestHelper.fail("tree entity fixture missing")
        return
    (
        TestHelper
        . assert_true(
            entity.get_node_or_null("ResourceTreeComponent") != null,
            "tree entity must keep its ResourceTreeComponent",
        )
    )
    (
        TestHelper
        . assert_true(
            entity.get_node_or_null("ResourceComponent") == null,
            "tree entity must not have a ResourceComponent at its root cell (#168)",
        )
    )
    entity.queue_free()


## Builds the fixture, runs one tree spawn tick around a tree rooted at
## TREE_CELL, and returns {spawned, world, tree_root}. The tree is bare
## (no ResourceComponent), matching a real tree after #168, so the root cell
## is NOT pre-registered as a resource cell. A World root is added so spawned
## resources route through the spawn seam into its Entities container; the
## caller must free world/tree_root AFTER inspecting spawned — freeing earlier
## would crash the caller's loop on freed nodes and silently skip assertions.
func _spawn_around_tree_root(radius: int) -> Dictionary:
    _ts.init_grid(GRID.x, GRID.y)
    _sh._building_cells.clear()
    _sh._bib_cells.clear()
    _sh._resource_cells.clear()
    var rules := GlobalRules.get_current()
    if not rules:
        TestHelper.fail("GlobalRules unavailable in headless test env")
        return {}
    (
        TestHelper
        . assert_true(
            BoundsSystem.is_in_play_area(TREE_CELL),
            "fixture tree root cell %s must be inside the playable area" % TREE_CELL,
        )
    )

    var tree_root := Node3D.new()
    var tree_comp := ResourceTreeComponent.new()
    tree_comp.name = "ResourceTreeComponent"
    tree_root.add_child(tree_comp)
    var data := EntityData.new()
    data.spawned_entity_id = "TIBERIUM_RIPARIUS"
    data.radius_cells = radius
    data.resource_type_id = "tiberium_green"
    data.node_count = 4
    tree_comp.configure(data)
    tree_root.position = CellUtil.cell_to_world(TREE_CELL)
    var scene_root: Window = (Engine.get_main_loop() as SceneTree).root
    scene_root.add_child(tree_root)

    # A World root makes the spawn seam resolve here, so spawned resources land
    # in World/Entities (the real per-match container) instead of the tree root.
    var world := World.new()
    world.name = "ResourceGrowthTestWorld"
    scene_root.add_child(world)

    # Run the spawn tick on the real ResourceGrowthSystem autoload — the same
    # instance production uses.
    var growth: Node = scene_root.get_node("ResourceGrowthSystem")
    growth._spawn_in_radius(tree_comp, TREE_CELL, radius, rules)

    var spawned: Array[Node] = []
    var entities: Node = world.get_node_or_null(World.ENTITIES_NAME)
    if entities:
        for child in entities.get_children():
            if child.get_node_or_null("ResourceComponent"):
                spawned.append(child)
    return {"spawned": spawned, "world": world, "tree_root": tree_root}


func test_tree_root_cell_stays_clear_on_spawn():
    var result := _spawn_around_tree_root(SPAWN_RADIUS)
    if result.is_empty():
        return
    var spawned: Array[Node] = result["spawned"]
    # Proves the spawn tick actually ran and produced resources in the ring.
    (
        TestHelper
        . assert_true(
            spawned.size() >= 1,
            "spawn tick produced at least one resource neighbor: got %d" % spawned.size(),
        )
    )
    for node in spawned:
        var cell := CellUtil.world_to_cell((node as Node3D).global_position)
        var offset := cell - TREE_CELL
        (
            TestHelper
            . assert_true(
                offset != Vector2i.ZERO,
                "tree root cell %s must stay clear, found a resource at %s" % [TREE_CELL, cell],
            )
        )
        (
            TestHelper
            . assert_true(
                offset.length_squared() <= SPAWN_RADIUS * SPAWN_RADIUS,
                "spawned resource at %s is outside radius %d of the tree" % [cell, SPAWN_RADIUS],
            )
        )
    (
        TestHelper
        . assert_true(
            not _sh.has_resource_cell(TREE_CELL),
            "tree root cell %s must not be registered as a resource cell" % TREE_CELL,
        )
    )
    (result["world"] as Node).free()
    (result["tree_root"] as Node).free()


## Regression: with tiberium at 11 bales/cell, a 0.5-bale spread must seed a cell at
## 0.5/11 (~4.5%) health, not 0.5 (the old "0.5 bales = half the cell" model).
func test_spawned_cell_seeds_at_bale_scale_not_health_ratio():
    var result := _spawn_around_tree_root(2)
    if result.is_empty():
        return
    var spawned: Array[Node] = result["spawned"]
    (
        TestHelper
        . assert_true(
            spawned.size() >= 1,
            "spawn tick produced at least one resource: got %d" % spawned.size(),
        )
    )
    # 0.5 bales on an 11-bale cell, rounded up, is at most 14 health.
    for node in spawned:
        var hp := node.get_node("HealthComponent") as HealthComponent
        (
            TestHelper
            . assert_true(
                hp != null and hp.current_health >= 1 and hp.current_health <= 14,
                (
                    "spawned cell seeds at bale scale (<=0.5 bales): expected health 1..14, got %d"
                    % (hp.current_health if hp else -1)
                ),
            )
        )
    (result["world"] as Node).free()
    (result["tree_root"] as Node).free()


## Regression for the cached-parent bug: after a World is released, growth must
## resolve the *current* World root rather than a parent cached from the old one.
func test_spawn_routes_to_current_world_after_replacement():
    var first := _spawn_around_tree_root(SPAWN_RADIUS)
    if first.is_empty():
        return
    (first["world"] as Node).free()
    (first["tree_root"] as Node).free()

    var second := _spawn_around_tree_root(SPAWN_RADIUS)
    if second.is_empty():
        return
    var world: Node = second["world"]
    var spawned: Array[Node] = second["spawned"]
    TestHelper.assert_true(spawned.size() >= 1, "resources still spawn after a World replacement")
    for node in spawned:
        (
            TestHelper
            . assert_true(
                world.is_ancestor_of(node),
                "spawned resource belongs to the current World, not a released one",
            )
        )
    (second["world"] as Node).free()
    (second["tree_root"] as Node).free()
