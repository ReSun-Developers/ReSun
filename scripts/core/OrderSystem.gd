extends Node

## Emitted after set_generator() installs a generator and after cancel()
## resets to the unit generator, so UI (e.g. Sidebar buttons) can sync its
## visual state from the signal instead of being told imperatively.
signal generator_changed

var active_generator: OrderGenerator = UnitOrderGenerator.get_instance()


## The single decision for one player input: apply the bounds/fog/shroud gates,
## then let the active generator resolve cursor and orders together.
func resolve(
    target: Node3D,
    target_cell: Vector2i,
    target_pos: Vector3,
    modifiers: Dictionary,
) -> OrderResolution:
    var bounds := _order_bounds(target, target_cell, target_pos)
    if bounds.blocked:
        return OrderResolution.new(CursorState.Type.GENERIC_BLOCKED, [])
    var effective := _fog_filter_target(target, target_cell, modifiers)
    var ground_modifiers := _ground_shroud_gate(effective.target, target_pos, effective.modifiers)
    return active_generator.resolve(
        effective.target, effective.target_cell, bounds.pos, ground_modifiers
    )


func get_cursor(
    target: Node3D,
    target_cell: Vector2i,
    target_pos: Vector3,
    modifiers: Dictionary,
) -> CursorState.Type:
    return resolve(target, target_cell, target_pos, modifiers).cursor


func get_orders(
    target: Node3D,
    target_cell: Vector2i,
    target_pos: Vector3,
    modifiers: Dictionary,
) -> Array[OrderResult]:
    return resolve(target, target_cell, target_pos, modifiers).orders


## Dispatch a resolved order batch: one confirmation voice, execute every order,
## then acknowledge the selection's target lines. Returns whether anything ran.
## The single owner of the voice/execute/acknowledge tail so the world-click,
## ground and minimap paths cannot drift apart.
func issue(orders: Array[OrderResult]) -> bool:
    if orders.is_empty():
        return false
    play_order_voices(orders, SelectionManager)
    for order in orders:
        order.execute.call()
    acknowledge_target_lines(SelectionManager)
    return true


## Bounds gate — the single decision point for order targets (callers must not
## branch on `target` nullness themselves). A player-initiated order whose
## entity target sits outside the visible (inset) playable diamond is rejected
## outright — never turned into a move. Ground orders (null target) fall
## through to the move path with their position clamped to the visible edge.
## Callers pass a real entity cell (MouseHandler resolves it from the raycast
## hit). Runs before the fog gate: a rejected out-of-bounds target stays
## BLOCKED even when shrouded.
func _order_bounds(target: Node3D, target_cell: Vector2i, target_pos: Vector3) -> Dictionary:
    if target != null:
        return {"blocked": not BoundsSystem.is_in_order_area(target_cell), "pos": target_pos}
    return {
        "blocked": false,
        "pos": BoundsSystem.clamp_to_visible_diamond(target_pos, BoundsSystem.ORDER_EDGE_INSET),
    }


## Fog gate: when fog of war is enabled, a target whose cell is not visible to
## the local player behaves as absent — it falls through to the move path and
## cannot be attacked (including force-fire). Buildings use their foundation
## footprint: any explored foundation cell keeps them targetable.
func _fog_filter_target(target: Node3D, target_cell: Vector2i, modifiers: Dictionary) -> Dictionary:
    if target == null:
        return {"target": null, "target_cell": target_cell, "modifiers": modifiers}
    var stats := target.get_node_or_null("StatsComponent") as StatsComponent
    var revealed: bool
    if stats != null and stats.entity_type == EntityData.EntityType.BUILDING:
        revealed = ShroudSystem.is_entity_revealed_to_local(target)
    else:
        var cell := target_cell
        if cell == Vector2i.ZERO:
            cell = CellUtil.world_to_cell(target.global_position)
        revealed = ShroudSystem.is_cell_visible_to_local(cell)
    if revealed:
        return {"target": target, "target_cell": target_cell, "modifiers": modifiers}
    var filtered := modifiers.duplicate()
    filtered.erase(OrderResult.MOD_FORCE_ATTACK)
    return {"target": null, "target_cell": target_cell, "modifiers": filtered}


## Shroud gate for force-fire ground orders. Fog (explored but not currently
## visible) does NOT block firing at terrain — only shroud (never explored) does,
## degrading the order to a plain move the way the original's MoveToShroud key
## does. Deliberately keyed on the shroud cover alone, not on
## GlobalRules.fog_of_war, and applied only while the modifier is held so plain
## ground orders are untouched.
func _ground_shroud_gate(target: Node3D, ground_pos: Vector3, modifiers: Dictionary) -> Dictionary:
    if target != null:
        return modifiers
    if not modifiers.get(OrderResult.MOD_FORCE_ATTACK, false):
        return modifiers
    if not ShroudSystem.is_shroud_enabled() or not ShroudSystem.is_grid_ready():
        return modifiers
    var cell := CellUtil.world_to_cell(ground_pos)
    if ShroudSystem.is_explored(PlayerManager.get_local_player_id(), cell):
        return modifiers
    var filtered := modifiers.duplicate()
    filtered.erase(OrderResult.MOD_FORCE_ATTACK)
    return filtered


## Sell/repair mode is derived from the active generator's type — no parallel
## booleans anywhere. is_action_mode() is the generic "not unit orders" query
## for gameplay guards (MouseHandler order routing, PauseMenu ESC handling),
## which must read these instead of any UI script's mode state.
func is_sell_mode() -> bool:
    return active_generator is SellOrderGenerator


func is_repair_mode() -> bool:
    return active_generator is RepairOrderGenerator


func is_action_mode() -> bool:
    return not active_generator is UnitOrderGenerator


func set_generator(gen: OrderGenerator) -> void:
    active_generator = gen
    generator_changed.emit()


func cancel() -> void:
    active_generator.cancel()
    active_generator = UnitOrderGenerator.get_instance()
    generator_changed.emit()


## Shared click-modifier snapshot (Ctrl = force-attack, Alt = force-move,
## Shift = queue); used by the world click path and the minimap.
static func build_modifiers(shift_pressed: bool) -> Dictionary:
    return {
        OrderResult.MOD_FORCE_ATTACK: Input.is_key_pressed(KEY_CTRL),
        OrderResult.MOD_FORCE_MOVE: Input.is_key_pressed(KEY_ALT),
        OrderResult.MOD_QUEUED: shift_pressed,
    }


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
