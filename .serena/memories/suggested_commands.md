# Suggested Commands

Run from repo root (Linux).

- Tests: `redot --headless -s test/run_tests.gd`
- Lint: `gdlint scripts/**/*.gd test/**/*.gd`
- Format check: `gdformat --check scripts/**/*.gd test/**/*.gd`
- Format apply: `gdformat scripts/**/*.gd test/**/*.gd` then `grep -P '\t' scripts/**/*.gd` (guard against tabs gdformat can introduce in multiline strings)
- Reindex code graph after adding scripts: `codebase-memory-mcp index_repository mode="full" name="ReSun"` (moderate/fast skip `scripts/` — always use full)
- Serena: auto-activates the project from CWD (nearest `.serena/` or `.git`), single-project mode. Validate memory refs with `serena memories check`.
- Git/GitHub: use `gh` for issues/PRs; branch/commit/PR naming conventions in `mem:conventions`.
