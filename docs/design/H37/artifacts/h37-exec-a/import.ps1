# H37 exec-a: run `godot --headless --path . --import` like scripts/ci/godot-import.sh.
# Retries once on a crash (Windows: negative or > 255 exit code, or a
# timeout), then checks that class_names registered (GutTest in the cache).
# Throwaway APPDATA so editor settings / user:// stay out of Levi's profile.
param([int]$TimeoutSec = 900)
$ErrorActionPreference = 'Continue'
$repo = 'C:\Users\lsl\Repositories\hopnbop'
$probe = Join-Path $repo '.claude\probes\H37\h37-exec-a'
$godot = (Get-Command godot).Source
$results = @()
for ($attempt = 1; $attempt -le 2; $attempt++) {
	$appdata = Join-Path $probe "appdata-import-$attempt"
	New-Item -ItemType Directory -Force $appdata | Out-Null
	$out = Join-Path $probe "import-$attempt.out.log"
	$err = Join-Path $probe "import-$attempt.err.log"
	$env:APPDATA = $appdata
	$start = Get-Date
	$p = Start-Process -FilePath $godot -ArgumentList @('--headless', '--path', $repo, '--import') `
		-RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru
	$done = $p.WaitForExit($TimeoutSec * 1000)
	if (-not $done) { try { $p.Kill($true) } catch {} ; $rc = 'timeout' } else { $rc = $p.ExitCode }
	$secs = [int]((Get-Date) - $start).TotalSeconds
	$results += "attempt $attempt : exit $rc after ${secs}s"
	$crashed = ($rc -eq 'timeout') -or ($rc -lt 0) -or ($rc -gt 255)
	if (-not $crashed) { break }
}
$results
$cache = Join-Path $repo '.godot\global_script_class_cache.cfg'
if (Select-String -Path $cache -Pattern '"GutTest"' -Quiet) { 'class cache: GutTest registered' } else { 'class cache: GutTest MISSING' }
'cache mtime: ' + (Get-Item $cache).LastWriteTime
