# Unit Production Pipeline - ReSun

## Overview
The unit production pipeline manages the creation of new units through factories, barracks, and other production structures. This system handles queue management, tech prerequisites, and spawn logic.

## Implementation Status (verified 2026-08-08)

Fully implemented and tested:
- **`ProductionManager.gd`** — per-player per-queue-type queues (`"%d:%s" % [player_id, queue_type]`), `MAX_STACK=25`, pause/resume/cancel (refund only what was gradually deducted), **gradual cost deduction** over build time (plan said deduct-on-queue — documented divergence), factory speed bonus `1 + (count-1) * rules.multiple_factory` (0.5)
- **`PrerequisiteSystem.gd`** — build limits, OR/AND prerequisites, factory-ownership check
- **`FactoryComponent` / `ExitComponent` / `RallyPointComponent`** — exit offsets, door delay, rally points (Alt+click)
- **`Sidebar.gd`** — 4 tabs (Buildings/Infantry/Vehicles/Special), 5×3 cameo grid, angular progress shader, credits label, prereq dimming, ready-to-place/spawn flows
- Tests: `test_production_manager.gd`, `test_factory_component.gd`, `test_exit_component.gd`, `test_rally_point_component.gd`

Not implemented from this plan:
- Batch production, queue reordering, emergency recall
- Research/upgrade tech tree (`upgrades` field unused)
- Real shift-click queueing (`MOD_QUEUED`/`queued` flag threaded through `OrderResult` but `set_target_position` replaces the path — cosmetic only)
- Aircraft production wiring (Special tab empty; aircraft have no weapons/exit data)

---

## Core Requirements

### 1. Production Structures
| Structure Type | Produces | Special Requirements |
|----------------|----------|---------------------|
| Factory/ Barracks | Ground units | Power required, specific tech level |
| Airfield | Aircraft units | Runway space, higher power cost |
| Shipyard | Naval units | Must be near water tiles |
| Defense Platform | Turrets/Walls | Fixed position, no movement |

### 2. Production Queue System

#### Queue Architecture
- Per-player, per-factory-type queue (e.g., "0:INFANTRY", "0:VEHICLE")
- Unlimited queue size, but individual entity max 25 count in stack
- FIFO ordering within each queue
- Primary building determines spawn location; production speed scales with multiple factories

#### Queue Operations
| Action | Effect |
|--------|--------|
| Left-click idle entity | Add to queue, deduct cost immediately |
| Right-click active item | Pause production |
| Right-click paused item | Cancel (full refund) or decrement stack |
| Left-click paused item | Resume production |

#### Production Timing
- `build_time` on EntityData in game seconds
- Uses `_process(delta)` directly — scales automatically with `Engine.time_scale`
- Production speed bonus from multiple factories: `1.0 + (factory_count - 1) * 0.25`
- Example: 2 barracks → 1.25x speed, 3 barracks → 1.5x speed

#### Visual Progress
- Angular progress shader on cameo: hard-edge radial wipe
- Starts at 12 o'clock, rotates clockwise
- Black semi-transparent overlay (alpha=0.5) → transparent
- Progress updates each frame from ProductionManager

### 3. Tech Tree Integration
- Prerequisite buildings must exist before unlocking
- Research upgrades enable new unit types
- Faction-specific tech paths (GDI vs Nod differences)
- Level requirements for advanced units

### 4. Spawn Logic
- Units spawn at primary factory's exit point
- EntityData has `spawn_point` (local offset) and `exit_direction` (Vector3)
- If no rally point set: find first free cell outside building foundation
- Reuses `_find_adjacent_free_cell()` pattern from FreeUnitComponent
- If all adjacent cells blocked: `MovementController._scatter_blockers()` pushes idle units
- Buildings complete → enter build mode (placement)
- Units complete → spawn at factory and auto-select

## Technical Implementation

### Data Model Additions

#### EntityData.gd — new fields
```gdscript
@export var build_time: float = 1.0        # game seconds (scales with Engine.time_scale)
@export var build_limit: int = 0           # 0 = unlimited per player
@export var buildable_queue: String = ""   # which production queue this entity belongs to
```

### New Autoloads

#### PrerequisiteSystem.gd
- Tracks player-owned buildings: `Dict[int, Dict[String, int]]` (player_id → {entity_id → count})
- `can_build(player_id, entity_data)` → checks prerequisite (OR) + prerequisite_necessary (AND) + build_limit
- `register_building()` / `unregister_building()` — integrates with BuildingManager signals
- Emits `prerequisites_changed(player_id)` when buildings change

#### ProductionManager.gd
- Queue key: `"%d:%s" % [player_id, queue_type]` (e.g., "0:InfantryType")
- QueueItem: `{entity_data, progress, is_paused, count}`
- `start_production()` — checks can_build via `buildable_queue`, deducts cost, adds to queue
- `cancel_production()` — refunds cost, removes/decrements item
- `pause_production()` / `resume_production()` — toggle timer
- `get_progress(queue_key)` → float 0.0-1.0
- `_process(delta)` — ticks active timers, spawns on complete
- Production speed bonus: `1.0 + (factory_count - 1) * 0.25`
- Unit spawning: finds factory via `factory` field, spawns at exit cell
- Building completion: enters build mode via BuildingManager, blocks queue via `_waiting_for_placement`
- Queue unblocks only after building is physically placed (`clear_waiting_for_placement`)

### Scene Structure
```
Sidebar.tscn (Control)
├── CreditsLabel (Label)
├── TabBar (HBoxContainer)
│   ├── BuildingsTab (Button)
│   ├── InfantryTab (Button)
│   ├── VehiclesTab (Button)
│   └── SpecialTab (Button)
├── GridScroll (ScrollContainer) → consumes middle mouse events
│   └── GridContainer (5×3)
│       └── CameoButton (Button) × 15
│           └── AngularProgress (ColorRect + shader)
├── ScrollButtons (HBoxContainer)
│   ├── UpButton (Button)
│   └── DownButton (Button)
└── QueueDisplay (VBoxContainer) → optional, shows active items
```

### Angular Progress Shader
```glsl
shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 overlay_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);

void fragment() {
    vec2 dir = UV - vec2(0.5);
    float angle = atan(dir.x, -dir.y);
    float norm = (angle + PI) / (2.0 * PI);
    COLOR = norm <= progress ? overlay_color : vec4(0.0);
}
```

## Integration Points
- Connect to economy system for cost deduction timing
- Link with tech tree for unlock validation
- Coordinate with selection system for newly spawned units
- Interface with minimap for production progress indicators

## Future Enhancements
- Batch production (train multiple units simultaneously)
- Priority reordering in queue via drag-drop UI
- Emergency recall function for partially trained units
- Production speed bonuses from tech upgrades
