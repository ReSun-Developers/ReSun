# Navigation & Pathfinding System - ReSun

## Overview
The navigation system provides pathfinding capabilities for all moving entities, enabling units to traverse terrain efficiently while avoiding obstacles and respecting movement constraints. The grid cell size is **2m × 2m** — each vehicle unit occupies exactly one cell (radius = 1.0).

> **Phase note (verified 2026-08-08):** Phase 1 straight-line movement was superseded — a **custom grid A\*** is now the global pathfinder. `NavigationServer3D` is **not** used. The Phase 1/Phase 2 split in this doc is historical; the shipped system is at "Phase 2+" quality with local radial repulsion steering layered on top of A* waypoints.

## Implementation Status (verified 2026-08-08)

Implemented and tested:
- **`Pathfinder.gd`** — 8-dir binary-heap A*, terrain cost via `Locomotor.get_speed_multiplier`, height-climb tolerance, bib-cell penalty, ice-as-footing on water, LOS string-pulling (`smooth_path`), best-reached fallback
- **`MovementController.gd`** (~1000 lines) — IDLE/ROTATING/MOVING/WAIT states, Catmull-Rom spline waypoints (`SplineUtil`), radial repulsion steering, **9 locomotors** (Foot/Track/Wheel/Hover/Amphibious/Fly/Jumpjet/Subterranean/Ship), slope coefficients, crushing, ice cracking, sub-slot cell sharing, jumpjet vertical state machine, wait-state scatter
- Supporting: `SpatialHash`, `CellReservation`, `CellSubPositions`, `CellUtil`, `BoundsSystem`, `Locomotor`/`LandType` registries in `GlobalRules`
- Tests: `test_pathfinder*.gd`, `test_movement_*.gd`, `test_locomotor_registry.gd`, `test_pathfinder_terrain.gd`

Not implemented from this plan:
- Terrain toxicity damage (tiberium fields drain health) — land-type speed multipliers exist, health drain does not
- Road speed bonus (road land type exists; no separate 0.7× bonus path)

Terrain cost modifiers in this doc's table (hills 1.5×, road 0.7×, tiberium 1.2×+toxicity) are **aspirational** — the shipped model is per-locomotor `terrain_speeds` for clear/resource/road/rough + height cost + bib penalty.

---

## Core Requirements

### 1. Pathfinding Approach Selection
- **Phase 1 (current)**: No global pathfinding — straight-line movement with local radial repulsion steering for obstacle avoidance between units on a shared grid. Movement is kinematic (`global_position += direction * speed * delta`), no physics bodies.
- **Phase 2**: A* or navmesh-based pathfinding via Redot's `NavigationServer3D`. Units follow waypoint arrays computed from the navigation mesh, with local repulsion steering layered on top for dynamic obstacles (other units).
- **Grid Resolution**: 2m cells — each vehicle unit occupies exactly one cell. Occupancy radius = 1.0 m per unit center. Pathfinding queries snap to nearest walkable cell node.
- **Dynamic Updates**: Real-time obstacle avoidance via radial repulsion steering in Phase 1; navmesh carving or dynamic cost updates for destructible terrain in later phases.

### 2. Terrain Cost Modifiers (Phase 2+)
| Terrain Type | Movement Cost | Notes |
|--------------|---------------|-------|
| Flat Ground | 1.0x | Standard speed |
| Hills/Slopes | 1.5x | Reduced unit speed |
| Water/Shallow | 2.0x | Naval units only |
| Deep Water | ∞ (blocked) | Untaversable |
| Tiberium Fields | 1.2x | Toxicity penalty over time |
| Road Networks | 0.7x | Speed bonus for vehicles |

### 3. Dynamic Obstacle Avoidance
- **Phase 1**: Radial repulsion steering — each unit checks nearby entities within ~3m radius and adds push-away forces normalized by distance² to its movement direction, causing natural flow-around behavior without global pathfinding.
- Phase 2+: Navmesh-based avoidance with dynamic obstacle recalculation when blocked mid-navigation; separation forces prevent clustering; emergency stop on imminent collision detection.

### 4. Cell Occupancy Rules (Phase 1+)
| Rule | Behavior |
|------|----------|
| One vehicle per cell | Each unit declares a circular occupancy radius of ~1.0 m (half the 2m cell size) |
| Smooth sliding between cells | Movement is continuous — units glide across cell boundaries without snapping or grid-lock stepping |
| Path around via repulsion | Radial repulsion steering causes units to naturally flow around each other when their paths converge, preventing stacking and creating Tiberian Sun-style traffic behavior |

### 4. Path Smoothing
- Raw path points smoothed for natural movement curves
- Bezier interpolation between waypoints
- Unit-specific turning radii (tanks vs infantry)
- Speed-based waypoint skipping at high velocities

## Technical Implementation

### Scene Structure
```
NavigationRoot.tscn (Node3D)
├── NavMeshManager.gd (singleton)
├── PathFinder.gd (A* algorithm implementation)
└── ObstacleAvoidance.gd (steering behavior)
```

### Key Scripts

#### NavMeshManager.gd (Singleton)
- Manages navmesh generation from terrain data
- Handles multiple navigation layers per faction/terrain type
- Caches path queries for performance optimization
- Updates on map changes or new obstacles

#### PathFinder.gd
- A* implementation with heuristic function
- Node expansion based on movement costs
- Path reconstruction from parent pointers
- Fallback to fallback paths when primary blocked

### Navmesh Generation Algorithm
```gdscript
func generate_navmesh_from_terrain(terrain_data):
    var nav_nodes = []
    
    for tile in terrain_data.tiles:
        if is_walkable(tile.terrain_type, unit_type):
            # Create navigation node at tile center
            var node = NavMeshNode.new()
            node.position = tile.center
            node.cost_modifier = get_movement_cost(tile.terrain_type)
            
            # Connect to adjacent walkable tiles
            for neighbor in tile.get_neighbors():
                if is_walkable(neighbor.terrain_type, unit_type):
                    node.add_connection(neighbor, calculate_distance(node, neighbor))
            
            nav_nodes.append(node)
    
    return build_graph(nav_nodes)
```

### Path Smoothing Implementation
- Apply Catmull-Rom or Bezier curves to raw waypoints
- Skip intermediate points at high speeds (optimize path length)
- Respect unit turning radius by adjusting curve tightness
- Re-smooth when path updates mid-navigation

## Integration Points
- Connect to movement system for path-following execution
- Link with selection system for unit grouping navigation
- Coordinate with combat AI for tactical movement decisions
- Interface with minimap for visible path overlay (debug mode)

## Future Enhancements
- Hierarchical pathfinding for large maps (coarse-to-fine approach)
- Dynamic navmesh updates during gameplay (destructible terrain)
- Multi-agent path coordination (group formations)
- Machine learning optimized paths based on player behavior
