# Developer guide

How to set up a ReSun dev environment and how we work. For a quick start, see
the short version in [README.md](README.md). This guide is the detailed one.

## Prerequisites

| Tool | Version | Why |
|------|---------|-----|
| Redot Engine | 26.2 LTS | Runs the game and the editor |
| Python 3.x | any recent | Runs gdlint / gdformat |
| Node.js | 20.19.0+ | Runs the OpenSpec CLI |
| gdtoolkit | latest (`pip install gdtoolkit`) | Lint + format |
| OpenSpec CLI | latest (`npm install -g @fission-ai/openspec@latest`) | Spec workflow (required) |

### About the engine

ReSun targets **Redot 26.2 LTS**, not plain Godot. Redot 26.2 is based on
Godot 4.5.2 with fixes cherry-picked on top, and `project.godot` declares the
feature tags `("26.2", "Forward Plus", "Redot")`.

Opening the project in a stock Godot 4.7 binary will warn about unknown
feature tags. It may load, but it is not the engine we test against. Use Redot
26.2 unless you are deliberately investigating a port.

Download: https://github.com/Redot-Engine/redot-engine/releases (grab the
`redot-26.2-stable` editor build for your platform).

## Quick start

1. Clone the repo.
2. Open `project.godot` in Redot 26.2. First import takes a while.
3. Open `scenes/MainScene.tscn` and press play (F5).
4. Run the tests headless from the repo root:

   ```bash
   redot --headless -s test/run_tests.gd
   ```

   Roughly 80 seconds for the full suite. `-- --tap` prints TAP output. There
   is no per-file filter; suites run in sorted order on every machine because
   they leak process-wide singleton state.

5. Before you push, lint and format:

   ```bash
   gdlint scripts/**/*.gd test/**/*.gd
   gdformat --check scripts/**/*.gd test/**/*.gd
   ```

   If `gdformat` rewrites files, run `grep -P '\t' scripts/**/*.gd` afterwards.
   It occasionally introduces tabs inside multi-line strings, and tabs break
   Redot parsing.

## OpenSpec (required)

Every change to behavior goes through OpenSpec. The flow is propose, apply,
archive. CI rejects any PR that still has an open change in `openspec/changes/`
(the only allowed subdirectory is `archive/`).

- `openspec/specs/` holds the authoritative behavior specs.
- `GLOSSARY.md` is the canonical term list. Read it before writing specs or
  designs. If you need a new term, check the Undecided section first, then
  propose it.
- Each change lives in `openspec/changes/<date>-<name>/` with a `proposal.md`,
  `design.md`, `tasks.md`, and `specs/<capability>/spec.md` deltas.
- `openspec archive <name>` folds the deltas into `openspec/specs/` and moves
  the change into `openspec/changes/archive/`.

If you work through an AI tool, the repo ships slash commands that wrap this
loop: `/opsx-propose`, `/opsx-apply`, `/opsx-explore`, `/opsx-archive`. They
exist in both `.opencode/commands/` and `.agents/commands/`. From a plain
terminal the equivalent is the `openspec` CLI directly.

## Agentic coding

We welcome AI-assisted development. It is not mandatory, and the conventions
do not change either way.

`AGENTS.md` at the repo root is the entry point for coding agents. It lists
the autoloads, the folder layout, and the hard rules. The ones people get
wrong most often:

- Type hints on every variable, parameter, and return value.
- Signal up, call down. Children emit signals, parents react.
- 4 spaces, never tabs.
- Conventional Commits with the issue number: `fix(TerrainSystem): prevent phantom cells (#17)`.
- Branch names: `type/issue-number-kebab-description`, e.g. `fix/59-building-placement-blocking`.
- PR titles: conventional prefix plus issue number, e.g. `fix: building ignores moving entities (#59)`.
- Commit `.uid` files together with their script or scene. Redot generates them.
- Right-click cancels, left-click acts. Unit orders only ever go on left-click.
- Tests validate behavior, not implementation. See the full rules in `AGENTS.md`.

Two `editor` concepts that are easy to confuse: `Engine.is_editor_hint()`
means the Redot IDE, `get_meta("is_map_editor")` means the in-game map editor.
They are unrelated.

## Optional AI tooling

Skip this section if you write code by hand.

### Serena (MCP, LSP symbol intelligence)

Serena talks to the GDScript language server so you can jump to definitions,
find references, and edit by symbol instead of by regex.

- Install: `uv tool install serena-agent` (or `pipx install serena-agent`).
  Provides the `serena` command.
- It connects to Redot's built-in language server over TCP on port **6005**,
  which means the Redot editor has to be open on the project. The port override
  lives in `.serena/project.yml`.
- The port setting only applies if the project path is listed under
  `trusted_project_path_patterns` in your global `~/.serena/serena_config.yml`.
  That trust is per machine, so you set it once after cloning.
- Docs: https://oraios.github.io/serena

Without a running editor, the symbol tools fail silently and you fall back to
grep.

### codebase-memory-mcp (MCP, knowledge graph)

Indexes the repo into a queryable graph: who calls what, data flow, hot paths.

- Install: https://github.com/DeusData/codebase-memory-mcp. The binary has a
  `codebase-memory-mcp install` command that registers it with common MCP
  clients.
- Index this repo with `mode="full"` and `name="ReSun"`. The default moderate
  and fast modes skip `scripts/` entirely, which is where all the GDScript
  lives, so you get an empty-looking graph. The PascalCase name keeps the
  identifier stable for auto re-indexing on git events.

```text
index_repository mode="full" name="ReSun"
```

### Redot docs in the editor loop

If your AI tool has Context7 access, the Redot docs library id is
`/redot-engine/redot-docs`. Prefer Redot docs over upstream Godot docs where
they differ.

## CI

GitHub Actions runs three jobs on every push and PR
(`.github/workflows/test.yml`):

1. **lint**. Runs `gdlint` then `gdformat --check` on `scripts/` and `test/`.
2. **check-openspec**. Fails if `openspec/changes/` has any non-archive
   directory.
3. **test**. Downloads Redot 26.2 headless (cached), imports assets, runs the
   full test suite.

A formatting-only failure is the most common red build. Run `gdformat` on the
files CI names and push again.

## Where things live

| Path | What |
|------|------|
| `AGENTS.md` | Conventions and rules, agent entry point |
| `GLOSSARY.md` | Canonical domain terms |
| `openspec/` | Specs and change workflow |
| `plans/` | Design docs by gameplay category |
| `docs/` | Multi-title research: capability matrix, gap analysis, architecture |
| `test/` | Test runner, `TestHelper`, unit + integration tests |
| `games/<id>/` | Per-game content: entities, art, audio, rules |
| `.gdlintrc`, `gdformatrc` | Lint and format config |

## Testing

```bash
redot --headless -s test/run_tests.gd          # full suite
redot --headless -s test/run_tests.gd -- --tap # TAP output
```

Tests are plain GDScript files named `test_*.gd` under `test/unit/` and
`test/integration/`, discovered by the runner. Use `TestHelper` static
assertions (`assert_eq`, `assert_true`, `reset()`), not a framework. The runner
injects autoload shorthand vars: `_ts` (TerrainSystem), `_sm` (SelectionManager),
`_bm` (BuildingManager), `_em` (EconomyManager), and others listed in
`AGENTS.md`.

Behavior, not implementation. A test that copies the production formula into
the assertion proves nothing. For rejections, first show the same setup
succeeds without the rejected condition, then break the condition.
