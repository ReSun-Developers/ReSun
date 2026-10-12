# cell-surfaces Specification

## Purpose

Every terrain cell holds an ordered stack of walkable surfaces: the ground at level 0 plus zero or more deck levels above it, bounded by `MAX_HEIGHT`. The capability defines height-parameterized surface and land queries, per-level place-sets, the tower height-transition rules for moving between levels, stacked decks, and the default-to-level-0 behavior that keeps every existing caller unchanged.

## Requirements

### Requirement: Per-cell surface stack
A terrain cell SHALL hold an ordered stack of walkable surfaces: the ground surface at level 0, plus zero or more deck levels above it. Every cell SHALL have a ground surface at level 0. A deck surface SHALL be added for a cell when a bridge deck covers that cell at that level, and SHALL be removed when the deck is removed or destroyed. The stack SHALL be bounded by `TerrainSystem.MAX_HEIGHT` (10); a deck level SHALL NOT be created at or above that bound. The stack SHALL be stored per cell and SHALL NOT overwrite the ground surface.

#### Scenario: Ground-only cell
- **WHEN** a cell with no bridge deck is queried
- **THEN** its surface stack contains exactly the ground surface at level 0

#### Scenario: Deck adds a level above ground
- **WHEN** a bridge deck covers a cell
- **THEN** the cell's surface stack contains the ground at level 0 and the deck surface at the deck's level

#### Scenario: Deck removal restores the ground-only stack
- **WHEN** a covering deck is removed or destroyed
- **THEN** the cell's surface stack returns to the ground surface at level 0

#### Scenario: Stack bounded by max height
- **WHEN** a deck level at or above `MAX_HEIGHT` is requested
- **THEN** no surface is created and the request is refused

### Requirement: Height-parameterized surface queries
Surface identity and height SHALL be queryable for a given level. `TerrainSystem.get_land_type(cell, level)` SHALL return the land type of the surface at `level` — for a deck, the land that lane resolves (`road`, `railroad`, or `clear`), never a synthetic `bridge` type — and `TerrainSystem.get_cell_surface_height(cell, level)` SHALL return the walkable world Y of the surface at `level`. Both queries SHALL accept an optional `level` argument defaulting to `0`. Queried at level 0, they SHALL return the ground land type and ground surface height exactly as today. A query for a level with no surface SHALL report no land type (empty string at levels above 0); the height query MAY fall back to the terrain height so movement/rendering callers never receive an invalid Y.

#### Scenario: Default level is ground
- **WHEN** `get_land_type(cell)` and `get_cell_surface_height(cell)` are called without a level
- **THEN** they return the ground land type and ground height (level 0)

#### Scenario: Deck level resolves deck surface
- **WHEN** a deck surface exists at level `L` for a cell and it is queried at `L`
- **THEN** the query returns the deck's resolved land type and the deck world Y

#### Scenario: Rail deck reports railroad
- **WHEN** a rail-bridge middle lane exists at level `L` and is queried at `L`
- **THEN** the query returns `"railroad"`

#### Scenario: Ground beneath a deck is still ground
- **WHEN** a cell carries a deck at level > 0 and is queried at level 0
- **THEN** the query returns the underlying land type and ground height, not the deck's

#### Scenario: Absent level reports no surface
- **WHEN** a cell with only a ground surface is queried at level > 0
- **THEN** the query reports no surface at that level

### Requirement: Parallel place-sets per level
Occupancy places SHALL be tracked per surface level, so a deck's places are independent of the ground's places beneath it. The ground level and each deck level SHALL each support their own places, using the existing sub-slot place model (`CellSubPositions` / `GlobalRules.shared_slots_per_cell`). Unit occupancy SHALL be attributed to the level the unit stands on, and a unit on a deck SHALL NOT consume a ground place. The ground beneath a deck SHALL remain occupiable by ground traffic.

#### Scenario: Deck places independent of ground places
- **WHEN** a deck at level 2 covers a cell whose ground places are full
- **THEN** the deck level still has its own available places

#### Scenario: Ground under a deck is occupiable
- **WHEN** a high deck covers a cell and a ground unit is ordered onto the ground beneath it
- **THEN** the ground level accepts the unit as open ground

#### Scenario: Deck unit costs no ground place
- **WHEN** a unit occupies a cell on the deck level
- **THEN** the ground level's occupancy count is unchanged

### Requirement: Height transition rules
Movement between adjacent cells SHALL evaluate the step between their surfaces using the Tiberian Sun rules, applied across the level stack:
- same level SHALL be allowed;
- a change of level SHALL be allowed only when the surface height difference between the two `(cell, level)` surfaces is within the mover's `climb_tolerance` and the destination surface is passable — a matching-grade bridge end, a low-bridge ramp, or an ordinary ramp;
- a step whose surface height difference exceeds `climb_tolerance` SHALL be refused, including climbing from surrounding ground onto a high deck (a high bridge is entered only from a matching-grade end);
- any other difference SHALL be refused.

(Tiberian Sun permits a bare four-level step across a spanned deck because its bridge cell carries the deck alone; this model authors the approach grade on the bridge-end terrain instead, so the grade-matched rule above replaces that allowance. A future change MAY add the ±4 allowance for maps without carved ends.)

A step of two or more height levels SHALL be costed from the locomotor's Road row, not the destination's land type. On a deck surface, the terrain figure SHALL be skipped entirely: deck passability and cost SHALL be the Road row.

#### Scenario: Level step allowed
- **WHEN** two adjacent cells have surfaces at the same level
- **THEN** the transition is allowed

#### Scenario: One-level step needs a lower ramp
- **WHEN** a unit attempts a one-level step and the lower of the two cells is a ramp
- **THEN** the transition is allowed

#### Scenario: One-level step without a ramp refused
- **WHEN** a unit attempts a one-level step and the lower cell is not a ramp
- **THEN** the transition is refused

#### Scenario: Deck entry from a matching-grade end allowed
- **WHEN** a ground unit at the deck grade attempts to step onto the adjacent deck
- **THEN** the transition is allowed

#### Scenario: High deck entry from surrounding ground refused
- **WHEN** a ground unit at the surrounding ground grade attempts to step onto a high deck four levels above
- **THEN** the transition is refused

#### Scenario: Step over climb tolerance refused
- **WHEN** two adjacent surfaces differ by more than the mover's climb tolerance and neither is a matching-grade connection
- **THEN** the transition is refused

#### Scenario: Large step costed from road
- **WHEN** a unit crosses a step of two or more levels
- **THEN** the transition cost uses the locomotor's Road multiplier, not the destination land type

#### Scenario: Deck skips the terrain figure
- **WHEN** a tracked unit whose ground speed for the underlying land type is zero crosses a deck
- **THEN** the deck is passable because the deck surface uses the Road row

### Requirement: Stacked decks bounded by max height
A cell SHALL support multiple deck levels stacked at different world heights over the same XZ, bounded by `MAX_HEIGHT`. Each stacked deck level SHALL be an independent surface with its own places and SHALL participate in the height transition rules. A deck SHALL NOT be stacked at a level equal to or above `MAX_HEIGHT`.

#### Scenario: Two decks over one cell
- **WHEN** two deck levels are authored over the same cell at different heights
- **THEN** the cell exposes both deck surfaces, each at its own world Y

#### Scenario: Stacked decks have independent places
- **WHEN** a unit occupies the upper deck of a stacked cell
- **THEN** the lower deck and the ground each retain their own available places

#### Scenario: Stack over max height refused
- **WHEN** a deck is requested at a level at or above `MAX_HEIGHT`
- **THEN** it is not created

### Requirement: Ground under a deck retains its own land
The land type of the ground surface beneath a deck SHALL remain the cell's underlying land type (water, beach, clear, …). Resolving or removing a deck SHALL NOT mutate the ground surface's land type. Painted land-type overrides SHALL be unaffected by deck presence.

#### Scenario: Water stays water beneath a high deck
- **WHEN** a high deck covers a water cell and the cell is queried at level 0
- **THEN** the ground surface reports `water`

#### Scenario: Removing the deck keeps the painted overlay
- **WHEN** a deck covering a painted cell is removed
- **THEN** the painted land-type override on that cell is unchanged

#### Scenario: Deck does not overwrite ground land type
- **WHEN** a deck is resolved on a cell
- **THEN** the ground surface's land type is the same value as before the deck existed

### Requirement: Default level preserves existing callers
Every level-parameterized query and movement/occupancy API SHALL default to level 0. Existing callers that pass no level SHALL observe the ground surface and SHALL behave exactly as before the surface stack existed.

#### Scenario: Existing caller unaffected
- **WHEN** an existing caller queries land type, surface height, or occupancy without a level
- **THEN** it receives the ground-level result, identical to pre-change behavior

#### Scenario: Old map loads unchanged
- **WHEN** a map with no bridge decks is loaded
- **THEN** every cell exposes only the ground surface at level 0 and all queries report ground values

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
