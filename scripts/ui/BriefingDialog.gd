extends Control

## Briefing dialog — shows the active mission's display name and briefing text.
## Two entry points share one scene: auto-shown before a mission (the game stays
## paused until it is closed) and re-opened from the pause menu. process_mode
## ALWAYS keeps it interactive while the tree is paused.
##
## The dialog records its origin so closing knows whether to unpause: closing a
## pre-mission briefing unpauses, closing a pause-menu briefing returns to the
## still-paused pause menu.

var _from_pause: bool = false

@onready var title_label: Label = %TitleLabel
@onready var body_label: Label = %BodyLabel
@onready var close_button: Button = %CloseButton


func _ready() -> void:
    close_button.pressed.connect(_on_close_pressed)
    var pause_menu := _find_pause_menu()
    if pause_menu:
        pause_menu.connect("briefing_requested", _on_briefing_requested)
    GameContext.mission_started.connect(_on_mission_started)
    _maybe_auto_show()


## A detached dialog (its HUD surface was released, e.g. when a match is
## replaced) must stop reacting to global signals — otherwise it runs
## out-of-tree, where `get_tree()` is null.
func _exit_tree() -> void:
    if GameContext.mission_started.is_connected(_on_mission_started):
        GameContext.mission_started.disconnect(_on_mission_started)


## ESC closes the briefing while it is open. The event is consumed here so the
## pause menu's _unhandled_input cannot toggle pause underneath the dialog.
func _input(event: InputEvent) -> void:
    if not visible:
        return
    if event.is_action_pressed("pause"):
        _on_close_pressed()
        get_viewport().set_input_as_handled()


## Shows the briefing for `mission`. `from_pause` records the entry point so
## closing knows whether to unpause. No-ops when `mission` is null.
func show_for_mission(mission: Mission, from_pause: bool) -> void:
    if mission == null or not is_inside_tree():
        return
    _from_pause = from_pause
    title_label.text = mission.display_name
    body_label.text = mission.briefing
    visible = true
    get_tree().paused = true


func _on_close_pressed() -> void:
    visible = false
    if not _from_pause:
        get_tree().paused = false


func _on_briefing_requested() -> void:
    show_for_mission(GameContext.current_mission, true)


func _on_mission_started(_mission: Mission) -> void:
    _maybe_auto_show()


func _maybe_auto_show() -> void:
    var mission := GameContext.current_mission
    if mission != null and mission.show_briefing:
        show_for_mission(mission, false)


## The pause menu that owns this briefing, found as a parent or sibling so the
## dialog works whether it is nested under the map HUD or placed beside it.
## Detected by the `briefing_requested` signal, so no hard script dependency.
func _find_pause_menu() -> Control:
    var node := get_parent()
    while node != null:
        if node.has_signal("briefing_requested"):
            return node as Control
        for sibling in node.get_children():
            if sibling != self and sibling.has_signal("briefing_requested"):
                return sibling as Control
        node = node.get_parent()
    return null
