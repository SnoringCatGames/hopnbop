# H37 verify item 3: is a party invite a forced join? Loopback REST + one
# websocket against this agent's own local dev stack (project h37verify).
# Tokens are never written out. Output: item3/raw.txt.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$stack = Get-Content (Join-Path $here 'stack\stack.json') -Raw | ConvertFrom-Json
$base = $stack.nakama_url
if ($base -notmatch '^http://127\.0\.0\.1:\d+$') { throw "refusing non-loopback $base" }
$out = Join-Path $here 'item3\raw.txt'
Set-Content $out "# item 3 raw responses, $(Get-Date -Format o), stack $base" -Encoding utf8
function Log([string]$label, $obj) {
    $s = if ($obj -is [string]) { $obj } else { $obj | ConvertTo-Json -Depth 12 -Compress }
    $s = $s -replace '"(token|refresh_token)":"[^"]+"', '"$1":"<redacted>"'
    Add-Content $out "## $label`n$s`n" -Encoding utf8
    "## $label"; $s.Substring(0, [Math]::Min(700, $s.Length))
}
$basic = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('defaultkey:'))
function Auth([string]$name) {
    $dev = "h37verify-$name-" + [guid]::NewGuid().ToString('N')
    $r = Invoke-RestMethod -Method Post -Uri "$base/v2/account/authenticate/device?create=true&username=h37v$name$((Get-Random -Maximum 99999))" `
        -Headers @{ Authorization = $basic } -ContentType 'application/json' -Body (@{ id = $dev; vars = @{ game_id = 'hopnbop' } } | ConvertTo-Json)
    $tok = $r.token
    $acct = Invoke-RestMethod -Uri "$base/v2/account" -Headers @{ Authorization = "Bearer $tok" }
    [pscustomobject]@{ name = $name; token = $tok; id = $acct.user.id }
}
function Api($who, [string]$method, [string]$path, $body = $null) {
    $h = @{ Authorization = "Bearer $($who.token)" }
    try {
        if ($null -ne $body) {
            Invoke-RestMethod -Method $method -Uri "$base$path" -Headers $h -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 8 -Compress)
        } else { Invoke-RestMethod -Method $method -Uri "$base$path" -Headers $h }
    } catch { "HTTP ERROR: $($_.Exception.Message) $($_.ErrorDetails.Message)" }
}
function Rpc($who, [string]$id, $payload) {
    $inner = $payload | ConvertTo-Json -Depth 8 -Compress
    $h = @{ Authorization = "Bearer $($who.token)" }
    try {
        Invoke-RestMethod -Method Post -Uri "$base/v2/rpc/$id" -Headers $h -ContentType 'application/json' -Body ($inner | ConvertTo-Json -Compress)
    } catch { "RPC ERROR: $($_.Exception.Message) $($_.ErrorDetails.Message)" }
}
$A = Auth 'A'; $B = Auth 'B'; $C = Auth 'C'
Log 'users (local throwaway)' ([ordered]@{ A = $A.id; B = $B.id; C = $C.id })

# B's realtime socket, open for the whole run.
$ws = [System.Net.WebSockets.ClientWebSocket]::new()
$wsBase = $base -replace '^http', 'ws'
$ws.ConnectAsync([Uri]"$wsBase/ws?token=$($B.token)&format=json&status=true", [Threading.CancellationToken]::None).Wait(5000) | Out-Null
$script:pending = $null; $script:buf = [byte[]]::new(65536); $script:acc = [Text.StringBuilder]::new()
function Drain([int]$ms) {
    $msgs = @(); $until = (Get-Date).AddMilliseconds($ms)
    while ((Get-Date) -lt $until) {
        if ($null -eq $script:pending) {
            $script:pending = $ws.ReceiveAsync([ArraySegment[byte]]::new($script:buf), [Threading.CancellationToken]::None)
        }
        $left = [int][Math]::Max(1, ($until - (Get-Date)).TotalMilliseconds)
        if (-not $script:pending.Wait($left)) { break }
        $res = $script:pending.Result; $script:pending = $null
        [void]$script:acc.Append([Text.Encoding]::UTF8.GetString($script:buf, 0, $res.Count))
        if ($res.EndOfMessage) { $msgs += $script:acc.ToString(); [void]$script:acc.Clear() }
        if ($res.MessageType -eq 'Close') { $msgs += '<socket closed>'; break }
    }
    return ,$msgs
}
Log 'B socket state' "$($ws.State)"
Log 'B socket, before anything' (Drain 1500)

# 1. A creates a party and invites B (no friendship, nothing accepted).
$rand = -join ((48..57) + (97..102) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
$gA = Api $A Post '/v2/group' @{ name = "party-h37vA$rand"; open = $false; max_count = 4 }
Log '1a A creates party (POST /v2/group)' $gA
Log '1b A party_invite B' (Rpc $A 'party_invite' @{ party_id = $gA.id; target_id = $B.id })
Log '1c B reads own groups (GET /v2/user/B/group)' (Api $B Get "/v2/user/$($B.id)/group")
Log '1d A reads party members (GET /v2/group/A/user)' (Api $A Get "/v2/group/$($gA.id)/user")
Log '1e B notifications (GET /v2/notification)' (Api $B Get '/v2/notification?limit=100')
Log '1f B socket after step 1' (Drain 2000)

# 2. B blocks C; C creates a party and invites B.
Log '2a B blocks C (POST /v2/friend/block)' (Api $B Post "/v2/friend/block?ids=$($C.id)")
Log '2b B friend list after block' (Api $B Get '/v2/friend?limit=100')
$gC = Api $C Post '/v2/group' @{ name = "party-h37vC$rand"; open = $false; max_count = 4 }
Log '2c C creates party' $gC
Log '2d C party_invite B (B blocks C)' (Rpc $C 'party_invite' @{ party_id = $gC.id; target_id = $B.id })
Log '2e B reads own groups again' (Api $B Get "/v2/user/$($B.id)/group")
Log '2f B notifications again' (Api $B Get '/v2/notification?limit=100')
Log '2g B socket after step 2' (Drain 2000)

# 3. A (leader, A+B in A's party) starts matchmaking.
Log '3a A party_start_matchmaking' (Rpc $A 'party_start_matchmaking' @{ party_id = $gA.id; game_mode = '' })
Log '3b B socket after start (4 s)' (Drain 4000)
Log '3c B notifications after start' (Api $B Get '/v2/notification?limit=100')
Log '3d B groups at end' (Api $B Get "/v2/user/$($B.id)/group")
try { $ws.CloseAsync('NormalClosure', 'done', [Threading.CancellationToken]::None).Wait(2000) | Out-Null } catch {}
"done $(Get-Date -Format HH:mm:ss)"

