#!/usr/bin/env pwsh
# Sync this game's `game.yaml` into the snoringcat-platform
# Nakama runtime's `games` Postgres table.
#
# The runtime exposes an operator-only `register_game` RPC that
# upserts the row and refreshes its in-process cache. It needs two
# keys: NAKAMA_HTTP_KEY (Nakama's runtime HTTP key) and
# GAME_ADMIN_KEY (sent as the `admin_key` query parameter). The
# HTTP key alone used to be enough, but it shipped in client builds
# up to 0.47.0, so anyone could have replaced the live config. This
# script parses game.yaml, converts to JSON, and POSTs it. It never
# prints either key.
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
# Before registering, it pulls `local_image_ref` onto the Nakama host
# (allocator_mode local or hybrid). The local allocator starts game
# servers through the Docker Engine API, which never pulls, and a
# failed local allocation fails the match outright (no Edgegap
# fallback). So a config naming a tag the host lacks fails every match
# routed local until someone pulls by hand. The pull needs the
# operator's SSH key; CI has none, so release.yml passes -SkipImagePull.
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
    # The runtime's GAME_ADMIN_KEY. deploy-cf-pages.ps1 loads it from
    # credentials.env; release.yml passes the GAME_ADMIN_KEY secret.
    # A loopback stack falls back to the dev stack's fixed value.
    [string]$AdminKey = $env:GAME_ADMIN_KEY,
    [switch]$DryRun,
    # Register without pulling local_image_ref on the host first. Only
    # for callers that cannot SSH to it (CI); pull it there by hand.
    [switch]$SkipImagePull
)

$ErrorActionPreference = "Stop"

# infra/dev/config.dev.yml starts the local stack with this
# GAME_ADMIN_KEY. Like the stack's other placeholder keys it is not a
# secret: the stack listens only on 127.0.0.1.
$DevStackAdminKey = "defaultadminkey"

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

# See the header: the host must have the image before the config names it.
$imageRef = "$($config['local_image_ref'])"
$needsPull = ($config['allocator_mode'] -in @("local", "hybrid")) -and $imageRef
$hostName = ([Uri]$NakamaHost).Host
$isLocalStack = $hostName -in @("localhost", "127.0.0.1", "::1")

if ($DryRun) {
    if ($needsPull -and -not $isLocalStack -and -not $SkipImagePull) {
        Write-Host "[DryRun] would first docker pull $imageRef on $hostName"
    }
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

$AdminKey = "$AdminKey".Trim()
if (-not $AdminKey -and $isLocalStack) {
    $AdminKey = $DevStackAdminKey
}
if (-not $AdminKey) {
    Write-Error @"
GAME_ADMIN_KEY is required to register with $hostName (or pass
-AdminKey).

register_game refuses calls that carry only the HTTP key. The value
must match GAME_ADMIN_KEY in the Nakama container's environment
(/opt/nakama/.env, rendered from credentials.env by
third_party/snoringcat-platform/scripts/lib/nakama-env.ps1).

Load it the way deploy-cf-pages.ps1 does, by reading
~/.hopnbop-migration/credentials.env into the environment, or set
`$env:GAME_ADMIN_KEY yourself. CI passes the GAME_ADMIN_KEY secret.
"@
    exit 2
}

if ($needsPull -and $isLocalStack) {
    Write-Host "Local stack ($hostName): skipping the host image pull."
} elseif ($needsPull -and $SkipImagePull) {
    Write-Warning ("-SkipImagePull: not pulling $imageRef on $hostName. " +
        "Every match the local allocator takes fails until it is there.")
} elseif ($needsPull) {
    $sshKey = Join-Path $HOME ".hopnbop-migration/ssh/nakama"
    $knownHosts = Join-Path $HOME "Repositories/claude-config/jobs/known_hosts"
    foreach ($required in @($sshKey, $knownHosts)) {
        if (-not (Test-Path $required)) {
            Write-Error ("Can't pull $imageRef on ${hostName}: $required is " +
                "missing. Pull it there by hand, then re-run with -SkipImagePull.")
            exit 2
        }
    }
    Write-Host "docker pull $imageRef on $hostName"
    $PSNativeCommandUseErrorActionPreference = $false
    & ssh -i $sshKey `
        -o StrictHostKeyChecking=yes `
        -o "UserKnownHostsFile=$knownHosts" `
        -o BatchMode=yes `
        -o ConnectTimeout=15 `
        "root@$hostName" "docker pull -q '$imageRef'"
    if ($LASTEXITCODE -ne 0) {
        Write-Error ("docker pull failed on $hostName (exit $LASTEXITCODE). " +
            "Not registering a config that names an image the host lacks.")
        exit 1
    }
}

# Print a template of the URI, never the URI itself. Replacing the
# raw keys in the real URI can't redact them: they appear there
# percent-encoded (a base64 key's /, + and = are escaped), so a
# String.Replace of the raw value matches nothing and prints the key.
# That is how this line used to print the HTTP key in cleartext.
$rpcPath = "/v2/rpc/register_game"
$uri = "$NakamaHost$rpcPath" +
    "?http_key=$([Uri]::EscapeDataString($HttpKey))" +
    "&admin_key=$([Uri]::EscapeDataString($AdminKey))" +
    "&unwrap=true"

Write-Host ("POST $NakamaHost$rpcPath" +
    "?http_key=<redacted>&admin_key=<redacted>&unwrap=true")
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
        } elseif ($errBody -match "GAME_ADMIN_KEY is not set") {
            Write-Host ""
            Write-Host "Diagnosis: the runtime has no GAME_ADMIN_KEY,"
            Write-Host "so register_game refuses every call. Add it to"
            Write-Host "credentials.env, re-render /opt/nakama/.env"
            Write-Host "(phase-b.ps1 -StartAt NakamaStack -StopAt"
            Write-Host "NakamaStack) and recreate the nakama container."
        } elseif ($errBody -match "admin_key") {
            Write-Host ""
            Write-Host "Diagnosis: admin key missing or wrong. Verify"
            Write-Host "GAME_ADMIN_KEY matches the value in the live"
            Write-Host "container's environment."
        }
    }
    exit 1
}

Write-Host ""
Write-Host "=== register_game response ==="
$response | ConvertTo-Json -Depth 5

# Explicit success exit — do not remove.
#
# `& script.ps1` does NOT reset $LASTEXITCODE when the script returns
# normally; it leaves whatever the last native command set, and it is
# $null in a fresh session. Callers therefore cannot distinguish
# "succeeded" from "left a stale 2 lying around", and `if
# ($LASTEXITCODE -ne 0)` is true for $null. Both callers
# (deploy-cf-pages.ps1 and release.yml) gate on $LASTEXITCODE, so
# without this they'd report a false failure on a clean sync.
exit 0
