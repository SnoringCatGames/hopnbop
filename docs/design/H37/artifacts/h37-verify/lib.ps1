# Shared helpers for the h37-verify REST probes (items 4a-4d). Loopback
# only: refuses any stack URL that is not 127.0.0.1. Tokens are redacted
# from every log line. Dot-source, then call Init-Log.
$ErrorActionPreference = 'Stop'
$stack = Get-Content (Join-Path $PSScriptRoot 'stack\stack.json') -Raw | ConvertFrom-Json
$base = $stack.nakama_url
if ($base -notmatch '^http://127\.0\.0\.1:\d+$') { throw "refusing non-loopback $base" }
$script:names = @{}
function Init-Log([string]$path, [string]$title) {
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    $script:out = $path
    Set-Content $path "# $title, $(Get-Date -Format o), local stack $base" -Encoding utf8
}
function Redact([string]$s) {
    $s = $s -replace '"(token|refresh_token)":"[^"]+"', '"$1":"<redacted>"'
    $s = $s -replace 'token=[A-Za-z0-9._-]+', 'token=<redacted>'
    foreach ($k in $script:names.Keys) { $s = $s.Replace($k, $script:names[$k]) }
    return $s
}
function Log([string]$label, $obj, [int]$show = 360) {
    $s = if ($obj -is [string]) { $obj } else { $obj | ConvertTo-Json -Depth 12 -Compress }
    $s = Redact $s
    Add-Content $script:out "## $label`n$s`n" -Encoding utf8
    "## $label :: " + $s.Substring(0, [Math]::Min($show, $s.Length))
}
$basic = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('defaultkey:'))
function Auth([string]$name) {
    $dev = "h37verify-$name-" + [guid]::NewGuid().ToString('N')
    $r = Invoke-RestMethod -Method Post -Uri "$base/v2/account/authenticate/device?create=true&username=h37v$name$((Get-Random -Maximum 99999))" `
        -Headers @{ Authorization = $basic } -ContentType 'application/json' -Body (@{ id = $dev; vars = @{ game_id = 'hopnbop' } } | ConvertTo-Json)
    $acct = Invoke-RestMethod -Uri "$base/v2/account" -Headers @{ Authorization = "Bearer $($r.token)" }
    $script:names[$acct.user.id] = "<user $name>"
    [pscustomobject]@{ name = $name; token = $r.token; id = $acct.user.id; device = $dev }
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
function Members($who, [string]$gid) {
    $r = Api $who Get "/v2/group/$gid/user"
    if ($r -is [string]) { return $r }
    $states = @{ 0 = 'superadmin'; 1 = 'admin'; 2 = 'member'; 3 = 'join_request'; 4 = 'banned' }
    (@($r.group_users) | ForEach-Object { "$(Redact $_.user.id)=$($states[[int]$_.state])" }) -join ', '
}
function Open-Socket($who) {
    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $wsBase = $base -replace '^http', 'ws'
    $ws.ConnectAsync([Uri]"$wsBase/ws?token=$($who.token)&format=json&status=true", [Threading.CancellationToken]::None).Wait(5000) | Out-Null
    [pscustomobject]@{ ws = $ws; pending = $null; buf = [byte[]]::new(65536); acc = [Text.StringBuilder]::new() }
}
function Drain($s, [int]$ms) {
    $msgs = @(); $until = (Get-Date).AddMilliseconds($ms)
    while ((Get-Date) -lt $until) {
        if ($s.ws.State -ne 'Open') { $msgs += "<socket $($s.ws.State)>"; break }
        if ($null -eq $s.pending) {
            $s.pending = $s.ws.ReceiveAsync([ArraySegment[byte]]::new($s.buf), [Threading.CancellationToken]::None)
        }
        $left = [int][Math]::Max(1, ($until - (Get-Date)).TotalMilliseconds)
        try { if (-not $s.pending.Wait($left)) { break } } catch { $msgs += "<receive failed: $($_.Exception.InnerException.Message)>"; $s.pending = $null; break }
        $res = $s.pending.Result; $s.pending = $null
        [void]$s.acc.Append([Text.Encoding]::UTF8.GetString($s.buf, 0, $res.Count))
        if ($res.EndOfMessage) { $msgs += $s.acc.ToString(); [void]$s.acc.Clear() }
        if ($res.MessageType -eq 'Close') { $msgs += "<socket closed by server: $($s.ws.CloseStatus) $($s.ws.CloseStatusDescription)>"; break }
    }
    return ,$msgs
}
function NewParty($who) {
    $rand = -join ((48..57) + (97..102) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
    Api $who Post '/v2/group' @{ name = "party-h37v$rand"; lang_tag = 'en'; open = $false; max_count = 4 }
}
function Payload($r) { if ($r -is [string]) { return $r }; try { $r.payload | ConvertFrom-Json } catch { $r } }
function Send($s, [string]$json) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $s.ws.SendAsync([ArraySegment[byte]]::new($bytes), 'Text', $true, [Threading.CancellationToken]::None).Wait(3000) | Out-Null
}
function Close-Socket($s) {
    try { $s.ws.CloseAsync('NormalClosure', 'probe quit', [Threading.CancellationToken]::None).Wait(3000) | Out-Null } catch {}
}
function ReadyRows($who, [string]$gid, $users) {
    $ids = @($users | ForEach-Object { @{ collection = 'party_ready'; key = $gid; user_id = $_.id } })
    $r = Api $who Post '/v2/storage' @{ object_ids = $ids }
    if ($r -is [string]) { return $r }
    (@($r.objects) | ForEach-Object { "$(Redact $_.user_id)=$($_.value)" }) -join ', '
}
function Online($who, [string]$gid) {
    $r = Api $who Get "/v2/group/$gid/user"
    if ($r -is [string]) { return $r }
    (@($r.group_users) | ForEach-Object { "$(Redact $_.user.id) online=$([bool]$_.user.online)" }) -join ', '
}
