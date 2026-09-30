## Context

ReSun is an RTS remake with 23 GDScript files (~3,500 lines), 25 scenes, and 21 tests. A full codebase review (issue #16) found 16 issues across bugs, dead code, over-engineering, and style. After verification against Redot 26.2 docs and codebase analysis, 11 were completed, 1 is valid remaining (#3 grid_cells setter), and 4 are deferred (#9 intentional, #12/#13 low-priority).

The codebase is early-stage — many patterns were established quickly during prototyping. This change is the first systematic cleanup pass.

## Goals / Non-Goals

**Goals:**
- Fix all verified bugs (assert crash, camera desync, framerate multiplier, grid_cells desync)
- Remove all dead code items
- Complete safe refactorings (Pathfinder heap, SplineUtil extraction)
- Fix style violations
- Add CI linting to prevent style regressions
- Update docs to reflect current project state

**Non-Goals:**
- Performance optimization beyond the Pathfinder heap key issue
- New features or gameplay changes
- Scene format migrations
- Replacing the component architecture (1 component = 1 impl is fine at this stage)
- Adding new tests (existing 21 tests are sufficient for regression checking)

**Deferred (verified but low priority):**
- #9 TestMap02 raise_cell duplicate: Intentional — each call increments height by 1, two calls needed for height 2. Removing one changes behavior.
- #12 MapEditor UI to scene: 48 lines of simple programmatic UI, not 80 as claimed. Works fine, low ROI for refactoring.
- #13 SelectComponent extraction: 286-line _ready(), tightly coupled to component state. Would require passing many parameters to a factory.

## Decisions

### 1. Export node reference vs %UniqueName for BoundsSystem

**Decision**: Use `@export var camera_pivot: Node3D`

**Alternatives considered**:
- `%camera_pivot` (unique name) — requires the node to be marked unique in the scene file. Breaks if the scene is instantiated in a different context where the unique name isn't registered.
- `@export` — wired in the editor, works across scene variations, no scene file dependency.

**Rationale**: Export is more portable. BoundsSystem is used in both Gameplay.tscn and MapEditor.tscn (which instantiates it programmatically). Unique names only work within a single scene ownership scope.

### 2. Pathfinder heap: optimize keys vs replace with sorted array

**Decision**: Keep the binary heap, optimize key lookups by caching `f_score` values

**Alternatives considered**:
- Replace with `Array.sort_custom()` — simpler but O(n log n) per operation vs O(log n) for heap. For large grids (32×32 = 1024 cells, up to 8 neighbors each), the heap is measurably faster.
- Use composite key structs `{ cell: Vector2i, f: float }` — cleaner but adds allocation pressure in GDScript.

**Rationale**: The heap is the correct data structure. The real waste is repeated `_cell_key()` string concatenation (each heap comparison does `str(x) + "," + str(y)` + dictionary lookup). Caching `f_score` in a flat dictionary keyed by the cell key, and passing it to heap operations, eliminates redundant computation without changing the algorithm.

### 3. SelectionVisuals: child node vs embedded code

**Decision**: Create `SelectionVisuals.gd` as a child node of SelectComponent scenes

**Alternatives considered**:
- Keep inline in SelectComponent — simpler but violates SRP, 200+ lines mixing state and presentation.
- Make it a separate scene added at runtime — more flexible but adds instantiation complexity.

**Rationale**: Child node follows the existing component pattern (HealthComponent, HitboxComponent are child nodes). SelectComponent owns state + signals, SelectionVisuals owns presentation. Clean separation without architectural changes.

### 4. SplineUtil: static utility class vs resource

**Decision**: Static utility functions in `scripts/core/SplineUtil.gd` (no `class_name`, no instantiation)

**Alternatives considered**:
- `class_name SplineUtil extends RefCounted` — allows type hints but adds a class registration.
- Custom Resource — overkill for pure math functions.

**Rationale**: Static functions with no `class_name` keep it lightweight. MovementController calls `SplineUtil.evaluate()` directly. No state, no instantiation needed.

### 5. CI linting: gdtoolkit vs Redot --check-only

**Decision**: Use `gdtoolkit` (pip install) for lint + format checking

**Alternatives considered**:
- `redot --headless --check-only --script <file>` — doesn't load autoloads, so scripts referencing TerrainSystem/Pathfinder/SpatialHash fail with false errors. Limited usefulness.
- GDQuest formatter — less mature than gdtoolkit, fewer CI integration examples.

**Rationale**: gdtoolkit is the community standard (1,500+ GitHub stars), works independently of Redot binary, catches naming conventions (the PascalCase finding), and has proven CI integration patterns.

### 6. MapEditor UI: scene vs code

**Decision**: Move UI construction to `scenes/editor/EditorUI.tscn`

**Alternatives considered**:
- Keep in code — no file creation, but 80 lines of programmatic Button/Label/FileDialog construction.
- Use a plugin — overkill for editor-only UI.

**Rationale**: UI belongs in scenes per Redot conventions. The scene file is self-documenting (shows layout in editor), and _setup_ui() becomes 5 lines of instantiation + signal wiring.

## Risks / Trade-offs

| Risk | Mitigation |
|------|-----------|
| SelectionVisuals extraction breaks visual selection display | Test all 3 box types (Infantry/Vehicle/Structure) in editor after changes |
| BoundsSystem export breaks existing scene wiring | Check all scenes that instantiate BoundsSystem, wire export in each |
| Pathfinder key optimization introduces pathfinding regression | Run existing test suite (21 tests) + manual pathfinding verification |
| gdtoolkit may flag existing code style issues | Run gdlint locally first, suppress known acceptable warnings in config |
| MapEditor UI scene doesn't match current layout | Side-by-side comparison in editor before/after |

## Migration Plan

1. All changes are backward-compatible (no API changes, no scene format changes)
2. Existing scenes work without modification (except BoundsSystem which needs export wiring)
3. CI lint may initially fail on existing code — fix style issues as part of this change
4. No rollback needed — all changes are incremental improvements

## Open Questions

- Should gdtoolkit warnings be configured via `.gdlintrc` to suppress specific rules? (Recommend: yes, add config file)
- Should the Minimap be included in EditorUI.tscn or kept as programmatic SubViewportContainer? (Recommend: keep in code — it has runtime viewport setup)
