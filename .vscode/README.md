# VSCode Development Tasks

This directory contains VSCode configuration for the Hop 'n Bop project.

## Quick Start

Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac) and type "Tasks: Run Task" to see all available tasks.

## Task Categories

### 🛠️ Setup Tasks

**GameLift: Initial Setup**
- First-time setup: installs dependencies and builds the GameLift GDExtension
- Runs in WSL automatically
- Takes 10-15 minutes
- Run this once after cloning the repository

**GameLift: Install WSL Dependencies**
- Installs build tools in WSL (cmake, make, gcc, scons)
- Requires sudo password
- Run this if you get "command not found" errors

### 🔨 Build Tasks

**GameLift: Build GDExtension (Release)** ⭐ *Default Build*
- Builds the GameLift native extension for Linux
- Output: `addons/gamelift/bin/libgamelift.linux.template_release.x86_64.so`
- Use `Ctrl+Shift+B` to run the default build task
- Takes ~2-3 minutes

**GameLift: Build GDExtension (Debug)**
- Builds with debug symbols for development
- Slower runtime, better error messages
- Use for local development and debugging

**GameLift: Clean Build**
- Removes all build artifacts
- Run this before a fresh rebuild or if you get linking errors

**GameLift: Rebuild SDK**
- Completely rebuilds the GameLift Server SDK from scratch
- Run this if you update the SDK or get undefined symbol errors
- Takes ~5-10 minutes

### ▶️ Run Tasks

**Godot: Run Server (Preview Mode)**
- Runs the game server locally without GameLift
- For testing game logic without AWS
- Runs headless (no window)

**Godot: Run 3 Instances (Multi-Client Test)**
- Opens Godot editor for multi-instance testing
- Configure Debug > Customize Run Instances:
  - Instance 1: `--server --preview`
  - Instance 2: `--client=1 --preview`
  - Instance 3: `--client=2 --preview`
- Press F5 to run all instances

**GameLift: Run Server (Anywhere Mode)**
- Runs the server with GameLift Anywhere fleet
- Requires GameLift Anywhere fleet setup
- For testing GameLift integration locally

### 🧪 Test Tasks

**Tests: Run All Tests**
- Runs all GUT tests (unit + integration)
- Exit code 0 = success, 1 = failures
- Output shows pass/fail for each test

**Tests: Run Unit Tests**
- Runs only unit tests (`test/unit/`)
- Faster than running all tests

**Tests: Run Integration Tests**
- Runs only integration tests (`test/integration/`)
- Tests that require multiple components

**Tests: Run Specific Test File**
- Prompts for a test file path
- Example: `res://test/unit/networking/test_rollback_buffer.gd`

**Tests: Run with JUnit XML Output**
- Runs all tests and exports results to `test_results.xml`
- For CI/CD integration

### 🚀 GameLift Deployment Tasks

**GameLift: Package for Deployment**
- Creates `gamelift-deploy.tar.gz` with all necessary files
- **Prerequisites**: Export Godot server build first
- Includes:
  - Exported server executable
  - GameLift extension
  - Required libraries
  - Run script with LD_LIBRARY_PATH

**GameLift: Upload Build to AWS**
- Uploads the deployment package to AWS GameLift
- **Prerequisites**:
  - AWS CLI installed and configured
  - Deployment package created
- Prompts for build version and AWS region

**GameLift: Create Fleet**
- Shows instructions for creating a GameLift fleet
- Use AWS Console or CLI

### 🔧 Development Tasks

**Dev: Format GDScript**
- Formats all GDScript files using the gdscript_formatter addon
- Run before committing to maintain code style

**Dev: Open Godot Editor**
- Opens the Godot editor
- Alternative to double-clicking project.godot

**Dev: Check for Pre-existing Errors**
- Checks for GDScript parse errors without running
- Useful for verifying syntax after editing

### 📝 Git Tasks

**Git: Commit with Co-Author**
- Creates a commit with Claude Sonnet 4.5 as co-author
- Prompts for commit message
- Use when Claude Code assists with changes

## Keyboard Shortcuts

- `Ctrl+Shift+B` - Run default build task (Build GDExtension Release)
- `Ctrl+Shift+P` → "Tasks: Run Task" - Show all tasks
- `F5` - Start debugging (if configured in launch.json)

## Launch Configurations

Use `F5` or the Debug panel to use these configurations:

**Godot: Debug Server (Preview Mode)**
- Debugs the server in local preview mode
- Port 6007

**Godot: Debug Server (GameLift Mode)**
- Debugs the server with GameLift enabled
- Port 6007

**Godot: Debug Client 1**
- Debugs a client instance
- Port 6008

**Godot: Attach to Running Instance**
- Attaches to an already-running Godot instance
- Port 6007

## Typical Workflows

### First-Time Setup
1. Run "GameLift: Initial Setup"
2. Wait for build to complete (10-15 min)
3. Run "Tests: Run All Tests" to verify

### Daily Development
1. Make code changes
2. Press `Ctrl+Shift+B` to rebuild
3. Run "Godot: Run Server (Preview Mode)" to test
4. Run "Tests: Run All Tests" before committing

### GameLift Development
1. Make GameLift-related changes
2. Run "GameLift: Build GDExtension (Release)"
3. Run "GameLift: Run Server (Anywhere Mode)" to test
4. Use "Tests: Run Integration Tests" to verify

### Before Committing
1. Run "Dev: Format GDScript"
2. Run "Dev: Check for Pre-existing Errors"
3. Run "Tests: Run All Tests"
4. Use "Git: Commit with Co-Author" if Claude assisted

### Deploying to AWS
1. Export Godot server build (Linux, headless)
2. Run "GameLift: Package for Deployment"
3. Run "GameLift: Upload Build to AWS"
4. Create/update fleet via AWS Console
5. Test deployed build

## Troubleshooting

### "command not found" errors
Run "GameLift: Install WSL Dependencies"

### Build fails with "No such file or directory"
1. Run "GameLift: Clean Build"
2. Run "GameLift: Initial Setup"

### Extension not loading in Godot
1. Check that `addons/gamelift/bin/` contains `.so` files
2. Check Godot Output tab for errors
3. Verify `addons/gamelift/gamelift.gdextension` exists

### Tests fail to run
1. Make sure GUT addon is installed
2. Check that test files start with `test_` prefix
3. Verify test files extend `GutTest`

## File Locations

- **Tasks**: `.vscode/tasks.json`
- **Launch configs**: `.vscode/launch.json`
- **Settings**: `.vscode/settings.json`
- **Build output**: `gamelift-gdextension/bin/`
- **Installed extension**: `addons/gamelift/`
- **Test results**: `test_results.xml` (if using JUnit export)
- **Deployment package**: `gamelift-deploy.tar.gz`

## Customization

### Changing WSL Username
If your WSL username is not "levi", update paths in `tasks.json`:
- Replace `/home/levi/.local/bin/scons` with `/home/YOUR_USERNAME/.local/bin/scons`

### Changing Project Path
If your repository is not in `C:\Users\lsl\Repositories\hopnbop`, update:
- All `/mnt/c/Users/lsl/Repositories/hopnbop` paths in `tasks.json`

### Adding Custom Tasks
Edit `.vscode/tasks.json` and add new task objects following the existing patterns.

## VS Code Extensions (Recommended)

- **godot-tools** - GDScript language support and debugging
- **C/C++** - For GDExtension development
- **WSL** - For seamless WSL integration

## More Information

- [VSCode Tasks Documentation](https://code.visualstudio.com/docs/editor/tasks)
- [Godot VSCode Integration](https://docs.godotengine.org/en/stable/tutorials/editor/external_editor.html)
- [Project BUILD.md](../BUILD.md) - Detailed build instructions
