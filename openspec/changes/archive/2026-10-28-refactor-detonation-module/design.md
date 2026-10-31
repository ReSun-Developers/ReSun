# Design

## Context

Two impact implementations exist today:

```
CombatComponent (instant / fallback)
  _apply_hitscan_damage
    impact point   = _engagement_pos() or _victim_impact_pos(target)
    victim         = target or SpatialHash.resolve_cell_victim(...)
    entity damage  = HealthComponent.take_damage(compute_warhead_damage(get_effective_damage(w), ...))
    overlay pass   = _damage_cell_overlays
    fallback FX    = EntityFactory.play_impact_effects_at

ProjectileController (arrival)
  _detonate_on
    impact point   = ordered point / nearest_world_point / snap-to-victim
    victim         = target or _resolve_ground_victim(...)
    entity damage  = HitboxComponent.receive_damage_source(self)   # get_damage_info() dict
    overlay pass   = _damage_cell_overlays
    fallback FX    = EntityFactory.play_impact_effects_at
```

Divergences already present:

- `_damage_cell_overlays` is duplicated almost line for line.
- `_is_structure` exists only to reproduce `CombatComponent._victim_impact_pos`.
- The projectile reads veteran damage through `combat_node.has_method("get_effective_damage")` and `call(...)`.
- The projectile builds a `get_damage_info()` dictionary that `HitboxComponent.receive_damage_source` parses back out.
- Impact FX/sound live in `EntityFactory`, reached through `HealthComponent.damage_taken`, even though the factory is an assembler.
- Overlay-only hits set `overlay_hit`, skip the fallback, and the factory skips overlay victims, so **no** impact report plays — contrary to the `entity-factory` requirement that the cell pass plays the shot's single report.

`#264`, `#360`, `#455`, `#37`, and `#243` each had to touch two or three of Combat/Projectile/EntityFactory for one impact behavior.

## Goals / Non-Goals

**Goals:**

- One typed impact seam for "weapon W from shooter S lands on victim V or ground point P".
- One implementation of victim resolution, impact point, damage math, overlay pass, and impact report.
- Remove the dictionary/duck-typed seams.
- Keep the interface directly testable: stub entities, real `SpatialHash`/`GlobalRules` instances, no physics ticks.

**Non-Goals:**

- Targeting policy and acquisition (#520).
- Projectile flight: arming, flight model, steering, detonation trigger, max-range fizzle, friendly-fire victim classification.
- Removing the invisible/teleport-detonate projectile family.
- Changing data resources or packed scenes.

## Decisions

### D1: Static `WeaponDetonation` module with a typed request and result

`scripts/combat/WeaponDetonation.gd` (`class_name WeaponDetonation extends RefCounted`) exposes one static entry:

```gdscript
static func detonate(
    weapon: WeaponData,
    shooter: Node3D,
    effective_damage: int,
    target: Node3D,
    ground_pos: Vector3 = Vector3.INF,
    arrival_pos: Vector3 = Vector3.INF
) -> Impact
```

`Impact` is a small typed inner class: `position`, `victim`, `damage` (total applied across the entity and overlay passes), `entity_hit`, `overlay_hit`.

Why static: the module owns no state and no lifecycle; both callers already run inside the scene tree, and tests can call it directly. A new autoload or component node would add a registration/lifecycle surface with no benefit.

*Alternative rejected:* an autoload singleton. It would need `project.godot` registration and adds a lifetime the module does not have.

*Alternative rejected:* a Dictionary result. The whole point is to delete the untyped dictionary seam; the result is typed for the same reason.

### D2: Veteran damage is a typed integer passed at fire time

`CombatComponent` already owns `get_effective_damage(weapon)` (veteran combat multiplier). It passes that value to the module for hitscan, and to `ProjectileController.setup(...)` for projectiles. `setup` stores it as `_effective_damage` and resolves a negative default to `weapon.damage`, so the module always receives a valid non-negative base for tests and hand-built projectiles (all existing direct `setup()` calls omit the new argument).

Behavior note: the old projectile read the shooter's combat state at detonation time. The new code locks the boost at fire time. Flight is typically short and fire-time locking is the more defensible rule (the shot was fired with that damage); a long flight could in principle span a promotion, so this is recorded as an intentional behavior change rather than a pure refactor.

*Alternative rejected:* typed `CombatComponent` reference on the projectile. `CombatComponent` already references `ProjectileController` (scene preload + class), so the reverse reference is circular; the existing code deliberately used untyped access to avoid it.

### D3: The module owns impact-point resolution; flight stays in the projectile

The module resolves:

- entity target + structure (`StatsComponent.is_structure()` true and a `FoundationComponent`) → `FoundationComponent.nearest_world_point(shooter.global_position)`; a multi-cell non-structure stays a point target;
- non-structure entity target + finite arrival within `SNAP_RADIUS = 2.0` → victim centre;
- non-structure entity target + finite arrival beyond the radius → arrival position;
- non-structure entity target + no arrival (instant fire) → victim centre;
- ground shot → the ordered `ground_pos` (never the resolved occupant's position).

`ProjectileController` keeps the detonation trigger and its own `SNAP_DISTANCE = 1.0` proximity threshold; `SNAP_RADIUS` moves to the module with the impact-point choice. The module passes its resolved point to `HealthComponent.take_damage`, preserving `HealthComponent.last_impact_pos` for the existing impact-point tests. This preserves the current snap behavior and the "one blast, one point" rule: occupant and overlay passes read the same point.

### D4: Impact FX/sound move to `FxSystem.play_impact`

`FxSystem` gains:

```gdscript
signal impact_played(damage_type: String, position: Vector3)
func play_impact(damage_type: String, position: Vector3) -> void
```

It resolves the warhead from the active rules, plays `impact_fx` through `play` and `sound_impact` through `AudioManager.play_random`, and emits `impact_played` once for a resolved warhead. It emits even when the warhead has no media, preserving the old observability contract ("one report per detonation").

`EntityFactory` loses `_on_entity_damaged`, `play_impact_effects_at`, the `impact_played` signal, and the `HealthComponent.damage_taken` connection. It keeps death cleanup and the `health_zero` connection.

The module calls `FxSystem.play_impact` through the scene-tree root (`get_node_or_null("FxSystem")` + `call`) because `FxSystem` is an autoload script without a `class_name`; a direct autoload identifier in a static function is avoidable and the root lookup matches `GlobalRules.get_current()`'s existing pattern.

*Alternative rejected:* keep the damage-choke-point hook and suppress it for module-driven hits. That keeps the assembler in the impact path and needs a suppression flag — more state, same duplication.

### D5: `HealthComponent.take_damage` returns the applied amount

The old factory skipped a zero-applied hit (veteran armor rounding). The module must preserve that, but it computes pre-armor damage. `take_damage` now returns the applied integer (0 on invalid damage or an already-dead victim) so the module can decide whether to report. Existing callers ignore the return value.

### D6: Delete the dictionary/duck-typed seam

`ProjectileController.get_damage_info()`, `_payload`, `HitboxComponent.receive_damage_source()`, `received_damage`, and the `area_entered`/`body_entered` connections are removed. The projectile is the only producer of `get_damage_info`, and nothing consumes `received_damage`; the hitbox remains collision geometry with its `health_component` reference and size. The projectile's motion-segment cast already bypassed `area_entered` by design, so no behavior depends on the deleted path.

*Alternative rejected:* keep `receive_damage_source` but make the projectile pass typed values. It would still be a second damage path next to the module and would keep dead signal wiring.

### D7: Overlay-only hits now play the single impact report

The module reports when total applied damage (entity plus overlays) is greater than zero, or when it resolved no damageable entity or overlay at all. A mixed hit where the entity rounds to zero but an overlay takes damage therefore reports once; a hit that resolves a damageable entity but applies zero total damage stays silent. An overlay-only hit reports once, which is what the existing `entity-factory` requirement already claims. This is a deliberate behavior fix, not a regression; it is covered by the new overlay report scenario.

### D8: No new autoload, no scene changes

The module is a class, not a node. `project.godot` is unchanged. No `.tscn` connected the deleted signals or methods (verified by grep).

## Interface summary

```
WeaponDetonation.detonate(weapon, shooter, effective_damage, target, ground_pos, arrival_pos)
  -> Impact { position, victim, damage, entity_hit, overlay_hit }

CombatComponent._apply_hitscan_damage
  -> WeaponDetonation.detonate(weapon, shooter, get_effective_damage(weapon), target, _engagement_pos())

ProjectileController._detonate_on(victim)
  -> WeaponDetonation.detonate(_weapon, _shooter, _effective_damage, victim, _last_known_target_pos, global_position)
  -> impacted.emit(result.position)
```

## Regression tests that must fail on base

- `test/unit/test_weapon_detonation.gd` does not parse on base (`WeaponDetonation` does not exist), so the suite fails to load.
- Its first real assertion is the parity case: the same weapon/shooter/victim detonated as an instant shot and as a projectile arrival must yield the same victim damage and impact position.
- Overlay hits, structure footprint point, ground occupant resolution, effective-damage override, and the one-report count are asserted through the module result and `FxSystem.impact_played`.
- `test/unit/test_projectile_controller.gd` loses its `get_damage_info` payload tests; the remaining detonation test observes health through `_detonate_on`.

## Risks / Trade-offs

- [Fire-time veteran lock changes a corner case] → Negligible (rank cannot change mid-flight in practice); recorded in D2. If it ever matters, pass a typed damage provider instead of re-introducing a duck-typed read.
- [Moving FX out of the damage choke point could miss non-weapon warhead damage] → No other production caller applies warhead-typed damage (`TriggerEngine` uses `"trigger"`, `MovementController` uses crush with no type); the module is the only weapon-damage path.
- [Overlay-only report is a visible behavior change] → It matches the existing spec text and is the intended one-report rule; covered by a new scenario.
- [Root lookup for `FxSystem` is untyped] → Same pattern as `GlobalRules.get_current()`; the module's damage seam is typed, and the FX call is a one-way side effect.
- [Projectile flight tests depend on `_detonate_on`] → The method remains, only its body changes; flight tests (`test_projectile_flight`) stay focused on flight and should pass with the new body.

## Migration Plan

Single PR, behavior-preserving except the overlay report fix:

1. Add `WeaponDetonation` + its regression test (red on base).
2. Add `HealthComponent.take_damage` return value and `FxSystem.play_impact`; remove the factory FX hook.
3. Route `CombatComponent` hitscan and `ProjectileController` arrival through the module; delete the duplicated helpers and the dictionary seam.
4. Migrate test scaffolding; run lint/format/tabs/full suite.
5. Archive the OpenSpec change.

Rollback = revert the PR; no data migration, no scene changes. Commit each new script with its generated `.uid` file.

## Spec Impact

- New `weapon-detonation` capability.
- Modified `combat-firing` (dispatch routes through the module).
- Modified `projectile-runtime` (typed handoff, lifecycle wording, teleport-detonate wording).
- Removed `entity-factory` "Warhead impact FX".
- Added `fx-system` "Warhead impact report".
- `GLOSSARY.md`: the impact FX meaning changes to `FxSystem.play_impact` behind the detonation module (not the damage choke point); add `detonation module`.
- `openspec/specs/projectile-runtime/spec.md` Purpose is edited directly to name `WeaponDetonation` (OpenSpec deltas cannot change Purpose).
