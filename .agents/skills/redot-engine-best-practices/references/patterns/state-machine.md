# State Machine Pattern

Two approaches for managing entity state in Redot 26.2 LTS GDScript. Choose based on complexity.

## Approach A: Enum-Match (Simple Entities)

Best for entities that only need branching logic — no per-state lifecycle hooks, visual transitions, or nested sub-states.

```gdscript
class_name SimpleStateMachine extends Node3D

enum State { IDLE, WALKING, ATTACKING }

@export var move_speed: float = 5.0
@export var attack_damage: int = 10
@export var attack_cooldown: float = 1.0

var current_state: State = State.IDLE
var _attack_timer: float = 0.0

func _physics_process(delta: float) -> void:
	match current_state:
		State.IDLE:
			_handle_idle(delta)
		State.WALKING:
			_handle_walking(delta)
		State.ATTACKING:
			_handle_attacking(delta)

func _handle_idle(_delta: float) -> void:
	if Input.is_action_just_pressed("attack"):
		change_state(State.ATTACKING)
	elif Input.get_vector("left", "right", "forward", "backward") != Vector2.ZERO:
		change_state(State.WALKING)

func _handle_walking(delta: float) -> void:
	var direction := Input.get_vector("left", "right", "forward", "backward").normalized()
	global_position.x += direction.x * move_speed * delta
	
	if not Input.is_anything_pressed():
		change_state(State.IDLE)

func change_state(new_state: State) -> void:
	current_state = new_state
```

Use this when the entity has 3-5 states, each state is a few lines of logic, and there are no visual transitions.

## Approach B: Component-Based (Complex Entities)

Best for entities with rich per-state behavior — animations, audio cues, nested sub-states, or multiple concurrent behaviors. Uses the component pattern already established in your project (`HealthComponent`, `SelectComponent`).

### Base State Script

```gdscript
# state.gd
class_name State extends Node3D
## Base class for all states in a StateMachine hierarchy.
## Each state is a child node of its parent StateMachine.

var _machine: StateMachine  # Set by the parent on registration

func enter(_msg: Dictionary = {}) -> void:
	"""Called when this state becomes active."""
	pass

func exit() -> void:
	"""Called before transitioning away from this state."""
	pass

func update(delta: float) -> void:
	"""Override for logic that runs every _process frame while in this state."""
	pass

func physics_update(delta: float) -> void:
	"""Override for logic that runs every _physics_process frame (movement, collision)."""
	pass

func handle_input(event: InputEvent) -> void:
	"""Override to intercept input events specific to this state."""
	pass
```

### State Machine Controller

```gdscript
# state_machine.gd
class_name StateMachine extends Node3D
## Manages child State nodes. Children are registered automatically in _ready().

signal state_changed(previous_state: StringName, new_state: StringName)

@export var initial_state: State = null

var current_state: State = null
var states: Dictionary  # name -> State mapping

func _enter_tree() -> void:
	process_mode = Node3D.PROCESS_MODE_DISABLED  # Disabled until a state is active

func _ready() -> void:
	_register_children_as_states()
	if initial_state and current_state == null:
		current_state.process_mode = Node3D.PROCESS_MODE_INHERIT
		initial_state.enter()

func _register_children_as_states() -> void:
	for child in get_children():
		if child is State:
			states[child.name] = child
			child._machine = self
			child.process_mode = Node3D.PROCESS_MODE_DISABLED  # Start disabled

# Lifecycle hooks — delegate to current active state only
func _process(delta: float) -> void:
	if current_state and has_process_override():
		current_state.update(delta)

func _physics_process(delta: float) -> void:
	if current_state and has_physics_override():
		current_state.physics_update(delta)

func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)

# Public API for transitioning between states
func transition_to(state_name: StringName, msg: Dictionary = {}) -> void:
	var new_state := states.get(state_name) as State
	assert(new_state != null, "State '%s' not found. Available: %s" % [state_name, ", ".join(states.keys())])

	if current_state == new_state:
		return  # No-op — already in this state
	
	var previous_state := current_state
	
	current_state = new_state
	state_changed.emit(previous_state.name if previous_state else "", state_name)
	
	# Deactivate old state (stop processing)
	if previous_state != null and has_process_override():
		previous_state.process_mode = Node3D.PROCESS_MODE_DISABLED
	elif previous_state != null:
		previous_state.exit()

	# Activate new state
	new_state.process_mode = Node3D.PROCESS_MODE_INHERIT
	new_state.enter(msg)


## --- Helper: check if a node overrides specific lifecycle methods ---

func has_process_override() -> bool:
	return current_state.has_method("update") and not (current_state.update is State.update)

func has_physics_override() -> bool:
	return current_state.has_method("physics_update") and not (current_state.physics_update is State.physics_update)
```

### Concrete Example — Enemy AI with States

```gdscript
# enemy_patrol.gd
class_name EnemyPatrol extends State

@export var patrol_speed: float = 3.0
@export var detection_radius: float = 15.0

var _patrol_target: Vector3
var _enemy_character: CharacterBody3D


func enter(_msg: Dictionary = {}) -> void:
	_enemy_character = get_parent().get_node_or_null("Character") as CharacterBody3D
	if not has_path_to_patrol_target():
		set_new_patrol_target()

func physics_update(delta: float) -> void:
	var direction := (_patrol_target - _enemy_character.global_position).normalized() * patrol_speed
	
	# Check for player in detection radius — switch to combat if found
	if is_player_detected():
		state_machine.transition_to("Combat")
	else:
		_enemy_character.move_and_slide(direction)

func set_new_patrol_target() -> void:
	var angle := randf_range(0, TAU)
	_patrol_target = Vector3(cos(angle), 0, sin(angle)) * detection_radius


## --- Concrete Example — Enemy Combat State ---

# enemy_combat.gd
class_name EnemyCombat extends State

@export var attack_damage: int = 15
@export var max_attack_range: float = 4.0
@export var attack_cooldown: float = 2.0

var _attack_timer: float = 0.0


func enter(_msg: Dictionary = {}) -> void:
	_attack_timer = attack_cooldown  # Force a cooldown before first attack in this session

func physics_update(delta: float) -> void:
	var enemy := get_parent() as CharacterBody3D
	
	if not is_player_in_range(enemy):
		state_machine.transition_to("Patrol")
	else:
		attack_timer -= delta
		
		if _attack_timer <= 0:
			_attack_target(enemy.global_position)
			_attack_timer = attack_cooldown


func _attack_target(target_pos: Vector3) -> void:
	print("Attacked target at %s" % str(target_pos))

```

### When to Use Which Approach

| Criterion | Enum-Match (A) | Component-Based (B) |
|-----------|-----------------|---------------------|
| Max states | 5–8 | Any number, hierarchical via nested StateMachine children |
| Per-state visual/audio effects | Not recommended — keep logic simple | Native: each state node can hold its own AnimationPlayer/AudioStreamPlayer nodes as children |
| Code size per state | ~10 lines max | Independent script files; unlimited complexity per file |
| Composability | No | Yes — sub-StateMachine child nodes for complex behaviors (e.g., VehicleStateMachine → DrivingState with nested SteeringBehavior) |
| Debugging visibility in scene tree | State name is a variable | Each state appears as a named node in the Scene Tree inspector — easy to inspect at runtime |
