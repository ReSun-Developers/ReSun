## Context

The game renders the 3D world through a single orthographic camera (1920×1080, `far=400`, ortho size 20). Units are data-driven via `EntityFactory` → `Entity.tscn` root + components; `ArtComponent` instantiates a GLB model (a static node tree of ~7 `MeshInstance3D` subnodes) as a child and, for unit types, currently renders it as-is. Each unit therefore costs ~7 draw calls. A separate direct-scene path (TestMap01's `NodBuggy.tscn`, GLB as root) exists for dev/testing and has no `ArtComponent`.

`TerrainRenderer` already proves the desired instancing pattern in-repo: per-region `MultiMeshInstance3D` nodes, per-instance transforms via `CellUtil.tile_transform`, swap-remove on cell removal, `visible_instance_count`, and `custom_aabb` merging. Research on Godot 4/Redot 26.2 MultiMesh confirms: one unit per instance via a baked merged `ArrayMesh`, per-region MultiMesh for frustum culling (a MultiMesh culls as one AABB), `set_instance_transform` coalescing dirty-region uploads (fine to low thousands of units in GDScript), and a known physics-interpolation bug (#108058) that corrupts instance transforms — avoided by disabling interpolation on the MultiMesh nodes.

Debug facilities (`DebugVisualizer` autoload `enabled=true`, `MovementController.debug_show_path=true` in two scenes, `DebugMenu` in the shipped HUD) ship enabled. No `export_presets.cfg` exists yet; `OS.is_debug_build()` is the release gate.

## Goals / Non-Goals

**Goals:**
- Reduce per-unit GPU draw calls via MultiMesh instancing on the data-driven path.
- Make all debug geometry/menus inert in non-debug builds.
- Cut constant GPU cost (SSAO) and redundant per-building materials with zero visual change.
- Keep behavior in debug builds and in the direct-scene path unchanged.
- Keep the renderer testable headlessly (unit tests on bake and slot lifecycle).

**Non-Goals:**
- SDFGI tuning (issue #221 — SDFGI stays enabled).
- Shadow map size change (stays 4096; future Options menu item).
- Instancing the direct-scene path (TestMap01's `NodBuggy.tscn`).
- Team-color/remap rendering and turret sub-animation (design hooks only).
- Instancing terrain, structures, or resources.

## Decisions

### D1. `UnitMeshRenderer` as an autoload, mirroring `TerrainRenderer`
Autoload (like `SelectionOverlay`, `DebugVisualizer`) so units on every map register without scene wiring. It keeps a registry keyed by entity root, per-model baked meshes, and per-region MultiMesh buckets. `TerrainRenderer` stays a scene node because it's map-bound; units are global. Sync runs in `_physics_process` with a process priority that orders it after gameplay movement updates (or accepts a one-frame visual lag).

### D2. Bake-merge GLB subnodes into one multi-surface `ArrayMesh` (`ModelBaker`)
At first use of a model path, walk the GLB instance's `MeshInstance3D` children; for each, transform vertex positions (and normals/tangents) by the child's transform relative to the model root, and append its surfaces onto a new `ArrayMesh` with per-surface materials preserved. Cache per model path. Result: one MultiMesh instance per unit instead of seven. Per-surface materials are retained so future team-color hue-shifts (which target specific materials) and distinct part materials keep working; the bake also records surface indices for `ArtData.is_remappable` art.
- *Alternative considered*: per-subnode MultiMesh (7 instances/unit). Rejected: more CPU writes and more draw calls; baking is a one-time cost per model.
- *Alternative considered*: per-unit `StandardMaterial3D` sharing only. Rejected: nearly moot (only `civ_guardtower` uses `texture_path`) and doesn't cut draw calls.

### D3. Per-region MultiMesh buckets for frustum culling
A `MultiMeshInstance3D` culls as a single AABB, so one mesh spanning the map would draw everything. Regions are fixed-size world cells (32 world units ≈ 16 grid cells; a few visible in the 20-unit ortho viewport). Each region bucket holds up to `MAX_INSTANCES` (512) units of one model, with `custom_aabb` set to the region box (prevents per-frame AABB recomputation) and `physics_interpolation_mode = OFF` (bug #108058). Slots are swap-removed (TerrainRenderer pattern). Units moving across region boundaries migrate buckets during sync.
- *Alternative considered*: GPU-driven culling (Godot 4.4 indirect MultiMesh). Rejected: RenderingDevice + compute complexity not warranted at RTS scale.

### D4. Per-frame transform sync
`_physics_process` writes each registered unit's `entity.global_transform × model-root offset` via `set_instance_transform`. The engine coalesces writes into one dirty-region upload per frame per MultiMesh. At RTS scale (hundreds of units) this is well under the documented "low thousands" GDScript budget.
- *Upgrade path*: `RenderingServer.multimesh_set_buffer` with a prebuilt `PackedFloat32Array` if thousands of moving units ever materialize (`ponytail:` note).

### D5. ArtComponent as the registration point
`ArtComponent` receives `EntityData` in `configure()`; it records eligibility (`entity_type` ∈ INFANTRY/VEHICLE/AIRCRAFT). On `_finalize_model` it registers the entity with `UnitMeshRenderer` (guarded for editor/preview) and then hides the GLB node tree — gameplay never reads mesh-child transforms (`MovementController` rotates the entity root, hitboxes are `Area3D`). `_exit_tree` unregisters. Structures and resources never register and keep node-tree rendering.

### D6. Debug gating via `OS.is_debug_build()`
- `DebugVisualizer._process` early-returns when not a debug build; `reset_overlays()` derives `enabled` from the same check.
- `MovementController._ready` sets `debug_show_path = OS.is_debug_build() and debug_show_path` — one guard covers both scenes that ship `true` and keeps debug behavior in debug builds.
- `DebugMenu._ready` calls `queue_free()` when not a debug build.
Headless tests run under a debug build, so existing behavior tests are unaffected.

### D7. Shared select-box material
`SelectComponent` uses one cached static `ORMMaterial3D` (white, unshaded) for building select boxes instead of allocating per building. Geometry stays per-building (foundation sizes vary wildly); only the material is shared.

## Risks / Trade-offs

- **Physics interpolation bug** (#108058) corrupts MultiMesh instance transforms → Mitigation: `physics_interpolation_mode = OFF` on every MultiMesh node (D3).
- **Instance transform lag** from sync ordering → Mitigation: process priority ordering in `_physics_process`; worst case a one-frame visual lag on a moving unit, imperceptible at ortho RTS scale.
- **Team color/remap later** could need per-team material variants or an `INSTANCE_CUSTOM` shader → Mitigation: bake keeps surfaces separate and records remappable surfaces (D2); renderer registers are keyed to allow a future `team_id`.
- **Future turret sub-animation** breaks the single-instance model → Mitigation: documented pattern is a second index-aligned MultiMesh per region; registration API keeps the entity root handle so this is additive.
- **Hidden GLB tree still holds memory** → Mitigation: acceptable (mesh resources are shared/instanced); re-evaluate if memory becomes an issue.
- **Visual regression on SSAO removal** → Mitigation: SSAO is subtle at top-down scale; verified visually in MainScene/MapEditor/AssetPreview before merge.

## Migration Plan

- Land R1/R4 (one-line config/material changes) and R2 (gating) first — independently verifiable and low risk.
- Land R3 (bake + renderer + ArtComponent hook) last; it is self-contained and guarded by editor/eligibility checks.
- Rollback: R3 is opt-in per entity type; disabling the renderer autoload restores node-tree rendering. No data migrations.
