# Terrain Systems - ReSun

## Overview
The terrain system defines the physical foundation of the game world, affecting unit movement, building placement, and resource distribution. This creates strategic depth through varied landscapes.

## Implementation Status (verified 2026-08-08)

| Capability | Status | Notes |
|------------|--------|-------|
| Heightfield terrain system | ✅ | `TerrainSystem.gd` — vertex grid, 4-dir cascade smoothing, JSON v4 |
| Terrain rendering | ✅ | `TerrainRenderer.gd` — MultiMesh per GLB submesh, pink placeholder fallback |
| Heightfield collision | ✅ | `intersect_heightfield_segment` + `HeightMapShape3D` |
| Rectangular grid + diamond bounds | ✅ | `CellUtil.is_in_diamond` (2·W·H cells), `BoundsSystem` red/blue diamonds, 4-inset visible bounds |
| Land types (data) | ✅ | 6 LandType .tres (clear/rough/road/water/cliff/resource) in GlobalRules |
| Land-type painting (editor) | ❌ | `TerrainSystem.set_land_type` exists, never called by UI — open #228 |
| Movement-cost modifiers | ✅ | Per-locomotor `terrain_speeds` + height cost + bib penalty (Pathfinder/MovementController) |
| Terrain-object catalog | ✅ | 130+ baked .tres (cliffs/slopes/ramps), isotem tooling, `TerrainCatalog` |
| Water | ⚠️ | Land type + passability exist; no water surface mesh/render — open #229 |
| Ice / drowning | ✅ | `IceComponent` + `MovementController._damage_ice` (ice sits on water cells, authoring blocked by #229) |
| Cliffs | ✅ | Height-driven slope/cliff classification + catalog rendering; tiling resolver open #230 |
| Bridges | ❌ | Data-only stubs (`bridge.tres`/`rail_bridge.tres`); no walkable surface — open #231 |
| Tiberium growth/spread | ✅ | `ResourceGrowthSystem` (batched, spread-capped) |
| Harvesting | ✅ | Full loop (see 1-3) |
| Theater selection | ⚠️ | Load-side only (`theater_id` → `TerrainCatalog.set_active_theater`); only `temperate`; editor can't set/save — open #203/#206 |

**Plan-doc staleness:** the "Scene Structure" (`TerrainManager` / `ElevationCalculator` / `TiberiumGenerator` singletons) never existed — superseded by `TerrainSystem.gd` + `ResourceGrowthSystem.gd` + the isotem catalog. The movement-modifier table (hills 65–80%, forest 70%, road 140%) is aspirational; the shipped model is per-locomotor `terrain_speeds`.

## Historical Implementation Status (stale — kept for reference)

- ✅ EntityData.gd — terrain entities use `entity_type = TERRAIN`
- ✅ .tres file created for TREE01 (destructible tree)
- 🔄 Remaining: ~25 more terrain .tres files (Issue #23), locomotor enforcement (Issue #34) — *both done; roster is ~44 terrain .tres, locomotors fully enforced*

## Core Requirements

### 1. Terrain Types & Movement Modifiers
| Terrain Type | Speed Modifier | Notes |
|--------------|----------------|-------|
| Flat Ground | 100% (baseline) | Standard movement speed |
| Hills/Slopes | 65-80% | Reduced vehicle speed, infantry unaffected |
| Rocky/Rough | 50% | Significant slowdown for all units |
| Water - Shallow | 30% | Naval only, ground blocked |
| Water - Deep | 0% (blocked) | Untaversable by any unit |
| Tiberium Fields | 90% + toxicity | Slow movement with health drain |
| Road Networks | 140% | Vehicle speed bonus |
| Forest/Wooded | 70% | Cover bonus, slowed movement |

### 2. Elevation System
- Height values determine buildable vs unbuildable areas
- Cliff edges prevent building placement
- Slope calculations for unit traversal feasibility
- Visual height representation via terrain mesh

### 3. Tiberium Distribution
- Random generation with seed control for replayability
- Cluster patterns (small, medium, large fields)
- Depletion mechanics over time during matches
- Special "rich" nodes with higher resource value

### 4. Environmental Hazards (Optional)
- Radiation zones damage units over time
- Lava/acid destroys structures instantly
- Storms reduce visibility or unit effectiveness
- Dynamic terrain changes mid-game

## Technical Implementation

### Entity System Integration
Terrain objects (trees, rocks, fauna, flora) are entities with minimal components (see GitHub Issue #22):

```
EntityData.tres (entity_type = TERRAIN)
    ↓ EntityFactory autoload
Entity.tscn + optional components
```

- **Terrain entities** use the same `EntityData.gd` resource as all other entities
- `entity_type = TERRAIN` — SelectComponent is NOT added (not selectable)
- `strength = 0` → HealthComponent NOT added (indestructible)
- `strength > 0` → HealthComponent added (destructible trees/rocks)
- `foundation: Vector2i` → FoundationComponent added (terrain objects can have footprints)
- Trees/rocks use `art_data: ArtData` for model and visual properties

### Terrain Object Data Example
```gdscript
# Example: TREE01 (destructible)
{
    "id": "TREE01",
    "display_name": "Tree",
    "entity_type": "TERRAIN",
    "strength": 200,          # from rules.ini TreeStrength=200
    "armor": "wood",
    "foundation": Vector2i(1, 1),
    "art_data": preload("res://resources/art/terrain/tree01_art.tres")
}

# Example: SROCK01 (indestructible)
{
    "id": "SROCK01",
    "display_name": "Small Rock",
    "entity_type": "TERRAIN",
    "strength": 0,            # 0 = indestructible
    "foundation": Vector2i(1, 1)
}
```

### Scene Structure
```
TerrainSystem.tscn (Autoload Singleton)
├── TerrainManager.gd (singleton terrain data)
├── ElevationCalculator.gd (height/slope logic)
└── TiberiumGenerator.gd (resource placement)
```

### Key Scripts

#### TerrainManager.gd (Singleton)
- Store tile-based terrain data in 2D array
- Query tile properties for movement/building validation
- Cache frequently accessed terrain info for performance
- Emit signals when terrain changes (depletion, destruction)

#### ElevationCalculator.gd
- Calculate slope between adjacent tiles
- Determine if unit can traverse elevation change
- Generate heightmap for visual rendering
- Provide buildability data based on terrain type

### Terrain Data Structure
```gdscript
var terrain_tiles = {
    "flat": {"speed_mod": 1.0, "buildable": true},
    "hill": {"speed_mod": 0.75, "buildable": false},
    "rocky": {"speed_mod": 0.5, "buildable": true},
    "water_shallow": {"speed_mod": 0.3, "naval_only": true},
    "water_deep": {"speed_mod": 0.0, "blocked": true},
    "tiberium": {"speed_mod": 0.9, "resource_value": 100},
    "road": {"speed_mod": 1.4, "vehicle_only": true}
}

func get_terrain_modifier(position):
    var tile = terrain_tiles_at.get_tile(position)
    return tile.terrain_type.speed_mod
```

### Tiberium Generation Algorithm
- Seed-based random placement for consistency
- Cluster generation: create groups of tiles with resource value
- Depletion tracking per match instance
- Rich nodes have higher harvest yield and slower depletion

### 5. Bounds System (Autoload Singleton)
- Diamond-shaped bounds mesh rendered via `BoundsSystem.gd` (`ImmediateMesh`), registered as autoload singleton
- **Outer bounds** (red): visual boundary, 1 cell margin inward from grid edge
- **Visible bounds** (blue): play area boundary, configurable offset from outer bounds (default 10 cells x, 8 cells z)
- Both meshes sample terrain height at cell centers along diamond edges (`get_height_at_world_smooth()`), producing multi-vertex meshes that follow terrain contours
- Single source of truth for gameplay bounds: `is_in_map_bounds()`, `is_in_play_area()` used by `BuildingManager` and `ResourceGrowthSystem`
- Camera clamping follows visible bounds (not outer bounds)
- API returns cell units; visual mesh converts to world units for rendering
- `@tool` script with `Engine.is_editor_hint()` guards for Redot IDE compatibility

## Integration Points
- Connect to pathfinding system for movement cost calculation
- Link with base building for build placement validation
- Coordinate with economy system for resource harvesting
- Interface with minimap for terrain visualization

## Related
- **Entity System**: See GitHub Issue #22 — composition-based architecture (IMPLEMENTED)
- **Map Design**: See `6-2_map_design.md` for terrain layout guidelines
- **Navigation**: See `2-1_navigation.md` for pathfinding over terrain
- **Data Population**: See GitHub Issue #23 for terrain entity .tres files
- **MovementController**: Issue #34 — implement locomotor enforcement and movement zones

## Historical Implementation Status (stale — kept for reference)

- ✅ EntityData.gd — terrain entities use `entity_type = TERRAIN`
- ✅ .tres file created for TREE01 (destructible tree)
- 🔄 Remaining: ~25 more terrain .tres files (Issue #23), locomotor enforcement (Issue #34) — *both done; roster is ~44 terrain .tres, locomotors fully enforced*

## Future Enhancements
- Destructible terrain (craters from explosions)
- Seasonal terrain changes affecting gameplay
- Dynamic weather modifying terrain properties
- Terrain-based unit bonuses (forest cover defense)
