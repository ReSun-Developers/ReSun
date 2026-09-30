# Unified Engine Architecture — Target for a 4-Title Data-Driven RTS

How ReSun becomes one engine that runs **Tiberian Sun**, **Firestorm**,
**Red Alert 2**, and **Yuri's Revenge** as data packages, rendered isometric-3D.

Status note: the codebase already implements the bones of this model (`GameContext`,
`GameDefinition`, data-set layering). The gap is a set of **generic subsystems** plus three
new **game packages**. See `docs/capability-matrix.md` for the row-by-row status.

---

## 1. Layering model

```
                ┌──────────────────────────────────────────────┐
                │  Engine (scripts/, scenes/) — title-agnostic │
                │  grid · pathfinding · combat core · UI frame │
                └──────────────────────────────────────────────┘
                                    ▲ reads
                ┌──────────────────────────────────────────────┐
                │  Generic subsystems (new)                    │
                │  superweapons · control links · garrison ·   │
                │  status/aura · mission runtime · skirmish AI │
                └──────────────────────────────────────────────┘
                                    ▲ configured by
   ┌──────────────┬──────────────┬──────────────┬──────────────┐
   │ games/ts     │ games/fs     │ games/ra2    │ games/yr     │
   │ (exists)     │ (new)        │ (new)        │ (new)        │
   └──────────────┴──────────────┴──────────────┴──────────────┘
```

Each game package = one `GameDefinition` (`games/<id>/game.tres`) that lists:
- its `GlobalRules` resource,
- ordered **data-set roots** for entities/art/audio/terrain/factions/theaters,
- maps directory.

Layering is **last-wins**; borrowing another title's root is allowed (e.g. `fs` lists the `ts`
root first, then its own delta overrides). Same-id claims by two non-borrowing games fail
validation (`GameContext.validate_id_collisions`).

**Expansion strategy:** FS is `ts` + delta. RA2 is its own base. YR is `ra2` + delta.
Do **not** merge all four into one giant ruleset — that destroys the per-title balance and
the ability to run one title without the others' units.

## 2. What stays generic vs per-title

**Generic engine (must never contain per-title names):**
- grid/occupancy/pathfinding/locomotors, damage formula shape (`Warhead.Verses[armor]`),
  projectiles, health/armor/veterancy math, power grid, vision, production/queues/prereqs,
  transport/dock/deploy primitives, the UI framework, the data loader, audio event hooks.

**Per-title data (lives only under `games/<id>/`):**
- armor class list and order, resource type table, warhead/weapon/projectile rosters,
  unit/building/infantry/aircraft/naval stats and art, faction/side/country rosters and
  bonuses, superweapon effect tables, prerequisite trees, theater/tileset content, EVA/voice/
  music content, campaign missions and AI team definitions, and every tuned numeric constant.

**New generic subsystems are the only new engine code required by the expansion.** They are
title-agnostic mechanisms whose *contents* are data. The critical ones:

| New subsystem | Why (which titles need it) | Seeds already in repo |
|---|---|---|
| Superweapon / support-power framework | all four | `PowerGrid`, `ProductionManager`, `RadarSystem` |
| Control-link (mind control) manager | RA2 (single), YR (multi/permanent) | none |
| Garrison / occupancy subsystem | RA2 (civ), YR (bunkers, fire-from-transport, bio reactor) | `TransportComponent`, `DockHost/Client` |
| Weapon state machine (staged/gattling, modes) | YR (gattling), RA2 (IFV modes) | `CombatComponent` weapon loop |
| Ammo / reload + pad rearm | TS/FS/RA2/YR (aircraft) | `WeaponData.ammo` schema-only |
| Auto-engage / guard / threat targeting | all four | `CombatComponent.threat_posed` |
| Attack-move / patrol / stances | all four | `OrderSystem` |
| Mission runtime (trigger/event/action, objectives, teams) | all four | `MapConfig`, `PlayerManager` |
| Skirmish AI (base build, attack teams, difficulty) | all four | none |
| Status-effect / aura framework | TS (EMP/gas), YR (berserk/poison/mutation) | none |
| Naval + aerospace movement & content | all four (RA2/YR heavy) | `Ship` locomotor stub, water land type |
| Save/load of live game state | all four | editor JSON only |
| Side → country → bonus registry | RA2/YR (countries), TS/FS (sides/mutants) | `FactionCatalog`, `Houses` |

Persistent-duration effects (mind control, EMP, berserk, iron curtain, force shield, mutate,
buffs) must be modeled as serializable, tickable effects attached to a generic
**status/effect registry** so they survive save/load and replays.

## 3. Data schema extensions implied by the four titles

These fields/schema shapes are needed regardless of title; today many are schema stubs with no
consumer (see audit). Not an implementation plan — a specification target.

- **Armor:** variable-length, ordered, named armor classes; `Verses` keyed by class id.
  (TS=5, RA2/YR=11.)
- **Projectiles:** trajectory family enum + per-family params (`arc`, `gravity`, `scatter`,
  `ROT`, `homing`, `inviso`, `subject_to_cliffs`), splash (`cell_spread`, `percent_at_max`).
- **Weapons:** ammo/reload, deploy-to-fire, passenger-driven mode table, staged/gattling
  parameters (`weapon_stages`, `stage_thresholds`, `rate_up`, `rate_down`), prism support.
- **Status/effects:** effect id, duration (frames), stack policy, immunity flags, per-tick
  action (damage/heal/convert/control/disable/allegiance), aura radius.
- **Superweapon:** type (damage/capture/convert/invulnerable/reveal/paradrop/siphon/blackout),
  charge time, target mode (area/line/none/unit), global reveal + shared timer, host building.
- **Control link:** firer, target, capacity, permanent flag, release conditions
  (death/power-loss/overflow), serialization.
- **Garrison/occupancy:** occupant slots, allowed classes (infantry/vehicle), stat bonuses,
  fire-from-inside, power hook (Bio Reactor), enter/exit orders.
- **House/country/side:** N sides; side→country mapping; per-country unit gates and
  `XxxMult` bonuses; per-country art/palette/voice binding.
- **Economy hooks:** refund/recycle, per-tick siphon, cost/build-time/income multipliers,
  discount auras, storage-cap policy (capped for TS, uncapped for RA2).
- **Resource:** generic resource type table (Tiberium variants, ore, gems) with growth/spread
  and optional lifeform/hazard flags.
- **Mission/scenario:** trigger (events→conditions→actions), objectives, waypoints,
  taskforce/teamtype/scripttype, reinforcements, cinematic camera, per-map roster gate
  (e.g. FS `Firestorm=yes`).
- **Theater:** tileset, palette, hazards, gravity/air rules, per-map override.
- **Game mode:** skirmish modes, team setups, optional co-op flag, map metadata.

## 4. Isometric-3D rendering target

The project is already fully 3D with an isometric **view**: the gameplay camera is Y=45°-yawed
orthographic (GLOSSARY `isometric view`). "Isometric 3D remake" therefore means:

- Keep the fixed 45° orthographic gameplay camera (the TS/RA2 look). No free rotation.
- Original 2D sprites/voxels are replaced by authored 3D models (already the pattern:
  `BatchLoader` / `ArtComponent` / `UnitMeshRenderer`, MultiMesh per region).
- Terrain is a true heightfield (already) with theater-driven surface art.
- The math consequence is documented: picking/alignment must rotate by ±45° (`MouseHandler`,
  `Minimap`). Anything world-axis-aligned draws rotated on screen.

Open decision (not resolved here): true 2:1 dimetric vs the current camera ratio. Record in
`GLOSSARY.md` under **Undecided** before authoring models.

## 5. Migration path from the current engine

1. **Lock the generic contracts** (this is spec work): armor list, projectiles, status effects,
   superweapon registry, house/country model, mission runtime. Each becomes its own spec.
2. **Fill the missing generic subsystems** in the order that unblocks the existing milestone
   (auto-engage/guard, attack-move, mission runtime) and then the multi-title needs.
3. **Author `games/fs`** as a delta over `ts`; validate the delta model end-to-end.
4. **Author `games/ra2`** as an independent base; this is the stress test that proves the
   engine has no TS-specific assumptions (11 armor classes, ore/gems, no silos, countries,
   naval/air).
5. **Author `games/yr`** as a delta over `ra2`; this forces the control-link, garrison, staged
   weapon, and status-effect subsystems to be real.
6. **Reconcile docs** as each subsystem lands (OpenSpec change → archive → spec sync).

## 6. Non-goals / deferred

- Netcode/lobby/replays — largest unknown; defer behind single-player completeness.
- Free camera rotation; the target is fixed isometric.
- FMV reconstruction; cinematic *camera scripting* is in scope, video playback is not.
- Random map generation — none of the four shipped one.
