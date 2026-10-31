# Spec Delta

## REMOVED Requirements

### Requirement: Warhead impact FX
**Reason**: Impact FX and sound are weapon-impact behavior, not entity assembly. They move behind the shared `WeaponDetonation` module into `FxSystem.play_impact`, so `EntityFactory` no longer listens to `HealthComponent.damage_taken` for effects. This keeps the assembler focused on building and inserting entities.

**Migration**: `FxSystem.play_impact(damage_type, position)` now resolves the warhead and plays its `impact_fx` and `sound_impact`, emitting the `impact_played` signal that previously lived on `EntityFactory`. The detonation module calls it once per resolved shot at the resolved impact point. The behavior contract (one report per detonation, silent for non-warhead damage, fog gating delegated to `FxSystem`) is preserved in the `weapon-detonation` and `fx-system` capabilities.
