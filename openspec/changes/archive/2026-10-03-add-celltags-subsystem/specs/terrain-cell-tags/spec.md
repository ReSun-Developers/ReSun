# Spec Delta

## Purpose

Bind map cells to opaque scripting tag ids so mission triggers can reference regions of
cells: a sparse cell→tag-id overlay, a diamond-scoped runtime registry for querying a tag's
cells, map-JSON round-trip, and a MapEditor tool to author and view the bindings.

## ADDED Requirements

### Requirement: Cell tag overlay API
`TerrainSystem` SHALL store a sparse overlay mapping a cell to an opaque tag-id string. It
SHALL expose `set_cell_tag(cell, tag_id) -> bool`, `clear_cell_tag(cell) -> bool`,
`get_cell_tag(cell) -> String` (returning `""` when unbound), and `has_cell_tag(cell) ->
bool`. Assigning SHALL be rejected for cells outside the playable diamond and for empty tag
ids, returning `false`; `clear_cell_tag` SHALL return `false` when the cell has no tag.
Assigning or clearing a tag SHALL emit `cell_tag_changed(cell, tag_id)`. `clear()` and a
grid re-initialization SHALL reset the overlay.

#### Scenario: Set and read back
- **WHEN** an in-diamond cell is assigned tag id `"02A74D10"`
- **THEN** `get_cell_tag(cell)` returns `"02A74D10"` and `has_cell_tag(cell)` is true

#### Scenario: Reassign a cell
- **WHEN** a cell already bound to `"02A74D10"` is assigned `"08717E90"`
- **THEN** `get_cell_tag(cell)` returns `"08717E90"` and only one tag remains for that cell

#### Scenario: Clear a tag
- **WHEN** a bound cell is cleared
- **THEN** `get_cell_tag(cell)` returns `""` and `has_cell_tag(cell)` is false

#### Scenario: Outside the diamond rejected
- **WHEN** `set_cell_tag` is called for a cell outside the playable diamond
- **THEN** it returns `false` and no tag is recorded

#### Scenario: Empty tag id rejected
- **WHEN** `set_cell_tag` is called with an empty tag id
- **THEN** it returns `false` and no tag is recorded

#### Scenario: Clear reports nothing to clear
- **WHEN** `clear_cell_tag` is called for a cell that has no tag
- **THEN** it returns `false` and no tag is recorded

#### Scenario: Clear resets the overlay
- **WHEN** `clear()` is called after cells have been tagged
- **THEN** no cell reports a tag

### Requirement: Cell tags form regions
A single tag id MAY be bound to many cells. The system SHALL expose `cells_with_tag(tag_id)`
returning every cell currently bound to that id, in unspecified order. Every returned cell
SHALL be inside the playable diamond.

#### Scenario: Region lookup
- **WHEN** three cells are bound to `"02A74D10"` and one to `"08717E90"`
- **THEN** `cells_with_tag("02A74D10")` returns exactly those three cells

#### Scenario: Unknown tag
- **WHEN** `cells_with_tag` is queried for an id bound to no cell
- **THEN** it returns an empty result

### Requirement: Cell tags persist in map JSON
`TerrainSystem.export_to_json` SHALL write the overlay as a top-level `"cell_tags"` object
keyed by `"x,y"` cell strings, omitting the key when the overlay is empty.
`import_from_json` SHALL restore tags for cells inside the diamond and discard entries for
cells outside it. A map without a `"cell_tags"` key SHALL load with no tags.

#### Scenario: Round-trip
- **WHEN** a map with tagged cells is exported and re-imported
- **THEN** every tag and its cells are restored

#### Scenario: Absent key loads clean
- **WHEN** a map exported with no tags is imported
- **THEN** no cell reports a tag

#### Scenario: Out-of-diamond entries ignored
- **WHEN** an imported `"cell_tags"` object contains a cell outside the diamond
- **THEN** that entry is discarded and only in-diamond tags are restored

#### Scenario: Malformed entries ignored
- **WHEN** an imported `"cell_tags"` entry has a non-`"x,y"` key, a non-string value, or an empty value
- **THEN** the entry is discarded and no tag is recorded, and the rest of the map still loads

#### Scenario: Empty overlay omitted
- **WHEN** a map is exported with no tagged cells
- **THEN** the JSON contains no `"cell_tags"` key

### Requirement: MapEditor cell tag tool
The MapEditor SHALL provide a `Cell Tags` tool with a tag-id input field. While the tool is
active, a left-click on an in-diamond cell SHALL bind that cell to the entered tag id, and a
right-click on a tagged cell SHALL clear it. The editor SHALL render a visible label at each
tagged cell showing its tag id. Saving and loading SHALL persist the bindings without a
separate editor-side store.

#### Scenario: Assign a tag
- **WHEN** the `Cell Tags` tool is active with tag id `"02A74D10"` entered and the user left-clicks an in-diamond cell
- **THEN** that cell is bound to `"02A74D10"` and a label showing the id appears there

#### Scenario: Clear a tag
- **WHEN** the tool is active and the user right-clicks a tagged cell
- **THEN** the cell's tag is cleared and its label is removed

#### Scenario: Assign outside the diamond is rejected
- **WHEN** the tool is active and the user left-clicks a cell outside the diamond
- **THEN** the assignment is ignored

#### Scenario: Round-trip through save and load
- **WHEN** tagged cells are saved from the editor and the map is reloaded
- **THEN** the labels reappear at the stored cells

### Requirement: Converter cell-tag output contract
The TS `.map` → game JSON converter (#227) SHALL, for `NewINIFormat` ≥ 4 maps, emit
`cell_tags` keyed by normalized `"x,y"` cell coordinates, not the source `Y*1000+X`
encoding. Each value SHALL be the source tag id preserved verbatim. (The legacy
`NewINIFormat` < 4 encoding, `Y*128+X`, is out of scope.)

#### Scenario: Normalized keys
- **WHEN** the converter reads a source cell tag with encoded coordinate `46037` (`Y=46`, `X=37` under `Y*1000+X`)
- **THEN** the emitted key is `"37,46"`

#### Scenario: Tag id preserved
- **WHEN** the converter reads a source cell tag bound to tag id `"02A74D10"`
- **THEN** the emitted value is `"02A74D10"`
