# system-initialization Specification

## Purpose
Defines how autoloads are accessed and how their startup order is declared: dependencies are explicit through registered singletons, a missing required dependency fails loudly instead of silently skipping wiring, and the `project.godot` ordering annotations match real lifecycle dependencies.

## Requirements

### Requirement: Autoloads are accessed through registered singletons

A registered autoload SHALL be accessed by its registered singleton identifier rather than by an absolute node path. In `scripts/`, a registered autoload SHALL NOT be resolved through a `get_node("/root/<Name>")` or `get_node_or_null("/root/<Name>")` string path. Nullable lazy accessors that resolve a child of the scene root by bare name (for example `tree.root.get_node_or_null("<Name>")`) are a separate, intentionally optional pattern and are out of scope for this requirement.

#### Scenario: Dependency access uses the registered singleton

- **WHEN** a script needs a registered autoload such as `PlayerManager`, `EconomyManager`, or `PrerequisiteSystem`
- **THEN** it references the autoload by its registered identifier, not by a `/root/<Name>` string path

#### Scenario: No autoload is resolved by absolute string path

- **WHEN** `scripts/` is scanned for `get_node("/root/<Name>")` and `get_node_or_null("/root/<Name>")` lookups targeting a registered autoload
- **THEN** no such lookups are found

### Requirement: A missing required dependency fails loudly

A registered autoload accessed by identifier SHALL be treated as guaranteed present: the accessing code SHALL NOT wrap that access in an existence check whose false branch silently skips dependency wiring. Where a dependency is genuinely optional or is not an autoload, its absence SHALL be handled explicitly — a named error when it is required at runtime, or a documented fallback otherwise. Nullable lazy accessors that resolve a child of the scene root by bare name are out of scope for this requirement (see the access requirement).

#### Scenario: Missing identifier dependency is loud

- **WHEN** a required autoload referenced by identifier is not registered
- **THEN** the failure surfaces at load/startup naming the identifier, rather than being swallowed by an existence check

#### Scenario: Optional dependency is handled explicitly

- **WHEN** a dependency is genuinely optional or is not an autoload, and it is absent
- **THEN** the system either reports a named error (when required at runtime) or takes a documented fallback, rather than skipping unconditionally

### Requirement: Declared startup order reflects real dependencies

The `[autoload]` ordering in `project.godot` SHALL register each autoload after every autoload whose `_ready`/`_enter_tree`-initialized state it reads during its own `_ready` or `_enter_tree`. Connecting to another autoload's signal does not constrain order, because a script-declared signal exists as soon as the autoload is instantiated. An ordering annotation SHALL name a reference that occurs in the annotated reader's `_ready`/`_enter_tree`; an annotation naming no such reference SHALL be removed. Registration order remains unchanged by this change.

#### Scenario: State-read dependency is ordered first

- **WHEN** an autoload reads another autoload's initialized state during `_ready` or `_enter_tree`
- **THEN** the dependency is registered earlier in `[autoload]` and its ordering annotation names that read

#### Scenario: Signal connection does not require ordering

- **WHEN** an autoload only connects to another autoload's signal during `_ready`
- **THEN** the connection is valid regardless of registration order, because the signal exists once the autoload is instantiated

#### Scenario: Unbacked ordering annotation is removed

- **WHEN** an ordering annotation in `[autoload]` names no reference in the reader's `_ready`/`_enter_tree`
- **THEN** the annotation is absent
