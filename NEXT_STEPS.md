# Next Steps

Short-horizon session log. The platform migration is complete
(Phase F finished 2026-05-03; AWS account empty), and the multi-
game refactor shipped over 2026-05-12 → 2026-05-14
(`MULTI_GAME_ROADMAP.md` for the detail). This file captures
items that fall outside the roadmap: operator-side cleanup,
follow-up polish, and useful diagnostic recipes.

For project history (what shipped when), prefer `git log`. For
deep architecture, see `third_party/snoringcat-platform/PLATFORM_ARCHITECTURE.md`.

## Currently open

### Compliance suite rate-limit

Running all 44 tests under
`addons/snoringcat_platform_client/test/compliance/` back-to-
back hits Nakama's auth rate-limit (HTTP 429 on ~17 of the 44).
Tests pass individually + in small batches, so the suite isn't
fundamentally broken, but it can't run as a single CI gate
until pacing or backoff is added. The Stage 8.31
`compliance-matrix.yml` workflow uses the ephemeral docker-
compose stack which has its own rate limiter, so it's
unaffected; the rate limit hits when running against prod /
shared tiers. Options:

- Per-test pacing in `compliance_helper.gd` (sleep ~250 ms
  between auth POSTs).
- Per-batch retry with exponential backoff on 429.
- Split the suite into rate-friendly tiers and run each as a
  separate CI job.

### Cert hygiene (optional)

Cert A from cert-rotate run `25301578756` was briefly stored
as `is_secret: false` for ~3 minutes before being superseded
by cert C. Theoretical leak window for anyone with
`EDGEGAP_TOKEN`. The cert is no longer in use; revoke at
Let's Encrypt for hygiene if paranoid.

### Godot 4.5 WebSocketPeer localhost quirk (low priority)

Realtime-socket compliance tests pend on the dev stack
(`infra/dev/docker-compose.dev.yml`) because Godot 4.5's
`WebSocketPeer` against `ws://127.0.0.1` times out without
seeing a server-side close — even though raw .NET / curl WS
clients with the same Nakama-issued JWT connect fine. Tests
pend gracefully via `pending(...)`. Fixing it would unlock
the full Tier 4 socket matrix. Investigation is unbounded
(could be a Godot WS-stack bug).

### Remote-player-state glitches (verify-or-archive)

`REMOTE_PLAYER_STATE_GLITCHES_session_context.md` (2026-03-28)
captures an investigation into a remote-player visual-state
bug. Unverified whether it still reproduces — multi-client
test session needed to confirm before either re-investigating
or moving the doc to `docs/archive/`.

Sibling doc `VIEWPORT_CENTERING_SESSION_NOTES.md` was
archived 2026-05-15 (centering was painstakingly fixed
through a different approach than the doc proposed; the doc
was misleading on the current state of the level cameras).

## Pointers

- Multi-game roadmap: `MULTI_GAME_ROADMAP.md`.
- Platform architecture: `third_party/snoringcat-platform/PLATFORM_ARCHITECTURE.md`.
- Studio architecture: `third_party/snoringcat-platform/STUDIO_ARCHITECTURE.md`.
- Compliance suite (canonical): `third_party/snoringcat-platform/addons/snoringcat_platform_client/test/compliance/`.
  The `addons/snoringcat_platform_client/` copy in this repo
  is refreshed by `scripts/setup-platform-addon.ps1` after
  every submodule bump.
- Test architecture plan: `docs/test-architecture-plan.md`.
- Migration archeology: `docs/archive/MIGRATION_PLAN.md`
  and `docs/archive/platform-pivot-discussion.md`.

## Useful diagnostic commands

### Decrypt Nakama SSH key (one-shot, cleans up at end)

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

### Probe Nakama runtime status

```powershell
$line = & ssh -i $keyDir\id_ed25519 root@5.78.137.83 "grep '^NAKAMA_HTTP_KEY=' /opt/nakama/.env"
$HTTP_KEY = $line.Split('=', 2)[1]
curl.exe -sS -X POST "https://nakama.snoringcat.games/v2/rpc/runtime_status?http_key=$HTTP_KEY&unwrap=true" `
  -H "Content-Type: application/json" -d '""' | python -m json.tool
```

### Verify runtime hardening (fake match_end should 404)

```bash
HTTP_KEY=...
curl -sS -X POST \
  "https://nakama.snoringcat.games/v2/rpc/match_end?http_key=$HTTP_KEY&unwrap=true" \
  -H "Content-Type: application/json" \
  -d '{"request_id":"fake","winner_id":"x","players":[{"user_id":"x","score":1,"kills":0,"bumps":0}]}'
```

### Check Edgegap deployment status

```powershell
$EDGEGAP_TOKEN = ...  # /opt/nakama/.env on Hetzner
curl.exe -sS -H "Authorization: token $EDGEGAP_TOKEN" `
  "https://api.edgegap.com/v1/status/REQ_ID" | python -m json.tool
```

### Trigger workflows

```powershell
# game-server build → Edgegap registry push:
gh workflow run game-server.yml -f version=v28
gh run watch (gh run list --workflow=game-server.yml --limit 1 --json databaseId -q '.[0].databaseId')

# Nakama runtime plugin build + scp + restart:
gh workflow run nakama-runtime.yml

# Cert rotation (auto-runs weekly; force a renew):
gh workflow run cert-rotate.yml -f force_renew=true

# Web client deploy (local):
pwsh scripts/deploy-cf-pages.ps1
```

### Rebuild Nakama runtime plugin locally

```bash
cd third_party/snoringcat-platform/runtime
BUILD_ID="local-$(git rev-parse --short HEAD)-dirty"
BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LDFLAGS="-X main.BuildID=${BUILD_ID} -X main.BuildTime=${BUILD_TIME}"
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd):/backend" -w /backend \
  heroiclabs/nakama-pluginbuilder:3.25.0 build -buildmode=plugin -trimpath \
  -ldflags "${LDFLAGS}" -o ./build/snoringcat.so .
# then scp + restart via the SSH-key flow above.
```

### List + prune stale Edgegap image tags

```bash
EDGEGAP_TOKEN=$(ssh -i $HOME/.hopnbop-migration/ssh/nakama \
  root@5.78.137.83 \
  "grep 'EDGEGAP_TOKEN' /opt/nakama/config.yml | head -1 | \
   sed 's/.*EDGEGAP_TOKEN=//; s/\"$//'")

# list:
curl -fsS -H "Authorization: Token $EDGEGAP_TOKEN" \
  "https://api.edgegap.com/v1/app/hopnbop-server/versions?limit=100" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);[print(v['name']) for v in d.get('versions', [])]"

# delete one by name:
curl -X DELETE -H "Authorization: Token $EDGEGAP_TOKEN" \
  "https://api.edgegap.com/v1/app/hopnbop-server/version/v<N>"
```

### Pull container logs from a live deploy

```powershell
pwsh scripts/edgegap-logs.ps1 -Latest
# or for a specific request_id:
pwsh scripts/edgegap-logs.ps1 -RequestId <id>
```
