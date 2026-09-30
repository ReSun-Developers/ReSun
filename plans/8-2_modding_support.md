# Modding Support - ReSun

## Overview
Modding support empowers the community to create custom content, extending game longevity and fostering creativity. This includes units, maps, factions, and gameplay mechanics.

## Implementation Status (verified 2026-08-08)

**Partial scaffold only:**

- ✅ `register_data_set()` exists in 3 autoloads — `EntityFactory.gd:82`, `TerrainCatalog.gd:46`, `AudioManager.gd:32` — providing the layered data-set loading this plan calls for
- ❌ No ModManager / mod loader / validation / load-order handling
- ❌ No asset import/export tools (isotem terrain tooling is a partial analogue)
- ❌ No script extensibility hooks / event API
- ❌ No mod distribution pipeline / UI

Not on the critical path for GDI Mission 01.

---

## Core Requirements

### 1. Modding Framework Design
- **Asset Loading**: Dynamic resource loading from mod directories
- **Script Extensibility**: GDScript hooks for modifying behavior
- **Data Files**: JSON/YAML definitions for custom units/buildings
- **Validation System**: Check mods for errors before loading

### 2. Custom Content Creation
| Content Type | Modification Points | Example Mods |
|--------------|---------------------|--------------|
| Units | Stats, models, weapons | New vehicle types |
| Buildings | Costs, production times | Unique faction bases |
| Maps | Terrain, objectives | Campaign missions |
| Factions | Complete overhaul | Total conversion mods |
| UI | Skins, layouts | Theme modifications |

### 3. Asset Import/Export Tools
- Model format converters (GLB/FBX to engine format)
- Texture optimization pipelines for performance
- Sound asset compression and streaming setup
- Batch import tools for large mod packages

### 4. Script Extensibility Points
- Event hooks: `on_unit_destroyed`, `on_building_built`
- Overrideable functions in base classes
- Custom ability creation via script templates
- Mission scripting API for campaigns

### 5. Mod Distribution Pipeline
- Workshop-style platform for sharing mods
- Version control with changelog tracking
- Dependency management (mod A requires mod B)
- Auto-update system for subscribed mods

## Technical Implementation

### Scene Structure
```
ModdingSystem.tscn (Autoload Singleton)
├── ModManager.gd (mod loading/unloading)
├── AssetImporter.gd (file conversion tools)
└── ScriptAPI.gd (exposed hooks and events)
```

### Key Scripts

#### ModManager.gd
- Scan mod directories for valid content packages
- Validate JSON/YAML definitions before import
- Handle load order dependencies between mods
- Provide UI for enabling/disabling active mods

#### AssetImporter.gd
- Convert external assets to engine-compatible formats
- Optimize textures/meshes based on target platform
- Generate LOD variants automatically
- Compress audio files with quality presets

### Mod Data Structure Example
```json
{
  "mod_id": "custom_faction_nod_revamp",
  "version": "1.2.0",
  "author": "CommunityModder",
  "dependencies": ["base_game"],
  
  "units": [
    {
      "name": "Cyborg Assassin",
      "faction": "NOD_CUSTOM",
      "cost_credits": 850,
      "health": 200,
      "special_ability": "stealth_invisibility"
    }
  ],
  
  "scripts": ["mods/custom_faction/scripts/assassin.gd"]
}
```

### Script API Exposure
- Expose game events as GDScript signals for mod scripts to connect
- Provide base classes that mods can extend/instantiate
- Document all available hooks in developer documentation
- Sandbox mod execution to prevent crashes affecting main game

## Integration Points
- Connect to unit roster system for custom unit registration
- Link with map editor for mod-created scenarios
- Coordinate with faction systems for new faction content
- Interface with save/load for mod persistence across sessions

## Future Enhancements
- In-game mod browser with search/filter functionality
- Mod rating and review system
- Developer tools within editor for easy mod creation
- Community showcase page featuring top mods
