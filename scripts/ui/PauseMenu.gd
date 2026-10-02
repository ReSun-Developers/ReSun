extends Control

# Pause menu — ESC toggles a global pause; the menu stays interactive while
# the rest of the tree is paused (process_mode = ALWAYS).

## Emitted when the player requests the mission briefing. MapBase01's briefing
## dialog connects to this; the pause menu never talks to the dialog directly.
signal briefing_requested

@onready var resume_button: Button = %ResumeButton
@onready var briefing_button: Button = %BriefingButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
    resume_button.pressed.connect(_on_resume_pressed)
    briefing_button.pressed.connect(_on_briefing_pressed)
    quit_button.pressed.connect(_on_quit_pressed)
    _update_briefing_button()


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("pause"):
        if _esc_busy():
            return
        _toggle_pause()
        get_viewport().set_input_as_handled()


## First ESC press belongs to active cancel-modes (build/sell/repair/debug-place),
## not to the pause menu — mirrors C&C where ESC exits the mode, then pauses.
## Mode state comes from the owners: OrderSystem (sell/repair) and EntityPlacer
## (free placement) — never from UI scripts.
func _esc_busy() -> bool:
    if BuildingManager.is_build_mode:
        return true
    if OrderSystem.is_action_mode():
        return true
    return EntityPlacer.is_placing()


func _toggle_pause() -> void:
    get_tree().paused = not get_tree().paused
    visible = get_tree().paused
    if visible:
        _update_briefing_button()


## The Briefing button is only meaningful with an active mission.
func _update_briefing_button() -> void:
    briefing_button.disabled = GameContext.current_mission == null


func _on_briefing_pressed() -> void:
    briefing_requested.emit()


func _on_resume_pressed() -> void:
    get_tree().paused = false
    visible = false


func _on_quit_pressed() -> void:
    get_tree().quit()
