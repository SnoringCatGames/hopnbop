#!/usr/bin/env pwsh
# Local end-to-end smoke test.
#
# Brings up the dev stack at `infra/dev/docker-compose.dev.yml`
# (Nakama + Postgres with EDGEGAP_MOCK_DEPLOY=true), registers
# hopnbop's game.yaml, runs the compliance suite against the
# local Nakama, and tears the stack down.
#
# Stage 8.30 of MULTI_GAME_ROADMAP.md.
#
# Usage:
#   pwsh scripts/local-smoke-test.ps1
#   pwsh scripts/local-smoke-test.ps1 -SkipBuild           # reuse existing snoringcat.so
#   pwsh scripts/local-smoke-test.ps1 -KeepStack           # leave compose up after run
#   pwsh scripts/local-smoke-test.ps1 -TestFile test_friends.gd
#
# Exit codes:
#   0 — every compliance test passed
#   1 — one or more compliance tests failed
#   2 — stack failed to come up (Docker / build / migrate)
#   3 — game registration RPC failed
#
# Prereqs:
#   - Docker Desktop running (Linux containers).
#   - Godot 4.5+ on PATH.
#   - `git submodule update --init --recursive` has run.

[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$KeepStack,
    # Run only the named compliance test file (relative path
    # under `addons/snoringcat_platform_client/test/compliance/`).
    # Example: -TestFile test_friends.gd. Omit to run the full
    # compliance directory.
    [string]$TestFile = "",
    [int]$NakamaReadyTimeoutSec = 90
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
Set-Location $RepoRoot

$ComposeFile = "infra/dev/docker-compose.dev.yml"
$RuntimeDir  = "third_party/snoringcat-platform/runtime"
$PluginPath  = "$RuntimeDir/build/snoringcat.so"
$ComplianceDir = "res://addons/snoringcat_platform_client/test/compliance"

$NakamaUrl     = "http://127.0.0.1:7350"
$HttpKey       = "defaulthttpkey"
$ServerKey     = "defaultkey"

function Write-Step($Msg) {
    Write-Host ""
    Write-Host "=== $Msg ===" -ForegroundColor Cyan
}

function Invoke-Teardown {
    if ($KeepStack) {
        Write-Host ""
        Write-Host "Leaving stack up (-KeepStack)." -ForegroundColor Yellow
        Write-Host "Tear down later with:" -ForegroundColor Yellow
        Write-Host "  docker compose -f $ComposeFile down -v"
        return
    }
    Write-Step "Tearing down dev stack"
    # `down -v` drops the Postgres volume so the next run starts
    # from a fresh schema. Stack failures should still tear down
    # to free the ports.
    & docker compose -f $ComposeFile down -v 2>&1 | Out-Host
}

# --- Step 0: refresh the platform addon copy ---------------
# Ensures the compliance suite under res://addons/... reflects
# the current snoringcat-platform submodule, not whatever was
# copied at last `git pull`.
Write-Step "Refresh platform addon"
& pwsh -NoProfile -File scripts/setup-platform-addon.ps1
if ($LASTEXITCODE -ne 0) {
    Write-Error "setup-platform-addon.ps1 failed (exit $LASTEXITCODE)"
    exit 2
}

# --- Step 1: build the runtime plugin ----------------------
# Skipped only when -SkipBuild is set AND the plugin already
# exists. A missing plugin always forces a build (otherwise the
# compose-up below would silently no-op the matchmaker hook).
if ($SkipBuild -and (Test-Path $PluginPath)) {
    Write-Step "Plugin build SKIPPED (-SkipBuild, existing $PluginPath)"
} else {
    Write-Step "Build runtime plugin"
    Push-Location $RuntimeDir
    try {
        # The plugin's Linux .so target requires Docker even on
        # a Windows dev box. Same image as `nakama-runtime.yml`.
        $cwd = (Get-Location).Path -replace '\\', '/'
        & docker run --rm -v "${cwd}:/backend" -w /backend `
            heroiclabs/nakama-pluginbuilder:3.25.0 `
            build -buildmode=plugin -trimpath `
            -o ./build/snoringcat.so .
        if ($LASTEXITCODE -ne 0) {
            throw "pluginbuilder failed (exit $LASTEXITCODE)"
        }
    } finally {
        Pop-Location
    }
    if (-not (Test-Path $PluginPath)) {
        Write-Error "Build reported success but $PluginPath is missing."
        exit 2
    }
}

# --- Step 2: bring up the dev stack ------------------------
# `--remove-orphans` swallows stale containers left from a
# crashed previous run (especially after a Ctrl+C during
# `migrate up`). `-d` so we can poll healthcheck below.
Write-Step "Start dev stack"
& docker compose -f $ComposeFile up -d --remove-orphans
if ($LASTEXITCODE -ne 0) {
    Write-Error "docker compose up failed (exit $LASTEXITCODE)"
    Invoke-Teardown
    exit 2
}

# --- Step 3: wait for Nakama healthcheck -------------------
Write-Step "Wait for Nakama"
$deadline = (Get-Date).AddSeconds($NakamaReadyTimeoutSec)
$ready = $false
while ((Get-Date) -lt $deadline) {
    try {
        $resp = Invoke-WebRequest -Uri "$NakamaUrl/healthcheck" `
            -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        if ($resp.StatusCode -eq 200) { $ready = $true; break }
    } catch {
        # connection refused / 5xx during boot; expected for the
        # first 10-30s while Postgres + migrate up run.
    }
    Start-Sleep -Seconds 2
}
if (-not $ready) {
    Write-Error "Nakama did not respond healthy within ${NakamaReadyTimeoutSec}s"
    Write-Host "Container logs:" -ForegroundColor Yellow
    & docker compose -f $ComposeFile logs --tail=80 nakama 2>&1 | Out-Host
    Invoke-Teardown
    exit 2
}
Write-Host "Nakama healthy at $NakamaUrl"

# --- Step 4: register hopnbop's game.yaml ------------------
# The runtime's BeforeAuthenticate* hooks reject any login that
# doesn't carry a recognized game_id (Stage 2.5). Compliance
# tests sign in with `game_id=hopnbop`, so we have to seed the
# row before the suite runs.
Write-Step "Register game.yaml"
& pwsh -NoProfile -File scripts/sync-game-config.ps1 `
    -NakamaHost $NakamaUrl `
    -HttpKey $HttpKey
if ($LASTEXITCODE -ne 0) {
    Write-Error "sync-game-config.ps1 failed (exit $LASTEXITCODE)"
    Invoke-Teardown
    exit 3
}

# --- Step 5: run the compliance suite ----------------------
Write-Step "Run compliance suite"

# Compliance tests read these from the environment. The keys
# match the hardcoded values in `docker-compose.dev.yml`.
$env:PLATFORM_API_URL    = $NakamaUrl
$env:NAKAMA_SERVER_KEY   = $ServerKey
$env:NAKAMA_HTTP_KEY     = $HttpKey
$env:EDGEGAP_MOCK_DEPLOY = "true"
# Force `live` mode (default but explicit). Mock-mode HTTP
# interception is a future track.
$env:PLATFORM_COMPLIANCE_MODE = "live"

# Drive GUT from the cmdline. -gexit is required for the exit
# code to reflect pass/fail. Per the project's CLAUDE.md
# "Project-Specific Testing Notes", -gdir works for the
# compliance directory specifically (unlike the wider test/
# tree where per-file invocation is more reliable).
$gutArgs = @(
    "--headless",
    "-s",
    "--path", ".",
    "addons/gut/gut_cmdln.gd",
    "-gexit"
)
if ($TestFile) {
    $gutArgs += "-gtest=$ComplianceDir/$TestFile"
} else {
    $gutArgs += "-gdir=$ComplianceDir"
}

& godot @gutArgs
$gutExit = $LASTEXITCODE

# --- Step 6: tear down (unless -KeepStack) -----------------
Invoke-Teardown

if ($gutExit -ne 0) {
    Write-Host ""
    Write-Host "Compliance suite reported failures (gut exit $gutExit)." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "OK: local smoke clean." -ForegroundColor Green
exit 0
