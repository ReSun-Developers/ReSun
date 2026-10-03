# Proposal

## Why

The GDI Mission 01 map (`gdi1a`) is entirely script-driven, and `[CellTags]` is the
spatial anchor for that scripting: 52 triggers bind regions of cells to tag ids (bridge
destruction, area reveals, gas leaks). No engine subsystem owns cell tags today, so
trigger event 35 ("cell-tagged entity state") and the mission wiring (#248) have nothing
to query. This change adds the cell→tag binding, its runtime registry, its map-JSON
round-trip, and an editor tool — the storage half only; trigger evaluation stays in #237.
It is unblocked: mission boot (#236) is already on `main`.

## What Changes

- Add a sparse `_cell_tags` overlay to `TerrainSystem` (`"x,y"` cell key → opaque tag-id
  string), beside the existing `_cell_pins` / `_land_types` overlays.
- Expose a runtime registry: `set_cell_tag`, `clear_cell_tag`, `get_cell_tag`,
  `has_cell_tag`, `cells_with_tag`, plus a `cell_tag_changed` signal, scoped to the
  playable diamond like the pin API.
- Round-trip cell tags through map JSON v4 as a top-level `cell_tags` object, omitted
  when empty — the same persistence shape as `cell_pins`.
- Add a `Cell Tags` tool to the MapEditor: assign the tag id typed into a toolbar field
  (left-click) and clear it (right-click), with a label overlay showing the id per tagged
  cell. The tool is a view over `TerrainSystem` (single store), so saving and loading need
  no `EditorSaveLoad` or `MapLoader` changes.
- Pin the converter interface: #227 must emit `cell_tags` keyed by normalized `"x,y"`
  cells, not source-encoded `Y*1000+X` coordinates.
- Propose a `cell tag` entry for `GLOSSARY.md`.

## Capabilities

### New Capabilities
- `terrain-cell-tags`: sparse cell→tag-id overlay, diamond-scoped registry and queries,
  and `cell_tags` map-JSON persistence.

### Modified Capabilities
- `map-loader`: the "Map JSON persists terrain overlays and entity houses" requirement
  gains the optional `cell_tags` key alongside `cell_pins` and `land_types`.

## Impact

- `scripts/core/TerrainSystem.gd` — new overlay, query/mutator API, signal, clear sites,
  export line, import loop.
- `scripts/editor/CellTagTool.gd` — new editor tool (input + label overlay).
- `scripts/editor/MapEditor.gd` — new `Tool.CELL_TAG`, toolbar button and tag-id field,
  input dispatch, settings clear.
- `test/unit/test_cell_tags.gd` — new round-trip / registry / boundary tests.
- Specs: new `terrain-cell-tags`, delta on `map-loader`. `GLOSSARY.md` gains `cell tag`.
- No `MapLoader`, `EditorSaveLoad`, packed-scene, or map-JSON version changes; absent
  `cell_tags` loads clean, so existing maps stay valid.
- #414 nominally depends on the waypoint tool (#234) for its pattern, but #234 is not
  implemented; this change uses the existing `_cell_pins` overlay pattern instead. #414's
  "event binding" acceptance item is deferred to #237; the "missing tag resolves safely"
  half lands here (unknown tag → empty result).
- Contract only (not implemented here): #227 emits normalized `cell_tags`; #237/#248
  consume `cells_with_tag` / `get_cell_tag` and own the tag→trigger table.
