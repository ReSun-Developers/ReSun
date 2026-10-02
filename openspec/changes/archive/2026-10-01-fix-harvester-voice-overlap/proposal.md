# Proposal

## Why

Ordering a harvester to harvest tiberium plays two voice lines back-to-back: the
unit's `select` line (from the preceding selection click) and its order
acknowledgment. `AudioManager.play_voice` never cancels or defers a line, so the
two clips overlap. Separately, the order-acknowledgment mapping collapses every
non-move cursor onto the `attack` event, so a harvest order barks with a combat
voice — confirmed by the original engine's rules, where non-attack player orders
acknowledge with `VoiceMove` and only `MISSION_ATTACK` uses `VoiceAttack`.

## What Changes

- **Voice event is owned by the order-producing component.** `OrderResult` gains a
  `voice_event` field. Components set the event for the order they produce instead
  of `MouseHandler` deriving it from the cursor. `MOVE`/`HARVEST`/`ENTER`/`DEPLOY`
  use `move`; `CombatComponent` attack orders use `attack`; sell/repair produce no
  voice event.
- **Harvest and other non-attack orders acknowledge with the `move` voice**,
  matching the original engine (`Player_Assign_Mission`: attack → `VoiceAttack`,
  everything else → `VoiceMove`).
- **Attack voice is owned by `CombatComponent`**, set on the player-issued attack
  orders (including force-fire), so auto-acquired engagements stay silent.
- **A command acknowledgment never overlaps the same speaker's previous line.**
  `AudioManager.play_voice` defers a `select` line briefly; if an order
  acknowledgment for the same voice set arrives within the window, the deferred
  select is discarded, and if it arrives after the window the already-playing
  select is stopped before the acknowledgment starts. `die` lines are never
  deferred, cancelled, or stopped.
- **The confirmation speaker is chosen among units that can voice the event.**
  The NW-most selected local unit whose voice set has a variant for the event
  speaks, so a mixed selection never lands on a silent speaker.
- **Deploy/stop hotkeys acknowledge too.** Ctrl+D and Ctrl+S play the move voice
  like their order-funnel equivalents.
- **BREAKING (internal API):** `MouseHandler.voice_event_for_cursor` is removed;
  the order-voice event now travels on `OrderResult.voice_event`. `OrderResult.new`
  call sites that need a non-default event set the field.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `audio-system`: the event-driven voice playback requirement changes — the voice
  event is supplied by the producing component via `OrderResult` rather than mapped
  from the cursor, harvest/dock/deploy acknowledge with the move voice, and a new
  requirement governs acknowledgment overlap (a deferred select yields to a
  following acknowledgment; `die` is exempt).
- `order-system`: the `OrderResult` data class requirement gains the `voice_event`
  field, and the order-confirmation-voices requirement changes to read the event
  from `OrderResult` and drop the ATTACK/HARVEST/ENTER/DEPLOY → attack mapping.

## Impact

- `scripts/orders/OrderResult.gd` — new `voice_event` field (defaults to `move`).
- `scripts/components/CombatComponent.gd` — declares `attack` on its ATTACK orders.
- `scripts/orders/SellOrderGenerator.gd`, `RepairOrderGenerator.gd` — declare an
  empty voice event (no unit bark when selling/repairing).
- `scripts/hud/MouseHandler.gd` — `play_order_voices` reads `orders[0].voice_event`;
  `voice_event_for_cursor` removed.
- `scripts/core/AudioManager.gd` — deferred-select acknowledgment handling.
- `games/ts/audio/*.tres` — no new content; harvest reuses the existing `move` set.
- Tests: `test/integration/test_audio_voice_routing.gd` (the select-stacking test
  moves to `die`), plus new order-event and deferred-select cases.
- Specs: `openspec/specs/audio-system/spec.md`, `openspec/specs/order-system/spec.md`.
