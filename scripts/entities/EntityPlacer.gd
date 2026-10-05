extends Node

## Centralized entity placement system. Handles creating, positioning, and
## adding entities to the scene. Manages inert preview entities for placement
## mode (frozen, non-interactive, transparent until finalized).

signal entity_placed(entity: Node3D, entity_data: EntityData)
## Emitted when the free-placement mode arms or disarms (enter/exit/start/
## commit/cancel), so UI can refresh what it shows without holding the flag.
signal placing_mode_changed(active: bool)

var _preview: Node3D = null
var _preview_data: EntityData = null
var _preview_original_layers: Dictionary = {}
var _preview_original_surface_overrides: Dictionary = {}
## Free-placement mode truth (glossary: "placing" — pick entity → ghost
## preview → place or cancel, no validity checks, unlike build mode).
var _placing_mode: bool = false
## Process-frame stamp of the last consumed commit click, so MouseHandler
## (which polls raw Input state that ignores event consumption) can skip the
## same physical click when routing orders.
var _consumed_click_frame: int = -1
## Frames to ignore commit/cancel polls after arming: the Input singleton
## records the arming cameo click even though GUI consumes it, so an
## unguarded poll would place at the cameo's screen point (BuildingManager
## keeps the same counter for the same reason).
var _skip_input_frames: int = 0


func place_entity(
    entity_data: EntityData, world_pos: Vector3, player_id: int, parent: Node3D = null
) -> Node3D:
    var entity := EntityFactory.create_entity(entity_data.id)
    if not entity:
        return null
    var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
    if stats:
        stats.player_id = player_id
    entity.position = world_pos
    var target: Node = parent if parent else World.spawn_container(World.Bucket.ENTITIES)
    if target == null:
        push_error("EntityPlacer: no scene root to place %s" % entity_data.id)
        entity.free()
        return null
    target.add_child(entity)
    var rules := GlobalRules.get_current()
    var lm: Locomotor = rules.get_locomotor(entity_data.locomotor) if rules else null
    if lm and lm.shares_cell:
        var mc := entity.get_node_or_null("MovementController") as MovementController
        if mc:
            var cell := CellUtil.world_to_cell(world_pos)
            mc._assign_sub_slot_at_cell(cell)
            if mc._has_sub_slot:
                entity.global_position = mc._sub_slot_position
    entity_placed.emit(entity, entity_data)
    return entity


# --- Preview system ---


func start_preview(entity_data: EntityData) -> void:
    cancel_preview()
    var entity := EntityFactory.create_entity(entity_data.id)
    if not entity:
        return
    # Make inert: remove from all groups, disable processing, disable collision
    _remove_preview_groups(entity)
    entity.process_mode = Node.PROCESS_MODE_DISABLED
    _store_and_disable_collision(entity)
    # Visual
    _set_node_transparency(entity, 0.33)
    var host: Node = World.spawn_container(World.Bucket.ENTITIES)
    if host == null:
        push_error("EntityPlacer: no scene root for preview of %s" % entity_data.id)
        entity.free()
        exit_placing_mode()
        return
    host.add_child(entity)
    _preview = entity
    _preview_data = entity_data


func update_preview_position(world_pos: Vector3) -> void:
    if is_instance_valid(_preview):
        _preview.position = world_pos


func finalize_preview(player_id: int) -> Node3D:
    if not is_instance_valid(_preview) or not _preview_data:
        return null
    # Restore: groups, processing, collision, transparency
    _add_preview_groups(_preview, _preview_data)
    _preview.process_mode = Node.PROCESS_MODE_INHERIT
    _restore_collision(_preview)
    _clear_preview_materials(_preview)
    # Set player
    var stats := _preview.get_node_or_null("StatsComponent") as StatsComponent
    if stats:
        stats.player_id = player_id
    # Emit signal
    var entity := _preview
    var data := _preview_data
    _preview = null
    _preview_data = null
    _preview_original_layers.clear()
    _preview_original_surface_overrides.clear()
    entity_placed.emit(entity, data)
    return entity


func cancel_preview() -> void:
    if is_instance_valid(_preview):
        _preview.queue_free()
    _preview = null
    _preview_data = null
    _preview_original_layers.clear()
    _preview_original_surface_overrides.clear()


func has_preview() -> bool:
    return is_instance_valid(_preview)


# --- Placing session (free placement) ---


## Arm the free-placement mode without a preview yet (grid shows all entities,
## cameo clicks start placement). No skip-frame counters: the arming cameo
## click is consumed as GUI input upstream and never reaches _unhandled_input.
func enter_placing_mode() -> void:
    if _placing_mode:
        return
    _placing_mode = true
    placing_mode_changed.emit(true)


## Disarm the mode and drop any live preview. The single exit path for the
## session (toggle-off, commit, cancel, scene-change reset all route here).
## Clears the commit latch first so a session teardown never leaves a stale
## "consumed click" claim behind; the commit path re-arms the latch AFTER this
## returns.
func exit_placing_mode() -> void:
    _consumed_click_frame = -1
    _skip_input_frames = 0
    if not _placing_mode and not has_preview():
        return
    _placing_mode = false
    cancel_preview()
    placing_mode_changed.emit(false)


## Start placing a specific entity: arms the mode and shows the ghost preview.
func start_placing(data: EntityData) -> void:
    enter_placing_mode()
    _skip_input_frames = 1
    start_preview(data)


## Direct deploy fallback (debug-menu spec): when the "No prerequisites" cheat
## is on and no factory exists for the queue type, the cameo click places the
## entity via this named session entry instead of starting production. Named
## separately from the place-anywhere start path so both stay observable.
func start_direct_deploy(data: EntityData) -> void:
    start_placing(data)


func is_placing() -> bool:
    return _placing_mode


## True on the same frame a commit click was consumed here. MouseHandler polls
## raw Input state that ignores set_input_as_handled, so it checks this latch
## before resolving orders — otherwise the commit click would also fire a unit
## order on the freshly placed entity (mode is already disarmed by then).
func did_consume_click_this_frame() -> bool:
    return _consumed_click_frame == Engine.get_process_frames()


func _unhandled_input(event: InputEvent) -> void:
    if not is_placing() or not has_preview():
        return
    if event.is_action_pressed("select_entity"):
        _commit_placement()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("deselect_entity") or event.is_action_pressed("ui_cancel"):
        exit_placing_mode()
        get_viewport().set_input_as_handled()


## Dispatch a commit click by entity type: buildings route through
## BuildingManager's grid machinery, everything else finalizes the ghost.
func _commit_placement() -> void:
    var data := _preview_data
    if data and data.entity_type == EntityData.EntityType.BUILDING:
        var hit: Variant = _ground_hit()
        if hit != null:
            _commit_building(data, hit as Vector3)
        return
    finalize_preview(PlayerManager.get_local_player_id())
    exit_placing_mode()
    _consumed_click_frame = Engine.get_process_frames()


## Place a building at the snapped origin cell via BuildingManager (foundation
## reservation, terrain leveling, registry — everything the raw ghost finalize
## skips). With the place-anywhere cheat armed, can_place passes bounds-only,
## so the session acts as free placement; a refused placement (no cheat,
## invalid spot) keeps the session armed for a retry.
func _commit_building(data: EntityData, ground_pos: Vector3) -> void:
    var origin := building_origin_for(data, ground_pos)
    if not BuildingManager.place_building(data, origin):
        return
    exit_placing_mode()
    _consumed_click_frame = Engine.get_process_frames()


## Foundation-snapped origin cell for a building ghost at the given ground
## point (mouse cell minus half the footprint) — same math as _try_place_building.
func building_origin_for(data: EntityData, ground_pos: Vector3) -> Vector2i:
    var mouse_cell := CellUtil.world_to_cell(ground_pos)
    return mouse_cell - Vector2i(data.foundation.x >> 1, data.foundation.y >> 1)


## Camera ray → terrain hit, shared by preview repositioning and commit.
func _ground_hit() -> Variant:
    var cam := _get_camera_3d()
    if not cam:
        return null
    return TerrainSystem.mouse_ray_to_terrain(cam, get_viewport().get_mouse_position())


func _process(_delta: float) -> void:
    if not is_placing() or not has_preview():
        return
    if _skip_input_frames > 0:
        _skip_input_frames -= 1
        _reposition_preview()
        return
    # Poll-based input: mouse events do not reliably reach _unhandled_input at
    # runtime (the same reason MouseHandler and BuildingManager poll theirs);
    # the _unhandled_input branches above stay as keyboard/test fallback.
    if Input.is_action_just_pressed("deselect_entity") or Input.is_action_just_pressed("ui_cancel"):
        exit_placing_mode()
        return
    if Input.is_action_just_pressed("select_entity"):
        # The gameplay minimap owns its own clicks; do not commit through it.
        if not UIUtil.is_mouse_over_minimap():
            _commit_placement()
        return
    _reposition_preview()


## Camera ray → terrain hit → ghost position (buildings snap to the foundation
## grid, everything else tracks the terrain surface).
func _reposition_preview() -> void:
    var hit: Variant = _ground_hit()
    if hit == null:
        return
    var pos := hit as Vector3
    if _preview_data and _preview_data.entity_type == EntityData.EntityType.BUILDING:
        var origin := building_origin_for(_preview_data, pos)
        pos = CellUtil.cell_origin_to_world(origin, _preview_data.foundation)
        pos.y = CellUtil.get_max_height(
            origin,
            _preview_data.foundation,
            func(c: Vector2i) -> float: return TerrainSystem.get_cell_max_height(c)
        )
    update_preview_position(pos)


func _get_camera_3d() -> Camera3D:
    # The gameplay camera is the root viewport's current camera. The map is
    # nested under MainScene/Gameplay/World, so it is not `current_scene`.
    var camera := get_viewport().get_camera_3d()
    if camera:
        return camera
    # Fallback when no camera is current (e.g. a standalone map scene): search
    # the scene recursively rather than assuming a fixed child path.
    var root := get_tree().current_scene
    if not root:
        return null
    return root.find_child("Camera3D", true, false) as Camera3D


# --- Group management ---


func _remove_preview_groups(entity: Node3D) -> void:
    for group in entity.get_groups():
        entity.remove_from_group(group)


func _add_preview_groups(entity: Node3D, data: EntityData) -> void:
    var etype := data.entity_type
    if etype != EntityData.EntityType.OVERLAY:
        if etype != EntityData.EntityType.TERRAIN or data.foundation != Vector2i(1, 1):
            entity.add_to_group("entities")
    var is_unit := StatsComponent.is_unit_type(etype)
    if is_unit:
        entity.add_to_group("selectable")
        entity.add_to_group("drag_selectable")
    elif etype == EntityData.EntityType.BUILDING:
        entity.add_to_group("selectable")
    if data.resource_category != "":
        entity.add_to_group("resources")
    if data.resource_spawner:
        entity.add_to_group("resource_trees")


# --- Collision management ---


func _store_and_disable_collision(node: Node) -> void:
    if node is CollisionObject3D:
        var co := node as CollisionObject3D
        _preview_original_layers[node] = [co.collision_layer, co.collision_mask]
        co.collision_layer = 0
        co.collision_mask = 0
    if node is MeshInstance3D:
        var overrides: Array[Material] = []
        for i in node.get_surface_override_material_count():
            overrides.append(node.get_surface_override_material(i))
        _preview_original_surface_overrides[node] = overrides
    for child in node.get_children():
        _store_and_disable_collision(child)


func _restore_collision(node: Node) -> void:
    if node is CollisionObject3D and _preview_original_layers.has(node):
        var layers: Array = _preview_original_layers[node]
        var co := node as CollisionObject3D
        co.collision_layer = layers[0]
        co.collision_mask = layers[1]
    for child in node.get_children():
        _restore_collision(child)


func _clear_preview_materials(node: Node) -> void:
    if node is MeshInstance3D:
        var mi := node as MeshInstance3D
        mi.material_override = null
        if _preview_original_surface_overrides.has(node):
            var overrides: Array = _preview_original_surface_overrides[node]
            for i in mi.get_surface_override_material_count():
                if i < overrides.size():
                    mi.set_surface_override_material(i, overrides[i])
                else:
                    mi.set_surface_override_material(i, null)
        else:
            for i in mi.get_surface_override_material_count():
                mi.set_surface_override_material(i, null)
    for child in node.get_children():
        _clear_preview_materials(child)


# --- Transparency ---


func _set_node_transparency(node: Node, alpha: float) -> void:
    if node is MeshInstance3D:
        var mat := StandardMaterial3D.new()
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.albedo_color = Color(0.5, 0.5, 0.5, alpha)
        (node as MeshInstance3D).material_override = mat
    for child in node.get_children():
        _set_node_transparency(child, alpha)
