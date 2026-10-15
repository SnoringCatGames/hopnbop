# Relaunches one harness process against an EXISTING run's sandbox, to
# test persistence across a restart. run-game.ps1 always makes a fresh
# sandbox, so this replicates its arguments (run-game.ps1:386-419) with
# the old APPDATA. H37 exec-b probe; loopback-free (no network flags).
param(
    [Parameter(Mandatory)][string]$RunDir,
    [Parameter(Mandatory)][string]$Scenario,
    [string]$Process = 'client1',
    [string]$OutName = 'client1-restart',
    [int]$TimeoutSec = 150
)
$repo = 'C:\Users\lsl\Repositories\hopnbop'
$godot = 'C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe'
$sandbox = Join-Path $RunDir "$Process\appdata"
if (-not (Test-Path $sandbox)) { throw "no sandbox at $sandbox" }
$out = Join-Path $RunDir $OutName
New-Item -ItemType Directory -Force $out | Out-Null
$scenarioCopy = Join-Path $out 'scenario.json'
Copy-Item $Scenario $scenarioCopy -Force
$args = @('--path', $repo, ('--' + $Process.Replace('client', 'client=')), '--windowed',
    '--resolution', '1360x765', '--position', '20000,100', '--audio-driver', 'Dummy',
    '-s', 'res://scripts/agent/agent_bootstrap.gd', '--',
    "--agent-scenario=$scenarioCopy", "--agent-process=$Process", "--agent-out=$out",
    "--agent-sandbox=$sandbox", '--agent-window=20000,100,1360,765',
    ("--agent-base-settings=" + (Join-Path $RunDir 'settings.committed.tres')))
$env:APPDATA = $sandbox
$quoted = $args | ForEach-Object { if ($_ -match '[\s'']') { '"' + $_ + '"' } else { $_ } }
$p = Start-Process -FilePath $godot -ArgumentList ($quoted -join ' ') -WorkingDirectory $repo -PassThru -NoNewWindow `
    -RedirectStandardOutput (Join-Path $out 'stdout.log') -RedirectStandardError (Join-Path $out 'stderr.log')
if (-not $p.WaitForExit($TimeoutSec * 1000)) { $p.Kill($true); "KILLED after $TimeoutSec s" }
"exit=$($p.ExitCode)"
$log = Get-Content (Join-Path $out 'stdout.log') -Encoding UTF8
$log | Where-Object { $_ -match '^(SCRIPT ERROR|ERROR):' } | Group-Object | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { "  $($_.Count)x $($_.Name)" }
$result = $log | Where-Object { $_ -match '^AGENT_RESULT ' } | Select-Object -Last 1
if ($result) { $result } else { 'no AGENT_RESULT' }
