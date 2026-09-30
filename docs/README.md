# ReSun — Documentation

Research and planning set for turning ReSun into one data-driven, isometric-3D engine
that runs **Tiberian Sun**, **Firestorm**, **Red Alert 2**, and **Yuri's Revenge**.

Produced 2026-09-14 from a code/spec audit + two research passes (first-pass recon, then an
exhaustive web-only deep pass with adversarial verification).

## Start here

| Doc | What it is |
|---|---|
| [`capability-matrix.md`](capability-matrix.md) | **The master reference.** Feature × title × engine status × action, by domain. |
| [`gap-analysis.md`](gap-analysis.md) | Prioritized gaps: doc fixes, P0 milestone blockers, P1 multi-title systems, P2. |
| [`architecture/unified-engine.md`](architecture/unified-engine.md) | Target layering, generic vs per-title data, required subsystems, migration path. |

## Per-title references

| Doc | Scope |
|---|---|
| [`titles/tiberian-sun.md`](titles/tiberian-sun.md) | TS base game (content package `games/ts`, exists). |
| [`titles/firestorm.md`](titles/firestorm.md) | FS delta over TS (future `games/fs`). |
| [`titles/red-alert-2.md`](titles/red-alert-2.md) | RA2 independent base (future `games/ra2`). |
| [`titles/yuris-revenge.md`](titles/yuris-revenge.md) | YR delta over RA2 (future `games/yr`). |

## Research

### Deep pass (exhaustive, verification-checked, ~18,000 lines)

| Doc | Contents |
|---|---|
| [`research/deep/README.md`](research/deep/README.md) | **Index + errata.** Start here; lists verified corrections that override the catalogs. |
| `research/deep/{ts,ra2,yr}-core.md` | Exhaustive simulation/mechanics per title (armor, warheads, projectiles, power, veterancy, formulas). |
| `research/deep/{ts,ra2,yr}-gameplay.md`, `fs.md` | Exhaustive gameplay systems + full rosters + AI + data architecture. |
| `research/deep/{ts,ra2,yr}-uiux.md` | Screens, HUD, controls, cursors, EVA, music, presentation, campaigns. |
| `research/deep/cross-engine-source.md` | Engine architecture ground truth (object model, INI loader, movement, AI, save/load, netcode). |
| `research/deep/cross-data-architecture.md` | Cross-title INI/schema/map/house/theater model + unified mapping table. |
| `research/deep/verification-{core,gameplay}.md` | Adversarial conflict ledgers; authoritative over the catalogs. |

Web-only; open reimplementations/released source used as ground truth.

### First pass (raw, superseded)

| File | Contents |
|---|---|
| [`research/_raw/current-state-audit.md`](research/_raw/current-state-audit.md) | 198 engine features audited against code with file:line evidence; doc-drift list. |
| [`research/_raw/ts-firestorm.md`](research/_raw/ts-firestorm.md) | TS + Firestorm inventory (superseded by deep pass). |
| [`research/_raw/ra2.md`](research/_raw/ra2.md) | RA2 inventory (superseded by deep pass). |
| [`research/_raw/yr.md`](research/_raw/yr.md) | YR inventory (superseded by deep pass). |

## Relationship to existing docs

- `openspec/specs/` remains the **authoritative** behavior spec. This set is research/planning;
  new capabilities become real work via future OpenSpec changes (see `AGENTS.md`).
- `plans/` holds per-system design docs. This set reconciles two of them
  (`00-0_project_status.md`, `project_planning_roadmap.md`) and adds
  `plans/12-0_unified_multi_title_expansion.md`.
- `GLOSSARY.md` is the canonical term directory; cross-title terms from this research were
  added there.

## Caveats

- The deep pass is verification-checked but not infallible; `research/deep/README.md` carries the
  errata, and `verification-*.md` is authoritative over any catalog claim it contradicts.
- Verify any numeric constant against the target title's own final-patch `rules(md).ini` before
  shipping. YR in particular: target 1.001, not the 1.000 mirror some catalogs used.
- "Engine status" in the matrix reflects the audit date; re-index the code before relying on it
  after significant development.
