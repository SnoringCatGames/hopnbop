param([string]$Out)
$h = "C:\Users\lsl\Repositories\hopnbop"
$nc = "$h\addons\rollback_netcode"
function Parse-Blame($raw) {
  $recs = New-Object System.Collections.Generic.List[object]; $cur = $null; $meta = @{}
  foreach ($line in $raw) {
    if ($line -match '^([0-9a-f]{40}) (\d+) (\d+)') {
      $cur = [ordered]@{ sha = $Matches[1].Substring(0,8); final = [int]$Matches[3]; time = $null; summary = ''; text = '' }
      if ($meta.ContainsKey($cur.sha)) { $cur.time = $meta[$cur.sha].time; $cur.summary = $meta[$cur.sha].summary }
    }
    elseif ($line -match '^author-time (\d+)') { $cur.time = [DateTimeOffset]::FromUnixTimeSeconds([int64]$Matches[1]).ToOffset([TimeSpan]::FromHours(-7)).ToString('yyyy-MM-dd') }
    elseif ($line -match '^summary (.*)') { $cur.summary = $Matches[1]; $meta[$cur.sha] = @{ time = $cur.time; summary = $cur.summary } }
    elseif ($line.StartsWith("`t")) { $cur.text = $line.Substring(1); $recs.Add([pscustomobject]$cur) }
  }
  return $recs
}
$a = Parse-Blame (git -C $nc blame --line-porcelain 6022552 -L 46,875 -- core/frame_driver.gd)
$b = Parse-Blame (git -C $h blame --line-porcelain -M -C 26966654 -L 46,870 -- addons/rollback_netcode/core/frame_driver.gd)
$todo = Get-Content "$h\TODO-scratch.md"
$j = 0; $rows = @()
for ($i = 0; $i -lt $a.Count; $i++) {
  $r = $a[$i]; $tl = $r.final - 37
  $date = $r.time; $sha = $r.sha; $src = 'nc'
  if ($r.sha -eq '78427ce0') {
    $found = -1
    for ($k = $j; $k -lt [Math]::Min($b.Count, $j + 60); $k++) { if ($b[$k].text.Trim() -eq $r.text.Trim()) { $found = $k; break } }
    if ($found -ge 0) { $date = $b[$found].time; $sha = $b[$found].sha; $src = 'hb'; $j = $found + 1 } else { $src = 'nomatch' }
  }
  if ($todo[$tl - 1].Trim() -ne $r.text.Trim()) { $src += '!textdiff' }
  $rows += [pscustomobject]@{ line = $tl; date = $date; sha = $sha; src = $src }
}
$rows | Export-Csv -NoTypeInformation -Path $Out
# Print compact runs by date
$runs = @(); foreach ($x in $rows) { if ($runs.Count -and $runs[-1].date -eq $x.date -and $runs[-1].end -eq $x.line - 1) { $runs[-1].end = $x.line } else { $runs += [pscustomobject]@{ start = $x.line; end = $x.line; date = $x.date; src = $x.src } } }
$runs | ForEach-Object { "{0}-{1} {2} {3}" -f $_.start, $_.end, $_.date, $_.src }
