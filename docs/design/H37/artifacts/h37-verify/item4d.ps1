# H37 verify 4d: H15 end to end. A harness client (guest, local stack via
# -Backend) opens the matchmaking socket, logs out, then a new guest signs
# in. This script plays user A: it sends player 1 (X) notifications before
# and after the log-out and records what the client's recorder saw and what
# Nakama reports. Local stack only. Output: item4d/raw.txt.
. (Join-Path $PSScriptRoot 'lib.ps1')
Init-Log (Join-Path $PSScriptRoot 'item4d\raw.txt') 'item 4d raw responses'
$repo = 'C:\Users\lsl\Repositories\hopnbop'
$runs = Join-Path $PSScriptRoot 'runs'
$scen = Join-Path $PSScriptRoot 'scenarios\h37v-h15-logout.json'
$outFile = Join-Path $PSScriptRoot 'item4d\harness.out.txt'
$t0 = Get-Date
$p = Start-Process pwsh -PassThru -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError "$outFile.err" `
    -ArgumentList @('-NoProfile', '-File', "$repo\scripts\agent\run-game.ps1", '-Scenario', $scen, '-Backend', $base, '-OutDir', $runs, '-Headless')
function FindLog {
    $d = Get-ChildItem $runs -Directory -ErrorAction SilentlyContinue | Where-Object { $_.CreationTime -ge $t0.AddSeconds(-2) -and $_.Name -like '*h37v-h15-logout*' } |
        Sort-Object CreationTime | Select-Object -Last 1
    if ($d) { Get-ChildItem $d.FullName -Recurse -Filter process.log | Select-Object -First 1 }
}
function WaitLine([string]$pat, [int]$sec) {
    $until = (Get-Date).AddSeconds($sec)
    while ((Get-Date) -lt $until) {
        $f = FindLog
        if ($f) { $m = Select-String -Path $f.FullName -Pattern $pat | Select-Object -Last 1; if ($m) { return (Redact $m.Line) } }
        if ($p.HasExited) { return "<harness exited $($p.ExitCode) before $pat>" }
        Start-Sleep -Milliseconds 300
    }
    return "<timeout waiting for $pat>"
}
$l = WaitLine 'H37UID1 ' 120
if ($l -notmatch 'H37UID1 (\S+)') { Log '0 harness did not report a user id' $l; return }
$X = [pscustomobject]@{ id = $Matches[1] }; $script:names[$X.id] = '<user X>'
Log '0 player 1 (guest) signed in and opened the matchmaking socket' (Redact $l)
Log '0s' (WaitLine 'H37SOCK1 ' 5)
$A = Auth 'A'
$g1 = NewParty $A
Log '1 phase 1, before log-out: A party_invite X' (Rpc $A 'party_invite' @{ party_id = $g1.id; target_id = $X.id })
Start-Sleep -Milliseconds 1500
Log '1o members as A sees them' (Online $A $g1.id)
Log '1c client recorder count' (WaitLine 'H37PHASE1 ' 30)
Log '2 client right after log-out' (WaitLine 'H37AFTER sock=' 40)
Log '2b' (WaitLine 'H37AFTER connected=' 10)
Log '2o members as A sees them after the log-out' (Online $A $g1.id)
$g2 = NewParty $A
Log '3 phase 2, after log-out: A party_invite X into a second party' (Rpc $A 'party_invite' @{ party_id = $g2.id; target_id = $X.id })
Log '3s A party_start_matchmaking on the second party (X a member)' (Rpc $A 'party_start_matchmaking' @{ party_id = $g2.id; rt_party_id = ''; game_mode = '' })
Start-Sleep -Milliseconds 1500
Log '3o members of the second party' (Online $A $g2.id)
Log '3c client recorder count' (WaitLine 'H37PHASE2 ' 30)
Log '4 next player signs in as a new guest and calls ensure_socket' (WaitLine 'H37RESIGN sock=' 30)
Log '4b' (WaitLine 'H37RESIGN connected=' 10)
$g3 = NewParty $A
Log '5 phase 3, player 2 signed in: A party_invite X into a third party' (Rpc $A 'party_invite' @{ party_id = $g3.id; target_id = $X.id })
Log '5c client recorder count' (WaitLine 'H37PHASE3 ' 30)
$pl = WaitLine 'rt party created: ' 30
Log '8 player 2 creates a realtime party (create_rt_party) over the reused socket' $pl
if ($pl -match 'rt party created: (\S+)') {
    $rt = $Matches[1]
    $sA = Open-Socket $A
    [void](Drain $sA 500)
    Send $sA ('{"cid":"9","party_join":{"party_id":"' + $rt + '"}}')
    Log '8j A joins it; the party as Nakama reports it (leader and presences)' (Drain $sA 2000) 900
    Close-Socket $sA
}$p.WaitForExit(90000) | Out-Null
$f = FindLog
Log '6 run dir' ($f.Directory.Parent.Name)
Log '6r recorder and result lines' ((Select-String -Path $f.FullName -Pattern 'H37REC|AGENT_RESULT' | ForEach-Object { Redact $_.Line }) -join "`n") 3000
Log '7 harness stdout tail' ((Get-Content $outFile -Tail 4) -join "`n") 600

