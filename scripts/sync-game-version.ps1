<#
.SYNOPSIS
    Pushes project.godot's config/version into the platform's
    per-game config as `display_version`, so the backend stops
    reporting a stale version.

.DESCRIPTION
    `version_check` returns the per-game config's display_version
    whenever the caller supplies a game_id (which every real client
    does — see runtime/version.go). NAKAMA_GAME_VERSION on the host
    is only the no-game_id fallback, so bumping that env var does
    NOT fix a stale version_check response.

    That per-game row is effectively hand-registered. A fuller
    mechanism was designed — scripts/sync-game-config.ps1 POSTs a
    whole game.yaml to `register_game` — but it never became
    operational: `game.yaml` has never existed in this repo, and the
    script was never wired into release.yml despite its header once
    claiming so. So the row was registered by hand once and nothing
    could move it: display_version drifted to 0.39.0 while
    project.godot reached 0.47.0. Nothing breaks (compatibility keys
    off protocol_version, and the client ignores the reported
    game_version) but every ops surface reporting the live version is
    wrong.

    This script is the narrow, safe half of that job: keep
    display_version derived from project.godot, and touch nothing
    else. If sync-game-config.ps1 is ever finished, this becomes
    redundant and should be folded into it.

    Read-modify-write, deliberately:

    `register_game` REPLACES the whole `config` blob. That blob holds
    matchmaker modes, allocator_mode, legal paths, local_image_ref,
    and edgegap_app_version. Sending a hand-built payload would wipe
    whatever isn't in it. Worse, edgegap_app_version / local_image_ref
    are bumped by the game-server deploy flow, so syncing them from a
    file in git could silently revert a newer server image. We
    therefore fetch the live config and patch exactly one field.

.PARAMETER DryRun
    Fetch and show the diff without writing.

.NOTES
    Needs NAKAMA_SERVER_KEY (anon auth; get_game_config requires a
    client session) and NAKAMA_HTTP_KEY (register_game is
    server-to-server) in ~/.hopnbop-migration/credentials.env.
#>

[CmdletBinding()]
param(
	[switch]$DryRun,
	[string]$GameId = 'hopnbop',
	[string]$NakamaUrl = 'https://nakama.snoringcat.games'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

# --- Desired version, straight from the single source of truth. ---
$versionLine = Select-String -Path "$repoRoot\project.godot" `
	-Pattern '^config/version="(.+)"$'
if (-not $versionLine) {
	throw "Couldn't read config/version from project.godot"
}
$target = $versionLine.Matches[0].Groups[1].Value
Write-Host "project.godot config/version: $target"

# --- Credentials. ---
$credPath = "$HOME\.hopnbop-migration\credentials.env"
if (-not (Test-Path $credPath)) { throw "missing $credPath" }
$lines = Get-Content $credPath
function Get-Cred($name) {
	$line = $lines | Where-Object { $_ -match "^$name=" } | Select-Object -First 1
	if (-not $line) { throw "$name not in $credPath" }
	return ($line -split '=', 2)[1].Trim()
}
$serverKey = Get-Cred 'NAKAMA_SERVER_KEY'
$httpKey = Get-Cred 'NAKAMA_HTTP_KEY'

# --- Read the live config (needs a client session). ---
$basic = [Convert]::ToBase64String(
	[Text.Encoding]::ASCII.GetBytes("${serverKey}:"))
$authBody = @{
	id   = "version-sync-$(Get-Random)"
	vars = @{ game_id = $GameId }
} | ConvertTo-Json -Compress
$auth = Invoke-RestMethod -Method Post `
	-Uri "$NakamaUrl/v2/account/authenticate/device?create=true" `
	-Headers @{ Authorization = "Basic $basic" } `
	-Body $authBody -ContentType 'application/json'

$live = Invoke-RestMethod -Method Post `
	-Uri "$NakamaUrl/v2/rpc/get_game_config?unwrap=true" `
	-Headers @{ Authorization = "Bearer $($auth.token)" } `
	-Body (@{ game_id = $GameId } | ConvertTo-Json -Compress) `
	-ContentType 'application/json'

$current = $live.display_version
Write-Host "live display_version:         $current"

if ($current -eq $target) {
	Write-Host "already in sync; nothing to do."
	exit 0
}

# --- Patch exactly one field on the verbatim live payload. ---
# $live.config is the raw registration payload (the `config` JSONB
# column), which is precisely what register_game expects back.
$config = $live.config
$config.display_version = $target

# Depth 20: the payload nests matchmaker_rules.modes[] a few levels
# down, and PowerShell silently truncates past -Depth, which would
# ship a mangled config to prod.
$payload = $config | ConvertTo-Json -Depth 20 -Compress

# Guard the round-trip: re-parse and confirm the fields we must not
# lose survived. ConvertFrom-Json -> ConvertTo-Json is not guaranteed
# faithful, and this write replaces live matchmaker config.
$check = $payload | ConvertFrom-Json
$problems = @()
if ($check.display_version -ne $target) { $problems += 'display_version did not apply' }
if ($check.matchmaker_rules.modes.Count -ne $live.config.matchmaker_rules.modes.Count) {
	$problems += "matchmaker modes count changed ($($live.config.matchmaker_rules.modes.Count) -> $($check.matchmaker_rules.modes.Count))"
}
if ($check.allocator_mode -ne $live.config.allocator_mode) { $problems += 'allocator_mode changed' }
if ($check.edgegap_app_version -ne $live.config.edgegap_app_version) { $problems += 'edgegap_app_version changed' }
if ($check.local_image_ref -ne $live.config.local_image_ref) { $problems += 'local_image_ref changed' }
if ($check.protocol_version -ne $live.config.protocol_version) { $problems += 'protocol_version changed' }
if ($problems.Count) {
	throw ("Refusing to write — round-trip altered fields it must not:`n  " +
		($problems -join "`n  "))
}

Write-Host "preserved: modes=$($check.matchmaker_rules.modes.Count) allocator=$($check.allocator_mode) edgegap=$($check.edgegap_app_version) protocol=$($check.protocol_version)"
Write-Host "display_version: $current -> $target"

if ($DryRun) {
	Write-Host "[DryRun] not writing."
	exit 0
}

# --- Write. ---
$null = Invoke-RestMethod -Method Post `
	-Uri "$NakamaUrl/v2/rpc/register_game?http_key=$httpKey&unwrap=true" `
	-Body $payload -ContentType 'application/json'

# --- Verify through the surface that was actually wrong. ---
$verify = Invoke-RestMethod -Method Post `
	-Uri "$NakamaUrl/v2/rpc/version_check?http_key=$httpKey&unwrap=true" `
	-Body (@{ game_id = $GameId } | ConvertTo-Json -Compress) `
	-ContentType 'application/json'
if ($verify.game_version -ne $target) {
	throw "register_game accepted but version_check still reports $($verify.game_version)"
}
Write-Host "OK: version_check now reports $($verify.game_version)"
Write-Host "     modes=$($verify.matchmaker_modes.Count) protocol=$($verify.protocol_version)"
