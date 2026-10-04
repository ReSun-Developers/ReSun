extends Control
class_name MouseHandler

@export var camera_controller: CameraController
@export var raycast_distance: float = 500.0
var selection_manager: SelectionManager

@onready var selection_rect: ReferenceRect = $SelectionRect

var MOUSE_DRAG_THRESHOLD := 5.0

# Drag state — stored across _process() frames instead of event callbacks.
var mouse_dragging := false
var drag_start_position := Vector2.ZERO
var active_rect: Rect2
var _last_hover_pos := Vector2.INF
var _hover_miss_count := 0
var _skip_release := false
var _skip_input_frames := 0

# Cursor state
var _current_cursor: CursorState.Type = CursorState.Type.DEFAULT
var _hovered_entity: Node3D = null


func _ready():
    selection_rect.hide()
    selection_manager = SelectionManager

    # Debug logging for raycasting infrastructure
    if not camera_controller:
        printerr(
            (
                "[MouseHandler] WARNING: camera_controller export is null. "
                + "All mouse-based interactions (selection, movement) will fail silently."
            )
        )
    else:
        var cam3d = _get_camera_3d()
        if !cam3d:
            printerr("[MouseHandler] Camera3D not found under camera_controller path.")

    if selection_manager:
        print("SelectionManager found!")


## Pausing mid box-select swallows the mouse-release (input is gated by
## process_mode), which would otherwise leave a stuck drag state. Reset it,
## and force the system cursor while the pause menu is open. Unpausing arms a
## short input debounce so the resume-click's release does not pass through as
## a game click (the Input singleton records it regardless of GUI consumption).
func _notification(what: int) -> void:
    if what == NOTIFICATION_PAUSED:
        mouse_dragging = false
        _skip_release = false
        selection_rect.hide()
        active_rect = Rect2()
        _apply_cursor(CursorState.Type.DEFAULT)
    elif what == NOTIFICATION_UNPAUSED:
        _skip_input_frames = 2


## Applies the deploy (Ctrl+D) or stop (Ctrl+S) hotkey to the selection. Non-local
## (enemy) entities are skipped: hotkeys must never command an enemy (issue #166),
## matching the order funnel's ownership filter. Extracted for testability.
func apply_selection_hotkey(is_stop: bool) -> void:
    if not selection_manager:
        return
    var local_id := PlayerManager.get_local_player_id()
    var acted := false
    for sc in selection_manager.selected_entities:
        if not is_instance_valid(sc):
            continue
        var entity := sc.get_parent() as Node3D
        if not PlayerManager.is_entity_local(entity, local_id):
            continue
        var transport := entity.get_node_or_null("TransportComponent") as TransportComponent
        if not is_stop:
            var deploy := entity.get_node_or_null("DeployComponent") as DeployComponent
            if deploy and deploy.can_deploy():
                deploy.execute_deploy(entity)
                acted = true
            if transport:
                transport.execute_unload()
                acted = true
        else:
            var harvest := entity.get_node_or_null("HarvestComponent") as HarvestComponent
            if harvest:
                harvest.cancel_harvest(true)
                acted = true
            if transport:
                transport.cancel_unload()
                acted = true
            # Stop must also cancel an in-flight deploy/undeploy seek or rotation,
            # otherwise the unit stays locked in `is_transitioning()` forever.
            var deploy := entity.get_node_or_null("DeployComponent") as DeployComponent
            if deploy:
                deploy.cancel_deploy()
                acted = true
            var mc := entity.get_node_or_null("MovementController") as MovementController
            if mc:
                mc.stop()
                acted = true
            # Stop ends the engagement outright: a unit firing at a fixed point
            # (or a ground position) is IDLE, so mc.stop() is a no-op and never
            # emits movement_started. clear_target() reverts it to idle while
            # leaving GuardComponent free to acquire again.
            var combat := entity.get_node_or_null("CombatComponent") as CombatComponent
            if combat:
                combat.clear_target()
                acted = true
    if is_stop:
        selection_manager._pending_moves.clear()
        selection_manager._pending_index = 0
    # Deploy/stop are non-attack orders: acknowledge with the move voice, once
    # from the NW-most unit that can voice it (matching the order funnel).
    if acted:
        play_ack_voice(selection_manager, VoiceData.EVENT_MOVE)


# Poll input directly (like CameraController.gd) instead of using _input().
# This is required because Control nodes embedded under Node3D root don't receive
# _input() events without focus in Play Scene mode. The Input singleton polls OS-level state
# and works regardless of scene hierarchy or node focus chains.
func _process(_delta):
    if Engine.is_editor_hint():
        return

    if BuildingManager.is_build_mode:
        return
    if BuildingManager.exiting_build_mode:
        BuildingManager.exiting_build_mode = false
        mouse_dragging = false
        _skip_release = true
        return

    # Free-placement session owns the mouse while armed; the latch also covers
    # the commit frame — the mode is already disarmed when this poll runs, and
    # the same physical click must not additionally issue an order.
    if EntityPlacer.is_placing() or EntityPlacer.did_consume_click_this_frame():
        return

    # Deploy hotkey (Ctrl+D) or Stop hotkey (Ctrl+S) — above _skip_release so hotkeys always work.
    if Input.is_action_just_pressed("deploy") or Input.is_action_just_pressed("stop"):
        apply_selection_hotkey(Input.is_action_just_pressed("stop"))
        return

    # Skip input while the unpause debounce or a mode-exit release-suppression
    # is active. The resume click's release is still visible to the Input
    # singleton on the unpause frame; skipping a couple of frames stops it
    # being read as a gameplay click and issued as an order to the selection.
    var skip_debounce := _skip_input_frames > 0
    if skip_debounce:
        _skip_input_frames -= 1
    if skip_debounce or _skip_release:
        if _skip_release and Input.is_action_just_released("select_entity"):
            _skip_release = false
        return

    # Skip input handling when hovering UI — but still update cursor below.
    var hovered := get_viewport().gui_get_hovered_control()
    var over_sidebar := UIUtil.is_mouse_over_sidebar()
    var over_debug := hovered and UIUtil.is_inside_node(hovered, "DebugMenu")

    var over_build := hovered and UIUtil.is_inside_node(hovered, "Sidebar")

    # Gameplay minimap consumes its own clicks; polling world input must not
    # also select/order there.
    var over_minimap := UIUtil.is_mouse_over_minimap()

    # Drop stale hover state when the cursor enters UI, so returning to the
    # same target re-emits hover_changed (the tooltip would otherwise stay
    # hidden forever — set_hover_preview dedupes on the still-set entity).
    if (
        (over_sidebar or over_debug or over_build or over_minimap)
        and selection_manager
        and selection_manager.is_hovering
    ):
        selection_manager.clear_hover_preview()

    if not over_sidebar and not over_debug and not over_build and not over_minimap:
        var shift_pressed: bool = Input.is_key_pressed(KEY_SHIFT)

        # Left mouse button just pressed — start drag tracking.
        if Input.is_action_just_pressed("select_entity"):
            mouse_dragging = true
            drag_start_position = get_viewport().get_mouse_position()
            selection_rect.hide()
            selection_rect.position = drag_start_position
            selection_rect.size = Vector2.ZERO

        # Left mouse button just released — resolve as box-select or single click.
        if Input.is_action_just_released("select_entity"):
            var threshold_exceeded: bool = selection_rect.size.x >= MOUSE_DRAG_THRESHOLD

            if mouse_dragging and threshold_exceeded:
                if not shift_pressed and selection_manager:
                    selection_manager.deselect_all()
                if active_rect.has_area():
                    _select_entities_2d_projected(active_rect)
            elif selection_manager:
                var mouse_pos := get_viewport().get_mouse_position()
                _handle_single_click(mouse_pos, shift_pressed)

            mouse_dragging = false
            selection_rect.hide()

        # Right mouse button is RESERVED for deselect/cancel only — never issue commands.
        if Input.is_action_just_released("deselect_entity"):
            if OrderSystem.is_action_mode():
                OrderSystem.cancel()
            elif selection_manager:
                selection_manager.deselect_all()

        # ESC key — exit sell/repair mode.
        if Input.is_key_pressed(KEY_ESCAPE):
            if OrderSystem.is_action_mode():
                OrderSystem.cancel()

        # Update drag rectangle while left mouse held and moving (polling).
        if mouse_dragging:
            var m_end := get_viewport().get_mouse_position()
            var diff: Vector2 = m_end - drag_start_position
            active_rect = Rect2(drag_start_position, diff).abs()
            var over_threshold := (
                active_rect.size.x >= MOUSE_DRAG_THRESHOLD
                or active_rect.size.y >= MOUSE_DRAG_THRESHOLD
            )
            if over_threshold:
                selection_rect.show()
                selection_rect.position = active_rect.position
                selection_rect.size = active_rect.size

        # Hover preview during mouse motion (when not dragging).
        if not mouse_dragging:
            var mouse_pos := get_viewport().get_mouse_position()
            if mouse_pos.distance_to(_last_hover_pos) > 2.0:
                _last_hover_pos = mouse_pos
                _handle_hover_preview(mouse_pos)

    # Update cursor every frame — runs even when over sidebar or middle-clicking.
    _update_cursor()


func _get_camera_3d() -> Camera3D:
    if camera_controller and camera_controller.has_node("Camera3D"):
        return camera_controller.get_node("Camera3D") as Camera3D

    # Debug logging for diagnosis of missing camera in raycasting flow
    printerr(
        (
            "[MouseHandler] _get_camera_3d() returned null — "
            + (
                "camera_controller is not set. "
                if !camera_controller
                else "camera_controller has no 'Camera3D' child node. "
            )
        )
    )
    return null


## Handle left-click raycast for entity select.
func _handle_single_click(mouse_pos: Vector2, shift_pressed: bool):
    var camera := _get_camera_3d()
    if not camera or not camera.is_current():
        return

    # Alt + Left Click → set rally point on selected building
    if Input.is_key_pressed(KEY_ALT):
        var ground_pos := _get_ground_position_at_mouse()
        if ground_pos != Vector3.INF and selection_manager:
            selection_manager.request_set_rally_point(ground_pos)
    else:
        _handle_left_click_normal(camera, mouse_pos, shift_pressed)


func _handle_left_click_normal(camera: Camera3D, mouse_pos: Vector2, shift_pressed: bool) -> void:
    var from = camera.project_ray_origin(mouse_pos)
    var dir := camera.project_ray_normal(mouse_pos).normalized()
    var space_state = camera.get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.create(from, from + dir * raycast_distance)
    query.collide_with_areas = true

    var modifiers := build_modifiers(shift_pressed)

    # Pass 1: layer 16 — SelectComponent (units, buildings).
    query.collision_mask = 1 << 15
    var result := space_state.intersect_ray(query)
    if result.has("collider"):
        var collider := result.collider as Node
        var target := _find_entity_parent(collider)
        var target_cell := Vector2i.ZERO
        var target_pos := Vector3.ZERO
        if target:
            target_cell = CellUtil.world_to_cell(target.global_position)
            target_pos = target.global_position
        else:
            target_pos = _get_ground_position_at_mouse()
        # Check if entity is already selected
        var select_comp := _find_select_component(collider)
        var already_selected := (
            select_comp and selection_manager and selection_manager.is_entity_selected(select_comp)
        )
        # If already selected or no select component, try order system
        if already_selected or not select_comp:
            _try_execute_orders(target, target_cell, target_pos, modifiers)
            return
        # Unselected entity — try orders (attack/dock/harvest) before selecting;
        # only select when no order applies (enemy and friendly alike, so a
        # shift+click selects rather than queueing an attack). SelectionManager
        # clears cross-ownership mixes.
        if select_comp and selection_manager:
            if not shift_pressed:
                if _try_execute_orders(target, target_cell, target_pos, modifiers):
                    return
            selection_manager.select_entity(select_comp, shift_pressed)
        return

    # Pass 2: layer 17 — interact hitboxes (tiberium, dock).
    query.collision_mask = 1 << 16
    result = space_state.intersect_ray(query)
    if result.has("collider"):
        var collider := result.collider as Node
        var target := _find_entity_parent(collider)
        if target:
            var target_cell := CellUtil.world_to_cell(target.global_position)
            if _try_execute_orders(target, target_cell, target.global_position, modifiers):
                return

    # No entity — deselect and issue movement command.
    if selection_manager and not selection_manager.selected_entities.is_empty():
        var pick := _get_ground_position_at_mouse_leveled()
        if not pick.is_empty():
            # Carry the picked surface level so a move onto a bridge deck targets
            # the deck; ground picks stay at level 0.
            modifiers[OrderResult.MOD_TARGET_LEVEL] = int(pick["level"])
            var orders := OrderSystem.get_orders(
                null, Vector2i.ZERO, pick["position"] as Vector3, modifiers
            )
            play_order_voices(orders, selection_manager)
            for order in orders:
                order.execute.call()
            if not orders.is_empty():
                acknowledge_target_lines(selection_manager)


func _try_execute_orders(
    target: Node, target_cell: Vector2i, target_pos: Vector3, modifiers: Dictionary
) -> bool:
    var orders := OrderSystem.get_orders(target, target_cell, target_pos, modifiers)
    if orders.is_empty():
        return false
    play_order_voices(orders, selection_manager)
    for order in orders:
        order.execute.call()
    acknowledge_target_lines(selection_manager)
    return true


## Flashes the move/attack target line for the selection when the player issues
## an order. Called only from the player order paths (world click, minimap), so
## automatic moves and guard auto-acquisition never surface the line on their own.
static func acknowledge_target_lines(selection_manager: SelectionManager) -> void:
    if selection_manager == null:
        return
    for sc in selection_manager.selected_entities:
        if is_instance_valid(sc):
            sc.acknowledge_order()


## Shared order-confirmation voice playback, used by both the world click path
## and the minimap. One voice per order event, from the NW-most selected local
## unit that can actually voice the event — never one per unit (would stack on
## large selections). The voice event is chosen by the order-producing component
## and carried on the OrderResult.
static func play_order_voices(
    orders: Array[OrderResult], selection_manager: SelectionManager
) -> void:
    if orders.is_empty() or selection_manager == null:
        return
    var event := _voice_event_for_orders(orders)
    if event.is_empty():
        return
    play_ack_voice(selection_manager, event)


## Play one acknowledgment line of `event` from the selection: the NW-most local
## selected unit whose voice set has a variant for that event. A unit without a
## variant is skipped, so a mixed selection never lands on a speaker that would
## silently no-op. Used by the order funnel and the deploy/stop hotkeys.
static func play_ack_voice(selection_manager: SelectionManager, event: String) -> void:
    if selection_manager == null or event.is_empty():
        return
    var candidates: Array[SelectComponent] = []
    for sc in selection_manager.selected_entities:
        if not is_instance_valid(sc):
            continue
        var entity := sc.get_parent() as Node3D
        if not is_instance_valid(entity):
            continue
        if not selection_manager._is_local_entity_node(entity):
            continue
        var voice := entity.get_node_or_null("VoiceComponent") as VoiceComponent
        if not voice or not voice.voice_data or voice.voice_data.get_event(event).is_empty():
            continue
        candidates.append(sc)
    var chosen := selection_manager.get_northwest_most(candidates) as SelectComponent
    if not chosen:
        return
    var speaker := chosen.get_parent() as Node3D
    var speaker_voice := speaker.get_node_or_null("VoiceComponent") as VoiceComponent
    if not speaker_voice or not speaker_voice.voice_data:
        return
    AudioManager.play_voice(speaker_voice.voice_data.id, event)


## Voice event for an order batch: the event of the highest-priority resolved
## order (ties keep the earlier order), matching how the cursor is resolved — an
## attack in a mixed selection acknowledges with the attack voice, not whichever
## entity happened to be selected first.
static func _voice_event_for_orders(orders: Array[OrderResult]) -> String:
    var best: OrderResult = null
    for order in orders:
        if order == null:
            continue
        if best == null or order.priority > best.priority:
            best = order
    return best.voice_event if best else ""


## Shared click-modifier snapshot (Ctrl = force-attack, Alt = force-move,
## Shift = queue); used by the world click path and the minimap.
static func build_modifiers(shift_pressed: bool) -> Dictionary:
    return {
        OrderResult.MOD_FORCE_ATTACK: Input.is_key_pressed(KEY_CTRL),
        OrderResult.MOD_FORCE_MOVE: Input.is_key_pressed(KEY_ALT),
        OrderResult.MOD_QUEUED: shift_pressed,
    }


## Box-select: select entities whose projection falls inside the drag rectangle.
func _select_entities_2d_projected(rect: Rect2):
    var camera := _get_camera_3d()
    var newly_added: Array = []
    for entity in get_tree().get_nodes_in_group("drag_selectable"):
        var select_component := entity.get_node_or_null("SelectComponent") as SelectComponent
        if not select_component:
            continue

        # Skip enemy entities — only own units can be drag-selected
        var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
        var is_enemy := stats and stats.player_id >= 0
        is_enemy = is_enemy and stats.player_id != PlayerManager.get_local_player_id()
        if is_enemy:
            continue

        # Selectability gate BEFORE unproject (cheapest cell math first): same
        # predicate as the click path — visible bounds + shroud, so a shrouded
        # unit cannot slip in via box-select when the click path rejects it.
        if not selection_manager._is_entity_selectable(select_component):
            continue

        if rect.has_point(camera.unproject_position(select_component.global_position)):
            if not selection_manager.is_entity_selected(select_component):
                selection_manager.clear_incompatible_selection(select_component)
                selection_manager.add_entity(select_component)
                newly_added.append(select_component)
    # C&C: one select voice for the whole box event (NW-most unit), not one per unit.
    if not newly_added.is_empty():
        selection_manager.play_select_voice_for_entities(newly_added)


## Walk up the node tree to find a SelectComponent descendant.
func _find_select_component(node: Node) -> SelectComponent:
    while is_instance_valid(node):
        if node is SelectComponent:
            return node as SelectComponent
        node = node.get_parent()
    return null


## Fog gate for hover targeting: shrouded entities are skipped entirely.
func _is_fog_visible(target: Node3D) -> bool:
    return ShroudSystem.is_entity_revealed_to_local(target)


## True when the ground cell under the cursor is not revealed (shroud/fog).
func _is_hovering_shrouded() -> bool:
    if not ShroudSystem.is_shroud_enabled():
        return false
    var ground := _get_ground_position_at_mouse()
    if ground == Vector3.INF:
        return false
    return not ShroudSystem.is_cell_visible_to_local(CellUtil.world_to_cell(ground))


## Walk up the node tree to find the entity root (first Node3D parent with components).
func _find_entity_parent(node: Node) -> Node3D:
    while is_instance_valid(node):
        if (
            node is Node3D
            and (
                node.get_node_or_null("ResourceComponent")
                or node.get_node_or_null("DockHostComponent")
                or node.get_node_or_null("SelectComponent")
            )
        ):
            return node as Node3D
        node = node.get_parent()
    return null


## Handle hover preview by raycasting at entities under the cursor.
func _handle_hover_preview(mouse_pos: Vector2) -> void:
    var camera := _get_camera_3d()
    if not camera:
        return

    var from = camera.project_ray_origin(mouse_pos)
    var dir := camera.project_ray_normal(mouse_pos).normalized()

    var space_state = camera.get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.create(from, from + dir * raycast_distance)
    query.collide_with_areas = true

    # Pass 1: layer 16 — SelectComponent (units, buildings).
    query.collision_mask = 1 << 15
    var result = space_state.intersect_ray(query)

    if result.has("collider"):
        var collider := result.collider as Node
        var select_comp := _find_select_component(collider)
        var entity := _find_entity_parent(collider)
        if select_comp and entity and _is_fog_visible(entity):
            _hover_miss_count = 0
            selection_manager.set_hover_preview(true, select_comp)
            _hovered_entity = entity
            return

    # Pass 2: layer 17 — interact hitboxes (tiberium, dock).
    query.collision_mask = 1 << 16
    result = space_state.intersect_ray(query)

    if result.has("collider"):
        var collider := result.collider as Node
        var entity := _find_entity_parent(collider)
        if entity and _is_fog_visible(entity):
            _hover_miss_count = 0
            _hovered_entity = entity
            selection_manager.set_hover_node(entity)
            return

    _hover_miss_count += 1
    if _hover_miss_count > 3:
        _hover_miss_count = 0
        if _is_hovering_shrouded():
            selection_manager.set_hover_shroud()
        else:
            selection_manager.clear_hover_preview()
        _hovered_entity = null


## Return where the camera ray through mouse cursor intersects terrain surface (iterative solve).
func _get_ground_position_at_mouse() -> Vector3:
    var pick: Dictionary = _get_ground_position_at_mouse_leveled()
    if pick.is_empty():
        return Vector3.INF
    return pick["position"] as Vector3


## Level-resolved ground pick: the nearest surface under the cursor plus its cell
## and surface level (a bridge deck reports its level, the ground beneath reports
## 0). Returns an empty Dictionary when the ray misses or is out of range.
func _get_ground_position_at_mouse_leveled() -> Dictionary:
    var camera := _get_camera_3d()
    if not camera:
        return {}
    # Headless/tool contexts instantiate MouseHandler outside the tree; fall back
    # to the origin like the original single-return path did.
    var vp := get_viewport()
    var mouse_pos := Vector2.ZERO
    if vp:
        mouse_pos = vp.get_mouse_position()
    var candidates: Array[Dictionary] = TerrainSystem.mouse_ray_to_terrain_candidates(
        camera, mouse_pos
    )
    if candidates.is_empty():
        return {}
    var hit: Dictionary = candidates[0]
    var hit_pos := hit["position"] as Vector3
    var dist_sq: float = camera.project_ray_origin(mouse_pos).distance_squared_to(hit_pos)
    if 0.0 < dist_sq and dist_sq <= raycast_distance * raycast_distance:
        return {"position": hit_pos, "level": int(hit["level"]), "cell": hit["cell"]}
    return {}


func _update_cursor() -> void:
    var cursor_type: CursorState.Type

    # Sidebar hover always shows system cursor
    if UIUtil.is_mouse_over_sidebar():
        cursor_type = CursorState.Type.DEFAULT
    # Debug menu hover always shows system cursor
    elif UIUtil.is_mouse_over_debug_menu():
        cursor_type = CursorState.Type.DEFAULT
    # Minimap hover always shows system cursor
    elif UIUtil.is_mouse_over_minimap():
        cursor_type = CursorState.Type.DEFAULT
    elif mouse_dragging and active_rect.size.x >= MOUSE_DRAG_THRESHOLD:
        cursor_type = CursorState.Type.SELECT
    else:
        # Middle-click panning — joystick cursor
        var joystick := _resolve_joystick_cursor()
        if joystick != CursorState.Type.DEFAULT:
            cursor_type = joystick
        # Edge scroll cursor
        var scroll := _resolve_scroll_cursor()
        if scroll != CursorState.Type.DEFAULT:
            cursor_type = scroll
        else:
            # Delegate to OrderSystem for cursor resolution
            var target := _hovered_entity
            var target_cell := Vector2i.ZERO
            var target_pos := Vector3.ZERO
            if is_instance_valid(target):
                target_cell = CellUtil.world_to_cell(target.global_position)
                target_pos = target.global_position
            else:
                target = null
                target_pos = _get_ground_position_at_mouse()
            var modifiers := build_modifiers(false)
            var order_cursor := OrderSystem.get_cursor(target, target_cell, target_pos, modifiers)
            # OpenRA pattern: SELECT only when selection is empty + hovering selectable entity
            var no_selection := selection_manager.selected_entities.is_empty()
            if order_cursor == CursorState.Type.DEFAULT and no_selection:
                if target and target.is_in_group("selectable"):
                    cursor_type = CursorState.Type.SELECT
                else:
                    cursor_type = CursorState.Type.DEFAULT
            else:
                cursor_type = order_cursor

    _apply_cursor(cursor_type)


func _resolve_scroll_cursor() -> CursorState.Type:
    if not InputSettings.edge_scroll_enabled:
        return CursorState.Type.DEFAULT

    var mouse_pos := get_viewport().get_mouse_position()
    var viewport_size := get_viewport().get_visible_rect().size
    var margin := 20.0

    var dx := 0
    var dy := 0

    if mouse_pos.x < margin:
        dx = -1
    elif mouse_pos.x > viewport_size.x - margin:
        dx = 1

    if mouse_pos.y < margin:
        dy = -1
    elif mouse_pos.y > viewport_size.y - margin:
        dy = 1

    if dx == 0 and dy == 0:
        return CursorState.Type.DEFAULT

    var direction := Vector2i(dx, dy)
    var blocked := _is_scroll_blocked(direction)

    var cursor_map := {
        Vector2i(0, -1): [CursorState.Type.SCROLL_T, CursorState.Type.SCROLL_T_BLOCKED],
        Vector2i(1, -1): [CursorState.Type.SCROLL_TR, CursorState.Type.SCROLL_TR_BLOCKED],
        Vector2i(1, 0): [CursorState.Type.SCROLL_R, CursorState.Type.SCROLL_R_BLOCKED],
        Vector2i(1, 1): [CursorState.Type.SCROLL_BR, CursorState.Type.SCROLL_BR_BLOCKED],
        Vector2i(0, 1): [CursorState.Type.SCROLL_B, CursorState.Type.SCROLL_B_BLOCKED],
        Vector2i(-1, 1): [CursorState.Type.SCROLL_BL, CursorState.Type.SCROLL_BL_BLOCKED],
        Vector2i(-1, 0): [CursorState.Type.SCROLL_L, CursorState.Type.SCROLL_L_BLOCKED],
        Vector2i(-1, -1): [CursorState.Type.SCROLL_TL, CursorState.Type.SCROLL_TL_BLOCKED],
    }

    var default_pair: Array = [CursorState.Type.DEFAULT, CursorState.Type.DEFAULT]
    var pair: Array = cursor_map.get(direction, default_pair)
    return pair[1] if blocked else pair[0]


func _is_scroll_blocked(direction: Vector2i) -> bool:
    if not camera_controller:
        return true
    var bounds_rect := BoundsSystem.get_bounds_rect()
    var cam_pos := camera_controller.global_position

    var rotated_pos := cam_pos.rotated(Vector3(0, 1, 0), -deg_to_rad(45))
    var half_width := bounds_rect.size.x / 2.0
    var half_height := bounds_rect.size.y / 2.0

    if direction.x == -1 and rotated_pos.x <= -half_width + 1.0:
        return true
    if direction.x == 1 and rotated_pos.x >= half_width - 1.0:
        return true
    if direction.y == -1 and rotated_pos.z <= -half_height + 1.0:
        return true
    if direction.y == 1 and rotated_pos.z >= half_height - 1.0:
        return true

    return false


func _resolve_joystick_cursor() -> CursorState.Type:
    if not camera_controller or not camera_controller.is_panning:
        return CursorState.Type.DEFAULT

    var mouse_pos := get_viewport().get_mouse_position()
    var click_pos: Vector2 = camera_controller.fixed_toggle_point
    var diff := mouse_pos - click_pos

    # Within 20px of click point — center (no pan direction yet)
    if diff.length() < 20.0:
        return CursorState.Type.JOYSTICK_CENTER

    # Map angle to 8 directions
    var angle := diff.angle()  # 0 = right, PI/2 = down, PI = left, -PI/2 = up
    var sector := wrapi(floori((angle + PI) / (PI / 4.0)), 0, 7)

    var direction_map := {
        0: Vector2i(-1, 0),  # left
        1: Vector2i(-1, -1),  # up-left
        2: Vector2i(0, -1),  # up
        3: Vector2i(1, -1),  # up-right
        4: Vector2i(1, 0),  # right
        5: Vector2i(1, 1),  # down-right
        6: Vector2i(0, 1),  # down
        7: Vector2i(-1, 1),  # down-left
    }

    var direction: Vector2i = direction_map.get(sector, Vector2i.ZERO)
    var blocked := _is_scroll_blocked(direction)

    var cursor_map := {
        Vector2i(0, -1): [CursorState.Type.JOYSTICK_T, CursorState.Type.JOYSTICK_T_BLOCKED],
        Vector2i(1, -1): [CursorState.Type.JOYSTICK_TR, CursorState.Type.JOYSTICK_TR_BLOCKED],
        Vector2i(1, 0): [CursorState.Type.JOYSTICK_R, CursorState.Type.JOYSTICK_R_BLOCKED],
        Vector2i(1, 1): [CursorState.Type.JOYSTICK_BR, CursorState.Type.JOYSTICK_BR_BLOCKED],
        Vector2i(0, 1): [CursorState.Type.JOYSTICK_B, CursorState.Type.JOYSTICK_B_BLOCKED],
        Vector2i(-1, 1): [CursorState.Type.JOYSTICK_BL, CursorState.Type.JOYSTICK_BL_BLOCKED],
        Vector2i(-1, 0): [CursorState.Type.JOYSTICK_L, CursorState.Type.JOYSTICK_L_BLOCKED],
        Vector2i(-1, -1): [CursorState.Type.JOYSTICK_TL, CursorState.Type.JOYSTICK_TL_BLOCKED],
    }

    var default_pair: Array = [
        CursorState.Type.JOYSTICK_CENTER,
        CursorState.Type.JOYSTICK_CENTER,
    ]
    var pair: Array = cursor_map.get(direction, default_pair)
    return pair[1] if blocked else pair[0]


func _apply_cursor(type: CursorState.Type) -> void:
    if type == _current_cursor:
        return
    _current_cursor = type

    if type == CursorState.Type.DEFAULT:
        Input.set_custom_mouse_cursor(null)
        return

    var texture := CursorState.get_texture(type)
    var hotspot := CursorState.get_hotspot(type)
    Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, hotspot)
