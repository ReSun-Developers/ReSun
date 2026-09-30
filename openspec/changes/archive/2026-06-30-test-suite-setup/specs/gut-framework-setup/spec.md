## ADDED Requirements

### Requirement: GUT addon shall be installed

The project SHALL include GUT v9.x addon at `addons/gut/` directory.

#### Scenario: GUT directory exists

- **WHEN** the project is opened in Redot editor
- **THEN** `addons/gut/` directory exists with plugin files

### Requirement: GUT plugin shall be enabled

The `project.godot` file SHALL include an `[editor_plugins]` section with GUT enabled.

#### Scenario: Plugin enabled in project settings

- **WHEN** `project.godot` is parsed
- **THEN** `[editor_plugins]` section exists containing `res://addons/gut/plugin.cfg`

### Requirement: Test directory structure shall exist

The project SHALL have a `test/` directory with `unit/` and `integration/` subdirectories.

#### Scenario: Directory structure created

- **WHEN** the test suite is set up
- **THEN** `test/unit/` and `test/integration/` directories exist

### Requirement: GUT configuration shall exist

A `.gutconfig.json` file SHALL exist at `test/.gutconfig.json` specifying test directories and settings.

#### Scenario: Config file present

- **WHEN** GUT is invoked from command line
- **THEN** `.gutconfig.json` is found and loaded with correct directory paths

### Requirement: GUT shall load on Redot

GUT plugin SHALL load without errors when Redot 26.2 LTS opens the project.

#### Scenario: Plugin loads successfully

- **WHEN** Redot opens the project with GUT enabled
- **THEN** no error messages appear related to GUT loading
- **THEN** GUT panel appears in the editor

### Requirement: Tests shall run in GitHub Actions CI

A GitHub Actions workflow SHALL exist at `.github/workflows/test.yml` that runs the test suite on every push and pull request.

#### Scenario: CI runs on push

- **WHEN** code is pushed to any branch
- **THEN** the test workflow triggers
- **THEN** Redot is installed on the runner
- **THEN** project assets are imported headlessly
- **THEN** test suite executes via `redot --headless -s test/run_tests.gd`
- **THEN** workflow fails if any test fails

#### Scenario: CI runs on pull request

- **WHEN** a pull request is opened or updated
- **THEN** the test workflow triggers
- **THEN** test results are reported on the PR

### Requirement: CI shall use Redot, not Godot

The CI workflow SHALL install Redot Engine (not Godot) to match the project's runtime.

#### Scenario: Redot binary used in CI

- **WHEN** the CI workflow installs the engine
- **THEN** the binary is `redot` (not `godot`)
- **THEN** version matches project requirements (26.2 LTS)

### Requirement: CI shall enforce no open changes in openspec/changes

The CI workflow SHALL verify that `openspec/changes/` contains no open change directories — only the `archive/` subdirectory is permitted.

#### Scenario: Open change exists — CI fails

- **WHEN** `openspec/changes/` contains a directory other than `archive/`
- **THEN** the CI workflow fails with an error message
- **THEN** the error lists the offending directories

#### Scenario: Only archive exists — CI passes

- **WHEN** `openspec/changes/` contains only `archive/` (and no other directories)
- **THEN** the CI check passes
