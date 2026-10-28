# Proposal

## Why

Weapon impact — "weapon W from shooter S lands on victim V or ground point P" — is implemented twice and the copies already diverge. `CombatComponent` owns a hitscan copy (`_apply_hitscan_damage`, `_victim_impact_pos`, `_damage_cell_overlays`); `ProjectileController` owns a near-identical arrival copy (`_detonate_on`, `_is_structure`, `_resolve_ground_victim`, `_damage_cell_overlays`, `_compute_damage_for`). Impact FX/sound live in `EntityFactory`, an assembler, reached through the `HealthComponent.damage_taken` choke point. Every recent impact change (#264, #360, #455, #37, #243) had to edit two or three of these files, and the projectile still reads the shooter's veteran damage through an untyped `has_method("get_effective_damage")` duck-type.

## What Changes

- Add one typed `WeaponDetonation` module: `detonate(weapon, shooter, effective_damage, target, ground_pos, arrival_pos) -> Impact`. It owns ground-victim resolution (the `SpatialHash` cell-victim query), the impact point (structure → `FoundationComponent.nearest_world_point`, ordered ground point, projectile snap radius), the warhead/armor damage math, the cell-overlay pass, and the impact report.
- Route both paths through it: `CombatComponent`'s hitscan fallback and `ProjectileController`'s arrival. Delete both `_damage_cell_overlays` copies, `_is_structure`, `_resolve_ground_victim`, `_compute_damage_for`, `_victim_impact_pos`, and `_apply_hitscan_damage`'s inline body.
- Move impact FX/sound out of `EntityFactory` into `FxSystem.play_impact` (behind the module). `EntityFactory` keeps death cleanup only; its `impact_played` signal moves to `FxSystem`.
- Replace the duck-typed seam: delete `ProjectileController.get_damage_info()`, `HitboxComponent.receive_damage_source()`, and the `received_damage` signal. The shooter's veteran-boosted damage is a typed `int` passed at fire time; `HealthComponent.take_damage` returns the applied amount so the module can suppress a report on a zero-applied hit.
- **BREAKING (internal scripts only):** `HitboxComponent.receive_damage_source`/`received_damage` and `ProjectileController.get_damage_info` are removed. No packed scene connects them; all callers move to `WeaponDetonation`.
- Fix a spec/code divergence while centralizing: an overlay-only detonation now plays the warhead's single impact report, matching the existing `entity-factory` requirement. Previously the overlay pass set `overlay_hit` and the fallback was skipped, so no report played.

Explicitly out of scope:

- Targeting policy and acquisition (separate change, #520).
- Projectile flight: arming, flight model, steering, detonation trigger, max-range fizzle, and friendly-fire victim classification stay in `ProjectileController`. Only arrival behavior moves.
- The invisible/teleport-detonate projectile family stays; it now calls the same module as hitscan.

## Capabilities

### New Capabilities

- `weapon-detonation`: one typed detonation interface for hitscan and projectile arrival — victim resolution, impact point, damage, overlay pass, and one impact report per detonation.

### Modified Capabilities

- `combat-firing`: weapon dispatch routes both the fallback and the projectile path through `WeaponDetonation`; the fallback no longer calls `HealthComponent.take_damage` directly.
- `projectile-runtime`: the payload requirement changes from the `get_damage_info()` dictionary to a typed detonation handoff; the lifecycle no longer routes damage through `HitboxComponent`.
- `entity-factory`: the "Warhead impact FX" requirement moves out of the assembler (removed).
- `fx-system`: adds the warhead impact report (`play_impact` + `impact_played`) now owned behind the detonation module.
- `audio-system`: the warhead impact sound moves to `FxSystem.play_impact` and plays at the resolved impact point rather than per victim.
- `veterancy`: the "collision hitbox entry" damage path is removed with the deleted `HitboxComponent` damage seam.

## Impact

- **Scripts:** `scripts/combat/WeaponDetonation.gd` (new), `scripts/components/CombatComponent.gd`, `scripts/components/ProjectileController.gd`, `scripts/components/HitboxComponent.gd`, `scripts/components/HealthComponent.gd`, `scripts/entities/EntityFactory.gd`, `scripts/core/FxSystem.gd`
- **Tests:** new `test/unit/test_weapon_detonation.gd` (parity, victim damage, overlay hits, FX count, structure/ground impact); migrate `test_ground_shot_damage`, `test_projectile_controller`, `test_fx_triggers`, `test_combat_sfx` scaffolding; `test_projectile_flight` stays flight-focused
- **Scenes:** no `.tscn` changes; no signal connections in packed scenes referenced the removed methods
- **UID files:** the new `scripts/combat/WeaponDetonation.gd.uid` and `test/unit/test_weapon_detonation.gd.uid` are committed with their scripts
- **Docs:** `GLOSSARY.md` impact FX row moves to `FxSystem`; add a `detonation module` entry
- **Backward compatibility:** `WeaponData`/`ProjectileData`/`WarheadData` resources unchanged; existing packed entity/projectile scenes load unchanged
