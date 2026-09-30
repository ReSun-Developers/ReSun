---
name: redot-engine-best-practices
description: "Unified Redot Engine 26.2 LTS best practices for GDScript code generation, scene architecture, signals, components, state machines, and performance optimization."
license: MIT
compatibility: Requires Redot 26.2 LTS (Forward Plus renderer). GDScript only — no C# bindings or GDExtension support in this version.
metadata:
  author: ReSun-Developers
  version: "1.0"
  engine_version: "26.2 LTS"
  type: utility
  mode: assistive
  domain: gamedev

---

# Redot Engine 26.2 LTS — GDScript Best Practices

Guide AI agents in writing high-quality, idiomatic GDScript code for **Redot Engine 26.2 LTS** (Forward Plus renderer). This skill covers coding standards, architecture patterns, scene composition, and performance optimization specific to the engine fork.

## When to Use This Skill

Use this skill when:
- Generating new GDScript files or modifying existing ones
- Creating or organizing Redot scenes (.tscn)
- Designing game architecture, node hierarchies, or component systems
- Implementing state machines, object pools, save/load systems, or resource data models
- Answering questions about Redot conventions, signal patterns, or GDScript standards
- Reviewing GDScript code for quality issues or anti-patterns

**Do NOT use this skill when:**
- Working with C# (Redot 26.2 LTS has no C# bindings)
- Using GDExtension / native libraries (.gdnlib files are out of scope)
- Writing editor plugins that target the Redot editor itself
- Targeting Godot 3.x — syntax and APIs differ significantly

## Core Principles

### Naming Conventions

Follow these consistently across all scripts:

```gdscript
# Classes + Scripts: PascalCase, use `class_name` for globally accessible types
class_name PlayerController extends CharacterBody3D

# Signals: past_tense_snake_case (describe what happened)
signal health_changed(current_health: int, max_health: int)
signal died(position: Vector3)
signal item_collected(item_type: StringName)

# Constants: SCREAMING_SNAKE_CASE
const MAX_SPEED: float = 200.0
const JUMP_FORCE: float = -400.0
const GRAVITY_SCALE: float = 1.0

# Variables and functions: snake_case (public), _snake_case for private
var current_health: int = 100
var speed_multiplier: float = 1.0

func calculate_damage(base_damage: int, multiplier: float) -> int:
	return int(base_damage * multiplier)

func _ready() -> void:
	pass

# Private helpers get leading underscore in name AND are not exposed via signals or @export
func _clamp_velocity_to_max(velocity: Vector3) -> Vector3:
	return velocity.clamped(MAX_SPEED)
```

### Type Hints (Static Typing) — REQUIRED

Use explicit type hints **on every variable, parameter, and return value**. Redot's GDScript provides autocomplete and compile-time checks when types are declared.

```gdscript
# Variable declarations with types
var speed: float = 100.0
var player_node: Node3D
var items: Array[Node] = []
var stats: Dictionary = {}

# Function signatures — always include return type
func get_damage() -> int:
	return _base_damage * _multiplier

func find_nearest_enemy(position: Vector3) -> Node3D:
	# Implementation returns null if none found
	return null

# Typed signals (Redot 4.x style, used in Redot 26.2 LTS)
signal score_updated(new_score: int, old_score: int)
signal target_acquired(target: Node3D, distance: float)

# @onready with type hints — NEVER use untyped onready
@onready var sprite_3d: Sprite3D = $Sprite3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
```

### Node References

Use modern, refactor-safe patterns for node access:

```gdscript
# PREFER: @onready with type hints and direct paths (max 2 levels deep)
@onready var health_bar: ProgressBar = $UI/HealthBar
@onready var weapon_mount: Node3D = $WeaponMount

# PREFER: Unique instance names for critical nodes wired in scene tree
@onready var player_character: CharacterBody3D = %PlayerCharacter
@onready var game_manager: GameManager = %GameManager  # Autoload reference via name

# AVOID: get_node() calls inside _ready() or later — defeats @onready caching
func _ready() -> void:
	# BAD — creates a new lookup every time, no type hint
	var sprite := get_node("Sprite3D") as Sprite3D

# AVOID: Deep fragile paths ($A/B/C/D/E)
@onready var thing = $Parent/Child/Grandchild/GreatGrandchild  # Fragile to refactor
```

### Signal-Driven Architecture — "Signal Up, Call Down"

Children emit signals; parents connect and react. Children must **never** directly call parent methods or hold references upward through the scene tree.

```gdscript
# Child node emits signals (has no knowledge of its parent)
class_name HealthComponent extends Node3D

signal health_changed(current: int, maximum: int)
signal died(position: Vector3)

var _current_health: int = 100
@export var max_health: int = 100

func take_damage(amount: int) -> void:
	_current_health = maxi(0, _current_health - amount)
	health_changed.emit(_current_health, max_health)
	if _current_health <= 0:
		died.emit(global_position)
```

```gdscript
# Parent connects to child signals (owns the relationship)
class_name Player extends CharacterBody3D

@onready var health_component: HealthComponent = $HealthComponent

func _ready() -> void:
	health_component.health_changed.connect(_on_health_changed)
	health_component.died.connect(_on_died)

func _on_health_changed(current: int, maximum: int) -> void:
	pass  # Update UI, play effects, etc.

func _on_died(position: Vector3) -> void:
	queue_free()
```

### Resource Loading Strategy

Choose the right loading mechanism for your use case:

```gdscript
# preload(): Compile-time resolved — best for small/critical assets referenced everywhere
const BULLET_SCENE: PackedScene = preload("res://scenes/particles/bullet_impact.tscn")
const PLAYER_SPRITE: Texture2D = preload("res://assets/sprites/player_idle.png")

# load() at runtime: resolves path string — use sparingly for dynamic/optional content
func load_level(level_name: String) -> PackedScene:
	var scene_path := "res://scenes/stages/%s.tscn" % level_name
	return load(scene_path) as PackedScene

# ResourceLoader threaded loading (prevents frame stutter on large scenes/assets)
var _level_load_progress: float = 0.0

func start_async_load(path: String, progress_callback: Callable) -> void:
	ResourceLoader.load_threaded_request(path)
	_update_threaded_load(progress_callback)

func _update_threaded_load(callback: Callable) -> void:
	var status := ResourceLoader.load_threaded_get_status("res://scenes/stages/level_01.tscn")
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			callback.call(0.5, 1.0)  # progress fraction
		ResourceLoader.THREAD_LOAD_LOADED:
			var scene := ResourceLoader.load_threaded_get("res://scenes/stages/level_01.tscn") as PackedScene
			add_child(scene.instantiate())
```

## Quick Reference Table

| Category | Prefer | Avoid |
|----------|--------|-------|
| Node references | `@onready var x: Type = $Path` (≤2 levels) | `get_node()` in `_ready()`, deep paths `$A/B/C/D/E` |
| Unique nodes | `%UniqueName` for autoloaded/root-wired nodes | Hardcoded string paths to sibling scenes' children |
| Resource loading | `preload()` for small/critical assets | `load()` called inside `_process()` or tight loops |
| Signals | Typed: `signal x(val: int)` → `x.emit(value)` | String-based: `emit_signal("x", value)`, `call("method")` |
| Type safety | Explicit type hints on ALL signatures and vars | Untyped variables, implicit typing via inference only |
| Constants / Configs | `const` or `@export var` with defaults | Magic numbers/strings scattered through logic |
| Null checks for nodes | `is_instance_valid(node)` after potential free | `node != null` (freed nodes are non-null in GDScript) |
| Coroutines | `await node.timeout` / `await tree.process_frame` | `yield()` — deprecated, no type safety |
| Groups | Scene-specific groups added in `_ready()` on component scripts | Global groups for everything; forgetting to remove when freed |
| Autoloads | Thin services/managers only (no game logic) | Heavy business logic inside autoload singletons |
| Property mutation | Private vars with setters + `emit_signal` / signals | Direct public var mutation without side effects |
| Communication pattern | Signal up, call down (child→parent via signal; parent→child via method on known instance) | Circular references between siblings or child→parent direct calls |

## Script Structure Template

Order sections **in this exact order** in every GDScript file. This keeps codebases navigable for AI agents and human reviewers alike:

```gdscript
class_name MyComponent extends Node3D
## Brief one-line description of purpose.
##
## Longer multi-line description if needed, explaining behavior, usage constraints, or integration notes.

# === Signals (top — consumers connect here) ===
signal state_changed(new_state: State)
signal action_performed(data: Dictionary)

# === Enums (next — used by signals and logic) ===
enum State { IDLE, MOVING, ATTACKING }

# === @export fields (editor-configurable values) ===
@export var move_speed: float = 10.0
@export_range(0.0, 1.0) var fade_alpha: float = 0.5
@export_group("Combat")
@export var damage: int = 10
@export var attack_cooldown: float = 1.0

# === Constants (compile-time constants internal to this script) ===
const MAX_HEALTH: int = 100
const DEFAULT_POSITION := Vector3.ZERO

# === Public variables (runtime state visible from outside) ===
var current_state: State = State.IDLE
var health_points: int = MAX_HEALTH

# === Private variables (internal implementation details, prefixed with _) ===
var _timer_accumulator: float = 0.0
var _cached_target: Node3D

# === @onready cached references ===
@onready var sprite_3d: Sprite3D = $Sprite3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var animation_player: AnimationTree = %AnimationTree  # Unique name from scene

# ========================================
# Lifecycle Methods (in order)
# ========================================

func _enter_tree() -> void:
	pass

func _ready() -> void:
	_connect_signals()
	_initialize_state()

func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		pass  # Use sparingly; prefer _physics_process for movement/logic updates

func _unhandled_input(event: InputEvent) -> void:
	pass

func _exit_tree() -> void:
	pass

# ========================================
# Public Methods (callable from other nodes)
# ========================================

func take_damage(amount: int, source: Node3D = null) -> int:
	var actual := mini(health_points, amount)
	health_points -= actual
	return actual

func reset() -> void:
	current_state = State.IDLE
	health_points = MAX_HEALTH

# ========================================
# Private Methods (implementation details)
# ========================================

func _connect_signals() -> void:
	pass

func _initialize_state() -> void:
	pass

func _on_health_changed(new_hp: int, max_hp: int) -> void:
	pass
```

## Export Annotations Reference

Use `@export` variants for editor-configurable values. These appear in the Inspector panel and are scene-persisted.

| Annotation | Use Case | Example |
|------------|----------|---------|
| `@export var x: Type = default` | Basic inspector field | `@export var speed: float = 200.0` |
| `@export_range(min, max)` or `@export_range(min, max, step)` | Numeric sliders with constraints | `@export_range(0, 100) var volume: float = 50.0`<br>`@export_range(0.0, 1.0, 0.01) var alpha: float = 1.0` |
| `@export_group("Group Name")` | Label separator for grouped fields | `@export_group("Movement")\n@export var walk_speed: float = 100.0\n@export var run_speed: float = 250.0` |
| `@export_file("*.tscn, *.glb")` or `@export_dir` | File / directory picker in Inspector | `@export_file("*.tscn") var scene_path: String`<br>`@export_dir var asset_directory: String = "res://assets/models/"` |
| `@export_flags_2d_physics` etc. | Bitmask enums for physics layers/masks | `@export_flags_3d_physics var collision_layers: int = 15` |
| `@export_enum("Choice A", "Choice B")` or typed enum export | Dropdown selector in Inspector | `@export var difficulty: Difficulty = Difficulty.NORMAL\nenum Difficulty { EASY, NORMAL, HARD }` |
| `@export_multiline var text: String` | Multi-line string field | `@export_multiline var description: String = "Enter description..."` |

### Editor-Only Scripts — `@tool` Annotation

Use the `@tool` annotation to run a script in the Redot editor (not just at runtime). This enables custom inspectors, real-time preview of component behavior, and automated scene validation. Always guard runtime-only calls with `Engine.is_editor_hint()`.

```gdscript
## Editor tool script for validating entity scenes during design time.
@tool
extends Node3D

func _enter_tree() -> void:
	# Run editor-specific logic here — this method fires in both editor and at runtime


func validate_entity_scene() -> Array[String]:
	var warnings := [] as Array[String]
	
	if not is_in_group("entity"):
		warnings.append("%s is missing 'entity' group tag" % name)
	
	var collision_shape: CollisionShape3D = $CollisionShape3D if has_node("$CollisionShape3D") else null
	if collision_shape == null and Engine.is_editor_hint():
		push_warning("%s: Missing expected child node 'CollisionShape3D'" % name)
	
	return warnings


func _get_configuration_warnings() -> PackedStringArray:
	var issues := validate_entity_scene() as PackedStringArray
	
	# Return non-empty array to show warning triangle in editor scene tree
	if not issues.is_empty():
		return PackedStringArray(issues)
	
	return PackedStringArray([])


func _on_node_added(parent: Node, node_name: StringName) -> void:
	# Editor callback — fires when a child is added via the editor's drag-and-drop UI.
	if Engine.is_editor_hint():
		print("[Editor] Added %s to %s" % [node_name, parent.name])


```

**Key rules for `@tool` scripts:**
- Always wrap runtime-only calls (e.g., `get_tree()`, input polling) in `if not Engine.is_editor_hint()` guards. The editor's scene tree differs from the running game — calling `queue_free()` on an editor-scene node will remove it permanently from the project file.
- Return meaningful strings via `_get_configuration_warnings()` to surface design-time validation errors as yellow warning triangles in the Redot inspector/scene tree.

## Common Game Patterns (Overview)

### State Machine — Enum-Match Variant (Simple Cases)

For simple entities that only need branching logic without rich per-state lifecycle hooks:

```gdscript
class_name SimpleStateMachine extends Node3D

enum State { IDLE, WALKING, ATTACKING }

@export var move_speed: float = 5.0

var current_state: State = State.IDLE

func _physics_process(delta: float) -> void:
	match current_state:
		State.IDLE:
			_handle_idle(delta)
		State.WALKING:
			_handle_walking(delta)
		State.ATTACKING:
			_handle_attacking(delta)

func _handle_idle(_delta: float) -> void:
	if Input.is_action_just_pressed("move_forward"):
		change_state(State.WALKING)

func change_state(new_state: State) -> void:
	current_state = new_state
```

### Object Pooling — Prevent Instantiation Stutter

Reuse objects to avoid GC pressure and frame hitches from frequent `instantiate()`/`queue_free()`:

```gdscript
class_name ObjectPool extends Node3D

var _pool: Array[Node3D] = []
@export var pooled_scene: PackedScene
@export var initial_size: int = 10

func _ready() -> void:
	for i in initial_size:
		var instance := _create_instance()
		_pool.append(instance)

func _create_instance() -> Node3D:
	if not pooled_scene:
		push_error("ObjectPool: pooled_scene is null")
		return null
	
	var instance := pooled_scene.instantiate() as Node3D
	instance.process_mode = Node3D.PROCESS_MODE_DISABLED
	add_child(instance)
	
	# Auto-connect return signal if the pooled object defines one
	if instance.has_signal("returned_to_pool"):
		instance.returned_to_pool.connect(_on_returned.bind(instance))
	return instance

func acquire() -> Node3D:
	var instance: Node3D
	
	if _pool.is_empty():
		instance = _create_instance()
	else:
		instance = _pool.pop_back()
	
	instance.process_mode = Node3D.PROCESS_MODE_INHERIT
	instance.visible = true
	
	# Call spawn callback if the object implements it
	if instance.has_method("on_spawn"):
		instance.on_spawn()
	
	return instance

func release(instance: Node3D) -> void:
	if instance.has_method("on_despawn"):
		instance.on_despawn()
	
	instance.process_mode = Node3D.PROCESS_MODE_DISABLED
	instance.visible = false
	_pool.append(instance)

func _on_returned(instance: Node3D) -> void:
	release(instance)
```

### Save/Load — Resource-Based Persistence

Use `Resource` subclasses for structured save data with the built-in serialization system:

```gdscript
# game_save_data.gd
class_name GameSaveData extends Resource

@export var player_position: Vector3 = Vector3.ZERO
@export var player_health: int = 100
@export var inventory_ids: Array[StringName] = []
@export var current_level: StringName = "level_01"
@export var game_time_seconds: float = 0.0

# Save function — serializes to user:// directory (sandboxed per OS)
func save_to_disk(path: String = "user://game_save.tres") -> void:
	var error := ResourceSaver.save(self, path)
	assert(error == OK, "Failed to save game data: %d" % error)

# Load function — returns a fresh instance or null if no save exists
static func load_from_disk(path: String = "user://game_save.tres") -> GameSaveData:
	if not ResourceLoader.exists(path):
		return null
	
	var loaded := ResourceLoader.load(path) as GameSaveData
	assert(loaded != null, "Failed to load game data from %s" % path)
	return loaded.duplicate()  # Return a copy so the original resource stays intact

# JSON fallback for plain-text saves (e.g. cloud sync or mod-friendly formats)
func to_json_string() -> String:
	var dict := {
		"player_position": [player_position.x, player_position.y, player_position.z],
		"player_health": player_health,
		"inventory_ids": inventory_ids.duplicate(),
		"current_level": current_level,
		"game_time_seconds": game_time_seconds,
	}
	return JSON.stringify(dict)

static func from_json_string(json_str: String) -> GameSaveData:
	var parsed := parse_json(json_str) as Dictionary
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid save data format")
		return null
	
	var save_data := GameSaveData.new()
	save_data.player_position = Vector3(
		parsed.get("player_position", [0.0, 0.0, 0.0])
	) as Vector3
	save_data.player_health = parsed.get("player_health", 100)
	save_data.inventory_ids = parsed.get("inventory_ids", [])
	save_data.current_level = str(parsed.get("current_level", "level_01"))
	save_data.game_time_seconds = float(parsed.get("game_time_seconds", 0.0))
	return save_data
```

## Common Anti-Patterns

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Polling in `_process()` for infrequent state changes | Wastes CPU every frame; couples logic to fixed timestep | Use signals or `await` with timers instead of checking flags each frame |
| `get_parent().get_parent()...` chains | Tight coupling, breaks on scene refactor, unreadable depth | Connect via signals, use unique `%Name` references, or inject dependencies through @export NodePath fields |
| Deep node paths `$A/B/C/D/E/F` | Fragile to reorganizing the scene tree; silent failures if a parent is renamed/moved | Use `@onready var x: Type = $SiblingOrChild`, or wire via unique instance names and autoload references |
| Calling `load()` inside `_process()`, `_physics_process()`, or tight loops | Causes frame stutter, memory churn — each call parses the file from disk at runtime | Move to `_ready()`, use `preload()` for compile-time known paths, or cache in a variable with a `const`/`@onready var` |
| String-based signals: `emit_signal("health_changed", val)` and `call("method_name")` | Typos silently ignored at runtime; no autocomplete; breaks on rename/refactor | Use typed signal declarations + dot-call syntax: `signal health_changed(val); health_changed.emit(value)` / direct method calls with known types |
| Untyped `@onready var x = $NodePath` | Loses type hints, disables IDE autocomplete for that node's methods and properties | Always add explicit type after the colon: `@onready var sprite_3d: Sprite3D = $Sprite3D` |
| Logic inside autoload singletons ( GameManager with all game rules) | Hard to test; couples every subsystem together; violates separation of concerns | Keep autoloads thin — expose only state + signals. Delegate actual logic to component scripts on scene nodes |
| Magic numbers: `if speed > 200 and damage == 15` | Unclear meaning, impossible to tune without reading code | Extract into named constants or @export fields with descriptive names |
| `node != null` check after a node may have been freed | In GDScript, a freed node is **not** null — it's an invalid instance that still passes `!= null`. Accessing it crashes. | Use `is_instance_valid(node)` to safely check if a previously-freed node is still alive |
| Creating new objects inside `_process()` or tight loops every frame | Triggers GC pressure; causes stutter spikes in the player | Pre-allocate with ObjectPool, reuse arrays/dictionaries, or use `Array.clear()` instead of re-instantiating containers |
| Circular references between sibling nodes (Child A holds ref to B AND vice versa) | Unclear ownership, memory leaks if not cleaned up on `_exit_tree()`, confusing debug flow | Parent owns and wires children; siblings communicate via parent signals or the global Autoload bus. Never hold direct cross-references between peers |
| Hardcoding scene paths as strings scattered across scripts | Path typos fail at runtime; refactoring a scene directory breaks every reference | Centralize in a single `const` file, use preload() for critical dependencies, or load via parameterized functions with consistent path templates |

## Redot Engine 26.2 LTS — API Notes

| Topic | Note |
|-------|------|
| **Renderer** | Forward Plus only (no Compatibility renderer). All materials must be `StandardMaterial3D` / `ORMMaterial3D`. |
| **Physics raycast** | Use `query.collide_with_areas = true` on `PhysicsRayQueryParameters3D`. Default collision mask is all layers (`4294967295`). |
| **Collision layers** | StaticBody3D defaults to layer 1. Entity detection typically uses higher bits like `1 << 15`. Set masks via bit shifts: `collision_mask = 1 << LAYER_NUMBER`. |
| **Node process modes** | Same as Godot 4.x: `PROCESS_MODE_INHERIT`, `PROCESS_MODE_PAUSED`, `PROCESS_MODE_ALWAYS`, `PROCESS_MODE_WHEN_PAUSED`. Use `process_mode` property to control behavior. |
| **await syntax** | Full GDScript `await` support — use for timers, signals (`await node.timeout`), and coroutines. No need for deprecated `yield()`. |
| **Documentation** | Always prefer Redot docs at `https://docs.redotengine.org/` over upstream Godot documentation when there are differences. |

## Limitations

- GDScript only — no C#, GDExtension, or native library bindings in this engine version
- Forward Plus renderer only (no Compatibility mode shaders)
- Game-focused patterns — not aimed at editor plugin development
- No built-in test framework; manual scene-level testing is the current practice
