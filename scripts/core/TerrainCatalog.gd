extends Node

## TerrainCatalog autoload — the global registry for terrain content, mirroring
## EntityFactory's data sets. Scans the active game's registered data-set layers
## (each layer's terrain_objects/, art/terrain/, and theaters/ dirs) and caches
## TerrainObject, TerrainArtData, and TheaterData by id. Owns the active theater
## (selected from the map JSON by MapLoader) and the resolve_art mesh-resolution
## choke point shared by the renderer and collision.

var _objects: Dictionary = {}
var _art: Dictionary = {}
var _theaters: Dictionary = {}
var _active_theater: TheaterData = null
var _data_sets: Array[String] = []
var _terrain_scene: PackedScene = null


func _ready() -> void:
    GameContext.game_changed.connect(_on_game_changed)
    _load_from_context()


## Registers terrain content from the active game's layer roots. Pulled at
## _ready (boot-time game_changed fires before this autoload exists) and
## re-run on every runtime game switch.
func _load_from_context() -> void:
    reset_content()
    var def := GameContext.current
    if def == null:
        return
    for root in def.data_sets:
        var base := root.trim_suffix("/")
        register_data_set(base + "/terrain_objects/")
        register_data_set(base + "/art/terrain/")
        register_data_set(base + "/theaters/")


func _on_game_changed(_def: GameDefinition) -> void:
    _load_from_context()


## Clears all registered content plus derived state (active theater, cached
## terrain scene). Called before every (re)registration.
func reset_content() -> void:
    _objects.clear()
    _art.clear()
    _theaters.clear()
    _data_sets.clear()
    _active_theater = null
    _terrain_scene = null


## The active terrain art's GLB scene (from the art seam, so corner-pivoted
## tiles are used), cached. Falls back to the placeholder const when art cannot
## resolve.
func load_terrain_scene() -> PackedScene:
    if _terrain_scene:
        return _terrain_scene
    var resolution := resolve_art("clear01", get_active_theater_id())
    if resolution.valid and not resolution.glb_path.is_empty():
        var scene := load(resolution.glb_path) as PackedScene
        if scene != null:
            _terrain_scene = scene
            return _terrain_scene
    var fallback := _fallback_scene_path()
    if fallback.is_empty():
        push_warning("TerrainCatalog: no fallback terrain scene for the active game")
        _terrain_scene = null
        return null
    _terrain_scene = load(fallback) as PackedScene
    return _terrain_scene


## The active game's declared fallback terrain scene path, or "" when none.
func _fallback_scene_path() -> String:
    var def: GameDefinition = GameContext.current
    return def.fallback_terrain_scene if def else ""


## Registers a directory to scan, recursing into subdirectories and caching each
## .tres by id in the cache matching its resource type. Idempotent per path.
func register_data_set(path: String) -> void:
    if _data_sets.has(path):
        return
    _data_sets.append(path)
    _scan_directory(path)


func _scan_directory(path: String) -> void:
    var dir := DirAccess.open(path)
    if not dir:
        push_warning("TerrainCatalog: Cannot open directory: %s" % path)
        return
    dir.list_dir_begin()
    var file_name := dir.get_next()
    while file_name != "":
        var resource_path := file_name.trim_suffix(".remap")
        if resource_path.ends_with(".tres"):
            var full_path := path + resource_path
            var resource: Resource = load(full_path)
            if resource is TerrainObject:
                _objects[resource.id] = resource
            elif resource is TerrainArtData:
                _art[resource.id] = resource
            elif resource is TheaterData:
                _theaters[resource.id] = resource
        elif dir.current_is_dir() and not file_name.begins_with("."):
            _scan_directory(path + file_name + "/")
        file_name = dir.get_next()
    dir.list_dir_end()


## TerrainObject registered under `object_id`, or null.
func get_object(object_id: String) -> TerrainObject:
    return _objects.get(object_id) as TerrainObject


## TerrainArtData registered under `art_id`, or null.
func get_art(art_id: String) -> TerrainArtData:
    return _art.get(art_id) as TerrainArtData


## TheaterData registered under `theater_id`, or null.
func get_theater(theater_id: String) -> TheaterData:
    return _theaters.get(theater_id) as TheaterData


## Registers a TerrainArtData directly (runtime content registration, mirrors
## register_data_set). Overwrites an existing entry with the same id.
func register_art(art: TerrainArtData) -> void:
    if art and not art.id.is_empty():
        _art[art.id] = art


## Registers a TheaterData directly (runtime content registration). Overwrites
## an existing entry with the same id.
func register_theater(theater: TheaterData) -> void:
    if theater and not theater.id.is_empty():
        _theaters[theater.id] = theater


## Every registered object: id -> TerrainObject (copy).
func get_all_objects() -> Dictionary:
    return _objects.duplicate(true)


## Every registered art entry: id -> TerrainArtData (copy).
func get_all_art() -> Dictionary:
    return _art.duplicate(true)


## Every registered theater: id -> TheaterData (copy).
func get_all_theaters() -> Dictionary:
    return _theaters.duplicate(true)


## Selects the active theater by id. Unknown ids fall back to the first
## registered theater and emit a warning; an empty id clears the selection.
func set_active_theater(theater_id: String) -> void:
    if theater_id.is_empty():
        _active_theater = null
        return
    var theater := get_theater(theater_id)
    if theater:
        _active_theater = theater
        return
    push_warning(
        "TerrainCatalog: unknown theater id '%s'; using first registered theater" % theater_id
    )
    _active_theater = _first_theater()


## The currently selected theater, or the first registered when unset.
func get_active_theater() -> TheaterData:
    if _active_theater:
        return _active_theater
    return _first_theater()


## Id of the active theater, or "" when none is registered.
func get_active_theater_id() -> String:
    var theater := get_active_theater()
    return theater.id if theater else ""


## Resolves a cell's mesh: the object's shared art entry resolved for the
## theater, or the art entry keyed by the id directly. Invalid when neither an
## object with art nor an art entry exists for the id.
func resolve_art(object_id: String, theater_id: String) -> TerrainArtData.ArtResolution:
    var obj := get_object(object_id)
    if obj and obj.art_data:
        return obj.art_data.resolve(object_id, theater_id)
    var art := get_art(object_id)
    if art:
        return art.resolve(object_id, theater_id)
    return TerrainArtData.ArtResolution.new()


## Sentinel cell for callers without cell context (skips the pin check).
const NO_CELL := Vector2i(-1, -1)


## Resolves a rendered cell's art from its cell data: a cliff pin on `cell`
## (when provided) resolves first, then the baked object_id (catalog path),
## then the legacy type/variant family, all resolved for the active theater.
## Invalid when none of those paths yields art. An unknown pinned id falls
## back to the derived paths with a warning.
func resolve_cell_art(
    cell_data: Dictionary, cell: Vector2i = NO_CELL
) -> TerrainArtData.ArtResolution:
    if cell != NO_CELL:
        var pinned: String = TerrainSystem.get_pin(cell)
        if not pinned.is_empty():
            if get_object(pinned) == null:
                push_warning(
                    "TerrainCatalog: pinned object '%s' unknown; using derived resolution" % pinned
                )
            else:
                return resolve_art(pinned, get_active_theater_id())
    var object_id: String = cell_data.get("object_id", "")
    var family := (
        object_id
        if not object_id.is_empty()
        else _get_mesh_family(
            String(cell_data.get("type", "clear")), int(cell_data.get("variant", 1))
        )
    )
    return resolve_art(family, get_active_theater_id())


## The TerrainArtData resource that renders a cell (catalog object art, else the
## direct art entry for the type/variant family). Null when neither exists.
## Uses the same family selection as resolve_cell_art so map coloring matches
## the mesh.
func get_cell_art(cell_data: Dictionary) -> TerrainArtData:
    var object_id: String = cell_data.get("object_id", "")
    var family := (
        object_id
        if not object_id.is_empty()
        else _get_mesh_family(
            String(cell_data.get("type", "clear")), int(cell_data.get("variant", 1))
        )
    )
    var obj := get_object(family)
    if obj and obj.art_data:
        return obj.art_data
    return get_art(family)


## Legacy mesh-family fallback for cells without a baked object_id
## (type+variant -> e.g. "clear01", "slope02"). New cells carry object_id.
static func _get_mesh_family(terrain_type: String, variant: int) -> String:
    var prefix := ""
    match terrain_type:
        "clear":
            prefix = "clear"
        "slope":
            prefix = "slope"
        "cliff":
            prefix = "cliff"
        _:
            prefix = "clear"
    return prefix + str(variant).pad_zeros(2)


func _first_theater() -> TheaterData:
    for key in _theaters:
        return _theaters[key] as TheaterData
    return null
