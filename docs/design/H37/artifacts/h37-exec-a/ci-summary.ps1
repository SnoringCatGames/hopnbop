# H37 exec-a: summarize gh run list JSON fetched into ci/<repo>-runs.json.
$out = 'C:\Users\lsl\Repositories\hopnbop\.claude\probes\H37\h37-exec-a\ci'
$since = [datetime]'2026-09-30T00:00:00Z'
foreach ($name in @('hopnbop', 'snoringcat-platform', 'godot-rollback-netcode')) {
	$runs = Get-Content "$out\$name-runs.json" -Raw | ConvertFrom-Json -DateKind String
	"=== ${name}: newest run per workflow on main"
	$runs | Where-Object { $_.headBranch -eq 'main' } | Group-Object workflowName | ForEach-Object {
		$n = $_.Group | Sort-Object createdAt -Descending | Select-Object -First 1
		'{0} | {1} | {2} | {3}/{4} | {5}' -f $_.Name, $n.createdAt.Substring(0, 16), $n.event, $n.status, $n.conclusion, $n.databaseId
	}
	'--- newest per workflow, any branch, with event counts in the fetched window'
	$runs | Group-Object workflowName | ForEach-Object {
		$n = $_.Group | Sort-Object createdAt -Descending | Select-Object -First 1
		$events = ($_.Group | Group-Object event | ForEach-Object { "$($_.Name)x$($_.Count)" }) -join ','
		$branches = ($_.Group | Group-Object headBranch | ForEach-Object { "$($_.Name)x$($_.Count)" }) -join ','
		'{0} | newest {1} {2} on {3} {4}/{5} | events: {6} | branches: {7}' -f $_.Name, $n.createdAt.Substring(0, 16), $n.event, $n.headBranch, $n.status, $n.conclusion, $events, $branches
	}
	'--- non-success since 2026-09-30'
	$runs | Where-Object { [datetime]$_.createdAt -ge $since -and $_.conclusion -notin @('success', 'skipped', '') } |
		Sort-Object createdAt | ForEach-Object {
			$t = $_.displayTitle; if ($t.Length -gt 60) { $t = $t.Substring(0, 60) }
			'{0} | {1} | {2} | {3} | {4} | {5} | {6}' -f $_.createdAt.Substring(0, 16), $_.workflowName, $_.event, $_.headBranch, $_.conclusion, $_.databaseId, $t
		}
	'--- in progress / queued'
	$runs | Where-Object { $_.status -ne 'completed' } | ForEach-Object {
		'{0} | {1} | {2} | {3}' -f $_.createdAt.Substring(0, 16), $_.workflowName, $_.status, $_.databaseId
	}
}
