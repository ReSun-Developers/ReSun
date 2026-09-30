# Economy & Resources System - ReSun

## Overview
The economy system manages resource harvesting, credit tracking, and spending — the core RTS resource loop. Unlike SimCity, there is **no passive income**. Every credit comes from the harvest cycle: harvester → resource pod → fill → refinery → dock → dump → credits.

The system is **resource-agnostic** — it supports tiberium, weed, or any custom resource type via the ResourceType hierarchy. Tiberium is the primary resource but the architecture doesn't assume it.

## Implementation Status (verified 2026-08-08)

Fully implemented and tested:
- Harvest loop: `HarvestComponent` (IDLE/SEEK_NODE/HARVESTING/DELIVERING/HIBERNATE) → `DockClientComponent` → `DockHostComponent` → `DockUnloadComponent` → `EconomyManager` credits
- `ResourceGrowthSystem` (tree + crystal timers, batching, spread limits)
- `ResourceComponent` (3-stage placeholder visuals, `collect()` → self-free), `ResourceTreeComponent`, `TransportComponent` (cargo/pips), `FreeUnitComponent`
- `ResourceType` hierarchy (green/blue/red/vein), `MapConfig`/`PlayerData`/`Faction`, per-player `PlayerManager`
- Map editor resource tools (paint tiberium / place tree / erase) + JSON persistence
- Tests: `test_harvest_dock.gd`, `test_resource_growth_system.gd`, `test_economy_manager.gd`, `test_dock_*`, `test_transport_cargo.gd`

Known gaps:
- `EconomyManager.get_storage_capacity()` now sums owned buildings' `EntityData.storage_capacity` (empty base = 0); per-owner attribution for AI/map-preloaded buildings still pending
- No income/expense rate tracking; credits-to-local-player shortcut in `DockUnloadComponent` (`ponytail:` comment)
- ServiceDepotComponent / dock-based repair not implemented (BuildingManager has flat `repair_building`)
- Vein toxicity gameplay missing (data exists)
- Real 3D crystal/tree models — placeholder cubes/pole only

---

## Core Loop
```
ResourceTree (persistent spawner on map)
  └── spawns Resource pod entities (one per cell within radius)
        └── Harvester drives to pod → fills cargo (pod depletes via HealthComponent)
              → drives to nearest refinery → docks at bib platform → dumps cargo → credits added
              → repeats (or finds new pod if current is depleted)
```

## Overlay Concept
Resource and Resource Tree entities are **overlays** — TERRAIN-type entities with 1×1 foundation that:
- **Block building placement** (checked by `BuildingManager.can_place()`)
- **Do NOT block unit movement or pathfinding**
- Are indestructible by weapons (no HealthComponent on trees, HealthComponent on crystals for amount tracking)
- Are unselectable by the player (no SelectComponent)
- Resource pods use **pseudo-foundation**: blocks building placement via FoundationComponent but has no collision shape for units
- Resource trees use **true 1×1 foundation**: blocks everything (like a building cell)

## Architecture

### PlayerData (Resource) — Issue #77
```gdscript
class_name PlayerData extends Resource
@export var player_id: int = 0
@export var credits: int = 0
@export var faction_id: String = ""     # e.g. "GDI", "Nod"
@export var color: Color = Color.WHITE
@export var team_id: int = 0            # same team = ally, different = enemy
@export var spawn_index: int = 0
@export var display_name: String = ""
@export var is_bot: bool = false        # AI player flag
```
Per-player identity + economy resource. Owned by PlayerManager autoload. Other per-player state (queues, power, shroud) lives in separate resources or systems.

### Faction (Resource) — Issue #77
```gdscript
class_name Faction extends Resource
@export var id: String = ""              # "GDI", "Nod"
@export var display_name: String = ""
@export var color: Color = Color.WHITE
```
Per-faction definition. Stored as .tres files under `resources/factions/`. Referenced by PlayerData.faction_id.

### MapConfig (Resource) — Issue #77
```gdscript
class_name MapConfig extends Resource
@export var players: Array[PlayerConfig] = []
```
Per-map player definitions. Loaded by PlayerManager at _ready() from a child node of the map scene. Each PlayerConfig is an inner class:
```gdscript
class PlayerConfig:
    @export var player_id: int = 0
    @export var display_name: String = ""
    @export var faction_id: String = ""
    @export var team_id: int = 0
    @export var color: Color = Color.WHITE
    @export var spawn_index: int = 0
    @export var is_bot: bool = false
    @export var starting_credits: int = -1   # -1 = use GlobalRules.starting_credits
    @export var starting_units: PackedStringArray = []  # field only, no spawning yet
    @export var power_output: int = -1       # field only, no power system yet
```
If no MapConfig is found, PlayerManager creates defaults: player 0 (human, GDI, team 1) + player 1 (AI, Nod, team 2) with GlobalRules.starting_credits.

### PlayerManager (Autoload) — Issue #77
```gdscript
extends Node
var _players: Dictionary = {}            # player_id → PlayerData
var _local_player_id: int = 0

func get_local_player_id() -> int
func get_player_data(player_id: int) -> PlayerData
func is_enemy(a_id: int, b_id: int) -> bool
func get_all_players() -> Array[PlayerData]
func get_players_by_team(team_id: int) -> Array[PlayerData]
```
Thin registry. Owns PlayerData instances. Reads MapConfig child node at _ready() to initialize players. Lazy-creates PlayerData on first access if not pre-populated. First autoload in load order.

### EconomyManager (Autoload Singleton) — Issue #77 refactored
Thin ledger. Stateless — calls PlayerManager.get_player_data() instead of owning _players dict. Signals stay on EconomyManager.
```gdscript
extends Node
signal credits_changed(player_id: int, new_balance: int, reason: String)
signal insufficient_funds(player_id: int, cost: int, balance: int)

func get_balance(player_id: int) -> int
func can_afford(player_id: int, cost: int) -> bool
func deduct(player_id: int, cost: int, reason: String) -> bool  # false if insufficient
func add(player_id: int, amount: int, reason: String) -> void
func get_storage_capacity(player_id: int) -> int  # computed from silos
```

### Deduction Timing
Credits deducted when an item enters a **production queue** (building at Construction Yard, unit at Factory/Barracks), not on placement. Repair deduction is handled by ServiceDepotComponent (future, rate per HP). Refunds from cancel/sell are proportional (GlobalRules.refund_percent).

## Components

### ResourceTreeComponent
Attached to a ResourceTree TERRAIN entity (1x1 true foundation, indestructible, unselectable). The tree is a persistent spawner placed by map designers — it does NOT disappear when pods are depleted. Growth/spread ticks managed by ResourceGrowthSystem.
```gdscript
class_name ResourceTreeComponent extends Node
@export var spawned_entity_id: String = ""       # EntityData ID of pod to spawn (e.g. "TIB")
@export var radius_cells: int = 8                # spawn radius in grid cells
@export var resource_type_id: String = "tiberium_green"  # resource sub-type to spawn
@export var node_count: int = 12                 # how many pod entities to spawn
@export var spawn_strength: float = 0.5          # health ratio for spawned pods (0.0–1.0)
@export var max_spawn_strength: float = 1.0      # max health ratio
@export var regrowth_rate: float = -1.0          # -1 = use GlobalRules.growth_rate
```
- On `_ready()` with `call_deferred()`: spawn `node_count` pod entities via `EntityFactory.create_entity(spawned_entity_id)` scattered within `radius_cells` with 2-cell minimum spacing
- Each spawned pod gets ResourceComponent configured from tree parameters, including `resource_type_id`
- Tree persists on map regardless of pod depletion
- Placeholder art: a thin pole (`0.33 × 2.0 × 0.33` BoxMesh) via ArtComponent placeholder_size

### ResourceComponent
Attached to TERRAIN-type entity instances (individual resource pods, one per cell). Acts as an overlay. Amount is backed by HealthComponent — `get_amount()` returns `health_ratio`, `collect()` calls `take_damage()`.
```gdscript
class_name ResourceComponent extends Node
@export var resource_type_id: String = "tiberium_green"  # resource sub-type
@export var regrowth_rate: float = -1.0          # -1 = use GlobalRules.growth_rate
@export var spread_count: int = 0                # times this entity has spread
```
- EntityData determines this component via `resource_category != ""` (not a bool flag)
- **Pseudo-foundation**: 1x1 cell blocks building placement but NOT unit movement
- 3 visual stages based on health ratio, rendered as procedurally generated cube clusters:
  1. **Stage 0 (≤33%)**: 3 small cubes (random size 0.15–0.35)
  2. **Stage 1 (34–66%)**: 2 big cubes (0.35–0.55) + 3 small cubes (0.15–0.25)
  3. **Stage 2 (≥67%)**: 5 big cubes (0.35–0.55)
- All cubes are green-tinted (`Color(0.2, 0.8, 0.2)`)
- `_update_visual()` is called after each `collect()` to switch visible stages
- When health reaches 0 after a `collect()` call, the entity self-destructs via `get_parent().queue_free()`

### DockHostComponent (on buildings — refineries, airpads, repair pads)
Manages the dock slot, queue, and cell reservation. Replaced the old DockComponent.
```gdscript
class_name DockHostComponent extends Node
@export var dock_position: Vector3     # local offset where unit stops
@export var dock_rotation: float       # Y rotation the unit faces when docked
@export var dock_types: PackedStringArray = []  # what this host offers (e.g. ["harvest"])
@export var dock_wait_ticks: int = 10  # ticks before queued client is promoted
@export var stale_timeout: float = 5.0 # evict a docker that doesn't finish in time

var queue: Array[Node] = []            # unbounded FIFO queue
var current_docker: Node = null
signal docker_docked(docker: Node)
signal docker_undocked(docker: Node)
signal slot_available
signal dock_timeout(docker: Node)      # current docker evicted for taking too long
```
- One client at a time. Others queue (unbounded — client-side occupancy penalty spreads load across refineries).
- Queued clients wait `dock_wait_ticks` before promotion. On undock with a queue, the host awaits vacate — polls until the dock cell physically clears (up to `VACATE_TIMEOUT`) before promoting the next valid client.
- Auto-evicts a `current_docker` that doesn't complete within `stale_timeout` (emits `dock_timeout`, then `leave_dock`). The client resets the timer on arrival and at unload start, so a long approach isn't mistaken for a stuck docker.
- Reads foundation from FoundationComponent sibling (no duplicate `foundation` export).
- Reserve/release dock cell in SpatialHash on dock/undock.

### DockClientComponent (on units — harvesters, future service depot clients)
Handles dock-finding, reservation-before-movement, and occupancy-aware host selection. New component split from old DockComponent.
```gdscript
class_name DockClientComponent extends Node
@export var can_dock_with: PackedStringArray = []  # entity IDs (e.g. ["PROC"])
@export var occupancy_penalty: float = 10.0        # added to distance per queued client
@export var search_radius_cells: int = 20

# State machine: IDLE, MOVING, ROTATING, UNLOADING, QUEUED
var _reserved_host: Node3D = null
signal dock_slot_failed
signal dock_cancelled
signal dock_undocked(docker: Node)
```
- Searches Buildings group for DockHostComponent with matching entity ID.
- Applies occupancy penalty to distance — distributes harvesters across refineries.
- Reserves slot before movement — prevents wasted pathfinding.
- Client decides compatibility via `can_dock_with`, not host's `allowed_entities`.
- Thin/reactive: driven by host signals (`slot_available`, `docker_undocked`); no per-state timeouts or queue rechecking.
- `cancel()` aborts docking from any sub-state (leaves slot/queue, resets to IDLE) — used by player move commands.

### Refinery Classification (`refinery: bool` on EntityData)

> **Status (2026-08-08):** `refinery: bool` was **re-added** to `EntityData` (schema-first, no consumer yet — per a `ponytail:` comment). It remains unused until the GameAI build-ratio system below is built and queries it.

**Source**: [ModEnc — Refinery](https://modenc.renegadeprojects.com/Refinery)

`Refinery=yes` is a **classification flag** in Tiberian Sun's `rules.ini` (applies to TS, Firestorm, RA2, YR). It answers one question: "is this building a refinery?"

**What it does:**
1. **AI targeting** — AI identifies buildings with `Refinery=yes` to prioritize economy disruption
2. **AI build ratio** — AI maintains N refineries per M harvesters (via `BuildRefinery=PROC,GAPROC` in `[AIControls]`)
3. **Dock registration** — engine recognizes this as a valid unload target (but `Dock=` already handles this)

**What it does NOT do:**
- Validate cargo types (that's `accepted_resource_categories` on `DockUnloadComponent`)
- Handle unload logic (that's `DockUnloadComponent`)

**Mapping to ReSun:**
```gdscript
# EntityData.gd
@export var refinery: bool = false  # classification flag for AI

# AI queries this to count refineries:
func _count_refineries() -> int:
    var count := 0
    for entity in get_tree().get_nodes_in_group("buildings"):
        var data: EntityData = entity.get("entity_data")
        if data and data.refinery:
            count += 1
    return count
```

**Decision for #55**: Delete `RefineryComponent`. Move `accepted_resource_categories` to `DockUnloadComponent`. (`refinery: bool` re-added as schema-first — see Status note above.)

### DockUnloadComponent (on refinery buildings)
Handles the actual unload tick — drains cargo from docked entity, converts to credits via ResourceType.value.
```gdscript
class_name DockUnloadComponent extends Node
@export var unload_rate: float = 0.5       # bales per second
@export var accepted_resource_categories: PackedStringArray = []  # empty = accept all
```
- Reads the docked entity's TransportComponent from `current_docker`'s parent entity
- Validates cargo against `accepted_resource_categories` (empty = accept all); rejects and leaves the dock if any cargo type is unaccepted
- Iterates `transport.cargo` dictionary, looks up `GlobalRules.get_resource_type(type_id).value` for each type
- Adds credits to EconomyManager when integer threshold reached
- Calls `dock.leave_dock()` when cargo empty

### HarvestComponent
Harvester behavior logic. References TransportComponent for cargo capacity and DockClientComponent for dock operations. HarvestComponent decides *what* to do; DockClientComponent owns *how to dock* (queue, move, rotate, unload).
- States: `IDLE`, `SEEK_NODE`, `HARVESTING`, `DELIVERING`, `HIBERNATE`
- SEEK_NODE: search scene tree for nearest entity with ResourceComponent matching `harvestable_types` category (e.g. `["tiberium"]` umbrella matches green/blue/red)
- HARVESTING: tick fill rate at `GlobalRules.harvester_fill_rate`, deplete pod health via `ResourceComponent.collect()`. When full → DELIVERING; when the pod depletes → `_assess_next_action()`
- **Cell occupation**: SpatialHash reserves the resource cell during harvest to prevent duplicate targeting
- DELIVERING: delegates to `DockClientComponent.seek_dock()`. If no refinery is reachable, schedules a `DELIVER_RETRY` cooldown and retries from `_process` — never re-seeks synchronously (that recurses via `dock_slot_failed`)
- `_assess_next_action()` (after unload / depletion): deliver if loaded → else seek nearest resource (current pos, fallback near `_last_field_position`) → else HIBERNATE
- HIBERNATE: field exhausted and empty. Waits `HIBERNATE_INTERVAL`, re-scans, auto-resumes to SEEK_NODE when a field reappears. On entry, if parked on a dock cell, steps off to a free wait cell (dock-unblock). Distinct from IDLE.
- IDLE: reserved for an explicit player stop — no auto-search
- Auto-targets nearest matching resource node when hibernating with no cargo
- Manually orderable via left-click (context-sensitive: click resource → `set_target_node`; click refinery → `set_target_refinery`, which enters DELIVERING so the loop resumes after unload)
- Left-click move on empty ground calls `cancel_harvest()` → `DockClientComponent.cancel()` → `IDLE`

### FoundationComponent.bib_cells
```gdscript
@export var bib_cells: PackedVector2i = []  # cell offsets from origin, within footprint
```
- Bib = flat concrete pad where harvesters drive onto (Refinery, War Factory, Service Depot)
- Cells within the foundation rect. Offsets outside are clamped/ignored.
- Bib cells are soft-blocked in SpatialHash — passable only for dock-queued harvesters
- EntityData gets `@export var bib_cells: PackedVector2i = []`

### FreeUnitComponent
Reusable one-shot component that spawns a free unit when its parent enters the scene tree, then removes itself.
```gdscript
class_name FreeUnitComponent extends Node
@export var free_unit_id: String = ""
```
- On `_ready()`: skip if `Engine.is_editor_hint()` or `get_parent().get_meta("_preview", false)` (ghost guard).
- Calls `_spawn_free_unit()` via `call_deferred()`:
  1. Find an adjacent free cell outside the entity's foundation (spiral search, up to ~5 cells).
  2. If no cell found, retry every 2 seconds.
  3. Create entity via `EntityFactory.create_entity(free_unit_id)`.
  4. Position it at the adjacent cell's center.
  5. Add it as a sibling in the scene tree.
  6. If the spawned entity has a HarvestComponent, find the nearest resource node via `_find_nearest_resource()` and call `set_target_node()` to auto-start harvesting.
  7. `queue_free()` itself — gone after one frame.

## ResourceTree System

The ResourceTree is a persistent map object that spawns and manages a resource patch. Map designers drop a `ResourceTree` scene into the map and configure it in the inspector.

- The tree is created via `EntityFactory` as a TERRAIN entity with `ResourceTreeComponent` + `FoundationComponent(1x1)`
- It has a true foundation (blocks everything) — occupies a cell like a building
- No HealthComponent (indestructible), no SelectComponent (unselectable)
- Resource pods are also TERRAIN overlay entities (full EntityFactory path) with 1x1 pseudo-foundation
- Pseudo-foundation blocks `BuildingManager.can_place()` but allows unit movement through the cell
- `BuildingManager.can_place()` checks: for each footprint cell, if any entity has ResourceComponent on that cell, the cell is blocked

## Map Editor — Resource Tools & Entity Persistence

The map editor provides tools to paint resource pods, place resource trees, and erase both. All painted/placed entities persist in the map JSON file and are recreated on load. Entities are placed at the center of 2×2 unit cells.

### Editor UI Layout
- Top toolbar row: tools arranged horizontally
  `[Save] [Load] | [Paint Height] [Paint Tiberium] [Place Tree] [Erase] | [Strength: HSlider] [Radius: SpinBox]`
- Minimap in top-right corner, above the toolbar
- Toggle tools are radio-button exclusive (one active at a time)
- **Strength** (HSlider): 0–100%, determines amount of resource added/removed per paint pass
- **Radius** (SpinBox): brush radius in cells for Paint Tiberium and Erase

### Tool Behaviors
- **Paint Height** — existing HeightPainter (click+drag raises/lowers terrain). No change.
- **Paint Tiberium** — click+drag over cells: calls `EntityFactory.create_entity("TIB", {resource_amount, resource_max_amount, resource_type_id})` for each cell within brush radius. If a resource pod already exists on the cell, adds to its amount (up to max) instead of creating a duplicate. Entities placed at cell center.
- **Place Tree** — single-click (no drag): places a ResourceTree entity on the clicked cell. If the cell is occupied (by a pod or any entity), the existing entity is removed and replaced with the tree. Entities placed at cell center.
- **Erase** — click+drag within brush radius: reduces resource amount by `strength% * max` per cell per pass. When amount ≤ 0, removes the entity and frees the cell.

### Entity Tracking
`MapEditor` holds `_painted_entities: Dictionary` (key = `"x,y"` string, value = `{ node: Node3D, data: Dictionary }`). Used for:
- O(1) lookup when erasing or re-painting a cell
- O(1) lookup when placing tree on occupied cell (replace)
- Serialization on save
This is editor-local — not using SpatialHash (runtime system).

### Map Persistence (JSON v3)
```
{
  "version": 3,
  "grid_cells": 512,
  "vertices": { "0,0": 1, ... },
  "cells": { "0,0": { "height": 2 }, ... },
  "entities": [
    { "id": "TIB", "cell": "12,5", "resource_amount": 300, "resource_max_amount": 300, "resource_type_id": "tiberium_green" },
    { "id": "TIBTRE01", "cell": "8,3" }
  ]
}
```

### MapLoader.gd
Reads the JSON and restores both terrain and entities:
1. Pass `"vertices"`/`"cells"` to `TerrainSystem.import_from_json()`
2. Iterate `"entities"` array, call `EntityFactory.create_entity(id, overrides)` for each entry
3. Add entities to scene, register in editor's `_painted_entities` dict
Called from MapEditor load flow and game map load.

### ArtComponent.placeholder_size
Add to ArtData:
```
@export var placeholder_size: Vector3 = Vector3.ZERO  # ZERO = auto from foundation
```
`_add_placeholder()` uses `placeholder_size` if non-zero, else existing foundation-based sizing.
ResourceTree ArtData sets `placeholder_size = Vector3(0.33, 2.0, 0.33)` for a thin pole.

## AI Build Ratio (Future)

The original Tiberian Sun uses `[AIControls]` in `rules.ini` to configure AI refinery building:

```ini
[AIControls]
BuildRefinery=PROC,GAPROC  ; comma-separated refinery building type IDs
```

**AI logic** (simplified):
```
if harvesters_count / refineries_count > RATIO_THRESHOLD:
    build refinery
```

**Mapping to ReSun** (future GameAI system):
```gdscript
# In some AI build controller
@export var refinery_ratio: float = 2.0  # harvesters per refinery

func _should_build_refinery() -> bool:
    var harvesters := _count_harvesters()
    var refineries := _count_refineries()
    return harvesters / maxf(refineries, 1.0) > refinery_ratio

func _count_refineries() -> int:
    var count := 0
    for entity in get_tree().get_nodes_in_group("buildings"):
        var data: EntityData = entity.get("entity_data")
        if data and data.refinery:
            count += 1
    return count
```

**Key insight**: `refinery: bool` is purely a classification flag. The AI queries it for build decisions; the dock system handles actual mechanics. No duplication.

## Resource Type System

### ResourceType Resource Class
Defines a resource type with parent/sub-type hierarchy.
```gdscript
class_name ResourceType extends Resource
@export var id: String = ""              # "tiberium_green", "vein"
@export var display_name: String = ""
@export var category: String = ""        # parent category (e.g. "tiberium") — empty = is a category
@export var parent_type: String = ""     # immediate parent type — empty = is a category
@export var value: float = 1.0           # credits per bale when refined
@export var color: Color = Color.WHITE   # for pip display and visual differentiation
@export var grow_rate: float = 0.05      # growth rate for this specific type
@export var spread_amount: float = 0.5   # bales spread per tick
@export var spread_max: int = 3          # max spread count per entity
```

### Resource Type Hierarchy
```
GlobalRules.resource_types: Dictionary = {
    "tiberium":       ResourceType  {category="", value=1.0},        # parent category
    "tiberium_green": ResourceType  {category="tiberium", value=1.0}, # sub-type
    "tiberium_blue":  ResourceType  {category="tiberium", value=2.0}, # sub-type
    "tiberium_red":   ResourceType  {category="tiberium", value=3.0}, # sub-type
    "vein":           ResourceType  {category="weed", value=0.5},     # category
}
```

- HarvestComponent uses `harvestable_types = ["tiberium"]` which umbrellas all sub-types via `GlobalRules.get_resource_category()`
- ResourceComponent stores `resource_type_id: String` (e.g. `"tiberium_green"`)
- DockUnloadComponent declares `accepted_resource_categories` (e.g. `["tiberium"]`), sourced from EntityData via `configure()`
- Resource types stored as `.tres` files under `resources/resource_types/`

### TransportComponent
```gdscript
class_name TransportComponent extends Node
@export var passengers: int = 0        # infantry capacity (APC, etc.)
@export var storage: int = 0           # resource cargo capacity (harvester)
@export var dock: String = ""          # entity ID of dock target
@export var harvester: bool = false
@export var pip_scale: String = ""

var cargo: Dictionary = {}  # {resource_type_id: amount}, e.g. {"tiberium_green": 14.5}

func get_cargo_total() -> float          # sum all values
func get_cargo_value(global_rules) -> int  # sum of amount × value
func add_cargo(type_id, amount) -> float     # returns actual added (capped by capacity)
func remove_cargo(type_id, amount) -> float  # returns actual removed
```

## Game Data

### GlobalRules additions
```gdscript
@export var starting_credits: int = 0
@export var harvester_fill_rate: float = 2.0
@export var resource_types: Dictionary = {}  # {id: ResourceType} — replaces tiberium_value

func get_resource_type(id: String) -> ResourceType
func get_resource_category(resource_id: String) -> String
func get_subtypes(category_id: String) -> Array[String]
```

### EntityData additions
```gdscript
# For ResourceTree (identified by resource_category == "tiberium_tree")
@export var spawned_entity_id: String = ""
@export var radius_cells: int = 0
@export var node_count: int = 0
@export var spawn_strength: float = 0.5
@export var max_spawn_strength: float = 1.0

# For Resource pods (identified by resource_category != "")
@export var resource_category: String = ""
@export var resource_type_id: String = ""

# For buildings (dock + bib)
@export var bib_cells: PackedVector2i = []
@export var dock_position: Vector3 = Vector3.ZERO
@export var dock_rotation: float = 0.0
@export var dock_unload: bool = false
# @export var refinery: bool  # DEFERRED classification flag — add when GameAI build-ratio queries it

# For units that dock
@export var dock: String = ""  # target entity ID (e.g. "PROC")

# For factory buildings with free units
@export var factory: String = ""
@export var free_unit: String = ""

# For harvester cargo
@export var storage: int = 0  # bales capacity

# For hitbox sizing
@export var hitbox_size: Vector3 = Vector3.ZERO
```

## Integration Points
- `BuildingManager.can_place()` → check footprint cells for ResourceComponent entities (pseudo-foundation)
- `BuildingManager._create_building_preview()` → set `_preview` meta on ghost entities
- `BuildingManager.place_building()` → stub deduction (replaced by build queue later)
- `FactoryComponent` / future production queue → deduct on queue
- `SpatialHash` → handle bib cells as soft-blocked
- `EntityFactory._add_components()` → add ResourceTreeComponent, ResourceComponent, HarvestComponent, DockHostComponent, DockClientComponent, DockUnloadComponent, FreeUnitComponent
- `EntityData.refinery` → DEFERRED classification flag for AI (not implemented; see Refinery Classification)
- AI system (future) → queries `refinery` flag for build ratio decisions
- `GlobalRules.tres` → resource_types dictionary with ResourceType entries
- Map scenes → add ResourceTree instances for resource patches
- `MapLoader.gd` → restore terrain + entities from JSON v3 (uses `resource_type_id`)
- `ArtData.gd` → add `placeholder_size`
- `ArtComponent.gd` → honor `placeholder_size` in `_add_placeholder()`

## Credit Display UI

A `Label` above the build menu grid showing the current credit balance, updated in real-time via `EconomyManager.credits_changed` signal.

- Located in `Sidebar.tscn` (renamed from BuildMenu.tscn)
- Uses white-to-green text (~18px) with a "$" prefix
- Updates on every `credits_changed` emission — no polling in `_process()`
- When balance is insufficient for the cheapest buildable item, the label turns red
- Reads initial balance from `EconomyManager.get_balance(PlayerManager.get_local_player_id())` in `_ready()`

## Transport Pip Display

When a vehicle with cargo or passengers is selected, small colored squares (pips) appear below the selection rectangle to indicate fill level. This is the classic Tiberian Sun visual feedback for transport capacity. Pips are rendered by `SelectionOverlay` (CanvasLayer), not by SelectComponent.

### Visual Design

- **Pip mesh**: QuadMesh with black outline (slightly larger QuadMesh behind fill)
- **Billboard**: `BILLBOARD_FIXED_Y` — always faces camera, flat on Y axis
- **Position**: Horizontal row centered below the vehicle selection box L-shaped corners
- **Size**: 0.12 × 0.12 fill, 0.15 × 0.15 outline
- **Max pips**: 5 for cargo, 5 for passengers

### Cargo Pips (Harvesters)

- One pip filled per 20% of `storage`
- Fill color from `ResourceType.color` (e.g., green for tiberium)
- Empty pips: dark gray (`Color(0.2, 0.2, 0.2)`)
- Updates in real-time via `TransportComponent.cargo_changed` signal

### Passenger Pips (APCs, Transports)

- One pip per passenger slot (up to 5)
- Fill color: white when occupied, dark gray when empty
- Updates in real-time via `TransportComponent.passenger_changed` signal

### Signal Flow

```
HarvestComponent → TransportComponent.add_cargo() → emits cargo_changed(current, capacity, type_id)
                                                      ↓
SelectionOverlay → reads TransportComponent → updates pip fill colors

TransportComponent.add_passenger() → emits passenger_changed(current, max)
                                       ↓
SelectionOverlay → updates pip fill colors
```

## Future (Not in scope of #50)
- ServiceDepotComponent for repair deduction (DockClientComponent is generic enough to support it)
- Build queue integration (separate issue)
- Factory queue integration (separate issue)
- **GameAI build ratio system** — queries `EntityData.refinery` to maintain harvester-to-refinery ratio
- Animated BIGBLUE/BIGBLUE3 resource variants
- Real 3D models replacing placeholder cubes (20 variants × 3 stages per resource type)
- Normal tree art (separate from Resource Tree Art)
- Resource toxicity/veins (ResourceType for "vein" category exists, needs gameplay)
- ~~Multiplayer per-player treasury~~ — implemented in #77 (single-player + AI scope)
