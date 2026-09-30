# Unit Testing for Core Systems - ReSun

## Overview
Unit testing via custom minimal runner (`test/run_tests.gd`). GUT fails on Redot 26.x — class_name registration breaks. Tests run from CLI and GitHub Actions CI.

## Implementation Status (verified 2026-08-08)

**Healthy and green: 74 test files, 777 test methods, 4364 asserts, 0 failures (~7.7s local run).**

- 67 unit + 7 integration suites. Integration: audio-voice-routing, entity-placement, theater-selection, map-editor-e2e, pathfinder-terrain, asset-preview-scene, building-placement.
- Runner auto-injects 7 autoloads (`_ts`, `_sh`, `_sm`, `_bm`, `_em`, `_pm`, `_am`), supports `-- --tap`, writes GHA summary/annotations.
- Engine emits node/RID leak warnings at exit — hygiene debt, not test failures.
- Slowest suites: `test_centered_bounds` (~5s), `test_map_editor_e2e` (~1.9s).

**Coverage:** terrain/heightfield/catalog, pathfinding/locomotion, grid/spatial, selection/orders/UI, combat/damage/death, economy/harvest/growth, production/building, dock/transport/deploy, data/entities, audio/voice, assets/rendering, map-editor E2E.

**Not covered (because not built):** fog/vision, multiplayer, save/load, combat AI, modding.

**CI:** `.github/workflows/test.yml` — lint + format (gdtoolkit), openspec-archive gate, headless test run. **Version:** CI pins Redot 26.2-stable — matches repo and local binary.

## Setup

### Test Runner
- `test/run_tests.gd` — extends SceneTree, discovers `test_*.gd` files, calls `test_*` methods
- No framework dependencies, works on Redot 26.2 LTS

### Directory Structure
```
test/
├── run_tests.gd                          ← test runner
├── test_helper.gd                        ← TestHelper assertions (assert_eq/assert_true/fail, reset)
├── fixtures/                             ← test_tone.wav, map_theater_test.json
├── unit/                                 ← 67 test files (all test_*.gd)
│   ├── test_pathfinder.gd                ← Phase 1: pure functions ✅
│   ├── test_terrain_system.gd            ← Phase 2: autoload state
│   ├── test_spatial_hash.gd              ← Phase 2: cell reservation
│   └── test_selection_manager.gd         ← Phase 2: selection state
└── integration/                          ← 7 test files
    ├── test_pathfinder_terrain.gd        ← Phase 3: height queries
    └── test_movement_signals.gd          ← Phase 3: signal emission
```
> **Note:** the full current listing is 74 files (67 unit + 7 integration). The tree above is illustrative; see `test/` for the authoritative list.

### CLI Run
```bash
redot --headless -s test/run_tests.gd
```

## Test Coverage

### Phase 1 — Pure Functions (no SceneTree) ✅
| Function | File | What to assert |
|----------|------|----------------|
| `world_to_cell` | Pathfinder.gd | Known positions → expected cells |
| `cell_to_world` | Pathfinder.gd | Known cells → expected positions |
| `_cell_key` | Pathfinder.gd | Deterministic string output |

### Phase 2 — Autoload Singletons ✅
| System | File | What to assert |
|--------|------|----------------|
| TerrainSystem | test_terrain_system.gd | `init_grid`, `get_cell`, `set_cell`, `clear` |
| SpatialHash | test_spatial_hash.gd | `reserve_cell`, `release_cell`, `is_cell_idle` |
| SelectionManager | test_selection_manager.gd | `select_entity`, `deselect_all` |

### Phase 3 — Integration ✅
| Scenario | File | What to assert |
|----------|------|----------------|
| Pathfinder + TerrainSystem | test_pathfinder_terrain.gd | Height queries return valid floats, find_path works |
| MovementController | test_movement_signals.gd | ⚠️ Skipped — requires scene tree (test runner limitation) |

## CI/CD (GitHub Actions)

### Workflow: `.github/workflows/test.yml`
- **lint**: gdtoolkit `gdlint` + `gdformat --check`
- **check-openspec**: Enforces no open changes in `openspec/changes/`
- **test**: Installs Redot **26.2** (matches repo), imports assets, runs `redot --headless -s test/run_tests.gd`

## Conventions
- Test files: `test_<module_name>.gd`
- Test methods: `func test_<what>():`
- Assertions: manual if/check with pass/fail counters (no assert() — crashes on failure)
- One test file per system
- Each test method tests one behavior
