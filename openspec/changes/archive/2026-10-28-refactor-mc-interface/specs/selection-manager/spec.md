# Spec Delta

## MODIFIED Requirements

### Requirement: Infantry cell pre-assignment
When infantry units are selected and a move command is issued, `request_move()` SHALL pre-assign each infantry to a cell using spiral search from the target cell, with max 3 per cell based on `CellReservation` combined capacity (physical idle infantry + in-flight claims). `request_move()` SHALL NOT pre-assign sub-slots; slot assignment SHALL occur at movement start inside the MovementController move intent (`move_to` / `player_move`) via `CellReservation.reserve_sub_slot`.

#### Scenario: Three infantry to same cell
- **WHEN** 3 infantry move to a cell with no existing infantry and no claims
- **THEN** all 3 are assigned to the target cell, and each claims a distinct sub-slot (0, 1, 2) at movement start

#### Scenario: Infantry overflow to adjacent cells
- **WHEN** 4 infantry move to a cell
- **THEN** 3 are assigned to the target cell, the 4th is assigned to the nearest free adjacent cell

#### Scenario: Target cell already has infantry
- **WHEN** 2 infantry move to a cell that already has 1 idle infantry
- **THEN** the 2 new infantry fill the remaining capacity, totaling 3 in the cell

#### Scenario: In-flight claims fill capacity
- **WHEN** a cell has idle infantry plus in-flight claims totaling 3
- **THEN** `_find_infantry_cell()` assigns new infantry to a neighboring cell instead

### Requirement: Sharers distribute by capacity
The system SHALL separate sharers from non-sharers when processing a group move command. Units whose MovementController `shares_cell()` returns true SHALL be distributed to cells near the target with at most `CellSubPositions.get_slot_count()` per cell, using `CellReservation` combined capacity. Each sharer SHALL be assigned a sub-slot at movement start inside the MovementController move intent (`move_to` / `player_move`); SelectionManager SHALL NOT pre-assign slots. Non-sharers SHALL use the existing offset-based vehicle formation.

#### Scenario: Group move with mixed units
- **WHEN** a player issues a move command with 6 sharers and 2 non-sharers selected
- **THEN** sharers are spread across cells near the target (≤ capacity per cell) using combined capacity, and non-sharers use existing offset logic

#### Scenario: Sharer cell search
- **WHEN** `_find_sharer_cell()` is called with a target cell at capacity
- **THEN** it spirals outward to find the nearest cell below capacity
