# Tasks

## 1. Regression tests first

- [x] 1.1 Add `test/unit/test_weapon_detonation.gd` covering: instant-fire vs projectile-arrival parity (same victim damage and impact position); effective-damage override; armor multiplier and zero multiplier; min/max clamping; ground occupant resolution and ordered-point impact; structure nearest-footprint impact; multi-cell non-structure point impact; snap radius vs distant arrival; overlay hit and overlay-as-target damaged once; mixed entity+overlay one `FxSystem.impact_played` report; overlay-only report; empty-ground report; report-without-media still emits; non-warhead damage silent; zero applied damage silent. Verify by running `flock /tmp/opencode/redot.lock redot --headless -s test/run_tests.gd` and capturing the base failure (`WeaponDetonation` not found)

## 2. Shared plumbing

- [x] 2.1 Change `HealthComponent.take_damage` to return the applied integer (0 on invalid damage or an already-dead victim); verify `test/unit/test_health_component.gd` and `test/unit/test_veterancy_system.gd` pass
- [x] 2.2 Add `FxSystem.impact_played` and `FxSystem.play_impact(damage_type, position)` resolving the warhead, playing `impact_fx`/`sound_impact`, and emitting once for a resolved warhead; verify `test/integration/test_fx_system.gd` passes and `test_weapon_detonation` remains red only because the module does not exist yet

## 3. Detonation module

- [x] 3.1 Create `scripts/combat/WeaponDetonation.gd` with the typed `detonate(...) -> Impact` entry, victim/impact-point resolution (structure gate on `StatsComponent.is_structure()` + `FoundationComponent`), warhead damage math, overlay pass, one-report rule over total applied damage, and the resolved impact point passed to `HealthComponent.take_damage`; verify `test/unit/test_weapon_detonation.gd` passes

## 4. Migrate both impact paths

- [x] 4.1 Rewrite `CombatComponent._apply_hitscan_damage` to call `WeaponDetonation.detonate` with `get_effective_damage(weapon)` and `_engagement_pos()`; delete `_victim_impact_pos` and `CombatComponent._damage_cell_overlays`; verify `test/unit/test_ground_shot_damage.gd`, `test/unit/test_combat_component.gd`, and `test/unit/test_force_fire_ground.gd` pass
- [x] 4.2 Add typed `effective_damage` to `ProjectileController.setup` (a negative value resolves to `weapon.damage` so existing direct `setup()` calls keep their damage) and rewrite `_detonate_on` to call the module and emit `impacted(result.position)`; delete `_is_structure`, `_resolve_ground_victim`, `_damage_cell_overlays`, `_compute_damage_for`, and the now-unused `SNAP_RADIUS`; update the class/`_detonate_on` docs that still mention the hitbox pipeline; verify `test/integration/test_projectile_flight.gd` and the remaining `test/unit/test_projectile_controller.gd` tests pass
- [x] 4.3 Pass `get_effective_damage(weapon)` from `CombatComponent._spawn_projectile` into `setup`; verify the parity test in `test_weapon_detonation` and `test_projectile_flight` pass

## 5. Move impact FX out of EntityFactory

- [x] 5.1 Remove `EntityFactory.impact_played`, `_on_entity_damaged`, `play_impact_effects_at`, and the `HealthComponent.damage_taken` connection, keeping the `health_zero` death cleanup; verify `grep -rn "impact_played\|_on_entity_damaged\|play_impact_effects_at" scripts/entities` returns nothing
- [x] 5.2 Migrate `test/integration/test_fx_triggers.gd` (drop `_wire_damage_fx`; rewrite the zero-applied case through the module), `test/unit/test_ground_shot_damage.gd` (drop `_wire_impact_reports`; connect `FxSystem.impact_played` through a root lookup), and `test/unit/test_combat_sfx.gd` (impact cases through the module or `FxSystem.play_impact`; keep death-sound cases); verify those three suites pass and no test calls a removed `EntityFactory` method

## 6. Delete the dictionary seam

- [x] 6.1 Remove `ProjectileController.get_damage_info`/`_payload`; remove `HitboxComponent.receive_damage_source`, `received_damage`, the `area_entered`/`body_entered` connections, the now-empty `_ready`, and the `get_damage_info` doc comment; verify `grep -rn "get_damage_info\|receive_damage_source\|received_damage" scripts test` returns nothing
- [x] 6.2 Migrate `test/unit/test_projectile_controller.gd`: delete the payload-contract/`get_damage_info` tests (their damage math is covered by `test_weapon_detonation`), keep the speed-precedence, friendly-fire, `impacted`, and detonation-health tests; update the file header that mentions the payload contract; verify the suite passes

## 7. Integration gates

- [x] 7.1 Run `gdlint scripts/**/*.gd test/**/*.gd`; verify zero errors
- [x] 7.2 Run `gdformat --check scripts/**/*.gd test/**/*.gd`; verify zero diffs
- [x] 7.3 Run `grep -P '\t' scripts/**/*.gd test/**/*.gd`; verify no tabs
- [x] 7.4 Run `flock /tmp/opencode/redot.lock redot --headless -s test/run_tests.gd`; verify the full suite passes

## 8. Docs and archive

- [x] 8.1 Update `GLOSSARY.md`: change the `impact FX` meaning to `FxSystem.play_impact` behind the detonation module and re-anchor it to `openspec/specs/fx-system/spec.md`; add a `detonation module` entry anchored to `scripts/combat/WeaponDetonation.gd`; verify `grep -n "detonation module\|impact FX" GLOSSARY.md` shows both updated rows
- [x] 8.2 Confirm `openspec/specs/projectile-runtime/spec.md` Purpose names `WeaponDetonation` (direct edit, since OpenSpec deltas cannot change Purpose); verify `grep -n "WeaponDetonation" openspec/specs/projectile-runtime/spec.md`
- [x] 8.3 Verify the new `scripts/combat/WeaponDetonation.gd.uid` and `test/unit/test_weapon_detonation.gd.uid` exist and are staged with their scripts
- [x] 8.4 Run `openspec archive refactor-detonation-module --yes`; verify `openspec/changes/` contains only `archive/` and the synced specs show the new `weapon-detonation` capability
