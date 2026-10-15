# H37 h37-verify item 4e (runtime half): what the runtime keeps for a
# match that nobody ends or cancels. Two device users matchmake on the
# local stack (EDGEGAP_MOCK_DEPLOY=true allocates nothing real); no game
# server ever reports, as in the all-dropped production quit. Loopback
# only: lib.ps1 refuses any other base URL. The HTTP key below is the
# dev stack's fixed public value (infra/dev), not a production key.
. "$PSScriptRoot\lib.ps1"
$out = Join-Path $PSScriptRoot 'item4e'
New-Item -ItemType Directory -Force $out | Out-Null
Init-Log (Join-Path $out 'raw.txt') 'item 4e: rows of a match nobody ends'
$pv = (Select-String -Path 'C:\Users\lsl\Repositories\hopnbop\project.godot' -Pattern '^config/protocol_version=(\d+)').Matches[0].Groups[1].Value
function Rows([string]$label) {
    $q = "select collection, key, read, to_char(create_time,'HH24:MI:SS'), value from storage where collection in ('match_metadata','server_registrations','synthetic_matches') order by create_time"
    $rows = & docker exec h37verify-postgres-1 psql -U nakama -d nakama -t -A -F ' | ' -c $q 2>&1
    Log $label ("rows=" + @($rows | Where-Object { "$_".Trim() }).Count + "`n" + (($rows | ForEach-Object { "$_" }) -join "`n")) 900
    return $rows
}
Rows 'db before'
$p1 = Auth 'P1'; $p2 = Auth 'P2'; $z = Auth 'Z'
$s1 = Open-Socket $p1; $s2 = Open-Socket $p2
$props = [ordered]@{ platform = 'native'; player_count = '1'; game_id = 'hopnbop'; client_protocol_version = $pv; game_mode = 'ffa' }
$t0 = Get-Date
foreach ($s in @($s1, $s2)) {
    Send $s (@{ cid = '1'; matchmaker_add = @{ query = '+properties.game_mode:ffa'; min_count = 2; max_count = 4; string_properties = $props; numeric_properties = @{} } } | ConvertTo-Json -Depth 6 -Compress)
}
$got = @{ P1 = $null; P2 = $null }
while (((Get-Date) - $t0).TotalSeconds -lt 90 -and (-not $got.P1 -or -not $got.P2)) {
    foreach ($pair in @(@('P1', $s1), @('P2', $s2))) {
        foreach ($m in (Drain $pair[1] 1000)) {
            $sec = [int]((Get-Date) - $t0).TotalSeconds
            $j = $null; try { $j = $m | ConvertFrom-Json } catch {}
            if ($j -and $j.notifications) {
                foreach ($n in $j.notifications.notifications) {
                    $c = $null; try { $c = ($n.content | ConvertFrom-Json).connection | ConvertFrom-Json } catch {}
                    Log "$($pair[0]) t+$sec notification" ("code=$($n.code) subject=$($n.subject) persistent=$($n.persistent) server=$($c.server_ip):$($c.server_port) content_keys=" + (($c.PSObject.Properties.Name) -join ','))
                    if ($n.subject -eq 'match_ready') { $got[$pair[0]] = $sec }
                }
            } elseif ($j -and $j.matchmaker_matched) {
                Log "$($pair[0]) t+$sec matchmaker_matched" ("users=" + @($j.matchmaker_matched.users).Count)
            } elseif ($j -and $j.matchmaker_ticket) {
                Log "$($pair[0]) t+$sec ticket" 'ok'
            } else { Log "$($pair[0]) t+$sec other" $m 200 }
        }
    }
}
Log 'match_ready seconds' ("P1=$($got.P1) P2=$($got.P2)")
# No game server reports: drop both players, as in the all-dropped case.
Close-Socket $s1; Close-Socket $s2
$rows = Rows 'db after allocation, no report'
$rid = (@($rows | Where-Object { "$_" -like 'match_metadata |*' }) | Select-Object -Last 1) -replace '^match_metadata \| ([^ |]+) \|.*$', '$1'
Log 'request id' $rid
$sys = '00000000-0000-0000-0000-000000000000'
$lm = Api $z Get "/v2/storage/match_metadata?user_id=$sys&limit=50"
Log 'unrelated user Z lists match_metadata of the system user' ($lm | ConvertTo-Json -Depth 6 -Compress) 900
$lr = Api $z Get "/v2/storage/server_registrations?user_id=$sys&limit=50"
Log 'unrelated user Z lists server_registrations' ($lr | ConvertTo-Json -Depth 6 -Compress) 400
$nl = Api $p1 Get '/v2/notification?limit=50'
Log 'P1 stored notifications' (@($nl.notifications) | ForEach-Object { "code=$($_.code) subject=$($_.subject) persistent=$($_.persistent)" }) 400
Start-Sleep -Seconds 45
Rows 'db 45 s later' | Out-Null
$c1 = try { Invoke-RestMethod -Method Post -Uri "$base/v2/rpc/match_cancel?http_key=defaulthttpkey&unwrap" -ContentType 'application/json' -Body (@{ request_id = $rid; reason = 'h37 probe: no registration' } | ConvertTo-Json -Compress) } catch { "HTTP ERROR: $($_.Exception.Message) $($_.ErrorDetails.Message)" }
Log 'server-key match_cancel for the unregistered match' ($c1 | ConvertTo-Json -Compress)
Rows 'db after that cancel' | Out-Null
Log 'done' ("elapsed " + [int]((Get-Date) - $t0).TotalSeconds + " s")
