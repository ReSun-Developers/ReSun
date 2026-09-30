## Context

ReSun is an RTS remake using Redot 26.2 LTS with GDScript. The project has a working A* pathfinding system on a 2m x 2m grid (`Pathfinder.gd`), spatial hash for cell occupancy (`SpatialHash.gd`), and movement controller with catmull-rom interpolation (`MovementController.gd`). Currently, the game world uses a flat ground plane with no terrain variation.

The existing `placeholder_terrain01.glb` contains 79 terrain tile meshes (clear, slope, cliff, water, shore, etc.) with 7 materials. The GLB is imported but unused. Terrain textures exist in `assets/textures/` but only the Ground texture is referenced by TestMap01.

**Constraints**:
- Engine: Redot 26.2 LTS (Forward Plus renderer)
- Language: GDScript only
- Must integrate with existing 2m grid system (`Pathfinder.CELL_SIZE = 2.0`)
- Must maintain backward compatibility with existing scenes (MapBase01, TestMap01)

## Goals / Non-Goals

**Goals:**
- Provide a terrain data system storing per-cell height, type, and variant
- Render terrain meshes from the existing GLB library
- Enable collision using mesh faces as physics shapes
- Create a map editor with isometric view and height painting
- Integrate terrain height with pathfinding and unit movement
- Support JSON import/export for map files

**Non-Goals:**
- Cliff, water, shore, waterfall tiles (future PRs)
- Movement cost modifiers based on terrain type (future PR)
- Destructible terrain (future PR)
- Terrain-based unit bonuses (future PR)
- Advanced selection tools in map editor (future PR)

## Decisions

### Decision 1: TerrainSystem as Autoload Singleton

**Choice**: Create `TerrainSystem` as an autoload singleton registered in `project.godot`.

**Rationale**: 
- Matches existing pattern (`SelectionManager` is an autoload)
- Provides global access for pathfinding, movement, and editor
- Centralizes terrain state management

**Alternatives considered**:
- Node in scene tree: Would require passing references everywhere
- Static class like `Pathfinder`: Wouldn't support signals or scene tree integration

### Decision 2: Dictionary-Based Cell Storage

**Choice**: Store cells in a `Dictionary` keyed by string `"x,y"` (matching `Pathfinder._cell_key()` pattern).

**Rationale**:
- Consistent with existing `SpatialHash` and `Pathfinder` patterns
- O(1) lookup for cell queries
- Easy JSON serialization (Dictionary → JSON)
- Sparse storage (only modified cells exist)

**Alternatives considered**:
- 2D Array: Would require fixed grid size, wastes memory for sparse maps
- Resource-based: Overkill for simple cell data

### Decision 3: GLB Mesh Extraction at Runtime

**Choice**: Load the GLB as a `PackedScene`, extract meshes by node name at runtime.

**Rationale**:
- Reuses existing imported asset
- Meshes are already named (clear01-08, slope01-06, etc.)
- Can instance specific variants per cell
- Materials are embedded in GLB (no separate .tres files needed)

**Alternatives considered**:
- Export meshes to separate .tres resources: More manual work, harder to maintain
- Use MeshLibrary: Would require pre-building library, less flexible

### Decision 4: Mesh Faces as Collision Shapes

**Choice**: Use `MeshShape3D` with the terrain mesh directly as collision shape.

**Rationale**:
- Slope meshes have only 4-6 vertices (very cheap)
- Collision perfectly matches visual mesh
- No manual collision shape authoring needed
- Works for all terrain types (clear, slope, future cliffs)

**Alternatives considered**:
- BoxShape3D at height: Would not match slope geometry
- Manual TrimeshShape3D: Same result but more work

### Decision 5: Isometric Camera for Map Editor

**Choice**: Reuse existing `CameraController` with isometric projection for map editor.

**Rationale**:
- Already implemented with WASD/mouse/border panning
- Matches gameplay camera (consistent UX)
- Orthographic projection works well for tile-based editing

**Alternatives considered**:
- Top-down orthographic: Less intuitive for height visualization
- Perspective camera: Harder to judge tile alignment

### Decision 6: SubViewport for Minimap

**Choice**: Use a `SubViewport` rendering a top-down view of the terrain.

**Rationale**:
- Can render terrain with color-coded materials
- Click-to-move functionality for camera navigation
- Separated from main viewport (no performance impact)

**Alternatives considered**:
- 2D texture overlay: Would require manual updates
- Separate camera in main viewport: Would conflict with editor camera

### Decision 7: Height Interpolation in MovementController

**Choice**: Interpolate Y-position as unit traverses slope cells based on progress (0.0 to 1.0).

**Rationale**:
- Provides smooth visual transition on slopes
- Matches user's requirement: "start Y=0, middle Y=0.4075, end Y=0.815"
- Works with existing catmull-rom spline interpolation

**Alternatives considered**:
- Snap to final height: Would look jarring on slopes
- Physics-based: Overkill for simple height transitions

## Risks / Trade-offs

### Risk 1: GLB Mesh Naming Convention
**Risk**: Mesh names in GLB may not match expected pattern (clear01, slope01, etc.).
**Mitigation**: Verified via Python analysis - all 79 meshes follow naming convention. Will add fallback for unknown names.

### Risk 2: Performance with Many Cells
**Risk**: Large maps (200x200 = 40,000 cells) could have performance issues with mesh instancing.
**Mitigation**: Use object pooling for mesh instances. Only render visible cells (frustum culling). Future optimization: merge static terrain into single mesh.

### Risk 3: Collision Shape Complexity
**Risk**: MeshShape3D with many triangles could be expensive for physics.
**Mitigation**: Slope meshes have 4-6 vertices (very cheap). Clear cells are flat planes (1 quad). Future cliffs will have more vertices but still manageable.

### Risk 4: JSON File Size
**Risk**: Large maps could produce large JSON files (20,000+ cells).
**Mitigation**: Use compact JSON format. Future optimization: binary format or run-length encoding.

### Risk 5: Backward Compatibility
**Risk**: Modifying Pathfinder.gd and MovementController.gd could break existing movement.
**Mitigation**: Height queries are additive (default to 0 if no terrain data). Existing flat-ground behavior preserved when no terrain system is loaded.
