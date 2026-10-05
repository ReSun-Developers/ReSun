class_name GameDefinition
extends Resource

## GameDefinition — one standalone game's content manifest (Tiberian Sun,
## Firestorm, RA2, ...). Each game owns exactly one definition at
## res://games/<id>/game.tres; the id MUST match the directory name.
## GameContext discovers these and exposes the active one to consumers.

## Unique game id, matching the res://games/<id>/ directory name.
@export var id: String = ""

## Human-readable name shown in menus (e.g. "Tiberian Sun").
@export var display_name: String = ""

## Full per-game rules resource — one global_rules.tres per game, no
## override-merge machinery.
@export var rules: GlobalRules = null

## Ordered layer roots scanned by EntityFactory/TerrainCatalog/AudioManager.
## Each entry is a res:// directory; consumers append their known subdirectory
## names (entities/, audio/, terrain_objects/, art/terrain/, theaters/) per
## root and register roots in order — later roots win on id collisions.
## Borrowing another game's content = listing its root here.
@export var data_sets: PackedStringArray = PackedStringArray()

## Directory holding this game's map files. Reserved for per-game map
## selection (follow-up phase); not consumed by the boot screen.
@export var maps_dir: String = ""

## Fallback terrain scene (res:// path) loaded when the active theater's art does
## not resolve. Empty = no fallback.
@export var fallback_terrain_scene: String = ""

## Main-menu background image (res:// path). Empty = leave the scene default.
@export var menu_background: String = ""

## Main-menu item accent colour. Defaults to white (neutral).
@export var menu_accent_color: Color = Color.WHITE

## Per-game on/off mechanic toggles (feature id -> bool). Absent ids read as
## false, so a game that omits a feature does not get the mechanic. Numeric or
## behavioral values belong on the game's GlobalRules, not here.
@export var features: Dictionary = {}

## Sidebar build-menu tabs in display order. Each entry is a Dictionary:
## { "name": String, "entity_types": Array[String], "requires_feature": String }.
## `entity_types` names EntityData.EntityType keys (e.g. "BUILDING"); an empty
## list is allowed (placeholder tab). `requires_feature` is optional — the tab
## is hidden when the game does not enable that feature. Empty = the built-in
## default tab set.
@export var sidebar_tabs: Array[Dictionary] = []

## Input actions this game supports. Empty = no restriction (every action the
## input system manages is supported). A non-empty list is an allow-list;
## actions absent from it are unsupported for this game and cannot be bound.
@export var supported_inputs: PackedStringArray = PackedStringArray()


## True when this game declares the feature and has it enabled. Unknown ids
## read as false.
func has_feature(id: String) -> bool:
    return bool(features.get(id, false))


## True when the game supports the input action (empty declaration = all).
func supports_input(action: String) -> bool:
    return supported_inputs.is_empty() or supported_inputs.has(action)
