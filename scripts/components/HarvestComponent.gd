class_name HarvestComponent extends Node

# IDLE = fully idle, waiting for player orders (no auto-search).
# HIBERNATE = field exhausted, empty: periodically re-search for nearby resources.
enum State { IDLE, SEEK_NODE, HARVESTING, DELIVERING, HIBERNATE }

## Resource categories this harvester collects (e.g. ["tiberium"] for all tiberium types).
## Empty = every category. Configured from EntityData.harvestable_categories.
@export_group("Harvest")
@export var harvestable_types: PackedStringArray = []

var _state: int = State.IDLE
var _current_resource: Node3D = null
var _entity_factory: Node = null
var _seek_timeout: float = 0.0
var dock_client: DockClientComponent = null
## True while a resource target came from an explicit player command
## (`set_target_node`), not from auto-seek. Player-commanded targets are honored
## even when the resource cell is already reserved; auto-seek abandons instead.
var _player_commanded: bool = false

var _harvest_accumulator: float = 0.0
var _last_field_position: Vector3 = Vector3.ZERO
var _deliver_retry: float = 0.0
var _hibernate_timer: float = 0.0

const SEEK_TIMEOUT: float = 5.0
const DELIVER_RETRY: float = 2.0
## Seconds between re-searches while hibernating. Damps idle pathfind spam.
const HIBERNATE_INTERVAL: float = 3.0

## Emitted when cargo amount or capacity changes (for UI updates).
signal cargoing_changed(cargo: float, capacity: int)
## Emitted on every state transition (for UI and debugging).
signal state_changed(new_state: int)


func _ready() -> void:
    var mc := get_parent().get_node_or_null("MovementController") as MovementController
    if mc:
        mc.arrived.connect(on_arrived)
    _entity_factory = EntityFactory
    dock_client = get_parent().get_node_or_null("DockClientComponent") as DockClientComponent
    if dock_client:
        dock_client.dock_slot_failed.connect(_on_dock_slot_failed)
        dock_client.dock_cancelled.connect(_on_dock_cancelled)
        dock_client.dock_undocked.connect(on_dock_undocked)


func _exit_tree() -> void:
    _release_resource_cell()


func get_dock_id() -> String:
    if dock_client:
        return dock_client.get_dock_id()
    return ""


## Applies per-entity harvest configuration from data. Empty categories = all.
func configure(data: EntityData) -> void:
    harvestable_types = data.harvestable_categories


func get_cargo() -> float:
    var transport := get_parent().get_node_or_null("TransportComponent") as TransportComponent
    return transport.get_cargo_total() if transport else 0.0


func set_cargo(type_id: String, bales: float) -> void:
    var transport := get_parent().get_node_or_null("TransportComponent") as TransportComponent
    if transport:
        transport.cargo[type_id] = maxf(0.0, bales)
        cargoing_changed.emit(transport.get_cargo_total(), _get_storage_capacity())


func _process(delta: float) -> void:
    var entity_parent := get_parent() as Node3D
    if not entity_parent:
        return

    match _state:
        State.IDLE:
            pass

        State.SEEK_NODE:
            _seek_timeout -= delta
            if _seek_timeout <= 0.0:
                _release_resource_cell()
                _current_resource = null
                _assess_next_action()

        State.HARVESTING:
            if not is_instance_valid(_current_resource):
                _release_resource_cell()
                _current_resource = null
                _assess_next_action()
                return
            var tib := _current_resource.get_node_or_null("ResourceComponent") as ResourceComponent
            if not tib:
                _release_resource_cell()
                _current_resource = null
                _assess_next_action()
                return
            var rules := _get_global_rules()
            var fill_rate := rules.harvester_fill_rate if rules else 1.0
            _harvest_accumulator += fill_rate * delta
            if _harvest_accumulator > 0.001:
                var bales_to_collect := _harvest_accumulator
                _harvest_accumulator = 0.0
                var collected := tib.collect(bales_to_collect)
                if collected > 0.0:
                    var transport := (
                        get_parent().get_node_or_null("TransportComponent") as TransportComponent
                    )
                    if transport:
                        transport.add_cargo(tib.resource_type_id, collected)
                        cargoing_changed.emit(transport.get_cargo_total(), _get_storage_capacity())
            if get_cargo() >= float(_get_storage_capacity()):
                _release_resource_cell()
                _current_resource = null
                _deliver_cargo(entity_parent)
            elif tib.is_depleted():
                _release_resource_cell()
                _current_resource = null
                _assess_next_action()

        State.DELIVERING:
            # No dock reachable — retry on a cooldown instead of re-seeking
            # synchronously (which recurses via dock_slot_failed). Retries
            # indefinitely; self-heals when a refinery becomes reachable.
            # A seek that cannot engage (busy client / retry cooldown) re-arms
            # the cooldown so the loop persists instead of stranding the
            # harvester after one attempt.
            # ponytail: no "stuck" signal — add one if the AI/UI needs to react.
            if _deliver_retry > 0.0:
                _deliver_retry -= delta
                if _deliver_retry <= 0.0:
                    _seek_dock_or_arm_retry(entity_parent)

        State.HIBERNATE:
            # Field exhausted — wait, then re-scan for nearby resources.
            # ponytail: searches in place; add drift-toward-refinery if needed.
            _hibernate_timer -= delta
            if _hibernate_timer <= 0.0:
                _hibernate_timer = HIBERNATE_INTERVAL
                _assess_next_action()


func _deliver_cargo(entity_parent: Node3D) -> void:
    _deliver_retry = 0.0
    _change_state(State.DELIVERING)
    _seek_dock_or_arm_retry(entity_parent)


## Ask the dock client to seek; if it cannot engage (busy client, retry
## cooldown, or no compatible host), arm the DELIVERING retry so the loop
## re-attempts instead of stranding the harvester.
func _seek_dock_or_arm_retry(entity_parent: Node3D, specific_host: Node3D = null) -> void:
    if dock_client and not dock_client.seek_dock(entity_parent, specific_host):
        _deliver_retry = DELIVER_RETRY


func set_target_node(node: Node3D) -> void:
    if node and node.get_node_or_null("ResourceComponent"):
        _player_commanded = true
        _release_resource_cell()
        _current_resource = node
        if dock_client:
            dock_client.cancel()
        _reenter_seek_node()


func cancel_harvest(_from_player: bool = false) -> void:
    _release_resource_cell()
    _current_resource = null
    _deliver_retry = 0.0
    if dock_client:
        dock_client.cancel()
    _change_state(State.IDLE)


func set_target_refinery(node: Node3D) -> void:
    if node and node.get_node_or_null("DockHostComponent") and dock_client:
        # Enter DELIVERING so the undock/failed/cancelled handlers resume the
        # loop afterwards — without this a player-ordered dock leaves the
        # harvester stuck idle after unloading.
        _release_resource_cell()
        _current_resource = null
        _change_state(State.DELIVERING)
        _seek_dock_or_arm_retry(get_parent() as Node3D, node)


func on_arrived(_position: Vector3) -> void:
    if _state == State.SEEK_NODE:
        _seek_timeout = 0.0
        _change_state(State.HARVESTING)


## Called when the dock host releases this entity (cargo fully unloaded).
func on_dock_undocked(_docker: Node = null) -> void:
    if _state == State.DELIVERING:
        _assess_next_action()


func _on_dock_slot_failed() -> void:
    if _state == State.DELIVERING:
        _deliver_retry = DELIVER_RETRY


func _on_dock_cancelled() -> void:
    if _state == State.DELIVERING:
        _assess_next_action()


## Scan for resources; deliver if loaded, else hibernate (auto-retry).
## IDLE is reserved for explicit player stop (cancel_harvest).
func _assess_next_action() -> void:
    _player_commanded = false
    var entity_parent := get_parent() as Node3D
    if not entity_parent:
        _change_state(State.IDLE)
        return
    if get_cargo() >= float(_get_storage_capacity()):
        _deliver_cargo(entity_parent)
        return
    var resource := _find_nearest_resource(entity_parent.global_position)
    if not resource and _last_field_position != Vector3.ZERO:
        resource = _find_nearest_resource(_last_field_position)
    if resource:
        _current_resource = resource
        _reenter_seek_node()
    elif get_cargo() > 0.0:
        _deliver_cargo(entity_parent)
    else:
        _change_state(State.HIBERNATE)


## Force a SEEK_NODE transition from any state. `_change_state` no-ops on a
## SEEK_NODE→SEEK_NODE transition (same-state guard), so reset to IDLE first to
## re-run the SEEK entry logic and re-issue the move.
func _reenter_seek_node() -> void:
    _state = State.IDLE
    _change_state(State.SEEK_NODE)


func _change_state(new_state: int) -> void:
    if _state == new_state:
        return
    if _state == State.SEEK_NODE and new_state != State.SEEK_NODE:
        if new_state != State.HARVESTING:
            _release_resource_cell()
    if _state == State.HARVESTING and new_state != State.HARVESTING:
        _harvest_accumulator = 0.0
    _state = new_state
    state_changed.emit(_state)

    var entity_parent := get_parent() as Node3D
    if not entity_parent:
        return
    var mc := entity_parent.get_node_or_null("MovementController") as MovementController

    match _state:
        State.SEEK_NODE:
            if is_instance_valid(_current_resource):
                var tib_cell := CellUtil.world_to_cell(_current_resource.global_position)
                var my_cell := CellUtil.world_to_cell(entity_parent.global_position)
                if SpatialHash.instance and not _player_commanded:
                    if not SpatialHash.instance.reserve_cell(tib_cell):
                        _current_resource = null
                        call_deferred("_assess_next_action")
                        return
                if tib_cell == my_cell:
                    _change_state(State.HARVESTING)
                    return
                _seek_timeout = SEEK_TIMEOUT
                mc.set_target_position(_current_resource.global_position)
        State.DELIVERING:
            _last_field_position = entity_parent.global_position
        State.HIBERNATE:
            # Wait one interval before the first re-scan (damps pathfind spam).
            _hibernate_timer = HIBERNATE_INTERVAL
            _unblock_dock_if_needed(entity_parent)


## If we're hibernating on a refinery's dock cell (just finished unloading and
## found nothing to harvest), step off to a free wait cell so we don't block the
## entrance for other harvesters.
func _unblock_dock_if_needed(entity_parent: Node3D) -> void:
    if not dock_client:
        return
    var mc := entity_parent.get_node_or_null("MovementController") as MovementController
    if not mc:
        return
    var host := dock_client.find_nearest_host(entity_parent)
    if not host:
        return
    var dock := host.get_node_or_null("DockHostComponent") as DockHostComponent
    if not dock:
        return
    var my_cell := CellUtil.world_to_cell(entity_parent.global_position)
    if dock._dock_cell != my_cell:
        return
    var free_cell := dock.find_wait_cell()
    if free_cell != my_cell:
        mc.set_target_position(CellUtil.cell_to_world(free_cell))


func _find_nearest_resource(search_from: Vector3) -> Node3D:
    var nearest: Node3D = null
    var nearest_dist := INF
    var rules := _get_global_rules()

    for entity in get_tree().get_nodes_in_group("resources"):
        var tib := entity.get_node_or_null("ResourceComponent") as ResourceComponent
        if not tib or tib.is_depleted():
            continue
        if rules:
            var category := rules.get_resource_category(tib.resource_type_id)
            if not harvestable_types.is_empty() and category not in harvestable_types:
                continue
        if SpatialHash.instance:
            var ecell := CellUtil.world_to_cell(entity.global_position)
            if SpatialHash.instance.is_cell_blocked(ecell):
                continue
            var key: int = CellUtil.cell_key(ecell)
            if SpatialHash.instance._reserved.has(key):
                continue
        var dist := search_from.distance_squared_to(entity.global_position)
        if dist < nearest_dist:
            nearest_dist = dist
            nearest = entity

    return nearest


func _get_storage_capacity() -> int:
    var transport := get_parent().get_node_or_null("TransportComponent") as TransportComponent
    return transport.storage if transport else 0


func _release_resource_cell() -> void:
    if (
        is_instance_valid(_current_resource)
        and _current_resource.is_inside_tree()
        and SpatialHash.instance
    ):
        var cell := CellUtil.world_to_cell(_current_resource.global_position)
        SpatialHash.instance.release_cell(cell)


func _get_global_rules() -> GlobalRules:
    if _entity_factory and _entity_factory.has_method("get_global_rules"):
        return _entity_factory.get_global_rules() as GlobalRules
    return null


func get_order_for_target(
    target: Node3D,
    _target_cell: Vector2i,
    target_pos: Vector3,
    modifiers: Dictionary,
) -> OrderResult:
    if not target:
        return null
    var queued: bool = modifiers.get(OrderResult.MOD_QUEUED, false)
    if target.get_node_or_null("ResourceComponent"):
        return OrderResult.new(
            CursorState.Type.HARVEST,
            20,
            target,
            target_pos,
            queued,
            func(): set_target_node(target),
        )
    if target.get_node_or_null("DockHostComponent"):
        # Only enter same-owner docks; foreign docks fall through to other generators.
        if DockHostComponent.owners_match(get_parent(), target):
            return OrderResult.new(
                CursorState.Type.ENTER,
                15,
                target,
                target_pos,
                queued,
                func(): set_target_refinery(target),
            )
    return null
