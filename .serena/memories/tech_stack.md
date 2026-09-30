# Tech Stack

- Engine: **Redot 26.2 LTS (Forward Plus)**. Binary `redot` at `/usr/bin/redot`, `redot --version` -> `26.2.stable.official.*`.
- **Pure GDScript + `.tscn`**. No C#, no native bindings, no build system (no Makefile/CMake/Docker). Built entirely through the Redot editor.
- Main scene `scenes/MainScene.tscn`. Viewport 1920x1080, `stretch/mode="viewport"`.
- **29 autoload singletons** declared in `project.godot [autoload]`. `GameContext` must remain first. Add singletons via project settings, never hardcoded references.
- **Data-driven**: entities are `EntityData` `.tres` resources under `games/<id>/entities/`, resolved via the active game's GameDefinition; `EntityFactory` reads them at runtime and attaches component scenes/scripts from data properties. Per-entity art `.tres` maps animation states to frames.
- **Testing**: custom runner `test/run_tests.gd` — no external framework. `TestHelper` (`test/test_helper.gd`) static assertions; runner injects autoload shorthands `_ts _sh _sm _bm _em _pm _am _ss`.
- **Lint/format**: gdtoolkit (`gdlint`, `gdformat`) installed globally via pip. Config `.gdlintrc`, `gdformatrc`.
- **UID files**: Redot generates `.uid` alongside scripts/scenes; they are valid source and MUST be committed with their source file.
- MCP tooling: `codebase-memory-mcp` (index name **`ReSun`**, mode **`full`** — moderate/fast skip `scripts/`), Serena (project name `resun`, `gdscript` language server).
