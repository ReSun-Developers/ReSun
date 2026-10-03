extends Node

## SessionShell — the persistent host for ReSun's GUI surfaces. Exactly one
## top-level surface is mounted at a time, chosen by session mode: `MENU` (the
## boot screen and main menu, process-level) or `MATCH` (the in-game HUD). The
## shell outlives any single match and is switched to `MATCH` by MissionBoot
## when a mission starts. The HUD is a peer of the World root, never a child of
## the loaded map.

enum Mode { MENU, MATCH }

const MENU_SURFACE_SCENE: PackedScene = preload("res://scenes/ui/MenuSurface.tscn")
const HUD_SURFACE_SCENE: PackedScene = preload("res://scenes/ui/HudSurface.tscn")

var _mode: int = Mode.MENU
var _surface: Node = null


func _ready() -> void:
    show_menu()


## Mounts the menu surface (boot screen + main menu). No match or World root is
## required.
func show_menu() -> void:
    _mount(Mode.MENU)


## Mounts the in-game HUD surface for the duration of a match.
func show_match() -> void:
    _mount(Mode.MATCH)


func get_mode() -> int:
    return _mode


## The currently mounted surface node, or null.
func get_surface() -> Node:
    return _surface


## Replaces the mounted surface, detaching and freeing the previous one so two
## top-level surfaces never coexist.
func _mount(mode: int) -> void:
    if is_instance_valid(_surface):
        _surface.queue_free()
        remove_child(_surface)
    _mode = mode
    var scene: PackedScene = HUD_SURFACE_SCENE if mode == Mode.MATCH else MENU_SURFACE_SCENE
    _surface = scene.instantiate()
    add_child(_surface)
