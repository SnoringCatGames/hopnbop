#!/usr/bin/env pwsh
# Sync this game's `game.yaml` into the snoringcat-platform
# Nakama runtime's `games` Postgres table.
#
# The runtime exposes a server-to-server `register_game` RPC
# (gated by NAKAMA_HTTP_KEY) that upserts the row and refreshes
# its in-process cache. This script parses game.yaml, converts
# to JSON, and POSTs it.
#
# Version fields are NOT read from game.yaml. `protocol_version` and
# `display_version` are injected here from project.godot, which is
# the single source of truth for both (CLAUDE.md "Version
# Management"). game.yaml used to duplicate them; display_version
# drifted to 0.39.0 against a 0.47.0 client because nothing guarded
# it, so the drift is now structurally impossible instead of policed.
#
# Everything else — including edgegap_app_version and
# local_image_ref — comes from game.yaml verbatim. game.yaml is
# genuinely their source of truth: game-server.yml pushes the image
# tag but never writes them back, so nothing else can clobber them.
#
# When to run:
#   - The web deploy (scripts/deploy-cf-pages.ps1) calls this.
#   - Standalone after a server-only deploy that bumped
#     edgegap_app_version / local_image_ref in game.yaml.
#   - Any time game.yaml changes. The runtime's cache is in-process
#     and lost on container restart; the Postgres row is durable, so
#     re-running is cheap and idempotent.
#
# Usage:
#   pwsh scripts/sync-game-config.ps1
#   pwsh scripts/sync-game-config.ps1 -DryRun
#   pwsh scripts/sync-game-config.ps1 -NakamaHost https://nakama-staging.snoringcat.games

[CmdletBinding()]
param(
    [string]$GameYamlPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "game.yaml"),
    [string]$NakamaHost = "https://nakama.snoringcat.games",
    [string]$HttpKey = $env:NAKAMA_HTTP_KEY,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $GameYamlPath)) {
    Write-Error "game.yaml not found at: $GameYamlPath"
    exit 2
}

# powershell-yaml is the de-facto YAML library for pwsh. Install
# on demand into CurrentUser scope so the script is portable to
# CI runners (ubuntu-latest's pwsh has PSGallery preconfigured)
# without a prereq install step.
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Write-Host "Installing powershell-yaml module (CurrentUser scope)..."
    Install-Module -Name powershell-yaml `
        -Scope CurrentUser -Force -AllowClobber | Out-Null
}
Import-Module powershell-yaml -ErrorAction Stop

Write-Host "Parsing $GameYamlPath"
$yamlText = Get-Content -Path $GameYamlPath -Raw
$config = ConvertFrom-Yaml $yamlText

# game.yaml must NOT carry the derived version fields. If someone
# re-adds them, fail loudly rather than silently letting a stale
# literal win over project.godot — that is the exact failure this
# design removes.
foreach ($derived in @("protocol_version", "display_version")) {
    if ($config.ContainsKey($derived)) {
        Write-Error @"
game.yaml must not define $derived — it is injected from
project.godot at sync time. Remove it from game.yaml and bump it in
project.godot instead. See "WHO OWNS WHAT" at the top of game.yaml.
"@
        exit 2
    }
}

# Inject the versions from project.godot (single source of truth).
$projectGodot = Join-Path `
    (Split-Path -Parent $PSScriptRoot) "project.godot"
if (-not (Test-Path $projectGodot)) {
    Write-Error "project.godot not found at: $projectGodot"
    exit 2
}
$protoLine = Select-String -Path $projectGodot `
    -Pattern '^config/protocol_version\s*=\s*(\d+)'
if (-not $protoLine) {
    Write-Error "could not read config/protocol_version from project.godot"
    exit 2
}
$verLine = Select-String -Path $projectGodot `
    -Pattern '^config/version="(.+)"$'
if (-not $verLine) {
    Write-Error "could not read config/version from project.godot"
    exit 2
}
$config["protocol_version"] = [int]$protoLine.Matches[0].Groups[1].Value
$config["display_version"] = $verLine.Matches[0].Groups[1].Value
Write-Host ("injected from project.godot: protocol_version=" +
    "$($config['protocol_version']) display_version=" +
    "$($config['display_version'])")

# Required-field sanity check, post-injection. The runtime validates
# the same fields server-side, but catching it locally gives a
# clearer error in CI logs.
$required = @(
    "schema_version", "game_id", "display_name",
    "edgegap_app_slug", "protocol_version", "display_version"
)
foreach ($field in $required) {
    if (-not $config.ContainsKey($field) -or
            $null -eq $config[$field] -or
            "$($config[$field])" -eq "") {
        Write-Error "resolved config is missing required field: $field"
        exit 2
    }
}

# register_game REPLACES the whole config blob, so a field missing
# from this payload is a field deleted from production. Guard the
# fields whose loss would break live matchmaking or allocation.
$mustSurvive = @(
    "matchmaker_rules", "allocator_mode", "edgegap_app_slug",
    "transports", "ports", "legal", "leaderboards", "auth_providers"
)
$missing = $mustSurvive | Where-Object { -not $config.ContainsKey($_) }
if ($missing) {
    Write-Error @"
Refusing to POST — game.yaml is missing field(s) that register_game
would then delete from the live config: $($missing -join ', ')
"@
    exit 2
}

$json = $config | ConvertTo-Json -Depth 20 -Compress
Write-Host ""
Write-Host "=== resolved game config ==="
$config | ConvertTo-Json -Depth 20
Write-Host ""

if ($DryRun) {
    Write-Host "[DryRun] not POSTing. JSON payload would be:"
    Write-Host $json
    exit 0
}

if (-not $HttpKey) {
    Write-Error @"
NAKAMA_HTTP_KEY is required (or pass -HttpKey).

The key is the same value Nakama is started with via
--runtime.http_key in
third_party/snoringcat-platform/infra/remote/nakama/
docker-compose.yml.

Set it via:
  `$env:NAKAMA_HTTP_KEY = (Get-Content ~/.hopnbop-migration/credentials.env |
      Select-String '^NAKAMA_HTTP_KEY=' | ForEach-Object {
          (`$_ -split '=',2)[1] })

Or pass inline:
  pwsh scripts/sync-game-config.ps1 -HttpKey '...'
"@
    exit 2
}

$uri = "$NakamaHost/v2/rpc/register_game" +
    "?http_key=$([Uri]::EscapeDataString($HttpKey))" +
    "&unwrap=true"

Write-Host "POST $($uri.Replace($HttpKey, '<redacted>'))"
try {
    $response = Invoke-RestMethod `
        -Method POST `
        -Uri $uri `
        -ContentType "application/json" `
        -Body $json
} catch {
    Write-Host "RPC call failed: $($_.Exception.Message)"
    if ($_.Exception.Response) {
        $errStream = $_.Exception.Response.GetResponseStream()
        $errReader = [System.IO.StreamReader]::new($errStream)
        $errBody = $errReader.ReadToEnd()
        Write-Host "Response body: $errBody"

        if ($errBody -match "function not found") {
            Write-Host ""
            Write-Host "Diagnosis: register_game RPC isn't"
            Write-Host "registered on the live runtime. Either"
            Write-Host "the plugin predates Stage 2 (push a"
            Write-Host "runtime change to snoringcat-platform/main"
            Write-Host "to trigger the nakama-runtime workflow)"
            Write-Host "or the plugin failed to load."
        } elseif ($errBody -match "invalid http key") {
            Write-Host ""
            Write-Host "Diagnosis: HTTP key mismatch. Verify"
            Write-Host "NAKAMA_HTTP_KEY matches the live"
            Write-Host "container's --runtime.http_key."
        }
    }
    exit 1
}

Write-Host ""
Write-Host "=== register_game response ==="
$response | ConvertTo-Json -Depth 5
