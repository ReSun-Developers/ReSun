# Tasks

## 1. Config authority and legacy repair

- [x] 1.1 Normalize the four legacy main specs (`openspec/specs/input-settings/spec.md`, `rendering-budget/spec.md`, `shadow-rendering/spec.md`, `select-component/spec.md`) from the `## ADDED Requirements` header to `## Purpose` + `## Requirements`; verify `openspec validate --changes options-settings-framework` no longer emits the "target spec is structurally invalid" INFO for them.
- [x] 1.2 Add a static `UserConfig` helper (`scripts/core/UserConfig.gd`) with load/set/get doing load-modify-save; unit test proves setting one section keeps pre-existing `[game]` and `[graphics]` sections intact.
- [x] 1.3 Route `GameContext.save_game_choice()` through `UserConfig` and verify the existing `test_boot_screen` persistence cases still pass.
- [x] 1.4 Route `InputSettings` persistence through `UserConfig`, migrate legacy `[camera]`/`[keybinds]` into `[input]`, and add a regression test that remapping a camera key no longer deletes the persisted `[game] id`.
- [x] 1.5 Change `InputSettings.remap_action(action, key_name)` to `remap_action(action, key_name, target)` (base or a game id) and update the callers in `test/unit/test_input_settings.gd`; verify those tests pass.
- [x] 1.6 Document the section layout and legacy migration in `docs/` (one short page) and verify the documented example config loads with defaults.

## 2. Graphics settings

- [x] 2.1 Define the graphics schema and Low/Medium/High/Ultra preset values in one data location, with the allowed values from `graphics-settings`; unit test asserts every schema field is present in every preset and that Low has GI Off, AA Off, cloud shadows off, and shadow quality Off.
- [x] 2.2 Add the `GraphicsSettings` autoload: load persisted values, fall back to Low when `[graphics]` is absent, write through `UserConfig`, and emit `settings_changed(changed)` once per batch; unit tests cover absent section, round-trip, and single-fire-on-preset.
- [x] 2.3 In the applier, map antialiasing to `Viewport.msaa_3d` + `screen_space_aa` for all five modes; unit test asserts the resulting viewport modes for Off, MSAA 2x, MSAA 4x, SMAA, and SMAA+MSAA.
- [x] 2.4 In the applier, resolve the live light/environment via the `lighting_controls` group first and by node type otherwise, and apply shadow on/off + mode, cloud-shadow overlay visibility, GI mode (+ High params), tone mapping, and exposure; unit test asserts the live node values after applying a preset and that node-name differences do not break resolution.
- [x] 2.5 Classify texture quality as restart-only and apply it at boot; make shadow quality live via `RenderingServer` (directional shadow atlas size + mode); unit test asserts the classification (texture restart-only, every other field live) and that a live shadow-quality change updates the rendering server without restart.
- [x] 2.6 Re-apply persisted graphics whenever an environment scene is (re)instantiated; integration test performs a mission/world swap and asserts the preset is still in effect (not reset to scene defaults), including after `LightingControls._ready()`.
- [x] 2.7 Apply persisted graphics in the Map Editor and Asset Browser scenes; integration test loads each scene with a non-default preset and asserts the environment/light/cloud nodes reflect it.

## 3. Options view, surfaces, and restart

- [x] 3.1 Build the `OptionsView` scene/script with Graphics/Input/Game section navigation, wired read/write through the three settings owners; unit test opens it on a named section and switches sections, and asserts opening/closing changes no game, persisted choice, or gameplay entity.
- [x] 3.2 Theme `OptionsView` from the active `GameDefinition` when opened from the main/pause surface and use neutral when opened from the boot selector; test asserts the neutral path references no `res://games/` asset even though a game is active.
- [x] 3.3 Make the `BootScreen.Options` row open `OptionsView` (remove the disabled placeholder) and update `test_boot_screen` accordingly.
- [x] 3.4 Add `Options` entry points to `MainMenu01` and `PauseMenu`, opening the same view; integration test opens it from each surface and asserts closing returns to the caller.
- [x] 3.5 Make the pause-menu Options overlay modal: `process_mode = ALWAYS` and ESC closes it without resuming (`get_tree().paused` stays true); test asserts the paused state is preserved on ESC.
- [x] 3.6 Implement the one-shot `[ui]` restart marker + `OS.set_restart_on_exit` path with a resume hook mounted outside `BootScreen`; test asserts a request from the main menu resumes the same section after relaunch, the hook fires even with `--game` (selector skipped), and the marker is cleared once.
- [x] 3.7 Disable restart-only rows on the pause-menu surface; test asserts the controls are disabled, no marker can be recorded from there, and a restart-only value leaves the running renderer unchanged.

## 4. Per-game input

- [x] 4.1 Add the `GameDefinition.supported_inputs` declaration and validation; unit test asserts a declared action binds and an undeclared action is inert for that game.
- [x] 4.2 Refactor `InputSettings` to resolve `[input.<id>]` → `[input]` → `project.godot` default and re-apply on `GameContext.game_changed`; tests cover base-only, override-wins, and revert-on-switch.
- [x] 4.3 Build the Input options table (base column + one column per known game) showing inherited vs overridden values and disabling unsupported cells; tests cover inherited, override, disabled, and base-edit cases.
- [x] 4.4 Propose and add the glossary entry for the game input-support declaration (e.g. "input support matrix") plus the other coined terms ("quality preset", "Options view") to `GLOSSARY.md`, and verify `serena memories check` passes from the repo root.

## 5. Per-game game settings and move-target line

- [x] 5.1 Add the `GameSettings` registry and per-game persistence under `[game_settings.<id>]`, applying on `game_changed`; tests cover per-game isolation, unknown-game defaults, and persistence across a simulated restart.
- [x] 5.2 Gate move-target line registration inside `SelectComponent` on the `move_target_line` toggle; regression test proves move lines do not register with the toggle off and do with it on, and that rally lines still render with the toggle off.

## 6. Integration verification

- [x] 6.1 Add an end-to-end integration test: select a non-default preset, restart, and assert the persisted preset re-applies at boot and is reported by `GraphicsSettings`.
- [x] 6.2 Run the full suite `redot --headless -s test/run_tests.gd` and confirm all new and existing tests pass.
- [x] 6.3 Run `gdlint scripts/**/*.gd test/**/*.gd` and `gdformat --check scripts/**/*.gd test/**/*.gd`, then `grep -P '\t' scripts/**/*.gd` to confirm no tabs, and fix any findings.

## 7. Options UX: display settings, custom preset, centered dialog

- [x] 7.1 Add the `display` domain to the graphics schema — window mode (Windowed/Borderless/Fullscreen) and resolution — with labels/descriptions; keep it out of the presets and prove presets never set it.
- [x] 7.2 Apply display settings live (resize/center in windowed, switch mode otherwise) with a headless no-op guard; unit test asserts the no-op path and that resolution options always include the stored value.
- [x] 7.3 Add a `matching_preset()` that reports `custom` when the graphics fields match no named preset; the Options preset picker offers a `Custom` item and re-selects it on divergence; unit test proves preset selection refreshes every option control and divergence shows `Custom`.
- [x] 7.4 Add labels, descriptions (tooltips), and pretty option labels to the schema and render them; add the missing numeric control for `exposure` so every field is editable.
- [x] 7.5 Center the Options dialog over a dimmed full-screen backdrop on every surface; unit test asserts the panel is centered by a full-rect `CenterContainer`.
- [x] 7.6 Fix the Restart button: offer it only when a restart-only field diverges from its boot value; unit test asserts it is hidden before and shown after a restart-only change. Guard `MainMenu01._input` while the Options overlay is open.
