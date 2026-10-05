# match-root Specification

## Purpose
Defines the per-match World root: a fresh container created for each match that
owns all scene content produced for that match — the loaded map and content
created during play (produced units, built structures, projectiles, effects, and
resources grown at runtime) — giving match teardown a single explicit owner and
preventing one match's content from surviving into the next.

## Requirements

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
descendant under it — map content and content spawned during play alike — before
the new match's content is added, so no per-match scene content from the previous
match remains in the scene tree; the detached subtree SHALL be freed at the end of
the frame.

#### Scenario: Second match starts clean

- **WHEN** a match is started while a previous match's World root is present
- **THEN** the previous World root is detached and queued for deletion, and the
  new match's World root is the only World root under `MainScene/Gameplay`

#### Scenario: Replaced map nodes are gone

- **WHEN** a match is replaced by another match
- **THEN** nodes created under the previous match's World root are no longer in
  the scene tree

#### Scenario: Runtime content from the previous match is gone

- **WHEN** a match that produced units, built structures, spawned effects and
  projectiles, or grew resources is replaced by another match
- **THEN** every such node is no longer in the scene tree after the swap

### Requirement: Runtime content lives under the match World root

Scene content created during a match — produced units, player-built structures,
projectiles, one-shot effects, and resources grown at runtime — SHALL be parented
under the match World root, so releasing the World root releases all of it. A
runtime spawner that does not choose its own parent SHALL resolve the match World
root and parent its node there rather than to the current scene. A live match
World root SHALL take precedence over a no-World fallback. When no World root
exists (headless tests, the map editor), a spawn SHALL fall back to an explicit
in-tree parent when one was supplied, otherwise to the current scene root and then
to the scene tree root, and SHALL NOT be dropped. A spawner that itself adds its
node to a fixed in-tree parent (for example a passenger returned to its transport)
SHALL keep that parent. Once a match is replaced, spawns SHALL resolve to the
incoming match's World root.

#### Scenario: Produced unit is parented under the World root

- **WHEN** a factory produces a unit during a match
- **THEN** the unit is a descendant of the match World root

#### Scenario: Spawned effect and projectile are parented under the World root

- **WHEN** a weapon fires a resolvable projectile and an effect is played during a match
- **THEN** both nodes are descendants of the match World root

#### Scenario: Spawn without a World root still succeeds

- **WHEN** content is spawned where no match World root exists (a headless test or
  the map editor)
- **THEN** the node is parented to the available current scene root and no spawn
  is dropped and no error is raised

#### Scenario: Explicit parent is used only when no World root exists

- **WHEN** a spawner supplies an explicit in-tree parent and no match World root exists
- **THEN** the node is parented to that parent, not to the scene tree root

#### Scenario: In-tree spawner keeps its fixed parent

- **WHEN** a spawner itself adds its node to a fixed in-tree parent during a match
- **THEN** the node is parented to that node
