# Spec Delta

## Purpose

Defines the per-match World root: a fresh container created for each match that
owns the loaded map and the scene content loaded with it, giving map teardown a
single explicit owner and preventing one match's map content from surviving into
the next. Runtime-spawned content (produced units, built structures, projectiles,
effects) is not yet routed under it; see design.md — Known gaps.

## ADDED Requirements

### Requirement: A match is hosted in a World root

Starting a match SHALL create a World root node under `MainScene/Gameplay` and
host the loaded map inside it. A match SHALL have at most one World root at a
time; loading a map that is missing or unreadable SHALL log an error and leave
the World root without map entities.

#### Scenario: Map content lives under the World root

- **WHEN** a mission with a readable map starts
- **THEN** the map and the entities loaded from the map JSON are descendants of a
  single World root node under `MainScene/Gameplay`

#### Scenario: Missing map leaves an empty World root

- **WHEN** a mission's `map_path` does not exist
- **THEN** an error is logged, the World root exists, and it contains no map
  entities

### Requirement: Starting a match releases the previous match's content

Starting a new match SHALL detach the previous match's World root and every
descendant under it before the new match's content is added, so no per-match
scene content from the previous match remains in the scene tree; the detached
subtree SHALL be freed at the end of the frame.

#### Scenario: Second match starts clean

- **WHEN** a match is started while a previous match's World root is present
- **THEN** the previous World root is detached and queued for deletion, and the
  new match's World root is the only World root under `MainScene/Gameplay`

#### Scenario: Replaced map nodes are gone

- **WHEN** a match is replaced by another match
- **THEN** nodes created under the previous match's World root are no longer in
  the scene tree
