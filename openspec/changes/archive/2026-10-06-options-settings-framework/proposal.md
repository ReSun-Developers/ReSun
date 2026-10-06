# Proposal

## Why

ReSun has no user-facing options: rendering is hard-coded across `project.godot` and the shared environment scenes, input bindings are global, and per-game gameplay preferences do not exist. The rendering optimization program needs user toggles plus quality presets targeting the GTX 1060 / 720p / 120 FPS floor, while the multi-title plan (Tiberian Sun, Firestorm, Red Alert 2, Yuri's Revenge) needs per-game keybinds and per-game toggles that still share one graphics configuration. The current file is already shared by two writers (`GameContext` preserves other sections; `InputSettings` rewrites a fresh `ConfigFile`) so changing a camera keybind silently destroys the persisted game choice — the foundation has to be fixed before more writers land on it.

## What Changes

- Introduce one user-config authority over `user://settings.cfg`, section-namespaced (`[game]`, `[graphics]`, `[ui]`, `[input]`, `[input.<id>]`, `[game_settings.<id>]`), with every writer doing load-modify-save so no writer clobbers another's keys; migrate the legacy `[camera]`/`[keybinds]` sections.
- Add a global **graphics settings** schema (antialiasing mode, shadow quality, cloud shadows, GI mode, tone mapping + exposure, texture quality) with **Low / Medium / High / Ultra** presets that apply atomically; persist, apply on boot, re-apply whenever an environment scene is (re)instantiated, and apply live where the engine supports it. Texture quality is restart-only; every other field is live.
- Add a per-game **input settings** model: a shared base table plus per-game override columns, resolved `per-game override → base → project.godot default`. Games declare which input actions they support; unsupported cells render disabled. Bindings apply on game switch.
- Add per-game **game settings** (gameplay/UI toggles such as show move-target line), namespaced per game id and applied on game switch. The move-target-line toggle gates only move-target lines, never rally lines.
- Surface the Options view in three places — the boot game selector, the pre-match main menu, and the in-match pause menu — themed from the active `GameDefinition` (neutral on the selector by surface, not by active game). The boot screen `Options` row becomes functional.
- Apply graphics settings in the runtime editor scenes too (Map Editor, Asset Browser).
- Support restart-and-resume: settings that require a restart land back on the same options section after relaunch via a one-shot resume marker; restart-only rows are disabled from the in-match pause menu (they would end the session).
- Add a change-notification signal so runtime systems can react to live setting changes without polling.
- **BREAKING (spec-level):** the fixed rendering pins in `rendering-budget` and `shadow-rendering` (shadow map size, SSAO/glow/fog) become preset-driven defaults rather than unconditional constants.

## Capabilities

### New Capabilities
- `options-framework`: one user-config authority (namespaced sections, no-clobber load-modify-save), the three Options surfaces (boot selector, pre-match main menu, in-match pause menu), navigation and per-game theming, the pause-overlay input/process contract, and the restart-and-resume marker.
- `graphics-settings`: global graphics schema, Low/Medium/High/Ultra presets with atomic application, persistence, boot/runtime/scene-load/editor apply, restart-only classification, and change notification.
- `game-settings`: per-game gameplay/UI toggle registry, namespaced per game id, applied on game switch, with the move-target-line toggle as its first consumer.

### Modified Capabilities
- `input-settings`: bindings become per-game (base + per-game overrides) with a `GameDefinition` support declaration; application moves from boot-only to per-game-switch; config moves to the shared authority and `[input]` section.
- `game-selection-boot-screen`: the `Options` row stops being a disabled placeholder and opens the Options view.
- `select-component`: move-target line drawing honors the per-game move-target-line toggle (rally lines unaffected).
- `pause-system`: the Options overlay opened from the pause menu is modal and consumes ESC while open.
- `rendering-budget`: the pinned SSAO/glow/fog/shadow constraints become the shipped *default* preset values, overridable by user preset selection.
- `shadow-rendering`: directional shadow size/mode become user-selectable via shadow quality instead of fixed constants.

## Impact

- New: a config helper (`UserConfig`), a `GraphicsSettings` autoload, a `GameSettings` autoload, an `OptionsView` scene + script, a per-game input-table view.
- `project.godot`: new autoload(s) registered with correct ordering; default preset selection.
- `scripts/core/InputSettings.gd`: per-game model, new `remap_action` target, preserve other sections on save.
- `scripts/core/GameContext.gd`: unchanged config key, now via the shared helper.
- `scripts/environment/LightingControls.gd`: shadow on/off owned by graphics settings (it keeps opacity/blur).
- `scenes/environment/DefaultWorldEnvironment01.tscn`, `DefaultSunLight01.tscn`: remain shipped defaults consumed by presets.
- `scripts/ui/BootScreen.gd`, `MainMenu01.gd`, `PauseMenu.gd`: Options entry points.
- `scripts/data/GameDefinition.gd`: supported-input declaration field.
- `scripts/components/SelectComponent.gd`: honors the move-target-line toggle and the move-vs-rally split.
- `scenes/editor/MapEditor.tscn`, `scenes/AssetBrowser.tscn`: graphics settings apply in the runtime editor scenes.
- Spec amendments listed under Modified Capabilities; tests under `test/unit/` and `test/integration/`.
- No C# / native bindings; pure GDScript.
