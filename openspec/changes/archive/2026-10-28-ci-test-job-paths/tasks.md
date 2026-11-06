# Tasks

## 1. Workflow change

- [x] 1.1 Add a `changes` job with `actions/checkout@v4` and `dorny/paths-filter@0e4a8c6effa4802afeda77dc8d303f8176d7dfad` (v3); expose the `gameplay` output.
- [x] 1.2 Give the `changes` job `permissions: {contents: read, pull-requests: read}`.
- [x] 1.3 Add the gameplay filter: `**/*.gd`, `**/*.tscn`, `**/*.tres`, `assets/**`, `games/**`, `shaders/**`, `test/**`, `project.godot`, `.github/workflows/test.yml`.
- [x] 1.4 Gate `test` with `needs: changes` and `if: ${{ !cancelled() && needs.changes.outputs.gameplay != 'false' }}`.
- [x] 1.5 Leave the `push`/`pull_request` triggers and the `lint`/`check-openspec` jobs unchanged.

## 2. Docs

- [x] 2.1 Update the CI section of `README.md` to say `test` is gated on gameplay inputs.
- [x] 2.2 Update the CI section of `DEVELOPER_GUIDE.md` to list the `changes` job and the `test` condition.

## 3. Verification

- [x] 3.1 Parse the workflow: `python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/test.yml"))'` (syntax only; PyYAML reads `on` as a boolean, so this is not a trigger check).
- [x] 3.2 Install and run `actionlint` (release binary or `go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.7`): `actionlint .github/workflows/test.yml`. This is the authoritative validation.
- [x] 3.3 Run `git diff --check`.
- [x] 3.4 Statically walk the acceptance cases against the YAML: docs-only PR skips `test` and still resolves; `.tscn`/`.tres` PR runs `test`; `.gd` PR runs all jobs; `assets/`/`games/`/`test/`-only PR runs `test`; `changes` failure still runs `test`; `check-openspec` has no path filter; a fork PR still classifies via `pull-requests: read`. Runtime verification (including push-to-main and a forced `changes` failure) is in the PR manual test plan.

## 4. Archive and commit

- [x] 4.1 Archive the change with `openspec archive ci-test-job-paths --yes`.
- [x] 4.2 Commit with `ci: gate the test job on gameplay file changes (#467)`.
