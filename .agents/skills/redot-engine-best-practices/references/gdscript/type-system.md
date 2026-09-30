# Type System Deep Dive

Redot 26.2 LTS GDScript supports full static typing with compile-time checking enabled by default for explicit type annotations. This document covers patterns that maximize the benefit of typed code in game development contexts.

## Variable Declarations — Always Include Types

```gdscript
var speed: float = 100.0                    # Explicit type + initializer (preferred)
var player_node: Node3D                     # Type only; will be set by @onready later
var items: Array[Node] = []                 # Generic array with element type
var stats: Dictionary = {}                  # Typed dictionary is not yet supported in GDScript


```

### Why Not Infer Types?

While `var x = 42` technically infers the type as `int`, **always write the type explicitly**. Inference loses IDE autocomplete for properties/methods on that variable, makes refactoring harder (changing from `float` to `double` requires finding every inferred var), and violates the project's explicit typing convention.

## @onready — Typed References Are Mandatory

```gdscript
# GOOD: Type hint after colon enables full autocomplete for all Sprite3D methods/properties
@onready var sprite_3d: Sprite3D = $Sprite3D

// BAD: No type → no autocomplete on `sprite_3d` in the rest of this script  
@onready var sprite_3d = $Sprite3D


```

When referencing unique nodes, prefer `%UniqueName` syntax for root-level or autoloaded nodes where path stability is guaranteed:

```gdscript
// References an Autoload singleton by name — type-safe with cast if needed
@onready var selection_manager: SelectionManager = %SelectionManager  // Works in scene tree


```

## Function Signatures — Return Types on Every Method

```gdscript
func calculate_damage(base_damage: int, armor_reduction_factor: float) -> int:
	var actual_damage := int(base_damage * (1.0 - clampf(armor_reduction_factor, 0.0, 0.9)))
	return maxi(actual_damage, 1)  # Minimum 1 damage

// Always include parameter types — even if the caller can infer them from a Callable


```

## Typed Signals and Callbacks

Typed signals provide compile-time checks for emitted values:

```gdscript
signal health_changed(new_health: int, max_health: int)   // Two typed parameters

func _on_health_bar_update(current_hp: int, max_hp: int) -> void:
	// Parameters inferred from signal declaration — no need to re-declare types here


```

For `Callable` type hints (used when passing callbacks as arguments):

```gdscript
var progress_callback: Callable  // Accepts any callable signature; for strict typing use custom wrapper or typed array + int pattern

func start_load(progress_cb: Callable) -> void:
	ResourceLoader.load_threaded_request("res://scenes/stages/level_01.tscn")
	progress_cb.call(0.5, 1.0)  // Call with expected arguments


```

## Enums — Typed and Scoped

Use `enum` for finite state sets. Enum values are accessible as constants on the class:

```gdscript
class_name PlayerController extends CharacterBody3D

// Inline enum declaration (scoped to this script's namespace)
enum State { IDLE, WALKING, JUMPING, ATTACKING }

var current_state: State = State.IDLE  // Typed variable accepts only these four values


```

For enums shared across multiple scripts, extract them into a standalone file or use `class_name` with explicit constant members.

## Arrays and Dictionaries — Generic Element Types (Where Available)

GDScript supports typed arrays using the generic syntax `Array[Type]`:

```gdscript
var selected_entities: Array[SelectComponent] = []  // Typed array — IDE knows element type on iteration

func add_entity(entity: SelectComponent) -> void:
	if not selected_entities.has(entity):
		selected_entities.append(entity)


// Dictionaries remain untyped in GDScript (Dictionary has no generic parameter syntax yet).
var config_options: Dictionary = {
	"volume": 0.8,
	"sensitivity": 50.0,
}

func _get_int(key: StringName) -> int:
	var value := config_options.get(key, -1) as int  // Cast after retrieval


```

## Null Safety — `is_instance_valid()` vs `!= null`

In GDScript / Redot Engine, a freed node is **not** equal to `null`. It becomes an invalid instance that still passes the `!= null` check. Accessing its properties/methods causes a crash:

```gdscript
var cached_player: Player = %Player  // Holds reference to player scene node

func _on_player_destroyed() -> void:
	cached_player.queue_free()   // Frees the node — but cached_player is NOT null


// WRONG: This check passes even after free!
if cached_player != null and cached_player.has_method("attack"):
	pass  // CRASH if player was freed


// CORRECT: Use is_instance_valid for checking alive nodes
if is_instance_valid(cached_player) and cached_player.has_method("attack"):
	cached_player.attack()  // Safe — only runs while node is still in scene tree


```

**Rule of thumb:** Always use `is_instance_valid(node)` whenever you hold a reference to a SceneTree node that might be freed by another part of the code (e.g., via signals from other systems, or after calling `queue_free()` on it). For local variables and @onready references owned exclusively by this script, direct access without validation is safe.
