# Test Setup Guide

## Quick Start

### 1. Enable GUT Plugin

1. Open the project in Godot Editor
2. Go to `Project` → `Project Settings` → `Plugins`
3. Find "Gut" in the list
4. Check the "Enable" checkbox
5. Click "Close"
6. Restart the Godot Editor

### 2. Verify Installation

After restarting, you should see:
- A "GUT" panel in the bottom dock (next to Output, Debugger, etc.)
- The GUT panel should show the test directory structure

### 3. Run Your First Test

1. Open the GUT panel
2. In the directory tree, navigate to `res://test/unit/scaffolder/`
3. Select `test_circular_buffer.gd`
4. Click "Run All" button
5. You should see green checkmarks indicating all tests passed

### 4. Verify Command Line Testing

Open a terminal in the project directory and run:

```bash
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gdir=res://test/unit/scaffolder \
  -gtest=res://test/unit/scaffolder/test_circular_buffer.gd \
  -gexit
```

You should see output showing tests running and passing, with exit code 0.

## Troubleshooting

### Plugin Not Appearing

If the GUT plugin doesn't appear in the Plugins list:
1. Verify `addons/gut/` directory exists
2. Verify `addons/gut/plugin.cfg` exists
3. Try closing and reopening the project

### GUT Panel Not Showing

If the GUT panel doesn't appear after enabling:
1. Go to `Editor` → `Editor Settings` → `Plugins`
2. Verify GUT is enabled
3. Restart Godot completely
4. Check the bottom dock tabs for "GUT"

### Tests Not Discovered

If tests don't appear in the GUT panel:
1. Verify test files start with `test_` prefix
2. Verify test files extend `GutTest`
3. Check `.gutconfig.json` has correct directories
4. Try refreshing the GUT panel (click refresh button)

### Command Line Tests Fail to Run

If command line execution fails:
1. Verify Godot is in your PATH or use full path to executable
2. Check that `.gutconfig.json` exists
3. Verify test paths use `res://` prefix

### ArrayPool Errors

If you see errors related to ArrayPool in tests:
1. Make sure `ArrayPool.clear_all_pools()` is called in `before_each()`
2. Make sure `ArrayPool.clear_all_pools()` is called in `after_each()`

## Next Steps

Once setup is complete, see [README.md](README.md) for:
- How to run different types of tests
- How to write new tests
- Test coverage information
- CI/CD integration details
