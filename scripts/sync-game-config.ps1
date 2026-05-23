#!/usr/bin/env pwsh
# Sync this game's `game.yaml` into the snoringcat-platform
# Nakama runtime's `games` Postgres table.
#
# The runtime exposes a server-to-server `register_game` RPC
# (gated by NAKAMA_HTTP_KEY) that upserts the row and refreshes
# its in-process cache. This script parses game.yaml, converts
# to JSON, and POSTs it.
#
# When to run:
#   - After every runtime redeploy that bumped game.yaml content
#     (since the cache is in-process and lost on container
#     restart, the row in Postgres is the durable source — but
#     no harm in re-running on every deploy).
#   - Wired into release.yml so a tagged release syncs config
#     automatically.
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

# Required-field sanity check before we POST. The runtime
# validates the same fields server-side, but catching it locally
# gives a clearer error in CI logs.
$required = @(
    "schema_version", "game_id", "display_name",
    "edgegap_app_slug", "protocol_version", "display_version"
)
foreach ($field in $required) {
    if (-not $config.ContainsKey($field) -or
            $null -eq $config[$field] -or
            "$($config[$field])" -eq "") {
        Write-Error "game.yaml is missing required field: $field"
        exit 2
    }
}

# protocol_version-vs-project.godot cross-check. CI also enforces
# this independently (pr-validate.yml), but doing it here means a
# manual `sync-game-config.ps1` run flags drift too.
$projectGodot = Join-Path `
    (Split-Path -Parent $PSScriptRoot) "project.godot"
if (Test-Path $projectGodot) {
    $protoLine = Select-String -Path $projectGodot `
        -Pattern '^config/protocol_version\s*=\s*(\d+)' `
        -ErrorAction SilentlyContinue
    if ($protoLine) {
        $projectProto = [int]$protoLine.Matches[0].Groups[1].Value
        $yamlProto = [int]$config["protocol_version"]
        if ($projectProto -ne $yamlProto) {
            Write-Error @"
protocol_version mismatch:
  game.yaml          = $yamlProto
  project.godot      = $projectProto
Both must match. Bump whichever is behind, then re-run.
"@
            exit 2
        }
    }
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
