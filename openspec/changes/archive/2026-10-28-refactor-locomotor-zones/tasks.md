# Tasks

## 1. Regression tests (write first)

- [x] 1.1 Replace the `EntityData.is_movement_zone_compatible` assertions in `test/unit/test_locomotor_registry.gd` with resource assertions covering the nine TS zone lists; run `flock /tmp/opencode/redot.lock redot --headless -s test/run_tests.gd` and confirm the tests fail on base because `Locomotor.zones` does not exist
- [x] 1.2 Add entity-validation tests: a custom locomotor whose zones differ from the old static table (set via `lm.set("zones", ...)` so it runs on base), a second locomotor that accepts a zone the unit's locomotor does not, real TS rules accepting a valid zone and rejecting a contradictory zone with a non-empty zone list, an empty-locomotor rejection, an empty-registry unknown-id run, and a null-rules run that skips compatibility; confirm the data-driven case fails on base because the static table rejects the pair
- [x] 1.3 Update the existing contradiction test to register a `Track` locomotor with its real zone list via `lm.set("zones", ...)`, assert the list is non-empty, and confirm it rejects `Subterannean`; the test runs on base because `set()` is a no-op there

## 2. Locomotor data

- [x] 2.1 Add `zones: PackedStringArray = []` to `scripts/data/Locomotor.gd` and verify a default `Locomotor` loads with an empty list
- [x] 2.2 Populate `zones` on the nine `games/ts/locomotors/*.tres` from the `LOCOMOTOR_ZONES` table and verify `test_ts_locomotor_zones` passes for all nine

## 3. Validation

- [x] 3.1 Replace the static-table branch in `EntityData.validate()` with `GlobalRules.get_current().get_locomotor(locomotor)` membership, preserving the unknown-locomotor error and the pre-GlobalRules skip, and correct the stale `movement_zone` doc comment; verify all `test_locomotor_registry.gd` tests pass
- [x] 3.2 Delete `LOCOMOTOR_ZONES` and `is_movement_zone_compatible()`; verify `grep -rn "LOCOMOTOR_ZONES\|is_movement_zone_compatible" scripts test` returns no hits and the full suite passes

## 4. Documentation and gates

- [x] 4.1 Update the `movement zone` row in `GLOSSARY.md` to reference `Locomotor.zones` instead of `LOCOMOTOR_ZONES`
- [x] 4.2 Run `gdlint scripts/**/*.gd test/**/*.gd`, `gdformat --check scripts/**/*.gd test/**/*.gd`, `grep -P '\t' scripts/**/*.gd test/**/*.gd`, and the full headless suite; all pass
