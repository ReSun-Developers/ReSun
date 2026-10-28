# Spec Delta

## MODIFIED Requirements

### Requirement: Hold-ground engagements never chase
When a target is set with `hold_ground = true`, CombatComponent SHALL NOT issue approach/chase moves. If the target's horizontal distance exceeds the longest weapon range on a subsequent `_physics_process` tick, CombatComponent SHALL `clear_target()` and remain in place rather than calling `_move_toward_target`. Player-ordered attacks (`hold_ground = false`, the default) SHALL retain existing chase behavior unchanged.

#### Scenario: Guard engagement stays put while target in range
- **WHEN** a hold-ground target remains within weapon range
- **THEN** CombatComponent SHALL fire (subject to cooldown/facing) and SHALL NOT call `mc.approach()` for a chase

#### Scenario: Target leaves weapon range disengages without moving
- **WHEN** a hold-ground target moves beyond longest weapon range
- **THEN** CombatComponent SHALL clear the attack target on that tick and SHALL NOT issue a chase move; the unit stays at its current position

#### Scenario: Player attack still chases
- **WHEN** `set_target` is called with default `hold_ground = false` and the target is out of range
- **THEN** CombatComponent SHALL issue the existing approach move toward the target
