# WebRTC Cross-Play Debug Session Context

Date: 2026-04-02 through 2026-04-06

## Problem

WebRTC cross-play matchmaking fails. Desktop-to-desktop
(ENet) works. When a web client is in the match, FlexMatch
selects WebRTC transport. WebRTC signaling (SDP
offer/answer) succeeds, but ICE connectivity checks fail
and DataChannels never open. All 5 retry attempts time out.

## Key Discovery: Server ICE Candidates Use Unreachable Ports

With the new logging deployed (2026-04-06), we confirmed:

**Server sends 2 ICE candidates to each client:**
```
remote ICE candidate: candidate:1 1 UDP 2122317823 172.17.0.5 38335 typ host
remote ICE candidate: candidate:2 1 UDP 1686109951 35.91.191.229 38335 typ srflx
```

- `172.17.0.5:38335` = Docker internal IP (unreachable
  from internet)
- `35.91.191.229:38335` = correct public IP, but port
  38335 is an **ephemeral port** picked by libdatachannel's
  ICE agent

**GameLift container port mapping only exposes:**
- 4433/UDP (ENet)
- 4434/TCP (nginx/WSS)

Port 38335 is NOT forwarded. The client tries to reach
`35.91.191.229:38335` but packets never arrive at the
container.

## Contradiction: This Used to Work on 4/2

On 2026-04-02, WebRTC ICE connected successfully on the
same GameLift fleet (same server IP 35.91.191.229). The
code was identical (version 0.18.0). The signaling server
code has NOT changed between 0.18.0 and 0.20.0.

On 4/2, ICE completed in ~250ms:
```
[67.029] WebRTC: created offer
[67.071] WebRTC: received answer from server
[67.319] WebRTCGamePeer: peer 1 channels open
```

We did not have remote ICE candidate logging on 4/2, so
we cannot see what candidates the server sent then. The
server code used the same `initialize()` config with no
port constraints, so it would have used ephemeral ports
then too.

**Possible explanations for why it worked before:**
1. GameLift container networking previously allowed
   ephemeral UDP outbound/inbound and changed since
2. The 4/2 server was running on a different container
   instance with different networking behavior
3. The 4/2 deploy never actually had the WebRTC code
   (user confirmed deploys didn't work before 4/6)

User confirmed the 4/2 deploys "didn't actually work
last time" and only actually deployed on 4/6. This means
the 4/2 test ran against an OLD server build. The WebRTC
code on that old server may have been different (perhaps
an earlier version that used WebSocket transport instead
of WebRTC, or a version where ICE ports happened to work).

## Current Investigation State

We were analyzing WHY `_poll()` on `WebRTCGamePeer` might
not be keeping the ICE agent running. The server's
`_handle_offer` in `WebRTCSignalingServer` does:

1. Creates `WebRTCPeerConnection`
2. Connects ICE/session signals
3. Calls `rtc.initialize()` with STUN config
4. **Emits `peer_signaled`** -> `WebRTCGamePeer.add_peer()`
   creates DataChannels
5. Sets `_ws_signaled[ws_index] = true` -> signaling
   server STOPS polling this RTC
6. Calls `rtc.set_remote_description("offer", sdp)` ->
   triggers SDP answer + ICE gathering

After step 5, only `WebRTCGamePeer._poll()` polls the
RTC (called by Godot's SceneMultiplayer each frame via
`MultiplayerPeerExtension`). The ICE candidate callback
(`_on_server_ice_candidate`) fires and successfully sends
candidates through the signaling WebSocket (confirmed by
client logs receiving them).

The actual failure is at the **UDP connectivity level**:
the server's ICE agent binds to ephemeral UDP ports that
GameLift doesn't forward.

## Fix Approach: Pin Server ICE Port to 4433

The `webrtc-native` GDExtension uses libdatachannel
(with libjuice for ICE). The `initialize()` config
dictionary supports `portRangeBegin` and `portRangeEnd`
to constrain the UDP port.

**Current change in webrtc_signaling_server.gd:**
```gdscript
var server_port: int = Netcode.server_port
var init_err := rtc.initialize({
    "iceServers": [
        {"urls": ["stun:stun.l.google.com:19302"]},
    ],
    "portRangeBegin": server_port,
    "portRangeEnd": server_port,
})
```

**Concern:** In WebRTC mode, ENet is shut down (the
multiplayer peer is replaced at
`network_connector.gd:891`), so 4433/UDP should be free.
BUT if multiple clients connect (e.g., 2 players in a
cross-play match), each gets their own
`WebRTCPeerConnection`. The second one can't also bind
to 4433.

**Counter-argument:** This might actually work because
libjuice may use SO_REUSEPORT or similar. Or it might
not. Needs testing.

**Alternative approaches discussed:**
- **Add more UDP ports** to container group definition
  (4435-4438). Increases ports per session, reduces max
  sessions per instance.
- **Native clients stay on ENet** in cross-play matches,
  only web client uses WebRTC. Server runs both
  listeners. Bigger architectural change.
- Neither was chosen yet. User wants to understand the
  root cause first.

## Files Modified in This Session

### Logging additions:
- `addons/rollback_netcode/core/webrtc_signaling_client.gd`
  Line ~317: Added "WebRTC: remote ICE candidate" log in
  `_handle_server_ice()`

- `addons/rollback_netcode/core/webrtc_signaling_server.gd`
  `_on_server_ice_candidate()`: Added logging for sent
  candidates and warnings for dropped candidates (WS
  closed or invalid index)
  `_handle_client_ice()`: Added logging for received
  client ICE candidates

### Fix attempt (in progress):
- `addons/rollback_netcode/core/webrtc_signaling_server.gd`
  `_handle_offer()`: Added `portRangeBegin`/`portRangeEnd`
  set to `Netcode.server_port` (4433) in the
  `rtc.initialize()` config. NOT YET TESTED.

### Bug fix:
- `src/ui/screens/loading_screen.gd`
  `_process()`: Added elapsed time increment so the
  loading screen timer continues updating after
  matchmaking polling stops (when match is found but
  connection is pending).

### Documentation:
- `CLAUDE.md`: Added "Transport Architecture" section
  documenting WebRTC signaling flow, components,
  GDExtension, physics tick rate, and known issue.
  Updated matchmaking flow and NetworkConnector
  description.

- `DISTRIBUTED_SYSTEMS_PLAN.md`: Updated M10 section
  from planned to implemented status. Updated decision
  table and server transport section.

## Key Files for WebRTC

- `addons/rollback_netcode/core/network_connector.gd` -
  Transport selection, `_server_start_webrtc()`,
  `_client_start_webrtc()`
- `addons/rollback_netcode/core/webrtc_game_peer.gd` -
  Custom MultiplayerPeerExtension with 2 DataChannels
- `addons/rollback_netcode/core/webrtc_signaling_server.gd` -
  Server-side signaling WS + ICE relay
- `addons/rollback_netcode/core/webrtc_signaling_client.gd` -
  Client-side signaling with retry logic
- `addons/gamelift_session_manager/server/gamelift_server.gd` -
  `_set_transport_from_matchmaker()` selects transport,
  `_on_game_session_started()` restarts server listener
- `addons/gamelift_session_manager/client/gamelift_client.gd` -
  `_handle_match_found()` sets client transport from
  backend response
- `backend/src/services/gamelift_service.py` -
  `_determine_transport()` reads `is_web` from
  matchmaker data
- `backend/src/handlers/matchmaking_handler.py` -
  `_resolve_server_address()` returns hostname + WSS
  port for WebRTC/WebSocket matches
- `gamelift-deploy/container-group-definition.json` -
  Container ports (4433/UDP, 4434/TCP)
- `gamelift-deploy/nginx.conf` - TLS detection +
  passthrough on port 4434

## Server Signaling Flow (Detailed)

When a WebRTC match starts:

1. `gamelift_server.gd:_on_game_session_started()` sets
   `transport_type = WEBRTC` from matchmaker data
2. Calls `Netcode.connector.server_enable_connections()`
3. `network_connector.gd:_server_start_webrtc()`:
   - Creates `WebRTCSignalingServer` on port 4433 TCP
   - Creates `WebRTCGamePeer` in server mode
   - Sets `multiplayer.multiplayer_peer = _webrtc_peer`
   - Connects `peer_signaled` signal
4. Client connects to signaling WS (through nginx on
   4434 -> proxied to 4433)
5. Client sends SDP offer with its peer_id
6. `webrtc_signaling_server.gd:_handle_offer()`:
   a. Creates `WebRTCPeerConnection`
   b. Connects ICE/session signals
   c. `rtc.initialize()` with STUN config
   d. Emits `peer_signaled` -> `WebRTCGamePeer.add_peer()`
      creates 2 negotiated DataChannels
   e. Sets `_ws_signaled = true` (stops RTC polling
      in signaling server)
   f. `rtc.set_remote_description("offer", sdp)` ->
      triggers answer generation + ICE gathering
7. `_on_session_description("answer")` sends SDP answer
   to client via signaling WS
8. `_on_server_ice_candidate()` sends server ICE
   candidates to client via signaling WS
9. Client ICE candidates arrive via signaling WS,
   forwarded to server's RTC via `_handle_client_ice()`
10. ICE connectivity checks happen over UDP
11. When ICE connects, DataChannels open
12. `WebRTCGamePeer._poll()` detects open channels,
    emits `peer_connected`
13. Signaling WS is closed

**Step 10 is where it fails.** The server's UDP port
is ephemeral and not forwarded by GameLift.

## Client Signaling Flow

1. Backend returns match with `transport: webrtc`,
   `server: hostname:Port+1` (nginx port)
2. `gamelift_client.gd:_handle_match_found()` sets
   `transport_type = WEBRTC`
3. `game_session_manager.gd:_on_session_ids_received()`
   calls `Netcode.connector.client_connect_to_server()`
4. `network_connector.gd:_client_start_webrtc()`:
   - Creates `WebRTCSignalingClient`
   - Generates temp peer_id from timestamp
   - Connects `peer_created`, `completed`, `failed`
5. `webrtc_signaling_client.gd:_attempt_connect()`:
   - Opens WebSocket to signaling server
   - On WS open: creates `WebRTCPeerConnection`,
     `initialize()` with STUN, emits `peer_created`
     -> `WebRTCGamePeer.add_peer()` creates
     DataChannels, then `create_offer()`
   - Sends offer via WS
   - Receives answer, sets remote description
   - ICE candidates exchanged via WS
   - Checks `_rtc.get_connection_state() == CONNECTED`
     each frame
   - 10s timeout per attempt, 5 attempts max

## What to Deploy

- **GameLift server**: Required for server-side changes
  (logging + port fix)
- **Website**: Required for web client testing (currently
  deployed at stale 0.17.0 with script compilation
  errors)
- **Backend**: Not needed (no backend changes)

## Next Steps

1. Verify whether `portRangeBegin`/`portRangeEnd` is
   actually supported by the installed webrtc-native
   version. If the extension ignores unknown config
   keys, the fix silently does nothing.
2. Test the port pin fix. If it works for 1 client,
   test with 2 WebRTC clients to see if the second
   PeerConnection can also bind to 4433.
3. If port pinning doesn't work or doesn't support
   multiple clients, consider adding more UDP ports
   to the container group definition.
4. Check CloudWatch server logs for the failed test to
   see if the server-side ICE logging shows the
   candidates being sent (confirms the logging deploy
   worked).

## Earlier Issues (Resolved)

### RPC Argument Mismatch (fixed before this session)
`auth_display_name` parameter was added to
`_server_rpc_declare_players` RPC. Client sent 6 args,
deployed server expected 5. Godot silently drops the
RPC. Fixed by redeploying server.

### Web Build Stale (0.17.0)
The website was still serving version 0.17.0 with script
compilation errors (`"Could not resolve external class
member 'settings'"` in scaffolder_log.gd, cheat_manager.gd,
cricket.gd, snail.gd). These errors are NOT caused by
`class_name G` being commented out (user confirmed
autoloads can't have class_name). The errors are likely
from the web export's strict bytecode compilation on an
old codebase version. Fix: redeploy website with current
0.20.0 code.

### Loading Screen Timer Stuck (fixed this session)
The loading screen stopped updating elapsed/remaining
time when the matchmaking poll stopped (match found).
Fixed by incrementing `_matchmaking_elapsed_sec` in
`_process()` independently of the poll signal.
