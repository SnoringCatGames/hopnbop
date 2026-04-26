# Creates a directory junction so Godot can find the platform
# client addon at res://addons/snoringcat_platform_client/.
#
# The canonical source lives in the snoringcat-platform git
# submodule under third_party/snoringcat-platform/. This script
# bridges that path into addons/ where Godot expects to find
# plugins.
#
# Run once after cloning the repo (or after a fresh
# git submodule update --init --recursive).
#
# To remove the junction without deleting the underlying files
# use cmd's `rmdir`:
#   cmd /c "rmdir addons\snoringcat_platform_client"
# (PowerShell's Remove-Item / Copy-Item misbehave on junctions
# in NonInteractive mode.)
#
# WARNING (2026-04-26): Godot 4.6 reads stale content through
# the junction (parser line numbers and class_name lookups
# don't match the on-disk file). The cause is unclear; possibly
# Godot caches file handles via the reparse point. Until
# resolved, prefer either: (a) re-clone or recopy the addon
# files into addons/snoringcat_platform_client/ before each
# Godot run, or (b) restructure the integration so Godot reads
# the addon files from a non-junctioned path. Tracked as a
# Phase 2 follow-up.

param(
    [switch]$Force
)

$ErrorActionPreference = "Continue"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
Set-Location $RepoRoot

$LinkPath   = "addons\snoringcat_platform_client"
$TargetPath = "third_party\snoringcat-platform\addons\snoringcat_platform_client"

Write-Host "=== Platform addon junction setup ===" -ForegroundColor Cyan
Write-Host "Repo:    $RepoRoot"
Write-Host "Link:    $LinkPath"
Write-Host "Target:  $TargetPath"
Write-Host ""

if (-not (Test-Path $TargetPath)) {
    Write-Error "Submodule target not found: $TargetPath"
    Write-Error "Run: git submodule update --init --recursive"
    exit 1
}

if (Test-Path $LinkPath) {
    $existing = Get-Item $LinkPath
    if ($existing.LinkType -eq "Junction") {
        if (-not $Force) {
            Write-Host "Junction already exists. Pass -Force to recreate." -ForegroundColor DarkGray
            exit 0
        }
        Write-Host "Removing existing junction..." -ForegroundColor Yellow
        Remove-Item -Path $LinkPath -Force
    } else {
        Write-Error "Path exists and is NOT a junction: $LinkPath"
        Write-Error "Refusing to clobber. Move it aside or delete it first."
        exit 1
    }
}

New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath | Out-Null
Write-Host "Junction created." -ForegroundColor Green
Write-Host ""
Write-Host "Verify: `n  Get-Item $LinkPath | Format-List Name,Target,LinkType"
