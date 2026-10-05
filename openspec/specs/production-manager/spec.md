# production-manager Specification

## Purpose

Manage per-player production queues keyed by `player_id:factory_type`: start, stack, and
cancel items; fund builds gradually as they progress (stalling and resuming on insufficient
funds); scale speed with factory count and power; route completed buildings to placement and
completed units to a free factory.
## Requirements
### Requirement: ProductionManager manages per-player production queues
`ProductionManager` SHALL be an autoload singleton managing production queues keyed by `player_id:factory_type`. It emits `production_started`, `production_progress`, `production_completed`, `production_cancelled`, and `production_paused` signals.

#### Scenario: Queue key format
- **WHEN** player 0 builds infantry
- **THEN** queue key is `"0:infantry"`

### Requirement: Start production
`start_production(player_id, entity_data, count)` SHALL add items to the queue after verifying that the entity has a `buildable_queue` and that prerequisites are met (via PrerequisiteSystem). It SHALL NOT require the player to afford the full cost up front — production is funded as it builds. Returns false if the queue type is empty or prerequisites fail.

#### Scenario: Start production — success
- **WHEN** player has prerequisites and queue is empty
- **THEN** item is added, `production_started` emits, returns true

#### Scenario: Start production — prerequisite fails
- **WHEN** player lacks required buildings
- **THEN** returns false, no item added

#### Scenario: Start production — zero balance still queues
- **WHEN** player has prerequisites but a zero credit balance
- **THEN** the item is added and `production_started` emits; it stalls until credits arrive

#### Scenario: Stack incrementing
- **WHEN** last queue item is the same entity type
- **THEN** count increments (up to MAX_STACK = 25) instead of adding new item

### Requirement: Gradual cost deduction
During production, credits SHALL be deducted gradually over the build time at rate `cost / build_time * speed`. A fractional accumulator prevents rounding loss. Progress SHALL advance only when the current increment's cost is successfully deducted; when `EconomyManager.deduct` returns false the queue SHALL stall — holding progress and the accumulator — and resume once funds are available. `item.deducted` SHALL increase only by amounts actually deducted. On completion, any remaining balance is deducted; if that deduction fails, completion SHALL be withheld until funds arrive.

#### Scenario: Gradual deduction during production
- **WHEN** a 1000-credit entity with 10s build time is producing with sufficient funds
- **THEN** approximately 100 credits are deducted per second

#### Scenario: Remaining balance on completion
- **WHEN** production completes and deducted total < cost
- **THEN** the remaining balance is deducted to reach exact cost

#### Scenario: Starved queue holds progress
- **WHEN** the player's balance reaches zero mid-production
- **THEN** progress stops advancing, no further credits are deducted, and the queue stalls

#### Scenario: Failed deduction is not counted
- **WHEN** an increment cannot be deducted
- **THEN** `item.deducted` is unchanged and the accumulator keeps the owed fraction

#### Scenario: Completion is withheld until paid
- **WHEN** progress reaches 100% but the residual balance cannot be deducted
- **THEN** the item does not complete, does not enter ready-to-place, and stalls

### Requirement: Production speed bonus from multiple factories
Production speed SHALL be `1.0 + (factory_count - 1) * 0.25` where `factory_count` is the number of matching-type factories owned by the player. Primary factory is preferred for spawning.

#### Scenario: Single factory
- **WHEN** player owns 1 infantry factory
- **THEN** production speed is 1.0

#### Scenario: Three factories
- **WHEN** player owns 3 vehicle factories
- **THEN** production speed is 1.5

### Requirement: Cancel production with refund
`cancel_production(player_id, queue_key, index, count)` SHALL remove items and refund only the amount already deducted. If count >= item count, entire item is removed.

#### Scenario: Cancel full item
- **WHEN** item has 500 deducted and is fully cancelled
- **THEN** 500 credits are refunded, item removed

#### Scenario: Cancel partial count
- **WHEN** stacked item has count 5 and count=1 is cancelled
- **THEN** count decrements to 4, no refund (waiting items not yet deducted)

### Requirement: Factory-loss teardown
When the final matching factory for a player and production type is sold or destroyed, ProductionManager SHALL cancel every active or paused item in the unsupported queue through the normal refund path. It SHALL refund only credits already deducted, preserve completed buildings waiting for placement, and cancel fully paid units waiting to spawn with a full-cost refund. Losing one of multiple matching factories SHALL preserve the queue and recompute its speed from the remaining count.

#### Scenario: Final factory is lost
- **WHEN** the player loses the last factory matching an active or paused queue
- **THEN** every item in that queue is cancelled and only its deducted credits are refunded

#### Scenario: Matching factory remains
- **WHEN** one of two matching factories is lost
- **THEN** production remains queued and its speed is recomputed from one factory

#### Scenario: Completed building awaits placement
- **WHEN** the last matching factory is lost after a building completed
- **THEN** the building remains ready for placement and is not refunded

#### Scenario: Completed unit awaits a factory
- **WHEN** the last matching factory is lost while a fully paid unit is ready to spawn
- **THEN** the ready unit is removed and its full cost is refunded

### Requirement: Pause and resume production
`pause_production(queue_key, index)` and `resume_production(queue_key, index)` SHALL toggle the `is_paused` flag on queue items. Paused items do not advance.

#### Scenario: Pause production
- **WHEN** `pause_production()` is called on active item
- **THEN** `item.is_paused = true`, timer stops advancing

#### Scenario: Resume production
- **WHEN** `resume_production()` is called on paused item
- **THEN** `item.is_paused = false`, timer resumes

### Requirement: Building completion enters placement mode
When a building completes, it enters ready-to-place state. `get_ready_buildings(player_id)` returns the list of ready `EntityData`. Each ready entry SHALL track the amount already deducted for that building. `place_ready_building(player_id, entity_id)` triggers BuildingManager build mode with skip deduction. `cancel_ready_building(player_id, entity_id)` SHALL refund the tracked deducted amount for that entry.

#### Scenario: Building completes
- **WHEN** production reaches 100% for a building
- **THEN** building is added to `_ready_to_place` with its deducted amount recorded, `_waiting_for_placement` blocks queue

#### Scenario: Place ready building
- **WHEN** `place_ready_building()` is called
- **THEN** BuildingManager enters build mode with skip deduction flag

#### Scenario: Cancel ready building
- **WHEN** `cancel_ready_building()` is called
- **THEN** the amount recorded as deducted for that entry is refunded, and the player's waiting queues unblock

#### Scenario: Build mode exited without placing
- **WHEN** BuildingManager exits build mode without placing, emitting `build_mode_changed(false, player_id)`
- **THEN** only the exiting player's `_waiting_for_placement` queues unblock, leaving other players' queues untouched

### Requirement: Unit spawning on completion
When a unit completes, ProductionManager SHALL find a free factory via `_find_factories()` and call `FactoryComponent.on_unit_produced()`. If no factory is free, the unit enters ready-to-spawn state. When the fallback spawner cannot find a free exit cell near the factory, the unit SHALL NOT spawn inside the building; it SHALL enter ready-to-spawn state with a warning.

#### Scenario: Unit spawns via factory
- **WHEN** unit completes and free factory exists
- **THEN** FactoryComponent.on_unit_produced() is called

#### Scenario: No free factory
- **WHEN** unit completes but all matching factories are busy
- **THEN** unit enters `_ready_to_spawn` list

#### Scenario: No free exit cell in fallback spawn
- **WHEN** a unit completes at a factory without FactoryComponent and no free exit cell exists within the search radius
- **THEN** the unit is NOT placed on the factory's own cell
- **THEN** a warning is logged and the unit enters `_ready_to_spawn`

#### Scenario: Ready-to-spawn retry
- **WHEN** `retry_ready_spawn()` is called
- **THEN** spawn is attempted again

#### Scenario: Ready-to-spawn cancel
- **WHEN** `cancel_ready_spawn()` is called
- **THEN** full cost is refunded

### Requirement: Debug instant-build mode
When `debug_menu.no_build_time == true`, production SHALL complete instantly in one frame.

#### Scenario: Debug mode active
- **WHEN** `no_build_time` is true
- **THEN** production completes immediately, no timer advancement

### Requirement: Zero build time handling
If `entity_data.get_build_time()` returns 0 or negative, production SHALL complete immediately.

#### Scenario: Zero build time
- **WHEN** entity has build_time = 0
- **THEN** item completes in one frame

### Requirement: Low power slows production
ProductionManager SHALL multiply each queue's effective production speed by the owner's current build-rate multiplier from PowerGrid (1.0 when healthy). Production SHALL slow under power deficit but SHALL NOT halt. The per-queue speed cache SHALL be invalidated when PowerGrid emits `grid_state_changed` for the queue's player. When PowerGrid is absent (e.g. isolated unit tests), the multiplier SHALL fall back to 1.0.

#### Scenario: Healthy grid keeps normal speed
- **WHEN** a player's grid is healthy and a queue computes its speed
- **THEN** the speed equals the existing multiple-factory speed with no power multiplier

#### Scenario: Deficit slows production
- **WHEN** a player's grid is in low power with build-rate multiplier r
- **THEN** every queue of that player advances at `speed × r` (e.g. ≈ 60% with output 100 against drain 150)

#### Scenario: Recovery restores speed
- **WHEN** the grid returns to healthy
- **THEN** the next speed lookup returns the unmultiplied speed

#### Scenario: Cache invalidated on grid change
- **WHEN** `grid_state_changed(player_id)` emits
- **THEN** cached speeds for that player's queues are dropped and recomputed on next lookup

### Requirement: Production stalls and resumes on insufficient funds
`ProductionManager` SHALL emit `production_stalled(queue_key)` once when a queue transitions from funded to starved, and `production_resumed(queue_key)` once when it transitions back. The queue key is `"player_id:factory_type"`. The signals SHALL be edge-triggered so a starved queue emits exactly one stall signal regardless of how many frames it remains starved.

#### Scenario: Stall signal fires once
- **WHEN** a producing queue's balance drops below the current increment
- **THEN** `production_stalled` emits exactly once for that queue key

#### Scenario: Resume signal fires on recovery
- **WHEN** credits are added and the starved queue deducts its next increment
- **THEN** `production_resumed` emits once for that queue key

#### Scenario: No stall while funded
- **WHEN** a queue deducts every increment successfully
- **THEN** neither `production_stalled` nor `production_resumed` emits

#### Scenario: Stall state cleared with the queue
- **WHEN** a starved queue is cancelled or completes
- **THEN** its stall state is cleared and a later re-queue is not treated as already stalled
