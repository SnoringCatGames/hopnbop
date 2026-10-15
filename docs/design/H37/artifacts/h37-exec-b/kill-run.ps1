# H37 exec-b: run h37-mm-kill.json and kill ONLY that run's server
# process 3 s after its match starts, to mimic a server crash (clients
# then learn of it by ENet timeout, not by a disconnect packet).
$ErrorActionPreference = 'Stop'
$r = 'C:\Users\lsl\Repositories\hopnbop'
$h = "$r\.claude\probes\H37\h37-exec-b"
$log = "$h\mm-kill-6.log"
$before = @(Get-ChildItem "$h\runs" -Directory | Where-Object Name -like '*-h37-mm-kill').Count
$wrapper = Start-Process pwsh -PassThru -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError "$log.err" -ArgumentList @(
    '-NoProfile', '-File', "$r\scripts\agent\run-game.ps1",
    '-Scenario', "$h\scenarios\h37-mm-kill.json", '-OutDir', "$h\runs",
    '-Port', '14433', '-Backend', 'http://127.0.0.1:56191', '-AllowNetwork')
"[$(Get-Date -Format HH:mm:ss)] wrapper pid $($wrapper.Id)"

# Find this run's dir.
$deadline = (Get-Date).AddSeconds(60); $run = $null
while (-not $run -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    $runs = @(Get-ChildItem "$h\runs" -Directory | Where-Object Name -like '*-h37-mm-kill' | Sort-Object Name)
    if ($runs.Count -gt $before) { $run = $runs[-1] }
}
if (-not $run) { throw 'run dir never appeared' }
"run dir $($run.Name)"

# Wait for the server's match start, then 3 s.
$slog = Join-Path $run.FullName 'server\process.log'
$deadline = (Get-Date).AddSeconds(240); $started = $false
while ((Get-Date) -lt $deadline -and -not $wrapper.HasExited) {
    Start-Sleep -Milliseconds 500
    if ((Test-Path $slog) -and (Select-String -Path $slog -Pattern 'match starting' -Quiet)) { $started = $true; break }
}
if (-not $started) { "server match never started"; $wrapper.WaitForExit(); return }
Start-Sleep -Seconds 3

# Kill only the Godot server whose command line names this run dir.
$procs = @(Get-CimInstance Win32_Process -Filter "Name like 'Godot%'" |
    Where-Object { $_.CommandLine -like "*$($run.Name)*" -and $_.CommandLine -like '*--agent-process=server*' })
"[$(Get-Date -Format HH:mm:ss)] killing $($procs.Count) server process(es): $(($procs | ForEach-Object ProcessId) -join ',')"
foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force }

$wrapper.WaitForExit()
"[$(Get-Date -Format HH:mm:ss)] wrapper exit $($wrapper.ExitCode)"
