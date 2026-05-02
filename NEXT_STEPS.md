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

- Latest commit on `main`: **`d90be90`** (P0+P1 work below
  is uncommitted in the working tree as of 2026-05-01).
- Nakama runtime plugin live on Hetzner:
  build_id `local-42aa284-dirty`. **Stale relative to local
  source** — needs rebuild + scp + restart to pick up
  fleet_allocator.go changes (EXPECTED_PLAYER_COUNT,
  EXPECTED_SESSION_IDS, per-player session_ids).
- Edgegap version registered: **v2** (active). The container
  image is unchanged; v2 is still valid for the new runtime
  contract because the new env vars are read at game-server
  boot and are absent-tolerant (server falls back to 2
  expected players + empty allowlist with warnings).
- Nakama `/opt/nakama/config.yml` `runtime.env` adds:
  - `EDGEGAP_APP_VERSION=v2`
  - `NAKAMA_GAME_VERSION=0.31.0`
  - `NAKAMA_PROTOCOL_VERSION=2`
- GitHub secret `NAKAMA_HTTP_KEY` is set.
- All test Edgegap deployments terminated.

---

## P0 — correctness gaps left from the unblock

All three P0 items shipped together this session (single
runtime/client/server change set). Awaiting redeploy of the
Nakama runtime + Edgegap image to verify end-to-end.

### 1. ~~Hardcoded `expected_count = 2`~~ → injected via env

`nakama-runtime/fleet_allocator.go` now adds
`EXPECTED_PLAYER_COUNT` to the Edgegap deploy `EnvVars` based
on the sum of `player_count` properties across matchmaker
entries (defaults to 1 per entry when unset).
`src/core/game_panel.gd::server_start_match` reads
`OS.get_environment("EXPECTED_PLAYER_COUNT")` and forwards to
`session_manager.server_set_expected_players`. Falls back to 2
with a warning if the env var is missing or unparseable.

### 2. ~~PreviewSessionProvider stand-in~~ → EdgegapServerProvider

New file `src/core/edgegap_server_provider.gd`. Loads the
allowlist from `EXPECTED_SESSION_IDS` env var on `_ready`,
rejects any session_id outside the list, and rejects any
already-claimed ID. Mirrors `GameLiftServerProvider`'s grace +
idle timer pattern. Wired in `_setup_session_provider`'s
edgegap branch (replaced the `PreviewSessionProvider` stand-in).

**Out of scope this round (still gated to GameLift in
`game_panel.gd`):**
- `_server_send_backend_ids_to_clients` — friend-add post-match
  is still no-op on Edgegap.
- `_server_report_match_result` — still hits the dead AWS URL
  and still gated to `GameLiftServerProvider`. Tracked under
  P2 #8 and the broader AWS-decommission pass.

### 3. ~~Client-invented session_ids~~ → authoritative IDs from runtime

`fleet_allocator.go` now generates one session_id per matched
player (`<userID>_<index>`), passes the full list to the
server via `EXPECTED_SESSION_IDS`, and ships each player their
own subset in the `match_ready` notification's
`connection.session_ids` field.
`src/core/nakama_matchmaker_client.gd` now reads
`session_ids` from the connection blob; falls back to the old
locally-derived IDs (with a warning) if the runtime omits them
so a mid-rollout deploy keeps working until every Nakama host
runs the new plugin.

**Couch co-op:** The matchmaker query still pairs per-presence
(min/max=2/4), but the runtime honors a `player_count` string
property if a future client populates it. End-to-end couch
co-op is untested.

---

## P1 — bugs flagged last session

### 4. ~~~47% packet loss in PERF stats~~ → diagnosed, fix pending

**Root cause:** `PerfTracker._update_packet_loss` in
`addons/rollback_netcode/utils/perf_tracker.gd:815` treats
every gap > 1 in `state_frame_index` as packet loss. But the
server intentionally throttles state sends per
`Netcode.frame_driver.state_send_interval`:

- ENet: `enet_state_send_fps=30` vs `target_network_fps=60`
  → `state_send_interval=2` → every event has gap=2 → metric
  reports `(2-1)/2 = 50%` "loss" with zero real UDP loss.
- WebRTC/WebSocket: `*_state_send_fps=20` → interval=3 →
  reported ~67%.

The 47% observation matches the ENet expectation almost
exactly (slight noise from frame jitter).

**Fix (deferred — submodule change):** subtract the expected
gap (`state_send_interval`) from the actual gap before
counting as loss in `_update_packet_loss`:

```gdscript
var send_interval := Netcode.frame_driver.state_send_interval
var lost: int = maxi(0, gap - send_interval)
_frames_expected_in_window += send_interval
_frames_received_in_window += send_interval - lost
```

Pending submodule PR in `godot-rollback-netcode`.

### 5. ~~Notification poller limit=0~~ → fixed

`src/core/friends_notification_poller.gd:103` was passing
`_last_poll_timestamp` (a leftover from the AWS-era API that
took `since_timestamp`) into the `limit` slot of
`fetch_notifications(limit, cacheable_cursor)`. Default value
0 tripped Nakama's `1 ≤ limit ≤ 100` check on every poll
cycle. Fix: drop the now-dead `_last_poll_timestamp` field and
its maintenance code; call `fetch_notifications()` with no
args (default limit=50). Cursor-based pagination is a
follow-up.

### 6. C1 preview client exits unexpectedly → diagnostics added

Logging added: `_client_transition_to_game_over` in
`game_panel.gd` and the `NOTIFICATION_WM_CLOSE_REQUEST`
branch in `main.gd::_notification` now both print a stack
trace plus a `[diag]` prefix. Next test session should reveal
whether C1's exit comes from the WM_CLOSE path (something
posting a window-close event) or the game-over transition
(something queue_free-ing the client). Strip the diagnostics
once the cause is known.

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

## Working tree (uncommitted, 2026-05-01)

P0.1 + P0.2 + P0.3 + P1.5 + P1.6 changes:
- `nakama-runtime/fleet_allocator.go` — generates per-player
  session_ids, injects EXPECTED_PLAYER_COUNT and
  EXPECTED_SESSION_IDS env vars on the Edgegap deploy, ships
  per-player session_ids in match_ready notification.
- `src/core/edgegap_server_provider.gd` (new) — validates
  incoming session_ids against env-loaded allowlist. Mirrors
  GameLiftServerProvider's grace + idle timer pattern.
- `src/core/game_session_manager.gd` — uses
  EdgegapServerProvider on Edgegap (was PreviewSessionProvider).
- `src/core/game_panel.gd` — reads EXPECTED_PLAYER_COUNT env
  (was hardcoded to 2). Adds `[diag]` log + print_stack to
  `_client_transition_to_game_over` (P1.6).
- `src/core/nakama_matchmaker_client.gd` — reads session_ids
  from the match_ready connection blob; falls back to
  locally-derived IDs with a warning if missing.
- `src/core/main.gd` — adds `[diag]` log + print_stack to
  NOTIFICATION_WM_CLOSE_REQUEST (P1.6).
- `src/core/friends_notification_poller.gd` — drops dead
  `_last_poll_timestamp` arg from fetch_notifications call
  (P1.5 limit=0 bug).

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
