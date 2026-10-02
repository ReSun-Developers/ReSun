class_name DeployComponent extends Node

## Bidirectional deploy/undeploy component.
## Configures vehicle→building (deploy) and building→vehicle (undeploy) transformations.
## Uses snapshot+deferred pattern: capture state → deselect → defer create+free.

enum DeployState { IDLE, ROTATING_DEPLOY, ROTATING_UNDEPLOY, TRANSFORMING }

## Entity id to create when deploying (e.g., "GDI_CONSTRUCTION_YARD" for MCV).
@export_group("Deploy")
@export var deploys_into: String = ""
## Entity id to create when undeploying (e.g., "GDI_MCV" for ConYard).
@export var undeploys_into: String = ""
## Rotation in degrees the source entity rotates to before deploying (0 = default/north).
@export var deploy_rotation: float = 0.0
## Rotation in degrees the source entity rotates to before undeploying (0 = default/north).
@export var undeploy_rotation: float = 0.0
## Local cell offset where the entity appears after deploy/undeploy.
## Default (0,0) = origin cell (top-left for buildings).
@export var deploy_cell: Vector2i = Vector2i(0, 0)
## Transfer health as ratio between source and target max_health.
@export var transfer_health_ratio: bool = true

var _state: int = DeployState.IDLE
var _target_entity: Node3D = null
var _target_rot_y: float = 0.0
var _rotation_speed: float = 180.0
var _pending_move_target: Vector3 = Vector3.ZERO
var _has_pending_move: bool = false


func _exit_tree() -> void:
    _state = DeployState.IDLE
    _target_entity = null


func _process(delta: float) -> void:
    if _state == DeployState.IDLE or _state == DeployState.TRANSFORMING:
        return
    if not is_instance_valid(_target_entity):
        _state = DeployState.IDLE
        _target_entity = null
        return
    var step := deg_to_rad(_rotation_speed) * delta
    var diff := angle_difference(_target_entity.rotation.y, _target_rot_y)
    if abs(diff) < 0.05:
        _target_entity.rotation.y = _target_rot_y
        var was_deploy := _state == DeployState.ROTATING_DEPLOY
        var entity := _target_entity
        _state = DeployState.TRANSFORMING
        _target_entity = null
        if was_deploy:
            _complete_deploy(entity)
        else:
            _complete_undeploy(entity)
    else:
        _target_entity.rotation.y += sign(diff) * minf(step, abs(diff))


func configure(data: EntityData) -> void:
    deploys_into = data.deploys_into
    undeploys_into = data.undeploys_into
    deploy_rotation = data.deploy_rotation
    undeploy_rotation = data.undeploy_rotation


func can_deploy() -> bool:
    return not deploys_into.is_empty()


func can_undeploy() -> bool:
    return not undeploys_into.is_empty()


func is_transitioning() -> bool:
    return _state != DeployState.IDLE


func get_order_for_target(
    target: Node3D,
    _target_cell: Vector2i,
    target_pos: Vector3,
    modifiers: Dictionary,
) -> OrderResult:
    var queued: bool = modifiers.get(OrderResult.MOD_QUEUED, false)
    var entity := get_parent() as Node3D
    if target and target == entity and can_deploy():
        return OrderResult.new(
            CursorState.Type.DEPLOY,
            15,
            entity,
            target_pos,
            queued,
            func(): execute_deploy(entity),
        )
    if not target and can_undeploy():
        return OrderResult.new(
            CursorState.Type.MOVE,
            5,
            null,
            target_pos,
            queued,
            func(): _undeploy_with_offset(entity, target_pos),
        )
    return null


func _undeploy_with_offset(entity: Node3D, click_pos: Vector3) -> void:
    var sm := Engine.get_main_loop().root.get_node_or_null("SelectionManager") as SelectionManager
    var center := entity.global_position
    if sm and sm.selected_entities.size() > 1:
        var sum := Vector3.ZERO
        var count := 0
        for sc in sm.selected_entities:
            if is_instance_valid(sc):
                var p := sc.get_parent() as Node3D
                if is_instance_valid(p):
                    sum += p.global_position
                    count += 1
        if count > 0:
            center = sum / count
    var offset := entity.global_position - center
    var cell_offset := Vector2i(
        roundi(offset.x / CellUtil.CELL_SIZE),
        roundi(offset.z / CellUtil.CELL_SIZE),
    )
    cell_offset.x = clampi(cell_offset.x, -2, 2)
    cell_offset.y = clampi(cell_offset.y, -2, 2)
    var undeploy_target := (
        click_pos
        + Vector3(
            cell_offset.x * CellUtil.CELL_SIZE,
            0,
            cell_offset.y * CellUtil.CELL_SIZE,
        )
    )
    execute_undeploy(entity, undeploy_target)


## Validate that deploy is possible. Returns true if foundation cells are free.
func validate_deploy(source_entity: Node3D) -> bool:
    if not can_deploy():
        return false
    var source_data := EntityFactory.get_entity_data(deploys_into)
    if not source_data:
        push_warning("[Deploy] Unknown deploy target: %s" % deploys_into)
        return false
    var origin := calculate_deploy_origin(source_entity, source_data)
    return _are_foundation_cells_free(origin, source_data.foundation, source_entity)


## Calculate the origin cell for the deployed building, centering it on the source entity.
func calculate_deploy_origin(source_entity: Node3D, target_data: EntityData) -> Vector2i:
    var source_cell := CellUtil.world_to_cell(source_entity.global_position)
    var foundation := target_data.foundation
    var half_x: int = int(foundation.x * 0.5)
    var half_y: int = int(foundation.y * 0.5)
    return source_cell - Vector2i(half_x, half_y)


## Check if all foundation cells are free (no buildings, blocked cells, or entities).
func _are_foundation_cells_free(
    origin: Vector2i,
    foundation: Vector2i,
    source_entity: Node3D = null,
) -> bool:
    for dx in foundation.x:
        for dz in foundation.y:
            var cell := origin + Vector2i(dx, dz)
            if not _is_cell_free_for_deploy(cell, source_entity):
                return false
    return true


## Check if a single cell is free for deploy (reuses BuildingManager logic pattern).
## source_entity is excluded from the entity check — the deploying unit occupies its own cell.
func _is_cell_free_for_deploy(cell: Vector2i, source_entity: Node3D = null) -> bool:
    var key := CellUtil.cell_key(cell)
    if SpatialHash.instance.get_building_cells().has(key):
        return false
    # Check blocked cells — exclude source entity if it's the only blocker
    if SpatialHash.instance.is_cell_blocked(cell):
        if not _is_only_source_blocking(cell, source_entity):
            return false
    # Check entity presence — exclude source entity
    if SpatialHash.instance.is_any_entity_on_cell(cell):
        if not _is_only_source_on_cell(cell, source_entity):
            return false
    if SpatialHash.instance.is_bib_cell(cell) or SpatialHash.instance.has_resource_cell(cell):
        return false
    var cell_type := TerrainSystem.get_cell_type(cell)
    return cell_type == "" or cell_type == "clear"


## Check if the only entity blocking a cell is the source entity.
func _is_only_source_blocking(cell: Vector2i, source_entity: Node3D) -> bool:
    if not source_entity:
        return false
    var entries := SpatialHash.instance.get_entries(cell)
    for entry in entries:
        var node: Node3D = entry.get("node")
        var mc: MovementController = entry.get("mc")
        if is_instance_valid(node) and node != source_entity and mc:
            return false
    return true


## Check if the only entity on a cell is the source entity.
func _is_only_source_on_cell(cell: Vector2i, source_entity: Node3D) -> bool:
    if not source_entity:
        return false
    var entries := SpatialHash.instance.get_entries(cell)
    for entry in entries:
        var node: Node3D = entry.get("node")
        if is_instance_valid(node) and node != source_entity:
            return false
    return true


## Scatter allied units blocking foundation cells. Returns true if all cells cleared.
func scatter_blockers(source_entity: Node3D, target_data: EntityData) -> bool:
    var origin := calculate_deploy_origin(source_entity, target_data)
    var foundation := target_data.foundation
    var scattered_any := false

    for dx in foundation.x:
        for dz in foundation.y:
            var cell := origin + Vector2i(dx, dz)
            if _can_scatter_cell(cell):
                if _scatter_single_cell(cell, source_entity):
                    scattered_any = true

    return scattered_any


## Check if a cell can be cleared by scattering (no terrain/building/resource blockers).
func _can_scatter_cell(cell: Vector2i) -> bool:
    var key := CellUtil.cell_key(cell)
    if SpatialHash.instance.get_building_cells().has(key):
        return false
    if SpatialHash.instance.is_bib_cell(cell) or SpatialHash.instance.has_resource_cell(cell):
        return false
    var cell_type := TerrainSystem.get_cell_type(cell)
    if cell_type != "" and cell_type != "clear":
        return false
    # Cell blocked by terrain/building/resource — scatter won't help.
    # Only attempt scatter if the only blockers are scatterable entities.
    return true


## Scatter units from a single cell. Returns true if scatter was attempted.
func _scatter_single_cell(cell: Vector2i, source_entity: Node3D) -> bool:
    var entries := SpatialHash.instance.get_entries(cell)
    var local_pid := PlayerManager.get_local_player_id()
    var scattered := false
    for entry in entries:
        var entity_node: Node3D = entry.get("node")
        if not is_instance_valid(entity_node):
            continue
        if entity_node == source_entity:
            continue
        var stats := entity_node.get_node_or_null("StatsComponent") as StatsComponent
        if not stats:
            continue
        # Only scatter own units (infantry/vehicles)
        if stats.player_id != local_pid:
            continue
        if (
            stats.entity_type != EntityData.EntityType.INFANTRY
            and stats.entity_type != EntityData.EntityType.VEHICLE
        ):
            continue
        var mc := entity_node.get_node_or_null("MovementController") as MovementController
        if not mc:
            continue
        if mc._state != MovementController.State.IDLE:
            continue
        var push_cell := _find_adjacent_free_cell(cell)
        if push_cell == Vector2i(-1, -1):
            continue
        mc.set_target_position(CellUtil.cell_to_world(push_cell))
        scattered = true
    return scattered


## Find an adjacent free cell for scattering.
func _find_adjacent_free_cell(origin: Vector2i) -> Vector2i:
    for radius in range(1, 4):
        for dx in range(-radius, radius + 1):
            for dz in range(-radius, radius + 1):
                if abs(dx) != radius and abs(dz) != radius:
                    continue
                var cell := origin + Vector2i(dx, dz)
                if _is_cell_free_for_deploy(cell):
                    return cell
    return Vector2i(-1, -1)


## Execute the deploy transformation. Returns true on success.
func execute_deploy(source_entity: Node3D) -> bool:
    if is_transitioning():
        return false
    if not can_deploy():
        return false
    var target_data := EntityFactory.get_entity_data(deploys_into)
    if not target_data:
        return false
    if not validate_deploy(source_entity):
        scatter_blockers(source_entity, target_data)
        if not validate_deploy(source_entity):
            push_warning("[Deploy] Cannot deploy — foundation cells blocked")
            return false

    _rotation_speed = _get_rotation_speed(source_entity)
    _target_rot_y = deg_to_rad(deploy_rotation)
    _target_entity = source_entity

    if abs(angle_difference(source_entity.rotation.y, _target_rot_y)) < 0.05:
        source_entity.rotation.y = _target_rot_y
        _target_entity = null
        _state = DeployState.TRANSFORMING
        _complete_deploy(source_entity)
    else:
        _state = DeployState.ROTATING_DEPLOY
    return true


func _complete_deploy(source_entity: Node3D) -> void:
    if not is_instance_valid(source_entity):
        _state = DeployState.IDLE
        return
    var target_data := EntityFactory.get_entity_data(deploys_into)
    if not target_data:
        _state = DeployState.IDLE
        return
    var origin := calculate_deploy_origin(source_entity, target_data)
    var snap := _snapshot_entity(source_entity)
    _deselect_entity(source_entity)
    _remove_source_from_systems(source_entity)
    call_deferred("_do_deploy", source_entity, origin, target_data, snap)


## Execute the deferred deploy: create target, apply snapshot, free source.
func _do_deploy(
    source: Node3D, origin: Vector2i, target_data: EntityData, snap: Dictionary
) -> void:
    if not is_instance_valid(source):
        _state = DeployState.IDLE
        return
    var target_entity := EntityFactory.create_entity(deploys_into)
    if not target_entity:
        push_error("[Deploy] Failed to create target entity: %s" % deploys_into)
        source.queue_free()
        _state = DeployState.IDLE
        return
    var world_pos := _cell_origin_to_world(origin, target_data.foundation)
    world_pos.y = _get_max_height(origin, target_data.foundation)
    target_entity.position = world_pos
    # Assign the player before add_child so MovementController._ready() caches the
    # real id (the crush filter's query side). Setting it post-add leaves
    # _player_id = -1 forever, so an undeployed crusher treats every unit as an
    # enemy and crushes friendlies.
    var deploy_stats := target_entity.get_node_or_null("StatsComponent") as StatsComponent
    if deploy_stats:
        deploy_stats.player_id = snap["player_id"]
    var buildings_parent := _get_buildings_parent()
    if buildings_parent:
        buildings_parent.add_child(target_entity)
    else:
        var tree := get_tree()
        if tree and tree.current_scene:
            tree.current_scene.add_child(target_entity)
    var cells: Array[Vector2i] = []
    for dx in target_data.foundation.x:
        for dz in target_data.foundation.y:
            cells.append(origin + Vector2i(dx, dz))
    SpatialHash.instance.register_building_cells(cells)
    (
        BuildingManager
        . _buildings
        . append(
            {
                "node": target_entity,
                "type": target_data,
                "origin": origin,
                "cells": cells,
            }
        )
    )
    PrerequisiteSystem.register_building(snap["player_id"], target_data)
    _apply_snapshot(target_entity, snap)
    source.queue_free()
    _state = DeployState.IDLE


## Execute the undeploy transformation. Returns true on success.
func execute_undeploy(source_entity: Node3D, move_target: Vector3 = Vector3.ZERO) -> bool:
    if is_transitioning():
        return false
    if not can_undeploy():
        return false
    var target_data := EntityFactory.get_entity_data(undeploys_into)
    if not target_data:
        return false

    _rotation_speed = _get_rotation_speed(source_entity)
    _target_rot_y = deg_to_rad(undeploy_rotation)
    _target_entity = source_entity
    if move_target != Vector3.ZERO:
        _pending_move_target = move_target
        _has_pending_move = true

    if abs(angle_difference(source_entity.rotation.y, _target_rot_y)) < 0.05:
        source_entity.rotation.y = _target_rot_y
        _target_entity = null
        _state = DeployState.TRANSFORMING
        _complete_undeploy(source_entity)
    else:
        _state = DeployState.ROTATING_UNDEPLOY
    return true


func _complete_undeploy(source_entity: Node3D) -> void:
    if not is_instance_valid(source_entity):
        _state = DeployState.IDLE
        return
    var target_data := EntityFactory.get_entity_data(undeploys_into)
    if not target_data:
        _state = DeployState.IDLE
        return
    var snap := _snapshot_entity(source_entity)
    var source_position := source_entity.global_position
    var source_stats := source_entity.get_node_or_null("StatsComponent") as StatsComponent
    var source_data_id: String = source_stats.id if source_stats else ""
    _deselect_entity(source_entity)
    _unregister_building_cells(source_entity)
    if not source_data_id.is_empty():
        var source_data := EntityFactory.get_entity_data(source_data_id)
        if source_data:
            PrerequisiteSystem.unregister_building(snap["player_id"], source_data)
    call_deferred("_do_undeploy", source_entity, source_position, target_data, snap)


## Execute the deferred undeploy: create target, apply snapshot, free source.
func _do_undeploy(
    source: Node3D,
    source_position: Vector3,
    _target_data: EntityData,
    snap: Dictionary,
) -> void:
    if not is_instance_valid(source):
        _state = DeployState.IDLE
        return
    var target_entity := EntityFactory.create_entity(undeploys_into)
    if not target_entity:
        push_error("[Deploy] Failed to create target entity: %s" % undeploys_into)
        source.queue_free()
        _state = DeployState.IDLE
        return
    var target_cell := CellUtil.world_to_cell(source_position) + deploy_cell
    var world_pos := CellUtil.cell_to_world(target_cell)
    world_pos.y = TerrainSystem.get_height_at_world_smooth(world_pos)
    target_entity.position = world_pos
    # Assign the player before add_child so MovementController._ready() caches the
    # real id (the crush filter's query side). Setting it post-add leaves
    # _player_id = -1 forever, so an undeployed crusher treats every unit as an
    # enemy and crushes friendlies.
    var deploy_stats := target_entity.get_node_or_null("StatsComponent") as StatsComponent
    if deploy_stats:
        deploy_stats.player_id = snap["player_id"]
    var parent := _get_buildings_parent()
    if parent:
        parent.add_child(target_entity)
    else:
        var tree := get_tree()
        if tree and tree.current_scene:
            tree.current_scene.add_child(target_entity)
    _apply_snapshot(target_entity, snap)
    # Issue pending move command to the new entity after creation.
    if _has_pending_move:
        var mc := target_entity.get_node_or_null("MovementController") as MovementController
        if mc:
            mc.set_target_position(_pending_move_target)
        _has_pending_move = false
    source.queue_free()
    _state = DeployState.IDLE


## --- Snapshot / Apply --------------------------------------------------------


## Capture all transferable entity state before destroy.
func _snapshot_entity(entity: Node3D) -> Dictionary:
    var snap: Dictionary = {}
    # Health ratio
    var health := entity.get_node_or_null("HealthComponent") as HealthComponent
    snap["health_ratio"] = health.get_health_ratio() if health else 1.0
    # Selection
    snap["was_selected"] = _is_selected(entity)
    # Player ID
    var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
    snap["player_id"] = stats.player_id if stats else -1
    return snap


## Apply snapshot state to the newly created target entity.
func _apply_snapshot(target: Node3D, snap: Dictionary) -> void:
    # Health
    if transfer_health_ratio:
        var health := target.get_node_or_null("HealthComponent") as HealthComponent
        if health and health.max_health > 0:
            health.current_health = int(float(health.max_health) * snap["health_ratio"])
    # Player ID
    var stats := target.get_node_or_null("StatsComponent") as StatsComponent
    if stats:
        stats.player_id = snap["player_id"]
    # Selection
    if snap["was_selected"]:
        var select := target.get_node_or_null("SelectComponent") as SelectComponent
        if select:
            SelectionManager.add_entity(select)


## --- Selection helpers -------------------------------------------------------


func _is_selected(entity: Node3D) -> bool:
    var select_comp := entity.get_node_or_null("SelectComponent") as SelectComponent
    return (
        select_comp != null
        and (select_comp.is_selected or SelectionManager.is_entity_selected(select_comp))
    )


## Deselect an entity from SelectionManager and clear hover state.
func _deselect_entity(entity: Node3D) -> void:
    var select_comp := entity.get_node_or_null("SelectComponent") as SelectComponent
    if select_comp:
        select_comp.set_is_selected(false)
        select_comp.set_is_hovering(false)
        SelectionManager.deselect_entity(select_comp)


## --- System registration helpers ---------------------------------------------


## Remove source entity from spatial hash and building manager.
func _remove_source_from_systems(_source_entity: Node3D) -> void:
    # If source is a vehicle, just remove from spatial hash
    # Vehicle cells are managed by spatial hash rebuild, no explicit unregister needed
    pass


## Unregister building cells from spatial hash.
func _unregister_building_cells(building_entity: Node3D) -> void:
    var idx := BuildingManager._find_building_index(building_entity)
    if idx >= 0:
        var entry: Dictionary = BuildingManager._buildings[idx]
        var cells: Array = entry.get("cells", []) as Array
        if not cells.is_empty():
            SpatialHash.instance.unregister_building_cells(cells)
        BuildingManager._buildings.remove_at(idx)


## --- Utility ----------------------------------------------------------------


## Get buildings parent node.
func _get_buildings_parent() -> Node3D:
    return BuildingManager._get_buildings_parent()


## Calculate world position from origin cell and foundation.
func _cell_origin_to_world(origin: Vector2i, footprint: Vector2i) -> Vector3:
    return CellUtil.cell_origin_to_world(origin, footprint)


## Get max height across foundation cells.
func _get_max_height(origin: Vector2i, footprint: Vector2i) -> float:
    return CellUtil.get_max_height(
        origin, footprint, func(c: Vector2i) -> float: return TerrainSystem.get_cell_max_height(c)
    )


## Get rotation speed from the source entity data.
func _get_rotation_speed(entity: Node3D) -> float:
    var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
    if stats and not stats.id.is_empty():
        var data := EntityFactory.get_entity_data(stats.id)
        if data:
            return data.rotation_speed
    return 180.0
