# Proposal: World root + UI session shell

## Why

20 of ReSun's 31 autoloads hold per-map runtime state, and map swap only frees
`MainScene/Gameplay`'s children, so production queues, registries, selection and
the bounds pivot survive between maps (#473). Separately, the main menu lives in
`MainScene` while the in-game HUD is welded inside the map scene
(`MapBase01.tscn` → `HUD`), so the two GUI surfaces have no single owner and the
HUD dies only as a side effect of the map being freed.

This change is the first, deliberately bounded slice: introduce the two
containers later waves migrate into — a per-match **World root** and a persistent
**UI session shell** — without moving any gameplay system off autoload. It gives
map teardown and GUI hosting one explicit owner each.

## What Changes

- Add a per-match **World root** node under `MainScene/Gameplay`. Starting a
  match instantiates a fresh World and releases the previous one, so the map
  loaded for the match hangs off a single teardown point. `MissionBoot` hosts
  `MissionMap` inside the World root instead of directly under `Gameplay`.
  Content spawned at runtime (produced units, built structures, projectiles,
  effects) is **not yet** routed under the World root; that routing is the next
  wave (see design.md — Known gaps).
- Add a persistent **UI session shell** under `MainScene` that mounts exactly
  one GUI surface at a time, selected by a session mode:
  - `Menu` — the main menu and boot screen (process-level; needs no World)
  - `Match` — the in-game HUD
  Switching modes clears the previous surface.
- Move the in-game HUD (`Sidebar`, `Minimap`, `CreditsLabel`, `HoverTooltip`,
  `PauseMenu`, `DebugMenu`, `BriefingDialog`, `FpsCounter`) out of the map
  scene's `HUD` CanvasLayer into the match HUD surface, so the HUD is a sibling
  GUI surface outside the loaded map rather than a descendant of it. **BREAKING**
  for packed scenes that instance `MapBase01.tscn` and expect its HUD children.
- Replace `MissionBoot._hide_menu_overlays()` with a session-mode switch to
  `Match`.
- Keep the main menu a process-level surface: it is shown in `Menu` mode with no
  World present.

**Non-goals (deferred to later waves):** no gameplay system leaves the autoload
registry in this change; the swap-safe access seam, the test-runner rework, and
the migration ratchet arrive with the first system move. The unified
multi-title content catalogs are untouched.

## Capabilities

### New Capabilities

- `match-root`: the per-match World root container — created per match, owns the
  loaded map and per-match scene content, and is the single teardown point; the
  previous world is released before/without leaking state into the next match.
- `ui-session-shell`: the persistent UI host and its session mode — exactly one
  GUI surface (menu vs match HUD) is mounted at a time, switching clears the
  prior surface, and the HUD's lifetime is tied to the match while the main menu
  is process-level.

### Modified Capabilities

- `mission-boot`: map loading targets the World root instead of the bare
  `Gameplay` node, and menu occlusion becomes the session-mode switch rather than
  directly hiding overlay nodes.

## Impact

- **Scenes:** `scenes/MainScene.tscn` (add UI session shell host), `scenes/maps/MapBase01.tscn`
  (remove `HUD` CanvasLayer + its children), new World root and HUD surface scenes.
  Packed scenes instancing `MapBase01.tscn` and reading its HUD children break.
- **Scripts:** `scripts/maps/MissionBoot.gd` (host map in World root, switch
  session mode), `scripts/maps/MissionMap.gd` (unchanged map loading), new
  World-root and session-shell scripts; HUD node scripts (Sidebar, Minimap,
  CreditCounter, HoverTooltip, PauseMenu, DebugMenu, BriefingDialog) re-parented.
- **Specs:** `mission-boot` requirement text changes; new `match-root` and
  `ui-session-shell` capabilities.
- **Glossary:** propose new terms `match root` (the per-match World container)
  and `session mode` / `UI session shell` (the persistent GUI host). No existing
  term is redefined. `mission boot`'s anchor text mentions `MainScene/Gameplay`
  and should be updated to the World root.
- **Tests:** existing `test/unit/test_autoload_access.gd` and
  `test/unit/test_autoload_order.gd` are unaffected (no autoload moves). New
  tests cover World-root create/destroy and session-mode surface switching.
