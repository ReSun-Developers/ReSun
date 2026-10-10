# Spec Delta

## ADDED Requirements

### Requirement: Cell buildability predicate

`TerrainSystem` SHALL expose `is_cell_buildable(cell) -> bool` returning true only when the cell
is within the grid and its `get_cell_type(cell)` is `""` or `"clear"`, and false otherwise. A
cell outside the grid extent SHALL return false — `get_cell_type` returns `""` for out-of-extent
cells, so the bounds guard is required to avoid classifying off-map cells as buildable. This
SHALL be the single place the `""`/`"clear"` construction convention is evaluated; placement,
spawn, and resource code SHALL NOT inline the comparison. The predicate SHALL be O(1). This is
not a land-type sentinel-constant change — it relocates the existing two-literal comparison and
adds a bounds guard; it introduces no new land types or constants.

#### Scenario: Clear cell is buildable
- **WHEN** `is_cell_buildable(cell)` is called for an in-bounds cell whose type is `""` or `"clear"`
- **THEN** it returns true

#### Scenario: Non-clear cell is not buildable
- **WHEN** `is_cell_buildable(cell)` is called for an in-bounds cell whose type is `"slope"`, `"water"`, or any other non-clear type
- **THEN** it returns false

#### Scenario: Out-of-bounds cell is not buildable
- **WHEN** `is_cell_buildable(cell)` is called for a cell outside the grid extent
- **THEN** it returns false

### Requirement: Cell type seeding

`TerrainSystem` SHALL expose `set_cell_type(cell, type) -> void` that stores the given type on
the cell and emits `cell_changed` for that cell, so a cell's `type` can be set without writing
the private `_cells` dictionary. This provides a supported seam for tests and tools that need to
stage a specific surface type; ordinary cell types are otherwise derived from vertices. The
seeded type SHALL be observable through `get_cell_type(cell)`.

#### Scenario: Set and read back
- **WHEN** `set_cell_type(cell, "clear")` is called for an in-bounds cell
- **THEN** `get_cell_type(cell)` returns `"clear"` and `cell_changed` was emitted for the cell

#### Scenario: Set a blocking type
- **WHEN** `set_cell_type(cell, "slope")` is called for an in-bounds cell
- **THEN** `is_cell_buildable(cell)` returns false
