class_name DockUnloadComponent extends Node

## Fallback bales per real second when no rules are active.
const DEFAULT_UNLOAD_RATE: float = 2.0

## Bales drained per real second. Negative = use the active rules'
## `refinery_unload_rate`; 0 = unload disabled (host evicts the docker).
@export var unload_rate: float = -1.0
## Resource categories this dock accepts (e.g. ["tiberium"]). Empty = accepts all.
@export var accepted_resource_categories: PackedStringArray = []

var _economy_manager: Node = null
var _credit_accumulator: float = 0.0
var _global_rules: GlobalRules = null


func _ready() -> void:
    _economy_manager = EconomyManager
    _global_rules = EntityFactory.get_global_rules() as GlobalRules
    var dock := get_parent().get_node_or_null("DockHostComponent") as DockHostComponent
    if dock:
        dock.docker_undocked.connect(_on_docker_undocked)
    set_process(false)


func configure(data: EntityData) -> void:
    accepted_resource_categories = data.accepted_resource_categories


## Effective bales/second: the component override when set (>= 0), otherwise the
## active rules' `refinery_unload_rate`, otherwise the generic fallback.
func get_effective_unload_rate() -> float:
    if unload_rate >= 0.0:
        return unload_rate
    if _global_rules:
        return _global_rules.refinery_unload_rate
    return DEFAULT_UNLOAD_RATE


func begin_unload() -> void:
    set_process(true)
    # Reset stale timer so the full unload duration is covered.
    var dock := get_parent().get_node_or_null("DockHostComponent") as DockHostComponent
    if dock:
        dock.reset_stale_timer()


func _on_docker_undocked(_docker: Node) -> void:
    set_process(false)


func _process(delta: float) -> void:
    var dock := get_parent().get_node_or_null("DockHostComponent") as DockHostComponent
    if not dock or not dock.current_docker:
        set_process(false)
        return

    var docker_node := dock.current_docker as Node
    if not is_instance_valid(docker_node):
        dock.leave_dock(docker_node)
        set_process(false)
        return

    # current_docker is the DockClientComponent; cargo lives on its parent entity.
    var entity := docker_node.get_parent() as Node3D
    var transport: TransportComponent = null
    if entity:
        transport = entity.get_node_or_null("TransportComponent") as TransportComponent
    if not transport or transport.get_cargo_total() <= 0.0:
        dock.leave_dock(docker_node)
        return

    # Validate cargo categories — reject if any cargo type is not accepted.
    if not _validate_cargo(transport):
        dock.leave_dock(docker_node)
        return

    var bales_to_unload := get_effective_unload_rate() * delta
    var removed := 0.0

    for type_id in transport.cargo.keys():
        var available: float = transport.cargo[type_id]
        var to_remove := minf(bales_to_unload, available)
        if to_remove > 0.0:
            var rt: ResourceType = null
            if _global_rules:
                rt = _global_rules.get_resource_type(type_id)
            var value := rt.value if rt else 1.0
            _credit_accumulator += to_remove * value
            transport.remove_cargo(type_id, to_remove)
            bales_to_unload -= to_remove
            removed += to_remove
            if bales_to_unload <= 0.0:
                break

    # Only refresh the host's stale clock on real progress: a docker that cannot
    # drain (e.g. unload_rate <= 0) must still be evicted by the host timeout.
    if removed > 0.0:
        dock.reset_stale_timer()

    var credits_to_add := int(_credit_accumulator)
    _credit_accumulator -= float(credits_to_add)
    if credits_to_add > 0 and _economy_manager:
        # Credits belong to the refinery, never to the docker.
        var owner_id := DockHostComponent.resolve_owner_id(get_parent())
        if owner_id >= 0:
            _economy_manager.add(owner_id, credits_to_add, "harvest")

    if transport.get_cargo_total() <= 0.0:
        dock.leave_dock(docker_node)


func _validate_cargo(transport: TransportComponent) -> bool:
    if accepted_resource_categories.is_empty():
        return true
    for type_id in transport.cargo.keys():
        if transport.cargo[type_id] <= 0.0:
            continue
        var category := ""
        if _global_rules:
            category = _global_rules.get_resource_category(type_id)
        if category.is_empty():
            category = type_id
        if category not in accepted_resource_categories:
            return false
    return true
