# H37 verify 4b: with more than 50 notifications stored for one user, does
# the client's HTTP poll (limit 50, blank cursor, friends_api_client.gd:252)
# ever return a newer one? Local stack only. Output: item4b/raw.txt.
. (Join-Path $PSScriptRoot 'lib.ps1')
Init-Log (Join-Path $PSScriptRoot 'item4b\raw.txt') 'item 4b raw responses'
function Summ($r, $who) {
    if ($r -is [string]) { return $r }
    $ns = @($r.notifications)
    $codes = ($ns | Group-Object code | ForEach-Object { "code $($_.Name) x$($_.Count)" }) -join ', '
    $fr = @($ns | Where-Object { $_.code -eq -2 })
    [ordered]@{ count = $ns.Count; codes = $codes
        first = if ($ns) { "$($ns[0].create_time) $($ns[0].subject)" } else { '' }
        last = if ($ns) { "$($ns[-1].create_time) $($ns[-1].subject)" } else { '' }
        has_friend_request = ($fr.Count -gt 0)
        cacheable_cursor_present = [bool]$r.cacheable_cursor }
}
$A = Auth 'A'; $B = Auth 'B'; $C = Auth 'C'
$g = NewParty $A
$n = 55; $t0 = Get-Date; $done = 0
for ($i = 1; $i -le $n; $i++) {
    $r = Rpc $A 'party_invite' @{ party_id = $g.id; target_id = $B.id }
    if ($r -is [string]) { Log "invite $i failed" $r; break }
    $l = Api $B Post "/v2/group/$($g.id)/leave"
    if ($l -is [string]) { Log "leave $i failed" $l; break }
    $done = $i
}
Log '1 fill' "$done party_invite + leave cycles (A invites B, B leaves) in $([int]((Get-Date) - $t0).TotalSeconds) s"
Log '2 B lists everything (limit=100)' (Summ (Api $B Get '/v2/notification?limit=100'))
Start-Sleep -Milliseconds 1500
Log '3 C sends B a friend request (POST /v2/friend?ids=B)' (Api $C Post "/v2/friend?ids=$($B.id)")
Log '3b B lists everything (limit=100)' (Summ (Api $B Get '/v2/notification?limit=100'))
$p1 = Api $B Get '/v2/notification?limit=50'
Log '4 B polls as the client does (limit=50, no cursor)' (Summ $p1)
Start-Sleep -Milliseconds 1000
Log '5 same poll again' (Summ (Api $B Get '/v2/notification?limit=50'))
if ($p1 -isnot [string] -and $p1.cacheable_cursor) {
    $cc = [uri]::EscapeDataString($p1.cacheable_cursor)
    Log '6 poll with the returned cacheable_cursor (what a fix would send)' (Summ (Api $B Get "/v2/notification?limit=50&cacheable_cursor=$cc"))
}
