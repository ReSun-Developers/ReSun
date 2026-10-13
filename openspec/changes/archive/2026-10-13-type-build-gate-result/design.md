# Design

## Context

See `proposal.md` — Why. Current state that shapes the approach:

- `evaluate_build(player_id, data) -> Dictionary` (`scripts/production/PrerequisiteSystem.gd:74`)
  returns `{ "enabled", "reason", "cost", "owned_factory" }`; `can_build` (`:85`) is a
  one-line wrapper reading `["enabled"]`.
- Production readers: `CreditCounter.gd:108` and `Sidebar.gd:251` use `["enabled"]`;
  `ProductionManager.gd:665` already uses **property access** `.owned_factory` on the
  Dictionary — so GDScript's dot access on a `Dictionary` is relied on in-tree today, and
  switching to a typed object is source-compatible for property-access sites.
- The `build-gate` spec (`openspec/specs/build-gate/spec.md`) constrains *what* is reported,
  never the container type.
- `BuildReason` is an enum on `PrerequisiteSystem` (a `Node` autoload with no `class_name`),
  referenced externally as `PrerequisiteSystem.BuildReason`.

## Goals / Non-Goals

**Goals:**
- Make the build-gate result's shape a compile-time contract, eliminating string-key access.
- Keep the change behaviour-identical and revertible in one commit.
- Keep the diff small: property-access callers do not change; only bracket-access sites and
  result-typed test annotations do.

**Non-Goals:**
- The affordability feedback join (gate + balance + `Cheats.no_cost`). It has one consumer
  (`CreditCounter`) and already lives in one place; extracting a shared helper now would be a
  one-use abstraction. Deferred until a second consumer (e.g. a cameo tooltip red state) exists.
- Renaming or relocating `PrerequisiteSystem` (the `reason` enum, the World-root move is #473).
- Any spec text change: behaviour is unchanged, so no requirement changes.

## Decisions

### D1 — `BuildDecision` is a nested `RefCounted` on `PrerequisiteSystem`

```
class BuildDecision:
    extends RefCounted
    var enabled: bool
    var reason: BuildReason
    var cost: int
    var owned_factory: bool
```

Reference from outside the script is `PrerequisiteSystem.BuildDecision`. Alternatives:
- Separate `scripts/data/BuildDecision.gd` with `class_name` — a new file plus `.uid` for a
  value object that is only ever produced and consumed by the gate; not warranted yet.
- `Resource` — adds serialization machinery the value never uses.

Keeping the record next to the enum it carries is the smallest correct change, and adds no
files.

### D2 — `reason` is typed as the `BuildReason` enum

The field is declared `reason: BuildReason`, not `int`. Redot 26.2 LTS resolves an outer
script's enum inside a nested class, and an autoload's nested class is a valid external type
annotation (`var d: PrerequisiteSystem.BuildDecision`) — both verified by compiling the
constructs. Typing the field to the enum is the point of the change; a plain `int` would leave
the reason's domain unconstrained. No `int` fallback is retained.

### D3 — `can_build` stays a projection

`can_build` remains `return evaluate_build(...).enabled`, so the two public entry points do not
diverge and no caller changes. It is not deleted: one production caller
(`ProductionManager.start_production`) and the tech-level and prerequisite test suites read the
boolean directly, and a boolean projection is the natural read.

### D4 — No spec delta (`skip_specs: true`)

The gate's reported fields and their triggers are unchanged; only the in-memory container is.
The `build-gate` spec is silent on return type by design, so no requirement changes and no delta
spec is authored. This follows the schema guidance ("if behaviour does not change, no spec
should change either"). No earlier in-tree change relied on `skip_specs`, so this is the first;
the schema's own instruction is the precedent.

### D5 — Affordability join is untouched

`CreditCounter._update_credits_color` keeps its `_cheapest_cost > 0 and not Cheats.no_cost and
can_afford(...)` predicate inline. A `# ponytail:` comment records that it stays inline until a
second affordability consumer appears. `EconomyManager.can_afford` stays a pure balance check.

## Risks / Trade-offs

- [Nested class cannot resolve the outer `BuildReason` enum in a typed field] → verified to
  resolve on Redot 26.2 LTS; `reason: BuildReason` compiles and the autoload's nested class is a
  valid external annotation. No fallback retained.
- [Test churn looks large (~15 result annotations)] → it collapses into the two helpers
  `_reason` / `_assert_rejected`, whose parameters are retyped once.
- [A caller typed the result as `Dictionary` and is missed] → static typing makes any missed
  site a parse error, so the compiler enforces completeness; `test_build_gate_shared` and
  `test_credit_counter.test_unaffordable_type_is_still_enabled` are the behavioural anchors.

## Migration Plan

Land as one change; rollback is a revert. Apply bottom-up so the tree compiles between steps:
(1) add `BuildDecision` and retype `evaluate_build` + `can_build`; (2) flip the two
bracket-access production sites; (3) retype test helpers and annotations. No data or scene
migration. `can_build`'s signature is unchanged throughout.
