# H37 verify 4a: can a party's creator leave, and can anything disband a
# party? Local stack only. Output: item4a/raw.txt.
. (Join-Path $PSScriptRoot 'lib.ps1')
Init-Log (Join-Path $PSScriptRoot 'item4a\raw.txt') 'item 4a raw responses'
$A = Auth 'A'; $B = Auth 'B'; $C = Auth 'C'
$g = NewParty $A
Log '1 A creates a party as the SDK does (POST /v2/group, closed, max 4)' $g
$code = (Payload (Rpc $A 'party_get_invite_code' @{ party_id = $g.id })).code
Log '2 A party_get_invite_code' "code length $("$code".Length)"
Log '3 B party_join_by_code' (Rpc $B 'party_join_by_code' @{ code = $code })
Log '3m members' (Members $A $g.id)
Log '4 A (creator) leaves: POST /v2/group/{id}/leave' (Api $A Post "/v2/group/$($g.id)/leave")
Log '4m members' (Members $A $g.id)
Log '5 A party_transfer_leadership to B' (Rpc $A 'party_transfer_leadership' @{ party_id = $g.id; target_user_id = $B.id })
Log '5m members' (Members $A $g.id)
Log '6 A leaves again after the transfer' (Api $A Post "/v2/group/$($g.id)/leave")
Log '6m members' (Members $A $g.id)
Log '7 B (now leader) kicks A: POST /v2/group/{id}/kick?user_ids=A' (Api $B Post "/v2/group/$($g.id)/kick?user_ids=$($A.id)")
Log '7m members' (Members $B $g.id)
Log '8 C party_join_by_code (same code)' (Rpc $C 'party_join_by_code' @{ code = $code })
Log '8a A (superadmin) kicks C' (Api $A Post "/v2/group/$($g.id)/kick?user_ids=$($C.id)")
Log '8m members after kick' (Members $A $g.id)
Log '8b C rejoins with the same code' (Rpc $C 'party_join_by_code' @{ code = $code })
Log '8n members after rejoin' (Members $A $g.id)
Log '9 B (admin) deletes the party: DELETE /v2/group/{id}' (Api $B Delete "/v2/group/$($g.id)")
Log '9m members' (Members $A $g.id)
Log '10 A (creator) deletes the party: DELETE /v2/group/{id}' (Api $A Delete "/v2/group/$($g.id)")
Log '10m B groups after delete' ((Api $B Get "/v2/user/$($B.id)/group").user_groups | ForEach-Object { $_.group.name })

