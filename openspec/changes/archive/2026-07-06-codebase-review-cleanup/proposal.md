## Why

Full codebase review (issue #16) identified 16 findings — 4 bugs, 5 dead code items, 5 over-engineering issues, 2 style violations. After verification against Redot 26.2 LTS docs and codebase analysis:

- **11 completed** across bug fixes, dead code removal, refactoring, style, CI, and docs
- **1 valid remaining** (#3 grid_cells setter) — applied in this commit
- **4 deferred** (#9 raise_cell duplicate was intentional, #12/#13 MapEditor UI and SelectionVisuals extraction are low-priority code organization)

This change fixes all verified bugs, removes dead code, completes safe refactorings, adds CI linting, and updates docs.

## What Changes

- **Bug fixes**: Replace `assert()` with `push_error()` + `return` in MouseHandler (4 locations); replace fragile relative path in BoundsSystem with `@export`; add setter to `grid_cells` in TerrainSystem; remove hardcoded `* 60.0` framerate multiplier in CameraController
- **Dead code removal**: Delete empty SceneManager.gd, unused `_on_deselected()` method, unused `grid_size` getter, duplicate `_vkey()` function
- **Refactoring**: Optimize Pathfinder heap key lookups; extract catmull-rom spline utils from MovementController into SplineUtil
- **Style**: Replace string-based `emit_signal()` with typed `.emit()` in HealthComponent; fix PascalCase variable in MainMenuItem01
- **CI**: Add gdtoolkit lint + format-check job to GitHub Actions
- **Docs**: Update AGENTS.md (test suite, linting, folder structure) and README.md (development section)

## Capabilities

### New Capabilities
- `code-quality`: Runtime error handling, signal emit patterns, naming conventions
- `terrain-grid-safety`: Grid cell state consistency via setter enforcement
- `camera-framerate`: Frame-rate independent camera movement
- `pathfinding-optimization`: Efficient A* heap operations with cached keys
- `ci-linting`: Automated GDScript lint and format checking in CI

### Deferred (not in this change)
- `selection-visuals`: Separated presentation layer for unit selection display — low priority code organization
- MapEditor UI scene extraction — low priority code organization

## Impact

- 15 files edited, 1 deleted, 3 created
- ~500 net lines removed
- No API changes, no scene format changes
- No breaking changes to existing gameplay
- CI pipeline gains new lint job (additive)
