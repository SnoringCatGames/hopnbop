#!/usr/bin/env pwsh
# Runs the snoringcat-platform compliance suite against a local
# Nakama + Postgres stack. This is the one command for verifying
# backend and SDK behavior without touching production:
#
#   pwsh scripts/local-smoke-test.ps1
#
# Steps: refresh the platform addon copy; build the runtime plugin
# from the submodule into a temp directory; start
# infra/dev/docker-compose.dev.yml (EDGEGAP_MOCK_DEPLOY=true) as a
# fresh compose project on free ports; register game.yaml; import
# the project; run the suite in one headless Godot process with an
# empty user:// directory; judge the run by GUT's per-test results;
# tear the stack down. Several runs can go at once (one per agent
# or worktree): each gets its own project, ports, and temp dirs.
#
# Production stays out of it three ways. PLATFORM_API_URL points at
# the local stack, and the suite refuses any non-loopback target
# unless ALLOW_PROD_COMPLIANCE=1, which this script clears. The
# empty user:// leaves the game's boot path (Platform is configured
# for production) no stored session to refresh. And a GUT post-run
# hook fails the run if anything sent a Nakama SDK request anyway.
#
# Usage:
#   pwsh scripts/local-smoke-test.ps1
#   pwsh scripts/local-smoke-test.ps1 -TestFile test_friends.gd
#   pwsh scripts/local-smoke-test.ps1 -KeepStack
#   pwsh scripts/local-smoke-test.ps1 -PluginDir <dir> -SkipBuild
#
# Exit codes:
#   0  every test ran and passed
#   1  a test failed, pended, or asserted nothing; GUT ran a
#      different number of tests than the files declare; Godot
#      timed out; or the run sent Nakama SDK traffic
#   2  setup failed: Godot not found, plugin build, compose up,
#      health check, or project import
#   3  game registration failed
#
# Prereqs: Docker running Linux containers, PowerShell 7, and the
# submodules checked out. Godot on the engine version project.godot
# declares, found via -Godot, $env:GODOT, `godot` on PATH, or (on
# Windows) the standard Program Files install. Binaries on another
# version are skipped. On Windows the *_console.exe twin is used
# when there is one.

[CmdletBinding()]
param(
    # Run one file under the compliance directory instead of all
    # of it. Example: -TestFile test_friends.gd.
    [string]$TestFile = "",
    # Leave the stack up afterwards. Prints how to reach it and
    # the exact teardown command.
    [switch]$KeepStack,
    # Directory to build snoringcat.so into, or to reuse with
    # -SkipBuild. Default: a fresh temp directory, deleted after.
    [string]$PluginDir = "",
    # Reuse <PluginDir>/snoringcat.so instead of building it.
    [switch]$SkipBuild,
    # Accept pending, skipped, and no-assert tests. The local
    # stack should exercise every test, so by default any of
    # them fails the run.
    [switch]$AllowPending,
    # A Godot binary to use instead of the search described in
    # Resolve-GodotBinary. Must match project.godot's engine.
    [string]$Godot = "",
    # Host port for Nakama. 0 picks a free one.
    [int]$NakamaPort = 0,
    [int]$NakamaReadyTimeoutSec = 90,
    [int]$ImportTimeoutSec = 600,
    # The full suite takes under a minute. GUT has no per-test
    # timeout, so a hung test would otherwise hang the run.
    [int]$GutTimeoutSec = 300,
    # Where logs and the JUnit XML go. Default: a fresh temp
    # directory, kept and printed at the end.
    [string]$LogDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ComposeFile = Join-Path $RepoRoot "infra/dev/docker-compose.dev.yml"
$RuntimeDir = Join-Path $RepoRoot "third_party/snoringcat-platform/runtime"
$ComplianceRes = "res://addons/snoringcat_platform_client/test/compliance"
$ComplianceDir = Join-Path $RepoRoot "addons/snoringcat_platform_client/test/compliance"
$TrafficHook = "res://test/hooks/fail_on_nakama_traffic.gd"
$WindowsGodot = "C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe"
# Nakama's placeholder keys, plus the runtime's GAME_ADMIN_KEY from
# infra/dev/config.dev.yml. The dev stack starts with exactly these
# and listens only on 127.0.0.1, so they are not secrets.
$ServerKey = "defaultkey"
$HttpKey = "defaulthttpkey"
$AdminKey = "defaultadminkey"
# The dev stack's console login (docker-compose.dev.yml and
# config.dev.yml), loopback-only like the keys above. The
# crash_report test reads its stored report back through the
# console, because no client can read that collection.
$ConsoleUser = "admin"
$ConsolePassword = "devadmin"
# $IsWindows is $null on Windows PowerShell 5.1.
$IsWin = if ($null -eq $IsWindows) { $true } else { $IsWindows }

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

function Stop-Run([int]$Code, [string]$Message) {
    Write-Host ""
    Write-Host $Message -ForegroundColor Red
    exit $Code
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try {
        return $listener.LocalEndpoint.Port
    } finally {
        $listener.Stop()
    }
}

# Docker Desktop on Windows takes forward slashes in bind mounts.
function ConvertTo-DockerPath([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($IsWin) {
        return $full -replace '\\', '/'
    }
    return $full
}

# The engine minor version project.godot declares, e.g. "4.7".
function Get-ProjectEngineVersion {
    $line = Select-String -LiteralPath (Join-Path $RepoRoot "project.godot") `
        -Pattern '^config/features=PackedStringArray\("(\d+\.\d+)"' |
        Select-Object -First 1
    if ($line) {
        return $line.Matches[0].Groups[1].Value
    }
    return $null
}

# The version a Godot binary reports, e.g. "4.7.2.stable.official".
# Windows reads the file's version resource: a GUI build run with
# --version detaches and prints nothing a script can capture.
function Get-GodotVersion([string]$Path) {
    if ($IsWin) {
        return [string](Get-Item -LiteralPath $Path).VersionInfo.ProductVersion
    }
    return [string](& $Path --version 2>$null | Select-Object -First 1)
}

# Picks a Godot binary that matches project.godot's engine version
# and that a script can wait on. Candidates, in order: -Godot,
# $env:GODOT, `godot` on PATH, the standard Windows install. A
# candidate on the wrong version is skipped with a warning (a stale
# GODOT variable pointing at an older engine is common), except
# -Godot, which is an explicit request and fails the run instead.
function Resolve-GodotBinary([string]$Explicit, [string]$FromEnv) {
    $want = Get-ProjectEngineVersion
    $candidates = [System.Collections.Generic.List[object]]::new()
    if ($Explicit) {
        $candidates.Add(@{ Path = $Explicit; Source = "-Godot" })
    }
    if ($FromEnv) {
        $candidates.Add(@{ Path = $FromEnv; Source = "`$env:GODOT" })
    }
    $onPath = Get-Command godot -CommandType Application `
        -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($onPath) {
        $candidates.Add(@{ Path = $onPath.Source; Source = "PATH" })
    }
    if ($IsWin) {
        $candidates.Add(@{ Path = $WindowsGodot; Source = "default install" })
    }
    foreach ($candidate in $candidates) {
        $path = $candidate.Path
        if (-not (Test-Path -LiteralPath $path)) {
            if ($candidate.Source -eq "-Godot") {
                Stop-Run 2 "-Godot: $path does not exist."
            }
            continue
        }
        $version = Get-GodotVersion $path
        if ($want -and -not $version.StartsWith("$want.")) {
            $message = ("$($candidate.Source) Godot $path is version " +
                "'$version', but project.godot needs $want.")
            if ($candidate.Source -eq "-Godot") {
                Stop-Run 2 $message
            }
            Write-Warning "Skipping it: $message"
            continue
        }
        # A GUI build: use its console twin when there is one.
        if ($IsWin -and $path -notmatch '_console\.exe$') {
            $twin = $path -replace '\.exe$', '_console.exe'
            if (Test-Path -LiteralPath $twin) {
                return $twin
            }
        }
        return $path
    }
    return $null
}

# Runs Godot to completion or kills its process tree at the
# deadline. Returns the exit code, or $null on timeout. Output
# goes to $Log (stdout) and $Log.stderr.
function Invoke-Godot([string[]]$Arguments, [string]$Log, [int]$TimeoutSec) {
    # Start-Process joins arguments with spaces and doesn't quote
    # them, so quote any that contain whitespace.
    $argLine = ($Arguments | ForEach-Object {
        if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
    }) -join ' '
    $proc = Start-Process -FilePath $script:GodotBin `
        -ArgumentList $argLine -WorkingDirectory $RepoRoot `
        -RedirectStandardOutput $Log `
        -RedirectStandardError "$Log.stderr" `
        -NoNewWindow -PassThru
    # Caching the handle keeps ExitCode readable after exit on some
    # PowerShell builds. Best effort: nothing depends on it.
    try {
        $null = $proc.Handle
    } catch {
    }
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        $proc.Kill($true)
        $proc.WaitForExit()
        return $null
    }
    return $proc.ExitCode
}

function Invoke-Compose([string[]]$Arguments) {
    & docker compose -p $script:Project -f $ComposeFile @Arguments
}

# Sets env vars for this process (Godot and docker inherit them)
# and remembers the old values for Restore-Env.
$script:SavedEnv = @{}
function Set-ScopedEnv([string]$Name, [string]$Value) {
    if (-not $script:SavedEnv.ContainsKey($Name)) {
        $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name)
    }
    [Environment]::SetEnvironmentVariable($Name, $Value)
}

function Restore-Env {
    foreach ($name in $script:SavedEnv.Keys) {
        [Environment]::SetEnvironmentVariable($name, $script:SavedEnv[$name])
    }
    $script:SavedEnv = @{}
}

function Remove-TempDir([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return
    }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force
    } catch {
        # On Linux the plugin builder writes its output as root.
        Write-Warning "Could not remove ${Path}: $($_.Exception.Message)"
    }
}

# --- Validate inputs ----------------------------------------
$script:GodotBin = Resolve-GodotBinary $Godot $env:GODOT
if (-not $script:GodotBin) {
    Stop-Run 2 ("No Godot $(Get-ProjectEngineVersion) binary found. Install it" +
        $(if ($IsWin) { " at $WindowsGodot" } else { " on PATH as godot" }) +
        ", or pass -Godot <path>.")
}
if ($SkipBuild -and -not $PluginDir) {
    Stop-Run 2 "-SkipBuild needs -PluginDir <dir holding snoringcat.so>."
}
$sourceCompliance = Join-Path $RepoRoot `
    "third_party/snoringcat-platform/addons/snoringcat_platform_client/test/compliance"
if ($TestFile -and -not (Test-Path -LiteralPath (Join-Path $sourceCompliance $TestFile))) {
    Stop-Run 2 "-TestFile: no $TestFile in $sourceCompliance."
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runId = "$stamp-$PID"
$tempRoot = [System.IO.Path]::GetTempPath()
if (-not $LogDir) {
    $LogDir = Join-Path $tempRoot "hopnbop-compliance-$runId"
}
New-Item -ItemType Directory -Force $LogDir | Out-Null
$ownsPluginDir = -not $PluginDir
if ($ownsPluginDir) {
    $PluginDir = Join-Path $tempRoot "hopnbop-plugin-$runId"
}
New-Item -ItemType Directory -Force $PluginDir | Out-Null
$userDataDir = Join-Path $tempRoot "hopnbop-userdata-$runId"
$script:Project = "hopnbop-smoke-$($runId.ToLower())"
$stackStarted = $false
$exitCode = 0

Write-Host "Godot:   $script:GodotBin"
Write-Host "Logs:    $LogDir"
Write-Host "Project: $script:Project"

try {
    # --- Refresh the platform addon copy --------------------
    # The suite runs from addons/snoringcat_platform_client/, a
    # copy of the submodule's addon, so refresh it first.
    Write-Step "Refresh platform addon"
    & pwsh -NoProfile -File (Join-Path $RepoRoot "scripts/setup-platform-addon.ps1") |
        Out-File (Join-Path $LogDir "setup-platform-addon.log")
    if ($LASTEXITCODE -ne 0) {
        Stop-Run 2 "setup-platform-addon.ps1 failed (exit $LASTEXITCODE)."
    }

    # --- Build the runtime plugin ---------------------------
    # The source is mounted read-only and the .so lands outside
    # the repo. Go plugins only load into the Nakama build they
    # were compiled against, so the builder tag comes from the
    # compose file's Nakama image.
    $pluginPath = Join-Path $PluginDir "snoringcat.so"
    $nakamaImage = Select-String -Path $ComposeFile `
        -Pattern '^\s*image:\s*heroiclabs/nakama:(\S+)' | Select-Object -First 1
    if (-not $nakamaImage) {
        Stop-Run 2 "Could not find the heroiclabs/nakama image in $ComposeFile."
    }
    $nakamaTag = $nakamaImage.Matches[0].Groups[1].Value
    if ($SkipBuild) {
        if (-not (Test-Path -LiteralPath $pluginPath)) {
            Stop-Run 2 "-SkipBuild: $pluginPath does not exist."
        }
        Write-Step "Plugin build skipped (reusing $pluginPath)"
    } else {
        Write-Step "Build runtime plugin (nakama-pluginbuilder:$nakamaTag)"
        & docker run --rm `
            -v "$(ConvertTo-DockerPath $RuntimeDir):/backend:ro" `
            -v "$(ConvertTo-DockerPath $PluginDir):/out" `
            -w /backend "heroiclabs/nakama-pluginbuilder:$nakamaTag" `
            build -buildmode=plugin -trimpath -o /out/snoringcat.so .
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $pluginPath)) {
            Stop-Run 2 "Plugin build failed (exit $LASTEXITCODE)."
        }
    }

    # --- Start the dev stack --------------------------------
    if ($NakamaPort -le 0) {
        $NakamaPort = Get-FreeTcpPort
    }
    $nakamaUrl = "http://127.0.0.1:$NakamaPort"
    $consolePort = Get-FreeTcpPort
    $consoleUrl = "http://127.0.0.1:$consolePort"
    Set-ScopedEnv "HOPNBOP_DEV_NAKAMA_PORT" "$NakamaPort"
    Set-ScopedEnv "HOPNBOP_DEV_CONSOLE_PORT" "$consolePort"
    Set-ScopedEnv "HOPNBOP_DEV_POSTGRES_PORT" "$(Get-FreeTcpPort)"
    Set-ScopedEnv "HOPNBOP_DEV_PLUGIN_DIR" (ConvertTo-DockerPath $PluginDir)

    Write-Step "Start dev stack at $nakamaUrl"
    $stackStarted = $true
    Invoke-Compose @("up", "-d")
    if ($LASTEXITCODE -ne 0) {
        Stop-Run 2 "docker compose up failed (exit $LASTEXITCODE)."
    }

    # --- Wait for Nakama ------------------------------------
    Write-Step "Wait for Nakama"
    $deadline = (Get-Date).AddSeconds($NakamaReadyTimeoutSec)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-WebRequest -Uri "$nakamaUrl/healthcheck" `
                -UseBasicParsing -TimeoutSec 3
            if ($resp.StatusCode -eq 200) {
                $ready = $true
                break
            }
        } catch {
            # Refused or 5xx while Postgres and `migrate up` run.
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        Invoke-Compose @("logs", "--tail=80", "nakama") | Out-Host
        Stop-Run 2 "Nakama was not healthy within ${NakamaReadyTimeoutSec}s."
    }
    Write-Host "Nakama healthy."

    # --- Register game.yaml ---------------------------------
    # The runtime's BeforeAuthenticate* hooks reject sign-ins
    # without a registered game_id, so seed the row first.
    Write-Step "Register game.yaml"
    & pwsh -NoProfile -File (Join-Path $RepoRoot "scripts/sync-game-config.ps1") `
        -NakamaHost $nakamaUrl -HttpKey $HttpKey -AdminKey $AdminKey |
        Out-File (Join-Path $LogDir "sync-game-config.log")
    if ($LASTEXITCODE -ne 0) {
        Get-Content (Join-Path $LogDir "sync-game-config.log") -Tail 20 | Out-Host
        Stop-Run 3 "sync-game-config.ps1 failed (exit $LASTEXITCODE)."
    }

    # --- Import the project ---------------------------------
    # Every Godot run gets an empty user:// so it can't start
    # from the operator's stored auth.
    New-Item -ItemType Directory -Force $userDataDir | Out-Null
    Set-ScopedEnv "APPDATA" $userDataDir
    Set-ScopedEnv "XDG_DATA_HOME" $userDataDir

    # A fresh checkout has no .godot/ cache, and GUT exits 0
    # having run nothing when its classes aren't registered.
    # --import exits non-zero on harmless warnings, so judge it by
    # the class cache, as pr-validate.yml does.
    Write-Step "Import project"
    $importExit = Invoke-Godot @("--headless", "--path", ".", "--import") `
        (Join-Path $LogDir "import.log") $ImportTimeoutSec
    $classCache = Join-Path $RepoRoot ".godot/global_script_class_cache.cfg"
    $cacheOk = (Test-Path -LiteralPath $classCache) -and
        (Select-String -LiteralPath $classCache -Pattern '"GutTest"' -Quiet)
    if (-not $cacheOk) {
        Stop-Run 2 ("Project import did not register class_names " +
            "(exit $importExit). See $(Join-Path $LogDir 'import.log').")
    }

    # --- Run the compliance suite ---------------------------
    if ($TestFile) {
        $targetFiles = @(Get-Item -LiteralPath (Join-Path $ComplianceDir $TestFile))
        $selector = "-gtest=$ComplianceRes/$TestFile"
    } else {
        $targetFiles = @(Get-ChildItem -LiteralPath $ComplianceDir -Filter "test_*.gd")
        $selector = "-gdir=$ComplianceRes"
    }
    $declared = ($targetFiles |
        ForEach-Object { (Select-String -LiteralPath $_.FullName -Pattern '^func test_').Count } |
        Measure-Object -Sum).Sum

    Set-ScopedEnv "PLATFORM_API_URL" $nakamaUrl
    Set-ScopedEnv "NAKAMA_SERVER_KEY" $ServerKey
    Set-ScopedEnv "NAKAMA_HTTP_KEY" $HttpKey
    Set-ScopedEnv "GAME_ADMIN_KEY" $AdminKey
    Set-ScopedEnv "NAKAMA_CONSOLE_URL" $consoleUrl
    Set-ScopedEnv "NAKAMA_CONSOLE_USERNAME" $ConsoleUser
    Set-ScopedEnv "NAKAMA_CONSOLE_PASSWORD" $ConsolePassword
    Set-ScopedEnv "PLATFORM_COMPLIANCE_MODE" "live"
    Set-ScopedEnv "ALLOW_PROD_COMPLIANCE" $null

    Write-Step "Run compliance suite ($declared tests declared)"
    $gutLog = Join-Path $LogDir "gut.log"
    $junit = Join-Path $LogDir "results.xml"
    $gutExit = Invoke-Godot @(
        "--headless", "-s", "--path", ".", "addons/gut/gut_cmdln.gd",
        $selector, "-gexit", "-gdisable_colors",
        "-gjunit_xml_file=$junit",
        "-gpost_run_script=$TrafficHook"
    ) $gutLog $GutTimeoutSec
    # gut.log keeps the Nakama SDK's DEBUG chatter; the console
    # doesn't need it.
    Get-Content -LiteralPath $gutLog |
        Where-Object { $_ -notmatch '^=== Nakama : DEBUG ===' } | Out-Host
    Get-Content -LiteralPath "$gutLog.stderr" -ErrorAction SilentlyContinue |
        Select-String -Pattern '^(ERROR|SCRIPT ERROR|WARNING):' | Out-Host
    Restore-Env

    # --- Judge the run --------------------------------------
    $problems = [System.Collections.Generic.List[string]]::new()
    $results = @()
    if ($null -eq $gutExit) {
        $problems.Add("Godot did not finish within ${GutTimeoutSec}s; killed it.")
    } elseif ($gutExit -ne 0) {
        $problems.Add("GUT exited $gutExit.")
    }
    if (Select-String -LiteralPath $gutLog -Pattern 'NAKAMA TRAFFIC' -Quiet) {
        $problems.Add("The run sent Nakama SDK requests (see NAKAMA TRAFFIC above).")
    }
    if (Test-Path -LiteralPath $junit) {
        [xml]$xml = Get-Content -LiteralPath $junit -Raw
        foreach ($case in $xml.SelectNodes("//testsuite/testcase")) {
            $note = $case.SelectSingleNode("failure|skipped")
            $detail = if ($note) { ($note.InnerText -split "`n")[0].Trim() } else { "" }
            $results += [pscustomobject]@{
                File = Split-Path -Leaf $case.ParentNode.GetAttribute("name")
                Test = $case.GetAttribute("name")
                Status = $case.GetAttribute("status")
                Detail = $detail
            }
        }
    } else {
        $problems.Add("GUT wrote no results to $junit.")
    }

    $passed = @($results | Where-Object Status -eq "pass")
    $failed = @($results | Where-Object Status -eq "fail")
    $idle = @($results | Where-Object { $_.Status -notin @("pass", "fail") })
    if ($results.Count -ne $declared) {
        $problems.Add("GUT reported $($results.Count) tests, but the files declare $declared.")
    }
    if ($failed.Count -gt 0) {
        $problems.Add("$($failed.Count) test(s) failed.")
    }
    if ($idle.Count -gt 0 -and -not $AllowPending) {
        $problems.Add(("$($idle.Count) test(s) pended, skipped, or asserted " +
            "nothing. The local stack should exercise every test; pass " +
            "-AllowPending to accept that."))
    }

    Write-Step "Summary"
    Write-Host ("Tests: {0} declared, {1} reported, {2} passed, {3} failed, {4} pending/other" -f
        $declared, $results.Count, $passed.Count, $failed.Count, $idle.Count)
    foreach ($row in @($failed) + @($idle)) {
        Write-Host ("  [{0}] {1}::{2}  {3}" -f $row.Status, $row.File, $row.Test, $row.Detail)
    }
    Write-Host "Logs: $LogDir"
    if ($problems.Count -gt 0) {
        foreach ($problem in $problems) {
            Write-Host "FAIL: $problem" -ForegroundColor Red
        }
        $exitCode = 1
    } else {
        Write-Host "OK: compliance suite green against the local stack." -ForegroundColor Green
    }
} finally {
    Restore-Env
    if ($stackStarted) {
        if ($KeepStack) {
            Write-Host ""
            Write-Host "Leaving the stack up (-KeepStack) at $nakamaUrl." -ForegroundColor Yellow
            Write-Host "Tear it down with:" -ForegroundColor Yellow
            Write-Host "  docker compose -p $script:Project -f infra/dev/docker-compose.dev.yml down -v"
        } else {
            Write-Step "Tear down dev stack"
            # `down -v` drops the Postgres volume so nothing leaks
            # into the next run.
            Invoke-Compose @("down", "-v", "--remove-orphans") | Out-Host
        }
    }
    if (-not $KeepStack -and $ownsPluginDir) {
        Remove-TempDir $PluginDir
    }
    Remove-TempDir $userDataDir
}

exit $exitCode
