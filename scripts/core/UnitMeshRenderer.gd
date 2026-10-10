extends Node

## Renders data-driven unit entities through per-region MultiMesh buckets.
## Mirrors TerrainRenderer: bake-merged per-model meshes (ModelBaker), one
## instance per unit, swap-remove slot lifecycle, visible_instance_count, and a
## custom_aabb per region so frustum culling still works. Instance transforms
## are synced every physics frame from the entity's world transform.

const REGION_SIZE: float = 32.0
const MAX_INSTANCES_PER_REGION: int = 512
const HIDDEN_POSITION := Vector3(-9999.0, -9999.0, -9999.0)

const _FOG_VISIBLE: int = 0
const _FOG_GHOST: int = 1
const _FOG_HIDDEN: int = 2

## entity_root(Node3D) -> entry
## entry: {model_path, model_root, region, slot, offset, is_remappable}
var _registry: Dictionary = {}
## region_key(Vector2i) -> {model_path -> bucket}
## bucket: {mmi, multimesh, active_count}
var _buckets: Dictionary = {}
var _active_count: int = 0
## instance_id -> {model_path, region, slot, cell} — frozen MultiMesh ghosts of
## units destroyed in fog, released when their cell leaves fog.
var _tombstones: Dictionary = {}
var ghost_depot: GhostDepot = null


func _ready() -> void:
    # Sync after gameplay nodes move (higher priority runs later), so instance
    # transforms reflect the current physics step rather than the previous one.
    process_physics_priority = 100
    set_physics_process(false)
    if Engine.is_editor_hint():
        return
    ghost_depot = GhostDepot.new()
    ghost_depot.name = "GhostDepot"
    add_child(ghost_depot)
    ShroudSystem.state_changed.connect(_reconcile)
    TerrainSystem.grid_initialized.connect(_on_grid_reinit)


## Registers a unit whose model_root (GLB instance) is a child of the entity's
## ArtComponent. The GLB node tree is hidden on success — gameplay never reads
## mesh-child transforms (hitboxes are Area3D, movement rotates the entity
## root). Returns false when ineligible, unknown model, or no free slot.
## Empty model_path registers a node-tree entity (placeholder art, no baked
## mesh): it gets slot -1 and the fog/ghost logic drives the GLB tree directly.
func register(
    entity_root: Node3D,
    model_path: String,
    model_root: Node3D,
    model_offset: Transform3D,
    is_remappable: bool,
    sockets: Array = [],
) -> bool:
    if Engine.is_editor_hint():
        return false
    if (
        not is_instance_valid(entity_root)
        or not is_instance_valid(model_root)
        or _registry.has(entity_root)
    ):
        return false
    if not _can_register(entity_root):
        return false
    var region := _region_key(entity_root.global_position)
    var slot: int = -1
    if not model_path.is_empty():
        var mesh: ArrayMesh = _ensure_mesh(model_path, is_remappable)
        if mesh == null:
            return false
        slot = _alloc_slot(model_path, region, mesh)
        if slot < 0:
            push_warning("UnitMeshRenderer: region %s full for %s" % [region, model_path])
            return false
    _registry[entity_root] = {
        "model_path": model_path,
        "model_root": model_root,
        "region": region,
        "slot": slot,
        "offset": model_offset,
        "is_remappable": is_remappable,
        "hidden": false,
        "fogged": false,
        "ghost_invalid": false,
        "cell": CellUtil.world_to_cell(entity_root.global_position),
        "stats": entity_root.get_node_or_null("StatsComponent") as StatsComponent,
        "turret": entity_root.get_node_or_null("TurretComponent") as TurretComponent,
        "sockets": _alloc_sockets(sockets, region),
    }
    model_root.visible = slot < 0
    _active_count += 1
    set_physics_process(true)
    return true


## Allocates one instance slot per socket in the entity's region. Each socket
## is a bucket keyed by a real turret model path or a synthetic placeholder key.
func _alloc_sockets(sockets: Array, region: Vector2i) -> Array:
    var entries: Array = []
    for socket in sockets:
        var key: String = socket.get("key", "")
        var mesh: ArrayMesh = socket.get("mesh")
        if key.is_empty() or mesh == null:
            continue
        var slot: int = _alloc_slot(key, region, mesh)
        if slot < 0:
            push_warning("UnitMeshRenderer: no slot for socket %s in region %s" % [key, region])
            continue
        (
            entries
            . append(
                {
                    "id": socket.get("id", ""),
                    "key": key,
                    "region": region,
                    "slot": slot,
                    "pivot": socket.get("pivot", Transform3D.IDENTITY),
                    "mesh": mesh,
                }
            )
        )
    return entries


func unregister(entity_root: Node3D, force: bool = false) -> void:
    if not _registry.has(entity_root):
        return
    var entry: Dictionary = _registry[entity_root]
    _registry.erase(entity_root)
    var slot: int = entry["slot"]
    var fogged: bool = entry["fogged"]
    var socket_entries: Array = entry.get("sockets", [])
    if not force and fogged and not _tombstone_still_fogged(entry):
        # The cell left fog while frozen: release the slot normally, no ghost.
        fogged = false
    if not force and fogged:
        if slot >= 0:
            # A unit destroyed in fog keeps its frozen instance as a tombstone.
            _tombstones[entity_root.get_instance_id()] = {
                "model_path": entry["model_path"],
                "region": entry["region"],
                "slot": slot,
                "cell": entry["cell"],
                "sockets": socket_entries,
            }
            return
        # Node-tree fallback: its frozen visual is already a depot ghost.
        if ghost_depot:
            ghost_depot.mark_dead(entity_root)
    _active_count -= 1
    _release_sockets(socket_entries)
    if slot >= 0:
        _release_slot(entry["model_path"], entry["region"], slot)
    if _active_count <= 0:
        set_physics_process(false)


func _release_sockets(socket_entries: Array) -> void:
    for socket in socket_entries:
        _release_slot(socket["key"], socket["region"], socket["slot"])


func _can_register(entity_root: Node3D) -> bool:
    if entity_root.process_mode == Node.PROCESS_MODE_DISABLED:
        return false
    var node: Node = entity_root
    while node:
        if node.has_meta("detached") or node.has_meta("is_map_editor"):
            return false
        node = node.get_parent()
    return true


func _ensure_mesh(model_path: String, is_remappable: bool) -> ArrayMesh:
    # ModelBaker caches the baked mesh per path internally.
    var result := ModelBaker.bake_model(model_path, is_remappable)
    if result.is_empty():
        return null
    return result.get("mesh") as ArrayMesh


func _region_key(pos: Vector3) -> Vector2i:
    return Vector2i(floori(pos.x / REGION_SIZE), floori(pos.z / REGION_SIZE))


func _region_aabb(region: Vector2i) -> AABB:
    var origin := Vector3(region.x * REGION_SIZE, -50.0, region.y * REGION_SIZE)
    return AABB(origin, Vector3(REGION_SIZE, 500.0, REGION_SIZE))


func _ensure_bucket(model_path: String, region: Vector2i, mesh: ArrayMesh) -> Dictionary:
    var region_map: Dictionary = _buckets.get(region, {})
    if not region_map.has(model_path):
        var multimesh := MultiMesh.new()
        multimesh.mesh = mesh
        multimesh.transform_format = MultiMesh.TRANSFORM_3D
        multimesh.instance_count = MAX_INSTANCES_PER_REGION
        multimesh.visible_instance_count = 0
        multimesh.custom_aabb = _region_aabb(region)
        var mmi := MultiMeshInstance3D.new()
        mmi.multimesh = multimesh
        # bug #108058: physics interpolation corrupts per-instance transforms.
        mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
        add_child(mmi)
        region_map[model_path] = {"mmi": mmi, "multimesh": multimesh, "active_count": 0}
        _buckets[region] = region_map
    return region_map[model_path]


func _get_multimesh(model_path: String, region: Vector2i) -> MultiMesh:
    var region_map: Dictionary = _buckets.get(region, {})
    var bucket: Dictionary = region_map.get(model_path, {})
    return bucket.get("multimesh", null)


func _alloc_slot(model_path: String, region: Vector2i, mesh: ArrayMesh) -> int:
    var bucket := _ensure_bucket(model_path, region, mesh)
    var multimesh: MultiMesh = bucket["multimesh"]
    var count: int = bucket["active_count"]
    if count >= MAX_INSTANCES_PER_REGION:
        return -1
    bucket["active_count"] = count + 1
    multimesh.visible_instance_count = count + 1
    return count


func _release_slot(model_path: String, region: Vector2i, slot: int) -> void:
    var region_map: Dictionary = _buckets.get(region, {})
    var bucket: Dictionary = region_map.get(model_path, {})
    if bucket.is_empty():
        return
    var multimesh: MultiMesh = bucket["multimesh"]
    var last: int = bucket["active_count"] - 1
    if slot != last:
        var last_transform: Transform3D = multimesh.get_instance_transform(last)
        multimesh.set_instance_transform(slot, last_transform)
        _retarget_slot(model_path, region, last, slot)
    bucket["active_count"] = last
    multimesh.visible_instance_count = last
    multimesh.set_instance_transform(last, Transform3D(Basis(), HIDDEN_POSITION))
    if last == 0:
        var mmi: MultiMeshInstance3D = bucket["mmi"]
        if is_instance_valid(mmi):
            remove_child(mmi)
            mmi.queue_free()
        region_map.erase(model_path)
        if region_map.is_empty():
            _buckets.erase(region)


## Repoints the owner(s) of a slot after swap-remove. Scans body slots and
## socket slots in the registry and tombstones, so twin sockets on one entity
## do not lose track of their indices when another entity is released.
func _retarget_slot(model_path: String, region: Vector2i, from_slot: int, to_slot: int) -> void:
    for entity in _registry:
        var entry: Dictionary = _registry[entity]
        if (
            entry["model_path"] == model_path
            and entry["region"] == region
            and entry["slot"] == from_slot
        ):
            entry["slot"] = to_slot
        _retarget_socket_slots(entry.get("sockets", []), model_path, region, from_slot, to_slot)
    for tkey in _tombstones:
        var t: Dictionary = _tombstones[tkey]
        if t["model_path"] == model_path and t["region"] == region and t["slot"] == from_slot:
            t["slot"] = to_slot
        _retarget_socket_slots(t.get("sockets", []), model_path, region, from_slot, to_slot)


func _retarget_socket_slots(
    socket_entries: Array, model_path: String, region: Vector2i, from_slot: int, to_slot: int
) -> void:
    for socket in socket_entries:
        if (
            socket["key"] == model_path
            and socket["region"] == region
            and socket["slot"] == from_slot
        ):
            socket["slot"] = to_slot


func _physics_process(_delta: float) -> void:
    if Engine.is_editor_hint() or _registry.is_empty():
        return
    var in_map_editor := _current_scene_is_map_editor()
    for entity in _registry.keys():
        var entity_node: Node3D = entity
        if not is_instance_valid(entity_node):
            unregister(entity)
            continue
        var entry: Dictionary = _registry[entity_node]
        var model_root: Node3D = entry["model_root"]
        var preview := (
            in_map_editor
            or entity_node.process_mode == Node.PROCESS_MODE_DISABLED
            or entity_node.has_meta("detached")
        )
        if preview:
            _set_model_visible(model_root, true)
            # ponytail: a parked preview keeps its slot counted toward region
            # capacity (one transient preview at a time, negligible under 512);
            # eject the slot too if previews ever outnumber region headroom.
            var parked: MultiMesh = _get_multimesh(entry["model_path"], entry["region"])
            if parked and entry["slot"] >= 0:
                parked.set_instance_transform(entry["slot"], Transform3D(Basis(), HIDDEN_POSITION))
            _park_sockets(entry)
            continue
        # Fog handling is visual-only (simulation keeps running). Enemy units
        # in unexplored shroud are parked off-world; enemy units in explored
        # fog are frozen at their last-known position so the player sees a
        # ghost where they last were. Friendly units and fog-off maps are
        # never hidden. GLB tree stays hidden throughout.
        var state := _fog_state(entity_node, entry)
        var multimesh: MultiMesh = _get_multimesh(entry["model_path"], entry["region"])
        if state == _FOG_HIDDEN:
            entry["fogged"] = false
            entry["hidden"] = true
            if entry["slot"] >= 0 and multimesh:
                multimesh.set_instance_transform(
                    entry["slot"], Transform3D(Basis(), HIDDEN_POSITION)
                )
            else:
                _set_model_visible(model_root, false)
            if ghost_depot:
                ghost_depot.release_entry(entity_node)
            _park_sockets(entry)
            continue
        if state == _FOG_GHOST:
            entry["hidden"] = false
            if entry["ghost_invalid"]:
                # The ghost's anchor cell was revealed while the entity was
                # elsewhere: keep it gone until the entity is visible again.
                _hide_ghost_visual(entry, model_root, multimesh)
                if ghost_depot:
                    ghost_depot.release_entry(entity_node)
                continue
            if entry["fogged"] and not _tombstone_still_fogged(entry):
                # The frozen anchor cell left fog (revealed or shroud-revert)
                # while the entity is still not visible: the ghost must vanish,
                # not slide to the entity's current position.
                _invalidate_ghost(entity_node, entry, model_root, multimesh)
                continue
            if not entry["fogged"]:
                # Freeze at the current (last-known) transform once on fog entry.
                entry["fogged"] = true
                entry["cell"] = CellUtil.world_to_cell(entity_node.global_position)
                if entry["slot"] >= 0 and multimesh:
                    multimesh.set_instance_transform(
                        entry["slot"], entity_node.global_transform * entry["offset"]
                    )
                else:
                    _freeze_fallback(entity_node, model_root)
                _freeze_sockets(entry, entity_node)
                # ponytail: a ghost frozen in a region bucket whose key differs
                # from its frozen position may frustum-cull late; negligible, and
                # the slot re-migrates to the true position on reveal.
            continue
        entry["fogged"] = false
        entry["hidden"] = false
        entry["ghost_invalid"] = false
        if entry["slot"] >= 0:
            _set_model_visible(model_root, false)
        else:
            _set_model_visible(model_root, true)
            if ghost_depot:
                ghost_depot.release_entry(entity_node)
        var region := _region_key(entity_node.global_position)
        if region != entry["region"]:
            if entry["slot"] >= 0:
                _release_slot(entry["model_path"], entry["region"], entry["slot"])
            _migrate_sockets(entry, region)
            entry["region"] = region
            if entry["slot"] >= 0:
                var migrated_mesh: ArrayMesh = _ensure_mesh(
                    entry["model_path"], entry["is_remappable"]
                )
                entry["slot"] = _alloc_slot(entry["model_path"], region, migrated_mesh)
                if entry["slot"] < 0:
                    push_warning(
                        (
                            "UnitMeshRenderer: region %s full for %s; falling back to node-tree"
                            % [region, entry["model_path"]]
                        )
                    )
                    _set_model_visible(model_root, true)
                    if ghost_depot:
                        ghost_depot.release_entry(entity_node)
        if entry["slot"] >= 0:
            var synced: MultiMesh = _get_multimesh(entry["model_path"], entry["region"])
            if synced:
                synced.set_instance_transform(
                    entry["slot"], entity_node.global_transform * entry["offset"]
                )
        _sync_sockets(entry, entity_node)


## Parks every socket instance off-world (preview / hidden fog).
func _park_sockets(entry: Dictionary) -> void:
    var hidden := Transform3D(Basis(), HIDDEN_POSITION)
    for socket in entry.get("sockets", []):
        var mm: MultiMesh = _get_multimesh(socket["key"], socket["region"])
        if mm and socket["slot"] >= 0:
            mm.set_instance_transform(socket["slot"], hidden)


## Writes socket transforms once at the moment of fog freeze.
func _freeze_sockets(entry: Dictionary, entity_node: Node3D) -> void:
    var turret: TurretComponent = entry.get("turret")
    for socket in entry.get("sockets", []):
        var mm: MultiMesh = _get_multimesh(socket["key"], socket["region"])
        if mm == null or socket["slot"] < 0:
            continue
        mm.set_instance_transform(socket["slot"], _socket_world(entity_node, socket, turret))


## Moves every socket instance from its old region into the new one.
func _migrate_sockets(entry: Dictionary, new_region: Vector2i) -> void:
    for socket in entry.get("sockets", []):
        if socket["region"] == new_region:
            continue
        _release_slot(socket["key"], socket["region"], socket["slot"])
        socket["region"] = new_region
        socket["slot"] = _alloc_slot(socket["key"], new_region, socket["mesh"])
        if socket["slot"] < 0:
            push_warning(
                (
                    "UnitMeshRenderer: region %s full for socket %s; dropped until next migrate"
                    % [new_region, socket["key"]]
                )
            )


## Syncs every socket instance transform from the entity and its turret yaw.
func _sync_sockets(entry: Dictionary, entity_node: Node3D) -> void:
    var sockets: Array = entry.get("sockets", [])
    if sockets.is_empty():
        return
    var turret: TurretComponent = entry.get("turret")
    for socket in sockets:
        var mm: MultiMesh = _get_multimesh(socket["key"], socket["region"])
        if mm == null or socket["slot"] < 0:
            continue
        mm.set_instance_transform(socket["slot"], _socket_world(entity_node, socket, turret))


## World transform of a socket: entity transform composed with the pivot, yawed
## by the socket's current turret angle (0 for fixed or unconfigured sockets).
func _socket_world(entity_node: Node3D, socket: Dictionary, turret: TurretComponent) -> Transform3D:
    var pivot: Transform3D = socket["pivot"]
    var yaw := 0.0
    if turret and is_instance_valid(turret) and not socket["id"].is_empty():
        yaw = turret.get_yaw(socket["id"])
    var local := Transform3D(Basis(Vector3.UP, yaw) * pivot.basis, pivot.origin)
    return entity_node.global_transform * local


func _set_model_visible(model_root: Node3D, visible: bool) -> void:
    if is_instance_valid(model_root) and model_root.visible != visible:
        model_root.visible = visible


func _fog_state(entity_node: Node3D, entry: Dictionary) -> int:
    var stats: StatsComponent = entry.get("stats")
    if not is_instance_valid(stats) or stats.player_id < 0:
        return _FOG_VISIBLE
    if not PlayerManager.is_enemy(PlayerManager.get_local_player_id(), stats.player_id):
        return _FOG_VISIBLE
    var cell_state: int = ShroudSystem.cell_state_to_local(
        CellUtil.world_to_cell(entity_node.global_position)
    )
    if cell_state == ShroudSystem.STATE_VISIBLE:
        return _FOG_VISIBLE
    if cell_state == ShroudSystem.STATE_FOG:
        return _FOG_GHOST
    return _FOG_HIDDEN


## Node-tree fallback freeze: the unit renders through its GLB tree (no
## MultiMesh slot), so freezing means reparenting the model into the depot.
func _freeze_fallback(entity_node: Node3D, model_root: Node3D) -> void:
    var depot := ghost_depot
    if depot == null or not is_instance_valid(model_root):
        return
    var original_parent := model_root.get_parent()
    if original_parent == null or original_parent == depot:
        return
    # The GLB tree was hidden at registration; the ghost must render.
    _set_model_visible(model_root, true)
    (
        depot
        . reparent_in(
            entity_node,
            model_root,
            original_parent,
            CellUtil.world_to_cell(entity_node.global_position),
            false,
        )
    )


## Hides a ghost's visual without touching ghost membership — the invalidated
## poll path uses this every frame so a stale ghost never re-renders.
func _hide_ghost_visual(entry: Dictionary, model_root: Node3D, multimesh: MultiMesh) -> void:
    if entry["slot"] >= 0 and multimesh:
        multimesh.set_instance_transform(entry["slot"], Transform3D(Basis(), HIDDEN_POSITION))
    else:
        _set_model_visible(model_root, false)
    _park_sockets(entry)


## A frozen ghost whose anchor cell left fog while the entity is still not
## visible must vanish entirely (never slide to the entity's current position).
## `ghost_invalid` suppresses re-freeze/re-render until the entity is visible.
func _invalidate_ghost(
    entity_node: Node3D, entry: Dictionary, model_root: Node3D, multimesh: MultiMesh
) -> void:
    entry["fogged"] = false
    entry["ghost_invalid"] = true
    _hide_ghost_visual(entry, model_root, multimesh)
    if ghost_depot:
        ghost_depot.release_entry(entity_node)


## Grid-derived ghost truth: on every shroud state change, release ghosts whose
## anchor cell is no longer fog and tombstone instances whose cell left fog.
func _reconcile(_dirty: PackedInt32Array) -> void:
    if Engine.is_editor_hint():
        return
    if ghost_depot:
        ghost_depot.release_unfogged()
    var local := PlayerManager.get_local_player_id()
    for entity in _registry.keys():
        var entry: Dictionary = _registry[entity]
        if not entry["fogged"] or entry["ghost_invalid"]:
            continue
        if _tombstone_still_fogged(entry):
            continue
        if _fog_state(entity, entry) == _FOG_VISIBLE:
            continue
        var model_root: Node3D = entry["model_root"]
        var multimesh: MultiMesh = _get_multimesh(entry["model_path"], entry["region"])
        _invalidate_ghost(entity, entry, model_root, multimesh)
    for key in _tombstones.keys():
        var t: Dictionary = _tombstones[key]
        var cell: Vector2i = t["cell"]
        if ShroudSystem.is_cell_visible_to_local(cell):
            _release_tombstone(key)
        elif not ShroudSystem.is_explored(local, cell):
            _release_tombstone(key)


func _release_tombstone(key: int) -> void:
    if not _tombstones.has(key):
        return
    var t: Dictionary = _tombstones[key]
    _tombstones.erase(key)
    _active_count -= 1
    _release_slot(t["model_path"], t["region"], t["slot"])
    _release_sockets(t.get("sockets", []))
    if _active_count <= 0:
        set_physics_process(false)


func _tombstone_still_fogged(entry: Dictionary) -> bool:
    if not ShroudSystem.is_fog_enabled():
        return false
    return ShroudSystem.cell_state_to_local(entry["cell"] as Vector2i) == ShroudSystem.STATE_FOG


## Releases every tombstone and depot ghost — runtime fog toggle-off, grid
## reinit, and map teardown all funnel here.
func sweep_ghosts() -> void:
    if Engine.is_editor_hint():
        return
    for key in _tombstones.keys():
        _release_tombstone(key)
    if ghost_depot:
        ghost_depot.release_all()


func _on_grid_reinit() -> void:
    sweep_ghosts()


func _current_scene_is_map_editor() -> bool:
    var scene := get_tree().current_scene
    return scene != null and scene.has_meta("is_map_editor")


func clear_all() -> void:
    for key in _tombstones.keys():
        _release_tombstone(key)
    for entity in _registry.keys():
        unregister(entity, true)
    if ghost_depot:
        ghost_depot.release_all()
