# Brings the local dev stack (Nakama + Postgres + the runtime
# plugin, mock allocation) up on its own and leaves it running,
# for agent-harness runs against a real backend:
#
#   pwsh scripts/dev-stack.ps1            # build, up, register game
#   pwsh scripts/dev-stack.ps1 -Action Restart
#   pwsh scripts/dev-stack.ps1 -Action Seed     # re-register game.yaml
#   pwsh scripts/dev-stack.ps1 -Action Status
#   pwsh scripts/dev-stack.ps1 -Action Down
#
# Unlike local-smoke-test.ps1 it runs no tests and never touches
# the checkout beyond the addon copy refresh that file does. State
# (ports, project name) lives in %TEMP%\hopnbop-dev-stack so Down
# and Restart find the stack again. Loopback only; the keys are
# the dev stack's public fixed values from infra/dev.

param(
    [ValidateSet('Up', 'Down', 'Restart', 'Seed', 'Status')]
    [string]$Action = 'Up',
    [string]$Project = 'hopnbop-dev'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ComposeFile = Join-Path $RepoRoot 'infra/dev/docker-compose.dev.yml'
$RuntimeDir = Join-Path $RepoRoot 'third_party/snoringcat-platform/runtime'
$StateDir = Join-Path $env:TEMP 'hopnbop-dev-stack'
$StateFile = Join-Path $StateDir 'stack.json'
$PluginDir = Join-Path $StateDir 'plugin'
$HttpKey = 'defaulthttpkey'
$AdminKey = 'defaultadminkey'

function ConvertTo-DockerPath([string]$Path) {
    ([System.IO.Path]::GetFullPath($Path)) -replace '\\', '/'
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    return $port
}

function Read-State {
    if (Test-Path -LiteralPath $StateFile) {
        return Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
    }
    return $null
}

function Set-StackEnv($state) {
    $env:HOPNBOP_DEV_NAKAMA_PORT = "$($state.nakama_port)"
    $env:HOPNBOP_DEV_CONSOLE_PORT = "$($state.console_port)"
    $env:HOPNBOP_DEV_POSTGRES_PORT = "$($state.postgres_port)"
    $env:HOPNBOP_DEV_PLUGIN_DIR = ConvertTo-DockerPath $PluginDir
}

function Invoke-Compose([string[]]$ComposeArgs) {
    & docker compose -p $Project -f $ComposeFile @ComposeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose $($ComposeArgs -join ' ') failed (exit $LASTEXITCODE)"
    }
}

function Register-Game([string]$Url) {
    & pwsh -NoProfile -File (Join-Path $RepoRoot 'scripts/sync-game-config.ps1') `
        -NakamaHost $Url -HttpKey $HttpKey -AdminKey $AdminKey |
        Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "sync-game-config.ps1 failed (exit $LASTEXITCODE)"
    }
}

switch ($Action) {
    'Down' {
        $state = Read-State
        if ($null -ne $state) { Set-StackEnv $state }
        Invoke-Compose @('down', '-v', '--remove-orphans')
        Write-Host "Dev stack '$Project' down."
    }
    'Status' {
        $state = Read-State
        if ($null -eq $state) {
            Write-Host "No dev stack state at $StateFile (never started)."
            exit 0
        }
        Write-Host "Project: $($state.project)  URL: $($state.nakama_url)"
        try {
            $resp = Invoke-WebRequest "$($state.nakama_url)/healthcheck" `
                -UseBasicParsing -TimeoutSec 3
            Write-Host "Nakama: healthy ($($resp.StatusCode))"
        } catch {
            Write-Host "Nakama: not answering ($($_.Exception.Message))"
        }
    }
    'Seed' {
        $state = Read-State
        if ($null -eq $state) { throw 'No stack state; run -Action Up first.' }
        Register-Game $state.nakama_url
        Write-Host 'Game config re-registered.'
    }
    'Restart' {
        $state = Read-State
        if ($null -eq $state) { throw 'No stack state; run -Action Up first.' }
        Set-StackEnv $state
        Invoke-Compose @('restart', 'nakama')
        Write-Host "Nakama restarted at $($state.nakama_url)"
    }
    'Up' {
        New-Item -ItemType Directory -Force $PluginDir | Out-Null
        $nakamaImage = Select-String -Path $ComposeFile `
            -Pattern '^\s*image:\s*heroiclabs/nakama:(\S+)' |
            Select-Object -First 1
        if (-not $nakamaImage) {
            throw "Could not find the heroiclabs/nakama image in $ComposeFile."
        }
        $tag = $nakamaImage.Matches[0].Groups[1].Value
        Write-Host "Building runtime plugin (nakama-pluginbuilder:$tag)..."
        & docker run --rm `
            -v "$(ConvertTo-DockerPath $RuntimeDir):/backend:ro" `
            -v "$(ConvertTo-DockerPath $PluginDir):/out" `
            -w /backend "heroiclabs/nakama-pluginbuilder:$tag" `
            build -buildmode=plugin -trimpath -o /out/snoringcat.so .
        if ($LASTEXITCODE -ne 0 -or
            -not (Test-Path -LiteralPath (Join-Path $PluginDir 'snoringcat.so'))) {
            throw "Plugin build failed (exit $LASTEXITCODE)."
        }

        $state = [ordered]@{
            project       = $Project
            nakama_port   = Get-FreeTcpPort
            console_port  = Get-FreeTcpPort
            postgres_port = Get-FreeTcpPort
            started       = (Get-Date -Format o)
        }
        $state.nakama_url = "http://127.0.0.1:$($state.nakama_port)"
        Set-StackEnv $state
        New-Item -ItemType Directory -Force $StateDir | Out-Null
        $state | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding utf8

        Write-Host "Starting stack '$Project' at $($state.nakama_url)..."
        Invoke-Compose @('up', '-d')
        $deadline = (Get-Date).AddSeconds(120)
        $ready = $false
        while ((Get-Date) -lt $deadline) {
            try {
                $resp = Invoke-WebRequest "$($state.nakama_url)/healthcheck" `
                    -UseBasicParsing -TimeoutSec 3
                if ($resp.StatusCode -eq 200) { $ready = $true; break }
            } catch {
                # Postgres and migrate up are still running.
            }
            Start-Sleep -Seconds 1
        }
        if (-not $ready) {
            throw 'Nakama was not healthy within 120s. See: docker compose logs.'
        }
        Register-Game $state.nakama_url
        Write-Host ''
        Write-Host "Dev stack up: $($state.nakama_url)"
        Write-Host "  run-game: scripts/agent/run-game.ps1 -Backend $($state.nakama_url) -AllowNetwork"
        Write-Host "  down:     pwsh scripts/dev-stack.ps1 -Action Down"
    }
}
