# Bridge the snoringcat-platform addon from the submodule into
# the project's addons/ directory so Godot can find it at
# res://addons/snoringcat_platform_client/.
#
# We COPY rather than junction because Godot 4.6 reads stale
# parser-cache content through directory junctions on Windows.
# Junctions also caused PowerShell Copy-Item to walk the file
# tree recursively forever in early experiments.
#
# Run once after cloning the repo (or after a fresh
# `git submodule update --init --recursive`), and again any
# time you bump the snoringcat-platform submodule pointer.
#
# This is idempotent: re-running just refreshes the copy.

param(
    [switch]$Force
)

$ErrorActionPreference = "Continue"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
Set-Location $RepoRoot

$Source = "third_party\snoringcat-platform\addons\snoringcat_platform_client"
$Dest   = "addons\snoringcat_platform_client"

Write-Host "=== Platform addon setup ===" -ForegroundColor Cyan
Write-Host "Source: $Source"
Write-Host "Dest:   $Dest"
Write-Host ""

if (-not (Test-Path $Source)) {
    Write-Error "Submodule source not found: $Source"
    Write-Error "Run: git submodule update --init --recursive"
    exit 1
}

# If a directory exists at $Dest, drop it. cmd's rmdir handles
# both real directories and lingering junctions cleanly.
if (Test-Path $Dest) {
    Write-Host "Removing existing $Dest..." -ForegroundColor Yellow
    cmd /c "rmdir /S /Q `"$Dest`""
}

# xcopy from cmd: PowerShell's Copy-Item misbehaves with the
# reparse points sometimes left behind from prior junction-based
# bridges.
Write-Host "Copying addon files..." -ForegroundColor Yellow
cmd /c "xcopy /E /I /Y /Q `"$Source`" `"$Dest`""
if ($LASTEXITCODE -ne 0) {
    Write-Error "xcopy failed (exit $LASTEXITCODE)"
    exit 1
}
Write-Host "Done." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  - Open the project in Godot (or run --import) to"
Write-Host "    refresh the .godot/ caches with the new files."
Write-Host "  - To verify end-to-end, run:"
Write-Host "      godot --headless --path . -s third_party/snoringcat-platform/scripts/platform_smoke_test.gd"
