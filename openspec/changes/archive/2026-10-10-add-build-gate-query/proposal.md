# Proposal

## Why

"Can the local player build this?" is answered four different ways and they can each be
right by their own rule and wrong together. `PrerequisiteSystem.can_build` collapses five
gates into a `bool` and discards the reason; `CreditCounter` derives a third notion from
`data.buildable` alone (player-agnostic); `ProductionManager.has_factory_for` scans the
global `factories` group with no `player_id`; and `EconomyManager.can_afford` has no
callers, so affordability never reaches the UI. A cameo's visibility, the greyed state,
the credit warning, and the production gate can therefore disagree.

## What Changes

- Deepen `PrerequisiteSystem` into one build-gate query: `evaluate_build(player_id, data)`
  returning `enabled`, `reason`, `cost`, and the raw `owned_factory` fact. `can_build` keeps
  its signature and delegates, so no caller or scene changes. **BREAKING** (behavioral): the
  delegate now also rejects types outside the build menu and returns `owned_factory` computed
  before the cheat bypass — see the `tech-level` and new `build-gate` specs.
- Fold the `EntityData.buildable` menu flag into the query as a gate (`enabled` is false,
  reason `not_buildable`), so callers stop pairing `buildable` with `can_build`. This widens
  the `can_build` contract that `production-manager` and `debug-menu` already rely on.
- Surface a reason for every rejection: `not_buildable`, `never` (`tech_level == -1`),
  `tech_level`, `build_limit`, `prerequisite` (OR), `prerequisite_necessary` (AND),
  `no_factory`. The `no_prereqs` cheat still returns `enabled` while leaving `owned_factory`
  truthful, so the direct-deploy fallback keeps a fact it can trust.
- Make factory ownership player-scoped in one place (the owned-buildings registry), and
  delete `ProductionManager.has_factory_for`.
- Point the credit warning at the same set the Sidebar shows: cheapest item the local player
  can actually build, not the cheapest item in the whole catalog. `EconomyManager.can_afford`
  gains its first caller.
- Affordability stays a warning only. It never gates `start_production`; production remains
  funded as it builds (stalls when credits run dry, resumes as they flow).
- Remove the dead `build_limit` greyed branch in `Sidebar._create_cameo` — the gate already
  filters capped items out before a cameo is built.
- Record `build gate` as a canonical term in `GLOSSARY.md`.

## Capabilities

### New Capabilities
- `build-gate`: the single per-player buildability decision — gate order, the reason for each
  rejection, the raw `owned_factory` fact, and the rule that affordability is never a gate.

### Modified Capabilities
- `credit-ui`: the "cheapest buildable item" that drives the insufficient-funds color becomes
  the cheapest item the local player can build (player-scoped gate), and the `no_cost` cheat
  disables the warning.
- `tech-level`: `can_build` now also rejects an entity whose `buildable` menu flag is false,
  and delegates to the shared `evaluate_build` query.
- `debug-menu`: the direct-deploy fallback fires when the player owns no producer for the
  queue type (player-scoped ownership) rather than when no matching factory exists anywhere
  on the map.
- `sidebar-build-order`: the `tech_level = -1` parenthetical no longer calls it "always
  available" (it contradicts `GLOSSARY.md` and `tech-level`); `-1` means never buildable and
  is filtered by the gate before sorting, so the ordering is retained only for determinism.

## Impact

- Code: `scripts/production/PrerequisiteSystem.gd`, `scripts/production/ProductionManager.gd`,
  `scripts/ui/Sidebar.gd`, `scripts/ui/CreditCounter.gd`, `scripts/economy/EconomyManager.gd`.
- Tests: `test/unit/test_prerequisite_system.gd`, `test/unit/test_tech_level_gate.gd`,
  `test/unit/test_credit_counter.gd`, `test/unit/test_economy_manager.gd`,
  `test/unit/test_cameo_click_policy.gd`, `test/unit/test_sidebar_build_order.gd`.
- No scene or `.tscn` changes; no autoload changes. `can_build`'s signature is preserved.
- Behavioral edge: `production-manager`'s "Start production" requirement says only that
  prerequisites are met via `PrerequisiteSystem`; after this change it also refuses non-menu
  types. The requirement is not falsified, but it understates the gate.
- Cross-references: #473 (relocates `PrerequisiteSystem`/`ProductionManager` — this change is
  independent of, and must not pre-empt, that move) and #495 (map-loaded buildings currently
  skip `register_building`, which leaves the player-scoped ownership fact empty on loaded maps —
  a pre-req for a meaningful affordability warning on those maps).
