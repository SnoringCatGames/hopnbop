# H37 h37-verify item 4e addendum: once a server registers (as an
# Edgegap server does at boot), can an unrelated player list the
# registration? Loopback only (lib.ps1). The HTTP key is the dev stack's
# fixed public value (infra/dev), and the IP/port are dummies.
param([Parameter(Mandatory)] [string]$RequestId)
. "$PSScriptRoot\lib.ps1"
Init-Log (Join-Path $PSScriptRoot 'item4e\raw-reg.txt') 'item 4e addendum: registration visibility'
$body = @{ request_id = $RequestId; server_ip = '127.0.0.1'; server_port = 14433; server_fqdn = 'h37-dummy.invalid' } | ConvertTo-Json -Compress
$r = try { Invoke-RestMethod -Method Post -Uri "$base/v2/rpc/register_server?http_key=defaulthttpkey&unwrap" -ContentType 'application/json' -Body $body } catch { "HTTP ERROR: $($_.Exception.Message) $($_.ErrorDetails.Message)" }
Log 'server-key register_server (what a booting server sends)' ($r | ConvertTo-Json -Compress)
$y = Auth 'Y'
$sys = '00000000-0000-0000-0000-000000000000'
$lr = Api $y Get "/v2/storage/server_registrations?user_id=$sys&limit=50"
Log 'unrelated user Y lists server_registrations' ($lr | ConvertTo-Json -Depth 6 -Compress) 700
$rows = & docker exec h37verify-postgres-1 psql -U nakama -d nakama -t -A -F ' | ' -c "select collection, key, read from storage where collection in ('match_metadata','server_registrations') order by create_time" 2>&1
Log 'db rows' (($rows | ForEach-Object { "$_" }) -join "`n")
