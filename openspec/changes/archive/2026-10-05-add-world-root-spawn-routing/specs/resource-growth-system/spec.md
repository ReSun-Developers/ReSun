# Spec Delta

## ADDED Requirements

### Requirement: Runtime resource spawns follow the match World root

Resource entities grown or spread at runtime SHALL resolve their spawn parent through the match World root at spawn time, rather than reusing a parent reference cached earlier. This ensures a resource spawned after a match boundary is parented under the current match rather than a released one, and is released with the match that owns it.

#### Scenario: Growth after a match boundary

- **WHEN** a second match starts and its trees grow new resource cells
- **THEN** the new cells are descendants of the new match's World root and growth continues without a warning about a missing parent

#### Scenario: Grown resources are released with the match

- **WHEN** a match that grew resource cells at runtime is replaced
- **THEN** those grown cells are no longer in the scene tree
