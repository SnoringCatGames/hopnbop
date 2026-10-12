# `infra/dev/` — local dev stack for compliance + smoke

Brings up a minimal Nakama + Postgres pair (no Caddy, no
observability, no signaling-proxy) with `EDGEGAP_MOCK_DEPLOY=true`
so the matchmaker hook synthesizes Edgegap deploys instead of
hitting the real API.

## Run the compliance suite locally (one command)

```pwsh
pwsh scripts/local-smoke-test.ps1
```

From the hopnbop repo root, with Docker running. It builds the
runtime plugin from the submodule into a temp directory, starts
this stack as a fresh compose project on free ports, registers
`game.yaml`, imports the project, runs the snoringcat-platform
compliance suite (`addons/snoringcat_platform_client/test/compliance/`)
in one headless Godot process with an empty `user://`, judges the
run by GUT's per-test results, and tears the stack down. About a
minute. Several runs can go at once (one per agent or worktree).

Exit 0 means every test ran and passed. A failing, pending, or
no-assert test fails the run, as does GUT running fewer tests than
the files declare. The summary names each one; full logs and a
JUnit XML land in a temp directory printed at the end.

| Flag | Effect |
|---|---|
| `-TestFile test_friends.gd` | Run one file instead of the directory. |
| `-KeepStack` | Leave the stack up; prints its URL and the exact `down -v` command. |
| `-PluginDir <dir>` / `-SkipBuild` | Build the plugin into `<dir>` (kept), or reuse the `.so` already there. |
| `-AllowPending` | Accept pending tests. |
| `-Godot <path>` | Use this Godot binary. |

Godot must match the engine in `project.godot` (4.7). The script
looks at `-Godot`, `$env:GODOT`, `godot` on PATH, then the
standard Windows install, skips any binary on another version
with a warning (a stale `GODOT` pointing at an older engine is
common), and prefers the `*_console.exe` build on Windows.

CI runs the same script: `.github/workflows/compliance-matrix.yml`.

## It never touches production

The compliance suite creates accounts, friendships, groups, and
storage rows wherever it points. Its helpers refuse to send
anything unless `PLATFORM_API_URL` is set to a loopback URL, or
`ALLOW_PROD_COMPLIANCE=1` explicitly allows another target. There
is no default URL. A refused request push_error()s and fails the
test, so a misconfigured run goes red without sending anything.

The smoke script also runs Godot with an empty `user://`, so the
game's boot path (which points `Platform` at production) has no
stored session to refresh, and passes GUT the
`test/hooks/fail_on_nakama_traffic.gd` post-run hook, which fails
the run if anything sent a Nakama SDK request anyway.

## Files

| File | Role |
|---|---|
| `docker-compose.dev.yml` | Two services: Postgres + Nakama. Mounts the runtime plugin from `HOPNBOP_DEV_PLUGIN_DIR`. No fixed container names; ports come from env vars (below). |
| `config.dev.yml` | Trimmed Nakama config (no OAuth, no signaling). Mounted into the container at `/nakama/data/config.yml`. |

## Manual usage

```pwsh
# 1. Build the runtime plugin outside the repo. The builder tag
#    must match docker-compose.dev.yml's Nakama image.
$plugin = Join-Path ([IO.Path]::GetTempPath()) "hopnbop-plugin"
New-Item -ItemType Directory -Force $plugin | Out-Null
$src = (Resolve-Path third_party/snoringcat-platform/runtime).Path -replace '\\', '/'
docker run --rm -v "${src}:/backend:ro" -v "$($plugin -replace '\\', '/'):/out" `
  -w /backend heroiclabs/nakama-pluginbuilder:3.25.0 `
  build -buildmode=plugin -trimpath -o /out/snoringcat.so .

# 2. Start the stack.
$env:HOPNBOP_DEV_PLUGIN_DIR = $plugin -replace '\\', '/'
docker compose -p hopnbop-dev -f infra/dev/docker-compose.dev.yml up -d

# 3. Wait for Nakama.
curl http://127.0.0.1:7350/healthcheck

# 4. Register hopnbop in the runtime's games table. register_game
#    also needs the stack's GAME_ADMIN_KEY; for a loopback host the
#    script falls back to defaultadminkey, or pass -AdminKey.
pwsh scripts/sync-game-config.ps1 `
  -NakamaHost http://127.0.0.1:7350 `
  -HttpKey defaulthttpkey

# 5. Run the compliance suite against it. Use the console build of
#    Godot 4.7 on Windows (the GUI build returns at once), and an
#    empty user:// so the game can't boot with your stored auth.
$env:APPDATA = Join-Path ([IO.Path]::GetTempPath()) "hopnbop-userdata"
$env:PLATFORM_API_URL = "http://127.0.0.1:7350"
$env:NAKAMA_SERVER_KEY = "defaultkey"
$env:NAKAMA_HTTP_KEY = "defaulthttpkey"
$env:GAME_ADMIN_KEY = "defaultadminkey"
& "C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe" `
  --headless -s --path . addons/gut/gut_cmdln.gd `
  -gdir=res://addons/snoringcat_platform_client/test/compliance -gexit

# 6. Tear down (the `-v` drops the Postgres volume).
docker compose -p hopnbop-dev -f infra/dev/docker-compose.dev.yml down -v
```

Ports and the plugin mount come from environment variables, so
stacks can run side by side under different `-p` project names:

| Variable | Default |
|---|---|
| `HOPNBOP_DEV_NAKAMA_PORT` | `7350` (Nakama HTTP + WebSocket) |
| `HOPNBOP_DEV_CONSOLE_PORT` | `7351` (Nakama console, `admin` / `devadmin`) |
| `HOPNBOP_DEV_POSTGRES_PORT` | `5432` |
| `HOPNBOP_DEV_PLUGIN_DIR` | the submodule's gitignored `runtime/build` |

The keys (`defaultkey`, `defaulthttpkey`) are the literal
placeholders Nakama uses when run without keys specified, and
`defaultadminkey` is the runtime's `GAME_ADMIN_KEY` from
`config.dev.yml` (`register_game` needs it on top of the HTTP
key). They're hardcoded on purpose: the dev stack never listens
outside `127.0.0.1`, so the lack of secrecy is fine.

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

Compliance tests (and the smoke script) use `127.0.0.1`
explicitly rather than `localhost`. On Windows + Docker Desktop,
`localhost` can resolve to `::1` first, and the container's port
is only bound on IPv4 (per the compose `127.0.0.1:...` mappings).
Godot's HTTPRequest then spends ~60 s burning timeouts on the
unreachable IPv6 host before retrying IPv4.

## History: the realtime tests that never ran

Until 2026-10-11 this file said the realtime-socket compliance
tests pended because of a Godot `WebSocketPeer` limitation. That
was wrong. Godot connected fine (the SDK logged `Connected!`).
The compliance helper's callbacks assigned to locals captured by
lambdas, and GDScript captures locals by value, so the helper
never saw the connection and reported every connect as a failure.
Ten realtime tests pended and two failed without exercising
anything, and the matchmaking assertions on lambda-set flags could
never observe a change. With the helpers fixed, those tests turned
up real problems:
Nakama 3.25 rejects the one-player matchmaker tickets three tests
relied on, and `cancel_account_deletion` left `[deleted]` on
accounts that had no display name.
