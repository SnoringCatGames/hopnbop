# H37 exec-b: a local Nakama dev stack WITHOUT local-smoke-test.ps1's
# addon refresh and --import (the audit reserves --import for exec-a).
# Follows infra/dev/README.md "Manual usage" steps 1-4 and 6.
# Loopback only. The keys are the dev stack's public fixed values.
#   pwsh stack.ps1 -Action Up     # build plugin, compose up, wait, register
#   pwsh stack.ps1 -Action Down   # compose down -v for the recorded project
param(
    [ValidateSet('Up', 'Down', 'Logs')] [string]$Action = 'Up',
    [string]$Project = 'h37execb',
    [string]$LogFilter = ''
)
$ErrorActionPreference = 'Stop'
$repo = 'C:\Users\lsl\Repositories\hopnbop'
$here = Join-Path $repo '.claude\probes\H37\h37-exec-b'
$stackDir = Join-Path $here 'stack'
$pluginDir = Join-Path $stackDir 'plugin'
$compose = Join-Path $repo 'infra\dev\docker-compose.dev.yml'
$runtime = Join-Path $repo 'third_party\snoringcat-platform\runtime'
$stateFile = Join-Path $stackDir 'stack.json'
New-Item -ItemType Directory -Force $pluginDir | Out-Null

function DockerPath([string]$p) { ([System.IO.Path]::GetFullPath($p)) -replace '\\', '/' }
function FreePort {
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $l.Start(); $p = $l.LocalEndpoint.Port; $l.Stop(); return $p
}

if ($Action -eq 'Down') {
    & docker compose -p $Project -f $compose down -v --remove-orphans 2>&1 |
        Select-Object -Last 5
    "down exit=$LASTEXITCODE"
    return
}
if ($Action -eq 'Logs') {
    $lines = & docker compose -p $Project -f $compose logs --no-color nakama 2>&1
    if ($LogFilter) { $lines = $lines | Select-String -Pattern $LogFilter }
    $lines | Select-Object -Last 60 | ForEach-Object {
        $s = "$_"; $s.Substring(0, [Math]::Min(260, $s.Length)) }
    return
}

$t0 = Get-Date
$tag = (Select-String -Path $compose -Pattern '^\s*image:\s*heroiclabs/nakama:(\S+)' |
    Select-Object -First 1).Matches[0].Groups[1].Value
"[$(Get-Date -Format HH:mm:ss)] build plugin (pluginbuilder:$tag)"
& docker run --rm -v "$(DockerPath $runtime):/backend:ro" -v "$(DockerPath $pluginDir):/out" `
    -w /backend "heroiclabs/nakama-pluginbuilder:$tag" `
    build -buildmode=plugin -trimpath -o /out/snoringcat.so . 2>&1 |
    Out-File (Join-Path $stackDir 'plugin-build.log') -Encoding utf8
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $pluginDir 'snoringcat.so'))) {
    throw "plugin build failed (exit $LASTEXITCODE), see stack/plugin-build.log"
}

$nakamaPort = FreePort; $consolePort = FreePort; $pgPort = FreePort
$env:HOPNBOP_DEV_NAKAMA_PORT = "$nakamaPort"
$env:HOPNBOP_DEV_CONSOLE_PORT = "$consolePort"
$env:HOPNBOP_DEV_POSTGRES_PORT = "$pgPort"
$env:HOPNBOP_DEV_PLUGIN_DIR = DockerPath $pluginDir
$url = "http://127.0.0.1:$nakamaPort"
[ordered]@{
    project = $Project; nakama_url = $url; console_port = $consolePort
    postgres_port = $pgPort; started = (Get-Date -Format o)
    teardown = "docker compose -p $Project -f infra/dev/docker-compose.dev.yml down -v --remove-orphans"
} | ConvertTo-Json | Set-Content $stateFile -Encoding utf8

"[$(Get-Date -Format HH:mm:ss)] compose up $Project at $url"
& docker compose -p $Project -f $compose up -d 2>&1 |
    Out-File (Join-Path $stackDir 'compose-up.log') -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw "compose up failed (exit $LASTEXITCODE)" }

$deadline = (Get-Date).AddSeconds(120); $ok = $false
while ((Get-Date) -lt $deadline) {
    try {
        if ((Invoke-WebRequest "$url/healthcheck" -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) {
            $ok = $true; break
        }
    } catch {}
    Start-Sleep -Seconds 1
}
if (-not $ok) { throw "Nakama not healthy within 120 s" }
"[$(Get-Date -Format HH:mm:ss)] healthy; register game.yaml"

# -NakamaHost MUST be given: the script's default is production.
& pwsh -NoProfile -File (Join-Path $repo 'scripts\sync-game-config.ps1') `
    -NakamaHost $url -HttpKey defaulthttpkey -AdminKey defaultadminkey 2>&1 |
    Out-File (Join-Path $stackDir 'sync-game-config.log') -Encoding utf8
$syncExit = $LASTEXITCODE
"sync-game-config exit=$syncExit"
Get-Content (Join-Path $stackDir 'sync-game-config.log') -Tail 4
"[$(Get-Date -Format HH:mm:ss)] stack up in $([int]((Get-Date) - $t0).TotalSeconds)s: $url"
