# Coroutines and `await` Patterns

Redot 26.2 LTS supports GDScript's modern `await` keyword for asynchronous operations, replacing the deprecated `yield()` function. This document covers all practical coroutine patterns in game development contexts.

## Basic Syntax

```gdscript
func _ready() -> void:
	await get_tree().create_timer(3.0).timeout   // Wait 3 seconds — non-blocking
	print("Three seconds have passed!")


// await can be used with signals too — execution resumes when the signal emits
var _delayed_action_done := false

func start_delayed_action() -> void:
	# Signal-based wait
	await some_signal
	
	if not _delayed_action_done:
		some_other_cleanup()  // Runs after signal emitted


```

## Pattern A: Timers — Delayed Execution Without Polling

**Before (anti-pattern):** Using `_process()` to count down with a float variable.

```gdscript
// BAD — wastes every frame checking an unchanged condition
var _timer: float = 5.0

func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0:
		do_something()


```

**After:** Using `await` with a timer node or `create_timer`:

```gdscript
// GOOD — no frame-by-frame polling; execution resumes exactly when the timeout fires
func start_attack_cooldown() -> void:
	await get_tree().create_timer(attack_cooldown_seconds).timeout
	_ready_for_next_attack = true


```

## Pattern B: Waiting for Signals (Event-Driven Waits)

Use `await` to pause execution until a signal emits. This is the primary replacement for callback-based patterns:

```gdscript
class_name DeathSequence extends Node3D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var audio_stream_player_3d: AudioStreamPlayer3D = $AudioStreamPlayer3D

func play_death_sequence() -> void:
	# Wait for death animation to finish (signal-based)
	animation_player.animation_finished.connect(_finish_death, CONNECT_ONE_SHOT)
	
	await get_tree().process_frame  // Ensure one frame passes before hiding
	
	audio_stream_player_3d.play("death_impact")
	await audio_stream_player_3d.finished   # Wait for sound to complete
	queue_free()                              # Remove from scene tree


```

## Pattern C: Coordinated Multi-Object Sequences

When multiple objects need synchronized behavior (e.g., camera shake + screen flash + UI fade), use `await` with signals or timers in sequence and parallel:

### Sequential Wait Chain

```gdscript
func _on_level_complete() -> void:
	# Sequence: show victory text → pause → fade out → load next level
	
	await get_tree().create_timer(0.5).timeout     # Brief pause before showing text
	victory_label.show()
	
	await get_tree().create_timer(2.0).timeout     # Display for 2 seconds
	victory_label.hide()
	
	await get_tree().create_timer(1.0).timeout     // Fade out transition duration
	
	# Load next level (async)
	ResourceLoader.load_threaded_request("res://scenes/stages/level_02.tscn")


```

### Parallel Waits — `await` + Signal for First-to-Finish

GDScript doesn't have a built-in "wait for any of these signals" primitive, but you can achieve it with a custom signal:

```gdscript
# Wait until either the timer fires OR another condition changes first.

signal sequence_complete

var _timer_node: Timer
var _player_alive: bool = true

func start_timed_sequence() -> void:
	_timer_node = get_tree().create_timer(10.0)
	
	var wait_futures := [
		await _timer_node.timeout,           # Waits for timer to complete (returns null on timeout)
	]
	
	if not _player_alive:
		wait_futures.append(await player_died_signal)  // Wait for death signal if it's alive
	
	# First awaited future completes → execution continues here
	on_sequence_ended()


```

## Pattern D: Async Resource Loading with Progress Feedback

Combine `await` with threaded resource loading to avoid frame stutter during level transitions.

**Frame-pacing note:** Redot 26.2 LTS re-implements core and GDScript VM multithreading (PR #1121), improving await performance over upstream Godot 4.x. The engine-level preallocation optimizations also reduce GC pressure on repeated coroutine invocations. However, the official recommendation remains to poll `load_threaded_get_status()` across frames rather than in tight loops — our pattern below yields one frame per iteration via `await get_tree().process_frame`, which satisfies this requirement.

```gdscript
var _load_progress_value: float = 0.0

func load_next_level_async(level_path: String, progress_callback: Callable) -> void:
	# Kick off background thread load
	ResourceLoader.load_threaded_request(level_path)
	
	# Poll until loaded — non-blocking yield to the main loop between polls (one frame per iteration)
	await _poll_load_progress(progress_callback, level_path)
	
	var scene := ResourceLoader.load_threaded_get(level_path) as PackedScene
	
	if is_instance_valid(scene):
		get_tree().change_scene_to_packed(scene)


func _poll_load_progress(callback: Callable, resource_path: String) -> void:
	while true:
		match ResourceLoader.load_threaded_get_status(resource_path):
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await get_tree().process_frame  // Yield one frame, then check again (frame-paced polling per Redot docs)
				callback.call(0.3)              # Fake progress — use real metrics if available
			
			ResourceLoader.THREAD_LOADED:
				callback.call(1.0)
				return
			
			ResourceLoader.THREAD_LOAD_FAILED:
				push_error("Failed to load level scene")
				get_tree().quit()


```

## Important Rules for `await` in Redot GDScript

| Rule | Detail |
|------|--------|
| **Only top-level functions can await** | You cannot use `await` inside a nested anonymous function or lambda. If you need to, declare the inner logic as its own method and call it with `await`. |
| **Avoid awaiting in `_process()` / `_physics_process()` directly** — these methods are called every frame by the engine. An `await` here would require the entire function to be re-entered on each resume, which is valid but can cause subtle bugs if you have state that persists across resumes. Prefer using signals or timers instead of awaiting inside these loops. |
| **Always check `is_instance_valid()` after an await** — time passes during any awaited operation; nodes may have been freed in the meantime (e.g., player died while waiting for a death animation). |
| **`await tree.process_frame` is your friend** — use it to defer one frame of work without creating timer objects or polluting `_process()`. Common pattern: `await get_tree().process_frame; do_cleanup()` |
