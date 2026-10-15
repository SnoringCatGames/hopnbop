# Runs the repro: {editor, release template} x {replace, null, deferred}.
# Loopback UDP only; every process gets a throwaway APPDATA under here.
param([string[]]$Only = @('editor', 'release'), [switch]$Spawn)
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$bins = [ordered]@{
    editor  = 'C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe'
    release = (Join-Path $here '..\reltpl\godot_rel.console.exe')
}
$env:APPDATA = Join-Path $here 'appdata'
New-Item -ItemType Directory -Force $env:APPDATA, (Join-Path $here 'logs') | Out-Null
foreach ($b in @($bins.Keys | Where-Object { $_ -in $Only })) {
    foreach ($v in 'replace', 'null', 'deferred') {
        $u = [System.Net.Sockets.UdpClient]::new(0); $port = $u.Client.LocalEndPoint.Port; $u.Close()
        $sl = Join-Path $here "logs\$b-$v-$([int][bool]$Spawn)-server.log"; $cl = Join-Path $here "logs\$b-$v-$([int][bool]$Spawn)-client.log"
        $s = Start-Process -FilePath $bins[$b] -ArgumentList '--headless', '--path', $here, '--', '--role=server', "--port=$port", $(if ($Spawn) { '--spawn' } else { '--nospawn' }) `
            -RedirectStandardOutput $sl -RedirectStandardError "$sl.err" -NoNewWindow -PassThru
        Start-Sleep -Milliseconds 1500
        $c = Start-Process -FilePath $bins[$b] -ArgumentList '--headless', '--path', $here, '--', '--role=client', "--variant=$v", "--port=$port" `
            -RedirectStandardOutput $cl -RedirectStandardError "$cl.err" -NoNewWindow -PassThru
        $c.WaitForExit(20000) | Out-Null; $s.WaitForExit(20000) | Out-Null
        $crash = (Select-String $cl, "$cl.err" -Pattern 'signal 11|CrashHandler' -Quiet)
        $last = (Get-Content $cl | Where-Object { $_ -match '^(client|build)' }) -join ' | '
        "{0,-8} {1,-9} client_exit={2} server_exit={3} crash_line={4} :: {5}" -f $b, $v, $c.ExitCode, $s.ExitCode, $crash, $last
    }
}

