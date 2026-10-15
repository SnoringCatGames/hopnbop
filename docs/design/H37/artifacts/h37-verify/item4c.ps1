# H37 verify 4c: a party member whose client is gone. Does
# party_start_matchmaking wait, fail or go ahead, and what do the others
# see? Emulates the clients' wire calls (SDK party_api_client.gd,
# matchmaker_api_client.gd:363-390). Local stack only. Output: item4c/raw.txt.
. (Join-Path $PSScriptRoot 'lib.ps1')
Init-Log (Join-Path $PSScriptRoot 'item4c\raw.txt') 'item 4c raw responses'
$A = Auth 'A'; $B = Auth 'B'; $C = Auth 'C'
$g = NewParty $A
$code = (Payload (Rpc $A 'party_get_invite_code' @{ party_id = $g.id })).code
Log '1 B and C join by code' ("B: " + (Payload (Rpc $B 'party_join_by_code' @{ code = $code })).ok + ", C: " + (Payload (Rpc $C 'party_join_by_code' @{ code = $code })).ok)
$sA = Open-Socket $A; $sB = Open-Socket $B; $sC = Open-Socket $C
foreach ($u in $A, $B, $C) { Log "2 $($u.name) party_set_ready true" (Rpc $u 'party_set_ready' @{ party_id = $g.id; ready = $true }) 120 }
Log '2r ready rows' (ReadyRows $A $g.id @($A, $B, $C))
Close-Socket $sB; Start-Sleep -Milliseconds 1500
Log '3 B quits (socket closed); members as A sees them' (Online $A $g.id)
Log '3r ready rows after B quit' (ReadyRows $A $g.id @($A, $B, $C))
[void](Drain $sA 500); [void](Drain $sC 500)
Send $sA '{"cid":"1","party_create":{"open":true,"max_size":4}}'
$m = Drain $sA 1500
$rt = ''; foreach ($x in $m) { if ($x -match '"party_id":"([^"]+)"') { $rt = $Matches[1]; break } }
Log '4 A creates the realtime party (socket party_create)' "rt party id length $($rt.Length)"
Log '5 A party_start_matchmaking with B gone' (Rpc $A 'party_start_matchmaking' @{ party_id = $g.id; rt_party_id = $rt; game_mode = '' })
Log '5a A socket' (Drain $sA 2000) 600
Log '5c C socket' (Drain $sC 2000) 600
Send $sC ('{"cid":"2","party_join":{"party_id":"' + $rt + '"}}')
Log '6 C joins the realtime party; C socket' (Drain $sC 1500) 300
Log '6a A socket (presences)' (Drain $sA 1500) 300
Log '7 A party_abort_matchmaking members_never_joined (what the leader client sends after 20 s)' (Rpc $A 'party_abort_matchmaking' @{ party_id = $g.id; reason = 'members_never_joined' })
Log '7a A socket' (Drain $sA 1500) 400
Log '7c C socket' (Drain $sC 1500) 400
Log '8 B returns: B notifications (persistent only)' ((Api $B Get '/v2/notification?limit=100').notifications | ForEach-Object { "code $($_.code) $($_.subject)" })
Log '8r ready rows when B returns' (ReadyRows $B $g.id @($A, $B, $C))
Log '9 A starts again with B still gone' (Rpc $A 'party_start_matchmaking' @{ party_id = $g.id; rt_party_id = $rt; game_mode = '' })
Close-Socket $sA; Close-Socket $sC
