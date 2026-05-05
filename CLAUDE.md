# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hop 'n Bop is a multiplayer action game built with Godot 4.5. It implements client-side prediction with rollback reconciliation for networked gameplay.

## Platform infrastructure (read on demand)

Backend, auth, matchmaking, game-server allocation, and per-game
config are handled by the shared Snoring Cat platform. The
authoritative docs (in priority of relevance to most tasks):

- **`third_party/snoringcat-platform/PLATFORM_ARCHITECTURE.md`** —
  depth-first runtime detail: Nakama runtime, Edgegap allocation,
  identity/account-linking/deletion, per-game config schema,
  per-game protocol versioning (bump procedure), ops runbook.
  Read when implementing or debugging anything platform-side.
- **`third_party/snoringcat-platform/STUDIO_ARCHITECTURE.md`** —
  breadth-first studio overview: every service we use (Hetzner,
  Edgegap, Cloudflare, GitHub, Discord, UptimeRobot, Google
  OAuth, Meta), the repo map across the studio, the rationale
  for each top-level architecture decision, and standard
  operator procedures (new dev machine, rotate creds, oncall).
  Read when the question is "what services do we use and how
  do they fit together" or "where does <thing> live".

The platform migration from AWS GameLift to
Nakama+Hetzner+Edgegap completed 2026-05-03 (Phase F). Live
production runs on Hetzner CPX11 (Nakama + Postgres) with
Edgegap-allocated game-server containers. Historical migration
notes for archeology are in `MIGRATION_PLAN.md` and
`docs/archive/platform-pivot-discussion.md`.

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

This repo uses git submodules for shared Snoring Cat platform
code and the rollback-netcode framework. After cloning, run:

```bash
git submodule update --init --recursive
```

Submodules:
- `addons/rollback_netcode/` →
  [godot-rollback-netcode](https://github.com/SnoringCatGames/godot-rollback-netcode)
- `third_party/snoringcat-platform/` →
  [snoringcat-platform](https://github.com/SnoringCatGames/snoringcat-platform).
  Vendored as a submodule. The addon directory inside the
  submodule is **copied** into `addons/snoringcat_platform_client/`
  by `scripts/setup-platform-addon.ps1` (gitignored copy; copy
  rather than junction because Godot 4.6 reads stale parser-
  cache content through directory junctions on Windows). Re-run
  the script after every submodule bump.

To bump a submodule to a newer version, `cd` into it,
`git fetch && git checkout vX.Y.Z` (or `main`), then commit
the new SHA in this repo.

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

The platform layer (Nakama, Postgres, Caddy/TLS, observability,
cost-monitor) runs on Hetzner; game-server containers run on
Edgegap, allocated on demand by Nakama's matchmaker hook.
Operational details for the platform itself are in
`third_party/snoringcat-platform/PLATFORM_ARCHITECTURE.md` and
the provisioning scripts at
`third_party/snoringcat-platform/scripts/phase-{a,b}.ps1`.

### Deploy targets in this repo

| Target | Trigger | Where |
|---|---|---|
| Game server (Edgegap registry) | manual workflow_dispatch | `.github/workflows/game-server.yml` |
| Web client (Cloudflare Pages + R2) | tag push or manual | `.github/workflows/release.yml` (CI) or `scripts/deploy-cf-pages.ps1` (local) |
| Nakama runtime plugin | manual workflow_dispatch | `.github/workflows/nakama-runtime.yml` |
| Tagged release (game server + web + runtime) | push to `v*` tag | `.github/workflows/release.yml` |

### Game server deploy (Edgegap)

`game-server.yml` builds `Dockerfile.edgegap`, pushes to the
Edgegap registry as `v<N>`, and is then registered as a new
Edgegap app version via the dashboard. Bump
`EDGEGAP_APP_VERSION` on the Nakama host's `runtime.env` (see
"Versioning drift" in `NEXT_STEPS.md`) so the matchmaker hook
allocates the new version.

Required GH secrets: `EDGEGAP_TOKEN`, `EDGEGAP_REGISTRY_*`,
`EDGEGAP_REGISTRY_PROJECT`, `SUBMODULE_PAT`. The Harbor robot
credentials in `EDGEGAP_REGISTRY_USERNAME`/`PASSWORD` need
rotation when they expire (failure mode: HTTP 401 on docker
login).

### Web client deploy (Cloudflare Pages + R2)

`scripts/deploy-cf-pages.ps1` (local) or the `web-client` job
in `release.yml` (CI):

1. Godot exports `web/`.
2. Heavy assets (`.wasm` ~38 MB, `.pck`, `.audio.worklet.js`,
   `.audio.position.worklet.js`) upload to R2
   (`hopnbop-assets` bucket). Pages caps individual files at
   25 MiB, so the wasm doesn't fit on Pages.
3. `index.html`'s `GODOT_CONFIG` is patched in a staging copy
   to point at absolute R2 URLs.
4. Remaining files deploy to Cloudflare Pages
   (`hopnbop-website` project).

R2 bucket CORS is configured open for `GET`/`HEAD` from any
origin so the cross-origin wasm fetch works from the Pages
domain. The deploy script + the GHA both set CORS idempotently.

Required GH secrets: `CLOUDFLARE_API_TOKEN` (with Pages:Edit +
Workers R2 Storage:Edit + Account Settings:Read),
`CLOUDFLARE_ACCOUNT_ID`.

### Web export gotcha

Godot `--export-release "Web"` returns non-zero on missing-
resource warnings. The CI step uses `|| true` plus a sanity
`test -s build/web/index.html` to distinguish a real failure
from a cosmetic one. If you export locally and the script
treats a non-zero exit as failure, do the export by hand,
verify the artifact landed, then run with `-SkipExport`.

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

- Docker Desktop running (Edgegap server-image build + local
  smoke).
- Godot CLI on PATH (server + web exports).
- For local Cloudflare deploys: `CLOUDFLARE_PAGES_TOKEN` in
  `~/.hopnbop-migration/credentials.env` and `npm`/`npx`
  available (the script invokes `npx wrangler@latest`).
- For Edgegap deploys: an Edgegap account with the
  `hopnbop-server` app registered. Push images via
  `game-server.yml`, then bump the version in the dashboard
  + on the Nakama host's `runtime.env`.

### Version Management

**Single source of truth:** `project.godot`
- `config/version="X.Y.Z"` (display version, bump on
  redeploy)
- `config/protocol_version=N` (integer, bump only when
  client/server protocol changes)

**Synced locations:**
- Edgegap registry image tag (set by `game-server.yml`'s
  workflow input).
- Nakama host's `runtime.env` `NAKAMA_GAME_VERSION` and
  `EDGEGAP_APP_VERSION` (manual; bump after each deploy).
  Surfaced by the `version_check` runtime RPC and exercised
  by client startup.
- `export_presets.cfg` `file_version`/`product_version`
  (optional, currently empty).

**Version bumping policy:**
- When in doubt, bump the version. Always bump on redeploy.
- Prefer bumping minor over patch. Do not ask about version
  numbers. Pick whichever sounds best and proceed.

**Commit policy:**
- Work lands directly on `main`. No feature branches, no PRs,
  no squash merges. (This overrides the workspace-level default
  in `~/Repositories/CLAUDE.md`.)
- Do not commit partial or broken work. All changes for a
  feature must be working end-to-end before committing.
- You don't need explicit permission to commit or push.
  Commit and push to `main` at natural stopping points — when
  work is end-to-end working and at a logical checkpoint. This
  overrides Claude Code's default "ask first" behavior for
  this repo.
- When the change spans the parent repo and a submodule
  under `third_party/`, commit + push the submodule first,
  then bump the parent's submodule pointer in the next
  parent commit.
- Stage only files relevant to the change. The parent repo
  often carries unrelated dirty files (e.g., `settings.tres`,
  `.claude/settings.local.json`);
  do not sweep them in.
- Force-push and push to anything other than `main` still
  need explicit confirmation.

**Version check architecture:**
- `protocol_version` determines client/server compatibility.
  Only bump when the network protocol actually changes.
- `config/version` is for display only. Hotfix deploys can
  bump this without breaking existing clients.
- Client checks `protocol_version` at app startup via
  `GET /version` (unauthenticated). Also checked in auth
  response, matchmaking response, and server RPC.

### Production resources

**Hetzner platform tier** (Pulumi-managed in
`third_party/snoringcat-platform/infra/pulumi/snoringcat-platform/`):
- **Project:** `snoringcat-platform`, stack `prod`, state in
  Cloudflare R2 bucket `hopnbop-pulumi-state-r2`. Pulumi
  authenticates via S3-compat keys in `R2_ACCESS_KEY_ID` /
  `R2_SECRET_ACCESS_KEY` / `R2_ENDPOINT` (sourced from
  `~/.hopnbop-migration/credentials.env`).
- **nakama-prod-1:** CPX11 in Hillsboro, Nakama + Caddy +
  Prometheus/Grafana/Loki/Promtail + cost-monitor systemd timer.
- **postgres-prod-1:** CPX11 in Hillsboro, Postgres 16 + node-
  exporter + postgres-exporter.
- **DNS:** Cloudflare-managed; `nakama.snoringcat.games` and
  `grafana.snoringcat.games` records bound to the Hetzner public
  IPs.
- **Cost:** ~$15/mo for the pair (capped). See cost-monitor.

**Edgegap game-server fleet:**
- **App:** `hopnbop-server` (registered in Edgegap dashboard).
- **Active version:** stored on the Nakama host's
  `runtime.env` as `EDGEGAP_APP_VERSION=v<N>`. Bump after
  pushing a new image via `game-server.yml`.
- **Allocation:** on demand by Nakama's matchmaker hook; no
  always-on fleet.

**Cloudflare:**
- **Pages project:** `hopnbop-website` (auto-deploy via
  `release.yml`).
- **R2 bucket:** `hopnbop-assets` (heavies > 25 MiB live here).
- **Cost-monitor thresholds:** R2 warn 8 GB / hard 9.5 GB, Pages
  builds warn 400 / hard 475 of the 500/mo free tier.

**Legacy AWS:** fully torn down. Phase F (2026-05-03) deleted the
hopnbop-* GameLift / Lambda / S3 / CloudFront / Route 53 surface;
the orphan `snoringcat-platform-backend` SAM stack and Pulumi-
state S3 bucket were cleaned up the next day. **Zero AWS
resources remain in the account.** Pulumi state migrated to
Cloudflare R2.

### Game-server allocation (Edgegap)

Allocation is on-demand: when Nakama's matchmaker matches
players, the runtime hook calls Edgegap's deployment API to
spin up a `hopnbop-server` container in a region close to the
matched players. There's no always-on fleet — cold start to
ready is typically a few seconds (Edgegap holds warm pools
internally). Once the match ends or the deploy idles, Edgegap
tears the container down automatically and we're billed only
for active session minutes.

The matchmaker hook lives in
`third_party/snoringcat-platform/runtime/fleet_allocator.go`
and reads `EDGEGAP_TOKEN`, `EDGEGAP_APP_NAME`, and
`EDGEGAP_APP_VERSION` from the Nakama runtime env (configured
in `infra/remote/nakama/config.yml`'s `runtime.env` block).

The previous AWS GameLift-based fleet (with cold-start warmup,
fleet state DynamoDB table, and Lambda idle-checker) was
decommissioned in Phase F. The historical detail is in
`MIGRATION_PLAN.md` if needed for archeology.

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
1. Nakama matchmaker takes an `is_web` player attribute.
2. The runtime's `matchmaker_matched` hook reads `is_web`
   from the matched players' properties and sets
   `transport_type` in the match-ready payload it pushes
   to clients (`"enet"`, `"webrtc"`, or `"websocket"`).
3. Client sets `Netcode.settings.transport_type` from the
   match-ready payload before connecting.
4. Server reads matchmaker data on session-start and sets
   transport. Only switches away from ENet if web players
   are matched.

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
   port from 4433 to the Edgegap host port.
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

**ICE port pinning:** Only declared container ports get
forwarded to the host (Edgegap maps each declared port to a
dynamic host port at allocation time). The server pins the
ICE agent to container port 4433 via
`portRangeBegin`/`portRangeEnd` in `initialize()`.
Multiple PeerConnections share this port via libjuice mux
mode (`enableIceUdpMux: true`), which demultiplexes STUN
traffic by username fragment.

**ICE candidate rewriting:** The ICE agent's STUN-reflected
(srflx) candidate advertises the container port (4433), but
clients must connect to the Edgegap host port (e.g., 4205).
The signaling server rewrites the srflx candidate's port
before sending it to the client. The host port is derived
from the client's WSS port (which the runtime hook returns
as `host_udp_port + 1` in the match-ready payload).

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

Edgegap allocates 2 contiguous host ports per deployment, one
mapped to each declared container port:

- `Port+0` → container `4433 UDP` (ENet, returned as `Port`)
- `Port+1` → container `4434 TCP` (nginx TLS detection)

The runtime hook reads both host ports from Edgegap's
deployment response and includes them in the match-ready
payload. **Do not add more container ports** to
`Dockerfile.edgegap` — the `Port+1` offset assumption breaks
once a third container port enters the picture.

#### DNS Pre-Warming

DNS hostnames are derived deterministically from the server
IP: `35.91.191.229` → `s-35-91-191-229.game.hopnbop.net`.
The container's `entrypoint.sh` creates the Cloudflare DNS
A record at container startup (using the public IP from
Edgegap's deployment metadata), seconds before any client
needs to connect. Both sides compute the same hostname from
the IP, so the runtime can include it in the match-ready
payload without round-tripping the container.

Wildcard cert for `*.game.hopnbop.net` via Let's Encrypt
DNS-01. Stored on the container image at build time (or
mounted via Edgegap secret). Renewal cadence: 60-90 days.

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

1. Client authenticates with Nakama (anonymous device-id or
   linked OAuth provider) and gets a session token.
2. Client adds itself to the matchmaker via the Nakama socket
   API with platform attributes (e.g. `is_web`).
3. Nakama matches players and fires the `matchmaker_matched`
   hook in the runtime plugin.
4. The hook calls Edgegap to deploy a `hopnbop-server`
   container near the matched players, then notifies all
   matched clients with the allocated server endpoint
   (`server_ip`, `server_port`, `transport_type`,
   per-player session ticket).
5. Client connects to the server:
   - ENet match: `enet://IP:Port` (UDP).
   - WebRTC match: `ws://` or `wss://` to `hostname:Port+1`
     for signaling, then DataChannels over UDP.
   - WebSocket match: `ws://` or `wss://` to
     `hostname:Port+1` (TCP, through nginx).
6. Server validates the per-player session ticket against the
   match-ready payload Nakama sent it during allocation.

The Edgegap allocation typically completes in a few seconds.
There is no longer a 29-second API-Gateway timeout to dance
around — the realtime socket pushes the allocation result
when ready, no client polling.

## Architecture

### Networking Layer (addons/rollback_netcode/core/)

The networking framework was extracted out of this repo into
the shared `godot-rollback-netcode` submodule. The classes
described below all live there now (not under `src/networking/`,
which no longer exists). Game-specific networked entities and
session glue live in `src/core/` (e.g. `nakama_matchmaker_client.gd`,
`game_session_manager.gd`, `match_state.gd`).

The networking system is frame-based with rollback support:

- **NetworkMain** - Top-level controller, accessed via the
  `Netcode` autoload (was `G.network` pre-extraction).
- **NetworkFrameDriver** - Core frame simulation at 60 FPS.
  Increments `server_frame_index` directly on each physics tick
  for deterministic frame progression. Manages rollback buffer
  and reconciliation.
- **ReconcilableNetworkedState** - Base class for all networked
  entities; implements client prediction + server authoritative
  reconciliation.
- **ServerTimeTracker** - NTP-like clock sync between client and
  server. Server frame timing is based on physics ticks, with
  periodic wall-clock re-sync for accurate logging.
- **NetworkConnector** - ENet/WebSocket/WebRTC peer management
  (default port 4433).

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

The Nakama matchmaker takes an `is_web` player attribute for
platform-preference matching (relaxes after the configured
backoff). The runtime hook then chooses `transport_type`
(`"enet"`, `"webrtc"`, or `"websocket"`) based on which
platforms made it into the match, and includes it in the
match-ready payload pushed to clients.

- Client sets `Netcode.settings.transport_type` from the
  match-ready payload before connecting.
- Server reads matchmaker data from Edgegap's deployment
  context and sets transport on session-start. Only switches
  away from ENet if a web client is in the match — ENet-only
  matches stay on ENet.
- Edgegap returns the public IP at allocation time; the
  runtime derives the `s-{ip}.game.hopnbop.net` hostname
  (DNS pre-warmed by the container's entrypoint).
- Web clients connect via `wss://hostname:Port+1` (through
  nginx TLS termination on the container).
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

### Web Build Parse Errors — DO NOT chase with `.get()` rewrites

Web exports sometimes fail at boot with cascading parse errors
of this shape:

```
ERROR: Cannot get class ''.
   at: _instantiate_internal (core/object/class_db.cpp:587)
ERROR: Parameter "obj" is null.
   at: ensure_resource_ref_override_for_outer_load
       (core/io/resource_loader.cpp:1013)
SCRIPT ERROR: Parse Error: Could not resolve external class
member "settings".
   at: GDScript::reload (res://src/.../foo.gd:42)
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
ERROR: Failed to load script "res://src/.../bar.gd"
  with error "Compilation failed".
```

**The parse errors at the bottom are symptoms. The root cause
is the `Cannot get class ''` / `Parameter "obj" is null` block
at the very top of the boot log.** Every `Could not resolve
external class member "settings"` parse error downstream is a
consequence of `settings.tres` (or some other class-typed
resource) failing to load, which makes
`var settings: Settings = preload(...)` fail at parse time,
which makes every `G.settings.X` access fail.

**DO NOT "fix" these by rewriting `G.settings.X` to
`G.get("settings").get("X")`**. That destroys autocomplete,
intellisense, and static type checking project-wide and does
*not* address the root cause. We need typed GDScript; treat
the `.get()` pattern as an atrocity, not a fix.

The original "cyclic reference" framing (which used to live in
this section) was a misdiagnosis. The Godot 4.7-beta1 parser
DOES emit a real `Cyclic reference.` suffix when it detects an
actual class-resolution cycle — but that's a *different* error
than the bare `Could not resolve external class member`
messages we usually see. If the message says ``: Cyclic
reference.`` literally at the end, treat it as cyclic; if it
doesn't, look upstream for the `Cannot get class ''` block.

#### Real causes seen so far

- **Stale GDExtension declaration.** `addons/X/X.gdextension`
  declares native libraries for desktop platforms but no
  `web.wasm32`, and `extensions_support=false` on the Web
  preset. On web load, Godot tries to instantiate the missing
  extension's classes from cached resource refs and emits the
  `Cannot get class ''` cascade. Fix: either remove the addon
  entirely (if it's no longer used — see the gamelift removal
  in commit `0b9b059`) or add an `exclude_filter` line for
  the addon directory in the Web preset of
  `export_presets.cfg` (see the webrtc exclude added in
  2026-05-04 — webrtc's classes are provided natively by the
  browser at runtime, so the GDExtension binaries shouldn't
  ship to web at all).
- **Stale `.godot/global_script_class_cache.cfg`.** A
  `class_name` was renamed or removed but the cache still
  carries the old entry; resource files referencing the old
  name fail with `Cannot get class ''`. Fix: close the editor,
  delete `.godot/global_script_class_cache.cfg`, reopen, let
  Godot rebuild. (Done in 2026-05-03 for the gamelift_session_
  manager registry leak.)
- **Resource file with broken script ref.** A `.tres` or
  `.tscn` `[ext_resource type="Script" ...]` block points at
  a UID/path whose script no longer registers the same
  `class_name`. Fix the resource file or the script.

#### Investigation playbook

1. **Read the web log top-down, not bottom-up.** Find the
   *first* error in boot output. If it's `Cannot get class ''`
   at `_instantiate_internal`, that's your root cause — every
   `Could not resolve external class member` parse error
   below it is downstream noise.
2. Identify what class is being looked up empty. The wasm
   stack frames don't give source line info, so work backward
   from clues: which `[ext_resource]` or `[node type="..."]`
   in recently-changed `.tres`/`.tscn` files might reference a
   class that disappeared, was renamed, or comes from a
   GDExtension that isn't shipped on web.
3. Check for stale GDExtension declarations (`grep -r
   gdextension addons/`) and verify each is either web-
   compatible or excluded from the Web export preset.
4. If nothing in source/resources is suspicious, the cache is
   stale: regenerate `.godot/global_script_class_cache.cfg`.
5. Only after the upstream cascade is gone should you treat
   any remaining parse errors as real. They'll generally
   either disappear with the upstream fix or point at a real
   bug (e.g., a syntax error you can fix without touching the
   typed access pattern).

Desktop builds tolerate a lot more breakage than web does, so
"works in editor" is no signal. Always read the web boot log.

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

## Backend Testing

The AWS SAM Lambda backend was decommissioned 2026-05-03 along
with its pytest+moto suite. Server-side logic now lives in the
Nakama runtime plugin at
`third_party/snoringcat-platform/runtime/`. For testing patterns
there see the snoringcat-platform repo's CI workflows and the
in-tree GUT compliance suite for the client SDK.

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
