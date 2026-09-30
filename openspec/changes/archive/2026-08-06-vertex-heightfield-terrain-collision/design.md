## Context

Terrain geometry authority is `TerrainSystem._vertex_grid` — per-vertex integer heights in `0..MAX_HEIGHT` scaled by `HEIGHT_STEP = 0.815`, on a diamond footprint defined by `grid_cells`. Every live terrain consumer (movement, picking, placement, debug, cell-type derivation, save/load) reads this one source via bilinear sampling (`get_height_at_world_smooth`). Authored `TerrainObject` tiles carry richer per-cell data (corners, `crease` diagonal, land types) but are not stamped into the runtime grid — the editor paints vertices, and all runtime geometry derives from them.

The old `TerrainCollision.gd` built per-cell `StaticBody3D` trimesh bodies from GLB submeshes (art), had zero consumers, and is being removed (issue #208). Issue #209 directs future terrain physics to derive from the vertex heightfield instead. Redot 26.2 ships `HeightMapShape3D` (a fixed-grid heightfield physics shape with NAN-hole support), which is the natural native shape for this.

## Goals / Non-Goals

**Goals:**
- A pure-GDScript segment/ray intersection API against the bilinear vertex heightfield, usable by ballistics and LOS with zero physics-server involvement.
- An opt-in `HeightMapShape3D` builder that mirrors the same heightfield for consumers that need physics collision response (knockback).
- Consistent answers across all surfaces: movement/picking height, math intersection, and the native shape all sample the same bilinear surface.
- Diamond-boundary correctness: no phantom collisions in map corners.

**Non-Goals:**
- Per-cell `StaticBody3D` terrain bodies (explicitly rejected by #208/#209).
- Any default physics body mounting at runtime — consumers opt in.
- Modeling authored `TerrainObject.crease` folds as runtime geometry (policy decision below).
- Caves/overhangs (out of scope for `HeightMapShape3D`; not representable in the heightfield).
- Implementing the consumers (ballistics, LOS, knockback) — this change provides the surface they will use.

## Decisions

### D1: One source of truth — the bilinear vertex heightfield
All three answer surfaces (height query, math intersection, native shape) sample the same bilinear surface over `_vertex_grid`. `get_height_at_world_smooth` is the canonical sampler and is reused/refactored so intersection and shape-building cannot drift from it.

- **Rationale**: the heightfield is already the gameplay authority; deriving collision from it guarantees collision always agrees with movement and picking. Art-independent (works for any theater).
- **Alternative rejected**: reusing `TerrainObject.crease` per-cell data to build folded quad meshes. Authoritative but theater-authored, unavailable at runtime for procedurally painted terrain, and duplicates the mesh fold the renderer already draws.

### D2: Intersection is pure math, not physics
Provide a segment intersection (e.g. `intersect_heightfield_segment(from: Vector3, to: Vector3) -> Dictionary` with hit point + cell, or null) that marches the segment across cells in the heightfield's own XZ grid and tests each cell's bilinear surface. No `PhysicsRayQueryParameters3D`, no server state, headless-testable, deterministic.

- **Rationale**: ballistics and LOS are query-only; a physics body adds server round-trips, layer setup, and frame-timing coupling for no benefit. This mirrors how picking already works (math plane↔heightfield, per #208's investigation).
- **Alternative rejected**: single `HeightMapShape3D` + `intersect_ray` for all consumers. Works, but couples query-only consumers to physics-server setup and rebuild-on-edit costs. Kept as the opt-in path (D3).

### D3: `HeightMapShape3D` builder is opt-in
A method (e.g. `build_heightfield_shape() -> HeightMapShape3D`) fills `map_data` from `_vertex_grid` (`height * HEIGHT_STEP`), with `NAN` for vertices outside the playable diamond, and sets `map_width`/`map_depth` to the square extent. Consumers that need collision response (knockback) instantiate it and own its lifetime.

- **Rationale**: Redot 26.2's `HeightMapShape3D` natively models a fixed-grid heightfield — exactly this data. NAN holes give correct diamond corners. It is faster than `ConcavePolygonShape3D` and only exists when a consumer mounts it.
- **Alternative rejected**: `ConcavePolygonShape3D` from a generated mesh — slower, requires building a triangle mesh that duplicates the heightfield, and can fight the renderer's existing meshes.

### D4: Crease policy — runtime heightfield is bilinear
Runtime collision treats each cell as a bilinear surface (matches `get_height_at_world_smooth` and the current renderer's shared resolution path). Authored `TerrainObject.crease` stays authoritative for art authoring (what the tile mesh *looks like*), and is *not* consulted at runtime collision time.

- **Consequence**: a ballistic reading the bilinear surface can disagree slightly with a visibly folded mesh. Acceptable — the difference is bounded by half the height gradient within a cell, and movement already behaves this way. Documented as a known trade-off; revisit only if a consumer demands pixel-level mesh fidelity.

### D5: Where the code lives
Intersection + shape builder live on `TerrainSystem` (it owns `_vertex_grid` and the sampling math). If the shape-builder grows beyond a few methods, extract a small `scripts/core/TerrainHeightfieldCollision.gd` helper; the decision is deferred until implementation size is known.

## Risks / Trade-offs

- [Bilinear-vs-fold disagreement on steep cliffs] → Bounded by half-cell height gradient; documented in D4. Revisit only if a consumer requires mesh-exact hits.
- [`HeightMapShape3D` rebuild cost on terrain edits] → Only consumers that need physics pay it; queries (D2) never rebuild. Rebuild is one array fill per map, cheap at these grid sizes.
- [Diamond NAN holes produce jagged edges at map corners] → Expected and correct — those cells are outside the playable map (`CellUtil.is_in_diamond` is the authority); tests assert no phantom collisions.
- [`HeightMapShape3D` slower than primitive shapes] → Acceptable; it only exists for physics-response consumers, and it is still faster than a trimesh. Per-engine docs.
- [Scope creep into consumer systems] → Guarded by Non-Goals: no ballistics/LOS/knockback implementation here, only the surface API.

## Migration Plan

- Purely additive: new methods on `TerrainSystem`, no signature changes, no scene changes, no packed-scene impact.
- No rollback risk: nothing live is modified; the dead `TerrainCollision.gd` removal (#208) is independent and landed separately.
- Tests land with the change: math intersection vs known-heightfield examples, invariance across square/rectangular/odd/even maps, and diamond-NAN assertions.
