# GitHub Actions Testing Debug Guide

## Current Issues and Solutions

### Problem Summary
The GitHub Actions testing is failing due to:
1. **GUT class imports not available** - Godot needs to import class definitions first
2. **Missing asset files** - CI doesn't have .godot/imported/ cache
3. **Scaffolder framework dependencies** - Project uses custom Scaffolder classes
4. **Autoload dependency chain** - Global.gd depends on Settings which depends on assets

### Solutions Implemented

#### 1. Updated GitHub Actions Workflow (.github/workflows/test.yml)
- Added proper project import step with `--import --quit`
- Made tests continue-on-error to collect diagnostics
- Added comprehensive logging and error reporting
- Extended timeouts for import process

#### 2. Created Test Infrastructure
- `test/helpers/test_settings.gd` - Minimal settings for CI
- `test/unit/core/test_framework_basic.gd` - Basic framework validation
- `test/minimal_test_scene.tscn` - Minimal scene for testing

#### 3. Expected Behavior in CI
The workflow now:
- Downloads Godot 4.5.1
- Attempts project import (will show errors but continue)
- Runs tests with error handling
- Captures detailed logs for debugging
- Shows test results even if errors occur

### What You Should See Next
1. **Import Phase**: Errors about missing assets and GUT classes (normal in CI)
2. **Test Phase**: Tests may run despite import errors
3. **Results**: Detailed logs showing exactly what succeeded/failed

### If Tests Still Fail
The logs will now show:
- Import process details
- Test execution logs
- File system state
- Specific error messages

Use this information to identify remaining issues such as:
- Missing class dependencies
- Asset path problems
- Project configuration issues

### Local Testing
To test locally:
```bash
godot --headless --import --quit
godot --headless --path . addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit
```
