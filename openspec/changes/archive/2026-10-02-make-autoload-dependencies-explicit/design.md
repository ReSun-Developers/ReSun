# Design

## Context

See `proposal.md` — Why. Two facts shape the approach:

- **Godot already provides the registry.** Every autoload in `project.godot` is bound to a global identifier that resolves statically. The `/root/<Name>` string form used in 69 places is not more capable than the identifier — it only moves a guaranteed lookup to runtime and adds a null branch that can silently swallow a wiring failure.
- **Editor context is real and asymmetric.** A `@tool` autoload is instantiated in the editor; a non-`@tool` autoload is not. `BoundsSystem` is `@tool`, `TerrainSystem` is not, which is exactly why `BoundsSystem.gd:62` guards on `Engine.is_editor_hint()` before touching `/root/TerrainSystem`. Any replacement must preserve this, or the map editor breaks.

## Goals / Non-Goals

**Goals:**

- Every absolute `get_node("/root/<Name>")` / `get_node_or_null("/root/<Name>")` resolution of an autoload is replaced by the registered identifier.
- A missing required dependency fails loudly, naming the dependency.
- Editor-only absence of a non-tool autoload stays a supported, non-error path and is expressed by an explicit editor guard, not a swallowed null.
- `project.godot` ordering annotations are true statements about `_ready`/`_enter_tree` reads.

**Non-Goals:**

- No new autoload, service locator, registry, or dependency-injection framework.
- No change to `[autoload]` ordering itself.
- No moving of per-map systems out of autoloads (that is the Main→World change, issue #473).
- No behavior change when all autoloads are present at runtime.

## Decisions

### D1: Access autoloads by registered identifier, not `/root` strings

Replace `get_node("/root/<Autoload>")` and `get_node_or_null("/root/<Autoload>")` with the bare registered identifier (e.g. `EconomyManager`, `PrerequisiteSystem`). The autoload table is the registry; a second one is redundant.

**Alternatives considered:**

- *Service locator / `provide`–`inject` autoload (option B's original shape)* — adds a second global registry, its own startup-order constraint, and hides the concrete dependency behind a key; it buys swapability we have no second implementation for. Rejected as an abstraction with no current consumer.
- *`@export` node references / `setup(deps)` injection* — the right end-state for per-map systems (issue #473), but autoloads are not scene-instanced and have no parent to inject from, so it does not apply here.
- *Constructor injection via `_init(deps)`* — autoloads are constructed by the engine with no arguments. Not applicable.

### D2: Distinguish three access classes, not one blanket edit

| Class | Treatment |
|---|---|
| Required autoload, runtime path (all autoloads present) | Direct identifier; delete the null guard |
| Required autoload read from a `@tool` autoload on an editor-reachable path | Keep a lookup but guard on `Engine.is_editor_hint()` (expected absence in editor), then use the identifier outside the guard; do not log an error for editor absence |
| Target that is not an autoload (e.g. `/root/MainScene`) | Keep an explicit guarded lookup; if the target is required at runtime, log a named error on absence |

This is why the edit is per-site, not a project-wide regex. `BoundsSystem.gd` is the only `@tool` autoload among the 29 affected files, so it is the one editor-context case. The other `Engine.is_editor_hint()` checks sit in non-`@tool` scripts, which do not execute in the editor; their guarded lookups are runtime-safe to convert.

### D3: Ordering annotations describe `_ready` reads only

Keep `project.godot` order unchanged. Delete the two annotations with no lifecycle backing (InputSettings `:25`, CampaignCatalog `:22`), and correct the PowerGrid annotation (`:41`): its real `_ready` consumer is `ProductionManager` (signal connect), not `PrerequisiteSystem` — which has no `PowerGrid` reference at all. Delete the `VeterancySystem` annotation, which describes purpose rather than a lifecycle read. Keep the rest; verify each names a reference that actually occurs in the reader's `_ready`/`_enter_tree`. Convention: an annotation states the reader and the read. Signal connections do not constrain order (a script-declared signal exists at instantiation), so `UnitMeshRenderer` connecting `ShroudSystem.state_changed` while registered earlier than `ShroudSystem` is engine-safe and does not force a reorder.

### D5: Out of scope — nullable lazy accessors

A second, distinct pattern resolves an autoload as a child of the scene root by bare name, e.g. `tree.root.get_node_or_null("TerrainSystem")` in static helpers (`Pathfinder`, `CellUtil`, `SpatialHash`, `Minimap.play_insets`, `GlobalRules.get_current`, `SellOrderGenerator`, …). These are deliberately nullable so static utilities and editor contexts work without the scene tree; converting them would change editor/isolated-test behavior. They are excluded from this change and from the `system-initialization` access requirement, and should be tracked separately if the project wants one access style. The regression guard therefore matches the absolute `/root/` form only.

### D4: Regression test is a source scan, not a runtime probe

Add `test/unit/test_autoload_access.gd` that parses the autoload names from `project.godot`, walks `scripts/`, and asserts no `get_node(_or_null)?("/root/<Autoload>")` remains. A runtime probe cannot catch this class (the bug is a string that resolves; the test is a lint). The scan is the only check that fails on the regression the spec forbids.

## Risks / Trade-offs

- **A `@tool` autoload direct-references a non-tool autoload → editor crash.** → D2's per-site audit; the regression test cannot detect editor-runtime nulls, so the audit must be explicit. Mitigation: keep the `Engine.is_editor_hint()` guard and re-run `openspec`/manual editor check on the map editor after the change.
- **Godot may not instantiate *any* non-tool autoload in editor, including ones a `@tool` script reads only at runtime.** → Only editor-reachable methods matter; runtime-only methods are safe. Classify each `@tool` file by call path.
- **Text-scan test is brittle to a change in spelling.** → Match the exact autoload names parsed from `project.godot`; false positives require writing a literal `/root/<Autoload>` string, which is the thing being prohibited.
- **Diff size.** 69 sites across 29 files. → Mechanical, no logic change; reviewable file-by-file by class.

## Migration Plan

Incremental, one class at a time, keeping the suite green between steps (strangler — no big-bang):

1. Add the regression test first (it fails on the current tree; that failure is the baseline).
2. Convert the non-`@tool` files (all 29 affected files except `BoundsSystem`), largest first: `Sidebar`, `ProductionManager`, `BuildingManager`, `DeployComponent`, then the rest.
3. Convert `BoundsSystem` separately under the D2 editor-guard classification.
4. Align `project.godot` annotations.
5. Run lint/format + full suite; manual editor smoke on the map editor.

Rollback: revert the commit; no data or format changes, so rollback is complete.
