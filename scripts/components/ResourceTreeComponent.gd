class_name ResourceTreeComponent extends Node

@export_group("Resource Tree")
@export var spawned_entity_id: String = ""
@export var radius_cells: int = 8
@export var resource_type_id: String = ""
@export var node_count: int = 12
@export var spawn_strength: float = 0.5
@export var max_spawn_strength: float = 1.0
@export var regrowth_rate: float = -1.0


func _ready() -> void:
    var root := get_parent() as Node3D
    if root and not root.get_meta("detached", false) and not root.is_in_group("resource_trees"):
        root.add_to_group("resource_trees")


func configure(data: EntityData) -> void:
    spawned_entity_id = data.spawned_entity_id
    radius_cells = data.radius_cells
    resource_type_id = data.resource_type_id
    node_count = data.node_count
    spawn_strength = data.spawn_strength
    max_spawn_strength = data.max_spawn_strength
    regrowth_rate = data.resource_regrowth_rate


func _random_cell_in_radius(center: Vector2i, radius: int) -> Vector2i:
    var angle := randf() * TAU
    var dist := sqrt(randf()) * float(radius)
    return Vector2i(center.x + roundi(cos(angle) * dist), center.y + roundi(sin(angle) * dist))
