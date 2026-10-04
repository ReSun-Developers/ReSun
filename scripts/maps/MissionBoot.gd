extends Node

## MissionBoot — the boot seam that turns an active Mission into a running map.
## A direct child of MainScene's root: connects the mission signal, applies the
## mission's overrides, and hosts MissionMap inside a per-match World root under
## Gameplay. Also consumes the --mission CLI flag after autoloads are ready (D7).

const MISSION_MAP_SCENE: PackedScene = preload("res://scenes/maps/MissionMap.tscn")
const WORLD_SCENE: PackedScene = preload("res://scenes/core/World.tscn")
const WORLD_NAME: String = "World"


func _ready() -> void:
    GameContext.mission_started.connect(_on_mission_started)
    var mission_id := _consume_mission_args(OS.get_cmdline_args(), OS.get_cmdline_user_args())
    if not mission_id.is_empty():
        GameContext.start_mission(mission_id)


## The --mission id from engine args, falling back to user args. Static-like pure
## helper so tests can drive it without real process args.
func _consume_mission_args(args: PackedStringArray, user_args: PackedStringArray) -> String:
    var mission_id := GameContext.extract_mission_id(args)
    if mission_id.is_empty():
        mission_id = GameContext.extract_mission_id(user_args)
    return mission_id


func _on_mission_started(mission: Mission) -> void:
    var gameplay := _find_gameplay()
    if gameplay == null:
        push_error("MissionBoot: no Gameplay node; cannot load mission '%s'" % mission.id)
        return
    var map: Node = MISSION_MAP_SCENE.instantiate()
    _swap_world(gameplay, map)
    _show_match_session()
    PlayerManager.begin_mission(mission, map.find_child("MapConfig", true, false))
    _arm_scripting(mission)


## Resets per-match scripting state and arms the mission's triggers from its map
## JSON. Safe to call with no scripting data (nothing arms).
func _arm_scripting(mission: Mission) -> void:
    MatchClock.reset()
    ScenarioState.reset()
    var scripting: Dictionary = MapLoader.read_scripting(mission.map_path)
    var variables: Dictionary = scripting["variables"]
    ScenarioState.declare_variables(
        _as_array(variables.get("globals", [])), _as_array(variables.get("locals", []))
    )
    ScenarioState.load_waypoints(scripting["waypoints"])
    TriggerEngine.reset()
    TriggerEngine.arm(_as_array(scripting["triggers"]), _load_overlay(mission))


## Loads an optional `<map_basename>_triggers.tres` TriggerSet overlay next to
## the mission map. Absent returns an empty overlay.
func _load_overlay(mission: Mission) -> Array:
    var overlay_path: String = mission.map_path.get_basename() + "_triggers.tres"
    if not ResourceLoader.exists(overlay_path):
        return []
    var trigger_set := load(overlay_path) as TriggerSet
    return trigger_set.triggers if trigger_set != null else []


## Coerces an untyped JSON value to an Array, so malformed imported content
## (e.g. a string where an array is expected) declares nothing instead of
## raising a type error.
func _as_array(value: Variant) -> Array:
    return value if value is Array else []


## Replaces any existing World root with a fresh one hosting `map`, and returns
## the new root. The previous root is detached immediately and freed at frame
## end, so at most one World root exists under `gameplay` at any time.
func _swap_world(gameplay: Node, map: Node) -> Node:
    var previous := gameplay.get_node_or_null(WORLD_NAME)
    if previous:
        previous.queue_free()
        gameplay.remove_child(previous)
    var world: Node = WORLD_SCENE.instantiate()
    world.name = WORLD_NAME
    gameplay.add_child(world)
    if map:
        world.add_child(map)
    return world


## Switches the UI session shell to match mode. An absent shell (e.g. a headless
## test tree) is a no-op.
func _show_match_session() -> void:
    var shell := _find_session_shell()
    if shell and shell.has_method("show_match"):
        shell.show_match()


func _find_session_shell() -> Node:
    var root := _scene_root()
    if root == null:
        return null
    return root.get_node_or_null("SessionShell")


func _find_gameplay() -> Node:
    var root := _scene_root()
    if root == null:
        return null
    return root.get_node_or_null("Gameplay")


## The scene that owns this node, with a fallback for a detached current scene.
func _scene_root() -> Node:
    var tree := get_tree()
    if tree and tree.current_scene:
        return tree.current_scene
    return get_parent()
