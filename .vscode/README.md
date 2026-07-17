# VSCode Development Tasks

VSCode configuration for the Hop 'n Bop project.

> **Rewritten 2026-07-16.** The previous version of this file
> documented a GameLift/WSL C++ workflow that was deleted in Phase F
> (2026-05-03): "GameLift: Initial Setup", "Build GDExtension", an
> `addons/gamelift/` output directory, WSL scons paths, and a
> "Deploying to AWS" section. None of those tasks had existed in
> `tasks.json` for months, so anyone following the "run this once
> after cloning" instruction found nothing. Everything below is
> checked against the actual `tasks.json` / `launch.json`.

## Quick Start

Press `Ctrl+Shift+P` and type "Tasks: Run Task" to see all tasks.

There is no default build task — this is a GDScript project with no
local compile step, so `Ctrl+Shift+B` does nothing useful.

## Tasks

### Run

| Task | What it does |
|---|---|
| **Godot: Run Server (Preview Mode)** | Runs the game server locally in preview mode. |
| **Godot: Run 3 Instances (Multi-Client Test)** | Opens the editor for multi-instance testing. Configure via Debug > Customize Run Instances (see the root CLAUDE.md for the launch args). |

### Test

| Task | What it does |
|---|---|
| **Tests: Run All Tests** | All GUT tests (unit + integration). |
| **Tests: Run Unit Tests** | `test/unit` only. |
| **Tests: Run Integration Tests** | `test/integration` only. Some of these expect a backend; CI runs them against a compose stack. |
| **Tests: Run Specific Test File** | Prompts for a path. Most reliable mode — see CLAUDE.md's "Project-Specific Testing Notes". |
| **Tests: Run with JUnit XML Output** | Exports `test_results.xml`. |

### Dev

| Task | What it does |
|---|---|
| **Dev: Format GDScript** | Formats via the `gdscript_formatter` addon. Run before committing. |
| **Dev: Open Godot Editor** | Opens the editor. |
| **Dev: Check for Pre-existing Errors** | Parse-check without running. |

## Launch Configurations

`F5` or the Debug panel:

- **Godot: Debug Server (Preview Mode)** — server in local preview mode. Port 6007.
- **Godot: Debug Server (Standalone, no preview)** — server without `--preview`, i.e. how it runs in a real deploy. Port 6007.
- **Godot: Debug Client 1 / 2** — client instances. Ports 6008 / 6009.
- **Godot: 2 Clients + Server (Preview)** — launches the server task first.
- **Godot: Attach to Running Instance** — attaches to a running Godot. Port 6007.
- **Multi-Client: 2 Clients + Server** (compound) — server + 2 clients together.

## Troubleshooting

**Tests fail to run.** First check the GUT/engine version pairing —
GUT ships one release per Godot minor, and a mismatch does not fail
loudly: GUT reports "Nothing was run" and still exits 0. See
CLAUDE.md's "Testing with GUT". After changing the engine or the
addon, delete `.godot/global_script_class_cache.cfg` and re-import.

**Tests report "Could not find script".** A `-gtest=` path that
doesn't exist also exits 0. Check the path.

**Godot not found.** `godot` must be on the PowerShell PATH; it is
not on bash's.

## File Locations

- **Tasks**: `.vscode/tasks.json`
- **Launch configs**: `.vscode/launch.json`
- **Settings**: `.vscode/settings.json`
- **Test results**: `test_results.xml` (JUnit export task only)

## VS Code Extensions

See `extensions.json`. This repo has no local C++ source — the only
GDExtension it consumes is `addons/webrtc/` (prebuilt), and the
patched `webrtc-native` build happens inside `Dockerfile.edgegap`,
not in the editor.

## More Information

- [VSCode Tasks Documentation](https://code.visualstudio.com/docs/editor/tasks)
- [Godot VSCode Integration](https://docs.godotengine.org/en/stable/tutorials/editor/external_editor.html)
