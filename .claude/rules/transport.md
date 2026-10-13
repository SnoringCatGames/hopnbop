---
paths:
  - "addons/rollback_netcode/**"
  - "addons/webrtc/**"
  - "third_party/snoringcat-platform/runtime/**"
  - "third_party/snoringcat-platform/infra/remote/signaling-proxy/**"
  - "src/core/game_session_manager.gd"
  - "src/core/nakama_matchmaker_client.gd"
---

# Transport lore

ENet/WebRTC/WebSocket transport detail, the signaling proxy, and the
end-to-end matchmaking flow, moved verbatim from CLAUDE.md by H34
(2026-10-13). CLAUDE.md keeps the three-mode summary.

## Transport architecture

Three transport modes, selected per-match by the backend
based on matched players' platforms:

- **ENet** (native-only matches): UDP on container port
  4433. Default. Lowest latency.
- **WebRTC** (cross-play matches with web players): UDP
  DataChannels via `webrtc-native` GDExtension. Signaling
  is a brief WebSocket through the Caddy-fronted
  `signaling.snoringcat.games` proxy. Provides UDP-like
  semantics in the browser, avoiding TCP head-of-line
  blocking.
- **WebSocket** (legacy, not currently used): TCP through
  the same signaling proxy path. Too slow for competitive
  play due to TCP head-of-line blocking (~100ms ping, 13-25%
  perceived packet loss).

**Transport selection flow:**
1. Nakama matchmaker takes a `platform` string player
   attribute (`"web"`, `"windows"`, `"linux"`, `"macos"`,
   `"android"`, `"ios"`), used for platform-preference
   matching (relaxes after the configured backoff).
2. The runtime's `matchmaker_matched` hook reads `platform`
   from each matched player's properties, calls
   `selectTransportType(platforms)` in `transport_select.go`,
   and sets `transport_type` in the match-ready payload it
   pushes to clients (`"enet"`, `"webrtc"`, or `"websocket"`).
3. Client sets `Netcode.settings.transport_type` from the
   match-ready payload before connecting.
4. Server reads matchmaker data on session-start and sets
   transport. Only switches away from ENet if a web player
   is in the match — ENet-only matches stay on ENet.

Local/preview bypasses the proxy and connects directly
to `ws://server_ip:server_port`.

## WebRTC architecture

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
1. Client connects to the signed `signaling_url` from the
   match_ready payload — a
   `wss://signaling.snoringcat.games/connect/<token>` URL
   where `<token>` is a base64url-encoded
   `<deploy-ip>:<tcp-port>:<expiry>:<hmac>` blob the runtime
   signed with `SIGNALING_HMAC_SECRET`. Caddy terminates TLS;
   the stateless signaling-proxy decodes the token, verifies
   the HMAC, and opens a plain-WS upstream to the encoded
   `(ip, tcp-port)` pair, then bridges frames bidirectionally.
   Token TTL is 5 min.
2. Client creates `WebRTCPeerConnection`, emits
   `peer_created` → `WebRTCGamePeer.add_peer()` creates
   negotiated DataChannels.
3. Client creates SDP offer, sends via signaling WS.
4. Server creates `WebRTCPeerConnection` with
   `portRangeBegin/End=4433` and `enableIceUdpMux=true`.
   Emits `peer_signaled` → `WebRTCGamePeer.add_peer()`
   creates matching DataChannels.
5. Server sets remote description (client's offer),
   generates SDP answer, sends via signaling WS.
6. ICE candidates exchanged bidirectionally via signaling
   WS. Server rewrites srflx candidate port from container
   4433 to the Edgegap UDP host port (looked up from
   `ARBITRIUM_PORT_GAME_EXTERNAL`).
7. ICE connects (UDP on host port), DataChannels open.
8. Signaling WS is closed.

**GDExtension:** `addons/webrtc/` provides
`webrtc-native` (v1.0.9) which implements
`WebRTCPeerConnection` using libdatachannel (with
libjuice for ICE) for native builds. Web builds use
the browser's native WebRTC API (no GDExtension
needed). The server uses a patched build in the
Docker image (the stock v1.0.9 ignores
`portRangeBegin`/`portRangeEnd`; see the WebRTC ICE
entry in `docs/history.md`).

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
clients must connect to the Edgegap UDP host port (e.g.,
4205). The signaling server rewrites the srflx candidate's
port before sending it to the client. The host port is read
from `ARBITRIUM_PORT_GAME_EXTERNAL` (Edgegap injects this
env at deploy time, alongside `ARBITRIUM_PUBLIC_IP`).

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

## WebRTC signaling proxy

```
Web/native client --wss://signaling.snoringcat.games/connect/<token>--> Caddy (TLS terminate) --> signaling-proxy --(plain WS)--> Godot signaling (deploy-ip:4434/TCP)
ENet-only match  --enet://ip:{UDP-port}/UDP--> Godot (unchanged, direct to Edgegap deploy)
WebRTC data plane --UDP DataChannels--> Godot (deploy-ip:{UDP-port}/UDP, after ICE)
```

The stateless `signaling-proxy` (Go, sibling docker-compose
service on the Hetzner host) puts a stable, always-resolvable
FQDN in front of dynamic Edgegap deploys. Caddy terminates
TLS once for the whole signaling tier; the proxy validates
the URL token then opens a plain-WS upstream to the encoded
`(deploy-ip, 4434/TCP)` pair and bridges frames.

**Why a stable FQDN proxy** (vs the previous per-deploy
`s-<ip>.game.hopnbop.net` + per-container nginx + wildcard
cert): home-router/ISP DNS resolvers often cache NXDOMAIN
for a hostname created seconds before the client tries to
resolve it, then keep serving NXDOMAIN until the negative-
cache TTL expires — clients saw "DNS name does not exist"
and the WebSocket failed in <50 ms with no chance to
handshake. The stateless proxy removes per-deploy DNS from
the connect path entirely. See
`third_party/snoringcat-platform/infra/remote/signaling-
proxy/main.go` for the protocol.

**Signed URL token:** The runtime hook's `signSignalingURL`
builds the URL with `base64url(<ip>:<tcp-port>:<expiry>:<
hmac-sha256>)`, signed with `SIGNALING_HMAC_SECRET` (shared
with the proxy's `SIGNALING_HMAC_SECRET` env). TTL is
5 minutes — generous enough for retries, short enough that
a leaked URL is useless quickly. No registration step, no
shared in-memory state between Nakama and the proxy; the
token IS the state.

**WebSocket buffer sizes:** Both client and server set
`inbound_buffer_size` and `outbound_buffer_size` to 1MB
(default 64KB) and `max_queued_packets` to 16384 (default
2048). The default buffer overflows within seconds on web
clients during 4-player matches.

**Container ports:** Edgegap allocates one host port per
declared container port (independent UDP and TCP host port
maps). The runtime hook reads both from Edgegap's deployment
status:

- `4433/UDP` (ENet payload + WebRTC DataChannel data
  plane) — host UDP port returned to ENet clients as
  `server_port`; the WebRTC ICE agent advertises this same
  port via the rewritten srflx candidate.
- `4434/TCP` (Godot's plain-WS signaling server) — host
  TCP port included in the signed signaling URL token;
  never exposed to clients directly.

The runtime hook picks the TCP port via `pickTCPPort
(status.Ports)`; no positional `Port+1` assumption.

## Godot native WSS limitation (2026-03-17, status unverified in current arch)

Godot 4.5's native `WebSocketMultiplayerPeer` historically
could not establish `wss://` to remote servers (every TLS
config tested failed instantly, not on timeout). Browser
`wss://` worked fine. Related Godot issues:
[#34083](https://github.com/godotengine/godot/issues/34083),
[#95217](https://github.com/godotengine/godot/issues/95217).

Previous workaround: native clients connected to plain
`ws://` through an in-container nginx `ssl_preread`
pass-through. That nginx path no longer exists — all
signaling now goes through `wss://signaling.snoringcat.
games`. The native WSS path is therefore on a Caddy-
managed Let's Encrypt cert (not a self-signed/mismatched
one), which may sidestep the original failure mode (the
2026-03-17 testing was against a custom TLS endpoint).
**Status unverified for native+web cross-play under the
current arch.** Native-only matches use ENet (no
signaling), so the question only matters when a web
player joins a cross-play match with native peers.

## End-to-end matchmaking flow

1. Client authenticates with Nakama (anonymous device-id or
   linked OAuth provider) and gets a session token.
2. Client adds itself to the matchmaker via the Nakama socket
   API with platform attributes (e.g. `platform: "web"` or
   `platform: "windows"`).
3. Nakama matches players and fires the `matchmaker_matched`
   hook in the runtime plugin.
4. The hook calls Edgegap to deploy a `hopnbop-server`
   container near the matched players, then notifies all
   matched clients with the connection payload:
   `server_ip`, `ports` (Edgegap port map),
   `transport_type`, `signaling_url` (signed
   `wss://signaling.snoringcat.games/connect/<token>` for
   non-ENet transports), per-player `session_ids`.
5. Client connects to the server:
   - ENet match: `enet://server_ip:UDP-port` (UDP, direct
     to the Edgegap deploy).
   - WebRTC match: connects to `signaling_url` for the
     brief SDP/ICE exchange, then UDP DataChannels direct
     to the deploy.
   - WebSocket match: connects to `signaling_url` for the
     full game stream (TCP, bridged plain-WS through the
     signaling proxy).
6. Server validates the per-player session ticket against the
   match-ready payload Nakama sent it during allocation.

The Edgegap allocation typically completes in a few seconds.
There is no longer a 29-second API-Gateway timeout to dance
around — the realtime socket pushes the allocation result
when ready, no client polling.

## Known issues (live)

### Web client WebSocket buffer overflow (2026-03-17)

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

### WebSocket cross-play latency (2026-03-17)

Desktop clients in WebSocket cross-play matches see
~100ms ping and 13-25% perceived packet loss, compared
to ~25ms ping and 0% loss with ENet-only matches. This
is inherent to TCP vs UDP: WebSocket over TCP has
head-of-line blocking (a single lost packet stalls the
entire stream until retransmitted). The "packet loss" in
PERF stats measures late/missed frame updates, not actual
TCP drops. Gameplay is playable but noticeably less smooth
than ENet.
