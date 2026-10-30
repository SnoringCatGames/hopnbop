<#
.SYNOPSIS
    Runs Hop 'n Bop headless or windowed for an AI agent: boots one or
    more Godot processes, drives them through scripted steps, and
    collects logs, screenshots, state snapshots, and a pass/fail
    summary in one run directory.

.DESCRIPTION
    Each Godot process runs res://scripts/agent/agent_bootstrap.gd as
    its main loop, which loads agent_driver.gd to apply in-memory
    settings overrides (settings.tres is never touched) and run the
    scenario's steps. See "Agent harness" in CLAUDE.md for the
    scenario format and step list.

    Prod-safe by default: every process gets its own throwaway APPDATA
    (so it cannot see the real auth.cfg or local settings), the driver
    refuses to run if an auth file is visible anyway, and every backend
    URL is pointed at 127.0.0.1:9. Pass -AllowNetwork to lift the
    network block, or -Backend to point Nakama at a local stack.

    Pass/fail comes from each process's `AGENT_RESULT {...}` line, not
    from exit codes alone.

.EXAMPLE
    scripts/agent/run-game.ps1 -Scenario offline-move-jump

.EXAMPLE
    scripts/agent/run-game.ps1 -Mode lobby -Visible

.EXAMPLE
    scripts/agent/run-game.ps1 -Mode match -Clients 2 -Headless

.EXAMPLE
    scripts/agent/run-game.ps1 -Mode level -Level level_2 -Steps '[
        {"do": "wait_ready"}, {"do": "screenshot", "name": "spawn"}]'

.EXAMPLE
    scripts/agent/run-game.ps1 -Scenario leaderboard-local-backend `
        -Backend http://127.0.0.1:7350
#>
[CmdletBinding()]
param(
    # Scenario JSON: a path, or a name under scripts/agent/scenarios/.
    [string]$Scenario,
    # Mode for an inline run, or an override for -Scenario.
    [ValidateSet('offline', 'level', 'lobby', 'match')]
    [string]$Mode,
    # Level id (level_0 ... level_5) or index.
    [string]$Level,
    # Client count for match mode.
    [ValidateRange(1, 2)]
    [int]$Clients = 0,
    # Steps for every client: a JSON array, or a path to one.
    [string]$Steps,
    # No windows (and so no screenshots) for any process.
    [switch]$Headless,
    # Put windows on the primary screen instead of off-screen.
    [switch]$Visible,
    [string]$WindowSize = '1360x765',
    # Per-process scenario timeout. Defaults to the scenario's, or 60.
    [int]$TimeoutSec = 0,
    # Parent of the run directory. Defaults to $env:TEMP\hopnbop-agent-runs.
    [string]$OutDir,
    # UDP port for match mode. 0 picks a free one.
    [int]$Port = 0,
    # RNG seed override: an integer, or 'none' to keep the game random.
    [string]$Seed,
    # Use the working copy of settings.tres instead of the committed one.
    [switch]$UseWorkingSettings,
    [switch]$AllowNetwork,
    # A local Nakama (scheme://host:port on a loopback host) to point
    # the game at instead of the blackhole, e.g. a stack left up by
    # local-smoke-test.ps1 -KeepStack. Other backend URLs stay
    # blackholed. Anything but loopback is refused.
    [string]$Backend,
    # The server key -Backend's stack takes; the dev stack's by default.
    [string]$BackendServerKey = 'defaultkey',
    # Do not fail a process for SCRIPT ERROR lines.
    [switch]$AllowScriptErrors,
    # Run a headless --import first (after pulling new assets).
    [switch]$Import,
    [string]$Godot = 'C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe',
    # Print only the summary JSON.
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$BootstrapPath = 'res://scripts/agent/agent_bootstrap.gd'
$ScenarioDir = Join-Path $PSScriptRoot 'scenarios'
$DefaultTimeoutSec = 60
# Mirrors agent_driver.gd: the server outlives its clients.
$ServerExtraTimeoutSec = 15
$KillMarginSec = 30
$ServerGraceSec = 20
$ServerReadyTimeoutSec = 30
$ServerReadyPattern = 'Started ENet multiplayer server'
$ClientConnectedPattern = 'Connected to server'
$OffscreenOriginX = 20000
$OffscreenY = 100
$VisibleOriginX = 40
$VisibleY = 120
$WindowGap = 40
$PortRangeStart = 24000
$PortRangeEnd = 34000
$TopErrorCount = 8
$LogTailLines = 25

function Write-Info([string]$Message) {
    if (-not $Json) { Write-Host $Message }
}

function Get-Prop($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function Set-Prop($Object, [string]$Name, $Value) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

# Masks anything token-shaped before it reaches the console.
function Protect-Secrets([string]$Text) {
    if (-not $Text) { return $Text }
    $Text = $Text -replace '(?i)(http_key|server_key|refresh_token|access_token|jwt_token|token|password|secret)(["'']?\s*[:=]\s*["'']?)[^\s"''&,;]+', '$1$2<redacted>'
    $Text = $Text -replace '(?i)Bearer\s+[A-Za-z0-9\-._~+/]+=*', 'Bearer <redacted>'
    $Text = $Text -replace 'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+', '<jwt-redacted>'
    return $Text
}

function ConvertTo-ArgumentString([string[]]$Arguments) {
    $quoted = foreach ($argument in $Arguments) {
        if ($argument -eq '') {
            '""'
        } elseif ($argument -notmatch '[\s"]') {
            $argument
        } else {
            # CommandLineToArgvW: double the backslashes before a quote.
            $escaped = $argument -replace '(\\*)"', '$1$1\"'
            $escaped = $escaped -replace '(\\+)$', '$1$1'
            '"' + $escaped + '"'
        }
    }
    return $quoted -join ' '
}

function Write-Utf8File([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

# Writes a file's committed (HEAD) bytes, untouched by console encoding.
function Save-CommittedFile([string]$RelativePath, [string]$Destination) {
    $info = New-Object System.Diagnostics.ProcessStartInfo 'git', ('-C "{0}" show "HEAD:{1}"' -f $RepoRoot, $RelativePath)
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    try { $process = [System.Diagnostics.Process]::Start($info) } catch { return $false }
    $errors = $process.StandardError.ReadToEndAsync()
    $stream = [System.IO.File]::Create($Destination)
    try { $process.StandardOutput.BaseStream.CopyTo($stream) } finally { $stream.Close() }
    $process.WaitForExit()
    $null = $errors.Result
    return ($process.ExitCode -eq 0 -and (Get-Item $Destination).Length -gt 0)
}

function Get-FreeUdpPort {
    $random = New-Object System.Random
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        $candidate = $random.Next($PortRangeStart, $PortRangeEnd)
        $inUse = Get-NetUDPEndpoint -LocalPort $candidate -ErrorAction SilentlyContinue
        if (-not $inUse) { return $candidate }
    }
    throw "No free UDP port found in $PortRangeStart-$PortRangeEnd."
}

# Launches a process with its own APPDATA and merges stdout and stderr,
# in arrival order, into one log file.
if (-not ('HopnbopAgent.LaunchedProcess' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace HopnbopAgent {
    public sealed class LaunchedProcess {
        public Process Process;
        public string LogPath;
        private StreamWriter _writer;
        private readonly object _lock = new object();

        public static LaunchedProcess Start(
            string exe, string arguments, string workingDirectory,
            string logPath, string appData) {
            var info = new ProcessStartInfo(exe, arguments);
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            info.StandardOutputEncoding = Encoding.UTF8;
            info.StandardErrorEncoding = Encoding.UTF8;
            info.WorkingDirectory = workingDirectory;
            info.EnvironmentVariables["APPDATA"] = appData;
            var launched = new LaunchedProcess();
            launched.LogPath = logPath;
            launched._writer = new StreamWriter(
                logPath, false, new UTF8Encoding(false));
            launched._writer.AutoFlush = true;
            var process = new Process();
            process.StartInfo = info;
            process.OutputDataReceived += launched.OnData;
            process.ErrorDataReceived += launched.OnData;
            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            launched.Process = process;
            return launched;
        }

        private void OnData(object sender, DataReceivedEventArgs e) {
            if (e.Data == null) { return; }
            lock (_lock) {
                if (_writer != null) { _writer.WriteLine(e.Data); }
            }
        }

        // Call once the process has exited: drains the output readers.
        public void Close() {
            try { Process.WaitForExit(); } catch (Exception) { }
            lock (_lock) {
                if (_writer != null) { _writer.Dispose(); _writer = null; }
            }
        }
    }
}
'@
}

# --- Prerequisites ------------------------------------------------------------

if (-not (Test-Path $Godot)) {
    throw "Godot not found at $Godot. Pass -Godot <console exe>."
}
if ((Split-Path $Godot -Leaf) -notmatch 'console') {
    Write-Warning 'Use the *_console.exe Godot build: the GUI build detaches, so no logs or exit code come back.'
}
if (-not (Test-Path (Join-Path $RepoRoot 'addons\snoringcat_platform_client\plugin.cfg'))) {
    throw 'addons/snoringcat_platform_client is missing. Run scripts/setup-platform-addon.ps1 first.'
}
if ($Backend) {
    # The driver checks again; refusing here fails before any launch.
    $backendUri = $null
    if (-not [Uri]::TryCreate($Backend, [UriKind]::Absolute, [ref]$backendUri) -or
        $backendUri.Scheme -notin @('http', 'https') -or
        -not $backendUri.IsLoopback -or
        $backendUri.AbsolutePath -ne '/' -or
        $Backend -notmatch ':\\d+/?$') {
        throw "-Backend must be http(s)://<loopback host>:<port>, not $Backend."
    }
    $Backend = $backendUri.GetLeftPart([UriPartial]::Authority)
}

# --- Scenario -----------------------------------------------------------------

if ($Scenario) {
    $scenarioPath = $Scenario
    if (-not (Test-Path $scenarioPath)) {
        $named = Join-Path $ScenarioDir $Scenario
        if (-not $named.EndsWith('.json')) { $named += '.json' }
        $scenarioPath = $named
    }
    if (-not (Test-Path $scenarioPath)) {
        $known = (Get-ChildItem $ScenarioDir -Filter *.json | ForEach-Object { $_.BaseName }) -join ', '
        throw "Scenario '$Scenario' not found. Known: $known"
    }
    $spec = Get-Content $scenarioPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    $spec = [pscustomobject]@{ name = 'inline' }
}
if ($Mode) { Set-Prop $spec 'mode' $Mode }
if (-not (Get-Prop $spec 'mode')) { Set-Prop $spec 'mode' 'offline' }
if ($Level) {
    $levelValue = $Level
    if ($Level -match '^\d+$') { $levelValue = [int]$Level }
    Set-Prop $spec 'level' $levelValue
}
if ($Clients -gt 0) { Set-Prop $spec 'clients' $Clients }
if ($TimeoutSec -gt 0) { Set-Prop $spec 'timeout_sec' $TimeoutSec }
if ($Seed) {
    if ($Seed -eq 'none') {
        Set-Prop $spec 'seed' $null
    } elseif ($Seed -match '^-?\d+$') {
        Set-Prop $spec 'seed' ([long]$Seed)
    } else {
        throw "-Seed must be an integer or 'none'."
    }
}
if ($Headless) { Set-Prop $spec 'headless' $true }
if ($Steps) {
    $stepsText = $Steps
    if (-not $Steps.TrimStart().StartsWith('[')) { $stepsText = Get-Content -LiteralPath $Steps -Raw -Encoding UTF8 }
    $parsedSteps = $stepsText | ConvertFrom-Json
    Set-Prop $spec 'steps' @($parsedSteps)
}

$mode = [string](Get-Prop $spec 'mode')
$scenarioName = [string](Get-Prop $spec 'name' 'inline')
$processSpecs = Get-Prop $spec 'processes'
$isHeadlessRun = [bool](Get-Prop $spec 'headless' $false)
if ($mode -eq 'match') {
    $clientCount = [int](Get-Prop $spec 'clients' 2)
    if ($clientCount -lt 1 -or $clientCount -gt 2) { throw "Match mode supports 1 or 2 clients, not $clientCount." }
    $processNames = @('server') + (1..$clientCount | ForEach-Object { "client$_" })
} else {
    $processNames = @('client1')
}
# The longest per-process timeout sets the kill deadline.
$timeout = [int](Get-Prop $spec 'timeout_sec' $DefaultTimeoutSec)
foreach ($property in @(if ($processSpecs) { $processSpecs.PSObject.Properties })) {
    $processTimeout = [int](Get-Prop $property.Value 'timeout_sec' 0)
    if ($processTimeout -gt $timeout) { $timeout = $processTimeout }
}

if ($WindowSize -notmatch '^(\d+)x(\d+)$') { throw "-WindowSize must look like 1360x765." }
$windowWidth = [int]$Matches[1]
$windowHeight = [int]$Matches[2]

# --- Run directory ------------------------------------------------------------

if (-not $OutDir) { $OutDir = Join-Path $env:TEMP 'hopnbop-agent-runs' }
$safeName = $scenarioName -replace '[^A-Za-z0-9_.-]', '_'
$runDir = Join-Path $OutDir ('{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $safeName)
New-Item -ItemType Directory -Force $runDir | Out-Null
$runDir = (Resolve-Path $runDir).Path
$scenarioFile = Join-Path $runDir 'scenario.json'
Write-Utf8File $scenarioFile ($spec | ConvertTo-Json -Depth 50)

if ($Import) {
    Write-Info 'Importing assets (headless --import)...'
    & $Godot --headless --path $RepoRoot --import *> (Join-Path $runDir 'import.log')
}
if (-not (Test-Path (Join-Path $RepoRoot '.godot\global_script_class_cache.cfg'))) {
    throw "This checkout has never been imported. Re-run with -Import."
}

$runPort = 0
if ($mode -eq 'match') {
    if ($Port -gt 0) { $runPort = $Port } else { $runPort = Get-FreeUdpPort }
}

# Runs start from the committed settings.tres so that local edits (an
# operator's level override, match length, ...) never change a result.
$baseSettings = $null
$settingsSource = 'working copy'
if (-not $UseWorkingSettings) {
    $candidate = Join-Path $runDir 'settings.committed.tres'
    if (Save-CommittedFile 'settings.tres' $candidate) {
        $baseSettings = $candidate
        $settingsSource = 'committed'
    } else {
        Write-Warning 'git show HEAD:settings.tres failed; using the working copy of settings.tres.'
    }
}
$seedText = 'none'
if ($null -ne $spec.PSObject.Properties['seed']) {
    if ($null -ne $spec.seed) { $seedText = [string]$spec.seed }
} else {
    $seedText = 'default'
}

# --- Launch -------------------------------------------------------------------

function Start-GameProcess([string]$Name, [int]$WindowIndex) {
    $processDir = Join-Path $runDir $Name
    $sandbox = Join-Path $processDir 'appdata'
    New-Item -ItemType Directory -Force $sandbox | Out-Null
    $processSpec = Get-Prop $processSpecs $Name
    if (-not $processSpec -and $Name -like 'client*') { $processSpec = Get-Prop $processSpecs 'client' }
    $defaultHeadless = $isHeadlessRun -or ($Name -eq 'server')
    $isHeadless = [bool](Get-Prop $processSpec 'headless' $defaultHeadless)
    if ($Headless) { $isHeadless = $true }

    $arguments = New-Object System.Collections.Generic.List[string]
    $arguments.Add('--path'); $arguments.Add($RepoRoot)
    if ($Name -like 'client*') { $arguments.Add('--' + $Name.Replace('client', 'client=')) }
    $window = $null
    if ($isHeadless) {
        $arguments.Add('--headless')
    } else {
        if ($Visible) {
            $x = $VisibleOriginX + $WindowIndex * ($windowWidth + $WindowGap)
            $y = $VisibleY
        } else {
            $x = $OffscreenOriginX + $WindowIndex * ($windowWidth + $WindowGap)
            $y = $OffscreenY
        }
        $window = '{0},{1},{2},{3}' -f $x, $y, $windowWidth, $windowHeight
        $arguments.Add('--windowed')
        $arguments.Add('--resolution'); $arguments.Add("${windowWidth}x${windowHeight}")
        $arguments.Add('--position'); $arguments.Add("$x,$y")
        $arguments.Add('--audio-driver'); $arguments.Add('Dummy')
    }
    $arguments.Add('-s'); $arguments.Add($BootstrapPath)
    $arguments.Add('--')
    $arguments.Add("--agent-scenario=$scenarioFile")
    $arguments.Add("--agent-process=$Name")
    $arguments.Add("--agent-out=$processDir")
    $arguments.Add("--agent-sandbox=$sandbox")
    if ($runPort -gt 0) { $arguments.Add("--agent-port=$runPort") }
    if ($window) { $arguments.Add("--agent-window=$window") }
    if ($baseSettings) { $arguments.Add("--agent-base-settings=$baseSettings") }
    if ($AllowNetwork) { $arguments.Add('--agent-allow-network') }
    if ($Backend) {
        $arguments.Add("--agent-backend=$Backend")
        $arguments.Add("--agent-backend-key=$BackendServerKey")
    }

    $logPath = Join-Path $processDir 'process.log'
    $launched = [HopnbopAgent.LaunchedProcess]::Start(
        $Godot, (ConvertTo-ArgumentString $arguments.ToArray()), $RepoRoot, $logPath, $sandbox)
    return [pscustomobject]@{
        Name = $Name
        Dir = $processDir
        Sandbox = $sandbox
        Log = $logPath
        Headless = $isHeadless
        Launched = $launched
        Killed = $false
    }
}

Write-Info ("hopnbop agent run '{0}' (mode={1}, seed={2}, settings={3}{4})" -f `
    $scenarioName, $mode, $seedText, $settingsSource, $(if ($runPort) { ", port=$runPort" } else { '' }))
Write-Info "run dir: $runDir"
if ($AllowNetwork -and -not $Backend) {
    Write-Warning '-AllowNetwork: this run may talk to production.'
}
if ($Backend) { Write-Info "backend: $Backend (local Nakama; other backend URLs blackholed)" }

$started = Get-Date
$processes = New-Object System.Collections.Generic.List[object]
try {
    $windowIndex = 0
    for ($index = 0; $index -lt $processNames.Count; $index++) {
        $name = $processNames[$index]
        $entry = Start-GameProcess $name $windowIndex
        $processes.Add($entry)
        if (-not $entry.Headless) { $windowIndex++ }
        if ($index -eq $processNames.Count - 1) { break }
        # Clients dial once at boot, so the server must be listening
        # first. Each client also connects before the next one starts:
        # the server hands out player ids in connection order, so client
        # N is always player N. Without a server process (lobby and
        # backend runs) there is nothing to dial, so don't wait.
        if ($processNames -notcontains 'server') { continue }
        $pattern = if ($name -eq 'server') { $ServerReadyPattern } else { $ClientConnectedPattern }
        $readyBy = (Get-Date).AddSeconds($ServerReadyTimeoutSec)
        while ((Get-Date) -lt $readyBy -and -not $entry.Launched.Process.HasExited) {
            if ((Test-Path $entry.Log) -and (Select-String -Path $entry.Log -Pattern $pattern -SimpleMatch -Quiet)) { break }
            Start-Sleep -Milliseconds 200
        }
        if ($entry.Launched.Process.HasExited) { break }
    }

    # --- Wait -----------------------------------------------------------------

    $killAt = (Get-Date).AddSeconds($timeout + $ServerExtraTimeoutSec + $KillMarginSec)
    $clientsDoneAt = $null
    while ($true) {
        $running = @($processes | Where-Object { -not $_.Launched.Process.HasExited })
        if ($running.Count -eq 0) { break }
        $now = Get-Date
        $clientsRunning = @($running | Where-Object { $_.Name -ne 'server' })
        if ($mode -eq 'match' -and $clientsRunning.Count -eq 0) {
            if (-not $clientsDoneAt) { $clientsDoneAt = $now }
            if (($now - $clientsDoneAt).TotalSeconds -gt $ServerGraceSec) { $killAt = $now }
        }
        if ($now -ge $killAt) {
            foreach ($entry in $running) {
                $entry.Killed = $true
                try { $entry.Launched.Process.Kill() } catch { }
            }
            Start-Sleep -Milliseconds 500
            break
        }
        Start-Sleep -Milliseconds 250
    }
} finally {
    # Never leave game processes behind, even if this script is stopped.
    foreach ($entry in $processes) {
        if (-not $entry.Launched.Process.HasExited) {
            $entry.Killed = $true
            try { $entry.Launched.Process.Kill() } catch { }
        }
        $entry.Launched.Close()
    }
}

# --- Summarize ----------------------------------------------------------------

$summaries = foreach ($entry in $processes) {
    $lines = @()
    if (Test-Path $entry.Log) { $lines = @(Get-Content $entry.Log -Encoding UTF8) }
    $result = $null
    $resultLine = -1
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match '^AGENT_RESULT (\{.*\})\s*$') {
            try { $result = $Matches[1] | ConvertFrom-Json } catch { $result = $null }
            $resultLine = $i
            break
        }
    }
    # Counts cover the run up to AGENT_RESULT. Shutdown noise after it
    # is reported separately as teardown_errors.
    $crashLines = @()
    $scriptErrors = 0
    $errors = 0
    $warnings = 0
    $teardownErrors = 0
    $errorCounts = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match 'CrashHandlerException|Program crashed with signal|handle_crash') {
            $crashLines += $i
        }
        $isTeardown = $resultLine -ge 0 -and $i -gt $resultLine
        if ($line -match '^(SCRIPT ERROR|ERROR): (.*)$') {
            if ($isTeardown) { $teardownErrors++; continue }
            if ($Matches[1] -eq 'SCRIPT ERROR') { $scriptErrors++ } else { $errors++ }
            $message = $Matches[1] + ': ' + $Matches[2]
        } elseif ($line -match '^WARNING: ') {
            if (-not $isTeardown) { $warnings++ }
            continue
        } else {
            continue
        }
        if ($errorCounts.ContainsKey($message)) { $errorCounts[$message]++ } else { $errorCounts[$message] = 1 }
    }
    $crashBeforeResult = @($crashLines | Where-Object { $resultLine -lt 0 -or $_ -lt $resultLine }).Count -gt 0
    $crashAfterResult = @($crashLines | Where-Object { $resultLine -ge 0 -and $_ -gt $resultLine }).Count -gt 0
    $topErrors = @($errorCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $TopErrorCount |
        ForEach-Object { [pscustomobject]@{ count = $_.Value; message = (Protect-Secrets $_.Key) } })

    $reasons = New-Object System.Collections.Generic.List[string]
    if ($entry.Killed) { $reasons.Add('killed after the harness deadline') }
    if (-not $result) {
        $reasons.Add('no AGENT_RESULT line (crashed, hung, or quit early)')
    } elseif (-not $result.ok) {
        foreach ($failure in @($result.failures)) {
            $reasons.Add(('step {0} {1}: {2}' -f $failure.step, $failure.do, (Protect-Secrets $failure.error)))
        }
        if ($reasons.Count -eq 0) { $reasons.Add('AGENT_RESULT ok=false') }
    }
    if ($crashBeforeResult) { $reasons.Add('engine crash (CrashHandlerException) before the result') }
    if ($scriptErrors -gt 0 -and -not $AllowScriptErrors -and -not (Get-Prop $spec 'allow_script_errors' $false)) {
        $reasons.Add("$scriptErrors SCRIPT ERROR line(s); see top_errors (or pass -AllowScriptErrors)")
    }

    # Tokens only exist with -AllowNetwork, but never leave them behind.
    $scrubbed = @(Get-ChildItem $entry.Sandbox -Recurse -Filter 'auth*.cfg' -ErrorAction SilentlyContinue)
    $scrubbed | Remove-Item -Force -ErrorAction SilentlyContinue

    $exitCode = $null
    try { $exitCode = $entry.Launched.Process.ExitCode } catch { }
    [pscustomobject]@{
        name = $entry.Name
        ok = ($reasons.Count -eq 0)
        reasons = @($reasons)
        exit_code = $exitCode
        headless = $entry.Headless
        log = $entry.Log
        result = $result
        script_errors = $scriptErrors
        errors = $errors
        warnings = $warnings
        teardown_errors = $teardownErrors
        crash_after_result = $crashAfterResult
        top_errors = $topErrors
        auth_files_scrubbed = $scrubbed.Count
    }
}
$summaries = @($summaries)
$allOk = @($summaries | Where-Object { -not $_.ok }).Count -eq 0
$settingsReset = @()
foreach ($process in $summaries) {
    if ($process.result -and $process.result.settings_reset) {
        $settingsReset = @($process.result.settings_reset)
        break
    }
}
$summary = [pscustomobject]@{
    ok = $allOk
    scenario = $scenarioName
    mode = $mode
    seed = $seedText
    settings = $settingsSource
    settings_reset = $settingsReset
    port = $runPort
    elapsed_sec = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    run_dir = $runDir
    processes = $summaries
}
$summaryPath = Join-Path $runDir 'summary.json'
Write-Utf8File $summaryPath ($summary | ConvertTo-Json -Depth 50)

if ($Json) {
    Get-Content $summaryPath -Raw -Encoding UTF8
} else {
    $verdict = if ($allOk) { 'PASS' } else { 'FAIL' }
    Write-Host ''
    Write-Host ("{0}  {1} ({2})  {3}s" -f $verdict, $scenarioName, $mode, $summary.elapsed_sec)
    if ($settingsReset.Count -gt 0) {
        Write-Host ('  ignored local settings.tres edits: ' + ($settingsReset -join ', '))
    }
    foreach ($process in $summaries) {
        $result = $process.result
        $stepsText = if ($result) { '{0}/{1} steps' -f $result.steps_run, $result.steps_total } else { 'no result' }
        Write-Host ("  {0,-8} {1}  exit={2}  {3}  errors={4} script_errors={5} teardown_errors={6}{7}" -f `
            $process.name, $(if ($process.ok) { 'PASS' } else { 'FAIL' }), $process.exit_code, $stepsText,
            $process.errors, $process.script_errors, $process.teardown_errors,
            $(if ($process.crash_after_result) { '  (crashed on exit)' } else { '' }))
        foreach ($reason in $process.reasons) { Write-Host "    ! $reason" }
        if ($result) {
            foreach ($shot in @($result.screenshots)) { Write-Host "    screenshot: $shot" }
            foreach ($state in @($result.states)) { Write-Host "    state:      $state" }
            foreach ($property in @($result.evals.PSObject.Properties)) {
                Write-Host ("    eval {0} = {1}" -f $property.Name, (Protect-Secrets ($property.Value | ConvertTo-Json -Compress -Depth 10)))
            }
            foreach ($warning in @($result.warnings)) { Write-Host "    note: $warning" }
        }
        if (-not $process.ok) {
            foreach ($item in $process.top_errors) { Write-Host ("    {0,3}x {1}" -f $item.count, $item.message) }
            Write-Host "    log tail ($($process.log)):"
            Get-Content $process.log -Tail $LogTailLines -Encoding UTF8 -ErrorAction SilentlyContinue |
                ForEach-Object { Write-Host ('      ' + (Protect-Secrets $_)) }
        }
    }
    Write-Host "summary: $summaryPath"
}
if ($allOk) { exit 0 } else { exit 1 }
