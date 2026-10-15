# Runs the repro pck on the DEBUG template (h37-verify 4f) (no --path: release templates refuse it).
# Loopback UDP only; throwaway APPDATA under here.
param([string[]]$Variants = @('replace', 'null', 'deferred'), [switch]$Spawn)
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $here '..\f4\dbgexp\repro.console.exe'
$env:APPDATA = Join-Path $here 'appdata'
New-Item -ItemType Directory -Force $env:APPDATA, (Join-Path $here 'logs') | Out-Null
foreach ($v in $Variants) {
    $u = [System.Net.Sockets.UdpClient]::new(0); $port = $u.Client.LocalEndPoint.Port; $u.Close()
    $tag = "dbgexport-$v-$([int][bool]$Spawn)"
    $sl = Join-Path $here "logs\$tag-server.log"; $cl = Join-Path $here "logs\$tag-client.log"
    $s = Start-Process -FilePath $exe -ArgumentList '--headless', '--', '--role=server', "--port=$port", $(if ($Spawn) { '--spawn' } else { '--nospawn' }) `
        -RedirectStandardOutput $sl -RedirectStandardError "$sl.err" -NoNewWindow -PassThru
    Start-Sleep -Milliseconds 1500
    $c = Start-Process -FilePath $exe -ArgumentList '--headless', '--', '--role=client', "--variant=$v", "--port=$port" `
        -RedirectStandardOutput $cl -RedirectStandardError "$cl.err" -NoNewWindow -PassThru
    $c.WaitForExit(20000) | Out-Null; $s.WaitForExit(20000) | Out-Null
    $crash = (Select-String $cl, "$cl.err" -Pattern 'signal 11|CrashHandler' -Quiet)
    $last = (Get-Content $cl | Where-Object { $_ -match '^(client|build)' }) -join ' | '
    "dbgexport {0,-9} spawn={1} client_exit={2} server_exit={3} crash_line={4} :: {5}" -f $v, [int][bool]$Spawn, $c.ExitCode, $s.ExitCode, $crash, $last
}

