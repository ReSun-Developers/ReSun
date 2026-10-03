# Design: World root + UI session shell

## Context

Today `MissionBoot` (`scripts/maps/MissionBoot.gd`) frees the children of
`MainScene/Gameplay` and adds a `MissionMap` there, while the main menu lives in
`MainScene`'s `HUD/UI` and the in-game HUD is a `CanvasLayer` **inside** the map
scene (`MapBase01.tscn` → `HUD` → Sidebar, Minimap, CreditsLabel, HoverTooltip,
PauseMenu, DebugMenu, BriefingDialog, FpsCounter). All 31 autoloads stay as they
are in this change.

Two reference architectures inform the shape (see the research thread):
OpenRA mounts the menu and the HUD as **peer widget trees under one persistent
`Ui.Root`**, selecting between them with a single discriminator
(`LoadWidgetAtGameStart`), while OpenTS welds the HUD into the world object by
inheritance — the anti-pattern to avoid. ReSun should copy the first: one
persistent UI host, two peer surfaces.

## Goals / Non-Goals

**Goals:**

- Give a match one teardown owner (the World root) without moving any gameplay
  system yet.
- Give the two GUI surfaces (menu vs HUD) one owner and one explicit switch.
- Make the HUD a peer of the World root so its lifetime is not a side effect of
  the map being freed.

**Non-Goals:**

- No autoload moves; no `static var instance` swap-safety work; no test-runner
  rework; no migration ratchet. These arrive with the first system move.
- No editor session mode, no animated shell-map background behind the menu.
- No changes to multi-title content catalogs.

## Decisions

### D1 — World root is a fresh scene node per match, nested under `Gameplay`

`Gameplay` becomes a stable container; each match instantiates a `World` node
(its own scene) as its child, and the loaded `MissionMap` is hosted inside that
`World`. Starting a match creates a new `World` and releases the previous one.

Why not alternatives:

- **Rename `Gameplay` and make systems/map flat siblings** — teardown stays
  spread across N nodes; no single unit to free.
- **`change_scene_to_*`** — Godot removes `Main` and the GUI along with the
  scene; `current_scene` churn. The docs warn explicitly.

### D2 — One persistent UI session shell owns the GUI surfaces

A `SessionShell` node under `Main` persists across matches and owns the surfaces.
It mounts exactly one surface by session mode and clears the previous one,
mirroring OpenRA's `Ui.Root` + `LoadWidgetAtGameStart`. This keeps GUI out of
`World` teardown.

Why not **leave the menu in `MainScene` and the HUD in the map** (today's shape):
there is no single owner, and the HUD is freed only because the map is freed —
the OpenTS coupling.

### D3 — HUD is a separate surface, not a child of the map

The match HUD surface is mounted by the shell for the match's duration and is
**not** a descendant of the loaded map scene. The HUD scripts are world-agnostic:
they resolve entities and services through `get_tree().get_nodes_in_group(...)`
and the autoloads, and reference their own children relatively; `BriefingDialog`
finds its pause menu by walking parents/siblings. **No `World`/map reference is
injected** — a future HUD consumer that needs the active match must use the
deferred accessor (D5), not ancestry.

Audit of the HUD scripts shows this is low-risk: Sidebar, Minimap, DebugMenu,
and HoverTooltip resolve entities through `get_tree().get_nodes_in_group(...)` and
the autoloads, and reference their own children relatively. `BriefingDialog`
already searches for the pause menu "whether it is nested under the map HUD or
placed beside it", so it tolerates the move.

### D4 — Session mode is a small enum on the shell, not a new autoload

`SessionMode` = `Menu` | `Match`, owned by `SessionShell`. `Menu` hosts the boot
screen and main menu; `Match` hosts the HUD. Editor mode and any animated menu
world are explicitly deferred, so a third mode is not introduced now.

Why not put the mode on `GameContext`: it already owns game/content selection;
adding session-UI state there mixes concerns and would widen the content
catalog's contract for no gain.

### D5 — Defer the access seam, test harness, and ratchet

No system leaves `/root` here, so there is nothing for a `static var instance`
guard, a `World` test fixture, or a migration ratchet to protect yet. They are
built in the first wave that actually moves a system. This keeps this change
small and archivable.

### D6 — Target node layout

```
Main (MainScene.tscn)
├── Gameplay (persistent container)
│   └── World (per match, created/freed)          ← new
│       └── MissionMap → MapBase01 (map only; HUD removed)
├── SessionShell (persistent)                     ← new
│   ├── MenuSurface (CanvasLayer, layer 256)   [mounted in Menu mode]
│   │   └── UI (Control)
│   │       └── BootScreen, MainMenu01, LoadingScreen
│   └── HudSurface  (CanvasLayer, layer 256)   [mounted in Match mode]
│       └── Sidebar, Minimap, CreditsLabel, HoverTooltip,
│           PauseMenu, DebugMenu, BriefingDialog, FpsCounter
└── MissionBoot
```

Exactly one surface is mounted at a time.

### D7 — Match-swap ordering

`_swap_world` and `SessionShell._mount` call `queue_free()` on the outgoing node
and then `remove_child()` it, so the old subtree's `_exit_tree` runs
**synchronously**, before the new World/surface is added. The outgoing content is
out of the tree immediately and fully freed at frame end; at most one World root
and one surface exist at a time. Because the detached subtree can still receive
global signals during the same frame, teardown must be lifecycle-safe: a detached
`BriefingDialog` disconnects in `_exit_tree`, and `BoundsSystem` drops a pivot
that is no longer in the tree (it must not center a camera from the previous
match). The deferred access seam in the first system-move wave must stay
swap-safe for the same reason.

## Risks / Trade-offs

- **Packed scenes instancing `MapBase01.tscn` lose the HUD children** → grep
  every `MapBase01`/`MissionMap` instance and `.tscn` referencing `Sidebar`,
  `Minimap`, etc.; update each to the new HUD surface. This is marked BREAKING.
- **HUD scripts that reached the map through ancestry break** → audit found none
  depend on map ancestry (they use groups/autoloads); no World/map reference is
  injected (D3). Verified by the suite.
- **Node paths inside HUD scripts** (e.g. `get_node_or_null("Label")`) are relative
  to each HUD node and survive re-parenting; verify with the existing suite.
- **Two surfaces briefly coexist on switch** → the shell detaches the previous
  surface before mounting the next; `test_session_shell.gd` asserts exactly one.
- **Stale references survive a synchronous detach** → `queue_free` + `remove_child`
  runs the old subtree's `_exit_tree` this frame while descendants may still hold
  references (camera pivot) or still be connected to global signals (briefing).
  Guards live in `BoundsSystem._has_live_pivot()` and `BriefingDialog._exit_tree()`;
  `test_match_swap.gd` starts two real missions to guard both.
- **Single-map behavior regression** → this change must be behavior-preserving for
  one map; existing integration tests are the guard.

## Known gaps (deferred)

- **Runtime-spawned content is not yet under the World root.** Produced units,
  built structures, projectiles, and one-shot FX parent to
  `get_tree().current_scene` (`Main`) or create a `Main/Buildings` node
  (`EntityPlacer`, `FactoryComponent`, `BuildingManager`, `CombatComponent`,
  `FxSystem`, `DeployComponent`). Only the map and the content `MapLoader` spawns
  live under `World`, so a match swap does not yet release runtime content. The
  world-root accessor and spawn routing belong to the first system-move wave (D5).
- **No match-end path.** `SessionShell.show_menu()` exists but nothing calls it on
  match end; the HUD is released when the shell switches surfaces, not when a
  match ends. A match-end/return-to-menu flow is future work.
- **HUD is world-agnostic, not injected.** A HUD consumer that needs the active
  match will need the deferred accessor (D3).

## Migration Plan

1. Add the `World` root scene and script; host `MissionMap` in it from
   `MissionBoot`; keep freeing the previous World.
2. Add `SessionShell` (CanvasLayer host + `SessionMode`); move BootScreen /
   MainMenu01 / LoadingScreen under `MenuSurface`; keep them hidden/shown as
   today.
3. Create the HUD surface scene from the map's current `HUD` children; remove
   that `CanvasLayer` from `MapBase01.tscn`; mount the HUD surface from the shell
   in `Match` mode.
4. Switch `MissionBoot` to set session mode `Match` instead of calling
   `_hide_menu_overlays()`.
5. Update `GLOSSARY.md` (`match root`, `session mode`, `UI session shell`; fix the
   `mission boot` anchor) and any BREAKING packed-scene references.

Rollback: the World root and shell are additive; reverting the mission-boot
hosting and the map-scene HUD removal restores the previous tree.
