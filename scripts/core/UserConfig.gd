extends RefCounted

## Single authority for `user://settings.cfg`. Every settings owner reads and
## writes through these helpers, so the ConfigFile is always loaded, one or
## more keys changed, and saved — writing one section never clobbers another.
##
## Access via `const UserConfig = preload("res://scripts/core/UserConfig.gd")`.


## Loads the file, ignoring a missing/invalid file (treated as defaults).
static func read(path: String) -> ConfigFile:
    var cfg := ConfigFile.new()
    cfg.load(path)
    return cfg


## Returns the stored value or `default_value` when absent.
static func get_value(
    path: String, section: String, key: String, default_value: Variant
) -> Variant:
    var cfg := ConfigFile.new()
    if cfg.load(path) != OK:
        return default_value
    return cfg.get_value(section, key, default_value)


## Load-modify-save one key, preserving every other section.
static func set_value(path: String, section: String, key: String, value: Variant) -> void:
    var cfg := ConfigFile.new()
    cfg.load(path)
    cfg.set_value(section, key, value)
    _save(cfg, path)


## Load-modify-save a whole section, preserving every other section.
static func set_section(path: String, section: String, values: Dictionary) -> void:
    var cfg := ConfigFile.new()
    cfg.load(path)
    for key: String in values:
        cfg.set_value(section, key, values[key])
    _save(cfg, path)


## Load-modify-save several sections at once, preserving every other section.
static func set_sections(path: String, sections: Dictionary) -> void:
    var cfg := ConfigFile.new()
    cfg.load(path)
    for section: String in sections:
        var values: Dictionary = sections[section]
        for key: String in values:
            cfg.set_value(section, key, values[key])
    _save(cfg, path)


static func _save(cfg: ConfigFile, path: String) -> void:
    var err := cfg.save(path)
    if err != OK:
        push_warning("[UserConfig] Failed to save %s (error %d)" % [path, err])
