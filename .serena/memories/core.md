# Core

ReSun — fan remake of C&C Tiberian Sun. Redot Engine 26.2 LTS (Forward Plus), pure GDScript, fully 3D RTS. Longer target: unified data-driven engine for TS, Firestorm, RA2, Yuri's Revenge.

Canonical terms live in `GLOSSARY.md`; `openspec/specs/` is authoritative. All changes under `openspec/changes/` must be archived before merge (CI rejects unarchived).

## Source map
- `scripts/core/` — engine-level systems and **all 29 autoloads**. `GameContext` MUST stay first (resolves active game; consumers pull it in their own `_ready()`).
- `scripts/components/` — ~29 reusable entity behaviors (Health, Combat, Movement, Harvest, Transport, Power, Vision, ...).
- `scripts/data/` — Resource class hierarchy: `EntityData` base -> `WeaponData`, `ArtData`, `WarheadData`, `ProjectileData`, `PlayerData`, `GlobalRules`, `MapConfig`/`MapOverride`.
- `scripts/entities/` — `EntityFactory`, `EntityPlacer` autoloads.
- `scripts/buildings/`, `scripts/production/`, `scripts/economy/`, `scripts/ui/`, `scripts/hud/`, `scripts/editor/`, `scripts/maps/`.
- `games/<id>/` — per-game content tree: `game.tres`, `global_rules.tres`, `entities/`, `art/`, `audio/`, owned `assets/`.
- `assets/` — shared shell assets only (fonts, HDRI, cursors).
- `scenes/` — packed scenes; `components/*.tscn` instantiated as children of entity scenes.
- `test/` — custom runner `test/run_tests.gd`, `unit/`, `integration/`, `TestHelper`.
- `plans/` — design docs by gameplay category. `docs/` — multi-title research (capability matrix, gap analysis, target architecture).
- `openspec/` — change management.

Top-level invariants, stack details, commands and style: `mem:tech_stack`, `mem:conventions`, `mem:suggested_commands`, `mem:task_completion`.
