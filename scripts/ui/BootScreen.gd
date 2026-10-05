class_name BootScreen
extends Control

# Boot screen — game-agnostic launcher shown before any game's main menu.
# Deliberately plain placeholder controls: one standard Button per
# discovered GameDefinition plus a disabled Options placeholder and Quit,
# on a neutral background. The scene references no per-game content —
# visual theming arrives with the content packs (#378+). Picking a game
# resolves it through GameContext, persists the choice, and reveals the
# main menu; Quit and ESC exit the app. With --game the launcher never
# becomes visible at all.
#
# ponytail: picking always lands on whatever menu MainScene hosts (today
# TS's MainMenu01); per-game menus arrive with the content packs too.

const OptionsView := preload("res://scripts/ui/OptionsView.gd")

const OPTIONS_LABEL: String = "Options"
const QUIT_LABEL: String = "Quit"


func _ready() -> void:
    _apply_gate(OS.get_cmdline_args(), OS.get_cmdline_user_args())


## Shared boot gate: with --game the launcher never shows (no menu flash);
## otherwise rows are built and the main menu is occluded. Split from
## _ready so tests can drive both branches with synthetic args.
func _apply_gate(args: PackedStringArray, user_args: PackedStringArray) -> void:
    if BootScreen.should_skip(args) or BootScreen.should_skip(user_args):
        visible = false
        return
    _build_rows()
    visible = true
    var menu := _main_menu()
    if menu:
        menu.visible = false


## True when the args carry a --game flag: skip the launcher entirely.
## Static for testability — process args cannot be changed at runtime.
static func should_skip(args: PackedStringArray) -> bool:
    return not GameContext.extract_flag_id(args).is_empty()


func _build_rows() -> void:
    var rows: VBoxContainer = get_node("%Rows")
    for def in GameContext.list_games():
        var label := def.display_name if not def.display_name.is_empty() else def.id
        _add_button(rows, label, def.id, false)
    _add_button(rows, OPTIONS_LABEL, "", false)
    _add_button(rows, QUIT_LABEL, "", false)


func _add_button(rows: VBoxContainer, label: String, game_id: String, disabled: bool) -> void:
    var button := Button.new()
    button.text = label
    button.disabled = disabled
    if not game_id.is_empty():
        button.set_meta("game_id", game_id)
        button.pressed.connect(_pick_game.bind(game_id))
    elif label == OPTIONS_LABEL:
        button.pressed.connect(_open_options)
    elif label == QUIT_LABEL:
        button.pressed.connect(_quit)
    rows.add_child(button)


## Opens the Options view over the launcher (neutral theme, no per-game asset).
func _open_options() -> void:
    OptionsView.open(self, "graphics", null, true)


## Exits the app — shared by the Quit row and ESC.
func _quit() -> void:
    get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
    if visible and event.is_action_pressed("pause"):
        _quit()


## Selects the picked game (skipped when already active — no wasteful
## consumer re-register), persists the choice, then hands off to the menu.
## A refused selection keeps the launcher open and writes nothing.
func _pick_game(id: String) -> void:
    if GameContext.current == null or GameContext.current.id != id:
        GameContext.select_game(id)
        if GameContext.current == null or GameContext.current.id != id:
            return
    GameContext.save_game_choice(id)
    visible = false
    var menu := _main_menu()
    if menu:
        menu.visible = true


func _main_menu() -> Node:
    return get_node_or_null("../MainMenu01")
