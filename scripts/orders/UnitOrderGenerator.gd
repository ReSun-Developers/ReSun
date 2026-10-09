class_name UnitOrderGenerator extends OrderGenerator

## Priority of the synthesized ground MOVE. Force-fire keeps only component
## orders that outrank it, so a component's own MOVE cannot displace the
## request_move()-based one with its formation, queue and target-level handling.
const GROUND_MOVE_PRIORITY: int = 5

static var _singleton: UnitOrderGenerator = null


static func get_instance() -> UnitOrderGenerator:
    if not _singleton:
        _singleton = UnitOrderGenerator.new()
    return _singleton


## One decision per input: the cursor and the orders come from the same branches,
## so a change to one cannot silently drift from the other. The cursor is the
## highest-priority order's cursor, or a selection affordance (SELECT / MOVE /
## GENERIC_BLOCKED / DEFAULT) when no order is produced.
func resolve(
    target: Node3D,
    target_cell: Vector2i,
    target_pos: Vector3,
    modifiers: Dictionary,
) -> OrderResolution:
    var sm := _get_selection_manager()
    if not sm:
        return OrderResolution.new()
    # An empty selection can only offer the SELECT affordance over an unselected
    # selectable entity — a decision previously re-derived in MouseHandler.
    if sm.selected_entities.is_empty():
        return OrderResolution.new(_select_affordance(target, sm), [])
    var locals := _local_selection(sm)
    if locals.is_empty():
        # Non-local (enemy) selections are viewing-only: no command cursor and no
        # orders. A selectable, not-yet-selected target still shows SELECT so the
        # player can click to re-select (TS ACTION_SELECT on a hovered selectable);
        # everything else is DEFAULT.
        return OrderResolution.new(_select_affordance(target, sm), [])

    var orders: Array[OrderResult] = []
    var target_level: int = int(modifiers.get(OrderResult.MOD_TARGET_LEVEL, 0))

    # ALT force-move: reposition regardless of the target, deliberately bypassing
    # every component targeter (attack/harvest/enter/deploy) so nothing can
    # outrank the move. Ctrl+Alt+Click is the original's Guard Area (unimplemented
    # here), so while both modifiers are held it falls back to force-move.
    if modifiers.get(OrderResult.MOD_FORCE_MOVE, false):
        if _has_movable(sm):
            var forced_move := _synthesized_move(
                sm, null, target_pos, modifiers, target_level, false
            )
            return OrderResolution.new(CursorState.Type.MOVE, [forced_move])
        return OrderResolution.new(_fallback_cursor(target, sm), [])

    if not target:
        if modifiers.get(OrderResult.MOD_FORCE_ATTACK, false):
            orders = _force_fire_attacks(locals, target_cell, target_pos, modifiers)
        if orders.is_empty():
            if _has_undeployable(sm):
                orders = OrderResolver.resolve_all(
                    locals, target, target_cell, target_pos, modifiers
                )
            elif _has_movable(sm):
                orders = [_synthesized_move(sm, null, target_pos, modifiers, target_level, false)]
    else:
        orders = OrderResolver.resolve_all(locals, target, target_cell, target_pos, modifiers)
        if orders.is_empty() and _is_already_selected(target, sm):
            if target.get_node_or_null("MovementController"):
                orders = [_synthesized_move(sm, target, target_pos, modifiers, target_level, true)]

    return OrderResolution.new(_resolve_cursor(orders, sm, target), orders)


## Force-fire ground resolution: let components answer for the cell instead of
## unconditionally synthesizing a move. Only orders above the plain movement
## priority are kept — a component's own MOVE would bypass formation, queued and
## target-level handling in request_move().
func _force_fire_attacks(
    locals: Array[SelectComponent],
    target_cell: Vector2i,
    target_pos: Vector3,
    modifiers: Dictionary,
) -> Array[OrderResult]:
    var attacks: Array[OrderResult] = []
    for order in OrderResolver.resolve_all(locals, null, target_cell, target_pos, modifiers):
        if order.priority > GROUND_MOVE_PRIORITY:
            attacks.append(order)
    return attacks


## The request_move()-based MOVE used for plain ground moves and re-clicks on an
## already-selected movable entity; it carries formation, queue and level handling
## that a component's own MOVE would bypass.
func _synthesized_move(
    sm: SelectionManager,
    target: Node3D,
    target_pos: Vector3,
    modifiers: Dictionary,
    target_level: int,
    as_entity: bool,
) -> OrderResult:
    var queued: bool = modifiers.get(OrderResult.MOD_QUEUED, false)
    var move_order := OrderResult.new(
        CursorState.Type.MOVE,
        GROUND_MOVE_PRIORITY,
        target,
        target_pos,
        queued,
        func() -> void: sm.request_move(target_pos, as_entity, target_level),
    )
    move_order.target_level = target_level
    return move_order


func _resolve_cursor(
    orders: Array[OrderResult], sm: SelectionManager, target: Node3D
) -> CursorState.Type:
    if not orders.is_empty():
        return _best_order(orders).cursor
    return _fallback_cursor(target, sm)


## Highest-priority order; ties keep the earlier order (matching resolve_single).
func _best_order(orders: Array[OrderResult]) -> OrderResult:
    var best: OrderResult = null
    for order in orders:
        if order == null:
            continue
        if best == null or order.priority > best.priority:
            best = order
    return best


## Cursor when no command was produced: SELECT over an unselected selectable
## entity, MOVE when the selection can be repositioned, GENERIC_BLOCKED over an
## already-selected immovable one, otherwise DEFAULT.
func _fallback_cursor(target: Node3D, sm: SelectionManager) -> CursorState.Type:
    if not target:
        if _has_undeployable(sm) or _has_movable(sm):
            return CursorState.Type.MOVE
        return CursorState.Type.DEFAULT
    if _is_already_selected(target, sm):
        return (
            CursorState.Type.MOVE
            if target.get_node_or_null("MovementController")
            else CursorState.Type.GENERIC_BLOCKED
        )
    if target.is_in_group("selectable"):
        return CursorState.Type.SELECT
    if _has_movable(sm) or _has_undeployable(sm):
        return CursorState.Type.MOVE
    return CursorState.Type.DEFAULT


func _select_affordance(target: Node3D, sm: SelectionManager) -> CursorState.Type:
    if target and target.is_in_group("selectable") and not _is_already_selected(target, sm):
        return CursorState.Type.SELECT
    return CursorState.Type.DEFAULT


## Selected entities owned by the local player (missing StatsComponent or
## player_id < 0 counts as local, matching `_is_local_entity`). Non-local (enemy)
## entities contribute no cursor or orders — selecting one is viewing only.
func _local_selection(sm: SelectionManager) -> Array[SelectComponent]:
    var locals: Array[SelectComponent] = []
    for sc in sm.selected_entities:
        if not is_instance_valid(sc):
            continue
        var entity := sc.get_parent() as Node3D
        if not is_instance_valid(entity):
            continue
        if _is_local_entity(entity):
            locals.append(sc)
    return locals


func _has_undeployable(sm: SelectionManager) -> bool:
    for sc in sm.selected_entities:
        if not is_instance_valid(sc):
            continue
        var entity := sc.get_parent() as Node3D
        if not is_instance_valid(entity):
            continue
        if not _is_local_entity(entity):
            continue
        var deploy := entity.get_node_or_null("DeployComponent") as DeployComponent
        if deploy and deploy.can_undeploy():
            return true
    return false


func _has_movable(sm: SelectionManager) -> bool:
    for sc in sm.selected_entities:
        if not is_instance_valid(sc):
            continue
        var entity := sc.get_parent() as Node3D
        if not is_instance_valid(entity):
            continue
        if not entity.get_node_or_null("MovementController"):
            continue
        if not _is_local_entity(entity):
            continue
        return true
    return false


func _is_local_entity(entity: Node3D) -> bool:
    return PlayerManager.is_entity_local(entity, PlayerManager.get_local_player_id())


func _is_already_selected(target: Node3D, sm: SelectionManager) -> bool:
    var target_sc := target.get_node_or_null("SelectComponent") as SelectComponent
    if not target_sc:
        return false
    return target_sc in sm.selected_entities


func _get_selection_manager() -> SelectionManager:
    return Engine.get_main_loop().root.get_node_or_null("SelectionManager") as SelectionManager
