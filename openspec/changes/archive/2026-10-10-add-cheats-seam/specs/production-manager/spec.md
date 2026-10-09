## MODIFIED Requirements

### Requirement: Debug instant-build mode

When `Cheats.no_build_time == true`, production SHALL complete instantly in one frame.

#### Scenario: Debug mode active
- **WHEN** `Cheats.no_build_time` is true
- **THEN** production completes immediately, no timer advancement
