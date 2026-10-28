class_name DockHostComponent extends Node

## Local offset from the building's top-left cell to the dock cell.
@export_group("Dock Host")
@export var dock_position: Vector3 = Vector3.ZERO
## Rotation in degrees the docker entity snaps to when docking (e.g. -90 for west-facing).
@export var dock_rotation: float = 0.0
## Accepted dock type IDs (e.g. ["harvest"]). Empty = accepts all types.
@export var dock_types: PackedStringArray = []
## Seconds to wait before promoting the next queued docker after the first.
## Delta-accumulated, so it stays frame-rate independent and scales with game speed.
@export var dock_wait_seconds: float = 0.2
## Seconds a docked client has to finish the dock sequence before eviction.
## The client resets this on arrival and again when unloading begins, so this
## mainly bounds the approach — raise it above the worst-case travel time.
@export var stale_timeout: float = 5.0

var queue: Array[Node] = []
var current_docker: Node = null
var _entity_data: EntityData = null
var _dock_cell: Vector2i = Vector2i.ZERO
## Seconds accumulated toward the next promotion. Resets to 0 after promoting.
var _wait_seconds: float = 0.0
## Seconds since the current docker was docked. Resets on each new docker.
var _stale_timer: float = 0.0
## True when the old docker has undocked but the dock cell may still be occupied.
var _awaiting_vacate: bool = false
## The docker that is currently vacating the dock cell. Prevents re-dock via signal chain.
var _vacating_docker: Node = null
## Seconds since vacate began. Safety timeout to avoid permanent deadlock.
var _vacate_timer: float = 0.0
## Seconds to wait for the dock cell to clear before promoting anyway.
const VACATE_TIMEOUT: float = 3.0

## Emitted when a docker is accepted and begins docking.
signal docker_docked(docker: Node)
## Emitted when a docker leaves the dock (finished unloading or cancelled).
signal docker_undocked(docker: Node)
## Emitted when a queue slot becomes available for the next waiting docker.
signal slot_available
## Emitted when a docked client is evicted for taking too long.
signal dock_timeout(docker: Node)


func _ready() -> void:
    if Engine.is_editor_hint():
        return
    _compute_dock_cell()


func _exit_tree() -> void:
    if Engine.is_editor_hint():
        return
    _clear_queue("host freed")


func configure(data: EntityData) -> void:
    _entity_data = data
    dock_position = data.dock_position
    dock_rotation = data.dock_rotation


func _get_foundation() -> Vector2i:
    var fc := get_parent().get_node_or_null("FoundationComponent") as FoundationComponent
    return fc.foundation if fc else Vector2i(1, 1)


func _compute_dock_cell() -> void:
    _dock_cell = CellUtil.world_to_cell(get_dock_world_position())


func get_dock_world_position() -> Vector3:
    var entity: Node3D = get_parent() as Node3D
    if not entity:
        return Vector3.ZERO
    var foundation: Vector2i = _get_foundation()
    var origin_cell: Vector2i = CellUtil.world_to_cell_origin(entity.global_position, foundation)
    var origin_world: Vector3 = CellUtil.cell_to_world(origin_cell)
    return origin_world + entity.global_transform.basis * dock_position


func is_cell_available(cell: Vector2i) -> bool:
    if not SpatialHash.instance:
        return true
    var occ := SpatialHash.instance.get_cell_occupancy(cell)
    return not (occ.building or occ.blocked or occ.reserved)


func find_wait_cell(max_radius: int = 3) -> Vector2i:
    return CellUtil.spiral_first_free(
        _dock_cell,
        max_radius,
        func(cell: Vector2i) -> bool:
            return not is_cell_available(cell) or SpatialHash.instance.is_bib_cell(cell)
    )


func has_dock_type(type: String) -> bool:
    return dock_types.is_empty() or type in dock_types


func get_entity_id() -> String:
    return _entity_data.id if _entity_data else ""


func get_queue_size() -> int:
    return queue.size()


## Effective wait: 0 if slot is free, queue.size()+1 if occupied (always penalize busy docks).
func get_effective_queue_size() -> int:
    if current_docker == null:
        return 0
    return queue.size() + 1


## Owner id for an entity root or one of its components (-1 when unset).
## Components live one level below their entity, so check the node itself,
## then its parent.
static func resolve_owner_id(node: Node) -> int:
    if node == null:
        return -1
    var stats := node.get_node_or_null("StatsComponent") as StatsComponent
    if stats == null and node.get_parent() != null:
        stats = node.get_parent().get_node_or_null("StatsComponent") as StatsComponent
    return stats.player_id if stats and stats.player_id >= 0 else -1


## True when both nodes belong to the same player with a valid (>= 0) owner id.
static func owners_match(a: Node, b: Node) -> bool:
    var owner_id := resolve_owner_id(a)
    return owner_id >= 0 and owner_id == resolve_owner_id(b)


## Accept a docker into the dock. Returns true if docked immediately, false if queued.
func request_dock(docker: Node) -> bool:
    if docker == _vacating_docker:
        return false
    if not owners_match(self, docker):
        return false
    if current_docker == docker:
        return true
    if current_docker == null:
        current_docker = docker
        _stale_timer = 0.0
        docker_docked.emit(docker)
        if SpatialHash.instance:
            SpatialHash.instance.force_reserve(_dock_cell)
        return true
    if docker in queue:
        return false
    queue.append(docker)
    _wait_seconds = 0.0
    return false


func _process(delta: float) -> void:
    # Vacate polling — wait for the old docker to physically leave the dock cell.
    if _awaiting_vacate:
        _vacate_timer += delta
        if _is_dock_cell_clear() or _vacate_timer >= VACATE_TIMEOUT:
            _finish_vacate()
        return

    # Stale client detection — evict if current docker doesn't complete in time.
    if current_docker and stale_timeout > 0.0:
        _stale_timer += delta
        if _stale_timer >= stale_timeout:
            var stale_docker := current_docker
            dock_timeout.emit(stale_docker)
            leave_dock(stale_docker)
            return

    if queue.is_empty():
        return
    if current_docker != null:
        return
    _wait_seconds += delta
    if _wait_seconds >= dock_wait_seconds:
        _wait_seconds = 0.0
        # Find first valid client, discard dead entries.
        var docker: Node = null
        while not queue.is_empty():
            var candidate := queue.pop_front() as Node
            if is_instance_valid(candidate):
                docker = candidate
                break
        if docker:
            current_docker = docker
            _stale_timer = 0.0
            if SpatialHash.instance:
                SpatialHash.instance.force_reserve(_dock_cell)
            docker_docked.emit(docker)
            slot_available.emit()
            if docker.has_method("on_slot_available"):
                docker.on_slot_available()


## Remove a docker from the dock. If queued, removes from queue. If current, frees the slot.
func leave_dock(docker: Node) -> void:
    if current_docker == docker:
        current_docker = null
        _stale_timer = 0.0
        if not queue.is_empty():
            _awaiting_vacate = true
            _vacating_docker = docker
            _vacate_timer = 0.0
        docker_undocked.emit(docker)
        if not _awaiting_vacate and SpatialHash.instance:
            SpatialHash.instance.release_cell(_dock_cell)
    else:
        var idx := queue.find(docker)
        if idx >= 0:
            queue.remove_at(idx)


## Purge the queue and notify each client.
func _clear_queue(_reason: String = "") -> void:
    while not queue.is_empty():
        var docker := queue.pop_front() as Node
        # on_dock_cancelled() cleans state without emitting signals — safe during teardown.
        if is_instance_valid(docker) and docker.has_method("on_dock_cancelled"):
            docker.on_dock_cancelled()
    _wait_seconds = 0.0


## Reset the stale timer — called when unloading begins so the timeout
## covers the full unload duration, not just the approach.
func reset_stale_timer() -> void:
    _stale_timer = 0.0


## Returns true if no entity from the "entities" group occupies the dock cell.
func _is_dock_cell_clear() -> bool:
    if not SpatialHash.instance:
        return true
    var entries: Array = SpatialHash.instance.get_entries(_dock_cell)
    return entries.is_empty()


## Release the dock cell reservation and promote the next queued docker.
## Skips dead clients in queue. Caller (_process) already verified the
## dock cell is clear or vacate timeout has elapsed.
func _finish_vacate() -> void:
    _awaiting_vacate = false
    _vacating_docker = null
    _vacate_timer = 0.0
    if SpatialHash.instance:
        SpatialHash.instance.release_cell(_dock_cell)

    # Find the first valid client in queue, discarding dead entries.
    var next_docker: Node = null
    while not queue.is_empty():
        var candidate := queue.pop_front() as Node
        if is_instance_valid(candidate):
            next_docker = candidate
            break

    if next_docker:
        current_docker = next_docker
        _stale_timer = 0.0
        if SpatialHash.instance:
            SpatialHash.instance.force_reserve(_dock_cell)
        docker_docked.emit(current_docker)
        slot_available.emit()
        if current_docker.has_method("on_slot_available"):
            current_docker.on_slot_available()
