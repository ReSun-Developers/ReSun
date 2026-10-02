# Proposal

## Why

ReSun registers 31 autoloads whose startup order works today but is implicit and inconsistently accessed. Some sites use the registered singleton directly (`OrderSystem.generator_changed`, `PlayerManager.get_local_player_id()`), while 69 sites across 29 scripts resolve the same autoloads through `get_node("/root/<Name>")` / `get_node_or_null("/root/<Name>")` string paths, frequently with a silent `if node:` guard. A broken or misordered dependency therefore degrades into missing signal wiring instead of a visible error, and the `project.godot` ordering comments no longer describe what the code actually needs. This change makes each dependency explicit and its absence loud, and removes the stale ordering annotations — without changing how any system behaves when all autoloads are present.

## What Changes

- Replace runtime `get_node("/root/<Autoload>")` / `get_node_or_null("/root/<Autoload>")` access to autoloads with the registered singleton identifier, so a missing dependency is a load-time failure naming it rather than a silent no-op.
- Remove defensive `if node:` null guards that only existed to tolerate a lookup that can no longer fail for a guaranteed autoload; keep (and make loud) a guard only where the target is genuinely optional or is not an autoload (e.g. scene-root `MainScene`).
- Align `project.godot` `[autoload]` ordering annotations with real `_ready` dependencies: keep the order, delete the three comments with no lifecycle backing (InputSettings, CampaignCatalog, PrerequisiteSystem), and correct the PowerGrid consumer note.
- Add a regression test that fails if any autoload is accessed through a `/root/<Name>` string path again.
- No new autoload, service locator, or registry is introduced (see design.md).
- Out of scope: nullable lazy accessors that resolve a child of the scene root by bare name (e.g. `tree.root.get_node_or_null("<Name>")`) in static helpers; converting them would change editor/isolated-test behavior, so they are tracked separately.

## Capabilities

### New Capabilities

- `system-initialization`: the contract for how autoloads are accessed and how their startup order is declared — direct registered-singleton access, loud failure on a missing required dependency, and order annotations that reflect real `_ready` dependencies.

### Modified Capabilities

<!-- None: no existing capability's requirements change. game-context's "registered first" requirement still holds unchanged. -->

## Impact

- `scripts/` — 29 files with `/root` autoload lookups, concentrated in `ProductionManager.gd`, `BuildingManager.gd`, `Sidebar.gd`, `EconomyManager` callers, `Minimap.gd`, `MouseHandler.gd`, and `SelectionOverlay.gd`.
- `project.godot` — `[autoload]` comment annotations only; ordering itself is unchanged.
- `test/unit/` — one new regression test; no existing test behavior changes.
- No gameplay behavior change, no data or scene format change, no API removal.
