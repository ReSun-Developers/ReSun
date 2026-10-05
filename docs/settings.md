# User settings

All user settings live in one file, `user://settings.cfg`, written through
`scripts/core/UserConfig.gd`. Every writer loads the file, changes only its own
keys, and saves, so no concern clobbers another's.

## Layout

```ini
[game]
id="ts"

[graphics]
preset="low"
aa="off"
shadow_quality="off"
cloud_shadows=false
gi="off"
tonemap="filmic"
exposure=1.0
texture_quality="medium"
window_mode="windowed"      ; windowed | borderless | fullscreen
resolution="1920x1080"      ; window size when windowed

[ui]
restart_section=""      ; one-shot restart resume target

[input]                 ; base camera bindings (shared by every game)
camera_up="W"

[input.ts]              ; per-game overrides (only differing keys)
camera_up="Numpad8"

[game_settings.ts]      ; per-game gameplay/UI toggles
move_target_line=true
```

Resolution for the active game and an action: `[input.<game_id>]` → `[input]`
→ the `project.godot` default. A per-game cell that is absent inherits the base.

Graphics settings are global and shared by every game; input bindings and
game settings are per game id.

Within `[graphics]`, the quality fields (AA, shadow quality, cloud shadows, GI,
tone mapping, exposure, texture quality) are covered by the presets. The display
fields (`window_mode`, `resolution`) live in the same section but form a separate
`display` domain that presets never touch. Changing the window or selecting a
resolution applies immediately; the preset picker shows `Custom` whenever the
quality fields match no named preset.

## Legacy migration

Older builds stored camera settings under `[camera]` and `[keybinds]`. On load,
`InputSettings` reads those keys as a fallback and copies legacy `[keybinds]`
entries into `[input]` when the base section does not already define them, so an
existing install keeps its bindings.

## Example

With the file above, `camera_up` is `Numpad8` while `ts` is active and `W` while
any other game is active. Deleting the `[game_settings.ts]` section leaves
`move_target_line` at its registry default (`true`).
