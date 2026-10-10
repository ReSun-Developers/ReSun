class_name ResourceComponent extends Node

@export var resource_type_id: String = ""
## EntityData.resource_category ("tiberium", "tiberium_tree", …). Consumers use
## it to tell harvestable crystal patches from tiberium trees.
@export var resource_category: String = ""
@export var regrowth_rate: float = -1.0
## How many times this crystal has spread to adjacent cells. Capped by GlobalRules.spread_max.
@export var spread_count: int = 0

var _cube_nodes: Array[Node3D] = []
var _current_visual_stage: int = -1
## Authoritative amount left in this cell, in bales. Lazy-initialized from health.
var _bales: float = -1.0

static var _mat_cache: Dictionary = {}


func configure(data: EntityData) -> void:
    resource_type_id = data.resource_type_id
    resource_category = data.resource_category
    regrowth_rate = data.resource_regrowth_rate


func _ready() -> void:
    var root := get_parent() as Node3D
    var detached: bool = root != null and root.get_meta("detached", false)
    if root and not detached and not root.is_in_group("resources"):
        root.add_to_group("resources")
    # Warhead damage hits the backing HealthComponent directly; mirror it back
    # into the authoritative bale amount so a damaged cell yields less tiberium.
    var health := _get_health()
    if health and not health.damage_taken.is_connected(_on_damage_taken):
        health.damage_taken.connect(_on_damage_taken)
    _ensure_visual_nodes.call_deferred()
    _update_visual.call_deferred()
    # Defer cell registration so the entity's global_position is settled
    # (important for spawned resources where position is set after add_child).
    # Detached entities (editor previews/stamps) never register occupancy.
    if not detached:
        _register_cell.call_deferred()


## Syncs bales from the post-damage health so warhead damage reduces the
## harvestable amount. `collect()`/`add_bales()` write health directly (not via
## take_damage), so they never re-enter here.
func _on_damage_taken(_amount: int, _damage_type: String) -> void:
    var health := _get_health()
    if health == null:
        return
    _bales = _health_to_bales(float(health.current_health))
    _update_visual()


func _exit_tree() -> void:
    var root := get_parent() as Node3D
    if root and SpatialHash.instance:
        var cell := CellUtil.world_to_cell(root.global_position)
        SpatialHash.instance.unregister_resource_cell(cell)


func _register_cell() -> void:
    var root := get_parent() as Node3D
    if root and SpatialHash.instance:
        var cell := CellUtil.world_to_cell(root.global_position)
        SpatialHash.instance.register_resource_cell(cell)


func _ensure_visual_nodes() -> void:
    var parent := get_parent() as Node3D
    if not parent:
        return
    var cell := CellUtil.world_to_cell(parent.global_position)
    var rng := RandomNumberGenerator.new()
    rng.seed = hash(cell)

    var configs: Array[Dictionary] = [
        {"count": 3, "big": false},
        {"count": 2, "big": true},
        {"count": 5, "big": true},
    ]

    for si in configs.size():
        var cfg := configs[si]
        var container := Node3D.new()
        container.name = "Stage%d" % si
        parent.add_child(container)
        container.owner = parent.owner

        for i in cfg.count:
            var mi := MeshInstance3D.new()
            mi.name = "Cube%d" % i
            var box := BoxMesh.new()
            if cfg.big:
                box.size = Vector3.ONE * rng.randf_range(0.35, 0.55)
            else:
                box.size = Vector3.ONE * rng.randf_range(0.15, 0.25)
            mi.mesh = box
            var pos_x := rng.randf_range(-0.8, 0.8)
            var pos_z := rng.randf_range(-0.8, 0.8)
            var world_x := parent.global_position.x + pos_x
            var world_z := parent.global_position.z + pos_z
            var terrain_h := TerrainSystem.get_height_at_world_smooth(Vector3(world_x, 0, world_z))
            var y_offset := terrain_h - parent.global_position.y
            mi.position = Vector3(pos_x, y_offset + box.size.y * 0.5, pos_z)
            if not _mat_cache.has(resource_type_id):
                var mat := StandardMaterial3D.new()
                var rules := _get_global_rules()
                var rt: ResourceType = rules.get_resource_type(resource_type_id) if rules else null
                mat.albedo_color = rt.color if rt else Color.WHITE
                _mat_cache[resource_type_id] = mat
            mi.material_override = _mat_cache[resource_type_id]
            container.add_child(mi)

    for i in 3:
        var node := parent.get_node_or_null("Stage%d" % i) as Node3D
        if node:
            _cube_nodes.append(node)


## Bales a ripe cell of this resource holds (its bale capacity).
func get_bale_capacity() -> float:
    var rules := _get_global_rules()
    if rules:
        var rt: ResourceType = rules.get_resource_type(resource_type_id)
        if rt and rt.bales_per_cell > 0.0:
            return rt.bales_per_cell
    return 1.0


func get_amount() -> float:
    _ensure_bales()
    return _bales


func get_max_amount() -> float:
    return get_bale_capacity()


## Remove up to `bales` from this cell, clamped to what remains.
## Returns the bales actually removed.
func collect(bales: float) -> float:
    var hp := _get_health()
    if not hp or hp.max_health <= 0 or bales <= 0.0:
        return 0.0
    _ensure_bales()
    var take := minf(bales, _bales)
    if take <= 0.0:
        return 0.0
    _bales -= take
    _apply_bales_to_health()
    _update_visual()
    if _bales <= 0.0:
        get_parent().queue_free()
    return take


## Grow this cell by `bales`, capped at its bale capacity.
func add_bales(bales: float) -> void:
    if bales <= 0.0:
        return
    _ensure_bales()
    _bales = minf(_bales + bales, get_bale_capacity())
    _apply_bales_to_health()
    _update_visual()


## Lazily initialize the authoritative bale amount from the backing health.
func _ensure_bales() -> void:
    if _bales >= 0.0:
        return
    var hp := _get_health()
    _bales = _health_to_bales(float(hp.current_health)) if hp else 0.0


func _health_to_bales(health: float) -> float:
    var hp := _get_health()
    if not hp or hp.max_health <= 0:
        return 0.0
    return health / float(hp.max_health) * get_bale_capacity()


func _bales_to_health(bales: float) -> int:
    var hp := _get_health()
    if not hp or hp.max_health <= 0:
        return 0
    return roundi(bales / get_bale_capacity() * float(hp.max_health))


## Mirror the authoritative bale amount onto the backing HealthComponent.
## Depletion uses kill() so the existing health_zero death path still runs.
func _apply_bales_to_health() -> void:
    var hp := _get_health()
    if not hp:
        return
    var target := clampi(_bales_to_health(_bales), 0, hp.max_health)
    if target <= 0:
        hp.kill()
    else:
        hp.current_health = target


func is_depleted() -> bool:
    var hp := _get_health()
    return hp.current_health <= 0 if hp else true


func get_visual_stage() -> int:
    var hp := _get_health()
    if not hp or hp.max_health <= 0:
        return 0
    var ratio := hp.get_health_ratio()
    if ratio <= 0.33:
        return 0
    elif ratio <= 0.66:
        return 1
    else:
        return 2


## The currently-visible stage container, used by fog-ghost freeze to reparent
## the harvest-stage visual. Returns null before the visual is staged.
func get_active_stage_node() -> Node3D:
    if _current_visual_stage < 0 or _current_visual_stage >= _cube_nodes.size():
        return null
    return _cube_nodes[_current_visual_stage]


## Re-applies the current harvest stage after a fog ghost is released. The
## stage may have changed (harvest under fog) while the visual was frozen in
## the depot, so a released ghost must snap to the live health stage.
func refresh_visual() -> void:
    _update_visual()


func _update_visual() -> void:
    var parent := get_parent()
    if not parent:
        return
    if _is_visual_frozen():
        # The harvest stage lives in the fog depot while frozen; leave its
        # visibility untouched so the ghost keeps the last-known visual.
        return
    var stage := get_visual_stage()
    if stage == _current_visual_stage:
        return
    _current_visual_stage = stage
    for i in 3:
        if i < _cube_nodes.size():
            var node := _cube_nodes[i] as Node3D
            if node:
                node.visible = (i == stage)


## True while the harvest stage container has been reparented into the fog
## depot (GhostDepot), i.e. the visual is frozen at its fog-entry state.
func _is_visual_frozen() -> bool:
    var parent := get_parent()
    if not parent:
        return false
    var active := get_active_stage_node()
    return is_instance_valid(active) and active.get_parent() != parent


func update_slope_positions() -> void:
    var parent := get_parent() as Node3D
    if not parent:
        return
    for container in _cube_nodes:
        if not container:
            continue
        for child in container.get_children():
            var mi := child as MeshInstance3D
            if not mi or not mi.mesh:
                continue
            var box := mi.mesh as BoxMesh
            if not box:
                continue
            var pos_x := mi.position.x
            var pos_z := mi.position.z
            var world_x := parent.global_position.x + pos_x
            var world_z := parent.global_position.z + pos_z
            var terrain_h := TerrainSystem.get_height_at_world_smooth(Vector3(world_x, 0, world_z))
            var y_offset := terrain_h - parent.global_position.y
            mi.position.y = y_offset + box.size.y * 0.5


func _get_health() -> HealthComponent:
    return get_parent().get_node_or_null("HealthComponent") as HealthComponent


func _get_global_rules() -> GlobalRules:
    return GlobalRules.get_current()
