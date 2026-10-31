## Purpose

GuardComponent Mode A stand-and-shoot acquisition: idle armed entities auto-acquire the nearest in-range hostile and engage without chasing.

## Requirements

### Requirement: GuardComponent attaches to armed entities
`EntityFactory` SHALL attach a `GuardComponent` to every entity whose `EntityData.weapons` array is non-empty, alongside the existing `CombatComponent`. Entities with no weapons SHALL NOT receive a `GuardComponent`.

#### Scenario: Armed entity gets GuardComponent
- **WHEN** an entity is created from EntityData with one or more weapons
- **THEN** the entity root SHALL have both a `CombatComponent` and a `GuardComponent` child named `GuardComponent`

#### Scenario: Unarmed entity gets no GuardComponent
- **WHEN** an entity is created from EntityData with an empty weapons array
- **THEN** the entity root SHALL NOT have a `GuardComponent` child

### Requirement: Idle armed entity auto-acquires nearest enemy already in weapon range
While an entity has a `GuardComponent`, no active `CombatComponent` engagement (entity target **or** ground engagement — `is_engaged()`, not merely a non-null `get_target()`), no in-progress movement, and power online (or no PowerComponent), the guard SHALL periodically scan for hostile entities within the longest weapon's range and, on finding at least one, call `CombatComponent.set_target()` with `hold_ground = true` on the nearest hostile. Acquisition range SHALL be `max(weapon.attack_range) * CellUtil.CELL_SIZE` world units over all of the entity's weapons, measured on the horizontal (XZ) plane. Candidate distance SHALL be measured to the candidate's effective target point: for a candidate with a `FoundationComponent`, the nearest point on its foundation footprint (the same measurement `CombatComponent` uses for range); otherwise the candidate's `global_position`. Hostility SHALL be `PlayerManager.is_enemy(self_player_id, candidate_player_id)` with both ids >= 0. A candidate SHALL additionally be visible to the scanning entity's **owning** player: `ShroudSystem.is_visible(owning_player_id, candidate_cell)` (which includes allied union). The owning player id SHALL be read from the scanning entity's `StatsComponent`, never the local player, so a computer-owned unit is not blinded by the human player's own fog. The scan SHALL query `SpatialHash` cells within a square hood of Chebyshev radius `max(1, ceil(range_world / CellUtil.CELL_SIZE)) + BUILDING_HOOD_MARGIN_CELLS` cells centered on the entity (full ±r index square, not a cell-index circle — diagonal in-range entities must not be skipped), not a full `all_entries()` walk. `BUILDING_HOOD_MARGIN_CELLS` is a bounded constant of 4 covering the widest foundation in content (6x6, half-extent 3 cells) plus one cell of rounding slack, because `SpatialHash` indexes each entity at its centre cell: without the margin a building whose centre is outside weapon range but whose nearest footprint edge is inside it would never be scanned. Candidates SHALL be filtered to entities that have a HealthComponent.

Acquisition is the only place visibility is tested. Once acquired, an engagement SHALL be retained even when the target later moves into a cell that is no longer visible — there is no visibility drop gate.

#### Scenario: Enemy already inside weapon range is acquired
- **WHEN** an armed idle unit with GuardComponent has an enemy whose horizontal distance is <= longest weapon range, whose cell is visible to the owning player, and no active attack target
- **THEN** GuardComponent SHALL call `CombatComponent.set_target()` with `hold_ground = true` and the unit SHALL fire without issuing a chase move

#### Scenario: Enemy in a non-visible cell is not acquired
- **WHEN** an armed idle unit with GuardComponent has a hostile entity within weapon range whose cell is not visible to the owning player
- **THEN** GuardComponent SHALL NOT acquire that entity and the unit SHALL remain idle

#### Scenario: Engaged target that leaves visibility is retained
- **WHEN** a guard-acquired target moves from a visible cell into a cell that is no longer visible to the owning player while the engagement is active
- **THEN** GuardComponent SHALL retain the engagement and the unit SHALL continue firing at it

#### Scenario: Computer-owned guard uses its own visibility
- **WHEN** a computer-owned armed unit scans for a target while the local player's fog is revealed
- **THEN** candidate visibility SHALL be evaluated against the computer-owned entity's own player, not the local player

#### Scenario: Building edge in range is acquired while center is out of range
- **WHEN** an armed idle unit has a hostile building whose foundation-footprint center is beyond the longest weapon range but whose nearest footprint point is within it and visible to the owning player
- **THEN** GuardComponent SHALL acquire that building, consistent with `CombatComponent` range checking

#### Scenario: Building acquired diagonally by its nearest corner
- **WHEN** a hostile building sits diagonally from the unit such that its footprint center is out of range but its nearest corner is within range and visible to the owning player
- **THEN** GuardComponent SHALL acquire the building (the widened hood covers the centre cell and the distance filter uses the corner)

#### Scenario: Enemy in sight but outside weapon range is ignored
- **WHEN** an enemy is farther than the longest weapon range (even if within `StatsComponent.sight`)
- **THEN** GuardComponent SHALL NOT acquire that enemy for this mode

#### Scenario: Nearest of multiple in-range enemies is chosen
- **WHEN** two or more hostile entities are within weapon range of an idle guarded unit and visible to the owning player
- **THEN** the candidate with the smallest horizontal distance to the unit SHALL be selected (ties: first found in deterministic cell scan order), where a building candidate's distance is to its nearest footprint point

#### Scenario: No enemy in weapon range stays idle
- **WHEN** a guarded unit scans and finds no hostile entity within weapon range
- **THEN** GuardComponent SHALL NOT call `set_target` and the unit SHALL remain idle

#### Scenario: Friendly or neutral entities are ignored
- **WHEN** entities within weapon range belong to the same team as the guard (or player_id < 0)
- **THEN** they SHALL NOT be selected as acquisition targets

#### Scenario: Diagonal corner cell within weapon range is acquired
- **WHEN** an enemy sits in a cell whose index offset from the unit fails a cell-index circle of radius `r_cells` (e.g. offset (4,4) with r_cells=5) but its horizontal world distance is still <= weapon range and its cell is visible to the owning player
- **THEN** GuardComponent SHALL still acquire that enemy (square hood, exact world distance)

#### Scenario: Candidate without HealthComponent is ignored
- **WHEN** a hostile entity within weapon range has no HealthComponent sibling
- **THEN** GuardComponent SHALL NOT select it as an acquisition target

#### Scenario: Guard does not steal a ground engagement
- **WHEN** an armed idle unit has an active ground engagement (`is_engaged()` true, `get_target()` null) and a hostile entity enters weapon range and visibility
- **THEN** GuardComponent SHALL NOT call `set_target` and the ground engagement SHALL continue uninterrupted

### Requirement: Hold-ground engagements never chase
When a target is set with `hold_ground = true`, CombatComponent SHALL NOT issue approach/chase moves. If the target's horizontal distance exceeds the longest weapon range on a subsequent `_physics_process` tick, CombatComponent SHALL `clear_target()` and remain in place rather than calling `_move_toward_target`. Player-ordered attacks (`hold_ground = false`, the default) SHALL retain existing chase behavior unchanged.

#### Scenario: Guard engagement stays put while target in range
- **WHEN** a hold-ground target remains within weapon range
- **THEN** CombatComponent SHALL fire (subject to cooldown/facing) and SHALL NOT call `mc.set_target_position` for a chase

#### Scenario: Target leaves weapon range disengages without moving
- **WHEN** a hold-ground target moves beyond longest weapon range
- **THEN** CombatComponent SHALL clear the attack target on that tick and SHALL NOT issue a chase move; the unit stays at its current position

#### Scenario: Player attack still chases
- **WHEN** `set_target` is called with default `hold_ground = false` and the target is out of range
- **THEN** CombatComponent SHALL issue the existing approach move toward the target

### Requirement: Guard does not interrupt player orders or active engagements
GuardComponent SHALL NOT scan (or SHALL skip the scan) when any of the following hold: `CombatComponent.get_target()` is non-null; a sibling `MovementController` exists and `is_moving()` is true; a sibling `PowerComponent` exists and `is_online` is false; the entity is invalid, a preview, or under a map editor.

#### Scenario: Active attack suppresses re-scan
- **WHEN** a guarded unit already has an attack target
- **THEN** GuardComponent SHALL NOT call `set_target` again until the target is cleared

#### Scenario: Player move suppresses acquisition
- **WHEN** a player-ordered move is in progress (MovementController `is_moving()` is true) and an enemy is in weapon range
- **THEN** GuardComponent SHALL NOT call `set_target` for that tick

#### Scenario: Power offline suppresses acquisition
- **WHEN** the entity has a PowerComponent with `is_online == false` and an enemy is in weapon range
- **THEN** GuardComponent SHALL NOT call `set_target`

### Requirement: Guard re-scans after target clears
When a previous engagement ends via target death (`health_zero` → `clear_target()`), hold-ground range break, invalid target, or player move clearing the attack, the unit returns to idle. On the next guard throttle tick that passes the idle gates, GuardComponent SHALL re-scan; if another hostile remains in weapon range it SHALL acquire it, otherwise the unit stays idle.

#### Scenario: Last enemy killed returns to idle
- **WHEN** the guarded unit's only nearby enemy dies and `clear_target()` has run
- **THEN** the next guard scan SHALL find no hostile in weapon range and the unit SHALL remain idle with no attack target

#### Scenario: Second in-range enemy re-acquires
- **WHEN** the current target dies while another hostile remains within weapon range
- **THEN** the next guard scan SHALL call `set_target` on the remaining hostile

### Requirement: Acquisition scans are throttled and phase-staggered
GuardComponent SHALL run the hood scan at most once per throttle interval (a fixed constant on the component, default ~0.3 s), and SHALL apply a per-instance phase offset so entities created in the same frame do not scan on the same physics tick.

#### Scenario: Scan does not run every physics tick
- **WHEN** `_physics_process` runs multiple times within one throttle interval while the unit is idle
- **THEN** the hood walk SHALL execute at most once during that interval

#### Scenario: Phase offset separates same-frame spawns
- **WHEN** two guarded entities are created in the same frame
- **THEN** their first scans SHALL be staggered by the per-instance phase offset rather than coinciding

### Requirement: Guard-area stance
A `GuardComponent` SHALL expose a guard-area stance entered when the guard-area order moves its entity: the stance records the entity's assigned destination as its anchor, keeps the existing idle stand-and-shoot acquisition (weapon-range radius, hold-ground, visibility, throttle), and walks the unit back to the anchor when the unit is idle, not engaged, and farther from the anchor than a small displacement threshold. The stance SHALL be cleared by a player-issued move to a destination farther from the anchor than the displacement threshold, by the Stop command, and by a failed return move (so an unreachable anchor does not retry forever). Guard Area SHALL NOT add a second targeting path: acquisition remains the existing Mode A scan.

#### Scenario: Unit guards the ordered area after arriving
- **WHEN** a unit with a `GuardComponent` receives the guard-area order and finishes moving to its assigned destination
- **THEN** it SHALL be in the guard-area stance and acquire a hostile that enters weapon range with the existing hold-ground behavior

#### Scenario: Displaced unit returns to the anchor
- **WHEN** a unit in the guard-area stance is idle, not engaged, and farther from its anchor than the displacement threshold
- **THEN** it SHALL request a move back to the anchor position

#### Scenario: Player move clears the stance
- **WHEN** the player issues a normal move to a unit in the guard-area stance to a destination farther from the anchor than the displacement threshold
- **THEN** the guard-area stance SHALL be cleared and the unit SHALL NOT return to the old anchor

#### Scenario: Stop clears the stance
- **WHEN** the Stop command is applied to a unit in the guard-area stance
- **THEN** the stance SHALL be cleared

#### Scenario: Unreachable anchor abandons the stance
- **WHEN** the stance's return move fails to find a path to the anchor
- **THEN** the stance SHALL be cleared instead of retrying every tick

#### Scenario: Unarmed selection has no stance
- **WHEN** a unit has no `GuardComponent` and receives the guard-area order
- **THEN** it SHALL only move to the target; no guard-area stance SHALL exist
