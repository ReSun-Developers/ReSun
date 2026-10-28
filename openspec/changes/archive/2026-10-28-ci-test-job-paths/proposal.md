# Proposal

## Why

Every push and PR runs the full Redot test job even when only `docs/`, `plans/`, or `openspec/` changed. That job downloads (or restores) the Redot binary, runs `--headless --import` over the whole project, then runs the suite. Docs-only changes pay that cost for no signal.

## What Changes

- Add a `changes` job that classifies the files touched by the push/PR.
- Gate only the `test` job on that classification. `lint` and `check-openspec` stay unconditional so the OpenSpec check is never skipped.
- Treat these as gameplay inputs that require tests:
  - `**/*.gd`
  - `**/*.tscn`, `**/*.tres`
  - `assets/**`, `games/**` (fonts, cursors, HDRI, models, audio, art/map data — including JSON maps — loaded by the suite)
  - `shaders/**`
  - `test/**` (test scripts and fixtures)
  - `project.godot`
  - `.github/workflows/test.yml`
- Leave the `push` / `pull_request` triggers as they are. The current `push.branches: ["*"]` does not match branch names containing `/` (GitHub's `*` does not cross `/`), so the repo's `type/issue-description` branches already get CI only from their PR. There is no duplicate run to remove.
- Update the CI sections in `README.md` and `DEVELOPER_GUIDE.md` to describe the gated `test` job.

## Capabilities

None. This is CI tooling only; no product behavior changes. The change sets `skip_specs: true` in `.openspec.yaml`.

### New Capabilities

_None._

### Modified Capabilities

_None._

## Impact

- `.github/workflows/test.yml` (new `changes` job, `test` condition).
- `README.md`, `DEVELOPER_GUIDE.md` (CI description).
- New dependency: `dorny/paths-filter` pinned to commit `0e4a8c6effa4802afeda77dc8d303f8176d7dfad` (`v3`).
- Branch protection: `main` has no required status checks (verified via the GitHub API), so a skipped `test` job cannot hang a PR today. Per-job gating keeps that true if `test` becomes required, because a skipped job reports success instead of never appearing.
