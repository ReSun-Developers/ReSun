class_name DeployComponent extends Node

## Bidirectional deploy/undeploy component.
## Configures vehicle→building (deploy) and building→vehicle (undeploy) transformations.
## Uses snapshot+deferred pattern: capture state → deselect → defer create+free.

enum DeployState { IDLE, SEEKING_DEPLOY, ROTATING_DEPLOY, ROTATING_UNDEPLOY, TRANSFORMING }

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
## Search radius in cells for a deployable cell whose foundation is free. The
## deploying unit drives to the centre of the nearest valid cell before rotating.
@export var deploy_search_radius_cells: int = 6

var _state: int = DeployState.IDLE
var _target_entity: Node3D = null
var _target_cell: Vector2i = Vector2i(-1, -1)
var _target_rot_y: float = 0.0
var _rotation_speed: float = 180.0
var _pending_move_target: Vector3 = Vector3.ZERO
var _has_pending_move: bool = false


func _exit_tree() -> void:
    _state = DeployState.IDLE
    _target_entity = null
    _target_cell = Vector2i(-1, -1)


func _process(delta: float) -> void:
    if _state == DeployState.SEEKING_DEPLOY:
        _check_seek_interrupted()
        return
    if _state != DeployState.ROTATING_DEPLOY and _state != DeployState.ROTATING_UNDEPLOY:
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


## Cancel an in-flight deploy or undeploy (Stop command). A committed
## `TRANSFORMING` step cannot be cancelled; every other state reverts to IDLE so
## the unit is commandable again and does not resume the cancelled order.
func cancel_deploy() -> void:
    if _state == DeployState.TRANSFORMING:
        return
    _state = DeployState.IDLE
    _target_entity = null
    _target_cell = Vector2i(-1, -1)


## True when `entity` has a DeployComponent mid-transition. Movement systems that
## relocate idle units (scatter/nudge) must skip it: deploy halts the unit to
## IDLE while it rotates, but it must not be moved until the transform completes.
static func is_entity_transitioning(entity: Node) -> bool:
    if entity == null:
        return false
    var deploy := entity.get_node_or_null("DeployComponent") as DeployComponent
    return deploy != null and deploy.is_transitioning()


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


## Calculate the origin cell for the deployed building, centering it on the source entity.
func calculate_deploy_origin(source_entity: Node3D, target_data: EntityData) -> Vector2i:
    var source_cell := CellUtil.world_to_cell(source_entity.global_position)
    return _origin_for_cell(source_cell, target_data.foundation)


## Origin cell (top-left for buildings) of a foundation centred on `cell`.
func _origin_for_cell(cell: Vector2i, foundation: Vector2i) -> Vector2i:
    var half_x: int = int(foundation.x * 0.5)
    var half_y: int = int(foundation.y * 0.5)
    return cell - Vector2i(half_x, half_y)


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
        # Never scatter another unit that is itself mid-deploy.
        if is_entity_transitioning(entity_node):
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


## Execute the deploy order. Returns true if the deploy engaged (the unit is
## either moving to a deployable cell, rotating, or transforming).
##
## A deploying unit must stand at the centre of a cell whose whole foundation is
## free. If the current cell does not qualify, the nearest valid cell within
## `deploy_search_radius_cells` is chosen and the unit drives to its centre
## before rotating to `deploy_rotation` and transforming.
func execute_deploy(source_entity: Node3D) -> bool:
    if is_transitioning() or not can_deploy() or not is_instance_valid(source_entity):
        return false
    var target_data := EntityFactory.get_entity_data(deploys_into)
    if not target_data:
        return false

    var deploy_cell := _find_deploy_cell(source_entity, target_data)
    if deploy_cell == Vector2i(-1, -1):
        push_warning("[Deploy] No free cell for %s" % deploys_into)
        return false

    # Only once a cell is confirmed: cancel the orders that must not resume
    # after the deploy. A failed search above leaves the unit's orders intact.
    _cancel_non_movement_activity(source_entity)

    _target_cell = deploy_cell
    _target_entity = source_entity
    _rotation_speed = _get_rotation_speed(source_entity)
    _target_rot_y = deg_to_rad(deploy_rotation)
    return _move_to_deploy_cell(source_entity, deploy_cell)


## Drive to the chosen cell (or settle into it) before the deploy rotation.
func _move_to_deploy_cell(source_entity: Node3D, deploy_cell: Vector2i) -> bool:
    var mc := source_entity.get_node_or_null("MovementController") as MovementController
    if not mc:
        if CellUtil.world_to_cell(source_entity.global_position) != deploy_cell:
            push_warning("[Deploy] Cannot reach deploy cell without a MovementController")
            _state = DeployState.IDLE
            return false
        _begin_deploy_rotation(source_entity)
        return true

    _connect_movement(mc)
    var centre := CellUtil.cell_to_world(deploy_cell)
    var h_dist := (
        Vector2(
            source_entity.global_position.x - centre.x, source_entity.global_position.z - centre.z
        )
        . length()
    )
    if h_dist < 0.05:
        # Already centred on the chosen cell: nothing to drive, rotate in place.
        _begin_deploy_rotation(source_entity)
        return true

    _state = DeployState.SEEKING_DEPLOY
    if CellUtil.world_to_cell(source_entity.global_position) == deploy_cell:
        # Same cell: a pathfinder move to its own cell is empty, so glide
        # straight to the centre through the normal movement step.
        mc.move_to_point(centre)
    else:
        mc.set_target_position(centre)
    return _state == DeployState.SEEKING_DEPLOY


## Choose the cell to deploy on. Follows the unit's current path forward — like
## the Stop command — returning the first cell ahead whose foundation is free, so
## a moving unit continues in its travel direction instead of reversing. An idle
## unit uses its own cell, else the nearest free cell within the search radius.
## Returns (-1, -1) when none is found.
func _find_deploy_cell(source_entity: Node3D, target_data: EntityData) -> Vector2i:
    var mc := source_entity.get_node_or_null("MovementController") as MovementController
    if mc:
        for cell in mc.get_remaining_path_cells():
            if _is_deploy_cell_valid(cell, target_data, source_entity):
                return cell

    var start := CellUtil.world_to_cell(source_entity.global_position)
    if _is_deploy_cell_valid(start, target_data, source_entity):
        return start
    var best := Vector2i(-1, -1)
    var best_dist := INF
    for dx in range(-deploy_search_radius_cells, deploy_search_radius_cells + 1):
        for dz in range(-deploy_search_radius_cells, deploy_search_radius_cells + 1):
            if dx == 0 and dz == 0:
                continue
            var cell := start + Vector2i(dx, dz)
            if not _is_deploy_cell_valid(cell, target_data, source_entity):
                continue
            var dist := float(dx * dx + dz * dz)
            if dist < best_dist:
                best_dist = dist
                best = cell
    if best != Vector2i(-1, -1):
        return best
    scatter_blockers(source_entity, target_data)
    if _is_deploy_cell_valid(start, target_data, source_entity):
        return start
    return Vector2i(-1, -1)


## True when a foundation centred on `cell` is entirely free for the source.
func _is_deploy_cell_valid(cell: Vector2i, target_data: EntityData, source_entity: Node3D) -> bool:
    var origin := _origin_for_cell(cell, target_data.foundation)
    return _are_foundation_cells_free(origin, target_data.foundation, source_entity)


## Connect to the movement controller's arrival/failure signals exactly once.
func _connect_movement(mc: MovementController) -> void:
    if not mc.arrived.is_connected(_on_arrived):
        mc.arrived.connect(_on_arrived)
    if not mc.pathfinding_failed.is_connected(_on_pathfinding_failed):
        mc.pathfinding_failed.connect(_on_pathfinding_failed)


## Arrival during SEEKING_DEPLOY: if the unit drifted into a neighbouring cell,
## re-issue the move; otherwise re-check the cell is still free and start the
## deploy rotation.
func _on_arrived(_position: Vector3) -> void:
    if _state != DeployState.SEEKING_DEPLOY:
        return
    var source_entity := _target_entity
    if not is_instance_valid(source_entity):
        _state = DeployState.IDLE
        return
    if CellUtil.world_to_cell(source_entity.global_position) != _target_cell:
        var mc := source_entity.get_node_or_null("MovementController") as MovementController
        if mc:
            mc.set_target_position(CellUtil.cell_to_world(_target_cell))
        return
    var target_data := EntityFactory.get_entity_data(deploys_into)
    if not target_data or not _is_deploy_cell_valid(_target_cell, target_data, source_entity):
        push_warning("[Deploy] Deploy cell became blocked")
        _state = DeployState.IDLE
        _target_entity = null
        return
    _begin_deploy_rotation(source_entity)


func _on_pathfinding_failed() -> void:
    if _state == DeployState.SEEKING_DEPLOY:
        push_warning("[Deploy] Pathfinding failed while seeking a deploy cell")
        cancel_deploy()


## Safety net for a seek that was interrupted without an `arrived` or
## `pathfinding_failed` event (e.g. the Stop command halting the controller).
## A live seek always has the controller MOVING/ROTATING, so IDLE means stalled.
func _check_seek_interrupted() -> void:
    if not is_instance_valid(_target_entity):
        cancel_deploy()
        return
    var mc := _target_entity.get_node_or_null("MovementController") as MovementController
    if mc and not mc.is_moving():
        push_warning("[Deploy] Seek interrupted; deploy cancelled")
        cancel_deploy()


## Rotate the entity to the deploy heading, or transform immediately when aligned.
func _begin_deploy_rotation(source_entity: Node3D) -> void:
    _target_entity = source_entity
    _rotation_speed = _get_rotation_speed(source_entity)
    _target_rot_y = deg_to_rad(deploy_rotation)
    if abs(angle_difference(source_entity.rotation.y, _target_rot_y)) < 0.05:
        source_entity.rotation.y = _target_rot_y
        _target_entity = null
        _state = DeployState.TRANSFORMING
        _complete_deploy(source_entity)
    else:
        _state = DeployState.ROTATING_DEPLOY


## Cancel the orders that must not resume after the deploy: harvesting,
## transport unloading, and combat. Movement is repurposed by the seek, so it is
## not halted here. Each component is optional, so absent ones are no-ops.
func _cancel_non_movement_activity(entity: Node3D) -> void:
    var harvest := entity.get_node_or_null("HarvestComponent") as HarvestComponent
    if harvest:
        harvest.cancel_harvest(true)
    var transport := entity.get_node_or_null("TransportComponent") as TransportComponent
    if transport:
        transport.cancel_unload()
    var combat := entity.get_node_or_null("CombatComponent") as CombatComponent
    if combat:
        combat.clear_target()


func _complete_deploy(source_entity: Node3D) -> void:
    if not is_instance_valid(source_entity):
        _state = DeployState.IDLE
        return
    var target_data := EntityFactory.get_entity_data(deploys_into)
    if not target_data:
        _state = DeployState.IDLE
        return
    var origin := _origin_for_cell(_target_cell, target_data.foundation)
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
        var fallback: Node = World.spawn_container(World.Bucket.ENTITIES)
        if fallback:
            fallback.add_child(target_entity)
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
        var fallback: Node = World.spawn_container(World.Bucket.ENTITIES)
        if fallback:
            fallback.add_child(target_entity)
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
