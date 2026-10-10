extends Node

signal build_mode_changed(is_active: bool, player_id: int)
signal building_placed(building: Node3D, entity_data: EntityData)
signal building_sold(building: Node3D, entity_data: EntityData)
signal building_repaired(building: Node3D, entity_data: EntityData)
signal building_destroyed(building: Node3D, entity_data: EntityData)

var is_build_mode: bool = false
var current_building_type: EntityData = null
var _buildings: Array[Dictionary] = []
var exiting_build_mode: bool = false
var _skip_input_frames: int = 0

var building_types: Array[EntityData] = []

var _preview: Node3D = null
var _building_preview: Node3D = null
var _grid_overlay: PlacementGridOverlay = null


func _ready() -> void:
    _load_building_types()
    _create_preview()
    EntityFactory.spawned.connect(_on_entity_spawned)


## Single registration path for every building that enters the world, regardless
## of source (build mode, map load, deploy). Driven by the spawn seam so
## map-loaded and deployed buildings register identically to runtime placements.
func _on_entity_spawned(entity: Node3D, data: EntityData, player_id: int) -> void:
    if data == null or data.entity_type != EntityData.EntityType.BUILDING:
        return
    _register_building_entity(entity, data, player_id)


func _register_building_entity(entity: Node3D, data: EntityData, player_id: int) -> void:
    var fc := entity.get_node_or_null("FoundationComponent") as FoundationComponent
    var foundation: Vector2i = fc.foundation if fc else data.foundation
    var bib: Array[Vector2i] = fc.bib_cells if fc else data.bib_cells
    var origin := CellUtil.world_to_cell_origin(entity.global_position, foundation)
    var cells := FoundationComponent.occupied_cells(foundation, bib, origin)
    (
        _buildings
        . append(
            {
                "node": entity,
                "type": data,
                "origin": origin,
                "cells": cells,
                "player_id": player_id,
            }
        )
    )
    if player_id >= 0:
        PrerequisiteSystem.register_building(player_id, data)
    var health := entity.get_node_or_null("HealthComponent") as HealthComponent
    if health:
        var on_death := _on_building_destroyed.bind(entity)
        if not health.health_zero.is_connected(on_death):
            health.health_zero.connect(on_death)


## Clears the per-match building registry. Called before a new match's map loads
## so a previous match's buildings do not accumulate on top of the new set.
func clear_registry() -> void:
    _buildings.clear()


func _load_building_types() -> void:
    var all_buildings := EntityFactory.get_all_by_type(EntityData.EntityType.BUILDING)
    for data in all_buildings:
        if data.buildable:
            building_types.append(data)


func _process(_delta: float) -> void:
    if Engine.is_editor_hint():
        return

    if not is_build_mode:
        return

    # Skip input for one frame after entering build mode to prevent
    # the click that triggered it from also placing the building
    if _skip_input_frames > 0:
        _skip_input_frames -= 1
        _update_preview_position()
        return

    _update_preview_position()

    if Input.is_action_just_pressed("select_entity"):
        # The gameplay minimap owns its own clicks; do not place through it.
        if not UIUtil.is_mouse_over_minimap():
            _try_place_building()
    elif Input.is_action_just_pressed("deselect_entity"):
        exit_build_mode()
    elif Input.is_action_just_pressed("ui_cancel"):
        exit_build_mode()


func enter_build_mode(building_type: EntityData) -> void:
    if is_build_mode and current_building_type == building_type:
        exit_build_mode()
        return

    current_building_type = building_type
    is_build_mode = true
    _skip_input_frames = 1
    # Re-set white even when the overlay survives a type switch mid-session —
    # _ensure_grid_overlay only populates it on creation.
    _ensure_grid_overlay()
    _grid_overlay.set_white_cells(_white_cells_in_bounds(building_type))
    _create_building_preview()
    _show_preview(true)
    build_mode_changed.emit(true, PlayerManager.get_local_player_id())


func exit_build_mode() -> void:
    is_build_mode = false
    current_building_type = null
    _show_preview(false)
    # Free preview building so its collision shapes leave the physics space
    for child in _preview.get_children():
        child.queue_free()
    _building_preview = null
    _grid_overlay = null
    build_mode_changed.emit(false, PlayerManager.get_local_player_id())


## The place-anywhere cheat bypasses placement validity only (bounds-only in
## can_place); the charge still applies unless the item was production-paid.
func _place_anywhere_active() -> bool:
    return Cheats.place_anywhere


func can_place(building_type: EntityData, origin_cell: Vector2i) -> bool:
    # Cheat mode: place anywhere (skip cell checks, keep bounds check)
    if _place_anywhere_active():
        return _is_in_bounds(origin_cell)

    # Bounds and play area — BuildingManager-only knowledge
    for dx in building_type.foundation.x:
        for dz in building_type.foundation.y:
            var cell := origin_cell + Vector2i(dx, dz)
            if not _is_in_bounds(cell):
                return false
            if not _is_in_play_area(cell):
                return false

    # Cell availability + terrain height variation — canonical footprint check
    if not FoundationComponent.footprint_buildable(building_type.foundation, origin_cell):
        return false

    # Adjacency requirement (EntityData.adjacent) — needs the building registry
    if not _is_adjacency_satisfied(building_type, origin_cell):
        return false

    return true


## Buildings with `adjacent > 0` must be placed within `adjacent` empty cells
## (Chebyshev gap) of an existing friendly building footprint, i.e. some
## footprint cell within Chebyshev `adjacent + 1` of a friendly cell. Touching
## always qualifies. `adjacent <= 0` = no requirement. Expressed as a set
## dilation so the white overlay shares the same primitive (#352).
func _is_adjacency_satisfied(building_type: EntityData, origin_cell: Vector2i) -> bool:
    var max_gap := building_type.adjacent
    if max_gap <= 0:
        return true
    var reach_radius := max_gap + 1
    var reach := _dilate_cells(_friendly_building_cells(), reach_radius, reach_radius)
    for fc in FoundationComponent.footprint_cells(building_type.foundation, origin_cell):
        if reach.has(fc):
            return true
    return false


## Foundation cells of every friendly (local-player) building in the registry.
## Uses the full foundation rect (origin + EntityData.foundation), not the
## stored non-bib cells: bib cells are part of the footprint and must dilate
## adjacency/white exactly like regular foundation cells (#352 follow-up).
func _friendly_building_cells() -> Array[Vector2i]:
    var pid := PlayerManager.get_local_player_id()
    var cells: Array[Vector2i] = []
    for entry in _buildings:
        var node := entry.get("node") as Node3D
        if not is_instance_valid(node):
            continue
        var stats := node.get_node_or_null("StatsComponent") as StatsComponent
        if not stats or stats.player_id != pid:
            continue
        var data := entry.get("type") as EntityData
        var origin: Vector2i = entry.get("origin", Vector2i.ZERO)
        if data:
            for cell in FoundationComponent.footprint_cells(data.foundation, origin):
                cells.append(cell)
        else:
            for cell in entry.get("cells", []) as Array:
                cells.append(cell)
    return cells


## Exact per-cell dilation of a cell set by per-axis radii (equal radii give
## the Chebyshev disk). Per-cell rather than bounding-box so concave cell sets
## (bibs) dilate exactly like the per-pair adjacency rule.
func _dilate_cells(cells: Array[Vector2i], radius_x: int, radius_z: int) -> Dictionary:
    var result := {}
    for cell in cells:
        for dx in range(-radius_x, radius_x + 1):
            for dz in range(-radius_z, radius_z + 1):
                result[Vector2i(cell.x + dx, cell.y + dz)] = true
    return result


## White-region rule (#352): friendly building footprints dilated by the
## ghost's clamped `adjacent` value, then by the ghost's full foundation size
## per XZ axis. The two box dilations compose additively per axis, so a single
## pass with radii (adjacent + foundation.x, adjacent + foundation.y) is exact.
func _adjacent_reachable_cells(building_type: EntityData) -> Dictionary:
    var adjacent := maxi(building_type.adjacent, 0)
    return _dilate_cells(
        _friendly_building_cells(),
        adjacent + building_type.foundation.x,
        adjacent + building_type.foundation.y,
    )


## White region clamped to the map — out-of-bounds cells never render.
func _white_cells_in_bounds(building_type: EntityData) -> Array[Vector2i]:
    var cells: Array[Vector2i] = []
    for cell in _adjacent_reachable_cells(building_type):
        if _is_in_bounds(cell):
            cells.append(cell)
    return cells


func place_building(building_type: EntityData, origin_cell: Vector2i) -> bool:
    var pid := PlayerManager.get_local_player_id()
    # A production-paid building committing through any placement path (build
    # mode or the cheat ghost) must not charge twice; its ready entry is
    # consumed only once the building actually lands (#339).
    var was_ready: bool = ProductionManager.is_ready_to_place(pid, building_type.id)

    if not can_place(building_type, origin_cell):
        return false

    var parent := _get_buildings_parent()
    if parent == null:
        push_error("[BuildingManager] no scene root for %s" % building_type.id)
        return false

    # Deduct cost unless already paid via the production queue
    if not was_ready:
        var reason := "build:%s" % building_type.id
        if not EconomyManager.deduct(pid, building_type.cost, reason):
            push_warning("[BuildingManager] Insufficient funds for %s" % building_type.id)
            return false

    var world_pos := _cell_origin_to_world(origin_cell, building_type.foundation)
    var max_height := _get_max_height(origin_cell, building_type.foundation)
    world_pos.y = max_height

    # Entry through the seam: position and player before insertion, registration
    # (occupancy via FoundationComponent, registry/prereq/death via the spawn
    # event) owned by the seam and the registrar.
    var building := (
        EntityFactory.spawn(
            building_type.id, {"world_pos": world_pos, "player_id": pid, "parent": parent}
        )
        as Node3D
    )
    if not building:
        push_error("[BuildingManager] Failed to create building entity")
        return false

    # Level the terrain under the footprint after placement
    TerrainSystem.flatten_footprint(origin_cell, building_type.foundation)

    building_placed.emit(building, building_type)

    # Play the placement buildup, if authored. Map-load and deploy-created
    # structures never reach place_building, so they skip buildup.
    var art := building.get_node_or_null("ArtComponent") as ArtComponent
    if art:
        art.play_buildup()

    # Resume production queue for this player
    ProductionManager.clear_waiting_for_placement(pid)
    if was_ready:
        ProductionManager.consume_ready_building(pid, building_type.id)

    return true


func get_all_buildings() -> Array[Dictionary]:
    return _buildings


func _cell_origin_to_world(origin: Vector2i, footprint: Vector2i) -> Vector3:
    return CellUtil.cell_origin_to_world(origin, footprint)


func _get_max_height(origin: Vector2i, footprint: Vector2i) -> float:
    return CellUtil.get_max_height(
        origin, footprint, func(c: Vector2i) -> float: return TerrainSystem.get_cell_max_height(c)
    )


func _is_cell_free(cell: Vector2i) -> bool:
    return FoundationComponent.is_cell_buildable(cell)


func _is_in_bounds(cell: Vector2i) -> bool:
    return BoundsSystem.is_in_map_bounds(cell)


func _is_in_play_area(cell: Vector2i) -> bool:
    return BoundsSystem.is_in_play_area_with_margin(cell)


## Player-built structures parent to the match World root's Entities container,
## resolved per call so nothing is cached across a match swap. With no World
## (map editor, headless tests) the seam falls back to the current scene root,
## which may not be a Node3D, so callers treat the result as a plain Node.
func _get_buildings_parent() -> Node:
    return World.spawn_container(World.Bucket.ENTITIES)


func _create_preview() -> void:
    _preview = Node3D.new()
    _preview.name = "PlacementPreview"
    _preview.visible = false
    add_child(_preview)


func _ensure_grid_overlay() -> void:
    if _grid_overlay and is_instance_valid(_grid_overlay):
        return
    _grid_overlay = PlacementGridOverlay.new()
    _grid_overlay.name = "PlacementGridOverlay"
    _grid_overlay.cell_state_resolver = _resolve_highlight_cell_state
    _preview.add_child(_grid_overlay)
    if current_building_type:
        _grid_overlay.set_white_cells(_white_cells_in_bounds(current_building_type))


## HIDDEN = outside map (never drawn); FREE = in play area and unoccupied;
## BLOCKED = everything else (#352).
func _resolve_highlight_cell_state(cell: Vector2i) -> int:
    if not _is_in_bounds(cell):
        return PlacementGridOverlay.CellState.HIDDEN
    if _is_in_play_area(cell) and _is_cell_free(cell):
        return PlacementGridOverlay.CellState.FREE
    return PlacementGridOverlay.CellState.BLOCKED


func _show_preview(show: bool) -> void:
    if _preview:
        _preview.visible = show


func _update_preview_position() -> void:
    if not _preview or not current_building_type:
        return

    var mouse_pos := get_viewport().get_mouse_position()
    var camera := _get_camera_3d()
    if not camera:
        return

    var hit: Variant = TerrainSystem.mouse_ray_to_terrain(camera, mouse_pos)
    if hit == null:
        _preview.visible = false
        return
    var hit_pos := hit as Vector3

    var mouse_cell := CellUtil.world_to_cell(hit_pos)
    var origin_cell := (
        mouse_cell
        - Vector2i(current_building_type.foundation.x >> 1, current_building_type.foundation.y >> 1)
    )

    var valid := can_place(current_building_type, origin_cell)
    _update_preview_mesh(valid, origin_cell)
    _preview.visible = true


func _update_preview_mesh(_valid: bool, origin_cell: Vector2i) -> void:
    if not _preview or not current_building_type:
        return

    _ensure_grid_overlay()
    (
        _grid_overlay
        . set_cursor(
            origin_cell,
            current_building_type.foundation,
            current_building_type.adjacent > 0,
        )
    )

    var any_out_of_bounds := false
    for dx in current_building_type.foundation.x:
        for dz in current_building_type.foundation.y:
            var cell := origin_cell + Vector2i(dx, dz)
            if not _is_in_bounds(cell):
                any_out_of_bounds = true
                break
        if any_out_of_bounds:
            break

    if _building_preview:
        if any_out_of_bounds:
            _building_preview.visible = false
        else:
            var world_pos := _cell_origin_to_world(origin_cell, current_building_type.foundation)
            var max_height := _get_max_height(origin_cell, current_building_type.foundation)
            world_pos.y = max_height
            _building_preview.position = world_pos
            _building_preview.visible = true


func _create_building_preview() -> void:
    if _building_preview:
        _building_preview.queue_free()
        _building_preview = null
    _building_preview = (
        EntityFactory.spawn(current_building_type.id, {"detached": true, "parent": _preview})
        as Node3D
    )
    if _building_preview:
        _set_node_transparency(_building_preview, 0.75)
        # The model may load asynchronously; re-apply transparency once it arrives.
        var art := _building_preview.get_node_or_null("ArtComponent") as ArtComponent
        if art:
            art.model_loaded.connect(_on_preview_model_loaded)


func _on_preview_model_loaded() -> void:
    if is_instance_valid(_building_preview):
        _set_node_transparency(_building_preview, 0.75)


func _set_node_transparency(node: Node, alpha: float) -> void:
    var mat := StandardMaterial3D.new()
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color(0.75, 0.75, 0.75, alpha)
    _apply_transparency(node, mat)


func _apply_transparency(node: Node, mat: StandardMaterial3D) -> void:
    if node is MeshInstance3D:
        (node as MeshInstance3D).material_override = mat
    for child in node.get_children():
        _apply_transparency(child, mat)


func _try_place_building() -> void:
    if not current_building_type:
        return

    var mouse_pos := get_viewport().get_mouse_position()
    var camera := _get_camera_3d()
    if not camera:
        return

    var hit: Variant = TerrainSystem.mouse_ray_to_terrain(camera, mouse_pos)
    if hit == null:
        return
    var hit_pos := hit as Vector3

    var mouse_cell := CellUtil.world_to_cell(hit_pos)
    var origin_cell := (
        mouse_cell
        - Vector2i(current_building_type.foundation.x >> 1, current_building_type.foundation.y >> 1)
    )
    if not place_building(current_building_type, origin_cell):
        # TODO: play invalid placement SFX
        push_warning("[BuildingManager] Cannot place here")
        return
    exiting_build_mode = true
    exit_build_mode()


func _get_camera_3d() -> Camera3D:
    # The gameplay camera is the root viewport's current camera. Prefer that —
    # the map is nested under MainScene/Gameplay/World, so it is not
    # `current_scene` and a current_scene/Camera path would miss it.
    var camera := get_viewport().get_camera_3d()
    if camera:
        return camera
    # Fallback for when no camera is current (e.g. a standalone map scene):
    # search the scene recursively rather than assuming a fixed child path.
    var tree := get_tree()
    if not tree:
        return null
    var root := tree.current_scene
    if not root:
        return null
    return root.find_child("Camera3D", true, false) as Camera3D


func sell_building(building_node: Node3D) -> bool:
    var idx := _find_building_index(building_node)
    if idx < 0:
        return false
    var entry: Dictionary = _buildings[idx]
    var entity_data: EntityData = entry.get("type") as EntityData
    if not entity_data:
        return false
    var owner_id := _building_owner(building_node, entry)
    # Selling is only allowed by the acting (local) player against their own
    # building. Refusing here keeps the rule true for any caller, not just the
    # sell order generator.
    if owner_id < 0 or owner_id != PlayerManager.get_local_player_id():
        return false
    # Refund a rules-configurable share of the cost to the building's owner.
    var rules := GlobalRules.get_current()
    var refund_pct: float = rules.refund_percent if rules else 0.5
    var refund: int = int(entity_data.cost * refund_pct)
    EconomyManager.add(
        owner_id, refund, "sell:%s" % entity_data.id, EconomyManager.get_default_category(), true
    )
    # Unregister from prerequisite system for the owner.
    PrerequisiteSystem.unregister_building(owner_id, entity_data)
    # Occupancy cells are unregistered by FoundationComponent on world exit.
    # Remove from list
    _buildings.remove_at(idx)
    # Deselect before freeing so rally line clears
    var select_comp := building_node.get_node_or_null("SelectComponent") as SelectComponent
    if select_comp:
        SelectionManager.deselect_entity(select_comp)
    # Emit signal before freeing
    building_sold.emit(building_node, entity_data)
    GhostDepot.capture_entity(building_node)
    # Free the node
    building_node.queue_free()
    return true


## Owning player for a building: the live StatsComponent when present, the
## player id recorded at registration next, and the local player as a last
## resort for legacy registry entries built without either.
func _building_owner(building_node: Node3D, entry: Dictionary) -> int:
    var stats := building_node.get_node_or_null("StatsComponent") as StatsComponent
    if stats and stats.player_id >= 0:
        return stats.player_id
    if entry.has("player_id"):
        return int(entry["player_id"])
    return PlayerManager.get_local_player_id()


func _on_building_destroyed(building_node: Node3D) -> void:
    var idx := _find_building_index(building_node)
    if idx < 0:
        return
    var entry: Dictionary = _buildings[idx]
    var entity_data: EntityData = entry.get("type") as EntityData
    var owner_id := _building_owner(building_node, entry)
    # Unregister from prerequisite system for the owner.
    PrerequisiteSystem.unregister_building(owner_id, entity_data)
    # Occupancy cells are unregistered by FoundationComponent on world exit.
    # Remove from list
    _buildings.remove_at(idx)
    # Deselect before freeing
    var select_comp := building_node.get_node_or_null("SelectComponent") as SelectComponent
    if select_comp:
        SelectionManager.deselect_entity(select_comp)
    # Emit signal before freeing
    building_destroyed.emit(building_node, entity_data)
    # Free the node
    building_node.queue_free()


## Removes a building from the registry and its owner's prerequisites without
## firing death cleanup. Used when a building is transformed away (undeploy).
## Occupancy cells are unregistered by FoundationComponent on world exit.
func unregister_building_entity(building_node: Node3D) -> void:
    var idx := _find_building_index(building_node)
    if idx < 0:
        return
    var entry: Dictionary = _buildings[idx]
    var entity_data: EntityData = entry.get("type") as EntityData
    var owner_id := _building_owner(building_node, entry)
    if entity_data:
        PrerequisiteSystem.unregister_building(owner_id, entity_data)
    _buildings.remove_at(idx)


func repair_building(building_node: Node3D) -> bool:
    var idx := _find_building_index(building_node)
    if idx < 0:
        return false
    var entry: Dictionary = _buildings[idx]
    var entity_data: EntityData = entry.get("type") as EntityData
    if not entity_data:
        return false
    # Check if already at full health
    var health := building_node.get_node_or_null("HealthComponent")
    if health and health is HealthComponent:
        if health.current_health >= entity_data.strength:
            return false
        # Heal by repair_step from GlobalRules
        var rules := GlobalRules.get_current()
        var repair_step: int = rules.repair_step if rules else 8
        var heal_amount: int = mini(repair_step, entity_data.strength - health.current_health)
        health.heal(heal_amount)
    building_repaired.emit(building_node, entity_data)
    return true


func _find_building_index(building_node: Node3D) -> int:
    for i in range(_buildings.size()):
        var entry: Dictionary = _buildings[i]
        if entry.get("node") == building_node:
            return i
    return -1


func get_building_at_cell(cell: Vector2i) -> Node3D:
    for entry in _buildings:
        var cells: Array = entry.get("cells", []) as Array
        if cell in cells:
            return entry.get("node") as Node3D
    return null
