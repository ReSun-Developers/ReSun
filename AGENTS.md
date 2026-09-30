---
applyTo: '**'
---

# Agent Configuration for ReSun

## Project Overview

ReSun is a fan remake of *Command & Conquer: Tiberian Sun*, built in **Redot Engine 26.2 LTS** (Forward Plus). Fully 3D, preserving core RTS mechanics — base building, unit production, combat, fog of war, economy. Pure GDScript, no C#. The longer-term target is a unified, data-driven engine supporting Tiberian Sun, Firestorm, Red Alert 2, and Yuri's Revenge — see `docs/`.

Canonical terms live in [`GLOSSARY.md`](GLOSSARY.md) — read it before writing specs/designs or using domain vocabulary; `openspec/specs/` stays authoritative. Propose glossary updates whenever a new term surfaces during planning or clarifying (including prompt-only terms); check **Undecided** there before coining names like `archetype`/`template`.

## Engine & Runtime

| Detail | Value |
|--------|-------|
| Engine | Redot 26.2 LTS (Forward Plus renderer) |
| Main scene | `scenes/MainScene.tscn` |
| Viewport | 1920×1080, stretch mode = viewport |

### Autoloads (31 singletons, all registered in `project.godot`)

| Singleton | Script | Purpose |
|-----------|--------|---------|
| `GameContext` | `scripts/core/GameContext.gd` | Active game resolution (first autoload), select/unload lifecycle, per-game rules |
| `FactionCatalog` | `scripts/core/FactionCatalog.gd` | Loads the active game's faction (house) roster from `factions/` data sets |
| `CampaignCatalog` | `scripts/core/CampaignCatalog.gd` | Loads the active game's campaign/mission content from `campaigns/` and `missions/` |
| `PlayerManager` | `scripts/core/PlayerManager.gd` | Per-player identity, teams, enemy checks, current tech level |
| `VeterancySystem` | `scripts/core/VeterancySystem.gd` | Credits kills to trainable killers (experience, rank, veterancy gates) |
| `InputSettings` | `scripts/core/InputSettings.gd` | Input configuration singleton |
| `SelectionManager` | `scripts/core/SelectionManager.gd` | Entity selection tracking |
| `OrderSystem` | `scripts/core/OrderSystem.gd` | Order/cursor resolution funnel |
| `DebugVisualizer` | `scripts/core/DebugVisualizer.gd` | Debug mesh overlays |
| `MoveLineRenderer` | `scripts/core/MoveLineRenderer.gd` | Draw unit move-order lines |
| `SpatialHashSingleton` | `scripts/core/SpatialHash.gd` | Spatial partitioning |
| `CellReservationSingleton` | `scripts/core/CellReservation.gd` | In-flight sub-slot cell reservation |
| `TerrainSystem` | `scripts/core/TerrainSystem.gd` | Terrain grid management |
| `TerrainCatalog` | `scripts/core/TerrainCatalog.gd` | Terrain object catalog |
| `EntityFactory` | `scripts/entities/EntityFactory.gd` | Creates entities from EntityData resources |
| `BatchLoader` | `scripts/core/BatchLoader.gd` | Async model loading |
| `EntityPlacer` | `scripts/entities/EntityPlacer.gd` | Places entities at world positions |
| `BuildingManager` | `scripts/buildings/BuildingManager.gd` | Build mode, placement, preview |
| `EconomyManager` | `scripts/economy/EconomyManager.gd` | Per-player credits, deductions |
| `ResourceGrowthSystem` | `scripts/core/ResourceGrowthSystem.gd` | Tiberium spread and tree regrowth |
| `SelectionOverlay` | `scripts/ui/SelectionOverlay.gd` | Draws selection brackets, health bars, pips |
| `PowerGrid` | `scripts/core/PowerGrid.gd` | Per-player power supply/demand grid |
| `RadarSystem` | `scripts/core/RadarSystem.gd` | Per-player radar availability tracking |
| `PrerequisiteSystem` | `scripts/production/PrerequisiteSystem.gd` | Tech tree prerequisite checks |
| `ProductionManager` | `scripts/production/ProductionManager.gd` | Production queues, timers, spawning |
| `BoundsSystem` | `scripts/core/BoundsSystem.gd` | Map/visible-bounds diamonds |
| `UnitMeshRenderer` | `scripts/core/UnitMeshRenderer.gd` | MultiMesh unit rendering |
| `AudioManager` | `scripts/core/AudioManager.gd` | Audio buses, SFX/voice playback |
| `ShroudSystem` | `scripts/core/ShroudSystem.gd` | Per-player fog-of-war grid |
| `FogRenderer` | `scripts/core/FogRenderer.gd` | Renders the fog-of-war overlay |
| `FxSystem` | `scripts/core/FxSystem.gd` | Plays one-shot visual effects (`FxData`), fog-gated |

## Folder Structure

| Directory | Purpose |
|-----------|---------|
| `scripts/components/` | 29 reusable entity behaviors (Health, Hitbox, Select, Combat, Movement, Art, Factory, Harvest, Transport, Deploy, DockHost/Client/Unload, Passenger, Power, Projectile, Radar, RallyPoint, Resource, ResourceTree, FreeUnit, Ice, Turret, Vision, Voice, SpecialAbility, etc.) |
| `scripts/core/` | Engine-level systems: SelectionManager, BoundsSystem, Pathfinder, SpatialHash, TerrainSystem, TerrainRenderer, CellUtil, CellSubPositions, ResourceGrowthSystem, PlayerManager, DebugVisualizer, EntityMaskManager, PixelArtManager, SplineUtil |
| `scripts/data/` | Resource type definitions: EntityData, WeaponData, ArtData, AnimClipData, WarheadData, ProjectileData, ResourceType, GlobalRules, MapConfig, PlayerData, MapOverride |
| `scripts/entities/` | EntityFactory autoload — creates entities from data resources |
| `scripts/buildings/` | BuildingManager — build mode, placement, preview system |
| `scripts/economy/` | EconomyManager — per-player credit tracking |
| `scripts/editor/` | Map editor tools: HeightPainter, MapEditor, Minimap |
| `scripts/hud/` | Camera01, CameraController, MouseHandler |
| `scripts/maps/` | Map-specific scripts (TestMap02, MapLoader) |
| `scripts/ui/` | Main menu, Sidebar, FPS counter |
| `scenes/` | 46 packed scenes: entities, components, maps, UI, environment, editor |
| `games/` | Per-game content trees: `games/<id>/` holds that game's `game.tres` definition, `global_rules.tres`, data dirs (entities, art, audio, …) and owned assets under `games/<id>/assets/` |
| `assets/` | Shared shell assets only (fonts, HDRI, placeholder cursors) — per-game assets live under `games/<id>/assets/` |
| `shaders/` | Single UI shader (`MainMenuItemBlur01.gdshader`) |
| `plans/` | 27 design docs organized by gameplay category (1-1 through 13-0, plus roadmap) |
| `docs/` | Unified multi-title research: capability matrix, gap analysis, target architecture, per-title references |
| `test/` | Custom test runner, `TestHelper` class, unit and integration tests |
| `openspec/` | OpenSpec change management — all changes in `openspec/changes/` must be archived before merge (CI rejects PRs with open changes) |

## Data-Driven Architecture

Entities are defined as `EntityData` resources (`.tres` files under `games/<id>/entities/`, resolved via the active game's GameDefinition). EntityFactory autoload reads these at runtime and dynamically attaches component scenes/scripts based on data properties. The data class hierarchy:

- `EntityData` (base) — identity, stats, combat, movement, build requirements
  - `WeaponData` — weapon definitions (damage, range, rate, warhead)
  - `ArtData` — sprite/animation references
  - `WarheadData` — damage type, radius, effects
  - `PlayerData` — per-player state
  - `GlobalRules` — game-wide constants (one `games/<id>/global_rules.tres` per game, resolved via GameContext)

Each entity type also has an art `.tres` (e.g., `games/ts/art/structures/gdi/gacnst_art.tres`) mapping animation states to sprite frames.

## What Does NOT Exist Yet

- **No build system** — built entirely through the Redot editor. No Makefile, Justfile, Dockerfile, or shell scripts.
- **No C# / native bindings** — pure GDScript + scenes only.

## Testing & Linting

### Running Tests

```bash
redot --headless -s test/run_tests.gd
```

Custom runner (`test/run_tests.gd`) discovers and runs all `test_*.gd` files in `test/unit/` and `test/integration/`. No external framework.

Test files use `TestHelper` class (`test/test_helper.gd`) with static assertions:
- `TestHelper.assert_eq(got, expected, msg)`
- `TestHelper.assert_true(value, msg)`
- `TestHelper.reset()` — called between test methods

The runner auto-injects autoloads as shorthand vars: `_ts` (TerrainSystem), `_sh` (SpatialHash), `_sm` (SelectionManager), `_bm` (BuildingManager), `_em` (EconomyManager), `_pm` (PlayerManager), `_am` (AudioManager), `_ss` (ShroudSystem).

### Test Design — Behavior, Not Implementation

Tests MUST validate requirements and real gameplay behavior, not reproduce the current
implementation.

- Derive expected results independently from specifications, geometry, or known real-world
  examples. Do not copy the production formula into the test.
- A regression test MUST fail on the broken implementation for the intended reason before the
  production fix is applied.
- Do not change expected values merely to match current output. Change them only when the
  documented requirement changes.
- Prevent vacuous passes: assert that paths are non-empty, fixtures are inside the playable map,
  entities are in the scene tree, and the tested branch was actually reached.
- For rejection tests, first prove the same setup succeeds without the rejected condition, then
  introduce that condition and verify rejection.
- Prefer observable consumer behavior over private implementation details: terrain lookup,
  placement, generated mesh geometry, docking destination, pathfinding result, serialization, and
  similar outcomes.
- Mathematical systems require both:
  - known examples with independently calculated answers;
  - invariant/property tests across square, rectangular, odd/even, and boundary cases.
- Include positive, negative, boundary, and regression cases. One happy-path assertion is
  insufficient for coordinate or geometry changes.
- Never weaken or delete a failing test solely to make broken production code pass. If a test is
  wrong, document which requirement made it wrong.

### Linting

```bash
pip install gdtoolkit
gdlint scripts/**/*.gd test/**/*.gd
gdformat --check scripts/**/*.gd test/**/*.gd
```

CI runs lint + format on every push/PR (`.github/workflows/test.yml`). Config in `.gdlintrc`. Formatter config in `gdformatrc` (4-space indent, 100 char line length).

**After `gdformat`**: always run `grep -P '\t' scripts/**/*.gd` to check for tab introduction in multi-line strings.

## GDScript Conventions

### Indentation — Spaces Only

4 spaces, never tabs. Mixing causes parse errors in Redot.

### Type Hints — REQUIRED

Every variable, parameter, and return value must have explicit type hints.

### Signal-Driven Architecture — "Signal Up, Call Down"

Children emit signals; parents connect and react. Children never call parent methods directly.

### Error Handling

- `push_error()` + `return` for runtime precondition guards
- `assert()` is stripped in release builds — never use for runtime checks
- `is_instance_valid(node)` instead of `node != null` after potential free

### Editor Modes — Two Different Things

There are two distinct "editor" concepts in this codebase:

1. **Redot IDE** — the game development editor (the application you edit scenes in). Check with `Engine.is_editor_hint()`. Returns `true` when a `@tool` script runs inside the IDE's viewport. Used to guard runtime-only calls (e.g., `get_tree()`, autoload access) that fail in the IDE context.

2. **In-game Map Editor** — the runtime level design tool (a scene the player can open). Check with `get_meta("is_map_editor")` on the MapEditor node (set in `_ready()`). Used to skip gameplay logic (e.g., free unit spawning, resource growth) when editing maps.

Do not conflate these. `Engine.is_editor_hint()` does NOT mean "we're in the map editor."

### Signal Syntax

Use typed `signal_name.emit(args)` — never `emit_signal("name", args)`.

### Doc Comments — `##` vs `#`

- `## Comment` — Redot editor doc comment. Shows as a tooltip hint in the Inspector when hovering the `@export` property below it. Use these as section headers above `@export` groups in Resource scripts.
- `# Comment` — Regular code documentation. Use for explaining logic, not for editor-facing descriptions.

### Script Structure Order

1. `class_name` + doc comments
2. Signals
3. Enums
4. `@export` fields
5. Constants (`const`)
6. Public variables
7. Private variables (`_var`)
8. `@onready` cached node references
9. Lifecycle: `_enter_tree()` → `_ready()` → `_process()` / `_physics_process()` → `_unhandled_input()` → `_exit_tree()`
10. Public methods
11. Private methods (`_method`)

## Key Conventions

- **Commits**: Conventional Commits format — `type(scope): description (#issue)`. Types: `feat`, `fix`, `bug`, `perf`, `refactor`, `chore`, `build`, `test`, `docs`, `ci`. Always suffix with the GH issue number in parentheses. Examples: `fix(TerrainSystem): prevent phantom cells from edge cascade (#17)`, `feat(FactoryComponent): implement production queue (#31)`. Scope is optional but preferred (the file or system affected).
- **Branch names**: `type/issue-number-kebab-description`. Examples: `fix/59-building-placement-blocking`, `feat/31-production-queue`, `perf/57-resource-growth-radius`. Always include the issue number after the slash.
- **GH issue titles**: Same conventional prefix as commits — `fix: building ignores moving entities`, `feat: async model loading`, `perf: SelectionOverlay O(n)`.
- **PR titles**: Conventional prefix + issue number in parentheses — `fix: building ignores moving entities (#59)`, `feat: async model loading (#60)`. The branch already has the number, but PR title must include it too.
- **Naming**: PascalCase for classes/scenes, snake_case for vars/funcs. Scene files mirror script names (e.g., `HealthComponent.tscn` ↔ `scripts/components/HealthComponent.gd`).
- **Scene composition**: Component scenes (`components/*.tscn`) are instantiated as children of entity scenes. Core systems have dedicated scene instances in the gameplay hierarchy.
- **Autoloads**: 31 autoloads registered in `project.godot`; `GameContext` must stay **first** (consumers pull the active game in their own `_ready()`). Add new singletons via project settings, not hardcoded references.
- **Input roles**: Right-click = deselect / cancel only (clears selection, exits modes, cancels production). Left-click = select / act (selects entities, issues orders, starts production). Never issue unit commands on right-click.
- **UID files**: Redot generates `.uid` files (e.g., `MyScript.gd.uid`) alongside scripts and scenes. These are valid parts of the codebase and MUST be committed. Always `git add` both the script and its `.uid` file together.

## Research Tools

### Codebase Memory (MCP) — Preferred for Code Discovery

This repo is indexed in `codebase-memory-mcp`. Use its graph tools **before** grep/glob/read when searching for code:

- `search_graph` — find functions, classes, routes, variables by pattern or natural language
- `trace_path` — trace callers, callees, or data flow through the code graph
- `get_code_snippet` — read specific function/class source code
- `query_graph` — run Cypher queries for complex patterns

Fall back to grep/glob only for string literals, config values, or non-code files.

#### Indexing mode — MUST use `full`

This project's source code lives in `scripts/` (Redot/Godot convention). The indexer's `moderate` and `fast` modes skip `scripts/` (it's in `FAST_SKIP_DIRS`). Always use `mode: "full"` when indexing or re-indexing this repo, or GDScript files won't be in the graph.

#### Project name

The canonical project name is **`ReSun`** (PascalCase). Always pass `name="ReSun"` when calling `index_repository` to keep the identifier consistent:

```
codebase-memory-mcp index_repository repo_path="<repo-root>" mode="full" name="ReSun"
```

Use the current repo root as `repo_path` — do not hardcode a developer-specific path. If CWD is the repo root, you can omit `repo_path`.

The `auto_watch` feature (enabled by default) uses this name for git-event-triggered re-indexing. If the name doesn't match, a duplicate entry with a different casing will appear in `list_projects`.

To verify the active project: `codebase-memory-mcp list_projects` — look for `ReSun` with 5000+ nodes.

To re-index this repo (e.g. after adding new scripts):
```
codebase-memory-mcp index_repository mode="full" name="ReSun"
```

### Redot Engine Docs (Context7 MCP)

Use `resolve-library-id` + `query-docs` for Redot docs (library ID: `/redot-engine/redot-docs`). Prefer Redot docs over upstream Godot docs.

### Serena (LSP Symbol Intelligence + Project Memories)

Serena runs the GDScript language server for symbol-level intelligence and keeps per-project memories under `.serena/` (config `project.yml` is committed; `cache/` and `project.local.yml` are ignored).

- Discovery still starts with `search_graph`; then use Serena `get_symbols_overview` / `find_symbol` to read a symbol body, `find_referencing_symbols` before rename/remove, and the symbolic editors (`replace_symbol_body`, `insert_after_symbol`, `rename_symbol`) for edits.
- Read `mem:core` first, then the memories it references (`mem:tech_stack`, `mem:conventions`, `mem:suggested_commands`, `mem:task_completion`) before non-trivial work. Persist durable conventions and gotchas with `write_memory`.
- Validate memory references with `serena memories check` from the repo root.
- **GDScript LSP prerequisites**: Serena does not launch Redot — it connects over TCP to an already-running Redot editor. Redot's language server defaults to port `6005` (Serena/solidlsp assumes `6008`), overridden in `.serena/project.yml` (`ls_specific_settings.gdscript.port`). That project setting is only applied if the project path is listed in `trusted_project_path_patterns` in the user's global `~/.serena/serena_config.yml` — trust is per-machine, so set it after cloning. Without a running editor or trust, symbol tools fail; fall back to `search_graph` + gdlint.

### Web Search (SearXNG MCP)

Use `searxng_searxng_web_search` for general web searches, tutorials, third-party resources.

### Reference URLs

| Resource | URL |
|----------|-----|
| Engine docs (26.2 LTS) | https://docs.redotengine.org/ |
| Shader Language | https://docs.redotengine.org/en/26.2/Tutorials/Shaders/index |
| 3D Systems | https://docs.redotengine.org/en/26.2/Tutorials/3d/index |
| GDScript Basics | https://docs.redotengine.org/en/26.2/Tutorials/scripting/gdscript/gdscript_basics |

## Full Skill Reference

For complete GDScript best practices (state machines, object pooling, save/load patterns, export annotations), see `.agents/skills/redot-engine-best-practices/SKILL.md`.
