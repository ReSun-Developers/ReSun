extends PanelContainer

## Hover tooltip for world entities (GH #272): black panel, green outline,
## uppercase monospace text. Consumes the existing SelectionManager hover
## signal — no additional per-frame raycasts. Appears after a short hover
## delay and hides immediately when hover clears.

const CURSOR_OFFSET := Vector2(16, 16)
const HOVER_DELAY := 0.5

var _selection_manager: SelectionManager = null
var _delay_timer: Timer = null
var _pending_label: String = ""
var _last_mouse_pos := Vector2.INF


func _ready():
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    visible = false
    _delay_timer = Timer.new()
    _delay_timer.one_shot = true
    _delay_timer.wait_time = HOVER_DELAY
    _delay_timer.timeout.connect(_on_delay_timeout)
    add_child(_delay_timer)
    _connect_to_selection_manager()


func _process(_delta: float):
    if UIUtil.is_mouse_over_sidebar() or UIUtil.is_mouse_over_debug_menu():
        _cancel_pending()
        visible = false
        return
    _restart_delay_if_cursor_moved()
    if not visible:
        return
    reset_size()
    _move_to_cursor()


func _connect_to_selection_manager():
    _selection_manager = SelectionManager
    if not _selection_manager.hover_changed.is_connected(_on_hover_changed):
        _selection_manager.hover_changed.connect(_on_hover_changed)


func _on_hover_changed(_entity: Node3D):
    _cancel_pending()
    var label := _resolve_current_label()
    if label.is_empty():
        visible = false
        return
    _pending_label = label
    _delay_timer.start()


func _on_delay_timeout():
    if _pending_label.is_empty():
        return
    _show(_pending_label)


func _show(label: String):
    _set_text(label)
    reset_size()
    _move_to_cursor()
    visible = true


func _cancel_pending():
    if _delay_timer:
        _delay_timer.stop()
    _pending_label = ""


func _restart_delay_if_cursor_moved():
    var vp := get_viewport()
    if vp == null:
        return
    var mouse_pos := vp.get_mouse_position()
    if mouse_pos == _last_mouse_pos:
        return
    _last_mouse_pos = mouse_pos
    if _delay_timer == null:
        return
    if visible:
        visible = false
        _pending_label = _resolve_current_label()
        if not _pending_label.is_empty():
            _delay_timer.start()
    elif not _pending_label.is_empty():
        _delay_timer.start()


func _resolve_current_label() -> String:
    var sm := _selection_manager
    if sm == null:
        return ""
    if not sm.hover_label_override.is_empty():
        return sm.hover_label_override
    if is_instance_valid(sm.hovered_node):
        return resolve_label(sm.hovered_node)
    return ""


func _move_to_cursor():
    var vp := get_viewport()
    if vp:
        position = vp.get_mouse_position() + CURSOR_OFFSET


func _set_text(label: String):
    var text_label := get_node_or_null("Label") as Label
    if text_label:
        text_label.text = label.to_upper()


## Resolve the tooltip label for a hovered entity: real display name for
## friendly/neutral/ownerless entities, type-only labels for enemies.
static func resolve_label(entity: Node3D) -> String:
    if not is_instance_valid(entity):
        return ""
    var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
    if not stats or stats.display_name.is_empty():
        return ""
    var local_id: int = PlayerManager.get_local_player_id()
    if stats.player_id == local_id or stats.player_id == -1:
        return stats.display_name
    if PlayerManager.is_enemy(local_id, stats.player_id):
        return _enemy_label(stats)
    return stats.display_name


static func _enemy_label(stats: StatsComponent) -> String:
    var etype: int = stats.entity_type
    if etype == EntityData.EntityType.INFANTRY:
        return "ENEMY INFANTRY"
    if etype == EntityData.EntityType.BUILDING:
        return "ENEMY STRUCTURE"
    if etype == EntityData.EntityType.AIRCRAFT and _is_airborne(stats):
        return "ENEMY AIRCRAFT"
    return "ENEMY UNIT"


static func _is_airborne(stats: StatsComponent) -> bool:
    var entity := stats.get_parent() as Node3D
    if not is_instance_valid(entity):
        return false
    var mc := entity.get_node_or_null("MovementController") as MovementController
    return mc != null and mc.is_airborne_jumpjet()
