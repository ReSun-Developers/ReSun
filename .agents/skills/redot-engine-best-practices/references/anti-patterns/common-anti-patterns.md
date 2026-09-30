# Common Anti-Patterns — Supplement Reference

This document expands on the quick-reference table in `SKILL.md` with concrete before/after examples and Redot Engine-specific gotchas. See SKILL.md's "Common Anti-Patterns" section for the primary reference list.

## 1. Polling State Flags Instead of Using Signals

```gdscript
// BAD — checks a boolean every frame in _process() even when state hasn't changed
var is_attacking: bool = false

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("attack") and not is_attacking:
		is_attacking = true
		play_attack_animation()


// GOOD — use a signal to notify when attack state begins; no polling needed
signal attack_started

func start_attack() -> void:
	if not _can_attack(): return  // Guard check, not frame-by-frame polling
	
	attack_started.emit()
	is_attacking = true
	play_attack_animation()


```

## 2. `get_parent().get_parent()` Chains — Tight Coupling

```gdscript
// BAD — fragile; breaks if scene tree structure changes by one level
func take_damage(amount: int) -> void:
	get_parent().get_parent().play_death_effect(global_position)


// GOOD — pass data through method arguments or signals. The caller knows the recipient's interface.
signal health_took_dmg(position: Vector3, amount: int)

func take_damage(amount: int) -> void:
	health_took_dmg.emit(global_position, amount)


```

## 3. Calling `load()` Inside Tight Loops or `_process()`

```gdscript
// BAD — parses scene file from disk every frame; causes severe stutter
var bullet_scene: PackedScene  // Declared but never assigned at top level!

func _physics_process(_delta: float) -> void:
	var b := load("res://scenes/particles/bullet_impact.tscn").instantiate()
	add_child(b)


// GOOD — preload the scene once; use it for all instantiations or cache in an @onready var
const BULLET_SCENE: PackedScene = preload("res://scenes/particles/bullet_impact.tscn")

func spawn_bullet(position: Vector3, direction: Vector3) -> void:
	var b := BULLET_SCENE.instantiate() as Node3D  // Instantiated and added to tree


```

## 4. String-Based Signal Calls (Typos Are Silent Bugs)

```gdscript
// BAD — "heath_changed" is a typo; no compile error, signal never fires
emit_signal("heath_changed", 50)  // Note: 'h' after 'e' in health


// GOOD — typed signal declaration + dot-call syntax catches typos at parse time (if the method name doesn't exist)
signal health_changed(amount: int)

func take_damage(amount: int) -> void:
	health_changed.emit(amount)  // Parse error if emit() is misspelled; IDE autocomplete works


```

## 5. `!= null` Check on Potentially-Freed Nodes

See **Type System** reference for the full explanation and fix (`is_instance_valid()`). This pattern appears most commonly when:
- A node holds a cached reference to another scene's node that may be destroyed by an unrelated system (e.g., CombatManager caches `Player` reference, but Player is freed via death sequence)

## 6. Heavy Logic in Autoload Singletons

```gdscript
// BAD — all game logic crammed into GameManager autoload
class_name GameManager extends Node  // Registered as Autoload

func _process(delta: float) -> void:
	for unit in get_tree().get_nodes_in_group("units"):
		unit.update_ai()          # AI runs every frame from the autoload!
	
	if Input.is_action_just_pressed("pause"):
		toggle_pause_logic()      // Direct input handling inside global singleton


// GOOD — GameManager manages state + emits signals. Actual logic lives on scene nodes.
signal game_paused(is_paused: bool)

func toggle_pause() -> void:
	get_tree().paused = !get_tree().paused
	game_paused.emit(get_tree().paused)

```

## 7. Circular Sibling References

See **Node Communication** reference for the detailed explanation and fix pattern. This most commonly manifests when two component scripts on sibling nodes hold `@export` references to each other (e.g., `WeaponMount` exports a reference to `EnemyAI`, while `EnemyAI` exports back to `WeaponMount`). The parent node should be the one that wires these relationships via method calls or signals.

## 8. Hardcoded Scene Paths as Magic Strings

```gdscript
// BAD — path typo fails at runtime; refactoring scene dirs breaks every reference
func load_stage() -> void:
	var s := load("res://scenes/stages/Level01.tscn")  // Case-sensitive, no autocomplete


// GOOD — centralize paths in a constants file or use preload for known scenes
const LEVEL_01_SCENE: PackedScene = preload("res://scenes/stages/level_01.tscn")

func load_stage() -> void:
	get_tree().change_scene_to_packed(LEVEL_01_SCENE)


```

## 9. Creating New Arrays/Dictionaries Inside `_process()` Loops

```gdscript
// BAD — allocates a new Array every frame → GC pressure → stutter spikes
var _last_frame_time := 0.0

func _physics_process(_delta: float) -> void:
	var nearby_entities := []   // New array created every physics tick!
	for e in get_tree().get_nodes_in_group("entities"):
		if global_position.distance_to(e.global_position) < detection_range:
			nearby_entities.append(e)


// GOOD — allocate once, clear and reuse
var _cached_nearby: Array[Node] = []

func _physics_process(_delta: float) -> void:
	_cached_nearby.clear()  // Reuse the same array instance
	for e in get_tree().get_nodes_in_group("entities"):
		if global_position.distance_to(e.global_position) < detection_range:
			_cached_nearby.append(e)


```

## 10. Missing `is_instance_valid()` After Async Operations

Any time you use `await`, execution pauses and another part of the scene tree may have been freed in the meantime. Always validate after resuming:

```gdscript
// BAD — player was destroyed during the wait; accessing methods crashes
func _on_player_died() -> void:
	await get_tree().create_timer(2.0).timeout  // Player might be queued_free()'d by now
	
	# Crash if player scene tree node is already freed!
	player_character.queue_free()


// GOOD — validate after await
func _on_player_died() -> void:
	await get_tree().create_timer(2.0).timeout  
	
	if is_instance_valid(player_character):  // Safe check before use
		player_character.queue_free()


```

## 11. Hardcoded Scene Paths Instead of UID-Based References

Redot 26.2 LTS includes a built-in UID-based scene reference system (PR #1144: "Add panel to view and search UIDs"). Use `load("uid://<UID>")` for robust scene references that survive directory renames, unlike string paths which break on file moves.

```gdscript
// BAD — path typo fails at runtime; refactoring scene dirs breaks every reference
var level_scene := load("res://scenes/stages/Level01.tscn")  // Case-sensitive, no autocomplete


// GOOD — UID-based references survive directory renames and are validated by the editor's UID panel
const LEVEL_01_SCENE: PackedScene = preload("uid://d2x4f8a1b3c7e9")  # Replace with actual UID from Scene > Convert to Unique Resource / Editor UID Panel


// For exported references, use @export_packed_scene or a typed scene variable in the editor inspector
@export var level_scene: PackedScene

func load_level() -> void:
	if is_instance_valid(level_scene):
		get_tree().change_scene_to_packed(level_scene)


```

## 12. Allocating Vectors/Arrays Inside Tight Loops Without Considering Engine Optimizations

Redot 26.2 LTS includes engine-level preallocation optimizations for vectors with known sizes (PR #1030). While this reduces the performance penalty of local allocations compared to upstream Godot, **the anti-pattern still applies** — repeated allocation inside `_process()` or `_physics_process()` can cause GC stutter spikes under high entity counts. The Redot optimization helps but does not eliminate the cost; preallocation remains best practice for hot paths.

```gdscript
// BAD — allocates a new Array every frame → GC pressure even with engine-level optimizations
var _last_frame_time := 0.0

func _physics_process(_delta: float) -> void:
	var nearby_entities := []   // New array created every physics tick!
	for e in get_tree().get_nodes_in_group("entities"):
		if global_position.distance_to(e.global_position) < detection_range:
			nearby_entities.append(e)


// GOOD — allocate once, clear and reuse (still preferred despite Redot's preallocation improvements)
var _cached_nearby: Array[Node] = []

func _physics_process(_delta: float) -> void:
	_cached_nearby.clear()  // Reuse the same array instance
	for e in get_tree().get_nodes_in_group("entities"):
		if global_position.distance_to(e.global_position) < detection_range:
			_cached_nearby.append(e)


```
