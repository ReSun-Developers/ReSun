extends Node

## ProductionManager autoload — manages production queues per player per factory type,
## handles timers, cost deduction/refund, and unit spawning on completion.

signal production_started(queue_key: String)
signal production_progress(queue_key: String, progress: float)
signal production_completed(queue_key: String, entity_data: EntityData)
signal production_cancelled(queue_key: String)
signal production_paused(queue_key: String)
## Edge-triggered per queue: emitted once when a queue runs out of credits
## (stalls) and once when it can pay again. The EVA "insufficient funds" trigger.
signal production_stalled(queue_key: String)
signal production_resumed(queue_key: String)

## queue_key → Array[ProductionQueue]
var _queues: Dictionary = {}

## queue_key → bool, whether the active item is currently starved of funds.
var _stalled: Dictionary = {}

## queue_key → currently building item index
var _active_index: Dictionary = {}

## queue_key → float (fractional credit accumulator for gradual deduction)
var _deduction_accums: Dictionary = {}

## queue_key → bool (true when a building completed and is waiting to be placed)
var _waiting_for_placement: Dictionary = {}

## player_id → Array[EntityData] of completed buildings waiting to be placed
var _ready_to_place: Dictionary = {}

## player_id → Array[Dictionary] of units that failed to spawn, waiting to retry
## Each dict: { "entity_data": EntityData, "player_id": int, "queue_key": String }
var _ready_to_spawn: Dictionary = {}

## queue_key → float (cached production speed, invalidated on factory changes)
var _speed_cache: Dictionary = {}

const MAX_STACK: int = 25


func _ready() -> void:
    BuildingManager.build_mode_changed.connect(_on_build_mode_changed)
    get_tree().node_added.connect(_on_node_added)
    PowerGrid.grid_state_changed.connect(_on_power_grid_changed)


func _on_power_grid_changed(player_id: int) -> void:
    # Low-power build rate is baked into cached speeds — drop the player's
    # stale entries so the next lookup recomputes with the new rate.
    var prefix := "%d:" % player_id
    for queue_key in _speed_cache.keys():
        if String(queue_key).begins_with(prefix):
            _speed_cache.erase(queue_key)


func _on_node_added(node: Node) -> void:
    # Any factory entering the tree — placement, debug, or spawn path — must
    # invalidate the cached speed before its `_ready` re-emits factories_changed
    # (node_added fires before _ready). Previously only the building-placement
    # path cleared the cache, leaving stale speeds for debug/spawned factories.
    if node is FactoryComponent:
        _connect_factory(node)


func _on_build_mode_changed(is_active: bool, player_id: int) -> void:
    if not is_active:
        # Build mode exited (ESC or placement cancelled) — unblock only this player's queues
        clear_waiting_for_placement(player_id)


func start_production(player_id: int, entity_data: EntityData, count: int = 1) -> bool:
    var queue_type := entity_data.buildable_queue
    if queue_type.is_empty():
        return false

    if not PrerequisiteSystem.can_build(player_id, entity_data):
        return false

    var key := _queue_key(player_id, queue_type)
    if not _queues.has(key):
        _queues[key] = []
    var queue: Array = _queues[key]

    # Stack: increment count if last item is same entity
    if queue.size() > 0:
        var last: ProductionQueue = queue.back() as ProductionQueue
        if last.entity_data.id == entity_data.id:
            last.count = mini(last.count + count, MAX_STACK)
            production_started.emit(key)
            return true

    var item := ProductionQueue.new(entity_data, count)
    queue.append(item)

    # If this is the first item, activate it
    if queue.size() == 1:
        _active_index[key] = 0

    production_started.emit(key)
    return true


func cancel_production(
    player_id: int, queue_key: String, index: int, count: int = 1, notify: bool = true
) -> void:
    if not _queues.has(queue_key):
        return
    var queue: Array = _queues[queue_key]
    if index < 0 or index >= queue.size():
        return
    var item: ProductionQueue = queue[index] as ProductionQueue

    # Decrement or remove
    if count >= item.count:
        # Removing entirely — refund only what was actually deducted
        if item.deducted > 0.0:
            EconomyManager.add(player_id, int(item.deducted), "cancel:%s" % item.entity_data.id)
        queue.remove_at(index)
        # Adjust active index
        var active: int = _active_index.get(queue_key, 0)
        if index < active:
            _active_index[queue_key] = active - 1
        elif index == active and active >= queue.size():
            _active_index[queue_key] = maxi(0, queue.size() - 1)
    else:
        # Just decrement count — no refund for waiting items
        item.count -= count

    # Clean up empty queues
    if queue.is_empty():
        _queues.erase(queue_key)
        _active_index.erase(queue_key)
        _deduction_accums.erase(queue_key)
        _waiting_for_placement.erase(queue_key)
        _stalled.erase(queue_key)

    if notify:
        production_cancelled.emit(queue_key)


func pause_production(queue_key: String, index: int) -> void:
    if not _queues.has(queue_key):
        return
    var queue: Array = _queues[queue_key]
    if index < 0 or index >= queue.size():
        return
    var item: ProductionQueue = queue[index] as ProductionQueue
    item.is_paused = true
    production_paused.emit(queue_key)


func resume_production(queue_key: String, index: int) -> void:
    if not _queues.has(queue_key):
        return
    var queue: Array = _queues[queue_key]
    if index < 0 or index >= queue.size():
        return
    var item: ProductionQueue = queue[index] as ProductionQueue
    item.is_paused = false
    production_paused.emit(queue_key)


func get_progress(queue_key: String) -> float:
    if not _queues.has(queue_key):
        return 0.0
    var queue: Array = _queues[queue_key]
    var active: int = _active_index.get(queue_key, 0)
    if active >= queue.size():
        return 0.0
    var item: ProductionQueue = queue[active] as ProductionQueue
    return item.progress


func get_queue_items(queue_key: String) -> Array:
    return _queues.get(queue_key, [])


func get_active_index(queue_key: String) -> int:
    return _active_index.get(queue_key, 0)


func get_queue_key(player_id: int, factory_type: String) -> String:
    return _queue_key(player_id, factory_type)


func _process(delta: float) -> void:
    var debug_menu := get_tree().get_first_node_in_group("debug_menu")
    var no_build_time: bool = debug_menu != null and debug_menu.no_build_time
    for key in _queues.keys():
        # Signal listeners can remove a factory and tear down this queue while
        # another queue is being processed from the keys snapshot.
        if not _queues.has(key):
            continue
        # Don't produce next item while a building is waiting to be placed
        if _waiting_for_placement.get(key, false):
            continue

        var queue: Array = _queues[key]
        var active: int = _active_index.get(key, 0)
        if active >= queue.size():
            continue
        var item: ProductionQueue = queue[active] as ProductionQueue
        if item.is_paused:
            continue

        var player_id := int(key.get_slice(":", 0))

        # Cheat mode: instant production (still gated on payment inside
        # _complete_item, so the no-cost path completes and a real-cost path stalls).
        if no_build_time:
            _complete_item(key, active)
            continue

        var speed := _get_production_speed(key)
        var build_time: float = item.entity_data.get_build_time(_get_build_speed())
        if build_time <= 0.0:
            _complete_item(key, active)
            continue

        # Owed increment for this frame: cost * speed / build_time * delta, plus
        # whatever fraction carried over. Only advance progress once the whole
        # integer credit amount has actually been deducted.
        var carried: float = _deduction_accums.get(key, 0.0)
        var increment: float = float(item.entity_data.cost) * speed / build_time * delta
        var owed := carried + increment
        var to_pay := int(owed)
        if to_pay > 0 and not _pay(player_id, item, to_pay):
            # Starved: keep only the pending fraction — do NOT bank the un-earned
            # increment, or the owed backlog grows every frame and a small
            # deposit can never clear it (the queue would stay frozen forever).
            _deduction_accums[key] = carried
            _set_stalled(key, true)
            continue
        _deduction_accums[key] = owed - float(to_pay)
        _set_stalled(key, false)

        item.progress += (delta * speed) / build_time
        production_progress.emit(key, item.progress)

        if item.progress >= 1.0:
            _complete_item(key, active)


## Deduct `amount` for `item` from the player's balance. Returns false when the
## balance cannot cover it (caller stalls).
func _pay(player_id: int, item: ProductionQueue, amount: int) -> bool:
    if amount <= 0:
        return true
    if not EconomyManager.deduct(player_id, amount, "prod:%s" % item.entity_data.id):
        return false
    item.deducted += amount
    return true


## Emit the stall/resume signal only on the transition edge, so a queue starved
## for many frames emits exactly one `production_stalled`.
func _set_stalled(key: String, stalled: bool) -> void:
    if bool(_stalled.get(key, false)) == stalled:
        return
    _stalled[key] = stalled
    if stalled:
        production_stalled.emit(key)
    else:
        production_resumed.emit(key)


func _complete_item(key: String, index: int) -> void:
    var queue: Array = _queues[key]
    if index >= queue.size():
        return
    var item: ProductionQueue = queue[index] as ProductionQueue
    var entity_data: EntityData = item.entity_data

    # Deduct the residual rounding. A failed payment withholds completion — the
    # item stays queued and stalled until credits arrive.
    var player_id := int(key.get_slice(":", 0))
    var remaining := entity_data.cost - int(item.deducted)
    if remaining > 0 and not _pay(player_id, item, remaining):
        item.progress = 1.0
        _set_stalled(key, true)
        return

    # Capture what was paid before the count/reset block clears item.deducted,
    # so a cancelled ready building refunds the actual cost paid (not 0).
    var paid := item.deducted

    # Decrement count
    if item.count > 1:
        item.count -= 1
        item.progress = 0.0
        item.deducted = 0.0
        _deduction_accums[key] = 0.0
    else:
        queue.remove_at(index)

    # Buildings go to ready-to-place state; units spawn immediately
    if entity_data.entity_type == EntityData.EntityType.BUILDING:
        _add_ready_to_place(player_id, entity_data, paid)
        _waiting_for_placement[key] = true
    else:
        _spawn_unit(entity_data, player_id)

    production_completed.emit(key, entity_data)

    # Clean up empty queues
    if queue.is_empty():
        _queues.erase(key)
        _active_index.erase(key)
        _deduction_accums.erase(key)
        _stalled.erase(key)
        # Keep _waiting_for_placement until the building is actually placed
    else:
        var active: int = _active_index.get(key, 0)
        if active >= queue.size():
            _active_index[key] = maxi(0, queue.size() - 1)


func _spawn_unit(entity_data: EntityData, player_id: int) -> void:
    var result := _find_factories(player_id, entity_data.buildable_queue)
    if not result.factory:
        _add_ready_to_spawn(entity_data, player_id, "")
        return

    var factory_comp: Node = result.factory.get_node_or_null("FactoryComponent")
    if factory_comp and factory_comp is FactoryComponent:
        if factory_comp.is_busy:
            _add_ready_to_spawn(entity_data, player_id, "")
            return
        (factory_comp as FactoryComponent).on_unit_produced(entity_data, player_id)
    else:
        # Fallback: spawn at a free exit cell. If none exists, retry later rather
        # than spawning the unit inside the factory footprint.
        var spawn_cell: Variant = _find_exit_cell(result.factory)
        if spawn_cell == null:
            push_warning(
                "ProductionManager: no free exit cell near factory for %s" % entity_data.id
            )
            _add_ready_to_spawn(entity_data, player_id, "")
            return
        var world_pos := CellUtil.cell_to_world(spawn_cell as Vector2i)
        var unit: Node3D = EntityPlacer.place_entity(
            entity_data, world_pos, player_id, result.factory
        )
        if unit == null:
            push_error("ProductionManager: no scene root to place produced %s" % entity_data.id)
            _add_ready_to_spawn(entity_data, player_id, "")


## Single-pass factory search: returns the best spawn factory and raw matching
## factory count. Callers that need the historical one-factory speed baseline
## clamp the count at the speed lookup boundary.
func _find_factories(player_id: int, factory_type: String) -> Dictionary:
    var factories := get_tree().get_nodes_in_group("factories")
    var count := 0
    var primary: Node3D = null
    var first_match: Node3D = null
    for f in factories:
        if not f is FactoryComponent:
            continue
        var fc := f as FactoryComponent
        _connect_factory(fc)
        if fc.player_id != player_id:
            continue
        if not factory_type in fc.produces:
            continue
        count += 1
        if fc.is_primary:
            primary = f.get_parent() as Node3D
        elif not first_match:
            first_match = f.get_parent() as Node3D
    return {"factory": primary if primary else first_match, "count": count}


## Returns a free cell near the factory to spawn a unit, or null if none is free
## within the search radius. spiral_first_free returns the center cell when it
## finds nothing free; the factory always occupies its own cell, so a returned
## center unambiguously means "no free cell found."
func _find_exit_cell(factory: Node3D) -> Variant:
    var cell := CellUtil.world_to_cell(factory.global_position)
    var found := CellUtil.spiral_first_free(
        cell,
        5,
        func(candidate: Vector2i) -> bool:
            var key := CellUtil.cell_key(candidate)
            if SpatialHash.instance.get_building_cells().has(key):
                return true
            if SpatialHash.instance.is_cell_blocked(candidate):
                return true
            var cell_type := TerrainSystem.get_cell_type(candidate)
            if cell_type != "" and cell_type != "clear":
                return true
            return false
    )
    if found == cell:
        return null
    return found


func _get_production_speed(queue_key: String) -> float:
    if _speed_cache.has(queue_key):
        return _speed_cache[queue_key]
    var player_id := int(queue_key.get_slice(":", 0))
    var factory_type := queue_key.get_slice(":", 1)
    var result := _find_factories(player_id, factory_type)
    var multiple_factory: float = 0.4
    var rules := GlobalRules.get_current()
    if rules:
        multiple_factory = rules.multiple_factory
    # Keep the historical one-factory baseline for callers that query speed
    # without a live factory. The raw count remains available to lifecycle
    # handling so zero factories can be distinguished from one.
    var factory_count: int = maxi(result.count, 1)
    var speed: float = 1.0 + (factory_count - 1) * multiple_factory
    # Low power slows (never halts) construction: multiply by the grid's
    # interpolated build rate.
    speed *= PowerGrid.get_build_rate(player_id)
    _speed_cache[queue_key] = speed
    return speed


## Connect a factory's change signal once so any add/remove/primary change
## invalidates the cached speeds.
func _connect_factory(factory: FactoryComponent) -> void:
    if factory.factories_changed.is_connected(_on_factories_changed):
        return
    factory.factories_changed.connect(_on_factories_changed)


func _on_factories_changed() -> void:
    _speed_cache.clear()
    var orphaned_keys: Array[String] = []
    var changed_keys: Dictionary = {}
    for queue_key_variant in _queues.keys():
        var queue_key := String(queue_key_variant)
        var player_id := int(queue_key.get_slice(":", 0))
        var factory_type := queue_key.get_slice(":", 1)
        if int(_find_factories(player_id, factory_type).count) == 0:
            orphaned_keys.append(queue_key)

    # Collect before mutating: cancel_production erases empty queue entries and
    # emits signals whose listeners may query the remaining queues.
    for queue_key in orphaned_keys:
        if _cancel_queue_after_factory_loss(queue_key):
            changed_keys[queue_key] = true

    # A fully paid unit may already be waiting for a formerly busy factory and
    # therefore have no live queue entry. Treat it like the unsupported queue:
    # cancel it and refund its full paid cost when the last matching factory is
    # gone. Completed buildings remain in _ready_to_place by design.
    var ready_keys: Dictionary = {}
    for player_id_variant in _ready_to_spawn.keys():
        var player_id := int(player_id_variant)
        for entry_variant in (_ready_to_spawn[player_id] as Array):
            var entry := entry_variant as Dictionary
            var data := entry["entity_data"] as EntityData
            if data and int(_find_factories(player_id, data.buildable_queue).count) == 0:
                ready_keys[_queue_key(player_id, data.buildable_queue)] = true
    for queue_key_variant in ready_keys.keys():
        var queue_key := String(queue_key_variant)
        if _cancel_ready_spawns_after_factory_loss(queue_key):
            changed_keys[queue_key] = true

    for queue_key_variant in changed_keys.keys():
        production_cancelled.emit(String(queue_key_variant))


## Cancels every item in an unsupported queue through the normal refund path.
## Returns true when at least one item was removed so the caller can batch UI
## refresh signals across queued and ready-to-spawn items of the same type.
func _cancel_queue_after_factory_loss(queue_key: String) -> bool:
    if not _queues.has(queue_key):
        return false
    var player_id := int(queue_key.get_slice(":", 0))
    var original_size: int = (_queues[queue_key] as Array).size()
    var cancelled := false
    for _index in range(original_size):
        if not _queues.has(queue_key):
            break
        var queue: Array = _queues[queue_key]
        if queue.is_empty():
            break
        var item: ProductionQueue = queue[0] as ProductionQueue
        cancel_production(player_id, queue_key, 0, item.count, false)
        cancelled = true
    return cancelled


## Removes fully paid units waiting for a factory of the lost type, refunds
## their complete cost, and reports whether the caller needs to refresh the UI.
func _cancel_ready_spawns_after_factory_loss(queue_key: String) -> bool:
    var player_id := int(queue_key.get_slice(":", 0))
    var factory_type := queue_key.get_slice(":", 1)
    if not _ready_to_spawn.has(player_id):
        return false
    var entries: Array = _ready_to_spawn[player_id]
    var removed := false
    for index in range(entries.size() - 1, -1, -1):
        var entry := entries[index] as Dictionary
        var data := entry["entity_data"] as EntityData
        if data and data.buildable_queue == factory_type:
            EconomyManager.add(player_id, data.cost, "factory_loss_ready:%s" % data.id)
            entries.remove_at(index)
            removed = true
    if entries.is_empty():
        _ready_to_spawn.erase(player_id)
    return removed


func _get_build_speed() -> float:
    var rules := GlobalRules.get_current()
    if not rules:
        return -1.0
    return rules.build_speed


func _queue_key(player_id: int, factory_type: String) -> String:
    return "%d:%s" % [player_id, factory_type]


func _add_ready_to_place(player_id: int, entity_data: EntityData, deducted: float) -> void:
    if not _ready_to_place.has(player_id):
        _ready_to_place[player_id] = []
    (_ready_to_place[player_id] as Array).append({"data": entity_data, "deducted": deducted})


func get_ready_buildings(player_id: int) -> Array:
    var out: Array = []
    for entry in _ready_to_place.get(player_id, []):
        out.append((entry as Dictionary)["data"])
    return out


func place_ready_building(player_id: int, entity_id: String) -> bool:
    if not _ready_to_place.has(player_id):
        return false
    var list: Array = _ready_to_place[player_id]
    for i in range(list.size()):
        var data: EntityData = (list[i] as Dictionary)["data"] as EntityData
        if data.id == entity_id:
            # Entry survives until the building lands (#339): a cancelled
            # placement keeps the paid item ready instead of losing it, so
            # re-clicking the cameo never charges a second time. The charge
            # skip itself is decided inside place_building via the readiness
            # check.
            if BuildingManager.is_build_mode and BuildingManager.current_building_type == data:
                return true
            BuildingManager.enter_build_mode(data)
            return true
    return false


## Consume a ready-to-place entry once the building physically landed (#339).
func consume_ready_building(player_id: int, entity_id: String) -> void:
    if not _ready_to_place.has(player_id):
        return
    var list: Array = _ready_to_place[player_id]
    for i in range(list.size()):
        var data: EntityData = (list[i] as Dictionary)["data"] as EntityData
        if data.id == entity_id:
            list.remove_at(i)
            break
    if list.is_empty():
        _ready_to_place.erase(player_id)


func cancel_ready_building(player_id: int, entity_id: String) -> bool:
    if not _ready_to_place.has(player_id):
        return false
    var list: Array = _ready_to_place[player_id]
    for i in range(list.size()):
        var entry: Dictionary = list[i] as Dictionary
        var data: EntityData = entry["data"] as EntityData
        if data.id == entity_id:
            list.remove_at(i)
            if list.is_empty():
                _ready_to_place.erase(player_id)
            # Refund exactly what was deducted for this building — production
            # deducted gradually, but the building was never placed.
            EconomyManager.add(player_id, int(entry["deducted"]), "cancel_ready:%s" % data.id)
            clear_waiting_for_placement(player_id)
            production_cancelled.emit("%d:%s" % [player_id, data.buildable_queue])
            return true
    return false


func clear_waiting_for_placement(player_id: int) -> void:
    # A placed building may be a new factory — drop cached speeds so the next
    # lookup re-scans and picks up the added factory.
    _speed_cache.clear()
    for key in _waiting_for_placement.keys():
        if key.begins_with("%d:" % player_id):
            _waiting_for_placement[key] = false


# --- Cameo click policy + queue read API (moved from Sidebar, which stays pure view) ---


## One entry point for build-cameo clicks. Left: routes place-ready buildings,
## retry-ready spawns, resume-paused items, the no-prereqs direct-deploy
## fallback, and start/stack production (shift = 5). Right: cancels/refunds
## (shift = 5), pauses the active item, or cancels paused items one by one.
func handle_cameo_click(player_id: int, data: EntityData, button: MouseButton, shift: bool) -> void:
    if button == MOUSE_BUTTON_LEFT:
        handle_cameo_left_click(player_id, data, shift)
    elif button == MOUSE_BUTTON_RIGHT:
        handle_cameo_right_click(player_id, data, shift)


## True while a completed building waits for the player to place it.
func is_ready_to_place(player_id: int, entity_id: String) -> bool:
    for item in get_ready_buildings(player_id):
        if (item as EntityData).id == entity_id:
            return true
    return false


## True while a completed unit waits for a spawn retry.
func is_ready_to_spawn(player_id: int, entity_id: String) -> bool:
    for entry in get_ready_spawns(player_id):
        var ed: EntityData = (entry as Dictionary)["entity_data"] as EntityData
        if ed.id == entity_id:
            return true
    return false


## Total queued count for an entity in its queue (cameo badge).
func get_queue_count(player_id: int, data: EntityData) -> int:
    var total := 0
    var items := get_queue_items(get_queue_key(player_id, data.buildable_queue))
    for item in items:
        var pq: ProductionQueue = item as ProductionQueue
        if pq.entity_data.id == data.id:
            total += pq.count
    return total


## Progress of the entity's queued item, 0 when not queued (cameo bar).
func get_item_progress(player_id: int, data: EntityData) -> float:
    var items := get_queue_items(get_queue_key(player_id, data.buildable_queue))
    for item in items:
        var pq: ProductionQueue = item as ProductionQueue
        if pq.entity_data.id == data.id:
            return pq.progress
    return 0.0


## Whether any factory building on the map produces this queue type.
func has_factory_for(queue_type: String) -> bool:
    for f in get_tree().get_nodes_in_group("factories"):
        var fc := f as FactoryComponent
        if fc and queue_type in fc.produces:
            return true
    return false


## Left-click cameo routing (production policy; the Sidebar holds no policy).
func handle_cameo_left_click(player_id: int, data: EntityData, shift: bool) -> void:
    # Building ready to place → enter build mode
    if data.entity_type == EntityData.EntityType.BUILDING and is_ready_to_place(player_id, data.id):
        place_ready_building(player_id, data.id)
        return

    # Unit ready to spawn → retry spawn
    if is_ready_to_spawn(player_id, data.id):
        retry_ready_spawn(player_id, data.id)
        return

    # Check if item is already in queue — resume if paused
    var queue_key := get_queue_key(player_id, data.buildable_queue)
    var items := get_queue_items(queue_key)
    for i in range(items.size()):
        var item: ProductionQueue = items[i] as ProductionQueue
        if item.entity_data.id == data.id and item.is_paused:
            resume_production(queue_key, i)
            return

    # No prerequisites cheat + no factory → direct deploy fallback (named
    # session entry on EntityPlacer; spec'd under debug-menu, not a UI concern).
    var debug_menu := get_tree().get_first_node_in_group("debug_menu")
    if debug_menu and debug_menu.no_prereqs and not data.buildable_queue.is_empty():
        if not has_factory_for(data.buildable_queue):
            EntityPlacer.start_direct_deploy(data)
            return

    # Not in queue or not paused — start/stack production (shift = 5)
    var count := 5 if shift else 1
    start_production(player_id, data, count)


## Right-click cameo routing: refund/cancel-first policy.
func handle_cameo_right_click(player_id: int, data: EntityData, shift: bool) -> void:
    # Ready-to-place building → cancel and refund
    if data.entity_type == EntityData.EntityType.BUILDING and is_ready_to_place(player_id, data.id):
        cancel_ready_building(player_id, data.id)
        return

    # Ready-to-spawn unit → cancel and refund
    if is_ready_to_spawn(player_id, data.id):
        cancel_ready_spawn(player_id, data.id)
        return

    var queue_key := get_queue_key(player_id, data.buildable_queue)
    var items := get_queue_items(queue_key)
    for i in range(items.size()):
        var item: ProductionQueue = items[i] as ProductionQueue
        if item.entity_data.id == data.id:
            if shift:
                var cancel_count := 5 if item.count > 5 else item.count
                cancel_production(player_id, queue_key, i, cancel_count)
            elif item.is_paused:
                cancel_production(player_id, queue_key, i, 1)
            elif i == get_active_index(queue_key):
                pause_production(queue_key, i)
            else:
                cancel_production(player_id, queue_key, i, 1)
            break


# --- Ready-to-spawn (units that failed to spawn, can retry or cancel) ---


func _add_ready_to_spawn(entity_data: EntityData, player_id: int, queue_key: String) -> void:
    if not _ready_to_spawn.has(player_id):
        _ready_to_spawn[player_id] = []
    (_ready_to_spawn[player_id] as Array).append(
        {"entity_data": entity_data, "player_id": player_id, "queue_key": queue_key}
    )
    production_cancelled.emit(queue_key)


func get_ready_spawns(player_id: int) -> Array:
    return _ready_to_spawn.get(player_id, [])


func retry_ready_spawn(player_id: int, entity_id: String) -> bool:
    if not _ready_to_spawn.has(player_id):
        return false
    var list: Array = _ready_to_spawn[player_id]
    for i in range(list.size()):
        var entry: Dictionary = list[i] as Dictionary
        var data: EntityData = entry["entity_data"] as EntityData
        if data.id == entity_id:
            var qk: String = entry["queue_key"] as String
            list.remove_at(i)
            if list.is_empty():
                _ready_to_spawn.erase(player_id)
            _spawn_unit(data, player_id)
            production_cancelled.emit(qk)
            return true
    return false


func cancel_ready_spawn(player_id: int, entity_id: String) -> bool:
    if not _ready_to_spawn.has(player_id):
        return false
    var list: Array = _ready_to_spawn[player_id]
    for i in range(list.size()):
        var entry: Dictionary = list[i] as Dictionary
        var data: EntityData = entry["entity_data"] as EntityData
        if data.id == entity_id:
            list.remove_at(i)
            if list.is_empty():
                _ready_to_spawn.erase(player_id)
            EconomyManager.add(player_id, data.cost, "cancel_ready_spawn:%s" % data.id)
            var qk: String = entry["queue_key"] as String
            production_cancelled.emit(qk)
            return true
    return false
