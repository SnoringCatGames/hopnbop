# H37 exec-a: run GUT per file like .github/workflows/pr-validate.yml.
# One Godot process per file, -gexit, the fail_on_nakama_traffic post-run
# hook, a 300 s timeout, and an empty user:// per file (fresh APPDATA under
# the probe dir; CI uses XDG_DATA_HOME on Linux).
# Usage: run-gut.ps1 -Tag unit -Roots test/unit
#        run-gut.ps1 -Tag rerun -Files test/unit/x/test_a.gd,test/unit/y/test_b.gd
param(
	[string]$Tag = 'unit',
	[string[]]$Roots = @(),
	[string[]]$Files = @(),
	[int]$TimeoutSec = 300
)
$ErrorActionPreference = 'Continue'
$repo = 'C:\Users\lsl\Repositories\hopnbop'
$probe = Join-Path $repo '.claude\probes\H37\h37-exec-a'
$outDir = Join-Path $probe "gut\$Tag"
New-Item -ItemType Directory -Force $outDir | Out-Null
$godot = (Get-Command godot).Source
Set-Location $repo
if ($Files.Count -eq 0) {
	$Files = foreach ($root in $Roots) {
		Get-ChildItem -Path (Join-Path $repo $root) -Recurse -Filter 'test_*.gd' |
			ForEach-Object { $_.FullName.Substring($repo.Length + 1).Replace('\', '/') }
	}
	$Files = $Files | Sort-Object
}
$summary = Join-Path $outDir 'summary.tsv'
"file`texit`ttests`tpassing`tfailing`tpending`tsecs`tflags" | Set-Content $summary -Encoding utf8
$ansi = [regex]'\x1b\[[0-9;]*m'
$i = 0
foreach ($f in $Files) {
	$i++
	$safe = $f.Replace('/', '_')
	$appdata = Join-Path $probe "appdata-gut\$Tag\$i"
	New-Item -ItemType Directory -Force $appdata | Out-Null
	$env:APPDATA = $appdata
	$out = Join-Path $outDir "$safe.out.log"
	$err = Join-Path $outDir "$safe.err.log"
	$start = Get-Date
	$p = Start-Process -FilePath $godot -NoNewWindow -PassThru `
		-RedirectStandardOutput $out -RedirectStandardError $err `
		-ArgumentList @('--headless', '-s', '--path', $repo, 'addons/gut/gut_cmdln.gd',
			"-gtest=res://$f", '-gexit',
			'-gpost_run_script=res://test/hooks/fail_on_nakama_traffic.gd')
	$done = $p.WaitForExit($TimeoutSec * 1000)
	if (-not $done) { try { $p.Kill($true) } catch {}; $rc = 124 } else { $rc = $p.ExitCode }
	$secs = [int]((Get-Date) - $start).TotalSeconds
	$text = $ansi.Replace(((Get-Content $out -Raw) + "`n" + (Get-Content $err -Raw)), '')
	$lines = $text -split "`r?`n"
	function Last-Num([string]$pattern) {
		$m = $lines | Select-String -Pattern $pattern | Select-Object -Last 1
		if ($m) { [int]$m.Matches[0].Groups[1].Value } else { 0 }
	}
	$tests = Last-Num '^Tests\s+(\d+)\s*$'
	$passing = Last-Num '^Passing Tests\s+(\d+)\s*$'
	$failing = Last-Num '^Failing Tests\s+(\d+)\s*$'
	$pending = Last-Num '^Risky/Pending\s+(\d+)\s*$'
	$flags = @()
	if ($rc -eq 124) { $flags += 'TIMEOUT' }
	if ($text -match 'Nothing was run') { $flags += 'NOTHING_RUN' }
	if ($text -match 'NAKAMA TRAFFIC') { $flags += 'NAKAMA_TRAFFIC' }
	if ($text -match 'SCRIPT ERROR') { $flags += 'SCRIPT_ERROR' }
	if ($text -match 'Parse Error') { $flags += 'PARSE_ERROR' }
	if ($text -match 'Unrecognized UID') { $flags += 'UID_WARN' }
	if ($rc -ne 0 -and $rc -ne 124) { $flags += "EXIT_$rc" }
	if ($rc -eq 0 -and $tests -eq 0) { $flags += 'ZERO_TESTS' }
	"$f`t$rc`t$tests`t$passing`t$failing`t$pending`t$secs`t$($flags -join ',')" | Add-Content $summary -Encoding utf8
}
'DONE ' + (Get-Date -Format 'HH:mm:ss') | Add-Content (Join-Path $outDir 'done.txt')
