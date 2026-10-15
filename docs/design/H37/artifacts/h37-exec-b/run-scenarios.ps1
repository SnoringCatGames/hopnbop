# Runs harness scenarios one after another, re-runs a failure once, and
# appends one compact line per attempt to a results file. H37 exec-b.
param(
    [Parameter(Mandatory)][string[]]$Names,
    [string]$OutDir = 'C:\Users\lsl\Repositories\hopnbop\.claude\probes\H37\h37-exec-b\runs',
    [string]$ResultFile = 'C:\Users\lsl\Repositories\hopnbop\.claude\probes\H37\h37-exec-b\results.md',
    [string[]]$ExtraArgs = @(),
    [int]$Retries = 1
)
$ErrorActionPreference = 'Continue'
$repo = 'C:\Users\lsl\Repositories\hopnbop'
$runner = Join-Path $repo 'scripts\agent\run-game.ps1'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$Names = @($Names | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($name in $Names) {
    for ($attempt = 1; $attempt -le 1 + $Retries; $attempt++) {
        $t0 = Get-Date
        $out = & pwsh -NoProfile -File $runner -Scenario $name -OutDir $OutDir @ExtraArgs 2>&1 | Out-String
        $code = $LASTEXITCODE
        $sec = [math]::Round(((Get-Date) - $t0).TotalSeconds, 0)
        $m = [regex]::Match($out, 'summary: (.+?summary\.json)')
        $label = [IO.Path]::GetFileNameWithoutExtension($name)
        if (-not $m.Success) {
            $tail = ($out -split "`n" | Select-Object -Last 6) -join ' | '
            Add-Content $ResultFile -Encoding utf8 ("- {0} attempt {1}: exit={2} {3}s NO SUMMARY. tail: {4}" -f $label, $attempt, $code, $sec, $tail)
            break
        }
        $summaryPath = $m.Groups[1].Value.Trim()
        $s = Get-Content $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $runRel = $s.run_dir.Replace($repo + '\', '')
        $parts = foreach ($p in $s.processes) {
            $r = $p.result
            $res = if ($r) { 'AGENT_RESULT ok={0} exit_code={1} steps={2}/{3} elapsed={4}s failures={5}' -f $r.ok, $r.exit_code, $r.steps_run, $r.steps_total, $r.elapsed_sec, @($r.failures).Count } else { 'no AGENT_RESULT' }
            $why = if (-not $p.ok) { ' reasons: ' + ((@($p.reasons) | ForEach-Object { ($_ -replace '\s+', ' ') }) -join ' ; ') } else { '' }
            '{0}[{1}] {2} errors={3} script_errors={4} teardown={5}{6}' -f $p.name, $(if ($p.ok) { 'PASS' } else { 'FAIL' }), $res, $p.errors, $p.script_errors, $p.teardown_errors, $why
        }
        $verdict = if ($s.ok) { 'PASS' } else { 'FAIL' }
        Add-Content $ResultFile -Encoding utf8 ('- {0} attempt {1}: {2} exit={3} {4}s run=`{5}` :: {6}' -f $label, $attempt, $verdict, $code, $sec, $runRel, ($parts -join ' || '))
        if ($s.ok) { break }
    }
}
Add-Content $ResultFile -Encoding utf8 ("<!-- batch done {0} -->" -f (Get-Date -Format 'HH:mm:ss'))


