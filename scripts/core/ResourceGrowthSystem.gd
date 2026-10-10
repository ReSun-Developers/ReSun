extends Node

const SPREAD_NEIGHBORS: Array[Vector2i] = [
    Vector2i(1, 0),
    Vector2i(-1, 0),
    Vector2i(0, 1),
    Vector2i(0, -1),
    Vector2i(1, 1),
    Vector2i(1, -1),
    Vector2i(-1, 1),
    Vector2i(-1, -1),
]

const REBUILD_INTERVAL: float = 5.0

var _tree_timer: float = 0.0
var _resource_timer: float = 0.0
var _tree_batch_offset: int = 0
var _resource_batch_offset: int = 0
var _rebuild_timer: float = 0.0
var _cached_trees: Array = []
var _cached_resources: Array = []


func _ready() -> void:
    _reset_tree_timer()
    _reset_resource_timer()
    _rebuild_cache()


func _physics_process(delta: float) -> void:
    if Engine.is_editor_hint():
        return
    if get_tree().current_scene and get_tree().current_scene.name == "MapEditor":
        return

    var rules := GlobalRules.get_current()
    if not rules:
        return
    if not rules.resource_grows and not rules.resource_spreads:
        return

    _rebuild_timer -= delta
    if _rebuild_timer <= 0.0:
        _rebuild_timer = REBUILD_INTERVAL
        _rebuild_cache()

    _tree_timer -= delta
    if _tree_timer <= 0.0 and _tree_regrowth_enabled():
        _reset_tree_timer()
        _tick_tree_batch(rules)

    _resource_timer -= delta
    if _resource_timer <= 0.0:
        _reset_resource_timer()
        _tick_resource_batch(rules)


## True when the active game enables the tree-seeded growth model.
func _tree_regrowth_enabled() -> bool:
    return GameContext.has_feature("resource_tree_regrowth")


func _rebuild_cache() -> void:
    _cached_trees = _get_trees()
    _cached_resources = _get_resources()


func _reset_tree_timer() -> void:
    var rules := GlobalRules.get_current()
    var base: float = 180.0
    if rules:
        base = rules.tree_growth_rate * 60.0
    _tree_timer = base


func _reset_resource_timer() -> void:
    var rules := GlobalRules.get_current()
    var base: float = 300.0
    if rules:
        base = rules.growth_rate * 60.0
    _resource_timer = base


func _tick_tree_batch(rules: GlobalRules) -> void:
    if _cached_trees.is_empty():
        return

    var batch_size: int = rules.growth_batch_trees
    var start := _tree_batch_offset
    var end := mini(start + batch_size, _cached_trees.size())

    for i in range(start, end):
        var tree_node = _cached_trees[i]
        if is_instance_valid(tree_node):
            _process_tree(tree_node as Node3D, rules)

    _tree_batch_offset = end % maxi(_cached_trees.size(), 1)


func _tick_resource_batch(rules: GlobalRules) -> void:
    if _cached_resources.is_empty():
        return

    var batch_size: int = rules.growth_batch_crystals
    var start := _resource_batch_offset
    var end := mini(start + batch_size, _cached_resources.size())

    for i in range(start, end):
        var res_node = _cached_resources[i]
        if is_instance_valid(res_node):
            _process_resource(res_node as Node3D, rules)

    _resource_batch_offset = end % maxi(_cached_resources.size(), 1)


func _process_tree(tree_node: Node3D, rules: GlobalRules) -> void:
    var tree_comp := tree_node.get_node_or_null("ResourceTreeComponent") as ResourceTreeComponent
    if not tree_comp:
        return
    if tree_comp.spawned_entity_id.is_empty() or tree_comp.node_count <= 0:
        return

    var tree_cell := CellUtil.world_to_cell(tree_node.global_position)
    var rt := rules.get_resource_type(tree_comp.resource_type_id) if rules else null
    var grow_rate: float = rt.grow_rate if rt else 0.1

    var radius_sq: float = float(tree_comp.radius_cells) * float(tree_comp.radius_cells)
    for res_node in _cached_resources:
        if not is_instance_valid(res_node):
            continue
        var res_comp := res_node.get_node_or_null("ResourceComponent") as ResourceComponent
        if not res_comp:
            continue
        var hp := res_node.get_node_or_null("HealthComponent") as HealthComponent
        if not hp or hp.current_health >= hp.max_health:
            continue
        var res_cell := CellUtil.world_to_cell(res_node.global_position)
        var dx: float = float(res_cell.x - tree_cell.x)
        var dz: float = float(res_cell.y - tree_cell.y)
        if dx * dx + dz * dz > radius_sq:
            continue
        res_comp.add_bales(grow_rate * res_comp.get_bale_capacity())

    _spawn_in_radius(tree_comp, tree_cell, rules.tree_spawn_radius, rules)


func _spawn_in_radius(
    tree_comp: ResourceTreeComponent, center: Vector2i, radius: int, rules: GlobalRules
) -> void:
    var rt := rules.get_resource_type(tree_comp.resource_type_id) if rules else null
    var spawn_bales: float = rt.spread_amount if rt else rules.spread_amount

    for dx in range(-radius, radius + 1):
        for dz in range(-radius, radius + 1):
            if dx * dx + dz * dz > radius * radius:
                continue
            # The center cell holds the tree itself — never plant a resource
            # on its root cell.
            if dx == 0 and dz == 0:
                continue
            var cell := center + Vector2i(dx, dz)
            if not _is_in_bounds(cell):
                continue
            if _is_cell_blocked_for_resource(cell):
                continue
            if SpatialHash.instance and SpatialHash.instance.has_resource_cell(cell):
                continue
            _spawn_at_cell(cell, tree_comp, spawn_bales)


func _process_resource(res_node: Node3D, rules: GlobalRules) -> void:
    var res_comp := res_node.get_node_or_null("ResourceComponent") as ResourceComponent
    if not res_comp:
        return

    var rt := rules.get_resource_type(res_comp.resource_type_id) if rules else null
    var grow_rate: float = rt.grow_rate if rt else 0.05
    var spread_max: int = rt.spread_max if rt else rules.spread_max

    var hp := res_node.get_node_or_null("HealthComponent") as HealthComponent
    if hp and hp.current_health < hp.max_health:
        res_comp.add_bales(grow_rate * res_comp.get_bale_capacity())

    if res_comp.spread_count < spread_max:
        _try_spread_from(res_node, res_comp, rules)


func _try_spread_from(res_node: Node3D, res_comp: ResourceComponent, rules: GlobalRules) -> void:
    var res_cell := CellUtil.world_to_cell(res_node.global_position)
    var neighbor: Vector2i = SPREAD_NEIGHBORS[randi() % SPREAD_NEIGHBORS.size()]
    var target_cell := res_cell + neighbor

    if not _is_in_bounds(target_cell):
        return

    if _is_cell_blocked_for_resource(target_cell):
        return

    var existing := _find_resource_at_cell(target_cell)
    if existing:
        _grow_entry(existing)
        return

    var tree_comp := _find_nearest_tree_comp(res_node.global_position)
    if not tree_comp:
        return

    var rt := rules.get_resource_type(res_comp.resource_type_id) if rules else null
    var spread_bales: float = rt.spread_amount if rt else rules.spread_amount

    _spawn_at_cell(target_cell, tree_comp, spread_bales)
    res_comp.spread_count += 1


func _find_nearest_tree_comp(world_pos: Vector3) -> ResourceTreeComponent:
    var nearest: ResourceTreeComponent = null
    var best_dist_sq: float = INF
    for tree in _cached_trees:
        if not is_instance_valid(tree):
            continue
        var d_sq: float = world_pos.distance_squared_to(tree.global_position)
        if d_sq < best_dist_sq:
            best_dist_sq = d_sq
            nearest = tree.get_node_or_null("ResourceTreeComponent") as ResourceTreeComponent
    return nearest


func _spawn_at_cell(cell: Vector2i, tree_comp: ResourceTreeComponent, bales: float) -> void:
    var base_data: EntityData = EntityFactory.get_entity_data(tree_comp.spawned_entity_id)
    var max_health: int = base_data.strength if base_data else 1
    var rules := GlobalRules.get_current()
    var rt := rules.get_resource_type(tree_comp.resource_type_id) if rules else null
    var bale_capacity: float = rt.bales_per_cell if rt and rt.bales_per_cell > 0.0 else 1.0
    var spawn_bales := randf_range(0.01, bales)
    var health := maxi(1, int(roundf(spawn_bales / bale_capacity * float(max_health))))
    var container: Node = World.spawn_container(World.Bucket.ENTITIES)
    if container == null:
        push_warning("ResourceGrowthSystem: no scene root for resource at %s" % cell)
        return
    var world_pos := CellUtil.cell_to_world(cell)
    (
        EntityFactory
        . spawn(
            tree_comp.spawned_entity_id,
            {
                "world_pos": world_pos,
                "overrides":
                {
                    "strength": max_health,
                    "spawn_health": health,
                    "resource_type_id": tree_comp.resource_type_id,
                    "resource_regrowth_rate": tree_comp.regrowth_rate,
                },
                "parent": container,
            }
        )
    )


func _grow_entry(entry: Dictionary) -> void:
    var res_node: Node3D = entry.get("node")
    if res_node:
        var res_comp := res_node.get_node_or_null("ResourceComponent") as ResourceComponent
        var hp := res_node.get_node_or_null("HealthComponent") as HealthComponent
        if res_comp and hp and hp.current_health < hp.max_health:
            var rules := GlobalRules.get_current()
            var rt := rules.get_resource_type(res_comp.resource_type_id) if rules else null
            var grow_rate: float = rt.grow_rate if rt else 0.1
            res_comp.add_bales(grow_rate * res_comp.get_bale_capacity())


func _find_resource_entry(entries: Array) -> Dictionary:
    for entry in entries:
        var node: Node3D = entry.get("node")
        if is_instance_valid(node) and node.get_node_or_null("ResourceComponent"):
            return entry
    return {}


func _find_resource_at_cell(cell: Vector2i) -> Dictionary:
    for entity in get_tree().get_nodes_in_group("resources"):
        if not is_instance_valid(entity):
            continue
        var ecell := CellUtil.world_to_cell(entity.global_position)
        if ecell == cell:
            return {"node": entity}
    return {}


func _is_in_bounds(cell: Vector2i) -> bool:
    return BoundsSystem.is_in_play_area(cell)


func _is_cell_blocked_for_resource(cell: Vector2i) -> bool:
    if not SpatialHash.instance:
        return false
    var key: int = CellUtil.cell_key(cell)
    if SpatialHash.instance._building_cells.has(key):
        return true
    if SpatialHash.instance._bib_cells.has(key):
        return true
    if SpatialHash.instance.is_cell_blocked(cell):
        return true
    return false


func _get_trees() -> Array:
    return get_tree().get_nodes_in_group("resource_trees")


func _get_resources() -> Array:
    return get_tree().get_nodes_in_group("resources")
