# Spec Delta

## MODIFIED Requirements

### Requirement: FxSystem autoload and playback

The system SHALL provide an `FxSystem` autoload exposing `play(fx: FxData, global_transform: Transform3D) -> Node3D`. `play` SHALL instantiate the effect node, parent it to the match World root (falling back to the caller's scene root when no World root exists, so headless tests and the map editor still get a valid parent), place it at `global_transform`, and return the node. A null `fx` or one that fails `validate()` SHALL log a warning and return `null` without adding a node.

#### Scenario: Play adds a node

- **WHEN** `play` is called with a valid `FxData` and a transform during a match
- **THEN** a node exists under the match World root at that transform and is returned

#### Scenario: Null effect is a no-op

- **WHEN** `play` is called with `null`
- **THEN** no node is added, a warning is logged, and `null` is returned

#### Scenario: Play without a World root still spawns

- **WHEN** `play` is called where no match World root exists
- **THEN** the effect is parented to the available scene root and is returned, with no node dropped

#### Scenario: Cleanup on map change

- **WHEN** a match is replaced while one-shot effects are alive
- **THEN** those effects are released with the outgoing match's World root and no orphan nodes remain
