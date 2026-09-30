## Context

`ArtComponent._load_model()` currently calls the blocking `load()` on the main thread. Building placement triggers this twice — once when the sidebar creates a translucent preview and again when the entity is actually placed — so a single placement can read the same `.glb` (up to ~1.4 MB) from disk twice, each read stalling the frame for ~10–50 ms. There is no caching, so every preview/place of the same building type re-reads from disk.

Redot exposes `ResourceLoader.load_threaded_request()` / `load_threaded_get_status()` / `load_threaded_get()`, the engine-native background loader. It performs the disk read and import on a worker thread and hands back a fully-formed `PackedScene`, which is exactly the producer/consumer + ready-queue pattern used by comparable RTS engines for streaming art. This change adopts it and adds a shared cache so repeat loads are free.

Constraints:
- GDScript only, Redot 26.2 LTS.
- `ArtComponent` is a `@tool` `Node3D`; editor code paths must stay synchronous-free of threaded loading.
- Consumers that read `art.art_data` (e.g. `SelectionOverlay`) must keep working — they already do not depend on the mesh existing synchronously, so async arrival is safe.
- `EntityFactory` calls `ArtComponent.configure()` inside `create_entity()`, so any signal emitted during `configure()` (the cache-hit case) fires before external code can connect.

## Goals / Non-Goals

**Goals:**
- Remove the main-thread stall from building preview and placement.
- Read each model from disk at most once per process via a shared cache.
- Provide a `model_loaded` signal so the build preview can re-apply its transparency override when the mesh arrives late.
- Handle the async lifecycle safely: missing files, failed loads, and entities freed mid-load.

**Non-Goals:**
- Preloading all models at game start (future enhancement).
- Reusing/reparenting the preview entity as the placed entity.
- Cache eviction/invalidation — models are static assets, so the cache lives for the process lifetime.
- Changes to `EntityFactory`, `Sidebar`, or `ArtData`/`EntityData` resources.

## Decisions

**Threaded loading via `ResourceLoader.load_threaded_request` + `_process()` polling.**
Chosen over `WorkerThreadPool` or a manual `Thread`, because the engine loader already runs import off-thread, returns a ready `PackedScene`, and integrates with the resource cache. Polling in `_process()` (rather than a callback) matches the engine's documented pattern and keeps all node-tree mutation on the main thread. `set_process()` is toggled on only while a load is pending, so idle components cost nothing; `_process()` also early-returns on `Engine.is_editor_hint()` and when no load is in flight.

**Process-wide `static var _model_cache: Dictionary` (path → `PackedScene`).**
A static keeps a single cache shared by every instance without a new singleton/autoload. Cache hit → instantiate synchronously and emit `model_loaded` in the same frame; cache miss → threaded request, populate the cache on completion. Alternative (an autoload cache manager) was rejected as over-engineering for a path→scene map with no eviction.

**`model_loaded` signal + shared finalize helper.**
Both the cache-hit and background-completion paths funnel through one `_finalize_model(scene)` helper that instantiates, adds the child, applies the optional texture override (reusing the existing `_apply_material` logic), and emits `model_loaded`. This avoids duplicating the instantiate/texture code across two paths.

**`BuildingManager` connects `model_loaded` on the preview's `ArtComponent`.**
After `_create_building_preview()` applies transparency to the current tree, it connects the preview `ArtComponent.model_loaded` to `_on_preview_model_loaded()`, which re-runs `_set_node_transparency(_building_preview, 0.33)`. On a cache miss the mesh is absent when transparency is first applied, so the callback covers it; on a cache hit the mesh already exists and the initial full-tree pass already covered it (the callback simply re-applies harmlessly, or the signal fired during `configure()` before connection — either way the result is correct).

## Risks / Trade-offs

- [Model appears a frame or two after the entity on first load] → Acceptable and intended: the entity is functional immediately (collision, stats, selection use data, not mesh); only the visual mesh is deferred. Cache hits are instant.
- [Entity freed mid-load leaves an unfetched threaded request] → `_process()` stops when the node is freed, so the completion path never runs against a dangling node; an `is_instance_valid(self)` guard protects the `add_child`. The engine keeps the loaded resource for a later identical request, so it is not wasted. No manual cancel API is needed.
- [Two `ArtComponent`s request the same uncached path in the same frame] → Both issue threaded requests for the same path; the engine coalesces to one disk read, and whichever completes first populates the static cache. Correct, at worst a redundant `load_threaded_request` call.
- [Static cache never frees `PackedScene`s] → Deliberate: model set is small and static. Documented as a non-goal.

## Migration Plan

Pure in-place behaviour change to two scripts; no data migration, no `.tscn` edits. Rollback is reverting the two files. Backward compatible: entities without `model_path` still show their placeholder unchanged.
