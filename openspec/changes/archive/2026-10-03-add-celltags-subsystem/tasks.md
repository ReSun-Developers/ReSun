# Tasks

## 1. TerrainSystem cell-tag overlay

- [x] 1.1 Add `_cell_tags` to `TerrainSystem` with `set_cell_tag(cell, tag_id) -> bool`, `clear_cell_tag(cell) -> bool`, `get_cell_tag(cell)`, `has_cell_tag(cell)` and a `cell_tag_changed(cell, tag_id)` signal; reject out-of-diamond cells and empty tag ids, and reset the overlay in `clear()` and on grid re-init (as `_cell_pins` does). Verify `test/unit/test_cell_tags.gd` covers set/read-back, reassign, clear, outside-diamond, empty-id, clear-reset, and the `false` returns.
- [x] 1.2 Add `cells_with_tag(tag_id)` returning the cells bound to an id. Verify a unit test asserts a three-cell region and an empty result for an unknown tag.
- [x] 1.3 Add a `cell tag` entry to `GLOSSARY.md` (definition + link to the `terrain-cell-tags` spec). Verify the entry is present and the referenced path resolves.

## 2. Map-JSON persistence

- [x] 2.1 Write the overlay in `TerrainSystem.export_to_json` as a top-level `"cell_tags"` object keyed by `"x,y"`, omitted when empty. Verify a unit test asserts the key is present with tags and absent without.
- [x] 2.2 Restore `"cell_tags"` in `TerrainSystem.import_from_json` for in-diamond cells, discard out-of-diamond or malformed (non-`"x,y"` key, non-string value, empty value) entries, normalize the stored key, and clear the overlay at the start of import. Verify unit tests cover round-trip, absent-key-clean, out-of-diamond-discarded, and malformed-discarded.
- [x] 2.3 Verify an existing map without `"cell_tags"` (`games/ts/maps/gdi01.json`) loads with no tags and no error (regression).

## 3. MapEditor cell-tag tool

- [x] 3.1 Add `scripts/editor/CellTagTool.gd`: a view node whose `assign`/`clear` delegate to `TerrainSystem` and that renders a label per tagged cell showing its tag id, rebuilt on `TerrainSystem.cell_tag_changed` and `grid_initialized`. Verify an integration test tags a cell and observes a label at that cell.
- [x] 3.2 Wire the tool into `MapEditor`: `Tool.CELL_TAG`, a `Cell Tags` toolbar button, a tag-id `LineEdit`, input dispatch (left-click assigns, right-click clears), clearing on map-settings apply, and `cleanup()` in `_exit_tree` (as `PlayerStartTool`). Verify an integration test assigns and clears a cell through the tool input path.
- [x] 3.3 Verify save-then-load in the editor restores labels without any `EditorSaveLoad` change (persistence rides `TerrainSystem`). Verify an integration test saves, reloads, and finds the labels at the stored cells.

## 4. Integration

- [x] 4.1 End-to-end: load a fixture map containing `"cell_tags"`, then assert `cells_with_tag(tag_id)` returns the tagged region and `get_cell_tag(cell)` returns the id. Verify via the integration test.
- [x] 4.2 Run `gdlint`, `gdformat --check`, `redot --headless -s test/run_tests.gd`, and `openspec validate add-celltags-subsystem --strict`; verify all pass.
