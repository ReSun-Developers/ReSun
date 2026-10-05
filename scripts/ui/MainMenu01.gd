extends Control

# Called when the node enters the scene tree for the first time.
# Main menu controller – handles button clicks and exit logic

const OptionsView := preload("res://scripts/ui/OptionsView.gd")

@onready var _campaign_dialog: CampaignDialog = $CampaignDialog
@onready var _background: TextureRect = $TextureRect


func _ready() -> void:
    _apply_game_theme()


## Applies the active game's menu background and accent colour, leaving the
## scene defaults when the game declares none.
func _apply_game_theme() -> void:
    var def: GameDefinition = GameContext.current
    if def == null:
        return
    if not def.menu_background.is_empty():
        var texture := load(def.menu_background) as Texture2D
        if texture:
            _background.texture = texture
    for item in _collect_menu_items(self):
        if item.has_method("set_accent"):
            item.set_accent(def.menu_accent_color)


func _input(event):
    # Hidden menus must ignore input: _input is delivered even when the
    # node is invisible (PauseMenu's ESC-unpause depends on that while its
    # own menu is hidden), so an overlay hiding this menu — the boot
    # screen — also needs this guard.
    if not visible:
        return
    # The Options overlay owns input while open; otherwise clicks on its
    # controls also hit the menu items behind it.
    if get_tree().get_first_node_in_group("options_view") != null:
        return
    if event is InputEventMouseButton and event.pressed:
        var mouse_pos = get_viewport().get_mouse_position()
        for item in _collect_menu_items(self):
            if item.get("is_disabled"):
                continue
            var lbl: Label = item.get_node_or_null("Text") as Label
            if lbl and lbl.get_global_rect().has_point(mouse_pos):
                _handle_click(lbl.text)


func _collect_menu_items(node: Node) -> Array:
    var items: Array = []
    if node != self and node.has_node("Text") and "is_disabled" in node:
        items.append(node)
    for child in node.get_children():
        items.append_array(_collect_menu_items(child))
    return items


func _handle_click(button_text: String) -> void:
    match button_text:
        "Exit":
            get_tree().quit()
        "New Campaign":
            if is_instance_valid(_campaign_dialog):
                _campaign_dialog.open()
            else:
                push_error("MainMenu01: CampaignDialog node is missing")
        "Options":
            OptionsView.open(self, "graphics", GameContext.current, true)
        _:
            # Placeholder for other buttons – currently just log
            print("Clicked button: ", button_text)
