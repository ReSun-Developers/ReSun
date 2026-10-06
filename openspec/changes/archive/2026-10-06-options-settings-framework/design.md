# Design

## Context

See `proposal.md` for motivation. The constraints that shape the approach:

- **Two existing writers already share `user://settings.cfg`.** `GameContext.save_game_choice()` loads, sets `[game] id`, and saves (preserves other sections). `InputSettings._save()` builds a fresh `ConfigFile` with only `[camera]`/`[keybinds]` and saves — it **wipes the `[game]` section** on every camera rebind. Any new writer must use load-modify-save.
- **`InputSettings` is global today** (single `[keybinds]` section), loaded once in `_ready()` before scene autoloads.
- **Rendering values are hard-coded** in `project.godot` (`directional_shadow/size=4096`), `DefaultWorldEnvironment01.tscn` (`sdfgi_enabled=true`, `ssao_enabled=false`, glow, fog), and `DefaultSunLight01.tscn` (`shadow_enabled=true`, mode 0, blur 0.9).
- **`LightingControls`** already mutates the live `DirectionalLight3D`/`WorldEnvironment` via setters, registers in the `lighting_controls` group, resolves the env/light by **sibling name**, and captures scene defaults. It runs in `_ready()` and forces `shadow_enabled = true`.
- **The environment scenes are shared**: `MapBase01` names the env node `WorldEnvironment`; `MapEditor.tscn` and `AssetBrowser.tscn` name it `DefaultWorldEnvironment01`. Only `CloudShadowPlane` carries a group (`cloud_shadow_overlay`), plus `LightingControls` (`lighting_controls`).
- **`BootScreen.Options` is a disabled placeholder**; the pause menu and main menu have no Options entry. No options view exists.
- Environment scenes are re-instantiated on every mission/world swap (`MissionBoot._swap_world`), each re-running `LightingControls._ready()`.
- Redot 26.2 exposes `Viewport.msaa_3d` and `Viewport.screen_space_aa` (`DISABLED/FXAA/SMAA`), and `RenderingServer` methods to change directional shadow quality at runtime; texture quality has no runtime API.

## Goals / Non-Goals

**Goals:**
- One config authority over `user://settings.cfg` with no writer clobbering another, plus migration of existing `[camera]`/`[keybinds]` data.
- A global graphics schema with atomic presets, applied at boot, on every environment scene load, in the runtime editor scenes, and live where the engine supports it.
- Per-game input bindings (base + overrides) and per-game gameplay toggles, applied on game switch.
- One reusable Options view surfaced from the boot selector, pre-match main menu, and in-match pause menu, with restart-and-resume.

**Non-Goals:**
- Auto-detecting hardware to pick a preset (fresh install uses Low).
- Native/C# work; a custom SMAA shader (native SMAA suffices).
- Per-game graphics overrides — graphics are global by design.
- Reworking the debug lighting sliders into the Options view (they remain a debug tool).
- Redot IDE (`@tool`) viewport changes; "editor" means the runtime Map Editor and Asset Browser scenes.

## Decisions

### D1 — One file, section-namespaced, behind a `UserConfig` helper
Sections: `[game]`, `[graphics]`, `[ui]`, `[input]`, `[input.<id>]`, `[game_settings.<id>]`. A single **static** helper class `UserConfig` (`scripts/core/UserConfig.gd`) exposes `load(path)`, `set_value(path, section, key, value)`, and `get_value(path, section, key, default)`, each doing load-modify-save. Every owner keeps an overridable `_config_path` for tests and writes through the helper.
- **Why:** static functions avoid a new autoload and an ordering dependency; the file is always loaded, one key changed, saved — so no writer clobbers another.
- **Alternative rejected:** a `SettingsStore` autoload — an extra singleton with no behavior beyond the helper, plus ordering concerns. **Alternative rejected:** separate `graphics.cfg` + `games/<id>/input.cfg` — grows with every game and fragments the single authoritative document for no data-model benefit.

### D2 — Ownership split between autoloads
- `GraphicsSettings` (new autoload): schema, presets, persistence, apply, `settings_changed(changed)` signal.
- `InputSettings` (refactored): resolves base + per-game bindings; listens to `GameContext.game_changed` and re-applies.
- `GameSettings` (new autoload): per-game toggle registry; applies on `game_changed`.
- `OptionsView` (scene, not autoload): presentation only; reads/writes through the three owners.
- **Why:** one owner per data shape (global scalars / per-game bindings / per-game bools); the UI has no persistence logic, matching the "signal up, call down" convention.

### D3 — Graphics apply path
`GraphicsSettings` applies to the root `Viewport` (`msaa_3d`, `screen_space_aa`), the live `WorldEnvironment` (SDFGI + High params, `tonemap_mode`, `tonemap_exposure`), the live `DirectionalLight3D` (`shadow_enabled`, `directional_shadow_mode`), the `cloud_shadow_overlay` group (visibility), and `RenderingServer` for directional shadow quality/atlas size. Node resolution:
- Resolve the `lighting_controls` group first (it already owns the live light/env references); otherwise fall back to finding a `WorldEnvironment` / `DirectionalLight3D` node in the current scene (name-agnostic, by type).
- Cloud overlay by the `cloud_shadow_overlay` group.
- Defer application one frame after scene load so it wins over scene/`LightingControls` `_ready()`.
- **Re-apply on scene load:** connect to `SceneTree.node_added` (or `MissionBoot`'s world swap) and re-apply once a new `WorldEnvironment`/`LightingControls` appears, so a mission swap cannot reset the preset to scene defaults.
- **Restart-only:** only **texture quality** (no runtime API) is restart-only; it is stored in `user://settings.cfg` and applied at boot (there is no reliable runtime `ProjectSettings` path). **Shadow quality is live** via `RenderingServer` (directional shadow atlas size + mode), matching `rendering-budget`/`shadow-rendering`.
- `LightingControls._apply_shadow()` stops forcing `shadow_enabled = true` (it owns opacity/blur only); the applier owns on/off. No spec change to `lighting-controls` — its slider contract is untouched.

### D4 — Antialiasing → viewport mapping
`Off` → both disabled; `MSAA 2x/4x` → matching `msaa_3d`; `SMAA` → `screen_space_aa = SMAA`; `SMAA+MSAA` → both. Distinct from shadow quality.

### D5 — Restart-and-resume via a one-shot `[ui]` marker, independent of the boot gate
The surface requesting a restart writes `[ui] restart_section` through the helper, calls `OS.set_restart_on_exit(true)` and quits. A resume handler that runs on every launch (mounted under `MainScene`/`SessionShell`, **not** `BootScreen`, because `--game` skips the selector) reads the marker after GameContext resolves, opens `OptionsView` on the recorded section, then clears the marker. Restart is only offered from the boot selector and the pre-match main menu; the pause menu disables restart-only rows. A non-restart close simply returns to the opening surface.
- **Why:** a relaunch preserves the original command line, so the resume hook cannot live behind the boot gate.
- **Alternative rejected:** command-line arg injection — the engine relaunches with the original command line and exposes no portable re-exec.

### D6 — One Options view, three entry points, modal over pause
A single `OptionsView` scene with Graphics/Input/Game sections, opened as an overlay by `BootScreen`, `MainMenu01`, and `PauseMenu`. It themes from the active `GameDefinition` (`menu_background`, `menu_accent_color`) when opened from the menu or pause, and uses the neutral placeholder theme when opened from the boot selector — **keyed to the opening surface**, because `GameContext` always resolves a game before the selector shows. When opened from the pause menu it uses `process_mode = ALWAYS` and consumes ESC to close without resuming.

### D7 — Per-game input resolution
Resolution for active game G, action A: `[input.G][A]` → `[input][A]` → `project.godot` default. `GameDefinition` gains a `supported_inputs` declaration; unsupported actions are unbound and rendered disabled in the table. `remap_action(action, key_name, target)` writes to the base section for the base column, else to `[input.<id>]`. On load, legacy `[camera]`/`[keybinds]` keys migrate into `[input]`.

### D8 — Per-game game settings and the move-line gate
`GameSettings` reads a registry of `{id, default, description}` toggles, stores values under `[game_settings.<id>]`, and applies on `game_changed`. The `move_target_line` toggle gates move-target line registration inside `SelectComponent` (client-side), so **rally lines** — which share the `MoveLineRenderer` registration path — are unaffected.

### D9 — Change notification
`GraphicsSettings.settings_changed(changed: PackedStringArray)` fires once per batch (a preset selection is one batch). Runtime systems subscribe; no polling. No concrete subscriber is claimed in this change beyond the applier's own subscribers and tests — the cloud overlay/GI are applied directly by the applier (D3).

### D10 — Normalize the legacy main specs first
`openspec/specs/{input-settings,rendering-budget,shadow-rendering,select-component}/spec.md` start with `## ADDED Requirements` and have no `## Requirements` section, so archive refuses deltas against them. Normalize each to `## Purpose` + `## Requirements` before archiving this change.

## Risks / Trade-offs

- [Texture quality can't be verified live] → It is the only restart-only field; marked in the UI, disabled in the pause menu, and covered by a boot test.
- [`OS.set_restart_on_exit` is platform-dependent (no-op on web)] → Desktop is the target; the marker still resumes on the next manual launch.
- [Node-name variance across shared env scenes] → Resolve by group first, then by node type, never by a single hardcoded name.
- [Refactoring `InputSettings` breaks existing input tests/specs] → Keep `project.godot` defaults identical, redirect the config path in tests as today, migrate legacy sections, update `remap_action` callers.
- [Applier vs `LightingControls` ordering] → Deferred apply + re-apply on scene load; `LightingControls` no longer force-enables shadows; a regression test asserts the applied value wins after a world swap.
- [Move-line gate accidentally suppressing rally lines] → Gate inside `SelectComponent`'s move-line path, not in the shared renderer; a test asserts rally lines survive with the toggle off.
- [Legacy malformed specs block archive] → D10 normalizes them as the first task.

## Migration Plan

1. Normalize the four legacy main specs (D10).
2. Add `UserConfig` and route `GameContext` + `InputSettings` through it (fixes the clobber); migrate `[camera]`/`[keybinds]` → `[input]`.
3. Add `GraphicsSettings` + applier + presets + notification + scene-load re-apply + editor apply; ship the Low default.
4. Add `OptionsView` + entry points + modal pause behavior.
5. Refactor `InputSettings` to per-game resolution + `GameDefinition.supported_inputs` + table view.
6. Add `GameSettings` + `move_target_line` gate in `SelectComponent`.
7. Add the restart marker + resume hook.
8. Tests (unit + integration).

Rollback: the change is additive and `UserConfig` reads legacy keys during migration, so reverting the code leaves a valid config file.

## Open Questions

- The exact numeric values per shadow-quality/GI/tone-mapping tier can be tuned during implementation without changing the specs or task breakdown.
