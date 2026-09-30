## Why

The project has no automated tests. As core systems grow (pathfinding, terrain, movement, selection), regressions accumulate silently. We need a test framework to catch bugs early and enable confident refactoring. GUT (Godot Unit Test) is the standard GDScript testing framework with CI/CD support.

## What Changes

- Install GUT v9.x addon into `addons/gut/`
- Enable GUT plugin in `project.godot`
- Create `test/` directory structure with unit and integration subdirectories
- Create `.gutconfig.json` for default test configuration
- Write smoke tests for `Pathfinder` pure functions (zero SceneTree dependencies)
- Verify GUT works on Redot 26.2 LTS (compatibility risk — may fall back to `cyotee/Rut` fork)

## Capabilities

### New Capabilities

- `gut-framework-setup`: Install and configure GUT testing framework for the project
- `pathfinder-smoke-tests`: Initial smoke tests for Pathfinder static pure functions

### Modified Capabilities

<!-- None — this is additive only -->

## Impact

- **New files**: `addons/gut/`, `test/`, `.gutconfig.json`
- **Modified**: `project.godot` (add `[editor_plugins]` section to enable GUT)
- **Risk**: GUT may not load on Redot — fallback is `cyotee/Rut` or raw assert scripts
- **Dependencies**: Adds GUT addon (MIT license, ~50 files in addons/gut/)
