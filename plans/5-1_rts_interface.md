# RTS Interface Elements - ReSun

## Overview
The UI interface system provides players with essential information and control panels for managing their base, units, and resources during gameplay. This is critical for responsive RTS gameplay.

## Implementation Status (verified 2026-08-08)

| Element | Status | Notes |
|---------|--------|-------|
| Tabbed sidebar (4 tabs, F1–F4, 5×3) | ✅ | `Sidebar.gd`; Special tab empty (aircraft not wired) |
| Credits HUD | ✅ | `%CreditsLabel`, signal-driven; insufficient-funds red state NOT implemented (credit-ui spec gap) |
| Cameo states + angular progress | ✅ | Angular progress shader, queue overlay, ready flicker, build-limit dim, prereq hiding |
| Cameo tooltip | ✅ | Native `tooltip_text` (cost + time) |
| Production queue display | 🟡 | Cameo overlays only; no separate queue panel/cancel buttons/hotkey slots |
| Cursor + order system | ✅ | 52 cursors (placeholder SVGs), generators, `OrderResolver` priority chain — see §6 |
| Sell/Repair mode | ✅ | `OrderSystem.set_generator` |
| Debug menu (~) | ✅ | `DebugMenu.gd` — overlays, lighting, cheats, entity inspection |
| FPS counter | ✅ | `FPSCounter01.tscn` |
| Gameplay minimap | ❌ | Only `scripts/editor/Minimap.gd` (editor tool); `RadarComponent` stub; open #177/#246 |
| Selection/info panel | ❌ | Health bars + pips exist (SelectionOverlay); no stats/actions panel |
| Resource HUD (Tiberium/income/power) | ❌ | Credits only; `EconomyManager` has no income tracking |
| Input routing | ✅ | `InputSettings` autoload + `UIUtil` hit-tests |

**Entity info:** closest is DebugMenu "Entity Inspection" (read-only component dump).

---

## Core Requirements

### 1. Selection Panel
- Displays health bars of selected units/buildings
- Shows available actions/commands per selection type
- Progress bars for construction/training queues
- Unit stats (health, armor, weapon info) on hover

### 2. Production Queue Display
- Visual list of queued buildings/units
- Progress indicators showing completion percentage
- Cancel button with refund confirmation
- Hotkey overlay showing queue slot numbers (1-5)

### 3. Resource HUD
| Element | Display Format | Update Frequency |
|---------|----------------|------------------|
| Credits | Numeric counter + income rate | Real-time (per frame) |
| Tiberium | Numeric counter + harvesting status | Every second |
| Power | Current/Max with color coding | When changes occur |

### 4. Minimap System
- Full map overview with fog of war overlay
- Unit markers colored by faction
- Build location indicators for queued structures
- Click-to-move functionality (right-click on minimap)

### 5. Build Menu Interface — Tabbed Sidebar

**GitHub Issue**: #66 — feat: tabbed build menu sidebar with 4 production categories

#### Tab Layout (Vinifera-style for TS)
```
┌──────────┬──────────┬──────────┬──────────┐
│ Buildings│ Infantry │ Vehicles │ Special  │
└──────────┴──────────┴──────────┴──────────┘
```

| Tab | Entity Type | Content | Production Building |
|-----|-------------|---------|---------------------|
| **Buildings** | BUILDING | Structures, defenses (sorted last) | Construction Yard |
| **Infantry** | INFANTRY | Infantry units | Barracks / Hand of Nod |
| **Vehicles** | VEHICLE | Tanks, buggies, harvesters, MCV | War Factory |
| **Special** | AIRCRAFT | Aircraft, superweapons | Airfield / Shipyard |

#### Sidebar Layout
```
┌─────────────────────────────────────────┐
│ $1500                                  │  ← Credits (top)
├─────────────────────────────────────────┤
│ [Build][Infantry][Vehicles][Special]   │  ← Tab bar
├─────────────────────────────────────────┤
│ ┌───────┐ ┌───────┐ ┌───────┐         │
│ │ ▓▓▓  │ │ ░░░  │ │  ░░  │ 5×3     │
│ │ConYard│ │ Power │ │Barracks│  grid    │
│ └───────┘ └───────┘ └───────┘         │
│ ... (5 rows × 3 cols = 15 visible)     │
├─────────────────────────────────────────┤
│ [▲]                           [▼]     │  ← Scroll by row
└─────────────────────────────────────────┘
```

- Width: 400px, Height: ~600px
- 5 rows × 3 columns, scrollable by row steps
- Middle mouse scroll on sidebar → scroll grid (consume event, don't zoom camera)
- Tab hotkeys: F1-F4

#### Cameo States
| State | Visual |
|-------|--------|
| Available | Normal cameo, full color |
| In queue (building) | Angular progress overlay (12 o'clock → clockwise) |
| In queue (paused) | Darkened, progress frozen |
| Prerequisites not met | Hidden |
| Build limit reached | Darkened "ghost" cameo |

#### Interaction
| Action | Effect |
|--------|--------|
| Left-click available | Add to queue, deduct cost |
| Left-click paused | Resume production |
| Right-click building | Pause production |
| Right-click paused | Cancel (refund) or decrement stack |
| Middle scroll on sidebar | Scroll grid row (not camera zoom)

## Technical Implementation

### Scene Structure
```
GameUI.tscn (Control root)
├── SelectionPanel.tscn (bottom-left corner)
├── ProductionQueue.tscn (bottom-center)
├── ResourceHUD.tscn (top-right corner)
├── MinimapContainer.tscn (bottom-right corner)
└── BuildMenu.tscn (hidden, toggle with hotkey)
```

### Key Scripts

#### GameUIController.gd
- Central coordinator for all UI panels
- Handle visibility toggling between states
- Update resource display every frame
- Process minimap click events for movement commands

#### SelectionPanel.gd
- Dynamically populate based on selected units
- Show health bars with color-coded damage levels
- Display action buttons for available commands
- Queue progress indicators for production

### Resource HUD Implementation
```gdscript
func update_resource_display(resources):
    credits_label.text = str(resources.credits) + " CR"
    tiberium_label.text = str(resources.tiberium) + " TIB"
    
    # Income rate display with color coding
    if resources.income_rate > 0:
        income_label.set_modulate(Color.GREEN)
    elif resources.income_rate < 0:
        income_label.set_modulate(Color.RED)
    
    income_label.text = str(resources.income_rate) + "/s"

func update_power_display(current, max):
    var percentage = float(current) / float(max)
    
    if percentage < 0.3:
        power_icon.set_modulate(Color.RED)
    elif percentage < 0.7:
        power_icon.set_modulate(Color.YELLOW)
    else:
        power_icon.set_modulate(Color.GREEN)
```

### Minimap Integration
- Render map tiles at reduced resolution for performance
- Draw unit markers as small colored circles/polygons
- Handle mouse clicks with raycast conversion to world coordinates
- Show build preview when placement mode active

## Integration Points
- Connect to economy system for resource updates
- Link with selection system for panel population
- Coordinate with production manager for queue display
- Interface with camera system for minimap position sync

## 6. Unified Cursor + Order System — IMPLEMENTED

**GitHub Issue**: #70 — feat: Tiberian Sun cursor system with per-unit resolution

**Status**: ✅ Implemented. All files created, all modifications applied. OrderSystem autoload registered.

### Overview
Context-sensitive cursors matching original Tiberian Sun. Per-unit resolution — each entity component determines what cursor to show AND what order to issue. A central `OrderSystem` autoload holds the active `OrderGenerator` and delegates mouse input — eliminating hardcoded order logic in `MouseHandler`.

### Architecture

```
MouseHandler._process()
│
├─ 1. Global overrides (modal state)
│   ├─ dragging box → SELECT
│   ├─ screen edge → SCROLL_* (with blocked variant if at map bounds)
│   └─ sell/repair mode → delegated to OrderSystem → SellOrderGenerator / RepairOrderGenerator
│
├─ 2. Per-unit resolution (if no global override)
│   └─ OrderSystem.get_cursor(target, target_cell, target_pos, modifiers)
│       └─ active_generator.get_cursor()  [UnitOrderGenerator by default]
│           └─ OrderResolver.resolve()
│               ├─ for each selected entity:
│               │   ├─ CombatComponent.get_order_for_target() → { cursor: ATTACK, priority: 30 }
│               │   ├─ HarvestComponent.get_order_for_target() → { cursor: HARVEST, priority: 20 }
│               │   ├─ TransportComponent.get_order_for_target() → { cursor: ENTER, priority: 15 }
│               │   └─ MovementController.get_order_for_target() → { cursor: MOVE, priority: 5 }
│               └─ highest priority wins
│
└─ 3. Fallback → DEFAULT
```

### Component Interface

Each component that can issue orders implements:

```gdscript
func get_order_for_target(
    target: Node3D,
    target_cell: Vector2i,
    target_pos: Vector3,
    modifiers: Dictionary  # { force_attack, force_move, queued }
) -> OrderResult:
    # Returns null if this component cannot handle this target
```

### OrderResult

```gdscript
class_name OrderResult

var cursor: CursorState.Type   # what cursor to show
var priority: int              # higher wins
var order_id: String           # "move", "attack", "harvest", "enter", "deploy"
var target: Node3D             # target entity (null for terrain)
var target_pos: Vector3        # world position (for movement)
var queued: bool               # shift-queue support
var execute: Callable          # the actual order execution
```

### OrderResolver (static)

```gdscript
static func resolve(
    selected_entities: Array[SelectComponent],
    target: Node3D,
    target_cell: Vector2i,
    target_pos: Vector3,
    modifiers: Dictionary
) -> OrderResult:
    var best: OrderResult = null
    for select_comp in selected_entities:
        var entity = select_comp.get_parent()
        for component in entity.get_children():
            if component.has_method("get_order_for_target"):
                var result = component.get_order_for_target(target, target_cell, target_pos, modifiers)
                if result and (not best or result.priority > best.priority):
                    best = result
    return best
```

### OrderGenerator Hierarchy

```
OrderGenerator (base class)
  ├── UnitOrderGenerator    # normal gameplay — uses OrderResolver
  ├── SellOrderGenerator    # sell mode — sell cursor + sell order on buildings
  └── RepairOrderGenerator  # repair mode — repair cursor + repair order on buildings
```

Each generator has:
- `get_cursor(target, target_cell, target_pos, modifiers) → CursorState.Type`
- `get_orders(target, target_cell, target_pos, modifiers) → Array[OrderResult]`
- `cancel() → void`

### OrderSystem (autoload)

```gdscript
var active_generator: OrderGenerator = UnitOrderGenerator.new()

func get_cursor(...) → CursorState.Type:
    return active_generator.get_cursor(...)

func get_orders(...) → Array[OrderResult]:
    return active_generator.get_orders(...)

func set_generator(gen: OrderGenerator):
    active_generator = gen

func cancel():
    active_generator.cancel()
    active_generator = UnitOrderGenerator.new()
```

### Sell/Repair Mode

When the player toggles sell/repair mode in the sidebar:
```
Sidebar: sell button pressed
  → OrderSystem.set_generator(SellOrderGenerator.new())
  → MouseHandler cursor: delegates to OrderSystem.get_cursor()
  → MouseHandler click: delegates to OrderSystem.get_orders()
  → SellOrderGenerator.get_cursor(): returns SELL if building under cursor, else SELL_BLOCKED
  → SellOrderGenerator.get_orders(): returns [OrderResult with sell callback]
  → Right-click or toggle: OrderSystem.cancel() → restores UnitOrderGenerator
```

### Modifier Support

Modifiers passed from MouseHandler as a Dictionary:
```gdscript
var modifiers := {
    "force_attack": Input.is_key_pressed(KEY_CTRL),
    "force_move": Input.is_key_pressed(KEY_ALT),
    "queued": Input.is_key_pressed(KEY_SHIFT),
}
```

Components check these in `get_order_for_target()`:
- `force_attack` → CombatComponent can target allies/terrain
- `force_move` → MovementController overrides CombatComponent on enemy actors

### Priority Chain

| Component | Target Condition | Cursor | Priority |
|-----------|-----------------|--------|----------|
| `CombatComponent` | Enemy unit/building | `ATTACK` | 30 |
| `HarvestComponent` | Tiberium (ResourceComponent) | `HARVEST` | 20 |
| `HarvestComponent` | Refinery (DockHostComponent) | `ENTER` | 15 |
| `TransportComponent` | Friendly infantry | `ENTER` | 10 |
| `DeployComponent` | Self (can deploy) | `DEPLOY` | 15 |
| `MovementController` | Ground (no entity) | `MOVE` | 5 |
| Any | — | `DEFAULT` | 0 |

### Example Scenarios

| Selection | Target | Cursor | Order | Why |
|-----------|--------|--------|-------|-----|
| Harvester + Tank | Tiberium | HARVEST | harvest | Harvest priority 20 > Attack priority 0 |
| Harvester + Tank | Enemy Tank | ATTACK | attack | Attack priority 30 > Harvest priority 0 |
| Harvester + Tank | Refinery | ENTER | dock | Enter priority 15 (harvest) > Attack 0 (friendly) |
| Two Buggies | Ground | MOVE | move | Move priority 5 |
| Combat unit + friendly unit | Friendly unit | SELECT | (none) | No order targeter matches allies |
| MCV (deployable) | Self | DEPLOY | deploy | Deploy priority 15 |
| Empty selection | Anything | DEFAULT | (none) | No components queried |

### Cursor Types (52 total)

- **Scroll (16)**: 8 directions × 2 (normal + blocked). Edge detection at 20px from viewport edge.
- **Joystick (17)**: center + 8 directions × 2 (normal + blocked). Middle-click panning directional cursor.
- **Core (12)**: default, select, move, move-blocked, attack, attack-out-of-range, harvest, enter, guard, sell, repair, generic-blocked
- **Deploy (2)**: deploy, deploy-blocked
- **Minimap (28)**: Same sprites at 16×16 (asset-ready, not used yet)

### Files to Create

| File | Purpose |
|------|---------|
| `scripts/orders/OrderResult.gd` | Data class — cursor, priority, order_id, execute callback |
| `scripts/orders/OrderResolver.gd` | Static — iterates components, picks best OrderResult |
| `scripts/orders/OrderGenerator.gd` | Base class — get_cursor(), get_orders(), cancel() |
| `scripts/orders/UnitOrderGenerator.gd` | Default — normal gameplay, uses OrderResolver |
| `scripts/orders/SellOrderGenerator.gd` | Sell mode — sell cursor on buildings |
| `scripts/orders/RepairOrderGenerator.gd` | Repair mode — repair cursor on damaged buildings |
| `scripts/core/OrderSystem.gd` | Autoload — holds active generator, delegates input |

### Files to Modify

| File | Changes |
|------|---------|
| `scripts/hud/MouseHandler.gd` | Delegate cursor + order resolution to OrderSystem; remove hardcoded sell/repair/deploy logic |
| `scripts/core/SelectionManager.gd` | Remove `request_harvest()`, `request_dock()`, `request_deploy()` — execution moves to component OrderResult.execute callbacks. `request_move()` stays — called by UnitOrderGenerator for group formation. |
| `scripts/components/MovementController.gd` | Add `get_order_for_target()` — returns MOVE order for terrain targets |
| `scripts/components/CombatComponent.gd` | Add `get_order_for_target()` — returns ATTACK order for enemy actors |
| `scripts/components/HarvestComponent.gd` | Add `get_order_for_target()` — returns HARVEST for resources, ENTER for dock hosts |
| `scripts/components/TransportComponent.gd` | Add `get_order_for_target()` — returns ENTER for friendly transports |
| `scripts/components/DeployComponent.gd` | Add `get_order_for_target()` — returns DEPLOY for self, MOVE for undeploy |
| `scripts/ui/Sidebar.gd` | Wire sell/repair toggle to `OrderSystem.set_generator()` |
| `project.godot` | Register OrderSystem autoload |

## 7. Debug/Developer Menu

**GitHub Issue**: #27 — feat: in-game debug menu

### Overview
In-game debug/developer panel toggled with ~ (tilde) key. Panel appears top-left as a dropdown overlay. Semi-transparent dark background, clean dev tool style. Game continues running underneath.

### Toggle & Layout
- **Key**: ~ (tilde/backtick, KEY_QUOTELEFT)
- **Position**: Top-left, dropdown from top
- **Size**: Medium (~400px wide, full height)
- **Style**: White/light gray text on dark semi-transparent background
- **Input**: Context-dependent — clicks inside panel captured, clicks outside pass through to game
- **State**: All toggles persist across open/close

### Accordion Sections (in order)
1. **Overlays** — Checkboxes for 5 debug overlays
2. **Lighting** — Sliders for all sun/sky/environment properties
3. **State** — Game stats (entity counts, FPS, etc.)
4. **Cheats** — Separate toggles for bypasses + action buttons
5. **Entity Inspection** — Click-to-inspect any entity (shows all component data)

### Debug Overlays (checkboxes)
| Overlay | What it draws |
|---------|--------------|
| Pathfinding lines | Green/gray lines to movement target (extends existing DebugVisualizer) |
| Spatial hash grid | Grid lines + occupancy counts from SpatialHashSingleton |
| Entity bounds | Selection box outlines per entity |
| Health bars | Color-coded bar above every entity (not just selected) |
| Entity IDs | Floating text label per entity (display_name + id) |

All overlays redraw every frame via new `DebugOverlay.gd` Node3D.

### Lighting Controls (sliders)
| Property | Source |
|----------|--------|
| Sun Elevation | LightPivot rotation.x (degrees) |
| Sun Rotation | LightPivot rotation.y (degrees) |
| Sun Intensity | DirectionalLight3D.energy |
| Sun Color | DirectionalLight3D.light_color |
| Shadow Strength | DirectionalLight3D shadow_opacity + shadow_blur |
| Ambient Light | WorldEnvironment.ambient_light_energy |
| Fog Density | WorldEnvironment.fog_density |
| Sky Rotation | WorldEnvironment.sky_rotation |
| Glow Intensity | WorldEnvironment.glow_intensity |

Uses LightingData resource + LightingControls script (long-term: reusable by MapEditor and MapLoader).

### Game State (display)
| Stat | Source |
|------|--------|
| Entity count by type | get_tree().get_nodes_in_group("entities") grouped by entity_type |
| Entity count by player | Grouped by player_id |
| Spatial hash occupancy | SpatialHashSingleton.get_entries().size() |
| Current selection | SelectionManager.get_selected_entities() |
| Economy state | EconomyManager credits per player |
| FPS | Engine.get_frames_per_second() |

### Cheats (toggles + buttons)
**Separate toggles (persist across open/close):**
- No prerequisites — PrerequisiteSystem.can_build() always returns true
- No build time — ProductionManager._process() multiplies delta by 999
- No cost — EconomyManager.deduct() is no-op
- Place anywhere (non-building entities) — BuildingManager.can_place() returns true for non-blocking cells

**Action buttons (one-way):**
- Clear All Paths — DebugVisualizer.clear_all()
- Add 100k Credits — EconomyManager.add(player_id, 100000)

Entity spawning repurposes existing build menu. When cheats are on, Sidebar shows all entities regardless of prerequisites, production is instant, placement uses BuildingManager flow.

### Entity Inspection (click-to-inspect)
- Click any entity when debug panel is open → Inspect section fills with data
- Shows: Identity, Health, Combat, Movement, Position, Foundation, Power, Groups, EntityData fields
- Click empty space → section clears
- Read-only in v1 (no live-editing)

### Architecture
```
DebugMenu.gd (panel UI, toggles, cheat flags)
  ├── references DebugOverlay.gd (draws overlays)
  ├── references LightingControls.gd (applies lighting)
  └── DebugMenu flags (cheat bypasses)

LightingControls.gd (owns LightPivot + WorldEnvironment)
  ├── reads/writes LightingData.gd (serializable resource)
  └── used by: DebugMenu, MapEditor (future), MapLoader

LightingData.gd (resource class)
  └── stored in MapConfig.gd as lighting field
```

### File Changes

**New files (5):**
| File | Purpose |
|------|---------|
| `scripts/data/LightingData.gd` | Resource class — all lighting properties |
| `scripts/environment/LightingControls.gd` | Controls lighting nodes, apply()/get_data() |
| `scripts/ui/DebugMenu.gd` | Panel controller script |
| `scenes/ui/DebugMenu.tscn` | Panel scene |
| `scripts/ui/DebugOverlay.gd` | Overlay drawing Node3D |

**Modified files (9):**
| File | Change |
|------|--------|
| `project.godot` | Add `toggle_debug` input action (KEY_QUOTELEFT) |
| `scenes/maps/MapBase01.tscn` | Instance LightingControls, DebugMenu, DebugOverlay |
| `scripts/data/MapConfig.gd` | Add `@export var lighting: LightingData` |
| `scripts/maps/MapLoader.gd` | Load lighting from MapConfig, call LightingControls.apply() |
| `scripts/ui/Sidebar.gd` | Gate _get_current_entities() on DebugMenu.no_prereqs |
| `scripts/production/ProductionManager.gd` | Gate _process() on DebugMenu.no_build_time |
| `scripts/core/PrerequisiteSystem.gd` | Gate can_build() on DebugMenu.no_prereqs |
| `scripts/economy/EconomyManager.gd` | Gate deduct() on DebugMenu.no_cost, add add_credits() |
| `scripts/hud/MouseHandler.gd` | Gate click handling on DebugMenu panel rect |

## Future Enhancements
- Customizable UI scaling and positioning
- Compact vs expanded view modes
- Tooltip system for all UI elements
- Accessibility features (colorblind modes, high contrast)
- Debug menu: live-edit entity fields (v2)
- Debug menu: MapEditor lighting integration
