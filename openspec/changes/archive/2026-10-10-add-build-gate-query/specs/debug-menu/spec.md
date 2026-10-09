# Spec Delta

## MODIFIED Requirements

### Requirement: Direct deploy fallback

When the "No prerequisites" cheat is enabled and the requesting player owns no building that produces the entity's queue type, clicking that entity's cameo SHALL start placing via EntityPlacer's placement session for it (direct deploy): the entity places at a non-blocked ground cell without factory involvement. Ownership SHALL be evaluated for the clicking player only; a producing building owned by another player SHALL NOT suppress the fallback. This fallback SHALL be a named path (`EntityPlacer.start_direct_deploy`, distinct from the place-anywhere start path) routed from ProductionManager so both entry points stay individually observable; the fallback logic SHALL NOT live in UI code.

#### Scenario: No factory for queue type
- **WHEN** "No prerequisites" is enabled, the queue's factory type is registered, the clicking player owns no matching producing building, and the user clicks the entity's cameo
- **THEN** EntityPlacer's session starts a preview for that entity, and clicking a non-blocked ground cell spawns it at full stats

#### Scenario: Another player's producer does not count
- **WHEN** "No prerequisites" is enabled, another player owns a matching producing building but the clicking player owns none, and the user clicks the entity's cameo
- **THEN** the direct deploy fallback fires for the clicking player

#### Scenario: Factory exists — normal production
- **WHEN** "No prerequisites" is enabled, the clicking player owns a matching producing building, and the user clicks the entity's cameo
- **THEN** production starts normally (the direct deploy fallback does not fire)
