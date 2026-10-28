class_name DockClientComponent extends Node

enum State { IDLE, MOVING, ROTATING, UNLOADING, QUEUED }

## Entity IDs this unit is allowed to dock with (e.g. ["GDI_REFINERY"]). Empty = any.
@export_group("Dock Client")
@export var can_dock_with: PackedStringArray = []
## Extra distance penalty squared added per queued docker when ranking dock hosts.
@export var occupancy_penalty: float = 10.0
## Search radius in cells when finding the nearest compatible dock host.
@export var search_radius_cells: int = 20

var _state: int = State.IDLE
var _reserved_host: Node3D = null
var _queued_host: Node3D = null
var _target_host: Node3D = null
var _dock_id: String = ""
var _mc: MovementController = null
var _retry_cooldown: float = 0.0

const DOCK_CELL_RETRY_COOLDOWN: float = 1.0

## Emitted when no compatible dock host is reachable or all are full.
signal dock_slot_failed
## Emitted when docking is cancelled (timeout, pathfinding failure, or player cancel).
signal dock_cancelled
## Emitted when the dock host undocks this client (cargo fully unloaded).
signal dock_undocked(docker: Node)


func _ready() -> void:
    _mc = get_parent().get_node_or_null("MovementController") as MovementController
    if _mc:
        _mc.arrived.connect(_on_arrived)
        _mc.pathfinding_failed.connect(_on_pathfinding_failed)


func _exit_tree() -> void:
    if _state != State.IDLE:
        release_reservation()
        _state = State.IDLE


func configure(data: EntityData) -> void:
    _dock_id = data.dock
    can_dock_with = [data.dock] if not data.dock.is_empty() else []


func get_dock_id() -> String:
    return _dock_id


func is_reserved() -> bool:
    return is_instance_valid(_reserved_host)


func get_state() -> int:
    return _state


func _process(delta: float) -> void:
    if _retry_cooldown > 0.0:
        _retry_cooldown -= delta
        if _retry_cooldown <= 0.0:
            if _state == State.MOVING and is_instance_valid(_target_host):
                _move_to_dock(_target_host)
            elif _state == State.QUEUED and is_instance_valid(_queued_host):
                if _try_bind_host(_queued_host):
                    _queued_host = null
                    _target_host = _reserved_host
                    _state = State.MOVING
                    _move_to_dock(_target_host)

    match _state:
        State.ROTATING:
            _process_rotation(delta)
        State.UNLOADING:
            pass


func _process_rotation(delta: float) -> void:
    if not is_instance_valid(_target_host):
        _cancel_dock()
        return
    var dock := _target_host.get_node_or_null("DockHostComponent") as DockHostComponent
    if not dock:
        _cancel_dock()
        return
    var entity := get_parent() as Node3D
    if not entity:
        return
    var target_yaw := deg_to_rad(dock.dock_rotation)
    var step := deg_to_rad(_mc.rotation_speed) * delta if _mc else deg_to_rad(180.0) * delta
    var diff := angle_difference(entity.rotation.y, target_yaw)
    if abs(diff) < 0.05:
        entity.rotation.y = target_yaw
        _begin_unload()
    else:
        entity.rotation.y += sign(diff) * minf(step, abs(diff))


func _begin_unload() -> void:
    if not is_instance_valid(_target_host):
        _cancel_dock()
        return
    _state = State.UNLOADING
    var dock_unload := _target_host.get_node_or_null("DockUnloadComponent") as DockUnloadComponent
    if dock_unload:
        dock_unload.begin_unload()


## Attempt to begin docking. Returns true when the client engaged (entered
## MOVING or QUEUED), false when it could not (client busy, retry cooldown, or
## no compatible host found). Callers use the result to schedule a retry rather
## than assuming the seek succeeded.
func seek_dock(parent: Node3D, specific_host: Node3D = null) -> bool:
    if _state != State.IDLE or _retry_cooldown > 0.0:
        return false

    _disconnect_host_signal()

    if specific_host:
        if _try_bind_host(specific_host):
            _target_host = specific_host
            _state = State.MOVING
            _move_to_dock(specific_host)
            return true
        _queued_host = specific_host
        _state = State.QUEUED
        var host_dock := specific_host.get_node_or_null("DockHostComponent") as DockHostComponent
        if host_dock:
            _move_to_cell(host_dock.find_wait_cell())
        return true

    var host := find_nearest_host(parent)
    if not host:
        dock_slot_failed.emit()
        return false
    if _try_bind_host(host):
        _target_host = host
        _state = State.MOVING
        _move_to_dock(host)
        return true

    # Host occupied — queue at the nearest.
    _queued_host = host
    _state = State.QUEUED
    var dock := host.get_node_or_null("DockHostComponent") as DockHostComponent
    if dock:
        _move_to_cell(dock.find_wait_cell())
    return true


func _move_to_dock(host: Node3D) -> void:
    var dock := host.get_node_or_null("DockHostComponent") as DockHostComponent
    if not dock or not _mc:
        dock_slot_failed.emit()
        return
    var target_pos: Vector3 = dock.get_dock_world_position()
    _mc.move_to(target_pos)


func _move_to_cell(cell: Vector2i) -> void:
    if not _mc:
        return
    _mc.move_to(CellUtil.cell_to_world(cell))


func _on_arrived(_position: Vector3) -> void:
    match _state:
        State.MOVING:
            if not _target_host:
                return
            # Verify we're at the correct dock cell.
            var dock := _target_host.get_node_or_null("DockHostComponent") as DockHostComponent
            if dock and _mc:
                var my_cell := CellUtil.world_to_cell(get_parent().global_position)
                if my_cell != dock._dock_cell:
                    _mc.move_to(CellUtil.cell_to_world(dock._dock_cell))
                    return
            # Arrived — restart the host's stale clock so the (variable-length)
            # approach doesn't eat the rotate+unload budget.
            if dock:
                dock.reset_stale_timer()
            _state = State.ROTATING
        State.QUEUED:
            # Scattered — navigate back to wait cell.
            if is_instance_valid(_queued_host):
                var dock := _queued_host.get_node_or_null("DockHostComponent") as DockHostComponent
                if dock:
                    var wait_cell := dock.find_wait_cell()
                    var my_cell := CellUtil.world_to_cell(get_parent().global_position)
                    if my_cell != wait_cell:
                        _mc.move_to(CellUtil.cell_to_world(wait_cell))


func _on_pathfinding_failed() -> void:
    if _state == State.MOVING:
        # Dock cell temporarily occupied — retry after cooldown.
        _retry_cooldown = DOCK_CELL_RETRY_COOLDOWN
    elif _state == State.QUEUED:
        # Stay queued — wait cell is just a convenience. Host will promote us.
        pass


func _cancel_dock() -> void:
    var was_reserved := is_reserved()
    release_reservation()
    _target_host = null
    _state = State.IDLE
    if was_reserved:
        dock_cancelled.emit()


func _disconnect_host_signal() -> void:
    if not is_instance_valid(_reserved_host):
        return
    var dock := _reserved_host.get_node_or_null("DockHostComponent") as DockHostComponent
    if dock and dock.docker_undocked.is_connected(on_dock_undocked):
        dock.docker_undocked.disconnect(on_dock_undocked)


func _try_bind_host(host: Node3D) -> bool:
    if not host:
        return false
    var dock := host.get_node_or_null("DockHostComponent") as DockHostComponent
    if not dock:
        return false
    if dock.request_dock(self):
        _bind_host(host)
        return true
    return false


func _bind_host(host: Node3D) -> void:
    _reserved_host = host
    var dock := host.get_node_or_null("DockHostComponent") as DockHostComponent
    if dock and not dock.docker_undocked.is_connected(on_dock_undocked):
        dock.docker_undocked.connect(on_dock_undocked)


func release_reservation() -> void:
    if not is_instance_valid(_reserved_host):
        return
    var dock := _reserved_host.get_node_or_null("DockHostComponent") as DockHostComponent
    if dock:
        if dock.docker_undocked.is_connected(on_dock_undocked):
            dock.docker_undocked.disconnect(on_dock_undocked)
        dock.leave_dock(self)
    _reserved_host = null
    _queued_host = null


## Fully abort docking from any sub-state: leave the reserved slot or the
## queue, then reset to IDLE. Use for player move commands mid-dock —
## release_reservation() alone leaves _state/_target_host dangling.
func cancel() -> void:
    if is_instance_valid(_reserved_host):
        release_reservation()
    elif is_instance_valid(_queued_host):
        var dock := _queued_host.get_node_or_null("DockHostComponent") as DockHostComponent
        if dock:
            dock.leave_dock(self)
    _reset()


func find_nearest_host(parent: Node3D, exclude: Node3D = null) -> Node3D:
    var parent_cell := CellUtil.world_to_cell(parent.global_position)
    var nearest: Node3D = null
    var nearest_dist := float(search_radius_cells * search_radius_cells)

    # Scan the whole scene via the entities group (map-loaded, player-built, and
    # MCV-deployed buildings all register here) instead of a single Buildings
    # node, which map-loaded buildings never join.
    for child in get_tree().get_nodes_in_group("entities"):
        if child == exclude:
            continue
        var dock := child.get_node_or_null("DockHostComponent") as DockHostComponent
        if not dock:
            continue
        if not can_dock_with.is_empty() and dock.get_entity_id() not in can_dock_with:
            continue
        if not DockHostComponent.owners_match(parent, child):
            continue
        var dock_cell := CellUtil.world_to_cell(CellUtil.cell_to_world(dock._dock_cell))
        var raw_dist := Vector2(parent_cell - dock_cell).length_squared()
        var queue_size: int = dock.get_effective_queue_size()
        var penalty := queue_size * occupancy_penalty * occupancy_penalty
        var dist := raw_dist + penalty
        if dist < nearest_dist:
            nearest_dist = dist
            nearest = child

    return nearest


func on_slot_available() -> void:
    if _state != State.QUEUED:
        return
    if is_instance_valid(_reserved_host):
        # Already reserved — move to dock.
        _target_host = _reserved_host
        _state = State.MOVING
        _move_to_dock(_reserved_host)
        return
    if is_instance_valid(_queued_host):
        var host := _queued_host
        if _try_bind_host(host):
            _queued_host = null
            _target_host = host
            _state = State.MOVING
            _move_to_dock(host)
        else:
            _retry_cooldown = 0.5


func _reset() -> void:
    _target_host = null
    _reserved_host = null
    _queued_host = null
    _retry_cooldown = 0.0
    _state = State.IDLE


func on_dock_undocked(docker: Node) -> void:
    if docker != self:
        return
    _reset()
    dock_undocked.emit(docker)


## Called by host when queue is purged (e.g. host building destroyed).
## Does NOT emit signals — safe to call during teardown.
func on_dock_cancelled() -> void:
    _reset()
