extends RefCounted

## Restart-and-resume marker for the Options view. Lives outside BootScreen so a
## relaunch with `--game` (which skips the selector) still resumes on the same
## section. Marker is one-shot: `consume` clears it.

const UserConfig := preload("res://scripts/core/UserConfig.gd")

const CONFIG_PATH: String = "user://settings.cfg"
const SECTION: String = "ui"
const KEY: String = "restart_section"
const FROM_KEY: String = "restart_from"


## Records the section to resume after a restart (and the requesting surface).
static func record(path: String, section: String, from_surface: String = "") -> void:
    UserConfig.set_sections(path, {SECTION: {KEY: section, FROM_KEY: from_surface}})


## Returns the recorded section and clears the marker ("" when none).
static func consume(path: String) -> String:
    var section := String(UserConfig.get_value(path, SECTION, KEY, ""))
    if section.is_empty():
        return ""
    UserConfig.set_value(path, SECTION, KEY, "")
    UserConfig.set_value(path, SECTION, FROM_KEY, "")
    return section
