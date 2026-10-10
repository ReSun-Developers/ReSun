class_name ExitComponent extends Node

## Defines where units spawn and exit from a building.
## Offsets are in local space (world units relative to building origin).
## Uses building.to_global() for world positioning, same as DockHostComponent.

## Local-space offset where unit appears inside building.
@export_group("Exit")
@export var spawn_offset: Vector3 = Vector3.ZERO
## Local-space offset where unit exits to (e.g., south side of building).
@export var exit_offset: Vector3 = Vector3.ZERO
## Rotation in degrees the unit faces after exit.
@export var exit_facing: int = 0
## Seconds to wait after spawn before unit starts moving to exit (door animation time).
@export var exit_delay: float = 0.0

## Emitted after unit is positioned at spawn point.
signal unit_spawned(unit: Node3D)
## Emitted when unit has fully exited (reached exit cell or rally point).
signal exit_completed

var _pending_unit: Node3D = null
var _pending_exit_pos: Vector3 = Vector3.ZERO
var _delay_timer: float = 0.0
var _rally_component: RallyPointComponent = null


func configure(data: EntityData) -> void:
    spawn_offset = data.spawn_offset
    exit_offset = data.exit_offset
    exit_facing = data.exit_facing
    exit_delay = data.exit_delay


func _process(delta: float) -> void:
    if _pending_unit and _delay_timer > 0.0:
        _delay_timer -= delta
        if _delay_timer <= 0.0:
            _start_exit(_pending_unit, _pending_exit_pos)


func on_unit_produced(unit: Node3D) -> void:
    var building := get_parent() as Node3D
    if not building:
        return

    # Position unit at spawn offset (local space → world)
    unit.global_position = building.to_global(spawn_offset)

    # Set facing
    unit.rotation.y = deg_to_rad(exit_facing)

    # Cache rally component for post-exit move
    _rally_component = building.get_node_or_null("RallyPointComponent") as RallyPointComponent

    if exit_delay > 0.0:
        # Defer exit movement until door animation time elapses
        _pending_unit = unit
        _pending_exit_pos = building.to_global(exit_offset)
        _delay_timer = exit_delay
    else:
        # Move immediately through full exit sequence
        _start_exit(unit, building.to_global(exit_offset))

    unit_spawned.emit(unit)


func _start_exit(unit: Node3D = null, exit_pos: Vector3 = Vector3.ZERO) -> void:
    if not unit:
        unit = _pending_unit
        exit_pos = _pending_exit_pos
    _pending_unit = null
    _pending_exit_pos = Vector3.ZERO
    _delay_timer = 0.0
    if is_instance_valid(unit):
        var mc := unit.get_node_or_null("MovementController") as MovementController
        if mc:
            mc._has_sub_slot = false
            CellReservation.instance.release_all(unit)
            if not mc.arrived.is_connected(_on_exit_arrived):
                mc.arrived.connect(_on_exit_arrived.bind(unit))
        _move_to_exit(unit, exit_pos)
    else:
        _rally_component = null
        exit_completed.emit()


func _on_exit_arrived(_position: Vector3, unit: Node3D) -> void:
    # After reaching exit cell, move to rally point if set
    if _rally_component and _rally_component.has_rally_point():
        var mc := unit.get_node_or_null("MovementController") as MovementController
        if mc:
            mc.set_target_position(_rally_component.get_target_position(), true)
        _rally_component = null
        return
    _rally_component = null
    exit_completed.emit()


func _move_to_exit(unit: Node3D, exit_pos: Vector3) -> void:
    var exit_cell := CellUtil.world_to_cell(exit_pos)
    var target_cell := _find_free_near(exit_cell)
    var target_pos := CellUtil.cell_to_world(target_cell)

    # Nudge any idle unit blocking the target cell
    if target_cell != exit_cell:
        _nudge_blocker(target_cell)

    var mc := unit.get_node_or_null("MovementController") as MovementController
    if mc:
        mc.set_target_position(target_pos, true)


func _nudge_blocker(cell: Vector2i) -> void:
    var owner_id := _owner_player_id()
    var entries := SpatialHash.instance.get_entries(cell)
    for entry in entries:
        var mc: MovementController = entry.get("mc", null)
        if mc and mc._state == MovementController.State.IDLE:
            if _entry_is_enemy(entry, owner_id):
                continue
            var free := _find_free_near(cell)
            mc.set_target_position(CellUtil.cell_to_world(free))
            return


## Player that owns this exit's building — the only side allowed to nudge
## blockers off its own exit (opponents' units must never be moved by it, #164).
func _owner_player_id() -> int:
    var building := get_parent() as Node3D
    if building == null:
        return -1
    var stats := building.get_node_or_null("StatsComponent") as StatsComponent
    return stats.player_id if stats else -1


func _entry_is_enemy(entry: Dictionary, owner_id: int) -> bool:
    if owner_id < 0:
        return false
    var node: Node3D = entry.get("node")
    if not is_instance_valid(node):
        return false
    var stats := node.get_node_or_null("StatsComponent") as StatsComponent
    if not stats or stats.player_id < 0:
        return false
    return PlayerManager.is_enemy(owner_id, stats.player_id)


func _find_free_near(cell: Vector2i) -> Vector2i:
    if _is_cell_available(cell):
        return cell
    for radius in range(1, 6):
        for dx in range(-radius, radius + 1):
            for dz in range(-radius, radius + 1):
                if abs(dx) != radius and abs(dz) != radius:
                    continue
                var candidate := cell + Vector2i(dx, dz)
                if _is_cell_available(candidate):
                    return candidate
    return cell


func _is_cell_available(cell: Vector2i) -> bool:
    return SpatialHash.instance.is_cell_free_for_unit_exit(cell)
