extends Node

signal selection_changed(selected_entities: Array[SelectComponent])
signal hover_changed(entity: Node3D)

const SHROUD_LABEL := "UNREVEALED TERRAIN"

var selected_entities: Array[SelectComponent] = []
var is_hovering: bool = false
var hovered_entity: SelectComponent = null
## Hovered entity regardless of selectability (units, structures, resources).
var hovered_node: Node3D = null
## Fixed tooltip label for hover states without an entity (e.g. shrouded cells).
var hover_label_override: String = ""

var _pending_moves: Array[Array] = []
var _pending_index: int = 0
var _selection_sync_counter: int = 0
## Batch-lifetime terrain-cost cache shared across one move order's 8-per-frame
## drain, so all units in the order read terrain cost data once. Created in
## `request_move` (the order boundary bumps Pathfinder's world generation).
var _cost_cache: Pathfinder.PathCostCache = null
## Batch-lifetime TerrainSystem reference, resolved once per move order so per-unit
## path resolution never walks the scene tree for the autoload.
var _terrain: Node = null
## Perf-guard counter: "selectable"-group scans by the throttled sync. The
## per-frame path must only scan every 6th frame (test/unit/test_perf_guard.gd).
## ponytail: only catches scans routed through this scan site.
var perf_group_scans: int = 0


func _ready():
    if not Engine.is_editor_hint() and OS.is_stdout_verbose():
        print("✅ SelectionManager loaded successfully!")


func select_entity(entity: SelectComponent, shift_pressed: bool = false):
    if not entity:
        return
    if not _is_entity_selectable(entity):
        return

    if shift_pressed and entity in selected_entities:
        remove_entity(entity)
        return

    if shift_pressed:
        clear_incompatible_selection(entity)
        add_entity(entity)
    else:
        deselect_all()
        add_entity(entity)
    _play_select_voice(entity)


## Reference rule (TS `ObjectClass::Select`): a selection never mixes local and
## non-local owners. Clear when the current head and the incoming entity are not
## both local — adding an enemy wipes the player's units, and adding a unit wipes
## a selected enemy. Enemy selection is therefore always a single entity.
func clear_incompatible_selection(entity: SelectComponent) -> void:
    if selected_entities.is_empty():
        return
    var head := selected_entities[0]
    if not is_instance_valid(head) or not is_instance_valid(entity):
        return
    var head_parent := head.get_parent() as Node3D
    var new_parent := entity.get_parent() as Node3D
    if not (_is_local_entity_node(head_parent) and _is_local_entity_node(new_parent)):
        deselect_all()


func deselect_entity(entity: SelectComponent):
    remove_entity(entity)


func deselect_all():
    clear_hover_preview()
    # Snapshot then clear first so the set_is_selected(false) cascade
    # (_on_selection_state_changed) sees each entity already gone and skips its
    # emits — deselecting N units fires exactly one selection_changed, not N+1.
    var snapshot := selected_entities.duplicate()
    selected_entities.clear()
    for entity in snapshot:
        if is_instance_valid(entity) and entity.has_method("set_is_selected"):
            entity.set_is_selected(false)
    var tree := get_tree()
    if tree:
        for entity in tree.get_nodes_in_group("selectable"):
            var select_comp := entity.get_node_or_null("SelectComponent") as SelectComponent
            if select_comp and select_comp.is_selected:
                select_comp.set_is_selected(false)
    selection_changed.emit([] as Array[SelectComponent])


func add_entity(entity: SelectComponent):
    if entity and is_instance_valid(entity) and not selected_entities.has(entity):
        selected_entities.append(entity)

        if entity.has_method("set_is_selected"):
            entity.set_is_selected(true)

        emit_signal("selection_changed", selected_entities.duplicate())


func _play_select_voice(select_comp: SelectComponent) -> void:
    if not is_instance_valid(select_comp):
        return
    var entity := select_comp.get_parent() as Node3D
    if not is_instance_valid(entity):
        return
    var voice := entity.get_node_or_null("VoiceComponent") as VoiceComponent
    if not voice or not voice.voice_data:
        return
    if not _is_local_entity_node(entity):
        return
    AudioManager.play_voice(voice.voice_data.id, VoiceData.EVENT_SELECT)


## Play exactly one select voice for a multi-unit selection event (C&C rule):
## the NW-most unit (top of screen, then right-most) speaks, never one per unit.
func play_select_voice_for_entities(entities: Array) -> void:
    var chosen := get_northwest_most(entities)
    if chosen:
        _play_select_voice(chosen)


## Deterministic single-voice picker mirroring TS/RA2: furthest northwest (screen
## top), then furthest northeast (planar right). Uses camera projection so the
## "top of screen" is screen-space; falls back to world-space (+Z is up) in
## headless/test contexts with no camera.
func get_northwest_most(entities: Array) -> SelectComponent:
    var camera := get_viewport().get_camera_3d() if get_viewport() else null
    var best: SelectComponent = null
    var best_screen := Vector2.INF
    for select_comp in entities:
        if not is_instance_valid(select_comp):
            continue
        var entity := select_comp.get_parent() as Node3D
        if not is_instance_valid(entity):
            continue
        var screen_pos := (
            camera.unproject_position(entity.global_position) if camera else Vector2.ZERO
        )
        if not camera:
            # Nodes not in the tree report global_position as zero; read local
            # position for the headless/test fallback ordering.
            screen_pos = Vector2(entity.position.x, entity.position.z)
        # Top-most (smallest y), then right-most (largest x).
        if (
            best == null
            or screen_pos.y < best_screen.y
            or (is_equal_approx(screen_pos.y, best_screen.y) and screen_pos.x > best_screen.x)
        ):
            best = select_comp
            best_screen = screen_pos
    return best


func _is_local_unit(entity: Node3D) -> bool:
    return _is_local_entity_node(entity)


func _is_local_entity_node(entity: Node3D) -> bool:
    return PlayerManager.is_entity_local(entity, PlayerManager.get_local_player_id())


func remove_entity(entity: SelectComponent):
    if entity in selected_entities:
        selected_entities.erase(entity)

        if is_instance_valid(entity) and entity.has_method("set_is_selected"):
            entity.set_is_selected(false)

        emit_signal("selection_changed", selected_entities.duplicate())


func toggle_entity(entity: SelectComponent):
    if entity in selected_entities:
        remove_entity(entity)
    else:
        add_entity(entity)


func set_hover_preview(enabled: bool, entity: SelectComponent = null):
    if enabled and entity == hovered_entity:
        return

    is_hovering = enabled

    if hovered_entity and is_instance_valid(hovered_entity) and hovered_entity != entity:
        hovered_entity.set_is_hovering(false)
    hovered_entity = entity if (enabled and entity and is_instance_valid(entity)) else null
    if is_instance_valid(hovered_entity):
        hovered_entity.set_is_hovering(true)
    _emit_hover(hovered_entity.get_parent() as Node3D if hovered_entity else null)


## Hover over a non-selectable entity (resources, dock hosts): sets the generic
## hover node without touching selectable selection state.
func set_hover_node(node: Node3D):
    if node == hovered_node and hover_label_override.is_empty():
        return
    if is_instance_valid(hovered_entity):
        hovered_entity.set_is_hovering(false)
        hovered_entity = null
    _emit_hover(node if is_instance_valid(node) else null)
    is_hovering = is_instance_valid(hovered_node)


## Hover over a shrouded cell: no entity, but the tooltip shows the shroud label.
func set_hover_shroud():
    if hovered_node == null and hover_label_override == SHROUD_LABEL:
        return
    if is_instance_valid(hovered_entity):
        hovered_entity.set_is_hovering(false)
        hovered_entity = null
    hovered_node = null
    hover_label_override = SHROUD_LABEL
    is_hovering = true
    hover_changed.emit(null)


func clear_hover_preview():
    set_hover_preview(false, null)


func _emit_hover(node: Node3D):
    hovered_node = node
    hover_label_override = ""
    hover_changed.emit(node)


func request_move(
    target_position: Vector3, skip_formation: bool = false, target_level: int = 0
) -> void:
    if selected_entities.is_empty():
        return

    SpatialHash.instance.clear_reservations()

    for ent in selected_entities:
        if not is_instance_valid(ent):
            continue
        var parent := ent.get_parent() as Node3D
        if _is_entity_transitioning(parent):
            continue
        if not _is_local_entity(ent):
            continue
        # Skip entities with DeployComponent — they handle undeploy via OrderResult
        var deploy := parent.get_node_or_null("DeployComponent") as DeployComponent
        if deploy and deploy.can_undeploy():
            continue
        if is_instance_valid(parent):
            var own_mc := parent.get_node_or_null("MovementController") as MovementController
            var own_level: int = own_mc._surface_level if own_mc else 0
            SpatialHash.instance.force_reserve(
                CellUtil.world_to_cell(parent.global_position), own_level
            )

    var center := Vector3.ZERO
    var count := 0
    for ent in selected_entities:
        if not is_instance_valid(ent):
            continue
        var parent := ent.get_parent() as Node3D
        if _is_entity_transitioning(parent):
            continue
        if not _is_local_entity(ent):
            continue
        if is_instance_valid(parent):
            center += parent.global_position
            count += 1
    if count == 0:
        return
    center /= count

    _pending_moves.clear()
    _pending_index = 0
    # New order = new world snapshot: bump the generation and start a fresh
    # batch-lifetime terrain-cost cache for the drain. Resolve the TerrainSystem
    # reference once per order so per-unit pathing skips the autoload lookup.
    Pathfinder.bump_world_generation()
    _cost_cache = Pathfinder.PathCostCache.new()
    _cost_cache.generation = Pathfinder._world_generation
    _terrain = Pathfinder._get_terrain_system()

    var sharers: Array[SelectComponent] = []
    var vehicles: Array[SelectComponent] = []

    # Snapshot — undeploy mutates selected_entities mid-loop
    var snapshot := selected_entities.duplicate()
    for ent in snapshot:
        if not is_instance_valid(ent):
            continue
        var parent := ent.get_parent() as Node3D
        if not is_instance_valid(parent):
            continue
        if _is_entity_transitioning(parent):
            continue
        if not _is_local_entity(ent):
            continue

        # Check for deploy component — undeploy handled by DeployComponent OrderResult
        var deploy := parent.get_node_or_null("DeployComponent") as DeployComponent
        if deploy and deploy.can_undeploy():
            continue

        var mc := parent.get_node_or_null("MovementController") as MovementController
        if mc and mc.shares_cell():
            sharers.append(ent)
        else:
            vehicles.append(ent)

    # Vehicles reserve destinations first: infantry sub-slot assignment below
    # rejects reserved cells, so the two passes can never claim the same cell.
    for ent in vehicles:
        var parent := ent.get_parent() as Node3D
        if not is_instance_valid(parent):
            continue
        var target: Vector3
        if skip_formation:
            target = target_position
        else:
            var offset := parent.global_position - center
            var cell_offset := Vector2i(
                roundi(offset.x / CellUtil.CELL_SIZE), roundi(offset.z / CellUtil.CELL_SIZE)
            )
            if abs(cell_offset.x) > 2 or abs(cell_offset.y) > 2:
                cell_offset.x = clampi(cell_offset.x, -2, 2)
                cell_offset.y = clampi(cell_offset.y, -2, 2)
            target = (
                target_position
                + Vector3(cell_offset.x * CellUtil.CELL_SIZE, 0, cell_offset.y * CellUtil.CELL_SIZE)
            )
        target = _bounded_player_target(target)
        var cell := CellUtil.world_to_cell(target)
        # A cell with infantry sub-slot claims (in flight or already boarded
        # destinations) is no parking spot for a vehicle.
        if (
            CellReservation.instance.get_claim_count(cell, target_level) > 0
            or not SpatialHash.instance.reserve_cell(cell, target_level)
        ):
            target = _fallback_target(target, target_level)
        _pending_moves.append([ent, target, target_level])

    for sharer in sharers:
        var parent := sharer.get_parent() as Node3D
        if not is_instance_valid(parent):
            continue
        var assigned_cell := _find_sharer_cell(target_position, target_level)
        var cell_center: Vector3 = _bounded_player_target(CellUtil.cell_to_world(assigned_cell))
        _pending_moves.append([sharer, cell_center, target_level])


func _process(_delta: float) -> void:
    _selection_sync_counter += 1
    if _selection_sync_counter % 6 == 0:
        _synchronize_visual_selection()
    var batch: int = 8
    while _pending_index < _pending_moves.size() and batch > 0:
        var data: Array = _pending_moves[_pending_index]
        var pending_level: int = int(data[2]) if data.size() > 2 else 0
        _execute_move(data[0] as SelectComponent, data[1] as Vector3, pending_level)
        _pending_index += 1
        batch -= 1


func _synchronize_visual_selection() -> void:
    var tree := get_tree()
    if not tree:
        return
    perf_group_scans += 1
    for entity in tree.get_nodes_in_group("selectable"):
        if not is_instance_valid(entity):
            continue
        var select_comp := entity.get_node_or_null("SelectComponent") as SelectComponent
        if not select_comp:
            continue
        if not select_comp.selection_state_changed.is_connected(_on_selection_state_changed):
            select_comp.selection_state_changed.connect(_on_selection_state_changed)
        # Add entities that are visually selected but not in the list
        if select_comp.is_selected and not selected_entities.has(select_comp):
            add_entity(select_comp)
        # Remove entities that are not visually selected but are in the list
        elif not select_comp.is_selected and selected_entities.has(select_comp):
            remove_entity(select_comp)


func _on_selection_state_changed(select_comp: SelectComponent) -> void:
    if not is_instance_valid(select_comp):
        return
    if select_comp.is_selected and not selected_entities.has(select_comp):
        selected_entities.append(select_comp)
        selection_changed.emit(selected_entities.duplicate())
    elif not select_comp.is_selected and selected_entities.has(select_comp):
        selected_entities.erase(select_comp)
        selection_changed.emit(selected_entities.duplicate())


func _execute_move(select_comp: SelectComponent, position: Vector3, target_level: int = 0) -> void:
    var parent := select_comp.get_parent() as Node
    if not is_instance_valid(parent):
        return
    if _is_entity_transitioning(parent as Node3D):
        return
    if not parent.has_node("MovementController"):
        return
    var mc := parent.get_node("MovementController") as MovementController
    if is_instance_valid(mc):
        mc.set_target_position(
            position, false, false, false, _cost_cache, _terrain, true, false, target_level
        )
    var harvest := parent.get_node_or_null("HarvestComponent") as HarvestComponent
    if harvest:
        harvest.cancel_harvest(true)


func _fallback_target(target: Vector3, level: int = 0) -> Vector3:
    var cell := CellUtil.world_to_cell(target)
    var result := CellUtil.spiral_first_free(
        cell,
        8,
        func(c: Vector2i) -> bool:
            if not BoundsSystem.is_in_order_area(c):
                return true
            if CellReservation.instance.get_claim_count(c, level) > 0:
                return true
            # `reserve_cell` itself refuses a `level > 0` cell with no live deck,
            # so the spiral never lands on a deckless above-ground cell.
            return not SpatialHash.instance.reserve_cell(c, level)
    )
    if result == cell:
        return target
    return CellUtil.cell_to_world(result)


func _is_entity_transitioning(entity: Node3D) -> bool:
    if not is_instance_valid(entity):
        return false
    var deploy := entity.get_node_or_null("DeployComponent") as DeployComponent
    return deploy != null and deploy.is_transitioning()


func is_entity_selected(entity: SelectComponent) -> bool:
    return selected_entities.has(entity)


func get_selected_entities():
    return selected_entities


func _is_local_entity(select_comp: SelectComponent) -> bool:
    var parent := select_comp.get_parent() as Node3D
    if not is_instance_valid(parent):
        return false
    return _is_local_entity_node(parent)


## Visible-bounds gate: entities whose cell lies outside the visible play
## diamond cannot be picked up by click or box select — every move order
## clamps inward, so the player could not reposition them anyway. Programmatic
## selection (add_entity) is intentionally not gated.
func is_entity_in_visible_bounds(entity: SelectComponent) -> bool:
    var parent := entity.get_parent() as Node3D
    if not is_instance_valid(parent):
        return true
    return BoundsSystem.is_in_play_area(CellUtil.world_to_cell(parent.global_position))


## Selectability gate: an entity must both lie inside the visible play diamond
## and be revealed through shroud/fog. Both gates apply; neither bypasses the
## other.
func _is_entity_selectable(entity: SelectComponent) -> bool:
    var parent := entity.get_parent() as Node3D
    if not is_instance_valid(parent):
        return true
    if not BoundsSystem.is_in_play_area(CellUtil.world_to_cell(parent.global_position)):
        return false
    return ShroudSystem.is_entity_revealed_to_local(parent)


## Player-issued destinations stay inside the visible order diamond (the
## visible outline inset by `BoundsSystem.ORDER_EDGE_INSET`). Applied after
## formation offsets and fallback relocation so a unit positioned near the
## boundary cannot leak its destination outside the inset margin.
func _bounded_player_target(world: Vector3) -> Vector3:
    return BoundsSystem.clamp_to_visible_diamond(world, BoundsSystem.ORDER_EDGE_INSET)


## Whether any selected local entity owns a RallyPointComponent, i.e. Alt+click
## can actually set a rally point. When false, Alt falls through to force-move.
func has_rally_receiver() -> bool:
    for ent in selected_entities:
        if not is_instance_valid(ent):
            continue
        if not _is_local_entity(ent):
            continue
        var parent := ent.get_parent() as Node3D
        if is_instance_valid(parent) and parent.get_node_or_null("RallyPointComponent"):
            return true
    return false


func request_set_rally_point(target_position: Vector3) -> void:
    var clamped := BoundsSystem.clamp_to_visible_diamond(
        target_position, BoundsSystem.ORDER_EDGE_INSET
    )
    var cell := CellUtil.world_to_cell(clamped)
    for ent in selected_entities:
        if not is_instance_valid(ent):
            continue
        if not _is_local_entity(ent):
            continue
        var parent := ent.get_parent() as Node3D
        if not is_instance_valid(parent):
            continue
        var rally := parent.get_node_or_null("RallyPointComponent") as RallyPointComponent
        if rally:
            rally.set_rally_point(cell)


func _find_sharer_cell(target_position: Vector3, level: int = 0) -> Vector2i:
    var target := CellUtil.world_to_cell(target_position)
    return CellUtil.spiral_first_free(
        target,
        4,
        func(cell: Vector2i) -> bool:
            if not BoundsSystem.is_in_order_area(cell):
                return true
            # A `level > 0` stand-off spot must sit on a live deck: without one
            # the level-aware A* has no `(cell, level)` surface to reach.
            if level > 0 and not SpatialHash.instance.has_bridge_on_cell(cell, level):
                return true
            if CellReservation.instance.is_cell_full(cell, level):
                return true
            # Cells reserved as vehicle destinations (or force-reserved own
            # cells of the selection) are no infantry stand-off spots.
            if SpatialHash.instance.get_reserved().has(CellUtil.cell_level_key(cell, level)):
                return true
            if SpatialHash.instance.is_cell_blocked(cell, level):
                return true
            return false
    )
