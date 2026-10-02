extends Node
class_name MapLoader

const OVERRIDE_KEYS: PackedStringArray = [
    "strength",
    "resource_type_id",
    "resource_regrowth_rate",
    "radius_cells",
    "node_count",
    "spawn_strength",
    "max_spawn_strength",
    # Bridge overlay cells carry their deck kind/land/level/end flag/rise and
    # shared piece id so a multi-level span resolves each deck at its own
    # surface on reload (bridges-walkable-surface: "Bridge entity persistence via
    # the entities array"). Absent keys keep the overlay resource's defaults.
    "bridge_kind",
    "bridge_land",
    "bridge_level",
    "bridge_end",
    "bridge_rise",
    "bridge_piece_id",
]


static func load_map_into(path: String, parent: Node) -> Array[Dictionary]:
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        push_error("MapLoader: Cannot open file: %s" % path)
        return []
    var text := file.get_as_text()
    file.close()
    var json := JSON.parse_string(text) as Dictionary
    if json == null:
        push_error("MapLoader: Invalid JSON: %s" % path)
        return []

    TerrainSystem.import_from_json(path)

    var theater_id: String = json.get("theater_id", "")
    if not theater_id.is_empty():
        TerrainCatalog.set_active_theater(theater_id)

    BoundsSystem.apply_saved_bounds(json)
    var entities: Array = json.get("entities", [])

    # Pre-warm BatchLoader with all unique model paths before entity creation.
    var model_paths: PackedStringArray = []
    for entry in entities:
        var entry_dict := entry as Dictionary
        if entry_dict == null:
            continue
        var entity_id: String = entry_dict.get("id", "")
        if entity_id.is_empty():
            continue
        var data := EntityFactory.get_entity_data(entity_id)
        if data and data.art_data and not data.art_data.model_path.is_empty():
            var mp: String = data.art_data.model_path
            if mp not in model_paths:
                model_paths.append(mp)
        # Also pre-warm deploy/undeploy target models.
        if data:
            for target_id in [data.deploys_into, data.undeploys_into]:
                if target_id.is_empty():
                    continue
                var target_data := EntityFactory.get_entity_data(target_id)
                if (
                    target_data
                    and target_data.art_data
                    and not target_data.art_data.model_path.is_empty()
                ):
                    var tp: String = target_data.art_data.model_path
                    if tp not in model_paths:
                        model_paths.append(tp)
    if not model_paths.is_empty():
        BatchLoader.preload_batch(model_paths)

    var result: Array[Dictionary] = []
    for entry in entities:
        var entry_dict := entry as Dictionary
        if entry_dict == null:
            continue
        var entity_id: String = entry_dict.get("id", "")
        if entity_id.is_empty():
            continue
        var overrides: Dictionary = {}
        for key in OVERRIDE_KEYS:
            if entry_dict.has(key):
                overrides[key] = entry_dict[key]
        var entity := EntityFactory.create_entity(entity_id, overrides)
        if not entity:
            continue

        var entry_player_id: int = entry_dict.get("player_id", -1)
        if entry_player_id >= 0:
            var stats := entity.get_node_or_null("StatsComponent") as StatsComponent
            if stats:
                stats.player_id = entry_player_id
        var house_id := resolve_house_id(entry_dict)
        if not house_id.is_empty():
            entity.set_meta("house_id", house_id)
        var cell_str: String = entry_dict.get("cell", "")
        if not cell_str.is_empty():
            var parts := cell_str.split(",")
            if parts.size() == 2:
                var cell := Vector2i(parts[0].to_int(), parts[1].to_int())
                # The map editor stores a building's cell as its footprint origin
                # and places the entity at the footprint center. Match that so
                # dock/foundation cells (derived from the entity's world
                # position) line up with where the building visually sits.
                var entity_data := EntityFactory.get_entity_data(entity_id)
                var world_pos: Vector3 = placement_position(cell, entity_data)
                if entity_data and entity_data.bridge_kind != EntityData.BridgeKind.NONE:
                    # Deck mesh sits at its walkable surface: the cell's lowest
                    # terrain corner plus the authored rise (matching
                    # BridgeComponent.get_surface_height, so a deck cell abutting a
                    # raised end/cliff does not inherit its corners). The persisted
                    # per-level `bridge_rise` override wins, so a stacked level-2
                    # deck loads above the level-1 deck. Registry-free by design:
                    # the bridge registry may not be rebuilt yet at load time.
                    var deck_rise: float = entity_data.bridge_rise
                    if overrides.has("bridge_rise"):
                        deck_rise = float(overrides["bridge_rise"])
                    world_pos.y = TerrainSystem.get_cell_min_height(cell) + deck_rise
                else:
                    var cell_data: Dictionary = TerrainSystem.get_cell(cell)
                    if not cell_data.is_empty():
                        var h: int = cell_data.get("max_height", cell_data.get("height", 0))
                        world_pos.y = float(h) * TerrainSystem.HEIGHT_STEP
                entity.position = world_pos
                var rotation_y: float = entry_dict.get("rotation_y", 0.0)
                if rotation_y != 0.0:
                    if entity_data and entity_data.entity_type != EntityData.EntityType.BUILDING:
                        _apply_rotation_with_slope(entity, rotation_y)
        var current_health: int = entry_dict.get("current_health", 0)
        if current_health > 0:
            var hp := entity.get_node_or_null("HealthComponent") as HealthComponent
            if hp:
                hp.current_health = current_health
        parent.add_child(entity)
        result.append({"key": cell_str, "node": entity, "data": entry_dict})

    if not parent.has_meta("is_map_editor"):
        _frame_camera_to_local_start(json)
    return result


## House id for a map entity entry: an explicit `house_id` wins; legacy entries
## fall back to a `player_id` below the house-list size mapped onto that house.
## Returns "" when the entry carries no house information.
static func resolve_house_id(entry: Dictionary) -> String:
    var house_id: String = entry.get("house_id", "")
    if not house_id.is_empty():
        return house_id
    var legacy_player: int = entry.get("player_id", -1)
    var house_ids := Houses.ids()
    if legacy_player >= 0 and legacy_player < house_ids.size():
        return house_ids[legacy_player]
    return ""


## Gameplay-only: frame the camera on the local player's start location.
## Maps with no `start_locations` key keep the existing default behavior and
## are left untouched. When the key is present, the local player's override is
## used if listed, otherwise the shared default cluster cell.
static func _frame_camera_to_local_start(json: Dictionary) -> void:
    if not json.has("start_locations"):
        return
    var start_data: Array = json["start_locations"] as Array
    if not start_data is Array:
        return
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    if not tree:
        return
    var bounds: Node = tree.root.get_node_or_null("BoundsSystem")
    if bounds == null:
        return
    var local_player: int = 0
    var pm: Node = tree.root.get_node_or_null("PlayerManager")
    if pm and pm.has_method("get_local_player_id"):
        local_player = pm.get_local_player_id()
    var override_cell: Vector2i = Vector2i(-999, -999)
    var found := false
    for item in start_data:
        var entry := item as Dictionary
        if entry == null:
            continue
        if int(entry.get("player_id", -1)) != local_player:
            continue
        var parts := (entry.get("cell", "") as String).split(",")
        if parts.size() == 2:
            override_cell = Vector2i(parts[0].to_int(), parts[1].to_int())
            found = true
            break
    var start: Vector2i = override_cell if found else bounds.default_start_cell(local_player)
    bounds.center_camera_on_cell(start)


## World position for a map entity. Buildings are placed at the footprint
## center (matching the editor / BuildingManager), everything else at the cell
## center.
static func placement_position(cell: Vector2i, data: EntityData) -> Vector3:
    if data and data.entity_type == EntityData.EntityType.BUILDING:
        return CellUtil.cell_origin_to_world(cell, data.foundation)
    return CellUtil.cell_to_world(cell)


static func _apply_rotation_with_slope(node: Node3D, rotation_y_deg: float) -> void:
    var yaw := deg_to_rad(rotation_y_deg)
    var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
    var normal := TerrainSystem.get_normal_at_world(node.global_position).normalized()
    if normal.is_equal_approx(Vector3.UP):
        node.rotation.y = yaw
        return
    var projected := (forward - forward.dot(normal) * normal).normalized()
    var right := projected.cross(normal).normalized()
    var basis := Basis()
    basis.x = right
    basis.y = normal
    basis.z = -projected
    node.global_transform.basis = basis
