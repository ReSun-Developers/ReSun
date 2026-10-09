# credit-ui Specification

## Purpose

Show the local player's credit balance in the gameplay HUD and give feedback as it changes: an animated counter that ticks up and down at direction-dependent cadences, plays income and spend sounds, and warns when funds are insufficient for the cheapest buildable item.
## Requirements
### Requirement: Credit display label in gameplay HUD
The system SHALL display the current credit balance as an animated counter in a Label node at the top of the right-hand gameplay HUD column, above the minimap and above the Sidebar build panel. On a `credits_changed` signal for the local player, the counter SHALL store the new balance as its target and step a displayed value toward the target once per frame until the displayed value reaches the target; the Label text SHALL always show the displayed value. Step size SHALL be proportional to the remaining gap (remaining gap divided by a configurable divisor, clamped to a configurable minimum and maximum). Counting cadence SHALL be time-based and direction-dependent: counting up SHALL step at the full frame rate, counting down SHALL step at a configurable slower interval, so an equal-amount spend animation takes longer than its gain counterpart. When the displayed value equals the target, the counter SHALL be idle (per-frame processing disabled until the next credit change). Forced initialization — scene ready or balance resync — SHALL set the displayed value directly to the balance without animating.

#### Scenario: Label shows current balance on ready
- **WHEN** the credit display label initializes
- **THEN** a Label displays `EconomyManager.get_balance(0)` prefixed with "$" immediately, with no animation

#### Scenario: Label counts toward the target on credit change
- **WHEN** `EconomyManager.add()` or `EconomyManager.deduct()` changes the local player's balance
- **THEN** the Label text updates over subsequent frames, stepping toward the new balance, and settles exactly at the new balance

#### Scenario: Large changes animate in a burst, small changes in few steps
- **WHEN** the gap between the displayed value and the target is large
- **THEN** each step covers the gap divided by the divisor (clamped), so the animation length grows sub-linearly with the amount changed

#### Scenario: Counting down is slower than counting up
- **WHEN** a gain and an equal-sized loss animate
- **THEN** the loss animation spans more time per step (spend step interval > gain step interval), both measured in seconds

#### Scenario: Counter is idle when settled
- **WHEN** the displayed value equals the target and no new `credits_changed` has arrived
- **THEN** the counter performs no per-frame updates (no label write and no tick) until the next credit change

#### Scenario: Other players' credit changes are ignored
- **WHEN** `credits_changed` fires for a player other than the local player
- **THEN** the counter does not animate and the Label is unchanged

### Requirement: Credit counter tick sounds
The credit counter SHALL play a tick sound on each displayed step while animating: `ECON_INCOME` while counting up, `ECON_SPEND` while counting down, routed through `AudioManager.play_sound` as non-spatial SFX. Only the local player's counter animates and ticks. Forced initialization SHALL NOT play any tick.

#### Scenario: Gain produces an up-tick burst
- **WHEN** a large credit gain animates
- **THEN** `ECON_INCOME` plays once per displayed step across the animation (repeats within the sound's retrigger window are dropped by `AudioManager` throttling)

#### Scenario: Spend produces down-ticks at the slower cadence
- **WHEN** a credit deduction animates
- **THEN** `ECON_SPEND` plays once per displayed step, at the slower count-down cadence

#### Scenario: Forced display is silent
- **WHEN** the counter is force-initialized (scene ready or balance resync)
- **THEN** no tick sound plays

#### Scenario: Other players' credit changes are silent
- **WHEN** `credits_changed` fires for a player other than the local player
- **THEN** no tick sound plays

### Requirement: Insufficient funds visual feedback

The Label SHALL change color when the local player's credit balance is below the cost of the
cheapest item that player can currently build. The set used for the comparison SHALL be the
same build gate the sidebar build list is drawn from, scoped to the local player and spanning
every build-menu tab (not only the currently-visible page): an item that is not buildable for
the local player SHALL NOT influence the warning, even if it is cheap. An item with zero or
negative cost SHALL NOT influence the warning. When the player can build no costed item, no
warning SHALL appear. When the `no_cost` cheat is active, the warning SHALL NOT appear.

#### Scenario: Sufficient funds
- **WHEN** the local balance is at or above the cost of the cheapest item the local player can build
- **THEN** the Label color is white

#### Scenario: Insufficient funds
- **WHEN** the local balance is below the cost of the cheapest item the local player can build
- **THEN** the Label color turns red

#### Scenario: Locked cheap item does not trigger the warning
- **WHEN** a cheap item exists in the catalog but is not buildable by the local player (unmet gate), and the balance covers every item the player can build
- **THEN** the Label color is white

#### Scenario: No-cost cheat disables the warning
- **WHEN** the `no_cost` cheat is active
- **THEN** the Label color is white regardless of balance

#### Scenario: Nothing buildable means no warning
- **WHEN** the local player can build no costed item
- **THEN** the Label color is white regardless of balance

### Requirement: Credit display resyncs when the player roster is rebuilt
`PlayerManager` SHALL emit `players_changed` after it (re)builds its player roster. The credit counter SHALL resync — via the forced, non-animated display path — to the local player's balance whenever `players_changed` fires, so a mission's starting credits replace any pre-mission balance shown while the map was loading.

#### Scenario: Roster rebuild resyncs the HUD
- **WHEN** `PlayerManager.begin_mission` rebuilds the roster with a new local-player balance
- **THEN** `players_changed` emits and the credit label immediately shows the new balance, with no animation

#### Scenario: Mission credits replace the stale default
- **WHEN** the map enters the tree showing the autoload default balance and the mission then sets the local player's credits
- **THEN** the label ends at the mission's balance, not the pre-mission default

#### Scenario: Resync is silent
- **WHEN** the counter resyncs from `players_changed`
- **THEN** no tick sound plays

