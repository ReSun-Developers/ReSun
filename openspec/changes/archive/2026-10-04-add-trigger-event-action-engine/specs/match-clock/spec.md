# Spec Delta

## Purpose

Provides a single fixed-rate logic clock and an integer-tick deadline scheduler so gameplay and
mission scripting advance deterministically, decoupled from the render frame rate.

## ADDED Requirements

### Requirement: Fixed-rate logic tick

`MatchClock` SHALL advance an integer frame counter at a fixed rate of 30 logic ticks per second,
independent of the render frame rate, and SHALL emit `tick(frame)` exactly once per logic tick.
Elapsed real time SHALL be accumulated and converted into whole logic ticks; a single rendered
frame MAY advance zero, one, or several logic ticks, and the clock SHALL NOT drop or double-count
a tick. The frame counter SHALL be monotonically increasing from zero after reset.

#### Scenario: Emits once per logic tick
- **WHEN** the accumulated elapsed time reaches one logic tick interval
- **THEN** the frame counter increases by exactly one and `tick(frame)` is emitted once with the new frame

#### Scenario: Decoupled from render rate
- **WHEN** a rendered frame takes longer than a logic tick interval
- **THEN** the clock advances the matching whole number of logic ticks and emits `tick` once per tick, not once per rendered frame

#### Scenario: No ticks before an interval elapses
- **WHEN** less than one logic tick interval of real time has elapsed
- **THEN** the frame counter does not change and no `tick` is emitted

### Requirement: Deadline scheduler

`MatchClock` SHALL allow scheduling a named deadline a whole number of frames ahead and cancelling
it. When the frame counter reaches a scheduled deadline, the clock SHALL emit `deadline_reached(key)`
exactly once for that key and remove it. Deadlines due on the same frame SHALL fire in ascending
deadline order, breaking ties by scheduling order. Scheduling a key that is already pending SHALL
replace its deadline and its scheduling order.

#### Scenario: Scheduled deadline fires once
- **WHEN** a deadline is scheduled three frames ahead
- **THEN** `deadline_reached` is emitted for that key when the frame counter reaches the deadline, and never again

#### Scenario: Cancelled deadline does not fire
- **WHEN** a pending deadline is cancelled before its frame
- **THEN** no `deadline_reached` is emitted for that key

#### Scenario: Same-frame order is deterministic
- **WHEN** two deadlines are scheduled for the same frame
- **THEN** they fire in the order they were scheduled

#### Scenario: Rescheduling replaces
- **WHEN** a pending key is scheduled again for a later frame
- **THEN** only the later deadline fires, once

### Requirement: Reset and pause

`MatchClock.reset()` SHALL set the frame counter to zero and clear every pending deadline. While the
match is paused, the clock SHALL NOT advance the frame counter or emit `tick` or `deadline_reached`;
after resume it SHALL continue from its current frame and still-pending deadlines.

#### Scenario: Reset clears frame and deadlines
- **WHEN** `reset()` is called after ticks and pending deadlines
- **THEN** the frame counter is zero and no deadline remains pending

#### Scenario: Paused clock does not advance
- **WHEN** the clock is paused and real time elapses
- **THEN** the frame counter does not change and no `tick` or `deadline_reached` is emitted

#### Scenario: Resume continues
- **WHEN** the clock resumes after being paused with a pending deadline
- **THEN** the pending deadline still fires at its original frame
