## Context

ReSun has no pause at all: `get_tree().paused` is never set, there is no pause menu, and no input action is bound to it (`plans/5-2_game_management.md` marks pause as ❌). Gameplay runs in standalone map scenes that all inherit `scenes/maps/MapBase01.tscn`, whose `HUD` CanvasLayer (layer 256) hosts `Sidebar`, `DebugMenu`, and `FpsCounter`. `MainScene.tscn` has an empty `Gameplay` node and is not the playable surface yet (issue #262).

ESC is already a cancel key in three `_process` polling loops: `BuildingManager.gd:67` (build mode, via built-in `ui_cancel`), `Sidebar.gd:118` (debug-place mode), `MouseHandler.gd:140` (sell/repair mode). The game uses the default theme (no project Theme resource); plain `Button` controls match the rest of the HUD.

The test runner (`test/run_tests.gd`) calls test methods synchronously (`obj.call`), so tests cannot `await` frames; assertions must be synchronous.

## Goals / Non-Goals

**Goals:**
- ESC opens a pause menu; everything in the gameplay scene freezes; menu stays interactive; resume + quit-to-desktop buttons.
- First ESC cancels an active cancel-mode, second ESC pauses (matches TS/RA convention).
- Works in every current map scene from one insertion point.

**Non-Goals:**
- Pause menu in `MainScene` (its `Gameplay` node is empty until #262).
- Save/load, settings screen, keyboard navigation, muting audio while paused.
- Pausing a single subtree instead of the whole tree.

## Decisions

**D1 — Global `get_tree().paused`, not per-scene.** Setting the tree paused freezes every default (PAUSABLE) node: movement, combat, production, economy, growth, sidebar, camera. This directly satisfies "everything paused" with zero per-system changes. Pause is global, not scoped to the gameplay subtree, because the menu lives inside that subtree and the canonical Redot pattern is tree-wide.
Alternative rejected: setting `process_mode = PAUSABLE` on a subtree root — more invasive, easy to miss a system.

**D2 — PauseMenu root uses `process_mode = PROCESS_MODE_ALWAYS`.** The canonical Redot pause pattern is a non-pausable menu root so its Buttons stay interactive while the tree is paused. The official tutorial uses `WHEN_PAUSED`, but that only works because its pause trigger lives *outside* the menu; here ESC is handled **on the menu** and must fire both unpaused (to open) and paused (to resume), so `ALWAYS` is required — `WHEN_PAUSED` would break ESC-to-open. Set in the `.tscn` node so it holds before `_ready`.

**D3 — ESC handled in `_unhandled_input` (event-driven), existing cancels stay `_process`-polling.** `PauseMenu._unhandled_input` reacts to `event.is_action_pressed("pause")`. The three existing ESC consumers poll in `_process` and are themselves paused the moment the menu opens, so the only conflict is the press frame. A guard (`_esc_busy()`) makes the pause handler no-op when build/sell/repair/debug-place mode is active, so the existing polled cancel wins. Result: first ESC cancels the mode, second opens the menu.
Alternatives rejected: converting the three polling consumers to event handlers (larger diff, churn); unbinding their ESC usage (removes existing functionality).

**D4 — New `pause` input action in `project.godot` bound to KEY_ESCAPE (physical 4194305).** Matches the codebase convention of explicit InputMap actions (`tab_*`, `toggle_debug`, `asset_preview_*`); rebindable later.
Alternatives rejected: raw `KEY_ESCAPE` check (skips convention, not rebindable); reusing built-in `ui_cancel` (semantically muddles pause=cancel and couples to build-mode cancel).

**D5 — Plain `Button` controls** in a `CenterContainer/VBoxContainer`, over a dim `ColorRect` (mouse_filter STOP). Consistent with the default-theme HUD; standard `pressed` signals; no custom hit-testing. The existing `MainMenuItem01` glow-text style was deliberately not reused per explicit choice.

**D6 — Guard reads state through existing public APIs.** `BuildingManager.is_build_mode` is already public; `Sidebar.is_sell_mode()`/`is_repair_mode()` exist; `_debug_place_mode` is private, so a one-line public getter `is_debug_place_mode()` is added. No new coupling beyond reading these.

**D7 — Synchronous tests using `Node.can_process()`.** Because the runner cannot `await`, tests assert pause state via `can_process()` (reflects pause + process_mode synchronously) instead of counting frames. Every test that pauses must unpause before returning or the rest of the suite corrupts.

**D8 — Cursor forced to DEFAULT on pause.** `MouseHandler` is the sole cursor owner (`_apply_cursor`), driven from `_process`; while paused it stops resolving, so whatever cursor was showing would stay frozen behind the menu. On `NOTIFICATION_PAUSED` (same handler as the drag reset), `_apply_cursor(DEFAULT)` clears the custom cursor once; nothing overrides it while paused, and the next `_process` frame after resume re-resolves it. No coupling from PauseMenu into cursor code.

**D9 — Unpause input debounce.** `MouseHandler` polls `Input.is_action_just_released("select_entity")` in `_process`, and the Input singleton records the resume button's left-click release even though GUI consumed it. On the unpause frame that release would be read as a gameplay click and issue a move order to the selection. `NOTIFICATION_UNPAUSED` arms a 2-frame `_skip_input_frames` debounce (same pattern as `BuildingManager._skip_input_frames`) that short-circuits `_process` before any action polling — swallowing the release (frame N, where the action flag is true) and one margin frame. ESC-to-resume arms it harmlessly (ESC is not a `select_entity` event).
Alternatives rejected: `get_viewport().set_input_as_handled()` in the resume handler — the Input singleton's `is_action_just_*` state ignores event-accept; press/release pairing in MouseHandler — churns core click semantics.

## Risks / Trade-offs

- **Leaked paused state across tests** → each pause test resets `get_tree().paused = false` and hides the menu on every code path before returning.
- **Audio pauses with the game** — default `AudioStreamPlayer`s set `stream_paused = true` on tree pause (gated by `process_mode`), so music/SFX freeze during pause. Whether music continues is a deferred product decision (later set `process_mode = ALWAYS` on music players when the music system lands, #255). Both behaviors are acceptable; no change now.
- **Menu over an in-progress box-select / drag** — the mouse-release event is swallowed while paused (input gated by `process_mode`), risking a stuck drag. `MouseHandler` resets its drag state on `NOTIFICATION_PAUSED`.
- **`pause` action and built-in `ui_cancel` both fire on ESC** → only `BuildingManager` consumes `ui_cancel`, and only in build mode, which the guard already covers.
