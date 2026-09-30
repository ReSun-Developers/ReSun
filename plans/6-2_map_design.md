# Map Design & Level Editor - ReSun

## Overview
The map design system provides tools for creating, editing, and loading custom maps. This enables modding community engagement and varied gameplay experiences.

## Implementation Status (verified 2026-08-08)

**MapEditor exists and is functional** (`scenes/editor/MapEditor.tscn`, `scripts/editor/MapEditor.gd`, runtime tool with `get_meta("is_map_editor")` guard):

| Tool/Feature | Status | Notes |
|--------------|--------|-------|
| File menu (New/Load/Save) | ✅ | JSON v4 via `EditorSaveLoad.gd` + `TerrainSystem.export_to_json` |
| New Map dialog | ✅ | W/H + insets + visible-bounds preview; **Starting Height and Player Count captured but ignored** (params unused); dialog max 12 vs `TerrainSystem.MAX_HEIGHT`=10 |
| Paint Height | ✅ | Single-cell drag (`HeightPainter`); no brush radius |
| Paint Resource (Tiberium) | ✅ | Radius brush (`ResourcePainter`) |
| Place Tree / Erase | ✅ | |
| Entity placement | ✅ | Buildings/units via `EntityPlacer` + `EntityBrowser` (search, owner player); TERRAIN/OVERLAY/SMUDGE categories missing from browser |
| Grid + hover highlight | ✅ | Diamond-clipped |
| Minimap | ✅ | Editor-only ortho SubViewport |
| Undo/redo | ❌ | Open #200 |
| Land-type paint | ❌ | Open #228 |
| Theater selector | ❌ | `theater_id` never written; open #203/#206 |
| Player start / MapConfig authoring | ❌ | `MapConfig`/`PlayerConfig` exist as data, no editor surface; `starting_units` spawning "not yet implemented" per map-config spec |
| Scenario/trigger system | ❌ | `ScenarioScripter`/`MissionManager` never built — entire mission layer missing |

**Plan-doc staleness:** this doc's `TerrainPainter.gd`, `ScenarioScripter.gd`, `MissionManager.gd` scene structure never existed. Map persistence is JSON v4 (terrain + entities + bounds), not the `map_data` dict in this doc.

For GDI Mission 01, the authentic falls/river/bridge geography is blocked on #228–#231 (land-type paint, water render, cliff tiling, bridges); a simplified hand-built JSON map works today (land types + pathfinding already function in-game).

---

## Core Requirements

### 1. Map Import Pipeline
- Support standard format imports (JSON, XML, or custom binary)
- Validate map dimensions against engine limits
- Auto-generate navmesh from terrain data
- Pre-process assets for optimization (LOD generation)

### 2. Scenario Scripting System
- Event triggers based on conditions (time, units destroyed, resources)
- Objective definitions (build X units, capture Y points)
- Victory/defeat condition scripting
- Cutscene sequencing with camera controls

### 3. Trigger & Event System
| Trigger Type | Condition Examples | Actions |
|--------------|-------------------|---------|
| Time | After 5 minutes | Spawn reinforcements |
| Unit Death | When player loses factory | Create enemy unit wave |
| Resource | Player reaches 5000 credits | Unlock tech level |
| Territory | Control 80% of map | Trigger victory screen |

### 4. Campaign Structure
- Mission sequencing with progression unlocks
- Save/load state between missions
- Tutorial integration for new players
- Victory/defeat consequence tracking

## Technical Implementation

### Scene Structure
```
MapEditor.tscn (Tool application)
├── TerrainPainter.gd (tile placement tools)
├── ScenarioScripter.gd (event trigger editor)
└── MissionManager.gd (campaign structure)
```

### Key Scripts

#### TerrainPainter.gd
- Brush-based terrain editing in editor mode
- Tile selection with preview overlay
- Batch operations for large area changes
- Undo/redo stack for safety during edits

#### ScenarioScripter.gd
- Visual node-based trigger editor or text-based DSL
- Condition builder with dropdown selectors
- Action chain linking triggers to effects
- Preview mode for testing scenarios

### Map Data Structure
```gdscript
var map_data = {
    "dimensions": {"width": 1024, "height": 1024},
    "terrain_layers": ["base", "roads", "tiberium"],
    "spawn_points": [
        {"player": 1, "position": Vector3(512, 0, 512)},
        {"player": 2, "position": Vector3(512, 0, 512)}
    ],
    "objectives": [
        {"type": "domination", "threshold": 90},
        {"type": "annihilation", "target_player": 2}
    ]
}

func save_map(path):
    var json_data = JSON.stringify(map_data)
    var file = FileAccess.open(path, FileAccess.WRITE)
    file.store_string(json_data)
```

### Map Editor Toolbar
The MapEditor toolbar provides:
- **Save/Load** — JSON map format (v4 with `map_size`/`visible_bounds`)
- **New Map** — dialog to set map dimensions, reinitializes grid (default 128×128)
- **Inset SpinBox fields** — Left/Right/Top/Bottom insets (cell units) for live editing of the visible bounds; each max is dynamically capped so the visible diamond never exceeds the map or becomes empty
- **Tool buttons** — Paint Height, Paint Resource, Place Tree, Erase
- **Strength/Radius** controls for painting tools
- **Grid toggle** and height label

### Mission Manager Logic
- Load mission configuration from resource files
- Track player progress across campaign sequence
- Handle mission completion/failure states
- Unlock next mission based on victory conditions

## Integration Points
- Connect to terrain system for map generation
- Link with navigation system for auto-navmesh creation
- Coordinate with game manager for scenario execution
- Interface with save/load system for persistence

## Future Enhancements
- Real-time map preview in editor
- Shared asset library for community maps
- Map balancing tools (AI difficulty adjustment)
- Steam Workshop integration for mod distribution
