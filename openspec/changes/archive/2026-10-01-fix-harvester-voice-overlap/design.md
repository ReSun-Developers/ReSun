# Design

## Context

See `proposal.md - Why` for motivation. Relevant current state:

- `MouseHandler.play_order_voices` derives the voice event from `orders[0].cursor`
  via `voice_event_for_cursor`, which maps `ATTACK`/`HARVEST`/`ENTER`/`DEPLOY` all
  to `attack`. It then picks the NW-most selected local unit and calls
  `AudioManager.play_voice(voice_data.id, event)` once.
- `SelectionManager.select_entity` / `play_select_voice_for_entities` call
  `play_voice(..., EVENT_SELECT)` at selection time.
- `AudioManager.play_voice(voice_id, event_name)` chooses a random variant and
  delegates to `play_sound`, which creates a tracked player and never cancels a
  line already playing. The choke point knows only the voice-set id and event —
  not the unit.
- `CombatComponent.set_target` is shared by player orders (`_attack`) and
  `GuardComponent` auto-acquire.

Reference-engine research (OpenTS C++ reconstruction, OpenRA `bleed`):
- OpenTS `TechnoClass::Player_Assign_Mission` uses one rule: `MISSION_ATTACK` →
  `VoiceAttack`, everything else (move, harvest, dock, unload, deploy) →
  `VoiceMove`; only player input paths call it, so auto-orders are silent.
- OpenRA gives the phrase to the action-owning trait (`IOrderVoice`), emits once
  from the order UI, and places the attack phrase on `AttackBase` for
  attack/force-attack orders.
- Neither engine cancels a line: OpenTS lets voices overlap (bounded by a global
  channel budget); OpenRA drops the second line while the first plays.

## Goals / Non-Goals

**Goals:**

- One coherent voice line for a select-then-order interaction.
- The order's voice event is chosen by the component that produced the order.
- Harvester (and other non-attack) orders acknowledge with the `move` voice.
- Attack voices issued only for player-issued attack orders.

**Non-Goals:**

- Audible crossfade/ducking. Rejected for v1 in favour of deferral (see
  Decisions); revisit if playtesting wants it.
- A general voice-channel/ducking system (deferred GH #242 work).
- Per-unit (rather than per-voice-set) suppression.
- New audio content; harvest reuses the existing `move` set.

## Decisions

### D1: Voice event travels on `OrderResult`, chosen by the producing component

Add `voice_event: String` to `OrderResult`, defaulting to `VoiceData.EVENT_MOVE`.
`CombatComponent` sets `EVENT_ATTACK` on its ATTACK orders; `SellOrderGenerator`
and `RepairOrderGenerator` set `""`. `MouseHandler.play_order_voices` reads
`orders[0].voice_event`; `voice_event_for_cursor` is deleted.

*Why:* matches both reference engines (phrase owned by the action, emission
centralised in the order layer) and removes the cursor→event table that forced
harvest/dock/deploy onto the attack voice. Defaulting to `move` is exactly
OpenTS's `mission == MISSION_ATTACK ? Attack : Move` rule, so the whole move
family needs no per-generator edits.

*Alternatives:* keep the cursor map and only special-case `HARVEST` (rejected:
leaves attack/dock/deploy conflated and keeps ownership in the wrong layer);
set `voice_event` explicitly in every generator (rejected: more edits, and
`move` is a genuine invariant for non-attack orders).

### D2: Attack voice hooks the player-order path, not `set_target`

`CombatComponent` sets `voice_event = EVENT_ATTACK` in `get_order_for_target`
for all three ATTACK orders (force-fire ground, force-fire entity, normal enemy).
No voice is emitted from `set_target`/`_begin_engagement`.

*Why:* `set_target` is also called by `GuardComponent` auto-acquire; a hook there
would make every auto-engagement bark. OpenTS only voices from the player-input
path, and OpenRA's attack phrase is returned for the attack order, not on fire.

### D3: Acknowledgment overlap resolved by deferring `select` and stopping an in-flight one

`AudioManager.play_voice` defers `select` events for `SELECT_DEBOUNCE_MS` (~150 ms
nominal) keyed by voice set instead of playing immediately. A `move`/`attack`/
`feedback` request for the same voice set within the window discards the deferred
`select`; window expiry flushes the `select` through the normal `play_sound` path.
Deferred requests are stored as `{sound_id, remaining}`; `_process(delta)`
decrements and flushes. The debounce only covers a select that has not started, so
the system additionally tracks the voice set's playing `select` player and, when an
acknowledgment arrives after the window, stops that player before playing — a
realistic select-then-order cadence is slower than 150 ms, and the select clip is
still sounding. `die` is exempt (never deferred, never cancels, never stopped).
Repeated `select` requests for the same set coalesce into one slot. Window `0`
disables deferral.

*Why:* deferral alone only fixes near-instant order-follows-select; stopping the
in-flight select closes the actual reported overlap. Together they guarantee one
line per select→order interaction at any cadence, without threading unit identity
and without a crossfade (Godot's `stop()` is a hard cut, acceptable for a short
radio bark). Flushing through `play_sound` means retrigger stamps, per-id stack
caps, and bus renormalization only run for lines that actually play.

*Alternatives:*
- **Duck-don't-cut** (fade the select under the ack): no latency but needs a
  `duck_db` offset owned by `_renormalize_bus`, or bus renormalization defeats
  the tween.
- **OpenRA parity** (drop the incoming ack): leaves a fast harvest with no
  acknowledgment, contradicting the issue.
- **OpenTS parity** (allow overlap): leaves the reported bug.

### D4: Suppression scope is the voice set

`play_voice` only receives `(voice_id, event_name)`, and `VoiceData.id` is the
only speaker identity available there, so both the deferred slot and the
discard-on-ack rule key on the voice set.

*Why:* the real interaction is same-unit select→ack, and `select_voice_for_entities`
and `play_order_voices` both pick the NW-most unit of the same selection, so the
select and the ack resolve to the same voice set in the reported case. No API
change needed.

*Escape hatch:* if mixed-type selections show false suppression, add an optional
selection-epoch argument (default empty) and key on it; existing callers and
tests stay untouched.

## Risks / Trade-offs

- [Coarse scope: an unrelated same-voice-set event can swallow a deferred select]
  → Short window (~150 ms) makes this rare; a genuine re-select within the window
  coalesces (harmless). Optional epoch argument is the escape hatch.
- [Deferred select adds time-based state to AudioManager] → drive the countdown
  from `_process(delta)`; tests set the window explicitly/inject delta rather than
  sleeping.
- [Mixed selection: select NW-most of newly-added vs ack NW-most of selection can
  be different voice sets] → they then play as two distinct speakers, which is
  acceptable (and arguably correct) RTS behavior; not the reported case.
- [A deferred select that is never flushed leaks state] → the flush path clears
  the slot on expiry and on acknowledgement; `0` window disables it entirely.
- [Retrigger throttle interaction] → the flush calls `play_sound` at real play
  time, so `_last_played_at` is stamped only when a line actually starts.

## Migration Plan

No data migration. Internal API change only (`OrderResult.voice_event`,
`voice_event_for_cursor` removal), both inside the repo. Rollback is reverting the
commit; no persisted state or packed-scene changes.

## Open Questions

- Exact `SELECT_DEBOUNCE_MS` value — tune from playtesting; not spec-affecting.
- Whether to add the optional selection-epoch argument now or only if mixed
  selections show false suppression — deferrable; does not change the specs or
  task breakdown.
