# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hop 'n Bop is a multiplayer action game built with Godot 4.5. It implements client-side prediction with rollback reconciliation for networked gameplay.

## Platform infrastructure (read on demand)

Backend, auth, matchmaking, game-server allocation, and per-game
config are handled by the shared Snoring Cat platform.
**When working on any of these topics, read
`third_party/snoringcat-platform/PLATFORM_ARCHITECTURE.md`** for
the architecture reference. It covers Nakama runtime, Edgegap
allocation, identity/account-linking/deletion, per-game config
schema, per-game protocol versioning (bump procedure), ops
runbook, and where things live.

The migration from AWS GameLift to Nakama+Hetzner+Edgegap is
in progress; see `MIGRATION_PLAN.md` for phase status. Until
migration completes, the **AWS GameLift architecture** described
later in this file is still authoritative for current production.

**Per-game protocol versioning** (post-migration): each game has
its own `protocol_version` integer in `game.yaml` and
`project.godot`. Bump only the affected game's version when
shipping a breaking network protocol change; do not bump other
games' versions. Full procedure and "what counts as breaking"
rules are in `PLATFORM_ARCHITECTURE.md`.

### Cost monitor (daily Discord MTD summary)

The Discord channel that receives this repo's morning-brief and
ci-failure pings also gets a **daily MTD spend summary** plus
threshold-crossing alerts. The source is in the snoringcat-platform
repo, deployed to the Hetzner host by Pulumi:

- Source files:
  `third_party/snoringcat-platform/infra/remote/cost-monitor/`
  (`cost-monitor.{sh, service, timer}`).
- Deployed path: `/opt/snoringcat/cost-monitor/` on the Nakama box.
- Trigger details, thresholds, emergency action, and inspection
  commands: see `PLATFORM_ARCHITECTURE.md` → "Cost monitor".

## Cloning

This repo uses git submodules for the rollback netcode and
GameLift session manager addons (extracted Phase 3 of the
platform refactor). After cloning, run:

```bash
git submodule update --init --recursive
```

Submoduled addons:
- `addons/rollback_netcode/` →
  [godot-rollback-netcode](https://github.com/SnoringCatGames/godot-rollback-netcode)
- `addons/gamelift_session_manager/` →
  [godot-gamelift-session-manager](https://github.com/SnoringCatGames/godot-gamelift-session-manager)
- `gamelift-gdextension/vcpkg/` → upstream Microsoft vcpkg.

To bump an addon to a newer version, `cd` into the submodule,
`git fetch && git checkout vX.Y.Z`, then commit the new SHA in
this repo.

## Claude Code Settings

Do NOT use the local memory system (`~/.claude/projects/*/memory/`).
This project is worked on across multiple machines. All persistent
context belongs in this file so it stays in sync via git.

## Running the Game

Test multiplayer locally in Godot editor:
1. Debug > Customize Run Instances
2. Enable 3 instances with launch args:
   - Instance 1: `--server`
   - Instance 2: `--client=1`
   - Instance 3: `--client=2`

Launch flags:
- `--server` - Run as server
- `--client=N` - Run as client N (1, 2, etc.)

## Deployment

### Deploy Order

1. **Backend (SAM)** first. API changes must be live
   before clients or servers reference them.
2. **GameLift server** second. Server code may depend
   on new backend endpoints.
3. **Website (web client)** last. Client needs both
   backend and server to be ready.

### Backend (SAM)

**Script:** `scripts/deploy-backend.ps1`

Syncs `GAME_VERSION` and `PROTOCOL_VERSION` in `template.yaml`
from `project.godot`, runs `sam build --use-container`, runs
`sam deploy --no-confirm-changeset`.

```powershell
.\scripts\deploy-backend.ps1
```

**Common issues:**
- `sam deploy` hangs without `--no-confirm-changeset` (waits
  for interactive confirmation).
- Never pass `--template-file template.yaml` to `sam deploy`.
  That bypasses the build output and deploys raw source without
  pip dependencies (73KB instead of ~17MB), causing
  `No module named 'aws_lambda_powertools'` Lambda init errors.
- Build container pulls `public.ecr.aws/sam/build-python3.12`.
  Docker Desktop must be running.
- Delete `backend/.aws-sam/` (not the repo root) if build
  cache is stale (causes "Unresolved resource dependencies"
  error).
- **"No changes to deploy" when code changed:** SAM uses
  content-addressed S3 keys. If the zip hash matches what
  is already in S3, CloudFormation sees no diff. This can
  happen when a previous `--force-upload` already pushed
  the new code, or due to Docker mount caching on Windows.
  Fix: use `aws lambda update-function-code` to force
  Lambda to reload from S3:
  ```bash
  aws lambda update-function-code \
    --function-name <full-function-name-with-suffix> \
    --s3-bucket <sam-managed-bucket> \
    --s3-key hopnbop-backend/<hash> \
    --profile hopnbop --region us-west-2
  ```
  Get the function names with `aws lambda list-functions`
  and the S3 key from the SAM deploy output. Only update
  the functions whose code you changed.

### CLI Tool Availability

Deploy scripts (`.ps1`) must be run via PowerShell.
`sam`, `godot`, and other deploy tools are only in the
PowerShell PATH, not the bash PATH. **Never run `sam`
or `godot` directly from bash.** Always use
`powershell -ExecutionPolicy Bypass -File <script>` or
`powershell -Command "<command>"` when invoking them.

SAM deploy with 36+ Lambda functions can take 5-10
minutes with no console output during the CloudFormation
changeset phase. Do not kill it prematurely. Check
`aws cloudformation describe-stacks` for current status
before assuming it is stuck. If deploy hangs for env-var-
only changes (same code hash), retry with `--force-upload`.

### GameLift Server

**Script:** `gamelift-deploy/deploy.ps1`

Exports Godot Linux .pck, builds Docker image, pushes to ECR,
updates container group definition, triggers fleet deployment.

```powershell
.\gamelift-deploy\deploy.ps1              # full
.\gamelift-deploy\deploy.ps1 -SkipExport  # skip Godot export
```

**Common issues:**
- Godot `--export-pack` returns non-zero due to GDExtension
  DLL copy warnings (non-fatal on Windows). The deploy
  script treats this as a failure. Workaround: run the
  export manually, verify `.pck` exists, then re-run with
  `-SkipExport`:
  ```bash
  mkdir -p build/linux
  godot --headless --export-pack "Linux Server" \
    build/linux/hopnbop_server.pck
  ls -la build/linux/hopnbop_server.pck  # verify ~24MB
  .\gamelift-deploy\deploy.ps1 -SkipExport
  ```
- Container group definition limit is 4 versions. Delete old
  versions before updating:
  ```bash
  aws gamelift delete-container-group-definition \
    --name hopnbop-server-group --version-number N \
    --region us-west-2 --profile hopnbop
  ```
- Definition stays in COPYING state for ~15 seconds after
  update. Fleet update fails if definition is not yet READY.
- Fleet deployment takes 5-15 minutes after container group
  definition update.
- Always use `docker build --no-cache` to avoid BuildKit
  serving a stale .pck from layer cache.

**Monitor fleet rollout:**
```bash
aws gamelift list-fleet-deployments \
  --fleet-id containerfleet-9836594e-0c96-4887-a8d5-be7f3541db36 \
  --region us-west-2 --profile hopnbop
```

### Website (Web Client)

**Script:** `scripts/deploy-website.ps1`

Exports Godot web build, copies export files into `web/`,
syncs `web/` to S3, invalidates CloudFront cache.

```powershell
.\scripts\deploy-website.ps1              # full (includes game export)
.\scripts\deploy-website.ps1 -SkipExport  # skip export
```

**Common issues:**
- Godot `--export-release "Web"` returns non-zero due to
  missing resource warnings. The deploy script treats this
  as a failure. Workaround: export manually, copy to
  `web/`, then run with `-SkipExport`:
  ```bash
  mkdir -p build/web
  godot --headless --export-release "Web" \
    build/web/index.html
  cp build/web/* web/
  .\scripts\deploy-website.ps1 -SkipExport
  ```
- `-SkipExport` also skips the copy step. If you exported
  manually, copy `build/web/*` to `web/` before running the
  S3 sync.
- CloudFront invalidation takes 1-2 minutes to propagate.

**Website structure:**
- Root page loads the Godot web export directly (no landing
  page).
- Supporting pages: `/leaderboard/`, `/blog/`, `/privacy/`,
  `/terms/`, `/data-deletion/`.
- Discord invite link: `https://discord.gg/QX939SF7nb`.
- Update `web/blog/index.html` with patch notes when making
  new releases.

### Legal Documents

The game bundles plain-text copies of the legal docs for
offline access. When updating legal content, update **both**
locations:

1. **Web pages:** `web/terms/index.html`,
   `web/privacy/index.html`, `web/data-deletion/index.html`
2. **In-game text:** `legal/en/terms.txt`,
   `legal/en/privacy.txt`, `legal/en/data_deletion.txt`
   (and any translated variants in `legal/{locale}/`)

If the changes require users to re-consent, also bump
`LEGAL_VERSION` in `src/core/auth_token_store.gd`.

### Prerequisites (All Deploys)

- AWS SSO login: `aws sso login --profile hopnbop`
- Docker Desktop running (backend build + GameLift)
- Godot CLI on PATH (GameLift + website export)

### Version Management

**Single source of truth:** `project.godot`
- `config/version="X.Y.Z"` (display version, bump on
  redeploy)
- `config/protocol_version=N` (integer, bump only when
  client/server protocol changes)

**Synced locations:**
- `backend/template.yaml` `GAME_VERSION` and
  `PROTOCOL_VERSION` (synced automatically by
  `deploy-backend.ps1`)
- ECR image tag (set automatically by
  `gamelift-deploy/deploy.ps1`)
- `export_presets.cfg` `file_version`/`product_version`
  (optional, currently empty)

**Version bumping policy:**
- When in doubt, bump the version. Always bump on redeploy.
- Prefer bumping minor over patch. Do not ask about version
  numbers. Pick whichever sounds best and proceed.

**Commit policy:**
- Do not commit partial or broken work. All changes for a
  feature must be working end-to-end before committing.
- You don't need explicit permission to commit. Commit at
  natural stopping points — when work is end-to-end working
  and at a logical checkpoint. This overrides Claude Code's
  default "ask first" behavior for this repo.

**Version check architecture:**
- `protocol_version` determines client/server compatibility.
  Only bump when the network protocol actually changes.
- `config/version` is for display only. Hotfix deploys can
  bump this without breaking existing clients.
- Client checks `protocol_version` at app startup via
  `GET /version` (unauthenticated). Also checked in auth
  response, matchmaking response, and server RPC.

### AWS Resources

- **Account:** 270469481989
- **Region:** us-west-2
- **Profile:** hopnbop
- **Fleet ID:** containerfleet-5568a04e-2984-4e77-9e24-fce721caa7c6
  (current; `aws gamelift list-fleets` is authoritative)
- **Fleet billing type:** SPOT (recreated 2026-04-11 from
  ON_DEMAND to cut GameLift costs ~65-75%)
- **ECR repo:** 270469481989.dkr.ecr.us-west-2.amazonaws.com/hopnbop-server
- **S3 bucket:** hopnbop-website
- **CloudFront:** E3LT833LSVTW9R
- **Container group def:** hopnbop-server-group
- **Matchmaker:** hopnbop-ffa-matchmaker
- **Game session queue:** hopnbop-game-queue
- **FlexMatch ruleset:** hopnbop-ffa-ruleset
- **IAM role:** GameLiftContainerFleetRole
- **Hosted zone:** Z05562172A1JF6AX39U2N (game.hopnbop.net)
- **TLS cert secret:** hopnbop/tls-wildcard-cert (expires
  2026-06-09)
- **CloudWatch log group:**
  gamelift-containerfleet-{fleet-id}-us-west-2 (auto-generated
  per fleet; the current one is named after the fleet ID above)
- **SNS alarms topic:** hopnbop-alarms (subscriptions:
  admin@snoringcat.games)
- **Fleet state table:** hopnbop-fleet-state (single-item
  table tracking `last_activity_at` for the idle-check Lambda)

### GameLift Architecture Notes

**Multi-stage Docker build:** The Dockerfile has three stages:
1. `webrtc-builder`: Compiles a patched webrtc-native
   GDExtension from source (v1.0.9) with
   `portRangeBegin`/`portRangeEnd` and `enableIceUdpMux`
   support. Upstream v1.0.9 ignores these config keys.
   The patch script is `gamelift-deploy/patch-webrtc-portrange.py`.
2. `sdk-builder`: Compiles GameLift Server SDK v5.2.0
   from source with `GAMELIFT_USE_STD=1` and
   `BUILD_SHARED_LIBS=ON`.
3. Runtime image (Ubuntu 24.04): Copies binaries from
   both builder stages.

The webrtc-builder stage is necessary because the
upstream GDExtension silently ignores `portRangeBegin`,
`portRangeEnd`, and `enableIceUdpMux` in the
`initialize()` config dictionary. Without these, the
ICE agent binds to ephemeral UDP ports that GameLift
does not forward, and multiple PeerConnections cannot
share a port.

**SDK version pinning:** The fleet was created with SDK v5.2.0.
The Docker build must pin `--branch v5.2.0` when cloning the
SDK source. Using `main` (v5.4.0+) causes WebSocket handshake
failures.

**Ubuntu 24.04 requirement:** The GDExtension binary requires
GLIBCXX_3.4.32 which is only available in Ubuntu 24.04+.

**GDExtension files outside .pck:** The `.gdextension` manifest
and `.so` binaries must exist on the filesystem. They cannot be
inside the `.pck` file.

**GDExtension type inference:** GDExtension methods return
`Variant` to GDScript. Using `:=` causes "Cannot infer type"
errors. Always use explicit type annotations:
```gdscript
# Wrong.
var count := session.maximum_player_session_count
# Correct.
var count: int = session.maximum_player_session_count
```

**Critical:** The server MUST call
`_gamelift.activate_game_session()` in the
`_on_game_session_started` callback. Without it, FlexMatch
times out with GAME_SESSION_ACTIVATION_TIMEOUT and the
deployment goes IMPAIRED.

**SERVER_API_KEY:** Set via the container group definition's
`EnvironmentOverride`. Read in `global.gd:_ready()`, stored in
`settings.server_api_key`, used by `match_result_reporter.gd`
to authenticate with the backend API.

### Fleet Warmup and Idle Shutdown

The fleet runs on Spot pricing with DESIRED=0 as the resting
state to minimize instance-hour costs. Client-driven warmup
brings it up on demand, and a scheduled Lambda scales it back
to 0 after 30 minutes of no activity.

**Client side (`src/core/backend_api_client.gd`):**
- `warm_up_fleet(source)` posts to `/fleet/warmup` and starts
  a 10-second polling timer for `/fleet/status`.
- Fired automatically from `global.gd:_ready()` on app startup
  unless `settings.prefer_offline_mode` is true.
- Fired again when the player toggles offline mode off, via
  the `LocalSettings.setting_override_changed` signal.
- Exposes `is_fleet_ready()`, `is_fleet_warming_up()`, and
  `get_fleet_estimated_remaining_sec()` for UI.
- Polling stops when status reaches `"ready"` or after 10
  minutes to avoid runaway retries.

**Lobby UI:** `lobby_level.tscn` has a bottom-right
`FleetWarmupLabel` that shows `LOBBY.SERVER_WARMING_UP_WITH_ESTIMATE`
with a minutes-and-seconds countdown, or `LOBBY.SERVER_READY`
once the fleet is live. Hidden in offline mode.

**Loading screen:** `loading_screen.gd` checks
`is_fleet_warming_up()` before falling through to the existing
matchmaking phase label, so players see
`LOADING.WARMING_UP_SERVER` during the cold-start wait instead
of `LOADING.CONNECTING`.

**Backend side:**
- `services/fleet_service.py` — Wraps DescribeFleetLocationCapacity,
  UpdateFleetCapacity, DescribeGameSessions, and reads/writes
  `last_activity_at` in the `hopnbop-fleet-state` DynamoDB table.
- `handlers/fleet_handler.py`:
  - `POST /fleet/warmup` — Unauthenticated. Updates activity
    timestamp and scales DESIRED to 1 if currently 0.
  - `GET /fleet/status` — Unauthenticated. Reads capacity
    without mutating anything.
  - `scheduled_idle_check` — Invoked by EventBridge every 5
    minutes. Scales DESIRED to 0 if no ACTIVE game sessions
    AND `now - last_activity_at >= 30 minutes`. First run
    seeds the timestamp instead of scaling down.
- `handlers/match_handler.submit_match_result` — Calls
  `fleet_service.update_activity("match_end")` after recording
  a match, so the 30-minute idle window starts fresh whenever
  a match ends.

**Warmup latency:** Cold start from DESIRED=0 to ACTIVE with
an IDLE game session slot takes roughly 3-5 minutes (EC2 boot
+ ECR image pull + GameLift health checks + game session
activation). The estimate returned to the client starts at
300 seconds and decrements as `now - last_activity_at`.

**FleetId parameter:** `backend/template.yaml` takes a `FleetId`
SAM parameter with an empty default. `scripts/deploy-backend.ps1`
looks up the current fleet via `aws gamelift list-fleets` and
passes it as a parameter override at deploy time. If the fleet
is ever recreated, redeploying the backend picks up the new ID
automatically. When `FleetId` is empty, the fleet service
gracefully skips all GameLift API calls and returns a neutral
status so tests pass without real AWS credentials.

**Spot interruption handling:** Already implemented in
`addons/gamelift_session_manager/server/gamelift_server.gd`
via `_on_process_terminate_requested`, which listens to
GameLift's 2-minute warning and calls
`Netcode.connector.server_notify_shutdown()` so clients see a
clean SERVER_SHUTDOWN rather than a hard disconnect.

### Transport Architecture

Three transport modes, selected per-match by the backend
based on matched players' platforms:

- **ENet** (native-only matches): UDP on container port
  4433. Default. Lowest latency.
- **WebRTC** (cross-play matches with web players): UDP
  DataChannels via `webrtc-native` GDExtension. Signaling
  uses a brief WebSocket through the nginx path. Provides
  UDP-like semantics in the browser, avoiding TCP
  head-of-line blocking.
- **WebSocket** (legacy, not currently used): TCP through
  nginx. Too slow for competitive play due to TCP
  head-of-line blocking (~100ms ping, 13-25% perceived
  packet loss).

**Transport selection flow:**
1. FlexMatch includes `is_web` player attribute.
2. Backend `gamelift_service.py` reads `is_web` from
   matchmaker data. Returns `transport_type` in
   matchmaking response (`"enet"`, `"webrtc"`, or
   `"websocket"`).
3. Client sets `Netcode.settings.transport_type` from the
   response before connecting.
4. Server reads matchmaker data in
   `_on_game_session_started` and sets transport. Only
   switches away from ENet if web players are matched.

#### WebRTC Architecture

**Components:**
- `WebRTCSignalingServer` (server-side): Lightweight
  WebSocket server for SDP/ICE exchange. Listens on
  container port 4433 TCP (same as ENet/UDP, no conflict).
- `WebRTCSignalingClient` (client-side): Connects to
  signaling server, exchanges SDP offer/answer, relays
  ICE candidates. Retries up to 5 times with 10s timeout.
- `WebRTCGamePeer` (both sides): Custom
  `MultiplayerPeerExtension` using 2 negotiated
  DataChannels (reliable + unreliable) instead of
  `WebRTCMultiplayerPeer`'s 6-8 SCTP streams.

**Signaling flow:**
1. Client connects to signaling WS (through nginx).
2. Client creates `WebRTCPeerConnection`, emits
   `peer_created` → `WebRTCGamePeer.add_peer()` creates
   negotiated DataChannels.
3. Client creates SDP offer, sends via signaling WS.
   Includes `server_port` (the WSS port from the
   matchmaking response) for host port derivation.
4. Server creates `WebRTCPeerConnection` with
   `portRangeBegin/End=4433` and
   `enableIceUdpMux=true`. Emits `peer_signaled` →
   `WebRTCGamePeer.add_peer()` creates matching
   DataChannels.
5. Server sets remote description (client's offer),
   generates SDP answer, sends via signaling WS.
6. ICE candidates exchanged bidirectionally via
   signaling WS. Server rewrites srflx candidate
   port from 4433 to the GameLift host port.
7. ICE connects (UDP on host port), DataChannels
   open.
8. Signaling WS is closed.

**GDExtension:** `addons/webrtc/` provides
`webrtc-native` (v1.0.9) which implements
`WebRTCPeerConnection` using libdatachannel (with
libjuice for ICE) for native builds. Web builds use
the browser's native WebRTC API (no GDExtension
needed). The server uses a patched build (see
"Multi-stage Docker build" above).

**Physics tick rate:** WebRTC matches run at 30 FPS
(vs 60 for ENet) to reduce bandwidth. Applied via
`Netcode.apply_match_physics_fps()` before connection.

**ICE port pinning:** On GameLift, only declared
container ports are forwarded to the host. The server
pins the ICE agent to container port 4433 via
`portRangeBegin`/`portRangeEnd` in `initialize()`.
Multiple PeerConnections share this port via libjuice
mux mode (`enableIceUdpMux: true`), which
demultiplexes STUN traffic by username fragment.

**ICE candidate rewriting:** The ICE agent's
STUN-reflected (srflx) candidate advertises the
container port (4433), but clients must connect to
the GameLift host port (e.g., 4205) which is in the
`InstanceConnectionPortRange` and forwarded to the
container. The signaling server rewrites the srflx
candidate's port before sending it to the client.
The host port is derived from the client's WSS port
(which the backend returns as host_udp_port + 1).

**ICE candidate buffering:** Client ICE candidates
that arrive before the server processes the SDP offer
are buffered and flushed after the
`WebRTCPeerConnection` is created. Without this,
early candidates are silently dropped.

**Fleet inbound permissions:** Port 4433/UDP must be
in the fleet's `InstanceInboundPermissions` in
addition to the `InstanceConnectionPortRange`. The
ICE agent's outbound STUN uses port-preserving NAT
(container port 4433 appears as host port 4433 to
STUN), so return traffic and client ICE checks
arrive on host port 4433. This port must be allowed
by the security group.

### WSS TLS Termination

```
Web client --wss://s-{ip}.game.hopnbop.net:{Port+1}--> nginx (TLS detect) --> TLS terminate --> Godot WS/signaling (4433)
Native client --ws://s-{ip}.game.hopnbop.net:{Port+1}--> nginx (TLS detect) --> pass-through --> Godot WS/signaling (4433)
ENet-only match --enet://ip:{Port}/UDP--> Godot (unchanged)
```

nginx uses `ssl_preread` on container port 4434 to detect
whether the incoming connection is TLS (web `wss://`) or
plain (native `ws://`). TLS connections are routed to an
internal HTTP block (port 4435) that terminates SSL and
strips the `Origin` header before proxying to Godot.
Plain connections are passed directly to Godot. In ENet/
WebSocket mode, Godot runs a plain WebSocket server on
port 4433. In WebRTC mode, the WebRTC signaling server
listens on port 4433 TCP instead.

**Critical nginx settings for real-time game traffic:**
- `tcp_nodelay on` in the stream block (disables Nagle's
  algorithm; without this, latency jumps to 3-10 seconds)
- `proxy_buffering off` in the HTTP block
- `proxy_socket_keepalive on` in the stream block

**WebSocket buffer sizes:** Both client and server set
`inbound_buffer_size` and `outbound_buffer_size` to 1MB
(default 64KB) and `max_queued_packets` to 16384 (default
2048). The default buffer overflows within seconds on web
clients during 4-player matches.

GameLift remaps container ports to dynamic host ports from the
fleet's `InstanceConnectionPortRange` (4192-4211). Each game
session gets 2 consecutive host ports:

- `Port+0` → container `4433 UDP` (ENet, returned as `Port`)
- `Port+1` → container `4434 TCP` (nginx TLS detection)

GameLift documentation says port mapping is random, but with
exactly 2 container ports the `Port+1` offset has been
reliable across all testing. **Do not add more container
ports.** Adding a third entry (e.g., 4435-4437/UDP) causes
GameLift to assign host ports beyond the
`InstanceConnectionPortRange`, breaking the `Port+1` WSS
offset. This was verified in v0.27.0 where port 4212 was
assigned outside the 4192-4211 range. GameLift requires
different port numbers per entry, even for different
protocols. Using the same number (e.g., 4433/UDP and
4433/TCP) causes GameLift to deduplicate.

**Important:** The port range must accommodate pairs. With 2
container ports per session, ensure `ToPort - FromPort + 1`
is even. An odd range wastes the last port and can cause
the WSS port to fall outside the range.

#### DNS Pre-Warming

DNS hostnames are derived deterministically from the server
IP: `35.91.191.229` → `s-35-91-191-229.game.hopnbop.net`.
The `entrypoint.sh` creates this Route 53 A record at
container startup (via EC2 IMDS for the public IP), minutes
before any game session is placed. By the time clients
connect, DNS is fully propagated. No per-session DNS
creation needed.

The backend derives the same hostname from the server IP
(in `_hostname_from_ip()`) and returns it to clients in the
matchmaking response. Both sides compute the hostname
independently from the IP.

Wildcard cert for `*.game.hopnbop.net` via Let's Encrypt
DNS-01. Stored in Secrets Manager (`hopnbop/tls-wildcard-cert`).
Expires **2026-06-09**. Renewal needed before then.

The `GameLiftContainerFleetRole` IAM role has an inline
policy (`Route53DnsWarmup`) granting
`route53:ChangeResourceRecordSets` on the hosted zone.

#### Godot Native WSS Limitation (2026-03-17)

Godot 4.5's native `WebSocketMultiplayerPeer` cannot
connect via `wss://` to any remote server. Every
configuration was tested with no success: default TLS,
`TLSOptions.client_unsafe()`, Godot TLS server, nginx TLS
proxy, with and without `supported_protocols`. The
connection fails instantly (not a timeout). Browser `wss://`
works fine (different TLS stack). Related Godot issues:
[#34083](https://github.com/godotengine/godot/issues/34083),
[#95217](https://github.com/godotengine/godot/issues/95217).

**Workaround:** Native clients use plain `ws://` (no TLS).
nginx's `ssl_preread` detects the lack of TLS and passes
the connection through to Godot without encryption. This
is acceptable because native ENet (the default transport)
is also unencrypted UDP.

### End-to-End Matchmaking Flow

1. Client calls `POST /auth/anon` to get JWT
2. Client calls `POST /matchmaking/start` with JWT
3. Client polls `GET /matchmaking/status/{ticket_id}`
4. Response includes `server_ip`, `server_port`,
   `player_session_ids`, `transport_type` (all dynamically
   assigned)
5. Client connects to the server:
   - ENet match: `enet://IP:Port` (UDP)
   - WebRTC match: `ws://` or `wss://` to
     `hostname:Port+1` (signaling through nginx),
     then DataChannels over UDP
   - WebSocket match: `ws://` or `wss://` to
     `hostname:Port+1` (TCP, through nginx)
6. Server validates player session IDs via GameLift SDK

API Gateway has a 29-second hard timeout. Use the two-step
start+poll approach, not a single blocking join endpoint.

## Architecture

### Networking Layer (src/networking/)

The networking system is frame-based with rollback support:

- **NetworkMain** - Top-level controller, accessed via `G.network` singleton
- **NetworkFrameDriver** - Core frame simulation at 60 FPS. Increments
  `server_frame_index` directly on each physics tick for deterministic frame
  progression. Manages rollback buffer and reconciliation.
- **ReconcilableNetworkedState** - Base class for all networked entities;
  implements client prediction + server authoritative reconciliation
- **ServerTimeTracker** - NTP-like clock sync between client and server. Server
  frame timing is based on physics ticks, with periodic wall-clock re-sync for
  accurate logging.
- **NetworkConnector** - ENet/WebSocket/WebRTC peer management (default port 4433)

**Frame Processing Flow:**
1. `_pre_network_process()` - Sync scene state from rollback buffer
2. `_network_process()` - Game logic executes (frame-synchronous)
3. `_post_network_process()` - Pack state for replication

All networked entities must extend ReconcilableNetworkedState and participate in this cycle.

### Game State (src/core/)

- **MatchState/MatchStateSynchronizer** - Replicated match data (players, kills, bumps)
- **PlayerState** - Per-player metadata (name, connection status)
- **GamePanel** - Game lifecycle orchestrator, handles level spawning
- **ClientSession** - Per-client session state

#### Signal Architecture

**MatchState is the single source of truth for all match events:**
- Low-level state change signals: `players_updated`, `kills_updated`, `bumps_updated`
- High-level game event signals: `player_joined`, `player_left`, `player_killed`, `players_bumped`
- MatchStateSynchronizer acts as a replication coordinator that triggers these signals
- All external code should connect to `G.match_state` signals for match events

#### Local Mode (Offline/Local-Only)

The game supports an offline local-only mode where the same
process acts as both server and client. The process stays
`is_server = false` (so client UI continues working) but sets
`Netcode.is_local_mode = true`. The property
`Netcode.runs_server_logic` (`is_server or is_local_mode`)
replaces `is_server` checks where server-side game logic must
also run locally.

**Local Mode RPC Pattern:** RPCs annotated with `call_remote`
do not reach the local process. Use `Netcode.call_client_rpc_with_local_support()`
to send the RPC and also call it directly in local mode. Bind
arguments before passing.

```gdscript
Netcode.call_client_rpc_with_local_support(
    _client_rpc_foo.bind(arg1, arg2))
```

Not all RPCs need this treatment. Only server-to-client RPCs
where the client needs to receive the call (e.g., match ended,
unpause, stats). Server-side functions that already apply state
locally before sending the RPC (e.g., snail crush/respawn) do
not need it.

### Character System (src/scaffolder/character/)

Reusable character framework:

- **Character** - Extends CharacterBody2D; manages velocity, collision, action state, surface contact
- **CharacterActionState** - State machine for movement (17+ action handlers for floor/wall/ceiling/air states)
- **CharacterStateFromServer** - Networked character state with rollback support
- **CharacterSurfaceState** - Tracks platform contact via raycasts

Action handlers in `src/scaffolder/character/action_handlers/` modify velocity and physics per frame.

### Player Implementation (src/player/)

- **Bunny** - Game-specific player extending the character system
- **PlayerActionSource** - Translates player input to action commands

### Level System (src/level/)

- **Level** - Scene container managing players_by_id dictionary and MultiplayerSpawner
- Server instantiates players for connected clients; clients receive spawned instances

### Web Build Cross-Play

FlexMatch uses an `is_web` player attribute for platform
preference matching (relaxes after 15 seconds). The backend
determines `transport_type` ("enet" or "websocket") from
matched players and includes it in the matchmaking response.

- Client sets `Netcode.settings.transport_type` from the
  response before connecting.
- Server sets transport from matchmaker data in
  `_on_game_session_started`. Only switches to WebSocket
  if the match includes a web player. ENet-only matches
  stay on ENet.
- Backend returns `s-{ip}.game.hopnbop.net` hostname for
  WebSocket matches (DNS pre-warmed at container startup).
- Web clients connect via `wss://hostname:Port+1` (through
  nginx TLS termination).
- Native clients connect via `ws://hostname:Port+1` (through
  nginx pass-through, no TLS).
- Local/preview always uses `ws://`.

## Networking Concepts Reference

This section documents game networking patterns used in this project. These concepts apply broadly to multiplayer game development.

### Client-Side Prediction

Without prediction, players experience input delay equal to their round-trip latency (e.g., 100ms ping = 100ms delay before seeing movement). Client-side prediction solves this by immediately simulating the predicted result of player inputs locally, providing instant visual feedback while the server validates those inputs in parallel.

**How it works:**
1. Player presses input → client immediately simulates the action locally
2. Input is sent to server with a sequence number
3. Client continues predicting future frames while awaiting confirmation
4. Server processes input and sends authoritative state back

### Server Reconciliation

When the server's authoritative state differs from the client's prediction, reconciliation corrects the client without visible stuttering.

**Reconciliation algorithm:**
1. Client receives server state with last-processed input sequence number
2. Client resets to server's confirmed state
3. Client replays all unacknowledged inputs on top of server state
4. Result becomes new prediction baseline

**Snap vs. Smooth reconciliation:**
- Snap: Instantly teleport to corrected position (causes visible jitter)
- Smooth: Gradually interpolate toward corrected position over several frames (this project uses smooth reconciliation via rollback buffer)

### Rollback Netcode

Rollback extends reconciliation by maintaining a buffer of historical states. When a mismatch is detected:
1. "Roll back" game state to the mismatched frame
2. Re-simulate all frames from that point with corrected data
3. Fast-forward back to present

This project's `NetworkFrameDriver` implements rollback with configurable buffer duration (default 1.5 seconds / ~90 frames at 60 FPS).

### Frame Synchronization

Deterministic simulation requires all clients to process the same inputs on the same frame numbers. This project uses:
- Fixed 60 FPS network tick rate (independent of render framerate)
- Server-authoritative frame numbering
- NTP-like clock synchronization (`ServerTimeTracker`) to estimate server time

### Lag Compensation

For hit detection in latency-sensitive actions (shooting), the server can "rewind" entity positions to where they appeared from the shooter's perspective, accounting for round-trip latency. This ensures high-ping players can still hit targets they visually aimed at.

### Authority Models

**Server-authoritative (used here):** Server is the source of truth. Clients predict locally but defer to server corrections. Prevents cheating but requires reconciliation.

**Client-authoritative:** Each client owns their character's state. Simpler but vulnerable to cheating. Sometimes used for non-competitive games.

**Hybrid:** Server authoritative for game logic, but clients have authority over their input timing.

## Godot Multiplayer Patterns

### MultiplayerSynchronizer

Continuously replicates configured properties from authority to other peers. Key concepts:
- Each synchronized entity needs its own MultiplayerSynchronizer instance
- Configure which properties to sync via the Replication panel
- Default authority is server (peer 1); can be changed per-node
- Visibility filters control which peers receive updates

**Dual Synchronizer Pattern:** Use separate synchronizers for spawn state (server authority) and input/player state (peer authority) to maintain proper isolation.

### MultiplayerSpawner

Replicates node instantiation/deletion across peers (including mid-game joins). Key concepts:
- Set `spawn_path` to define where spawned nodes appear in tree
- Configure Auto Spawn List for scenes to replicate automatically
- Only replicates creation/deletion, not ongoing state (use MultiplayerSynchronizer for that)
- Use `spawn_limit` to constrain maximum instances

### Input Isolation Pattern

For player characters, use a dedicated child node for player inputs while keeping character node authority with the server. This separates control handling from game logic, reducing synchronization errors.

### Replicated State Sub-node Pattern

Create a sub-node within entities specifically for replicated state. Other scripts reference this node, maintaining clear separation between networked and local-only state. This project uses this pattern with `CharacterStateFromServer`.

### Physics Considerations

Godot's physics engine doesn't natively support rewinding/re-simulation. Options:
1. Server-only physics with position sync (simple but high bandwidth)
2. Custom physics stepping (this project's approach via frame-based simulation)
3. External libraries (Netfox, MonkeNet) that provide rollback-compatible physics

## Key Patterns

### Adding Networked Entities

1. Extend ReconcilableNetworkedState
2. Define synced properties in `_get_packed_state()` and `_apply_packed_state()`
3. Set mismatch thresholds for rollback detection
4. Register with NetworkFrameDriver (automatic via scene tree)

### Adding Character Actions

1. Create handler in `src/scaffolder/character/action_handlers/`
2. Follow pattern: modify velocity based on surface state and input
3. Register in CharacterActionState

### Circular Dependency Prevention

`ReconcilableState` (base class) must never reference subclass
`class_name`s (`PlayerInputFromClient`,
`CharacterStateFromServer`,
`ForwardedPlayerInputFromServer`) as type annotations. This
creates circular compile-time dependencies that break exported
builds.

Use the `ReconcilableStateType` enum and `_get_type()` virtual
method pattern instead of `is` type checks. Access subclass
properties through `ReconcilableState`-typed variables using
`get()` or `call()` for dynamic dispatch.

### Web Build Cyclic-Reference Parser Failures

Godot 4.7-beta1's web exporter runs a stricter parser pass than
the editor or desktop builds. Parse messages of this shape
appear at boot in the web log:

```
SCRIPT ERROR: Parse Error: Could not resolve external class
member "settings": Cyclic reference.
   at: GDScript::reload (res://src/.../foo.gd:42)
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
ERROR: Failed to load script "res://src/.../bar.gd"
  with error "Compilation failed".
```

**These messages are NOT just noise on web.** They are load-
fatal when they appear: the script at the originating line
fails to register its `class_name`, and any `ClassName.new()`
call later returns null silently. Symptoms surface much later
at first instantiation, not at boot, which makes diagnosis
hard:

```
ERROR: Error constructing a GDScriptInstance: '...::_init':
   Cannot convert argument 1 from Nil to int
```

(Identified 2026-04-30 when `ScaffolderLog.new()` returned
null on web because `scaffolder_log.gd:42` did
`G.settings.include_category_in_logs` — direct typed access
through the `G` autoload tripped the parser's cyclic-resolution
pass. Symptom showed up much later as `RollbackBuffer.new()`
crashing because `Netcode.log` was null and so
`Netcode.initialize()` had bailed.)

Desktop builds suppress the parser cascade entirely, which is
why this never appears in desktop logs.

#### Surgical fix pattern

When a parse error of this shape originates inside a
`class_name`'d script that accesses `G.<typed-autoload-prop>.<member>`,
rewrite the access to use `Object.get()` for dynamic dispatch:

```gdscript
# Before (parser tries to statically resolve through cyclic
# autoload graph, fails on web):
if G.settings.include_category_in_logs:
    ...

# After (dynamic dispatch — parser doesn't chase the cycle;
# desktop is unaffected, autocomplete is lost only at this
# line):
var include_category: bool = (
    G.get("settings").get("include_category_in_logs"))
if include_category:
    ...
```

Cache the value into a typed local once at the top of the
function so the rest of the function still reads cleanly. Only
apply this at the specific lines named in the parse-error
stack trace; keep typed access everywhere else.

#### Other workarounds (use only if the surgical fix isn't
viable)

1. Replace `preload("res://...")` with `load("res://...")` at
   the cycle-trigger site. Defers resolution past the parser's
   check phase. Zero runtime cost for a one-shot autoload-init
   load.
2. Cast at access site: `(G as GlobalClass).settings.foo`.
3. Static-instance singleton: declare `class_name GlobalClass`
   with `static var I: GlobalClass; func _enter_tree(): I = self`,
   reference as `GlobalClass.I.settings.foo`.

Approach #3 is the cleanest long-term restructure; the
surgical `.get()` rewrite is the safest narrow fix.

#### Investigation playbook

1. Web log shows `ERROR: Failed to load script ".../foo.gd"`
   downstream of `Parse Error: Could not resolve external class
   member` — the originating script is named in the
   `at: GDScript::reload (.../bar.gd:N)` line just above the
   parse error, NOT the script in the "Failed to load" line.
2. The "Failed to load" scripts are just downstream casualties
   of the originating parse failure.
3. Look up the originating line and find the
   `G.<autoload-prop>.<member>` or similar typed-autoload chain
   access; apply the `.get()` rewrite there.
4. If runtime errors appear far from boot (e.g., at first
   spawn), trace back: what class did `.new()` on something?
   Was that class registered? Search for parse failures naming
   that class's source file in the boot log.

Upstream Godot tracker:
[godot#80877](https://github.com/godotengine/godot/issues/80877)
(meta-issue, 40+ linked).

### Internationalization (i18n)

All user-visible strings must be hooked up to Godot's
translation system using `tr()`. When adding or modifying
user-facing text, check the existing translation files in
the project to determine supported languages and file
format, then provide translations for all of them.

### Viewport and Camera (src/core/pixel_viewport_manager.gd)

`PixelViewportManager` sizes the `SubViewportContainer` to
fill the window at the nearest integer pixel scale and adjusts
the active camera's zoom so the base viewport area is always
visible.

**Camera anchor mode:** Godot 4.5 defaults Camera2D to
`FIXED_TOP_LEFT`. PVM sets `ANCHOR_MODE_DRAG_CENTER` on
first contact so extra viewport space is distributed
equally on all sides. Do not use `camera.offset` to "fix"
centering. `DRAG_CENTER` already centers the view.

**Camera activation:** Each level has a static `level_camera`
(Camera2D). Because `queue_free` on the previous level is
deferred, the new level's camera enters the tree while the
old camera is still alive and current. Auto-activation
only triggers when no current camera exists, so the new
camera must call `make_current()` explicitly. This is done
in `_server_spawn_level` and `_client_on_level_spawned`.

**Camera change detection:** PVM forces a
`_on_window_resized()` call when the active camera changes
(the `size_changed` signal can miss resizes during scene
teardown/setup). `_last_camera` must be set before calling
`_on_window_resized` to prevent mutual recursion
(`_on_window_resized` → `_update_camera_zoom` →
`_on_window_resized`).

**No per-player camera:** The bunny has no Camera2D. The
level camera is used for everything, including the
end-of-match celebration (which tweens the level camera's
`offset` to follow the winner).

## UI Patterns

### Navigation

All interactive UI elements must be navigable with U/D and
L/R controls. Players use gamepads or keyboard. UI that only
responds to mouse/touch is not acceptable.

**Side panels** (`SidePanel` subclasses): Every interactive
element (button, toggle, link) must be a `SettingsRow`
subclass added directly to `_row_container`. The base class
scans `_row_container.get_children()` for `SettingsRow`
instances. Non-SettingsRow children (spacers, labels) are
ignored. Call `_connect_row_clicked(row)` for each row and
`rebuild_row_list()` after dynamic content changes.

For dynamically generated rows that don't need a scene file,
use `ActionRow` (extends `SettingsRow`). Call
`setup_actions(on_right, on_left)` with callables for L/R
input. Right/trigger is the primary action. Example:

```gdscript
var row := ActionRow.new()
var content := HBoxContainer.new()
content.mouse_filter = Control.MOUSE_FILTER_IGNORE
row.add_child(content)
# ... add labels/buttons to content ...
row.setup_actions(primary_action, secondary_action)
_row_container.add_child(row)
_connect_row_clicked(row)
```

**Screens** (`Screen` subclasses using `ScreenFocusNavigator`):
All interactive buttons must be in the focusable list via
`_navigator.set_focusable_list(items)`. Dynamically created
buttons (e.g., friend action buttons in result rows) must also
be added.

### Button Icons

Use pixel-art icons in most buttons. All icon buttons must use
the same scale from Settings:

```gdscript
button.expand_icon = true
button.add_theme_constant_override(
    "icon_max_width",
    int(G.settings.get_icon_display_width()))
```

Icon assets live in `assets/images/gui/`. When a new feature
needs an icon that doesn't exist yet, ask for one. Do not
ship buttons without icons or use placeholder text where an
icon is expected.

## Configuration

- **settings.tres** - Runtime settings (network, debug, gameplay)
- **project.godot** - Input actions, physics layers, rendering config

Debug toggles in settings: `dev_mode`, `draw_annotations`, `perf_tracker_enabled`, `debug_console_enabled`

## Code Style

Follow the
[Godot GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
with the project-specific additions below.

### Formatting

- **Indentation:** Tabs (4-space width), enforced by
  `.editorconfig`.
- **Line length:** 80 characters maximum.
- **Blank lines:** Two blank lines between functions/methods.
- **Line wrapping:** Prefer parentheses over backslashes for
  line continuation. Conversely, unwrap lines onto a single
  line when they fit within the 80-character limit.
- **Operator placement:** When wrapping expressions across
  multiple lines, place operators at the start of the next
  line, not the end of the previous line.
- **Trailing commas:** Include trailing commas in multi-line
  function calls, arrays, and dictionaries.

```gdscript
# Correct: parens for wrapping, operator at start of line.
var is_valid := (
	is_instance_valid(node)
	and node.is_inside_tree()
	and not node.is_queued_for_deletion()
)

# Correct: trailing comma in multi-line call.
some_function(
	first_arg,
	second_arg,
)

# Wrong: backslash continuation.
var is_valid := is_instance_valid(node) \
	and node.is_inside_tree()

# Wrong: operator at end of line.
var is_valid := (
	is_instance_valid(node) and
	node.is_inside_tree()
)
```

### Naming Conventions

- **Classes/enums:** `PascalCase`
- **Functions/variables:** `snake_case`
- **Constants:** `UPPER_SNAKE_CASE`
- **Private members:** Prefix with underscore (`_my_var`,
  `_my_method`)
- **Signals:** Past tense (`player_died`, `match_started`)
- **Booleans:** Prefix with `is_`, `can_`, `has_`
- **No prefixes:** Avoid prefixes in variable names (e.g.,
  use `speed` not `player_speed` when already inside a player
  class). The underscore prefix for private members is the
  exception.
- **No abbreviations:** Use full words in identifiers (e.g.,
  `diagnostic` not `diag`, `configuration` not `config`,
  `information` not `info`). Standard domain abbreviations
  (`rtt`, `fps`, `rpc`, `usec`, `id`) are acceptable.

### Type Annotations

- Use `:=` for inferred types on variable declarations.
- Always specify return types on functions.
- Use explicit type hints for `@export` vars and function
  parameters.

```gdscript
var speed := 10.0
const _MAX_SPEED := 200.0
@export var jump_height: float = 64.0

func get_speed() -> float:
	return speed
```

### Negation

- Prefer `not` over `!` for boolean negation.
- Do use `!=` for inequality comparisons.

```gdscript
# Correct.
if not is_alive:
	return
if count != 0:
	process()

# Wrong.
if !is_alive:
	return
```

### Comments and Prose

- End all comments with a period.
- Use `##` for doc comments (Godot documentation comments),
  `#` for regular comments.
- Never use em dashes, en dashes, or hyphens as grammatical
  em dashes. Use a period and start a new sentence instead.
- Wrap comments at 80 characters, matching the code line
  limit.

```gdscript
## Advances the snail by the given number of
## network frames. Each frame applies a fixed
## movement step.
func _simulate_frames(count: int) -> void:

# Wrong: em dash in comment.
# The snail moves forward — unless blocked.

# Correct: period and new sentence.
# The snail moves forward. It stops when blocked.
```

### File Structure

Follow the Godot-recommended ordering within each script:

1. `@tool`
2. `class_name`
3. `extends`
4. Doc comment (`##`)
5. `signal` declarations
6. `enum` declarations
7. `const` declarations
8. `@export` variables
9. Public variables
10. Private variables (`_`-prefixed)
11. `@onready` variables
12. `_init()`, `_enter_tree()`, `_exit_tree()`, `_ready()`
13. `_process()`, `_physics_process()`
14. Other virtual/callback methods
15. Public methods
16. Private methods

### Constants Over Inline Values

Use file-level `const` declarations instead of hard-coding
static values inline in functions. Private constants use
underscore prefix.

```gdscript
# Correct: file-level constant.
const _RESPAWN_DELAY_FRAMES := 30

func _respawn() -> void:
	timer = _RESPAWN_DELAY_FRAMES

# Wrong: magic number inline.
func _respawn() -> void:
	timer = 30
```

### Scene Templates Over Scripts

Prefer configuring state in `.tscn` scene files rather than
in scripts:

- **Animations:** Configure `AnimatedSprite2D.sprite_frames`
  animations in the scene editor, not in code.
- **Resource references:** Use `@export` vars and assign
  resources in the scene inspector. NEVER use `preload()` or
  `load()` for resource references in scripts.
- **Node references:** Use `%NodeName` unique-name syntax in
  scenes when referencing sibling/child nodes.

**Editing `.tscn` files directly (without the Godot editor):**
Scene files can be edited as text. The key fields are:
- `load_steps=N` in the header — increment N for each new
  `[ext_resource]` entry added.
- `[ext_resource type="PackedScene" path="res://..." id="X"]`
  — declares a scene dependency. Use a unique `id` string.
  `uid=` is optional; omit it if the scene has no UID yet.
- `[node name="Foo" parent="." instance=ExtResource("X")]`
  — instantiates the scene as a child node.
- Export vars on an instanced node are set directly on the
  node entry, e.g. `doc_type = 0`. Enum values are integers
  (0, 1, 2…) matching declaration order.

```gdscript
# Correct: export var assigned in scene inspector.
@export var death_effect: PackedScene

# Wrong: preload in script.
const _DEATH_EFFECT := preload(
	"res://src/effects/death_effect.tscn"
)
```

### Direct Access Over Local Copies

Do not assign local or class-level variable copies of
autoload properties (`G`, `Netcode`) or unique-name nodes
(`%`). Access them directly where needed.

```gdscript
# Correct: access autoload properties directly.
if G.match_state.is_match_active:
	Netcode.server_frame_index += 1

# Wrong: local copy of autoload property.
var match_state := G.match_state
if match_state.is_match_active:
	pass

# Correct: access unique-name node directly.
%AnimatedSprite2D.play("idle")

# Wrong: local or class-level copy.
@onready var sprite := %AnimatedSprite2D
```

### Performance

- Prefer `distance_squared_to()` over `distance_to()` when
  feasible, to avoid unnecessary `sqrt` calculations.

### GDScript Formatter

The GDScript formatter addon is installed
(`addons/gdscript_formatter`). Format code before committing.

### Legacy Code Migration

Some older files use `!` for negation or backslash line
continuation. When modifying lines in these files, convert
them to the current style (`not`, parenthesized wrapping).
Do not bulk-convert unrelated lines in the same commit.

## Backend Testing (pytest)

The backend uses pytest with moto for AWS service mocking.
Tests live in `backend/tests/`.

### Running Backend Tests

```bash
cd backend
pip install -r tests/requirements.txt  # if needed
python -m pytest tests/ -v
python -m pytest tests/test_party.py -v  # single file
```

### Test Infrastructure

- **`conftest.py`** provides shared fixtures:
  - `_aws_env` (autouse): Sets environment variables for
    all tests.
  - `aws_mock`: Wraps tests in `moto.mock_aws()` with
    pre-created DynamoDB tables and Secrets Manager secrets.
    Re-initializes handler module-level service instances so
    they use mocked clients.
  - `mock_httpx_client(responses)`: Context manager for
    mocking OAuth provider HTTP calls.
  - `make_response(status_code, json_body)`: Builds fake
    httpx responses.
- **`constants.py`**: `TEST_JWT_SECRET`, `TEST_REGION`.

### Test Patterns

**Debug auth:** Use `DEBUG_` prefix tokens (e.g.,
`"Bearer DEBUG_alice"`) to bypass JWT validation. The
handler's `_authenticate()` returns an `AuthToken` with
`player_id="DEBUG_alice"` for these tokens.

**Helper conventions (per test file):**
```python
class _FakeLambdaContext:
    function_name = "test-function"
    ...

def _make_event(body=None, headers=None, ...):
    """Build a minimal API Gateway event."""

def _parse_response(response):
    """Return (status_code, body_dict)."""

def _auth_headers(player_id):
    """Return {'Authorization': 'Bearer DEBUG_...'}."""

def _create_player(player_id, display_name, ...):
    """Insert a player row into the test table."""

def _run(coro):
    """asyncio.run() wrapper."""
```

**Service tests** instantiate service classes directly
within `aws_mock` and call async methods via `_run()`.

**Handler tests** invoke Lambda handler functions with
`_make_event()` and `_CONTEXT`, then assert on status
code, error codes, and response body.

### Adding New Handler Tests

1. Add service reinitialization to
   `conftest._reinit_handler_services()` if the handler
   module is not already covered.
2. Create `tests/test_<feature>.py` with the helper
   pattern above.
3. Use `_create_player()` and direct DynamoDB puts for
   test data setup.
4. Always use `aws_mock` fixture for DynamoDB/Secrets
   Manager access.

## Testing with GUT

This project uses GUT (Godot Unit Test) 9.x for testing. Tests are organized
in `res://test/` with separate directories for unit and integration tests.

### Test File Structure

- Files must start with `test_` prefix (e.g., `test_rollback_buffer.gd`)
- Extend `GutTest` base class
- Use `func test_*()` naming for test methods
- Configuration in `res://.gutconfig.json`

### Common Assertions

```gdscript
# Equality
assert_eq(actual, expected, "optional message")
assert_ne(actual, expected)

# Null checks
assert_null(value)
assert_not_null(value)

# Boolean
assert_true(condition, "message")
assert_false(condition)

# Numeric comparisons
assert_gt(value, threshold)  # greater than
assert_lt(value, threshold)  # less than
assert_almost_eq(actual, expected, tolerance)

# Godot types
assert_almost_eq(vector1, vector2, tolerance)
assert_has(array_or_dict, value)
assert_does_not_have(array_or_dict, value)

# Signals
watch_signals(object)
assert_signal_emitted(object, "signal_name")
assert_signal_not_emitted(object, "signal_name")
```

### Test Lifecycle Methods

```gdscript
extends GutTest

# Run once before any tests in this script
func before_all():
	pass

# Run before each test
func before_each():
	pass

# Run after each test
func after_each():
	pass

# Run once after all tests
func after_all():
	pass
```

### Test Doubles (Mocking)

**Creating Doubles:**
```gdscript
# Double a script
var MyClass = preload("res://src/my_class.gd")
var DoubledClass = double(MyClass)
var instance = DoubledClass.new()

# Double a scene
var MyScene = load("res://scenes/my_scene.tscn")
var DoubledScene = double(MyScene)
var instance = DoubledScene.instantiate()
```

**Stubbing Methods:**
```gdscript
# Return a specific value
stub(instance, 'method_name').to_return(42)

# Call original implementation
stub(instance, 'method_name').to_call_super()

# Stub with parameters
stub(instance, 'method_name').param_count(2).to_return(value)
```

**Spies (Verifying Calls):**
```gdscript
# Check if method was called
assert_called(instance, 'method_name')
assert_not_called(instance, 'method_name')

# Check call count
assert_call_count(instance, 'method_name', 3)

# Check parameters
assert_called_with(instance, 'method_name', [arg1, arg2])
```

**Important Notes:**
- Inner classes need `register_inner_classes(ClassName)` before doubling
- Doubles are freed automatically after each test
- Don't create doubles in `before_all()` - use `before_each()`
- Use `partial_double()` to keep some original functionality

### Parameterized Tests

Run the same test with different inputs:

```gdscript
var test_cases = [
    [0, 0],        # input, expected
    [5, 25],
    [-3, 9],
]

func test_square(params=use_parameters(test_cases)):
    var input = params[0]
    var expected = params[1]
    assert_eq(square(input), expected)
```

**Named Parameters (more readable):**
```gdscript
var test_cases = ParameterFactory.named_parameters(
	['input', 'expected'],
    [
        [0, 0],
        [5, 25],
    ]
)

func test_square(p=use_parameters(test_cases)):
    assert_eq(square(p.input), p.expected)
```

### Inner Test Classes

Organize related tests with shared setup:

```gdscript
extends GutTest

class TestWhenEmpty:
    extends GutTest

    var buffer

    func before_each():
        buffer = Buffer.new()

    func test_size_is_zero():
        assert_eq(buffer.size(), 0)

    func test_pop_returns_null():
        assert_null(buffer.pop())

class TestWhenFull:
    extends GutTest

    var buffer

    func before_each():
        buffer = Buffer.new(capacity=3)
        buffer.push(1)
        buffer.push(2)
        buffer.push(3)

    func test_size_is_capacity():
        assert_eq(buffer.size(), 3)
```

### Async Testing

For testing signals and coroutines:

```gdscript
func test_async_operation():
    var obj = MyClass.new()
    add_child_autofree(obj)

    watch_signals(obj)
    obj.start_async_operation()

    # Wait for signal
    await wait_for_signal(obj.completed, 2.0)  # 2 second timeout

    assert_signal_emitted(obj, "completed")

func test_with_frames():
    var obj = MyClass.new()
    add_child_autofree(obj)

    obj.start()

    # Wait for next frame
    await wait_frames(1)

    assert_true(obj.is_running)
```

### Scene Testing

```gdscript
func test_scene_interaction():
    var scene = load(
        "res://test/fixtures/test_scene.tscn"
    ).instantiate()
    add_child_autofree(scene)

    # Scene is now in tree and can be tested
    var button = scene.get_node("Button")
    button.pressed.emit()

    # Cleanup happens automatically via autofree
```

### Common Patterns for This Project

**Testing Networking Code:**
```gdscript
# Mock NetworkMain
var MockNetworkMain = double(NetworkMain)
stub(MockNetworkMain, 'is_server').to_return(true)
stub(MockNetworkMain, 'get_current_tick').to_return(100)

# Mock multiplayer API
var MockMultiplayer = double(MultiplayerAPI)
stub(MockMultiplayer, 'get_unique_id').to_return(1)
```

**Testing Rollback Logic:**
```gdscript
# Create fixture states
var state_frame_10 = {"x": 100, "y": 200}
var state_frame_20 = {"x": 150, "y": 250}

buffer.store_state(10, state_frame_10)
buffer.store_state(20, state_frame_20)

# Test rollback
var retrieved = buffer.get_state(10)
assert_eq(retrieved.x, state_frame_10.x)
```

**Testing Character Actions:**
```gdscript
# Create test character with mocked dependencies
var character = partial_double(Character)
character.velocity = Vector2.ZERO
character.surface_state = create_floor_surface_state()

# Test action handler
var action = FloorWalkAction.new()
action.process(character, delta, instructions)

assert_gt(character.velocity.x, 0, "Should move right")
```

### Running Tests

**Editor:**
- Open GUT panel (bottom dock)
- Select test file or directory
- Click "Run All" or specific test

**Command Line:**
```bash
# Run all tests
godot --headless -s --path . addons/gut/gut_cmdln.gd -gexit

# Run unit tests only
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gdir=res://test/unit -gexit

# Run specific test
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gtest=res://test/unit/networking/test_rollback_buffer.gd -gexit

# Export results
godot --headless -s --path . addons/gut/gut_cmdln.gd \
  -gexit -gjunit_xml_file=results.xml
```

**Exit codes:** 0 = success, 1 = failures

### Best Practices

1. **One concept per test** - Test one behavior in each test method
2. **Descriptive names** -
   `test_rollback_triggers_on_mismatch_above_threshold` not
   `test_rollback`
3. **AAA pattern** - Arrange (setup), Act (execute), Assert (verify)
4. **Use fixtures** - Create reusable test data in `before_each`
5. **Mock external dependencies** - Don't rely on file I/O, network, etc.
6. **Test edge cases** - Empty, null, boundary values, error conditions
7. **Keep tests fast** - Unit tests should run in milliseconds
8. **Deterministic tests** - No randomness, no timing dependencies
   (in unit tests)
9. **Clean up** - Use `add_child_autofree()` for nodes, GUT handles
   the rest

### Common Pitfalls

- **Forgetting to extend GutTest** - Tests won't be discovered
- **Missing `test_` prefix** - Method won't run as a test
- **Creating doubles in before_all()** - Use before_each() instead
- **Not registering inner classes** - Call `register_inner_classes()`
  first
- **Assuming execution order** - Tests can run in any order
- **Testing implementation details** - Test behavior, not internals
- **Integration tests in unit test dir** - Keep them separated

### Project-Specific Testing Notes

**Running Tests Successfully:**
- Run specific test files rather than directories for reliability:
  ```bash
  godot --headless -s --path . addons/gut/gut_cmdln.gd \
	-gtest=res://test/unit/scaffolder/test_circular_buffer.gd -gexit
  ```
- Directory-based runs (`-gdir=res://test/unit`) sometimes fail to
  discover tests
- Always use `-gexit` flag for CI/CD to get proper exit codes

**Critical Test Setup Patterns:**
- **ArrayPool management is mandatory** - Every test that uses ArrayPool
  (directly or indirectly through CircularBuffer/RollbackBuffer) MUST call
  `ArrayPool.clear_all_pools()` in both `before_each()` and `after_each()`
- **Type hints for Arrays** - GDScript tests require explicit type hints
  when retrieving arrays:
  ```gdscript
  var state: Array = buffer.get_at(5)  # Correct
  var state = buffer.get_at(5)         # May fail type checking
  ```

**Testing Networking Components:**
- The `G` singleton (Global) is auto-loaded and initializes networking
  subsystems
- Tests run with full autoload context - NetworkMain, NetworkFrameDriver,
  etc. are active
- Frame-based simulation uses `NetworkFrameDriver.TARGET_NETWORK_TIME_STEP_SEC`
  (1/60 = 0.01666... seconds)
- Use `ReconcilableNetworkedState.FrameAuthority` enum values (UNKNOWN=0,
  AUTHORITATIVE=1, PREDICTED=2)

**Accessing Internal State:**
- Avoid accessing private members like `buffer._data[i]` in tests when
  possible
- Use public API methods (`get_at()`, `set_at()`) for better encapsulation
- If internal access is necessary, understand it couples tests to
  implementation

**Known Test Failures:**
- A few tests check array instance equality which fails due to GDScript's
  array semantics
- Some tests access RollbackBuffer internal state for validation - these
  may break if implementation changes
- Type coercion in assertions: use explicit types to avoid GDScript type
  inference issues

**Test Coverage:**
- Unit tests: CircularBuffer (47 tests), ArrayPool (13 tests),
  RollbackBuffer (20 tests), ServerTimeTracker (12 tests)
- Integration tests: Rollback flow (10 tests), state synchronization
  (10+ tests), frame timing (14+ tests)
- Total: 90+ tests covering core networking infrastructure

## References

Networking concepts and patterns:
- [Gabriel Gambetta's Client-Side Prediction and Server Reconciliation](https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html) - Definitive explanation of prediction/reconciliation
- [Godot High-Level Multiplayer Docs](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html) - Official Godot networking documentation
- [Godot Scene Replication (4.0)](https://godotengine.org/article/multiplayer-in-godot-4-0-scene-replication/) - MultiplayerSynchronizer/Spawner introduction

Godot networking addons (for reference, not used in this project):
- [Netfox](https://forum.godotengine.org/t/netfox-addons-for-online-multiplayer-games/36066) - Client-side prediction and server reconciliation addon
- [MonkeNet](https://github.com/grazianobolla/godot-monke-net) - C# addon with prediction, interpolation, lag compensation

## Known Issues

### Web Client WebSocket Buffer Overflow (2026-03-17)

Web clients in cross-play matches eventually hit "Buffer
payload full! Dropping data" errors. The server replicates
state for all players via MultiplayerSynchronizer nodes,
generating ~150-500 state updates per second. The web
client's single-threaded WASM runtime cannot always drain
the inbound buffer fast enough.

**Mitigation:** WebSocket buffers increased to 1MB
(default 64KB) and max queued packets to 16384 (default
2048). This provides ~7-30 seconds of headroom before
overflow. A proper fix would be reducing the server's
send rate for web peers (e.g., 30 FPS state updates
instead of 60), but that is an architectural change.

### WebSocket Cross-Play Latency (2026-03-17)

Desktop clients in WebSocket cross-play matches see
~100ms ping and 13-25% perceived packet loss, compared
to ~25ms ping and 0% loss with ENet-only matches. This
is inherent to TCP vs UDP: WebSocket over TCP has
head-of-line blocking (a single lost packet stalls the
entire stream until retransmitted). The "packet loss" in
PERF stats measures late/missed frame updates, not actual
TCP drops. Gameplay is playable but noticeably less smooth
than ENet.

### Resolved Issues

**Server Stuck on "Waiting for Players" (2026-03-11,
resolved 2026-03-17):** Godot's WebSocket server rejects
HTTP upgrade requests with an `Origin` header (all
browsers send one), and GameLift port mapping is
unpredictable with 3+ container ports. Fixed by using
nginx with `ssl_preread` for TLS detection on 2 container
ports, with Origin stripping in the TLS termination path.

**Native Clients Cannot Connect via WSS (2026-03-16,
resolved 2026-03-17):** Godot 4.5's native mbedTLS-based
WebSocket client cannot establish `wss://` connections to
any remote server. Worked around by having native clients
use plain `ws://` through nginx's pass-through path. See
"Godot Native WSS Limitation" in the WSS TLS Termination
section.

**WebRTC ICE Fails on GameLift (2026-04-02, resolved
2026-04-09):** WebRTC cross-play stopped working after
a fleet deployment. SDP exchange succeeded but ICE
connectivity checks timed out. Three root causes:
(1) The webrtc-native GDExtension v1.0.9 ignores
`portRangeBegin`/`portRangeEnd` in `initialize()`, so
the ICE agent bound to ephemeral UDP ports not
forwarded by GameLift. Fixed by patching the
GDExtension at Docker build time.
(2) The STUN-reflected srflx candidate advertised the
container port (4433) instead of the GameLift host
port. Fixed by rewriting the candidate port in the
signaling server before sending to clients.
(3) Multiple PeerConnections could not share port 4433
because libjuice's mux mode was not enabled
(`JUICE_CONCURRENCY_MODE_POLL` default). Fixed by
adding `enableIceUdpMux: true` to the initialize
config, which sets `JUICE_CONCURRENCY_MODE_MUX`.
Also required adding port 4433/UDP to the fleet's
`InstanceInboundPermissions` (GameLift uses
port-preserving NAT for outbound STUN, so return
traffic arrives on host port 4433).

**Buffer overflow on shutdown (2026-03-16, fixed):**
Server did not disconnect clients when cancelling a match
(grace period expiry) or during process termination with
no active match. Client did not close the WebSocket on
receiving the shutdown notification. Both fixed in
`gamelift_server.gd`, `game_panel.gd`, and
`network_connector.gd`.
