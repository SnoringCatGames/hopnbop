# Next Steps

Captured end-of-session 2026-05-01 (UTC 2026-05-02). Phase D
matchmaking is fully working end-to-end against production
Nakama + Edgegap. This file tracks the cleanup, polish, and
new-bug items left over.

## Status snapshot (what works now)

| Layer | Status |
|---|---|
| Client matchmaker (`NakamaMatchmakerClient`) | ✅ |
| Per-preview-instance Nakama identity | ✅ |
| `record_client_ip` RPC | ✅ |
| Nakama matchmaker pairs | ✅ |
| Runtime `MatchmakerMatched` hook fires | ✅ |
| Edgegap allocate + image pull | ✅ |
| Edgegap deployment `READY` | ✅ |
| `match_ready` notification reaches both clients | ✅ |
| Clients receive session IDs and start ENet | ✅ |
| Server inside container boots and binds 4433 | ✅ |
| ENet handshake | ✅ |
| Player declarations validated | ✅ |
| Match starts (countdown, level loads) | ✅ |
| Gameplay events (kills, bumps) | ✅ |
| Match end → GAME_OVER screen | ✅ |
| 5 new client-session Nakama RPCs registered | ✅ |

---

## Live state (don't lose track)

- Latest commit on `main`: **`d90be90`**
- Nakama runtime plugin live on Hetzner:
  build_id `local-42aa284-dirty` (one commit behind main; the
  latest commit is a client-only fix that doesn't need the
  runtime to redeploy).
- Edgegap version registered: **v2** (active). v1 still exists
  but is the broken pre-fix image; can be deleted from the
  dashboard.
- Nakama `/opt/nakama/config.yml` `runtime.env` adds:
  - `EDGEGAP_APP_VERSION=v2`
  - `NAKAMA_GAME_VERSION=0.31.0`
  - `NAKAMA_PROTOCOL_VERSION=2`
- GitHub secret `NAKAMA_HTTP_KEY` is set.
- All test Edgegap deployments terminated.

---

## P0 — correctness gaps left from the unblock

### 1. Hardcoded `expected_count = 2` breaks 3-4 player matches

`src/core/game_panel.gd` `server_start_match()` (~line 1170)
sets `session_manager.server_set_expected_players(2)` whenever
`PLATFORM=edgegap`. The matchmaker is `min=2/max=4`, so when 3
or 4 players are paired, `all_players_connected` fires
prematurely (after 2 connect) and the match starts before
everyone is in.

**Fix:** have the Nakama runtime inject the matched player
count via env at allocation time. In
`nakama-runtime/fleet_allocator.go` `OnMatchmakerMatched`, add
`{Key: "EXPECTED_PLAYER_COUNT", Value:
fmt.Sprintf("%d", len(entries))}` to `EnvVars` on the deploy
request. Server reads `OS.get_environment("EXPECTED_PLAYER_COUNT")`
on boot and forwards to `session_manager.server_set_expected_players`.

### 2. `PreviewSessionProvider` has no real session_id validation

`src/core/game_session_manager.gd` `_setup_session_provider()`
detects `PLATFORM=edgegap` and instantiates
`PreviewSessionProvider` as a stand-in. It auto-accepts any
session_id, so currently the only thing stopping a malicious
client from joining any active match is the obscurity of the
Edgegap deployment URL.

**Fix:** write `addons/snoringcat_platform_client/server/edgegap_server_provider.gd`
(or `src/core/edgegap_server_provider.gd`) that:
- On `_ready`, register the server with Nakama and pull the
  authoritative session_id list for the just-started match.
- In `server_validate_player_sessions`, only accept session_ids
  that match what Nakama allocated.
- Wire it up in `_setup_session_provider`'s edgegap branch.

The Nakama `register_server` RPC already exists; extend it
(or add a new `claim_session` RPC) so the server can pull the
matchmaker entry list back.

### 3. `client_session_ids` are derived locally, not authoritative

`src/core/nakama_matchmaker_client.gd` ~line 356 generates
`base_id_0`, `base_id_1`, ... per local player. The Nakama
runtime doesn't actually issue these — they're placeholder
strings the client invents to satisfy the
`session_ids.size() == local_player_count` check. Pairs with
#2: once the server validates session_ids, the runtime needs
to also issue them and ship them in `match_ready`'s
`connection` blob.

---

## P1 — new bugs flagged in this session

### 4. ~47% packet loss in PERF stats during gameplay

Test logs showed
`PERF: ... LOSS:47% N:397.4 PING:30.2ms` for a Seattle-to-Seattle
UDP path. Loss should be near-zero. Could be:
- Genuine packet loss (Edgegap container network tuning,
  outbound rate limit, MTU mismatch).
- Perf tracker misreading (counts late frames as loss?).

**Investigate:** tcpdump on both the Edgegap container and
client, compare sent vs received packet counts. Also check
`Netcode.perf_tracker._current_packet_loss_percent`'s
computation.

### 5. Client polls notifications with `limit=0`, Nakama 400s

Pre-existing client bug. Every notification poll cycle prints:
```
Request N returned response code: 400, RPC code: 3,
error: Invalid limit - limit must be between 1 and 100.
```
Find the poller (likely the friends or notification manager)
and pass a sensible limit (e.g. 100).

### 6. C1 preview client exits unexpectedly after match-over

In the working test, `--client=1` exited itself after the
`GAME_OVER` screen appeared (no `Main.close_app` log line,
just `--- Debugging process stopped ---`). C2 stayed open.

Add `print_stack()` in `_client_transition_to_game_over` and
in `Main`'s `NOTIFICATION_WM_CLOSE_REQUEST` handler to catch
what's calling them. Could also be the Godot debugger
disconnecting unrelated to the match.

---

## P2 — housekeeping

### 7. Stop shipping the gamelift addon in Edgegap images

`Dockerfile.edgegap` `COPY addons/gamelift /game/addons/gamelift`
exists to satisfy `extension_list.cfg` (Godot scans for
`.gdextension` manifests at startup). With the GameLift SDK
skip in `_setup_session_provider`, the extension just loads
its `.so` binaries pointlessly (~5MB).

Two paths:
- **(a)** Remove the addon from the project entirely once
  GameLift is fully decommissioned.
- **(b)** Add the addon to the Linux Server preset's
  `exclude_filter` and stop COPYing in Dockerfile.

(b) is the smaller change and lets the preset stay valid for
desktop/web exports.

### 8. Stale `_PLATFORM_API_URL` in `src/core/game_panel.gd`

Line ~23 still hardcodes
`https://r20b7wqop6.execute-api.us-west-2.amazonaws.com/prod/v1`
for "active session" polling. The endpoint is dead (or about
to be once AWS is decommissioned). Either rewire to Nakama or
delete the polling path entirely.

### 9. Settings field cleanup (`gamelift_*`)

`src/core/settings.gd` still has `gamelift_backend_api_url`
(line 35), `gamelift_anywhere_host_id`,
`gamelift_anywhere_process_id`,
`gamelift_matchmaking_timeout_sec`. The `crash_reporter` call
site that referenced `gamelift_backend_api_url` was retargeted
this session, so the field is unused. Drop during the broader
AWS-decommission pass.

### 10. Route `version_check` through Nakama HTTP key

`backend_api_client.gd:check_version()` only fires after a
client session exists. The original AWS endpoint was
unauthenticated so version-check could happen before login.
Now that the runtime has HTTP-key support and a registered
`version_check` RPC, route the app-startup version check
through the HTTP key path so it doesn't need a session.

### 11. Skipped cyclic-ref preventative fixes

The pre-Phase-D punch list called out
`src/objects/splash/splash.gd`, `src/objects/fish/fish.gd`,
`src/ui/confirm_overlay/confirm_overlay.gd`,
`src/level/networked_level.gd:2` for the `.get()` rewrite.
They weren't actually triggering parse errors after our fixes
(no direct `G.settings.*` access) so they were skipped. Keep
an eye out: if web-build cyclic-ref errors reappear in CI,
these are the next files to patch.

### 12. Set up CI for Nakama runtime deployment

`release.yml`'s `nakama-runtime` job wants
`NAKAMA_SSH_KEY` / `NAKAMA_HOST` repo secrets, which are not
set. So the runtime deploy flow is currently manual:
- Build `.so` locally via `heroiclabs/nakama-pluginbuilder`
  Docker.
- `scp` to `/opt/nakama/modules/snoringcat.so`.
- `ssh root@5.78.137.83 'cd /opt/nakama && docker compose
  restart nakama'`.

Once the secrets are populated, the release pipeline runs
this automatically on tag push.

### 13. Stale `v1` Edgegap image

`v1` tag in the Edgegap registry still points to the broken
pre-fix image. Either re-tag v2 as v1 (and revert the Nakama
config.yml `EDGEGAP_APP_VERSION` back to v1) or just delete
v1 from the Edgegap dashboard and stay on v2 indefinitely.

---

## Already shipped this session

Commits on `main`, in order:
- `999432a` phase-d unblock: Dockerfile.edgegap, entrypoint,
  cyclic-ref `.get()` fixes on 4 GD scripts, CI workflow_call
  + NAKAMA_HTTP_KEY env, snoringcat_platform_client bridge,
  release.yml refactor, SUBMODULE_PAT in 3 workflows, 5 new
  Nakama runtime RPCs (`version_check`,
  `update_and_get_presence`, `get_player_stats`,
  `get_match_history`, `export_player_data`), match_history
  write in match_end, `requireClientSession` helper.
- `0b648b3` CLAUDE.md: drop the wait-for-explicit-commit-permission
  rule.
- `42aa284` ci(game-server): install Godot export templates so
  `--export-release` works.
- `3ca8465` nakama-runtime: `rich_presence` is a string, not
  a dict.
- `eca5925` edgegap: skip GameLift SDK on Edgegap servers
  (`PLATFORM=edgegap` env detection, instantiate
  `PreviewSessionProvider`, hardcode `expected_count=2`).
- `d90be90` nakama_matchmaker: emit one session_id per local
  player.

Backend state changes (not in git):
- Nakama runtime plugin rebuilt and `scp`'d to Hetzner;
  build_id `local-42aa284-dirty`.
- Nakama `/opt/nakama/config.yml` `runtime.env` updated.
- Edgegap registry: v1 (broken) and v2 (working) image tags.
- Edgegap version v1 and v2 records both registered.
- GitHub secret `NAKAMA_HTTP_KEY` set.
- All test deployments terminated.

---

## Useful diagnostic commands (preserve)

Decrypt Nakama SSH key (one-shot, cleans up at end):
```powershell
$keyDir = "$env:TEMP\nakama-deploy"
New-Item -ItemType Directory $keyDir -Force | Out-Null
age -d -i $HOME\.config\age\key.txt `
    $HOME\Repositories\claude-config\secrets\hopnbop-migration-nakama-ssh.age `
    | Out-File -FilePath $keyDir\id_ed25519 -Encoding ASCII -NoNewline
icacls $keyDir\id_ed25519 /inheritance:r /grant:r "${env:USERNAME}:(R)" | Out-Null
# ... use it ...
Remove-Item -Recurse -Force $keyDir
```

Probe Nakama runtime status:
```powershell
# (after decrypting the SSH key as above into $keyDir)
$line = & ssh -i $keyDir\id_ed25519 root@5.78.137.83 "grep '^NAKAMA_HTTP_KEY=' /opt/nakama/.env"
$HTTP_KEY = $line.Split('=', 2)[1]
curl.exe -sS -X POST "https://nakama.snoringcat.games/v2/rpc/runtime_status?http_key=$HTTP_KEY&unwrap=true" `
  -H "Content-Type: application/json" -d '""' | python -m json.tool
```

Check Edgegap deployment status (`REQ_ID` from `match_ready`):
```powershell
# EDGEGAP_TOKEN lives in /opt/nakama/config.yml runtime.env on Hetzner.
$EDGEGAP_TOKEN = ...
curl.exe -sS -H "Authorization: token $EDGEGAP_TOKEN" `
  "https://api.edgegap.com/v1/status/REQ_ID" | python -m json.tool
```

Trigger game-server build + watch:
```powershell
gh workflow run game-server.yml -f version=v2
gh run watch (gh run list --workflow=game-server.yml --limit 1 --json databaseId -q '.[0].databaseId')
```

Rebuild Nakama runtime plugin and deploy:
```bash
cd nakama-runtime
BUILD_ID="local-$(git rev-parse --short HEAD)-dirty"
BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LDFLAGS="-X main.BuildID=${BUILD_ID} -X main.BuildTime=${BUILD_TIME}"
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd):/backend" -w /backend \
  heroiclabs/nakama-pluginbuilder:3.25.0 build -buildmode=plugin -trimpath \
  -ldflags "${LDFLAGS}" -o ./build/snoringcat.so .
# then scp + restart via the SSH key flow above
```
