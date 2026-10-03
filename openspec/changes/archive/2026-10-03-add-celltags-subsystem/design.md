# Design

## Context

See proposal.md — Why. The engine already round-trips three sparse, cell-keyed terrain
overlays through map JSON v4: `_cells`, `_cell_pins`, and `_land_types`, all owned by
`TerrainSystem.export_to_json` / `import_from_json`. `PlayerStartTool` is the editor-tool
precedent, but it carries its own store only because `start_locations` is *not* in
`TerrainSystem`. Mission boot (#236) is on `main`; the tag→trigger table belongs to the
trigger engine (#237), not here.

## Goals / Non-Goals

**Goals:**
- One authoritative store for cell→tag-id bindings, round-tripped with the terrain overlays.
- A query surface the trigger engine can use to resolve a tag id to its cells and a cell to
  its tag.
- An editor tool to author and view bindings, with persistence for free.

**Non-Goals:**
- Parsing `[Tags]` / `[Triggers]` / `[Events]` / `[Actions]` or evaluating triggers (#237).
  This defers #414's "event binding" acceptance item; the safe "missing tag resolves safely"
  half lands here as the empty result from `cells_with_tag` / `get_cell_tag`.
- Storing or displaying tag *names*; the binding value is the opaque tag id only.
- The `#227` converter implementation — only the output contract it must satisfy.
- Waypoints (#234). #414 lists a dependency on the waypoint *pattern*, but #234 is not
  implemented; this design deliberately uses the existing `_cell_pins` overlay pattern
  instead, so cell tags do not depend on the waypoint tool.
- The legacy `NewINIFormat` < 4 coordinate encoding (`Y*128+X`); only `Y*1000+X` is in scope.

## Decisions

### D1 — Store the overlay in `TerrainSystem`, beside `_cell_pins`
`_cell_tags: Dictionary` maps `CellUtil.cell_key_str(cell)` → opaque tag id, exactly like
`_cell_pins`. This reuses the established sparse-overlay pattern, needs no new autoload,
and rides the existing `export_to_json` / `import_from_json` rails. #473 already lists
`TerrainSystem` as a system destined to move under the per-match World root, so the overlay
travels with it when that lands.
- *Alternatives:* a map-scoped `CellTagRegistry` under the World root (cleaner seam, but
  extra plumbing through `MapLoader` and `EditorSaveLoad` for the same bytes); a two-level
  `cell_tags` + `tags` model (faithful, but pulls the `[Tags]` table into this change and
  blurs the #237 boundary).
- *Trade-off:* scripting data lives in a terrain-geometry owner. Bounded, and it moves with
  `TerrainSystem` under #473.

### D2 — Value is the opaque tag id, not a name or trigger link
The binding stores the source tag id verbatim (e.g. `"02A74D10"`). Tag ids are unique and
stable; names from `[Tags]` are not, and the tag→trigger edge is #237's. Editor labels show
the id — adequate for debugging and for tags authored by the converter rather than by hand.
- *Alternatives:* store names (needs a name source and a collision policy); store the full
  tag record (blurs the #237 boundary).

### D3 — The editor tool is a view, not a second store
`CellTagTool` holds no overlay of its own; `assign`/`clear` call `TerrainSystem` and the
label overlay rebuilds from the store. Because `TerrainSystem.export_to_json` is what
`EditorSaveLoad` already calls and `TerrainSystem.import_from_json` runs inside
`MapLoader.load_map_into`, saving and loading need **no `EditorSaveLoad` or `MapLoader`
changes** — unlike `PlayerStartTool`, which must hand-carry `start_locations`.
The overlay rebuilds on `TerrainSystem.cell_tag_changed` (assign/clear) and on
`grid_initialized`, which `import_from_json` emits at its end and `init_grid` emits after a
map-settings reset — so labels refresh after load without any new signal or import
emission.
- *Alternative:* mirror `PlayerStartTool`'s private `_overrides` (rejected: duplicates the
  store and reintroduces a round-trip seam that can drift).

### D4 — Region query is the primary read
`cells_with_tag(tag_id) -> Array[Vector2i]` is the API triggers need (a tag spans a region,
e.g. "Reveal Falls" covers five cells); `get_cell_tag(cell) -> String` covers the inverse.
Both are O(n) over the sparse overlay, which is small (tens of entries).

### D5 — Converter emits normalized keys; engine never sees `Y*1000+X`
The source `[CellTags]` encodes `COORDS = Y*1000+X` for `NewINIFormat` ≥ 4 (verified against
`gdi1a.map`: the `"Reveal GDI Base 2"` tag at encoded `62042` decodes to cell `(42,62)`,
inside the GDI base cluster). The converter (#227) SHALL normalize to `"x,y"` keys matching
every other cell-keyed map key (`entities[].cell`, `start_locations[].cell`, `cell_pins`).
The engine consumes normalized keys only. This is stated as a requirement in the
`terrain-cell-tags` spec so the contract is testable without depending on #227's
implementation.

### D6 — Backward compatibility by omission
`cell_tags` is optional and omitted when empty; import ignores absent keys. No JSON version
bump, no packed-scene change, existing maps load unchanged.

## Risks / Trade-offs

- [Cell tags are invisible to the trigger engine until #237 lands] → The registry API is
  fixed now and tested in isolation, so #237 integrates without revisiting this change.
- [Editor labels show opaque hex ids] → Acceptable for debug/converter output; if human
  labels are wanted later, add a name table in #237 without changing the binding format.
- [`TerrainSystem` grows another responsibility] → It is already the map-JSON owner and the
  #473 World-root migration carries the overlay with it.
- [Labels go stale after import or a map-settings reset] → `CellTagTool` rebuilds from the
  store on `cell_tag_changed` and `grid_initialized`; no per-tag emission on import is
  needed.

## Migration Plan

Pure addition. Existing maps without `cell_tags` load with no tags. Rollback is deleting the
overlay and its JSON key; no data migration.

## Open Questions

- None blocking. Human-readable labels and the `[Tags]` name table are deferred to #237.
