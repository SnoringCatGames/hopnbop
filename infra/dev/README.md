# `infra/dev/` — local dev stack for compliance + smoke

Brings up a minimal Nakama + Postgres pair (no Caddy, no
observability, no signaling-proxy) with `EDGEGAP_MOCK_DEPLOY=true`
so the matchmaker hook synthesizes Edgegap deploys instead of
hitting the real API.

The intended consumer is `scripts/local-smoke-test.ps1`, but the
files here also work hand-driven.

## Files

| File | Role |
|---|---|
| `docker-compose.dev.yml` | Two services: Postgres + Nakama. Mounts the locally-built runtime plugin from `third_party/snoringcat-platform/runtime/build/snoringcat.so` (built by the smoke script if absent). |
| `config.dev.yml` | Trimmed Nakama config (no OAuth, no signaling). Mounted into the container at `/nakama/data/config.yml`. |

## Manual usage

```pwsh
# 1. Build the runtime plugin (one time per code change).
cd third_party/snoringcat-platform/runtime
docker run --rm -v "$(pwd):/backend" -w /backend `
  heroiclabs/nakama-pluginbuilder:3.25.0 `
  build -buildmode=plugin -trimpath -o ./build/snoringcat.so .
cd ../../..

# 2. Start the stack.
docker compose -f infra/dev/docker-compose.dev.yml up -d

# 3. Wait for Nakama healthcheck.
curl http://127.0.0.1:7350/healthcheck

# 4. Register hopnbop in the runtime's games table.
pwsh scripts/sync-game-config.ps1 `
  -NakamaHost http://127.0.0.1:7350 `
  -HttpKey defaulthttpkey

# 5. Run the compliance suite against localhost.
$env:PLATFORM_API_URL = "http://127.0.0.1:7350"
$env:NAKAMA_SERVER_KEY = "defaultkey"
$env:NAKAMA_HTTP_KEY = "defaulthttpkey"
$env:EDGEGAP_MOCK_DEPLOY = "true"
godot --headless --path . -s addons/gut/gut_cmdln.gd `
  -gdir=res://addons/snoringcat_platform_client/test/compliance `
  -gexit

# 6. Tear down (the `-v` drops the Postgres volume).
docker compose -f infra/dev/docker-compose.dev.yml down -v
```

The defaults in step 4-5 (`defaultkey`, `defaulthttpkey`) are
the literal placeholders Nakama uses when run without keys
specified. They're hardcoded here on purpose — the dev stack
never listens outside `127.0.0.1`, so the lack of secrecy is
fine.

## What this is NOT

- **Not a prod replica.** Caddy / TLS / OAuth / observability /
  cost-monitor / pg-backup are all absent. Tests that care about
  those (Caddy rate-limit, Grafana provisioning, etc.) still need
  the real prod target.
- **Not a multi-game host.** It's seeded with hopnbop's
  `game.yaml` only. A second game would need its own
  `register_game` POST.
- **Not stateful across runs.** `docker compose down -v` is the
  expected teardown; the smoke script does this automatically.
  If you `docker compose down` without `-v` the Postgres data
  survives and the next migrate-up will see the prior schema.

## Use 127.0.0.1, not localhost

Compliance tests (and the smoke script) use `127.0.0.1:7350`
explicitly rather than `localhost:7350`. On Windows + Docker
Desktop, `localhost` can resolve to `::1` first, and the
container's port is only bound on IPv4 (per the compose
`127.0.0.1:7350:7350` mapping). Godot's HTTPRequest then
spends ~60 s burning timeouts on the unreachable IPv6 host
before retrying IPv4. Use 127.0.0.1 to keep test runs fast.

## Known limitations

- **Realtime-socket compliance tests pend.** Godot 4.5's
  `WebSocketPeer` connect against `ws://localhost:7350` times
  out without the SDK ever seeing a server-side close, even
  though raw .NET / curl WS connects against the same endpoint
  succeed with a valid Nakama-issued JWT. The compliance
  helpers pass `ws://localhost:7350/ws?token=...` correctly
  (verified in `--verbose` debug logs); the failure is in
  Godot's WS upgrade. Tests pend gracefully via
  `pending("socket would not connect")`, so GUT exits 0. The
  HTTP-only path of every compliance test still runs. When
  this limitation lifts (Godot WS fix or alternate client) the
  smoke script catches the full matrix automatically.

## Running the compliance suite from this repo

The compliance tests live in the snoringcat-platform submodule
at `addons/snoringcat_platform_client/test/compliance/`. When
run from `hopnbop/` the addon path resolves through
the platform-addon copy at
`addons/snoringcat_platform_client/` (created by
`scripts/setup-platform-addon.ps1`). `scripts/local-smoke-test.ps1`
re-runs setup-platform-addon before each smoke run so a stale
copy doesn't shadow a fresh submodule bump.
