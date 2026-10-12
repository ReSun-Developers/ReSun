class_name SpatialHash extends Node


## Composite snapshot of a cell's occupancy, returned by `get_cell_occupancy`.
## Permanent facts (building/bib/resource/terrain_buildable) are ground-only;
## momentary facts (units/blocked/moving/shared_count/reserved) are level-scoped.
## `blocked`/`moving`/`shared_count` partition `units` by movement state and
## sharing. Buildings and resource overlays never appear in `units`.
class CellOccupancy:
    extends RefCounted
    var cell: Vector2i = Vector2i.ZERO
    var level: int = 0
    var building: bool = false
    var bib: bool = false
    var resource: bool = false
    var terrain_buildable: bool = false
    var units: Array[Node3D] = []
    var blocked: bool = false
    var moving: bool = false
    var shared_count: int = 0
    var reserved: bool = false


static var instance: SpatialHash

var _grid: Dictionary = {}
var _blocked_cells: Dictionary = {}
var _building_cells: Dictionary = {}
var _bib_cells: Dictionary = {}
var _reserved: Dictionary = {}
var _resource_cells: Dictionary = {}
var _shared_cell_counts: Dictionary = {}
var _ice_cells: Dictionary = {}
## Live bridge deck cells: cell_level_key -> {surface_height, bridge_kind, is_end,
## piece_id, level}. Rebuilt from the "bridge" group each `rebuild()` (see
## `_bridge_cells` note there).
var _bridge_cells: Dictionary = {}
## Pooled per-entity entries (entity root -> entry dict). Shared with `_grid`.
var _entry_map: Dictionary = {}
var _rebuild_pending := false
## Perf-guard counter: group scans performed by the rebuild path. The per-frame
## `_reconcile()` must never increment it (test/unit/test_perf_guard.gd asserts
## this). ponytail: only catches scans routed through these scan sites.
var perf_group_scans: int = 0
## Perf-guard counter: cell recomputes (world_to_cell + cell_key) performed by the
## per-frame `_reconcile()`. Idle, unmoved entries must never increment it
## (test/unit/test_perf_guard.gd asserts this). ponytail: only catches recomputes
## routed through the position-changed branch.
var perf_reconcile_recomputes: int = 0
## Monotonic grid-generation counter. Bumped on every `rebuild()`, which
## replaces the `_grid` entry arrays. Consumers caching references to those
## arrays (MovementController's frame-scoped hood) must invalidate when this
## changes, or they read stale arrays whose entries may reference freed nodes.
var grid_generation: int = 0
## Perf-guard counter: `get_entries` invocations. The movement avoidance scan
## must fetch the 3×3 hood once per unique cell per frame (not 9× per unit),
## asserted by test/unit/test_movement_frame_cache.gd. ponytail: test-only
## instrumentation; a single int increment per call.
var perf_get_entries_calls: int = 0


func _enter_tree() -> void:
    instance = self


func _ready() -> void:
    get_tree().node_added.connect(_on_node_added)
    get_tree().node_removed.connect(_on_node_removed)


func _on_node_added(node: Node) -> void:
    if _is_membership_node(node):
        _rebuild_pending = true


func _on_node_removed(node: Node) -> void:
    if _is_membership_node(node):
        _rebuild_pending = true


func _is_membership_node(node: Node) -> bool:
    if node.is_in_group("entities") or node.is_in_group("ice") or node.is_in_group("bridge"):
        return true
    var parent := node.get_parent()
    return (
        parent != null
        and (
            parent.is_in_group("entities")
            or parent.is_in_group("ice")
            or parent.is_in_group("bridge")
        )
    )


func _physics_process(_delta: float) -> void:
    if _rebuild_pending:
        rebuild()
    else:
        _reconcile()


func rebuild() -> void:
    grid_generation += 1
    _grid.clear()
    _blocked_cells.clear()
    _shared_cell_counts.clear()
    _ice_cells.clear()
    var old_bridge_keys: Dictionary = {}
    for key in _bridge_cells:
        old_bridge_keys[key] = true
    _bridge_cells.clear()
    _entry_map.clear()
    # ponytail: ice spawned mid-game by EntityFactory._add_ice_component only
    # joins _ice_cells on the next membership rebuild, so a freshly spawned ice
    # block has a short window without passability override / weight damage. Map
    # ice is scene-placed before the first rebuild, so this only matters for
    # runtime ice spawning.
    perf_group_scans += 1
    for ice in get_tree().get_nodes_in_group("ice"):
        var ice_root := ice as Node3D
        if not is_instance_valid(ice_root):
            continue
        var ice_key: int = CellUtil.cell_key(CellUtil.world_to_cell(ice_root.global_position))
        if not _ice_cells.has(ice_key):
            _ice_cells[ice_key] = []
        _ice_cells[ice_key].append(ice_root)
    # ponytail: a bridge spawned/removed mid-frame enters/leaves _bridge_cells on
    # the next membership rebuild; static map bridges are placed before the first
    # rebuild, so this only affects runtime bridge destruction (#250).
    perf_group_scans += 1
    for bridge in get_tree().get_nodes_in_group("bridge"):
        var bridge_root := bridge as Node3D
        if not is_instance_valid(bridge_root):
            continue
        var bridge_data := _read_bridge_cell_data(bridge_root)
        if bridge_data.is_empty():
            continue
        var bridge_cell := CellUtil.world_to_cell(bridge_root.global_position)
        var bridge_level: int = int(bridge_data.get("level", 1))
        _bridge_cells[CellUtil.cell_level_key(bridge_cell, bridge_level)] = bridge_data
    if _bridge_cell_keys_changed(old_bridge_keys):
        _on_bridge_cells_changed()
    perf_group_scans += 1
    for entity in get_tree().get_nodes_in_group("entities"):
        # ponytail: scene-placed units add SelectComponent (Node) to group,
        # not the root Node3D. Resolve root for MC lookup + position.
        var entity_root := entity as Node3D
        if not entity_root:
            entity_root = entity.get_parent() as Node3D
        if not is_instance_valid(entity_root) or entity_root.is_queued_for_deletion():
            continue
        var mc := entity_root.get_node_or_null("MovementController") as MovementController
        var stats := entity_root.get_node_or_null("StatsComponent") as StatsComponent
        var cell := CellUtil.world_to_cell(entity_root.global_position)
        var key := CellUtil.cell_key(cell)
        var etype: int = stats.entity_type if stats else -1
        var pid: int = stats.player_id if stats else -1
        var state: int = mc._state if mc else -1
        var shares: bool = mc.shares_cell() if mc else false
        var entry_level: int = mc._surface_level if mc else 0
        var entry := {
            "node": entity_root,
            "mc": mc,
            "stats": stats,
            "entity_type": etype,
            "player_id": pid,
            "cell_key": key,
            "level": entry_level,
            "state": state,
            "shares": shares,
            "last_x": entity_root.global_position.x,
            "last_z": entity_root.global_position.z,
        }
        _entry_map[entity_root] = entry
        _add_entry_to_grid(entry, key)
        # ponytail: only count IDLE sharers. Moving sharers can stack
        # beyond capacity transiently, but crush clears them. Counting
        # MOVING would block pathfinding for all cells with moving sharers.
        if mc and state == MovementController.State.IDLE:
            var level_key := CellUtil.cell_level_key(cell, entry_level)
            if shares:
                _shared_cell_counts[level_key] = _shared_cell_counts.get(level_key, 0) + 1
            else:
                _blocked_cells[level_key] = true
    _rebuild_pending = false


## Allocation-free drift correction. Reads cached node/MC refs and only mutates
## the grid when a cell or state actually changed. No group scans, no node
## lookups, no per-entity dictionary allocations. Entries whose position has not
## changed since the last reconcile short-circuit on a cached-position compare,
## skipping the `world_to_cell`/`cell_key` recompute entirely.
func _reconcile() -> void:
    for entity_root in _entry_map:
        var entry: Dictionary = _entry_map[entity_root]
        var node: Node3D = entry["node"]
        var mc: MovementController = entry["mc"]
        var state: int = -1
        var shares := false
        var level: int = 0
        if mc and is_instance_valid(mc):
            state = mc._state
            shares = mc.shares_cell()
            level = mc._surface_level
        var pos: Vector3 = node.global_position
        var last_x: float = entry["last_x"]
        var last_z: float = entry["last_z"]
        var cached_key: int = entry["cell_key"]
        var cached_level: int = int(entry.get("level", 0))
        # Short-circuit: an unchanged position implies an unchanged cell (the only
        # continuous position writer, MovementController, mutates in place; spawn
        # and Deploy set position before add_child, which triggers a rebuild).
        # Unchanged position + unchanged state/shares/level => nothing to reconcile.
        if (
            pos.x == last_x
            and pos.z == last_z
            and state == entry["state"]
            and shares == entry["shares"]
            and level == cached_level
        ):
            continue
        var key: int
        if pos.x == last_x and pos.z == last_z:
            key = cached_key
        else:
            key = CellUtil.cell_key(CellUtil.world_to_cell(pos))
            perf_reconcile_recomputes += 1
        entry["last_x"] = pos.x
        entry["last_z"] = pos.z
        if (
            key == cached_key
            and state == entry["state"]
            and shares == entry["shares"]
            and level == cached_level
        ):
            continue
        var cached_level_key := CellUtil.cell_level_key(_level_key_cell(cached_key), cached_level)
        var level_key := CellUtil.cell_level_key(_level_key_cell(key), level)
        var was_blocking: bool = (
            entry["state"] == MovementController.State.IDLE and not entry["shares"]
        )
        var was_sharing: bool = entry["state"] == MovementController.State.IDLE and entry["shares"]
        _remove_entry_from_grid(entry, cached_key)
        if was_sharing:
            _decrement_shared(cached_level_key)
        elif was_blocking and not _has_blocking_entity(cached_key, cached_level):
            # _blocked_cells is a set (key -> true), so only erase when the
            # last blocking occupant on this level leaves.
            _blocked_cells.erase(cached_level_key)
        entry["cell_key"] = key
        entry["level"] = level
        entry["state"] = state
        entry["shares"] = shares
        _add_entry_to_grid(entry, key)
        if state == MovementController.State.IDLE:
            if shares:
                _shared_cell_counts[level_key] = _shared_cell_counts.get(level_key, 0) + 1
            else:
                _blocked_cells[level_key] = true


func _add_entry_to_grid(entry: Dictionary, key: int) -> void:
    var arr: Variant = _grid.get(key)
    if arr == null:
        arr = []
        _grid[key] = arr
    arr.append(entry)


func _remove_entry_from_grid(entry: Dictionary, key: int) -> void:
    var arr: Variant = _grid.get(key)
    if arr == null:
        return
    arr.erase(entry)
    if arr.is_empty():
        _grid.erase(key)


func _decrement_shared(key: int) -> void:
    var count: int = int(_shared_cell_counts.get(key, 0)) - 1
    if count <= 0:
        _shared_cell_counts.erase(key)
    else:
        _shared_cell_counts[key] = count


## True when at least one entry on the cell at `level` still blocks it
## (IDLE + non-shaver). Level-scoped: a deck blocker does not keep the ground
## cell blocked, and vice versa.
func _has_blocking_entity(key: int, level: int) -> bool:
    var arr: Variant = _grid.get(key)
    if arr == null:
        return false
    for entry in arr:
        if (
            entry["state"] == MovementController.State.IDLE
            and not entry["shares"]
            and int(entry.get("level", 0)) == level
        ):
            return true
    return false


func get_entries(cell: Vector2i, level: int = -1) -> Array:
    perf_get_entries_calls += 1
    var arr: Array = _grid.get(CellUtil.cell_key(cell), [])
    if level < 0 or arr.is_empty():
        return arr
    var filtered: Array = []
    for entry in arr:
        if int(entry.get("level", 0)) == level:
            filtered.append(entry)
    return filtered


## Decodes the cell half of a `CellUtil.cell_level_key`.
static func _level_key_cell(key: int) -> Vector2i:
    var base := key & 0xFFFFFFFF
    var x := ((base >> 16) & 0xFFFF) - CellUtil.CELL_KEY_OFFSET
    var y := (base & 0xFFFF) - CellUtil.CELL_KEY_OFFSET
    return Vector2i(x, y)


## Ice entities (breakable surfaces) occupying a cell.
func get_ice_entities_on_cell(cell: Vector2i) -> Array:
    return _ice_cells.get(CellUtil.cell_key(cell), [])


## True when a live (intact) ice entity occupies the cell.
func has_intact_ice_on_cell(cell: Vector2i) -> bool:
    for ice in _ice_cells.get(CellUtil.cell_key(cell), []):
        if not is_instance_valid(ice):
            continue
        var hc := (ice as Node3D).get_node_or_null("HealthComponent") as HealthComponent
        if hc and hc.current_health > 0:
            return true
    return false


## Bridge deck metadata on a cell. `level >= 0` reads that exact deck level;
## `level == -1` returns the lowest-level (ground-most) deck entry, else {}.
func get_bridge_cell(cell: Vector2i, level: int = -1) -> Dictionary:
    if level >= 0:
        return _bridge_cells.get(CellUtil.cell_level_key(cell, level), {})
    var levels: Array[int] = get_bridge_levels(cell)
    if levels.is_empty():
        return {}
    return _bridge_cells.get(CellUtil.cell_level_key(cell, levels[0]), {})


## True when a bridge deck covers the cell. `level == -1` means any level on the
## cell (legacy behavior); otherwise the exact level. The any-level probe scans
## the small deck registry so direct-write test fixtures stay valid without a
## separate index; level 0 is `cell_key`, level N is `cell_level_key`.
func has_bridge_on_cell(cell: Vector2i, level: int = -1) -> bool:
    if level >= 0:
        return _bridge_cells.has(CellUtil.cell_level_key(cell, level))
    var base: int = CellUtil.cell_key(cell)
    for key in _bridge_cells:
        if (int(key) & 0xFFFFFFFF) == base:
            return true
    return false


## Sorted ascending deck levels present on a cell (empty when none). A
## directly-written legacy level-0 entry reads back as level 0.
func get_bridge_levels(cell: Vector2i) -> Array[int]:
    var levels: Array[int] = []
    var base: int = CellUtil.cell_key(cell)
    for key in _bridge_cells:
        if (int(key) & 0xFFFFFFFF) == base:
            levels.append(int(key) >> 32)
    levels.sort()
    return levels


## Metadata for every deck level on a cell, lowest level first.
func get_bridge_surfaces(cell: Vector2i) -> Array[Dictionary]:
    var surfaces: Array[Dictionary] = []
    for level in get_bridge_levels(cell):
        var data: Variant = _bridge_cells.get(CellUtil.cell_level_key(cell, level))
        if data is Dictionary:
            surfaces.append(data)
    return surfaces


## Bridge cell metadata published by a bridge entity, or {} when no publisher is
## present or its data is malformed (missing required keys). Reads the entity's
## own `get_bridge_cell_data()` when it has one (stub/legacy), otherwise the
## `BridgeComponent` child's method.
func _read_bridge_cell_data(node: Node3D) -> Dictionary:
    var source: Variant = null
    if node.has_method("get_bridge_cell_data"):
        source = node.get_bridge_cell_data()
    else:
        var component := node.get_node_or_null("BridgeComponent")
        if component and component.has_method("get_bridge_cell_data"):
            source = component.get_bridge_cell_data()
    if not (source is Dictionary):
        return {}
    var data: Dictionary = source
    if not (data.has("surface_height") and data.has("is_end") and data.has("piece_id")):
        return {}
    var level := 1
    if data.has("level"):
        var raw_level: int = int(data["level"])
        if raw_level > 0:
            level = raw_level
    # Spec "Stack over max height refused": a deck at or above MAX_HEIGHT is
    # refused here — the registry is the single source of deck surfaces, so no
    # surface is created for the cell and every consumer sees ground only.
    if level >= TerrainSystem.MAX_HEIGHT:
        return {}
    return {
        "surface_height": float(data["surface_height"]),
        "bridge_kind": int(data.get("bridge_kind", 0)),
        "land": String(data.get("land", "road")),
        "is_end": bool(data["is_end"]),
        "piece_id": String(data["piece_id"]),
        "level": level,
    }


func _bridge_cell_keys_changed(old_keys: Dictionary) -> bool:
    if old_keys.size() != _bridge_cells.size():
        return true
    for key in _bridge_cells:
        if not old_keys.has(key):
            return true
    return false


## A bridge register/unregister changes per-cell walkable height, so any cached
## height snapshot and any batch-lifetime path-cost cache are stale. Invalidates
## the terrain height snapshot and bumps the Pathfinder world generation (the same
## API blocker/building changes use via SelectionManager.request_move).
func _on_bridge_cells_changed() -> void:
    var terrain := _resolve_terrain_system()
    if terrain and terrain.has_method("invalidate_height_snapshot"):
        terrain.invalidate_height_snapshot()
    Pathfinder.bump_world_generation()


func _resolve_terrain_system() -> Node:
    var tree: SceneTree = get_tree()
    if tree == null:
        return null
    return tree.root.get_node_or_null("TerrainSystem")


## Level-scoped blocked set for pathfinding. Returns only the blockers on
## `level` (keys are `cell_level_key`, `cell_key` at level 0) plus the building
## footprint at level 0 — buildings never sit on a deck. The no-arg call is
## byte-identical to the pre-level behavior for ground maps.
func get_blocked_cells(level: int = 0) -> Dictionary:
    var result: Dictionary = {}
    for key in _blocked_cells:
        if (int(key) >> 32) == level:
            result[key] = true
    if level == 0:
        for key in _building_cells:
            result[key] = true
    return result


func all_entries() -> Array:
    var result: Array = []
    for key in _grid:
        result.append_array(_grid[key])
    return result


func is_cell_blocked(cell: Vector2i, level: int = 0) -> bool:
    return _blocked_cells.has(CellUtil.cell_level_key(cell, level))


func get_shared_cell_count(cell: Vector2i, level: int = 0) -> int:
    return _shared_cell_counts.get(CellUtil.cell_level_key(cell, level), 0)


func is_cell_full_for_shared(cell: Vector2i, level: int = 0) -> bool:
    return get_shared_cell_count(cell, level) >= CellSubPositions.get_slot_count()


## Level-scoped shared (sharing-unit) cells with at least one occupant. Keys are
## `cell_key` at level 0 (legacy callers) and `cell_level_key` for decks.
func get_shared_cells(level: int = 0) -> Dictionary:
    var result: Dictionary = {}
    for key in _shared_cell_counts:
        if _shared_cell_counts[key] <= 0:
            continue
        if (int(key) >> 32) == level:
            result[key] = true
    return result


func get_crusher_blocking_cells(player_id: int) -> Dictionary:
    var result: Dictionary = {}
    for key in _shared_cell_counts:
        if _shared_cell_counts[key] <= 0:
            continue
        # Crushers are ground vehicles: deck (level > 0) sharers do not block them.
        if (int(key) >> 32) != 0:
            continue
        var entries: Array = _grid.get(CellUtil.cell_key(_level_key_cell(key)), [])
        for entry in entries:
            if not is_instance_valid(entry["node"]):
                continue
            var entry_type: int = entry["entity_type"]
            if entry_type != EntityData.EntityType.INFANTRY:
                continue
            var entry_pid: int = entry["player_id"]
            if player_id < 0 or entry_pid == -1 or not PlayerManager.is_enemy(player_id, entry_pid):
                result[key] = true
                break
            var entry_node: Node3D = entry["node"]
            var entry_stats := entry_node.get_node_or_null("StatsComponent") as StatsComponent
            if entry_stats and not entry_stats.crushable:
                result[key] = true
                break
    return result


func get_crushable_enemies_on_cell(cell: Vector2i, player_id: int) -> Array:
    var result: Array = []
    var entries: Array = _grid.get(CellUtil.cell_key(cell), [])
    for entry in entries:
        if not is_instance_valid(entry["node"]):
            continue
        var entry_node: Node3D = entry["node"]
        var entry_pid: int = entry["player_id"]
        var entry_type: int = entry["entity_type"]
        if entry_type != EntityData.EntityType.INFANTRY:
            continue
        if entry_pid == -1 or player_id < 0 or not PlayerManager.is_enemy(player_id, entry_pid):
            continue
        var entry_stats := entry_node.get_node_or_null("StatsComponent") as StatsComponent
        if entry_stats and entry_stats.crushable:
            result.append(entry_node)
    return result


## Nearest entity a ground shot can hit: the occupant of `cell` at any level
## that has a HealthComponent and a combat entity_type (infantry, vehicle,
## aircraft, building), closest to `impact_pos` in 3D. Only the shooter is
## exempt — allies and neutrals qualify, matching how a blast in the original
## spares the object credited with the shot. Terrain and overlay entities are
## never occupants; bridge, ice and tiberium go through find_cell_overlays().
func resolve_cell_victim(cell: Vector2i, impact_pos: Vector3, shooter: Node3D) -> Node3D:
    var best: Node3D = null
    var best_dist := INF
    for entry in _grid.get(CellUtil.cell_key(cell), []):
        var entry_node: Node3D = entry["node"]
        if not is_instance_valid(entry_node) or entry_node == shooter:
            continue
        var entry_type: int = entry["entity_type"]
        if (
            entry_type != EntityData.EntityType.INFANTRY
            and entry_type != EntityData.EntityType.VEHICLE
            and entry_type != EntityData.EntityType.AIRCRAFT
            and entry_type != EntityData.EntityType.BUILDING
        ):
            continue
        if entry_node.get_node_or_null("HealthComponent") == null:
            continue
        var dist := entry_node.global_position.distance_squared_to(impact_pos)
        if dist < best_dist:
            best_dist = dist
            best = entry_node
    if best == null:
        # A building is indexed in _grid only at its centre cell, so a shot at
        # an edge cell of a large structure finds nothing above. Its footprint
        # registry is keyed by every cell it covers.
        var footprint: Variant = _building_cells.get(CellUtil.cell_key(cell))
        var building := footprint as Node3D
        if (
            building != null
            and is_instance_valid(building)
            and building != shooter
            and building.get_node_or_null("HealthComponent") != null
        ):
            best = building
    return best


## Overlays in `cell` a warhead may damage: a destructible LOW normal bridge
## span, ice (only present while the `breakable_ice` feature is on) and tiberium
## — each gated on the warhead flag that maps to it in the original. `exclude`
## is the shot's own entity target, which the caller has already damaged.
##
## None of these are `_grid` entries: OVERLAY and 1x1 TERRAIN entities never
## join the "entities" group, so they are read from the registries that do know
## about them — `_ice_cells` (keyed by cell), the small "bridge" group, and the
## `_resource_cells` probe that gates the "resources" scan.
func find_cell_overlays(cell: Vector2i, warhead: WarheadData, exclude: Node3D = null) -> Array:
    var result: Array = []
    if warhead == null or not is_inside_tree():
        return result
    # A warhead that cannot hurt walls/ice or tiberium can damage no overlay, so
    # skip the registry scans entirely — most shots carry such a warhead.
    if not warhead.can_damage_walls and not warhead.can_damage_tiberium:
        return result
    var tree := get_tree()
    if tree == null:
        return result
    for bridge in tree.get_nodes_in_group("bridge"):
        var bridge_node := bridge as Node3D
        if not is_instance_valid(bridge_node) or bridge_node == exclude:
            continue
        if CellUtil.world_to_cell(bridge_node.global_position) != cell:
            continue
        if _overlay_damage_allowed(bridge_node, warhead):
            result.append(bridge_node)
    for ice in _ice_cells.get(CellUtil.cell_key(cell), []):
        var ice_node := ice as Node3D
        if not is_instance_valid(ice_node) or ice_node == exclude:
            continue
        if _overlay_damage_allowed(ice_node, warhead):
            result.append(ice_node)
    # Tiberium is an OVERLAY entity, so only the boolean resource-cell index
    # knows the cell has any. One dictionary probe keeps the common empty-cell
    # shot O(1).
    if warhead.can_damage_tiberium and has_resource_cell(cell):
        for resource in tree.get_nodes_in_group("resources"):
            var resource_node := resource as Node3D
            if not is_instance_valid(resource_node) or resource_node == exclude:
                continue
            if CellUtil.world_to_cell(resource_node.global_position) != cell:
                continue
            if _overlay_damage_allowed(resource_node, warhead):
                result.append(resource_node)
    return result


## True when `node` is a cell overlay — a bridge span, ice sheet or resource —
## rather than a combat entity. Overlay damage belongs to the warhead-gated
## `find_cell_overlays()` pass, so direct shots must not damage one through the
## entity path (a tiberium shot only lands when `can_damage_tiberium` is set).
static func is_overlay_entity(node: Node3D) -> bool:
    if node == null:
        return false
    return (
        node.get_node_or_null("BridgeComponent") != null
        or node.get_node_or_null("IceComponent") != null
        or node.get_node_or_null("ResourceComponent") != null
    )


## Per-overlay warhead gate. `can_damage_walls` is the game's Wall=yes: it
## covers both bridge spans and ice cracking in the original. Tiberium has its
## own flag. Ice is only reachable while its IceComponent exists, which
## EntityFactory attaches only when the `breakable_ice` feature is on.
func _overlay_damage_allowed(node: Node3D, warhead: WarheadData) -> bool:
    var bridge := node.get_node_or_null("BridgeComponent")
    if bridge != null:
        if not warhead.can_damage_walls:
            return false
        var data: Variant = bridge.call("get_bridge_cell_data")
        if not data is Dictionary or (data as Dictionary).is_empty():
            return false
        var bridge_data := data as Dictionary
        return (
            int(bridge_data["bridge_kind"]) == EntityData.BridgeKind.LOW
            and not bool(bridge_data["is_end"])
        )
    if node.get_node_or_null("IceComponent") != null:
        return warhead.can_damage_walls
    if node.get_node_or_null("ResourceComponent") != null:
        var resource := node.get_node_or_null("ResourceComponent")
        return warhead.can_damage_tiberium and resource.get("resource_category") == "tiberium"
    return false


## True when any mobile entity occupies the cell. `level >= 0` restricts to that
## surface; the no-level call resolves to ground (level 0), so ground building,
## deploy, and transport queries ignore a deck occupant above. Pass `level == -1`
## explicitly for the any-level query.
func is_any_entity_on_cell(cell: Vector2i, level: int = 0) -> bool:
    var entries: Array = _grid.get(CellUtil.cell_key(cell), [])
    for entry in entries:
        if entry["mc"] == null:
            continue
        if level >= 0 and int(entry.get("level", 0)) != level:
            continue
        return true
    return false


## Composite occupancy snapshot for a cell. `level` scopes the momentary facts
## (units/blocked/moving/shared_count/reserved); the permanent facts (building,
## bib, resource, terrain) are ground-only. `exclude` removes one entity's
## momentary contribution so a caller can ask "is this cell free apart from me".
## Buildings and resource overlays never appear in `units`: buildings have no
## MovementController, and overlays are not in the "entities" group.
func get_cell_occupancy(cell: Vector2i, level: int = 0, exclude: Node3D = null) -> CellOccupancy:
    var occ := CellOccupancy.new()
    occ.cell = cell
    occ.level = level
    var key := CellUtil.cell_key(cell)
    # Permanent facts are ground-only: buildings/bibs/resources never sit on a
    # deck, so a level > 0 query reports none of them and no ground terrain.
    if level == 0:
        occ.building = _building_cells.has(key)
        occ.bib = _bib_cells.has(key)
        occ.resource = _resource_cells.has(key)
        occ.terrain_buildable = TerrainSystem.is_cell_buildable(cell)
    occ.reserved = _reserved.has(CellUtil.cell_level_key(cell, level))
    for entry in _grid.get(key, []):
        if entry["mc"] == null:
            continue
        if int(entry.get("level", 0)) != level:
            continue
        var node: Node3D = entry["node"]
        if exclude != null and node == exclude:
            continue
        occ.units.append(node)
        if int(entry.get("state", MovementController.State.IDLE)) == MovementController.State.IDLE:
            if bool(entry.get("shares", false)):
                occ.shared_count += 1
            else:
                occ.blocked = true
        else:
            occ.moving = true
    return occ


## True when a structure may occupy `cell`: buildable terrain, no building/bib/
## resource, and no unit body of any state (idle, moving, or sharing). Mirrors
## the original TS `CellClass::Is_Clear_To_Build`. Ground-scoped.
func is_cell_free_for_build(cell: Vector2i, level: int = 0, exclude: Node3D = null) -> bool:
    var occ := get_cell_occupancy(cell, level, exclude)
    if not occ.terrain_buildable or occ.building or occ.bib or occ.resource:
        return false
    return occ.units.is_empty()


## True when a produced or free unit may appear on `cell`: no building/bib, no
## idle non-sharer and no moving unit, and idle sharers below
## `shared_slots_per_cell`. A resource cell is allowed (tiberium is driveable).
## Mirrors a TS `Can_Enter_Cell(...) == MOVE_OK` exit test at the occupancy
## level. Walkable terrain (slopes included) is a locomotor concern, not
## buildability, so non-`"clear"` terrain is NOT refused here.
func is_cell_free_for_unit_exit(cell: Vector2i, level: int = 0, exclude: Node3D = null) -> bool:
    var occ := get_cell_occupancy(cell, level, exclude)
    if occ.building or occ.bib:
        return false
    if occ.blocked or occ.moving:
        return false
    return occ.shared_count < CellSubPositions.get_slot_count()


## True when tiberium may seed `cell`: buildable terrain, no building/bib. Units
## are ignored (tiberium grows under units). Mirrors the original TS
## `CellClass::Can_Tiberium_Germinate`. Ground-scoped.
func is_cell_free_for_resource(cell: Vector2i, level: int = 0) -> bool:
    var occ := get_cell_occupancy(cell, level)
    return occ.terrain_buildable and not occ.building and not occ.bib


## Level-scoped cell reservation. Keys are `CellUtil.cell_level_key`; level 0 is
## `cell_key`, so the no-arg callers reserve exactly as before. A deck
## reservation never blocks the ground beneath and vice versa. Buildings are
## ground-only, so `_building_cells` (keyed by `cell_key`) only refuses level 0.
## A `level > 0` reservation requires a live deck at that level: empty air over a
## deckless cell is refused so nobody paths to a surface the level-aware A* cannot
## reach. Ground level 0 is unchanged and needs no deck. `force_reserve` bypasses
## this deliberately for a unit's own occupied cell.
func reserve_cell(cell: Vector2i, level: int = 0) -> bool:
    if level > 0 and not has_bridge_on_cell(cell, level):
        return false
    var key := CellUtil.cell_level_key(cell, level)
    if _reserved.has(key) or _blocked_cells.has(key) or _building_cells.has(key):
        return false
    _reserved[key] = true
    return true


func release_cell(cell: Vector2i, level: int = 0) -> void:
    _reserved.erase(CellUtil.cell_level_key(cell, level))


func force_reserve(cell: Vector2i, level: int = 0) -> void:
    _reserved[CellUtil.cell_level_key(cell, level)] = true


func clear_reservations() -> void:
    _reserved.clear()


func get_reserved() -> Dictionary:
    return _reserved


## Records a building's footprint cells. Values hold the owning entity when the
## caller knows it (FoundationComponent does) so a shot landing on an edge cell
## of a large structure can still find its occupant — `_grid` only indexes a
## building at its centre cell. Consumers treat this as a set: they read keys
## and never values.
func register_building_cells(cells: Array[Vector2i], node: Node3D = null) -> void:
    for cell in cells:
        var key := CellUtil.cell_key(cell)
        # A later node-less registration (placement preview, deploy transition)
        # must not clobber the entity FoundationComponent recorded.
        if node != null or not _building_cells.has(key):
            _building_cells[key] = node


func register_bib_cells(cells: Array[Vector2i]) -> void:
    for cell in cells:
        _bib_cells[CellUtil.cell_key(cell)] = true


func unregister_bib_cells(cells: Array[Vector2i]) -> void:
    for cell in cells:
        _bib_cells.erase(CellUtil.cell_key(cell))


func is_bib_cell(cell: Vector2i) -> bool:
    return _bib_cells.has(CellUtil.cell_key(cell))


func register_resource_cell(cell: Vector2i) -> void:
    _resource_cells[CellUtil.cell_key(cell)] = true


func unregister_resource_cell(cell: Vector2i) -> void:
    _resource_cells.erase(CellUtil.cell_key(cell))


func has_resource_cell(cell: Vector2i) -> bool:
    return _resource_cells.has(CellUtil.cell_key(cell))


func unregister_building_cells(cells: Array[Vector2i]) -> void:
    for cell in cells:
        _building_cells.erase(CellUtil.cell_key(cell))


func get_building_cells() -> Dictionary:
    return _building_cells
