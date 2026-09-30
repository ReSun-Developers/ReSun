## Context

The harvest loop stores a pod's amount in `HealthComponent` and treats full health as one bale: `ResourceComponent.get_amount()` returns `health_ratio`, `get_max_amount()` returns `1.0`, and `collect(bales)` converts bales to health with `bales * max_health`. Three callers bake in the 1 cell = 1 bale assumption: `ResourceGrowthSystem._spawn_at_cell` (seeds health from a bale figure), `ResourcePainter` (adds/removes bales as health), and the harvester full check (`storage` compared against summed bales).

Separately, the dock host runs a stale timer that is reset on arrival and at unload start but never during draining, while unload is far longer than the timeout.

## Goals / Non-Goals

**Goals:**
- One ripe tiberium cell is worth 11 bales; a 28-bale load draws ~2.5 cells.
- A docked harvester always deposits its full accepted cargo before undocking.
- Fill/unload cadences match the reference order of magnitude.

**Non-Goals:**
- A discrete per-stage overlay model with 12 real art stages (deferred).
- Vein/weed economy changes beyond the shared conversion.
- AI harvester/refinery ratio, save-format changes, or multiplayer.

## Decisions

### D1. `bales_per_cell` lives on `ResourceType`
Yield is a property of the resource type, not the instance. Add `@export var bales_per_cell: float = 1.0`, set to 11 on the tiberium variants. The `1.0` default keeps isolated `ResourceComponent` unit tests and other resources (veins) unchanged.

- Alternative: on `EntityData` (per-pod) - rejected, yield is type-level.
- Alternative: on `GlobalRules` - rejected, resources can differ.

### D2. Bales are authoritative; health is a mirror
`ResourceComponent` keeps the authoritative amount as a float `_bales`, lazily initialized from the backing `HealthComponent`. `collect()` decrements `_bales` and mirrors it onto health (`_apply_bales_to_health`); growth/spread call `add_bales()`. Health stays the visual/death driver (3-stage thresholds, `health_zero` on depletion) and the map/save format is unchanged (`strength`/`spawn_health` are health values, parsed back into bales on first use).

- Why not derive bales from an integer `HealthComponent` ratio: 11 bales cannot map exactly onto 300 health, so per-bail harvests drift (a ripe cell yielded 10.7-11.5 bales depending on harvest chunk size). A bale store makes a ripe cell yield exactly 11.
- Simplification: 12 discrete growth stages collapse to a continuous bale float; upgrade to an integer per-stage store if stage-accurate visuals or AI are later required.

### D3. Centralize the conversion on `ResourceComponent`
`get_bale_capacity()`, `_health_to_bales()`, `_bales_to_health()`, `get_amount()`, `collect()`, and `add_bales()` live on `ResourceComponent`. `ResourceGrowthSystem` and `ResourcePainter` call `add_bales()` / `collect()` instead of writing `HealthComponent` directly, so the scale lives in one place.

### D4. Refresh the stale timer while draining
`DockUnloadComponent._process` calls `dock.reset_stale_timer()` each frame while it is actively draining. The timeout keeps guarding the approach/rotation phase (a docker that arrives and stalls is still evicted). `begin_unload()` keeps its existing reset.

- Alternative: host queries the client's UNLOADING state - rejected, couples host to client.
- Alternative: delete `stale_timeout` - rejected, loses the stuck-docker guard.

### D5. Pacing defaults
`games/ts/global_rules.tres` `harvester_fill_rate` 0.5 -> 1.667; `DockUnloadComponent` `unload_rate` 0.5 -> 2.0. Both are data/default changes, not new config.

The project runs TS timings on a **2x time base** (matching the existing `build_speed = 0.4`, which is half TS's `BuildSpeed = .8`): TS's authored 15 ticks/second becomes 30 ticks/second. TS authors fill at 18 ticks/bail and unload at ~15 ticks/bail (HarvesterDumpRate = .016 min), so fill = 30/18 ~= 1.67 bales/s and unload = 30/15 = 2.0 bales/s. ReSun's own frame rate (60) is irrelevant because both rates are per-second and `delta`-scaled.

## Risks / Trade-offs

- [Rounding across many small collects] -> bales stay authoritative (health is a rounded mirror) plus a test that harvesting a ripe cell one bail at a time yields exactly 11.
- [Existing tests encode 1 cell = 1 bale] -> update only assertions that codified the old requirement; default `bales_per_cell = 1.0` keeps bare-component tests green and documents which case changed.
- [Regrowth interferes with yield tests] -> tests must not tick `ResourceGrowthSystem`.
- [Longer unload holds the dock] -> acceptable; the stale fix makes it correct, and the queue/vacate flow already serializes dockers.
- [Partial-cell spread now starts very low] -> intended; cells regrow over time.

## Migration Plan

Behavior/data change only; no save migration. Land as ordered commits:

1. `bales_per_cell` + `ResourceComponent` conversions.
2. Growth/painter conversion call sites.
3. Stale-timer refresh during unload.
4. Pacing data/defaults.
5. Tests + spec sync.

Rollback: revert the branch; the `1.0` default restores prior behavior for unconfigured resources.

## Open Questions

- Whether to adopt a discrete 12-stage store later for stage-accurate art/AI (deferred).
- Whether blue/red tiberium keep 11 bales/cell (assumed yes; value differs, not yield).
