class_name FactoryComponent extends Node

## Building-level production interface. Declares what queue types this
## building produces and manages primary building selection.

## Emitted when this factory joins/leaves the "factories" group or when its
## primary state changes, so consumers can invalidate cached factory counts.
signal factories_changed

## Queue types this building handles (e.g., ["infantry"], ["vehicle"]).
@export var produces: Array[String] = []

## Whether this factory is the primary exit for its queue type.
@export var is_primary: bool = false

## Player ID that owns this factory.
var player_id: int = -1

## Whether a unit is currently exiting (door animation + movement).
var is_busy: bool = false

## Emitted when a unit is exiting (factory is busy).
signal exit_in_progress

## Known production queue types the `factory` field may reference.
const KNOWN_FACTORY_TYPES: PackedStringArray = [
    "BuildingType",
    "InfantryType",
    "VehicleType",
    "AircraftType",
]


func _ready() -> void:
    # Detached entities (editor/preview) are not live factories.
    var parent := get_parent()
    if parent and parent.get_meta("detached", false):
        return
    # EntityPlacer/BuildingManager assign StatsComponent.player_id before the
    # entity enters the tree. Sync before announcing the factory so listeners
    # never observe a newly added factory with the sentinel owner -1.
    _sync_player_id()
    add_to_group("factories")
    factories_changed.emit()


func _exit_tree() -> void:
    remove_from_group("factories")
    factories_changed.emit()


func configure(data: EntityData) -> void:
    if not data.factory.is_empty():
        produces = [data.factory]


func validate(data: EntityData) -> PackedStringArray:
    var errors: PackedStringArray = []
    if not data.factory.is_empty() and not KNOWN_FACTORY_TYPES.has(data.factory):
        errors.append(
            "FactoryComponent: '%s' has unknown factory type '%s'" % [data.id, data.factory]
        )
    return errors


func _sync_player_id() -> void:
    var stats := get_parent().get_node_or_null("StatsComponent") as StatsComponent
    if stats:
        player_id = stats.player_id


func set_primary() -> void:
    is_primary = true
    var factories := get_tree().get_nodes_in_group("factories")
    for f in factories:
        if f == self:
            continue
        if not f is FactoryComponent:
            continue
        var other := f as FactoryComponent
        if other.player_id != player_id:
            continue
        if other.produces != produces:
            continue
        other.is_primary = false
    factories_changed.emit()


func on_unit_produced(entity_data: EntityData, owner_player_id: int) -> void:
    var building := get_parent() as Node3D
    if not building:
        return

    # Spawn at building center — ExitComponent will reposition if present
    var unit := EntityPlacer.place_entity(entity_data, building.global_position, owner_player_id)
    if not unit:
        return

    # Let ExitComponent handle positioning, exit movement, and rally point
    var exit := building.get_node_or_null("ExitComponent")
    if exit:
        # Only block factory during exit delay (war factory door animation)
        if exit.exit_delay > 0.0:
            is_busy = true
        if not exit.exit_completed.is_connected(_on_exit_completed):
            exit.exit_completed.connect(_on_exit_completed)
        exit.on_unit_produced(unit)
    else:
        # No ExitComponent — find nearest free cell (exclude bib cells)
        var building_cell := CellUtil.world_to_cell(building.global_position)
        var free_cell := _find_free_near(building_cell)
        var free_pos := CellUtil.cell_to_world(free_cell)
        unit.global_position = free_pos
        push_warning(
            (
                "[FactoryComponent] No ExitComponent on %s — spawned at nearest free cell"
                % building.name
            )
        )

    exit_in_progress.emit()


func _on_exit_completed() -> void:
    is_busy = false


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
    if SpatialHash.instance.is_cell_blocked(cell):
        return false
    if SpatialHash.instance.is_cell_full_for_shared(cell):
        return false
    var key := CellUtil.cell_key(cell)
    if SpatialHash.instance.get_building_cells().has(key):
        return false
    if SpatialHash.instance.is_bib_cell(cell):
        return false
    return true
