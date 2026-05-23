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

$Source = "third_party/snoringcat-platform/addons/snoringcat_platform_client"
$Dest   = "addons/snoringcat_platform_client"

# $IsWindows is $null on Windows PowerShell 5.1 (which is
# Windows-only by definition); default to true in that case.
$IsWin = if ($null -eq $IsWindows) { $true } else { $IsWindows }

Write-Host "=== Platform addon setup ===" -ForegroundColor Cyan
Write-Host "Source: $Source"
Write-Host "Dest:   $Dest"
Write-Host ""

if (-not (Test-Path $Source)) {
    Write-Error "Submodule source not found: $Source"
    Write-Error "Run: git submodule update --init --recursive"
    exit 1
}

if (Test-Path $Dest) {
    Write-Host "Removing existing $Dest..." -ForegroundColor Yellow
    if ($IsWin) {
        # cmd's rmdir handles both real directories AND
        # lingering junctions/reparse points from prior
        # junction-based bridges that Remove-Item can't.
        cmd /c "rmdir /S /Q `"$($Dest -replace '/', '\')`""
    } else {
        Remove-Item -Recurse -Force -Path $Dest
    }
}

Write-Host "Copying addon files..." -ForegroundColor Yellow
if ($IsWin) {
    # xcopy: PowerShell's Copy-Item misbehaves with the
    # reparse points sometimes left behind from prior
    # junction-based bridges on Windows. xcopy works through
    # them.
    $SourceWin = $Source -replace '/', '\'
    $DestWin = $Dest -replace '/', '\'
    cmd /c "xcopy /E /I /Y /Q `"$SourceWin`" `"$DestWin`""
    if ($LASTEXITCODE -ne 0) {
        Write-Error "xcopy failed (exit $LASTEXITCODE)"
        exit 1
    }
} else {
    # Linux/macOS: no junctions or reparse points to worry
    # about. The CI runner takes this path.
    & cp -r $Source $Dest
    if ($LASTEXITCODE -ne 0) {
        Write-Error "cp failed (exit $LASTEXITCODE)"
        exit 1
    }
}
Write-Host "Done." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  - Open the project in Godot (or run --import) to"
Write-Host "    refresh the .godot/ caches with the new files."
Write-Host "  - To verify end-to-end, run:"
Write-Host "      godot --headless --path . -s third_party/snoringcat-platform/scripts/platform_smoke_test.gd"
