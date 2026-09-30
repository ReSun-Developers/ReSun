# Project Status Report — ReSun

**Last verified:** 2026-09-14
**Engine:** Redot 26.2 LTS (Forward Plus renderer) — CI pins 26.2
**Language:** GDScript only
**Project state:** Core TS systems largely complete — mission layer + multi-title expansion are the next fronts
**Verification:** `docs/research/_raw/current-state-audit.md` (198 features, file:line evidence)

## Overview

ReSun has shipped most of the Tiberian Sun gameplay foundation: a data-driven entity
system (~408 `.tres`), base building, a complete economy/harvest loop, unit production with
prerequisites, custom grid A* pathfinding with 9 locomotors, hitscan + runtime projectiles,
warhead×armor combat, turrets, a terrain system with heightfield + land types + movement costs,
shroud/fog of war, power grid, radar/minimap, a working MapEditor, audio buses with voice hooks,
and a healthy test suite (139 test files, lint+format+openspec CI gate).

Two fronts remain:

1. **Tiberian Sun completion** — the mission layer (triggers, objectives, briefing, scripted
   teams, win/lose), combat AI (auto-engage/guard/attack-move), VFX, EVA/music, naval/water.
2. **Multi-title expansion** — run Firestorm, RA2, and Yuri's Revenge from the same engine as
   data packages. Research + gap plan: `docs/` and `plans/12-0_unified_multi_title_expansion.md`.

## System status (TS)

| Area | Done | Notes |
|------|------|-------|
| Foundations & harness | 95% | 28 autoloads, MainScene, CI green |
| Grid / primitives | 95% | CellUtil, BoundsSystem, SpatialHash, rectangular+diamond maps |
| Data & rules (.tres) | 90% | EntityData, ~408 entities, 44 weapons, 27 warheads, GlobalRules |
| Object model & world grid | 90% | EntityFactory, 29 components, placement, occupancy, crush |
| Movement & locomotion | 85% | Grid A*, splines, 9 locomotors, repulsion, jumpjets, ice |
| Terrain & map systems | 80% | Heightfield, renderer, land types, movement costs; water/bridge render + authoring missing |
| Vision & fog | 85% | ShroudSystem + FogRenderer + ghosts + radar gating (was reported 0% — now shipped) |
| Power & radar | 85% | PowerGrid + low-power + PowerBar; RadarSystem + minimap gating |
| Combat (weapons/firing) | 70% | Hitscan + projectiles + turrets + warhead×armor; splash, auto-engage, abilities, superweapons missing |
| Unit & building sim | 65% | Production, deploy, prereqs, dock, power, turret; upgrades, batch, repair cost path missing |
| Economy | 60% | Full harvest→dock→credits + storage capacity; silo overflow, income tracking, crate, rank XP missing |
| Testing & CI | 85% | 139 files; lint+format+test+openspec-archive gate |
| MapEditor tooling | 65% | Height/resource/entity/player-start tools; no undo, land-type paint, theater select, water authoring |
| Shell / UI | 60% | Sidebar, credits, power bar, minimap, pause, tooltips, boot screen; save/load, settings, skirmish setup, map browser, control groups missing |
| Audio | 45% | AudioManager + voices + combat SFX; music + EVA missing; content gitignored on fresh clone |
| Presentation / VFX | 40% | Async models, MultiMesh, shadows; no explosions/death FX, water, craters |
| Save/load & game loop | 30% | Map loading works; no live-game save/load |
| Faction & skirmish AI | 15% | Faction `.tres` only; no AI, no special-ability logic |
| Campaign / scenario (missions) | 10% | MapConfig/PlayerManager/MapEditor hooks only; triggers, objectives, briefing, scripted teams greenfield |
| Multiplayer / netcode | 0% | Zero network code |
| Modding | 20% | `register_data_set()` scaffold + data-set layering + collision validation |
| Multi-title (FS/RA2/YR) | 0% | Only `games/ts`; research + gap plan done (`docs/`) |

**Overall:** strong TS engine base; mission layer and combat AI are the critical blockers for a
playable mission, and a defined set of generic subsystems is the gap to RA2/YR.

## What was corrected in this report

Prior versions (2026-08-08) under-reported shipped systems. Since then verified in code/specs:
fog-of-war + fog rendering, power grid, radar/minimap gating, runtime projectiles, turrets,
pause system, boot screen game selection, resource storage capacity. Counts corrected: 28
autoloads (not 22), 95 specs (not 63), 29 components (not 23), 46 scenes (not 37).

## Critical-path blockers

### For TS GDI Mission 01 (current milestone)

**Re-scoped 2026-09-14** to authenticity-first: triggers, scripted teams, reinforcements,
reveals and bridge destruction are required, not optional. Full plan:
`plans/13-0_gdi-mission-01_rescope.md`. Milestone #1 now holds 44 issues (41 open / 3 closed).

```
mission boot ──→ trigger engine ──→ scripted teams/reinforcements ──→ objectives/win-lose
      │                 │                    │
      └──── map build ──┴──── entity_placement/content (houses, roster gating)
```

1. **Auto-engage / guard (#261) + attack/attack-move (#264)** — acquisition scan missing;
   chase/fire-control groundwork exists.
2. **Mission boot (#236)** — no entry point, briefing, or start-camera placement.
3. **Trigger/event/action engine (#237)** — nothing exists. Largest new subsystem; needs
   CellTags (#414).
4. **Scripted teams (#238) + reinforcements (#239) + trigger wiring (#248)** — the authentic
   mission; now required.
5. **Objectives + win/lose (#240) + mission timer (#415)**.
6. **Map build-out + entity placement (#247 + #412 houses + #413 roster gating)** — note: the
   "~13 missing entities" premise was false (all 31 exist); now verify-and-map.
7. **Map/terrain track** (#226–#234) — land-type paint/water/cliff tiling/bridges/waypoints.
8. **Music (#255) + EVA (#258)**; placeholder art acceptable, final art is polish phase.

**Already done (close):** #246 minimap/radar, #242 audio manager, #243 combat SFX.
**Superseded:** #199/#207 → #230. **Pulled in:** #203 theater, #267 aircraft, #321/#323 AoE/FX.
**Descoped:** #265 superweapon targeting UI (meteor is trigger-driven here).

### For multi-title support

See `docs/gap-analysis.md` §B P1. The engine currently bakes TS assumptions (5 armor classes,
silo storage, no country model); these must be generalized **before** RA2 content is authored.

## Documentation state

- **New (2026-09-14):** `docs/` unified reference — capability matrix, gap analysis, target
  architecture, per-title references, and a two-pass research set: first-pass recon
  (`docs/research/_raw/`) then an exhaustive web-only deep pass with adversarial verification
  (`docs/research/deep/`, ~18,000 lines, 12 catalogs + 2 conflict ledgers). Read
  `docs/research/deep/README.md` errata before quoting any catalog number.
- **Verified corrections incorporated:** TS warhead `Verses` is editable (not hardcoded);
  armor enum is per-game (TS 5, RA2/YR 11); RA2 sidebar = 4 tabs; TS Nod campaign = 13 main;
  YR target patch 1.001; FS content gating is mix+ini detection, not a map flag.
- **Reconciled:** this report, `plans/project_planning_roadmap.md`, `AGENTS.md`,
  `GLOSSARY.md` (cross-title terms + new Undecided items).
- **Added:** `plans/12-0_unified_multi_title_expansion.md`,
  `plans/13-0_gdi-mission-01_rescope.md` (milestone #1 re-scope + mission-fact corrections).
- **Still to reconcile per-system:** `plans/3-1`, `4-1`, `2-1`, `7-2`, `5-2`, `1-4`, `6-2`,
  `6-3`, `11-1` (see `docs/gap-analysis.md` §A D3–D8).

## Related Files

- Capability matrix: `docs/capability-matrix.md`
- Gap analysis: `docs/gap-analysis.md`
- Target architecture: `docs/architecture/unified-engine.md`
- Current-state audit (evidence): `docs/research/_raw/current-state-audit.md`
- Deep research catalogs + errata: `docs/research/deep/README.md`
- Roadmap: `plans/project_planning_roadmap.md`
- Multi-title plan: `plans/12-0_unified_multi_title_expansion.md`
- GDI Mission 01 re-scope: `plans/13-0_gdi-mission-01_rescope.md`
- Capability specs: `openspec/specs/` (95 capabilities)
