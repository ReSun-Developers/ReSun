# Save / Load System Patterns

Redot 26.2 LTS provides built-in resource serialization via `ResourceSaver`/`ResourceLoader`. For plain-text or cross-platform portable saves, fall back to JSON with manual deserialization.

## Approach A: Resource-Based (Recommended for Game Saves)

Uses Redot's native `.tres` format — auto-serializes all `@export` fields and enum values without any boilerplate.

### Save Data Resource Template

```gdscript
# save_data.gd
class_name SaveData extends Resource

## Persistent game state saved to disk via ResourceSaver.
## All @export fields are automatically serialized/deserialized — no manual code needed for basic types, Vector3, StringName, Array[T], etc.

@export var player_position: Vector3 = Vector3.ZERO
@export var player_rotation_degrees_y: float = 0.0
@export var current_health: int = 100
@export var max_health: int = 100
@export var inventory_ids: Array[StringName] = []
@export var current_level: StringName = "level_01"
@export var game_time_seconds: float = 0.0

# Enum values serialize automatically (stored as integer index)
enum Difficulty { EASY, NORMAL, HARD }
@export var difficulty: Difficulty = Difficulty.NORMAL

# Nested Resources — also serialized recursively if they extend Resource
class_name InventorySlot extends Resource
	@export var item_id: StringName
	@export var quantity: int = 1

var inventory_slots: Array[InventorySlot] = []


## Save to disk. Default path is user:// (sandboxed per OS).
func save_to_disk(path: String = "user://game_save.tres") -> void:
	var error := ResourceSaver.save(self, path)
	assert(error == OK, "Failed to save game data — error code %d" % error)

## Load from disk. Returns a fresh duplicate so the loaded-on-disk resource stays intact for future saves.
static func load_from_disk(path: String = "user://game_save.tres") -> SaveData:
	if not ResourceLoader.exists(path):
		return null
	
	var loaded := ResourceLoader.load(path) as SaveData
	assert(loaded != null, "Failed to parse save data from %s" % path)
	
	# Return a duplicate so in-memory mutations don't corrupt the on-disk file
	return loaded.duplicate()

```

### Usage — Saving Game State

```gdscript
func save_current_game_state(player: CharacterBody3D, inventory: Array[InventorySlot]) -> void:
	var save := SaveData.new()
	save.player_position = player.global_position
	save.current_health = player.health_component.current_health
	save.inventory_ids.assign(inventory.map(func(slot): return slot.item_id))
	save.difficulty = GameSettings.get_current_difficulty()  # External config reference
	
	# Auto-save to user:// or prompt for filename on "Save As..."
	save.save_to_disk("user://autosave.tres")

```

### Usage — Loading and Restoring State

```gdscript
func load_and_restore_game(player: CharacterBody3D) -> void:
	var save := SaveData.load_from_disk()
	if save == null:
		print("No saved game found. Starting new game.")
		return
	
	player.global_position = save.player_position
	player.health_component.current_health = save.current_health  # Trigger setter for health_changed signal emission
	
	for i in range(save.inventory_slots.size()):
		var slot := InventorySlot.new() as SaveData.InventorySlot
		slot.item_id = save.inventory_ids[i] if i < save.inventory_ids.size() else ""
		player.inventory.add_slot(slot)

```

## Approach B: JSON (Portable / Mod-Friendly Saves)

Use when you need human-readable saves, cloud-sync compatibility, or modder-friendly formats. More boilerplate but no engine dependency on `.tres` format versioning.

### Serialization Helper — Convert SaveData to/from JSON

```gdscript
# save_json_helper.gd (standalone utility module)
class_name SaveJsonHelper extends RefCounted

## Serialize a dictionary-compatible object into a formatted JSON string.
static func serialize(data: Dictionary, pretty_print: bool = true) -> String:
	var options := JSON.OPTION_ENCODE_UTF8 | (JSON.OPTIONPrettyPrint if pretty_print else 0)
	return JSON.stringify(data, "  ", false, options)

## Parse a JSON string back into structured data. Returns null on parse failure.
static func deserialize(json_string: String) -> Variant:
	var result := parse_json(json_string)
	
	if typeof(result) == TYPE_NIL:
		push_error("JSON parse failed — invalid input")
	elif typeof(result) != TYPE_DICTIONARY:
		push_error("Expected JSON object (dictionary), got %s" % type_string(typeof(result)))
	
	return result

## Convert a Resource instance to a Dictionary by reading its exported properties.
static func resource_to_dict(resource: Resource) -> Dictionary:
	var dict := {}
	for key in resource.get_property_list():
		if key.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not (key.usage & PROPERTY_USAGE_STORAGE):
			continue  # Skip non-storable keys
		
		var prop_name := key.name as String
		if not resource.has_method("get"):
			continue
			
		dict[prop_name] = resource.get(prop_name)
	
	return dict

```

### Usage — JSON Save/Load with Encryption Support

```gdscript
func save_game_json(player_pos: Vector3, health: int, level: StringName) -> void:
	var data := {
		"player_position": [player_pos.x, player_pos.y, player_pos.z],  # Arrays not natively serialized by JSON lib
		"current_health": health,
		"level_name": str(level),
	}
	
	var json_string := SaveJsonHelper.serialize(data)
	
	# Write to disk — optionally encrypt with FileAccess.open_encrypted_with_pass()
	var file := FileAccess.open("user://game_save.json", FileAccess.WRITE)
	assert(file != null, "Failed to open save file for writing")
	file.store_line(json_string)

func load_game_json() -> Dictionary:
	if not FileAccess.file_exists("user://game_save.json"):
		return {}
	
	var file := FileAccess.open("user://game_save.json", FileAccess.READ)
	assert(file != null, "Failed to open save file for reading")
	
	var json_str := file.get_line()  # Single-line JSON (our serializer writes one line)
	file.close()
	
	var parsed := SaveJsonHelper.deserialize(json_str) as Dictionary
	
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	
	# Reconstruct Vector3 from stored array
	var pos_array := parsed.get("player_position", [0.0, 0.0, 0.0]) as Array[Variant]
	parsed["player_position"] = Vector3(pos_array[0], pos_array[1], pos_array[2]) if pos_array.size() >= 3 else Vector3.ZERO
	
	return parsed

```

## Choosing the Right Approach

| Criterion | Resource (.tres) | JSON |
|-----------|------------------|------|
| Serialization boilerplate | None — `@export` fields auto-serialized | Manual dict conversion or reflection helper needed |
| Human readability | Binary-ish .tres format; not easily edited by hand | Plain text — modders and players can edit saves directly |
| Engine version compatibility | `.tres` internal structure may change between engine versions (rare but possible) | Stable as long as your `Serialize()` / `Deserialize()` code handles field additions gracefully |
| Complex nested types | Works for Resource subclasses, Enums, basic arrays/dicts | Must manually convert Vector3/Quaternion to/from JSON arrays |
| Encryption support | `FileAccess.open_encrypted_with_pass()` works on any file handle — same API as JSON approach | Same encryption option available; no difference here |

## Best Practices

1. **Always save a duplicate** of loaded resources so mutations don't corrupt the disk copy
2. **Use `user://` path prefix** for all game saves (sandboxed per OS, writable without admin)
3. **Version your saves** — add an integer field like `@export var save_version: int = 1` and check it on load to handle schema migrations
4. **Never trust loaded data blindly** — validate ranges (`assert(current_health >= 0)`), clamp values before applying, test with malformed `.tres` files
