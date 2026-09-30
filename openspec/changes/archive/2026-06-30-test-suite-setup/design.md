## Context

ReSun is an RTS remake with GDScript-only codebase on Redot 26.2 LTS. No test infrastructure exists. Core systems (Pathfinder, TerrainSystem, SpatialHash, SelectionManager) are growing without regression coverage. GUT is the established GDScript testing framework with CI/CD support.

## Goals / Non-Goals

**Goals:**
- Install GUT v9.x and verify it loads on Redot 26.2 LTS
- Create minimal test infrastructure (directory structure, config)
- Write smoke tests for Pathfinder pure functions to prove the framework works
- Enable CI/CD test execution via GitHub Actions

**Non-Goals:**
- Full test coverage for all systems (future work)
- Integration tests requiring SceneTree mocking
- Performance/benchmark testing
- Replacing GUT with alternative frameworks

## Decisions

### Decision: Custom runner over GUT

**Choice**: Minimal test runner (`test/run_tests.gd` extends SceneTree)

**Rationale**: GUT v9.x and `cyotee/Rut` fork both fail on Redot 26.2 — `class_name` registration breaks during import. Custom runner is 40 lines, zero dependencies, works on Redot.

### Decision: Pure functions first

**Choice**: Start with Pathfinder static functions (world_to_cell, cell_to_world, _cell_key, _heuristic)

**Rationale**: These have zero SceneTree dependencies, making them trivially testable. Proves GUT works before tackling autoload singletons.

### Decision: Git clone over Asset Library

**Choice**: `git clone https://github.com/bitwes/Gut.git addons/gut`

**Rationale**: Asset Library requires editor interaction. Git clone is scriptable and works in CI/CD.

## Risks / Trade-offs

- **[Custom runner lacks features]** → Acceptable for now; can add mocking, fixtures later
- **[CI binary path may change]** → Redot releases use consistent naming; cache mitigates re-download
- **[Autoloads unavailable in tests]** → Phase 1 avoids autoloads; Phase 2 will test with `before_each()` state reset
