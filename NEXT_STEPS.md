# Next Steps

Captured end-of-session 2026-05-02 (UTC 2026-05-02 evening).
The platform migration is functionally complete: AWS GameLift is
out, Edgegap + Nakama (Hetzner) are running production matches,
the platform-shared infra and runtime live in
`snoringcat-platform/`, and AWS resources are queued for
teardown via `phase-f-destroy.ps1`.

## Status snapshot (what works now)

| Layer | Status |
|---|---|
| Nakama runtime (build `local-pending-172017-dirty`) | ✅ |
| Edgegap server image v8 (active) | ✅ |
| Matchmaker → Edgegap allocation → match_ready → ENet handshake | ✅ |
| Per-player session_id allocation by runtime; server validates | ✅ |
| 3-4 player matches (was hardcoded =2 before today) | ✅ |
| Pre-auth `version_check` via HTTP key | ✅ |
| `match_end` RPC writes leaderboard + match_history | ✅ |
| Runtime hardening: match_end ↔ server_registrations, winner validation, score clamping, register_server idempotency, bulk_import gated behind env var | ✅ |
| Cloudflare Pages web client at v0.33.0 | ✅ |
| Pulumi stack parameterized (zone / location / serverType / image as config keys) | ✅ |
| `perf_tracker` reports realistic packet loss (state_send_interval-aware) | ✅ |

## Live state (don't lose track)

- **Latest commit on `main`:** `3eb8389` (fix Nakama RPC body shape).
- **Nakama runtime plugin:** build_id `local-pending-172017-dirty`,
  built from platform commit `ae914c6` (runtime hardening). Live
  on Hetzner.
- **Edgegap registry:** `v8` is the live tag (active deploy
  source). Older tags `v2`-`v7` should be cleaned up via dashboard
  or the Edgegap API — they're now obsolete.
- **Nakama `runtime.env`:** `EDGEGAP_APP_VERSION=v8`,
  `NAKAMA_GAME_VERSION=0.32.0`. (Game version drifted from the
  current `0.33.0` — see follow-ups.)
- **`addons/gamelift_session_manager/` + `addons/gamelift/` +
  `gamelift-deploy/` + `gamelift-gdextension/`:** all deleted.
  `class_name SessionProvider`, `PreviewSessionProvider`,
  `LocalOnlySessionProvider` moved to `src/core/`.
- **AWS Phase F:** queued. Dry-run clean. Real run blocked on
  `aws sso login --profile hopnbop` token refresh.
- **Cloudflare Pages:** redeployed at v0.33.0. Heavies (.wasm,
  .pck) on R2; rest on Pages.

## Open follow-ups

### Phase F (AWS teardown) — finish

`scripts/phase-f-destroy.ps1` errored at the first delete with
exit 255 because the `hopnbop` SSO session expired. Re-auth
and re-run:

```powershell
aws sso login --profile hopnbop
.\scripts\phase-f-destroy.ps1 -Confirm
```

Targets (from the dry-run): matchmaker, queue, 2 rulesets,
container group def, ECR repo, 5 Secrets Manager entries
(forced delete), CloudFront distribution, S3 website bucket.
**Skips Route 53 zone** (no `-IncludeRoute53Zone` flag) — that
zone exists but Cloudflare is authoritative for hopnbop.net,
so it's harmless to leave for now.

The script also creates a CloudWatch billing alarm at the end —
useful tripwire if any AWS resource creeps back in.

### Bump `NAKAMA_GAME_VERSION` to 0.33.0

Currently `0.32.0` in Nakama config; client is at `0.33.0` after
today's gamelift-removal version bump. Mismatch is informational
only (compat check uses `protocol_version`, which both sides
have at `2`), but worth keeping in sync.

```bash
ssh root@5.78.137.83 \
  "sed -i 's/NAKAMA_GAME_VERSION=0.32.0/NAKAMA_GAME_VERSION=0.33.0/' \
   /opt/nakama/config.yml && \
   cd /opt/nakama && docker compose restart nakama"
```

### Clean up stale Edgegap image tags

Registry has `v2` through `v8`. Only `v8` is referenced. Delete
the obsolete tags via the Edgegap dashboard or:

```bash
EDGEGAP_TOKEN=...  # in /opt/nakama/.env on Hetzner
for v in v2 v3 v4 v5 v6 v7; do
  curl -X DELETE -H "Authorization: token $EDGEGAP_TOKEN" \
    "https://api.edgegap.com/v1/app/hopnbop-server/version/$v"
done
```

### Fix `runtime_status.go` static RPC list

`registered_rpcs` in the status response is hardcoded — still
lists `bulk_import` even when the env-gate skips its
registration. Cosmetic but confusing for an operator probe.
Either build the list dynamically from the initializer state
or pass a `bulkImportRegistered` flag through
`runtimeStatusConfig` like the matchmaker hook does. Triggers a
runtime rebuild when fixed.

### Cyclic-ref preventative `.get()` rewrites (NEXT_STEPS #11)

Still skipped from May 1:
`src/objects/splash/splash.gd`, `src/objects/fish/fish.gd`,
`src/ui/confirm_overlay/confirm_overlay.gd`,
`src/level/networked_level.gd`. Apply only if web build starts
emitting "Could not resolve external class member ... Cyclic
reference" parse errors again.

### Post-Phase-F CLAUDE.md cleanup

Once Phase F runs clean, the CLAUDE.md "AWS Resources" section,
the "Deployment > GameLift Server" section, and the entire
"GameLift Architecture Notes" section are all describing
demolished infra. Replace with a brief "Production deployment"
section that points at:

- `gh workflow run game-server.yml -f version=vN` for image
  builds,
- `nakama-runtime.yml` workflow (or its successor in the
  platform repo) for runtime rolls,
- `scripts/deploy-cf-pages.ps1` for web client.

### Documentation: update PLATFORM_ARCHITECTURE.md

Several sections in the snoringcat-platform repo still describe
the planned/transitional state ("post-migration target",
"snoringcat-platform/backend/runtime/*.go" — runtime is at
`snoringcat-platform/runtime/` now). Worth a sweep once the
above docs cleanup happens in hopnbop.

### Move `phase-f-destroy.ps1` out (eventually)

After Phase F runs and stays clean for a while, this script
becomes dead weight in `hopnbop_private/scripts/`. Either delete
or move to a generic `scripts/decommission/aws/` directory in
case another game ever needs to do the same migration.

---

## Already shipped this session (2026-05-02)

Many commits across three repos. Highlights, in roughly the
order they landed:

**hopnbop_private:**
- `68ef668` edgegap: real session validation, env-driven
  expected count (P0 trio: EXPECTED_PLAYER_COUNT,
  EdgegapServerProvider, runtime-issued session_ids; P1.5
  notification poller fix; P1.6 silent-exit diagnostics).
- `59396d2` game_panel: defer match-end cleanup to next idle
  tick (silent C1/C2 exit bug, root cause was multiplayer-
  peer teardown from inside the peer-disconnected callback).
- `55e02dc` Move platform-shared infra to snoringcat-platform
  submodule (cost-monitor, runtime, Pulumi, remote configs,
  scripts).
- `0611b42` deps: bump rollback_netcode (perf-loss fix) +
  platform (pulumi parameterization).
- `4aecd49` cleanup: route version_check + match_end through
  Nakama, drop gamelift from Edgegap export.
- `cf0942c` fix: restore gamelift addon binaries on Edgegap
  container; debug check_version transport (the
  `extension_list.cfg` regression).
- `4163c2a` fix: revert Linux Server export-filter — gamelift
  addon hosts SessionProvider base class (the
  parse-time-undefined-class bug).
- `0b9b059` gamelift: remove the addon, the build env, the
  deploy scripts, the tests (~28k-line deletion).
- `3eb8389` fix: Nakama RPC body shape — bare JSON, not
  JSON-encoded string (the silent-pass version_check bug).

**snoringcat-platform (submodule):**
- `0731de1` Migrate platform-shared infra in from
  hopnbop_private.
- `790b75b` pulumi: extract zone/location/server-type into
  stack config.
- `4b8b2f7` cost-monitor: track CF Pages builds, simplify
  daily summary (parallel work stream).
- `ae914c6` runtime: harden write RPCs against forged calls
  from client builds (match_end ↔ registrations dedup,
  winner validation, stat clamping, register_server
  idempotency, bulk_import env gate).

**rollback_netcode (submodule):**
- `6065de3` perf_tracker: compensate for state_send_interval
  in loss metric.

Live state changes (not in git): GitHub repo secrets
`NAKAMA_HOST` + `NAKAMA_SSH_KEY` populated; Edgegap registry
`v1` deleted, `v2` through `v8` still present (`v8` live);
Nakama runtime plugin scp'd + restarted multiple times during
the day; Hetzner runtime config bumped through `v3 → v4 → v5
→ v6 → v7 → v8`.

---

## Useful diagnostic commands (preserve)

Decrypt Nakama SSH key (one-shot, cleans up at end):

```powershell
$keyDir = "$env:TEMP\nakama-deploy"
New-Item -ItemType Directory $keyDir -Force | Out-Null
age -d -i $HOME\.config\age\key.txt -o $keyDir\id_ed25519 `
    $HOME\Repositories\claude-config\secrets\hopnbop-migration-nakama-ssh.age
icacls $keyDir\id_ed25519 /inheritance:r /grant:r "${env:USERNAME}:(R)" | Out-Null
# ... use it ...
icacls $keyDir\id_ed25519 /grant "${env:USERNAME}:(F)" | Out-Null
Remove-Item -Recurse -Force $keyDir
```

Probe Nakama runtime status:

```powershell
$line = & ssh -i $keyDir\id_ed25519 root@5.78.137.83 "grep '^NAKAMA_HTTP_KEY=' /opt/nakama/.env"
$HTTP_KEY = $line.Split('=', 2)[1]
curl.exe -sS -X POST "https://nakama.snoringcat.games/v2/rpc/runtime_status?http_key=$HTTP_KEY&unwrap=true" `
  -H "Content-Type: application/json" -d '""' | python -m json.tool
```

Verify runtime hardening (match_end with fake request_id should
return HTTP 404 "unknown request_id"):

```bash
HTTP_KEY=...
curl -sS -X POST \
  "https://nakama.snoringcat.games/v2/rpc/match_end?http_key=$HTTP_KEY&unwrap=true" \
  -H "Content-Type: application/json" \
  -d '{"request_id":"fake","winner_id":"x","players":[{"user_id":"x","score":1,"kills":0,"bumps":0}]}'
```

Check Edgegap deployment status (`REQ_ID` from `match_ready`):

```powershell
$EDGEGAP_TOKEN = ...  # /opt/nakama/.env on Hetzner
curl.exe -sS -H "Authorization: token $EDGEGAP_TOKEN" `
  "https://api.edgegap.com/v1/status/REQ_ID" | python -m json.tool
```

Trigger game-server build + watch:

```powershell
gh workflow run game-server.yml -f version=v9
gh run watch (gh run list --workflow=game-server.yml --limit 1 --json databaseId -q '.[0].databaseId')
```

Rebuild Nakama runtime plugin and deploy:

```bash
cd third_party/snoringcat-platform/runtime
BUILD_ID="local-$(git rev-parse --short HEAD)-dirty"
BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LDFLAGS="-X main.BuildID=${BUILD_ID} -X main.BuildTime=${BUILD_TIME}"
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd):/backend" -w /backend \
  heroiclabs/nakama-pluginbuilder:3.25.0 build -buildmode=plugin -trimpath \
  -ldflags "${LDFLAGS}" -o ./build/snoringcat.so .
# then scp + restart via the SSH key flow above
```
