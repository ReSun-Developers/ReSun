class_name TransportComponent extends Node

signal cargo_changed(current: float, capacity: int, type_id: String)
signal passenger_changed(current: int, max_passengers: int)

## Number of infantry passengers this unit can carry.
@export_group("Transport")
@export var passengers: int = 0
## Dock type ID this unit docks with (e.g. "GDI_REFINERY").
@export var dock: String = ""
## Whether this unit is a harvester (auto-docks when full).
@export var harvester: bool = false
## Maximum resource bales this unit can carry.
@export var storage: int = 0
## Animation scale key for pip overlays on the sidebar.
@export var pip_scale: String = ""

## Water land-type id — transports cannot unload onto it (amphibious gate).
const WATER_LAND_TYPE := "water"

## Cargo hold — dictionary mapping resource_type_id to bale amount (e.g. {"tiberium_green": 14.5}).
var cargo: Dictionary = {}
## Detached infantry passenger nodes held while aboard (health/veterancy/weapons preserved).
var passenger_nodes: Array[Node3D] = []
## Seat pip color per held passenger, parallel to passenger_nodes.
var passenger_colors: Array[Color] = []
## Current number of infantry passengers aboard.
var current_passengers: int = 0

var _unloading: bool = false
var _unload_timer: float = 0.0


func _ready() -> void:
    if Engine.is_editor_hint():
        return
    var entity := get_parent() as Node3D
    if not entity:
        return
    var health := entity.get_node_or_null("HealthComponent") as HealthComponent
    if health:
        health.health_zero.connect(_on_transport_destroyed)


func _exit_tree() -> void:
    _unloading = false
    # Backstop for scripted frees: nothing may hold detached passengers. The
    # tree is mid-teardown here, so the re-add is deferred one frame.
    for passenger in passenger_nodes:
        if not is_instance_valid(passenger):
            continue
        if passenger.is_inside_tree():
            continue
        var container := get_parent()
        if container:
            passenger.position = _fallback_position()
            container.add_child.call_deferred(passenger)
        else:
            passenger.free()
    passenger_nodes.clear()
    passenger_colors.clear()
    current_passengers = 0


func _physics_process(delta: float) -> void:
    if Engine.is_editor_hint():
        return
    if not _unloading:
        return
    # Any movement cancels the unload — move orders, shoves, everything.
    if _is_transport_moving():
        _unloading = false
        return
    _unload_timer += delta
    if _unload_timer >= _get_unload_interval():
        _unload_timer = 0.0
        _eject_next()


func configure(data: EntityData) -> void:
    passengers = data.passengers
    dock = data.dock
    harvester = data.harvester
    storage = data.storage
    pip_scale = data.pip_scale


func validate(data: EntityData) -> PackedStringArray:
    var errors: PackedStringArray = []
    if data.harvester and data.dock.is_empty():
        errors.append("TransportComponent: '%s' is a harvester but has no dock" % data.id)
    return errors


func can_carry() -> bool:
    return passengers > 0


func is_harvester() -> bool:
    return harvester


func get_cargo_total() -> float:
    var total := 0.0
    for amount in cargo.values():
        total += amount
    return total


func get_cargo_value(global_rules: GlobalRules) -> int:
    var total := 0.0
    for type_id in cargo:
        var rt: ResourceType = global_rules.get_resource_type(type_id)
        if rt:
            total += cargo[type_id] * rt.value
    return int(total)


## Add resource bales to cargo. Returns actual bales added (limited by remaining capacity).
func add_cargo(type_id: String, amount: float) -> float:
    var space := float(storage) - get_cargo_total()
    var actual := minf(amount, space)
    if actual > 0.0:
        cargo[type_id] = cargo.get(type_id, 0.0) + actual
        cargo_changed.emit(get_cargo_total(), storage, type_id)
    return actual


## Remove resource bales from cargo. Returns actual bales removed.
func remove_cargo(type_id: String, amount: float) -> float:
    var available: float = cargo.get(type_id, 0.0)
    var actual := minf(amount, available)
    if actual > 0.0:
        cargo[type_id] = available - actual
        if cargo[type_id] <= 0.0:
            cargo.erase(type_id)
        cargo_changed.emit(get_cargo_total(), storage, type_id)
    return actual


## Add a passenger. Returns false if at capacity.
func add_passenger() -> bool:
    if current_passengers >= passengers:
        return false
    current_passengers += 1
    passenger_changed.emit(current_passengers, passengers)
    return true


## Remove a passenger. Returns false if empty.
func remove_passenger() -> bool:
    if current_passengers <= 0:
        return false
    current_passengers -= 1
    passenger_changed.emit(current_passengers, passengers)
    return true


# --- Passenger loading / unloading ---


## A stationary transport with a free seat can take another passenger.
func can_accept_passenger() -> bool:
    if current_passengers >= passengers:
        return false
    return not _is_transport_moving()


## Detach the infantry node into this transport. Returns false when full/moved.
func board(passenger: Node3D) -> bool:
    if not is_instance_valid(passenger) or not can_accept_passenger():
        return false
    var select := passenger.get_node_or_null("SelectComponent") as SelectComponent
    if select and select.is_selected:
        SelectionManager.deselect_entity(select)
    var color := Color.WHITE
    var pcomp := passenger.get_node_or_null("PassengerComponent") as PassengerComponent
    if pcomp:
        color = pcomp.pip_color
    var parent := passenger.get_parent()
    if parent:
        parent.remove_child(passenger)
    passenger_nodes.append(passenger)
    passenger_colors.append(color)
    return add_passenger()


## Unload eligibility: passengers aboard, transport stationary, standing on land.
func can_unload() -> bool:
    if current_passengers <= 0:
        return false
    if _is_transport_moving():
        return false
    return not _is_on_water()


## Begin sequential eject — one passenger per GlobalRules.unload_interval.
func execute_unload() -> void:
    if not can_unload():
        return
    _unloading = true
    _unload_timer = 0.0
    _eject_next()


## Cancel a pending unload; remaining passengers stay aboard.
func cancel_unload() -> void:
    _unloading = false


## Eject everything immediately (death path). No gating — used on health_zero.
func eject_all() -> void:
    _unloading = false
    while not passenger_nodes.is_empty():
        _eject_passenger(passenger_nodes[0])


func _on_transport_destroyed() -> void:
    eject_all()


func _eject_next() -> void:
    if passenger_nodes.is_empty():
        _unloading = false
        return
    _eject_passenger(passenger_nodes[0])


func _eject_passenger(passenger: Node3D) -> void:
    var idx := passenger_nodes.find(passenger)
    if idx < 0:
        return
    passenger_nodes.remove_at(idx)
    passenger_colors.remove_at(idx)
    remove_passenger()
    _readd_passenger_at_free_cell(passenger)
    if passenger_nodes.is_empty():
        _unloading = false


## Re-add a detached passenger at the nearest free land cell around the
## transport, mirroring EntityPlacer.place_entity's infantry sub-slot flow.
func _readd_passenger_at_free_cell(passenger: Node3D) -> void:
    if not is_instance_valid(passenger):
        return
    var entity := get_parent() as Node3D
    var container := entity.get_parent() if entity else null
    if not container:
        push_error("TransportComponent: no container to re-add passenger")
        passenger.queue_free()
        return
    var center := CellUtil.world_to_cell(entity.global_position)
    var target_cell := _find_free_land_cell_near(center)
    container.add_child(passenger)
    passenger.global_position = CellUtil.cell_to_world(target_cell)
    var mc := passenger.get_node_or_null("MovementController") as MovementController
    if mc:
        mc._assign_sub_slot_at_cell(target_cell)
        if mc._has_sub_slot:
            passenger.global_position = mc._sub_slot_position


## Ring search (r=1..3) for an in-bounds land cell without an entity on it;
## falls back to the center cell itself (transport's own cell).
func _find_free_land_cell_near(center: Vector2i) -> Vector2i:
    for radius in range(1, 4):
        for dx in range(-radius, radius + 1):
            for dz in range(-radius, radius + 1):
                if absi(dx) != radius and absi(dz) != radius:
                    continue
                var cell := center + Vector2i(dx, dz)
                if _is_free_land_cell(cell):
                    return cell
    return center


func _is_free_land_cell(cell: Vector2i) -> bool:
    var land_type := TerrainSystem.get_land_type(cell)
    if land_type == "" or land_type == WATER_LAND_TYPE:
        return false
    if SpatialHash.instance and SpatialHash.instance.is_any_entity_on_cell(cell):
        return false
    return true


func _is_transport_moving() -> bool:
    var entity := get_parent() as Node3D
    if not entity:
        return false
    var mc := entity.get_node_or_null("MovementController") as MovementController
    return mc != null and mc.is_moving()


func _is_on_water() -> bool:
    var entity := get_parent() as Node3D
    if not entity or not entity.is_inside_tree():
        return false
    var cell := CellUtil.world_to_cell(entity.global_position)
    return TerrainSystem.get_land_type(cell) == WATER_LAND_TYPE


func _get_unload_interval() -> float:
    var rules := GlobalRules.get_current()
    return rules.unload_interval if rules else 0.25


func _fallback_position() -> Vector3:
    var entity := get_parent() as Node3D
    return entity.global_position if entity else Vector3.ZERO


# --- Order targeting ---


func get_order_for_target(
    target: Node3D,
    _target_cell: Vector2i,
    target_pos: Vector3,
    modifiers: Dictionary,
) -> OrderResult:
    var entity := get_parent() as Node3D
    if not target or target != entity or not can_unload() or not _is_sole_selected():
        return null
    var queued: bool = modifiers.get(OrderResult.MOD_QUEUED, false)
    return OrderResult.new(
        CursorState.Type.DEPLOY,
        15,
        entity,
        target_pos,
        queued,
        func() -> void: execute_unload(),
    )


## Mouse-driven unload fires only when the transport is the only selected
## entity — a mixed-selection click must mean load (ENTER) or converge (the
## generator's implode move). Keyboard deploy bypasses order resolution.
func _is_sole_selected() -> bool:
    var entity := get_parent() as Node3D
    if not entity:
        return false
    var select := entity.get_node_or_null("SelectComponent") as SelectComponent
    if not select or not select.is_selected:
        return false
    return SelectionManager.selected_entities.size() == 1
