# Proposal

## Why

Order intake input assembly — the `(target, target_cell, target_pos, modifiers)` quadruple fed to `OrderSystem.resolve()` — is hand-built independently at four sites (hover cursor, click entity path, click ground path, minimap click), each re-implementing cell/position derivation and mutating `MOD_TARGET_LEVEL` ad hoc. #499 unified order *output* (`OrderResolution` decides cursor and orders together so they cannot drift); the *input* side can still drift the same way, and nothing stops the next intake site (touch orders, controller, replay) from building a malformed tuple.

## What Changes

- New `OrderProbe` data class: the typed input to order intake (`target`, `target_cell`, `target_pos`, `modifiers`), with three factories encoding the existing asymmetries as named policy:
  - `from_entity(target, shift)` — cell/pos from entity position, no target level
  - `from_ground(ground_pos, level, shift)` — ground/deck position, `MOD_TARGET_LEVEL` always set (0 for ground)
  - `from_cell(cell, target, world_pos, level, shift)` — minimap cell lookup, `MOD_TARGET_LEVEL` always set
- `OrderSystem.resolve_probe(probe)` — thin entry that splats a probe into the existing tuple `resolve()` (signature unchanged; spec-mandated `get_cursor`/`get_orders` projections untouched).
- `MouseHandler._probe_pointer(mouse_pos)` — one shared 2-pass raycast (layer 16 → 17) replacing the duplicated probe logic in hover preview and left-click. Policy stays at call sites: fog gate + miss-count lag remain in `_handle_hover_preview`; select-vs-order ordering remains in `_handle_left_click_normal`.
- All four assembly sites route through `OrderProbe` factories: hover cursor (`_update_cursor`), click entity (`_try_execute_orders`), click ground (move-order tail of `_handle_left_click_normal`), minimap (`Minimap._handle_click`).
- `MOD_TARGET_LEVEL` is no longer hand-mutated at call sites — only `from_ground`/`from_cell` set it.
- GLOSSARY.md: add `OrderProbe` entry (input counterpart of the existing `OrderResolution`).

Explicitly out of scope (per #508):

- No hover-resolution cache (invalidation risk reintroduces the #499 drift class; hover resolves once per frame, not hot).
- No removal of `get_cursor` (zero production callers but spec-mandated — separate change + spec delta).
- No threading `MOD_TARGET_LEVEL` into the hover path (archived force-fire design rejection).
- Right-click cancel path, hover lag/miss-count semantics, and pre-intake mode gates untouched.

## Capabilities

### New Capabilities

(none — pure refactor)

### Modified Capabilities

(none — the spec never constrains how callers build the input tuple; `resolve()`/`get_cursor()`/`get_orders()` behavior is unchanged, so no requirement changes. Change declares `skip_specs: true`.)

## Impact

- **Scripts:** `scripts/orders/OrderProbe.gd` (new), `scripts/core/OrderSystem.gd` (add `resolve_probe`), `scripts/hud/MouseHandler.gd` (probe extraction + 3 sites rewired), `scripts/ui/Minimap.gd` (1 site rewired)
- **Tests:** `test_mouse_handler_hover`, `test_force_fire_ground`, `test_order_bounds`, `test_order_resolver` must pass unchanged; new small test for `OrderProbe` factory modifier policy
- **Docs:** `GLOSSARY.md` gains an `OrderProbe` entry
- **Scenes:** no `.tscn` changes (scripts only, autoload surface grows by one method)
- **Backward compatibility:** `resolve(target, cell, pos, mods)` remains the spec-facing interface; packed scenes unaffected