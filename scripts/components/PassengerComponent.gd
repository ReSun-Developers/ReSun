class_name PassengerComponent extends Node

## Infantry-side boarding orders. Offers an ENTER cursor/order when the clicked
## target is a friendly, stationary transport with free seats. The order walks
## the infantry to the transport as a plain move; on arrival the infantry
## boards if the transport is still valid, adjacent, stationary, and has room.

## Range (world units) within which an arrived infantry still boards — the
## transport may have drifted a little or sit on an adjacent water cell.
const BOARD_RANGE := CellUtil.CELL_SIZE * 1.5

## Seat pip color for the selection overlay, captured from EntityData.pip_color.
var pip_color: Color = Color.WHITE

var _pending_transport: Node3D = null


func configure(data: EntityData) -> void:
    pip_color = data.pip_color


func _exit_tree() -> void:
    _clear_pending()


func get_order_for_target(
    target: Node3D,
    _target_cell: Vector2i,
    target_pos: Vector3,
    modifiers: Dictionary,
) -> OrderResult:
    if not _can_board_target(target):
        return null
    var queued: bool = modifiers.get(OrderResult.MOD_QUEUED, false)
    return OrderResult.new(
        CursorState.Type.ENTER,
        10,
        target,
        target_pos,
        queued,
        func() -> void: _approach(target),
    )


## Boarding eligibility: friendly transport, stationary, with a free seat.
func _can_board_target(target: Node3D) -> bool:
    if not target or target == get_parent():
        return false
    if target.is_in_group("enemy"):
        return false
    var transport := target.get_node_or_null("TransportComponent") as TransportComponent
    if not transport or not transport.can_accept_passenger():
        return false
    return DockHostComponent.owners_match(get_parent(), target)


## Walk to the transport and board: targets the transport's own cell with a
## straight final leg (set_exact_target), so the infantry walks flush to the
## APC. Boarding happens only on arrival at the APC's center — never instantly
## at order time, even from an adjacent cell.
func _approach(transport: Node3D) -> void:
    var entity := get_parent() as Node3D
    if not entity or not is_instance_valid(transport):
        return
    var movement := entity.get_node_or_null("MovementController") as MovementController
    if not movement:
        return
    _pending_transport = transport
    if not movement.arrived.is_connected(_on_arrived):
        movement.arrived.connect(_on_arrived)
    if not movement.movement_started.is_connected(_on_movement_started):
        movement.movement_started.connect(_on_movement_started)
    movement.set_exact_target(transport.global_position)


func _on_arrived(_position: Vector3) -> void:
    var transport := _pending_transport
    _clear_pending()
    if not is_instance_valid(transport):
        return
    var entity := get_parent() as Node3D
    if not entity or not entity.is_inside_tree():
        return
    if entity.global_position.distance_to(transport.global_position) > BOARD_RANGE:
        return
    var t := transport.get_node_or_null("TransportComponent") as TransportComponent
    if not t or not DockHostComponent.owners_match(entity, transport):
        return
    if t.board(entity):
        return
    # Boarding failed (full or started moving again): sidestep off the APC's
    # cell with a normal move — its relocation logic finds the nearest free one.
    var movement := entity.get_node_or_null("MovementController") as MovementController
    if movement:
        movement.set_target_position(transport.global_position)


## A new (non-exact) move supersedes the pending board: without this, a
## redirected infantry that later stops near the transport would board on
## that arrival's range check. The boarding move itself is exact, so it keeps
## its pending; stop() arms nothing new, and the next player move cleans up.
func _on_movement_started() -> void:
    var entity := get_parent() as Node3D
    if not entity:
        return
    var movement := entity.get_node_or_null("MovementController") as MovementController
    if movement and not movement._exact_target:
        _clear_pending()


func _clear_pending() -> void:
    _pending_transport = null
    var entity := get_parent() as Node
    if entity:
        var movement := entity.get_node_or_null("MovementController") as MovementController
        if movement:
            if movement.arrived.is_connected(_on_arrived):
                movement.arrived.disconnect(_on_arrived)
            if movement.movement_started.is_connected(_on_movement_started):
                movement.movement_started.disconnect(_on_movement_started)
