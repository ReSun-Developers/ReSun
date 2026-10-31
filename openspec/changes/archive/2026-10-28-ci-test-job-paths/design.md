# Design

## Context

See `proposal.md` for motivation.

- `.github/workflows/test.yml` triggers on pushes matching `branches: ["*"]` and PRs targeting `main`. It runs `lint`, `check-openspec`, and `test`.
- GitHub's `*` filter does not match `/`, so the repo's `type/issue-description` branches do not match the push filter. Recent workflow runs confirm this: push runs are on `main` only; feature branches report `pull_request` runs. There is no push + PR duplicate to remove.
- `test` downloads/restores Redot, runs `--headless --import` over the whole project, then `--headless -s test/run_tests.gd`. This is the expensive job.
- `check-openspec` enforces the OpenSpec archive policy. It is not an enforced GitHub required check today, but it must not be skipped.
- The `main` ruleset (`common-ruleset-main`) requires a PR and code-owner review but has **no required status checks** (checked via the GitHub API on 2026-10-28). The design still has to stay safe if `test` becomes required later.
- The suite loads more than scripts and scenes:
  - JSON map data: `games/ts/maps/gdi01.json`, `games/ts/assets/test_map01.json`, `games/ts/assets/test_terrain.json`, `test/fixtures/map_theater_test.json`, `test/fixtures/maps/mission_map_credits.json`.
  - Binary assets: `games/ts/assets/models/*.glb`, `games/ts/external_assets/audio/*.ogg`, `test/fixtures/audio/test_tone.wav`, terrain textures.
  - Shared shell assets: `assets/fonts/*` (preloaded by `SelectionOverlay` and `Sidebar` autoloads), `assets/hdri/*` (world environment), `assets/cursors/*` (cursor state).
  - Shaders: `shaders/**` (loaded by UI and environment scenes).
  - Scene and resource data: `EntityData`, `GlobalRules`, and art `.tres` files.
- The repository's default workflow token permission is read-only; `pull-requests: read` is not implied by that default.
- Redot is headless-only in CI; no editor/LSP is involved.

## Goals / Non-Goals

**Goals:**

- Docs-only (`docs/`, `plans/`, `openspec/`, markdown) PRs skip `test` while `lint` and `check-openspec` still run.
- Changes to scripts, scenes, resources, JSON map data, game/shared assets, shaders, test fixtures, `project.godot`, or the workflow itself run `test`.
- A docs-only PR resolves all checks; no check stays "waiting to be reported", whether or not `test` is required.
- If change detection itself fails, tests run rather than being silently skipped.

**Non-Goals:**

- Gating `lint` or `check-openspec`.
- Splitting or speeding up the test suite itself.
- Changing branch-protection settings.
- Removing the existing `push` trigger.

## Decisions

### 1. Per-job condition, not workflow-level `paths`

Workflow-level `on.push.paths` / `on.pull_request.paths` would skip the whole workflow, including `check-openspec`, violating the OpenSpec policy. It would also make the `test` check never appear on docs-only PRs; if `test` is ever required, those PRs hang forever waiting for a check that never runs.

Instead, a `changes` job classifies the diff and `test` declares `needs: changes` with a job-level `if`. A skipped job reports a conclusion (treated as success for required checks) instead of a missing check.

### 2. `dorny/paths-filter` pinned to a commit SHA

Alternatives:

- **Inline `git diff` shell**: more code and wrong on new branches, force-pushes, and merge-base selection; must reimplement what the action already handles.
- **`tj-actions/changed-files`**: same role, heavier surface.
- **GitHub REST API shell**: needs pagination and event-specific handling for push.

`dorny/paths-filter` reads the PR file list from the API and falls back to git for push events (it fetches the `before` SHA if the shallow clone lacks it). Pin it to `0e4a8c6effa4802afeda77dc8d303f8176d7dfad` (the `v3` tag) instead of a mutable major tag; a third-party action should not be able to change under the workflow.

### 3. Fail-open condition

`test` uses:

```yaml
if: ${{ !cancelled() && needs.changes.outputs.gameplay != 'false' }}
```

`needs:` implies a `success()` check, so without `!cancelled()` a failed or cancelled `changes` job would skip `test` regardless of the expression. With it:

- `changes` succeeds and reports `false` → tests skipped.
- `changes` succeeds and reports `true` → tests run.
- `changes` fails or produces no output → tests run.
- The workflow is cancelled → tests do not start.

The cost of a false positive is one test run; the cost of a false negative is untested gameplay code.

### 4. Gate only `test`

`lint` stays always-on: it is cheap, and gating it would need a second filter/output for no meaningful saving. `check-openspec` stays always-on because it enforces the OpenSpec archive policy.

### 5. Keep the existing triggers

`push.branches: ["*"]` does not match slash-containing branches, and the repo's branch convention always includes `/`. Run history shows feature branches only run on `pull_request`; changing the trigger would add no value and would remove CI from non-slashed branches. Leave both triggers unchanged.

### 6. Gameplay filter

```yaml
gameplay:
  - '**/*.gd'
  - '**/*.tscn'
  - '**/*.tres'
  - 'assets/**'
  - 'games/**'
  - 'shaders/**'
  - 'test/**'
  - 'project.godot'
  - '.github/workflows/test.yml'
```

- `**/*.gd`, `**/*.tscn`, `**/*.tres`: code, scenes, and resources.
- `assets/**`: shared fonts, cursors, and HDRI loaded by autoloads and scenes.
- `games/**`: models, audio, art data, map data (including JSON maps), and other content the suite loads.
- `shaders/**`: shaders loaded by UI and environment scenes.
- `test/**`: test scripts, fixtures, JSON data, and `.import` metadata.
- `project.godot`: autoloads, input map, engine settings.
- `.github/workflows/test.yml`: a CI change tests itself.

Scope cut: the suite is a single Redot process, so any matched input runs the full suite; the directory scopes only keep docs and tooling from matching. `.uid`-only changes are not matched; `.import` files under `assets/`/`games/`/`test/` are covered by those globs, and the only unmatched import is the root `icon.svg.import`, which the suite does not load. If a regression later appears from a file type not listed here, add the extension.

### 7. Job-level permissions

The `changes` job needs `contents: read` for checkout and `pull-requests: read` for the PR file-list API:

```yaml
permissions:
  contents: read
  pull-requests: read
```

Job-level permissions replace the repository default for that job; specifying only `pull-requests: read` would remove `contents` and break checkout. Other jobs keep the default read-only token.

### 8. Required-check evidence

`gh api repos/ReSun-Developers/ReSun/branches/main/protection` returns `404 Branch not protected`; the active ruleset `common-ruleset-main` contains only `deletion`, `non_fast_forward`, and `pull_request` rules, with no `required_status_checks`. So no check can hang a PR today. Per-job skipping keeps that property if `test` becomes required.

## Risks / Trade-offs

- **Filter action supply chain** → pinned to a commit SHA. No Dependabot config exists; a follow-up can add one, but the pin is safe without it.
- **PR file-list API cap (3000 files)** → the suite's PRs are far below the cap; if that changes, replace the action with a custom `git diff` step against the PR base.
- **Filter returns `false` for an unanticipated file type** → `assets/**`, `games/**`, `shaders/**`, and `test/**` cover the known data-driven inputs; extend the filter when a missed regression is found.
- **`changes` job failure skips nothing** → `!cancelled()` runs tests on failure, so a filter outage costs time rather than coverage.
- **Post-merge run on `main`** → intended: the mainline commit is the health check.
- **Skipped required checks** → GitHub treats a skipped job as successful for required checks. Do not "simplify" this later to workflow-level `paths`, which reintroduces the hanging-check failure mode.

## Migration Plan

- Deploy by squash/rebase merge; the new job and condition take effect on the next event.
- Rollback is a revert of the workflow commit; no state or data migration.
- Static verification happens before commit (YAML parse, `actionlint`, acceptance walk-through). Runtime verification is post-merge/manual: docs-only PR (test skipped, other checks pass), `games/`/`test/`-only (test runs), `.gd` (all jobs run), a forced `changes` failure leaves `test` running, and a push to `main` runs the workflow once. The PR body carries this manual matrix.

## Open Questions

None.
