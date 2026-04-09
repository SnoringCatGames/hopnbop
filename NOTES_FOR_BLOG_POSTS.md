# Notes for blog posts

# FIXME: LEFT OFF HERE: ----------

# VERY CLEARLY describe my approach to AI in this game
# - Include this call-out at the top of each post (and/or maybe make a separate post detailing this and link to it from the blurb, which has a condensed summary).
# - I wrote the original (robust) client/server rollback netcode implementation with no AI assistance.
# - I later added the _entire_ backend, most of the current UI, and various bells and whistles with AI assistance.
# - I also wrote the original tileset-based level art with no AI assistance.
# - I wrote all animations with no AI assistance.
# - I used Stable Diffusion with ControlNet to generate the foundations of my level art. I then adjusted this by hand.

## Post: Stable Diffusion for 2D platformer art

- Briefly experimented with Stable Diffusion.
  - Completely garbage results at following specific level geometry.
  - So, completely unusable for my purposes.
- PixelLab performed just as poorly.

## Post: The Netcode rollback plugin

-

## Post: AWS GameLift and GDExtension

- Why I chose this architecture.

## Claude Code for hands-free distributed systems with AWS

- I _always_ use `--dangerously-skip-permissions` now for the Claude code session that's handling backend changes.
- Otherwise, Claude needs too many interruptions for permissions to check-on or execute things on the backend or server. And I've _never_ seen a time where I'd want to say no.


## Post: WebRTC DataChannel Transport for Web Cross-Play

### The WebSocket cross-play experience
- Buffer overflow errors within seconds of 4-player web matches (default 64KB buffers)
- Increased buffers to 1MB, extended headroom to ~7-30 seconds before overflow
- Send rate throttling (20 Hz for WebSocket vs 30 Hz for ENet) eliminated overflow
- But TCP head-of-line blocking remained: ~100ms ping vs ~25ms for ENet, 13-25% perceived packet loss
- Ping ramped from 89ms to 356ms over the match duration
- The fundamental problem: TCP's reliable ordered delivery guarantees are wrong for real-time game state

### Send rate throttling as mitigation
- Reduced server state replication from 60 Hz to 20 Hz for WebSocket peers
- Eliminated buffer overflow but couldn't fix head-of-line blocking
- Gameplay was never playable on WebSocket at any send rate due to TCP head-of-line blocking

### The decision to adopt WebRTC DataChannels
- WebRTC DataChannels with unreliable/unordered mode provide UDP-like semantics in browsers
- Only way to get unreliable transport in the browser (WebTransport has limited support)
- Expected result: web clients get network characteristics similar to native ENet (~25ms ping, ~0% loss)

### Architecture comparison
- WebSocket: client -> wss:// -> nginx TLS -> Godot WS server (TCP, head-of-line blocking)
- WebRTC: client -> DTLS/UDP -> Godot WebRTC DataChannel (unreliable, no blocking)
- Signaling: brief WebSocket through existing nginx path for SDP/ICE exchange (~1-2s)
- Star topology (server_compatibility_mode): no mesh, plugs into existing multiplayer API

### The DTLS bug story (v1.0.9 vs v1.1.0)
- webrtc-native v1.1.0 has a DTLS handshake bug with Firefox
- mbedTLS (v1.1.0) lacks ClientHello defragmentation (GitHub issue #180)
- v1.0.9 uses OpenSSL, which handles this correctly
- Occasional Firefox failures on first attempt handled with automatic retry (5 attempts)
- Lesson: always test specific plugin versions against all target browsers

### Lessons learned about Godot's networking stack
- Godot's WebRTCMultiplayerPeer with create_server() works in star topology
- Web exports have native WebRTC (browser API), only server needs GDExtension
- No STUN/TURN needed for client-to-server when server has known public IP
- Rollback plan: change backend to return "websocket" instead of "webrtc"

### WebRTCMultiplayerPeer performance failure
- WebRTCMultiplayerPeer creates 6-8 SCTP streams (3 reserved + extras per channel config)
- All streams share one SCTP congestion window per association
- SCTP congestion control throttles even "unreliable" streams
- Small game packets (~100 bytes) don't trigger PMTUD, keeping congestion window constrained
- Result: web client R:2.3 FPS, PING:259ms, LOSS:95%. Desktop LOSS:15-52%
- Packets arrive in bursts causing fast-forward cascades in rollback netcode
- Root cause is not WebRTC itself but WebRTCMultiplayerPeer's SCTP stream design

### Custom MultiplayerPeerExtension approach
- Godot 4.5 has MultiplayerPeerExtension: GDScript-extensible base for custom MultiplayerPeer
- WebRTCGamePeer: 2 negotiated DataChannels (reliable + unreliable) instead of 8 SCTP streams
- Reliable channel: negotiated=true, id=1, ordered=true
- Unreliable channel: negotiated=true, id=2, ordered=false, maxRetransmits=0
- Fewer SCTP streams = less congestion window contention
- True fire-and-forget on unreliable channel (no head-of-line blocking for state sync)
- No double-polling (custom peer owns WebRTCPeerConnection polling entirely)
- 1-byte channel header per packet preserves Godot's transfer_channel routing
- SceneMultiplayer handles relay (is_server_relay_supported = false)
- Desktop performance: excellent (58-60 R FPS, 25-30ms ping, 0-28% loss)
- Web performance: still degrades over match duration (R FPS drops from 47 to 4)

### Failed optimization: PMTUD packet padding
- Theory: small game packets (~100 bytes) don't trigger SCTP PMTUD, keeping
  the congestion window constrained. Padding packets to 1200 bytes (near MTU)
  would force SCTP to discover real path capacity and open the window wider.
- Implementation: padded unreliable packets to 1200 bytes with a 3-byte header
  (channel + payload length for stripping padding on receive)
- Result: made things WORSE. SCTP congestion window is measured in bytes, not
  packets. Padding to 1200 bytes means each packet consumes 12x more of the
  congestion window. Fewer packets fit in flight before SCTP throttles.
  Same packet rate but 12x the bandwidth = faster congestion.
- Reverted immediately

### Root cause: per-synchronizer packet overhead
- Godot's MultiplayerSynchronizer sends one packet per node per tick
- With 4 players: 9+ synchronizer nodes × 10 Hz = 90+ packets/sec aggregate
- Each packet is a separate SCTP packet with its own overhead
- Browser SCTP congestion control throttles at this packet rate regardless
  of individual packet size
- Potential fix: bypass MultiplayerSynchronizer, bundle all state updates
  into a single packet per tick (10 packets/sec instead of 90+)

### WebRTC performance rule of thumb
- Combine all per-frame (always-send) synchronizers across the entire app
  into a single consolidated synchronizer that sends one bundled packet per
  tick. This is the single most impactful optimization for WebRTC performance.
- On-change synchronizers (kills, bumps, player list, match events) and
  reliable RPCs can stay separate. They fire infrequently and don't
  contribute to the per-frame packet flood that overwhelms SCTP congestion
  control.

### State bundler implementation learnings

- Custom `WebRTCGamePeer` (MultiplayerPeerExtension) must emit
  `peer_connected`/`peer_disconnected` signals AFTER draining all
  DataChannels, not during iteration. Emitting during iteration causes
  SceneMultiplayer to process the signal synchronously (sending
  PEER_CONFIG packets), but the second peer's packets haven't been
  drained yet. Use a two-pass approach: first pass polls and drains,
  second pass emits signals.

- `var_to_bytes`/`bytes_to_var` creates temporary Array objects on
  every call. In WASM's single-threaded runtime, these trigger GC
  pauses that directly cause render FPS drops. Raw byte packing
  (encode floats/ints directly into PackedByteArray using
  `StreamPeerBuffer` or `decode_float`/`decode_s32`) eliminates
  temporary allocations entirely. Decode directly into
  ArrayPool-acquired arrays for zero GC pressure.

- SAM deploy can silently hang when only environment variables change
  (code hash identical). The CloudFormation changeset is never created.
  Workaround: update Lambda env vars directly via
  `aws lambda update-function-configuration`.

- Godot headless export (`--export-pack`, `--export-release`) must run
  from the project directory and cannot run two instances in parallel
  on the same project. The second instance silently produces no output.

- GameLift container group definitions have a limit of 4 versions.
  Delete old versions before creating new ones.

- Deploy scripts (`.ps1`) and CLI tools like `sam` and `godot` are
  only in the PowerShell PATH on Windows, not the bash PATH.

### PERF metrics with bundling

- N (network FPS) counts per-`_handle_new_state_from_network` calls,
  not per-packet. With bundling at 20 Hz, each bundle dispatches
  multiple entity states, so N reads ~40 (2 states per entity × 20 Hz).

- LOSS of 66-67% is expected with 20 Hz sends at 60 fps sim rate.
  It measures missed frame updates, not actual packet drops.
  (60 - 20) / 60 = 66.7%.

### Frame sync destabilization at 30fps

- Switched WebRTC matches to 30fps physics (from 60fps) to reduce
  SCTP packet rate
- FF/s (fast-forwards per second) grew from 2.8 to 18.5 over a
  match, making gameplay progressively worse
- Root cause was three interacting bugs in the NTP-based frame
  synchronizer's drift correction

#### Bug 1: Catch-up ratchet via `maxi()`
- `fd._catchup_frames_remaining = maxi(fd._catchup_frames_remaining, drift)`
- Each pong could only INCREASE the catch-up counter, never decrease it
- If client is mid-catch-up and a new pong shows smaller drift, counter
  stays high, causing systematic overshoot past the server's frame

#### Bug 2: Asymmetric correction
- Client behind server: smooth gradual catch-up (1 extra frame per tick)
- Client ahead of server: destructive hard reset with 3-second cooldown
- When catch-up overshoots by a few frames, the only correction was a
  hard reset (clears rollback buffers, reinitializes state, resets frame
  index). But the 3-second cooldown blocks another reset, so client runs
  ahead for up to 3 seconds before snapping back. Then NTP detects client
  behind again, triggers catch-up, overshoots again. Repeat forever.

#### Bug 3: No catch-up cancellation on drift flip
- When drift crosses zero (client goes from behind to ahead),
  `_catchup_frames_remaining` was not cleared
- Catch-up continued even though client was already at or ahead of
  server, guaranteeing overshoot every time

#### The oscillation cycle
1. Client slightly behind -> gradual catch-up starts
2. `maxi()` ratchets counter to peak drift value
3. Client reaches server frame, but catch-up continues (no cancellation)
4. Client overshoots, now ahead by a few frames
5. Hard reset fires, snaps client back, clears buffers
6. 3-second cooldown prevents another reset
7. NTP detects client behind -> back to step 1

#### Why this didn't manifest at 60fps
- At 60fps, the drift correction granularity was finer (each extra
  frame = 16.7ms). Overshoot of 1-2 frames was within the jitter-aware
  threshold and got absorbed.
- At 30fps, each extra frame = 33.3ms. The same overshoot exceeds the
  threshold and triggers the hard reset path. The longer tick interval
  also means each catch-up step is a bigger jump.

#### Fix: 3 changes
1. Replace `maxi()` with direct assignment: each pong is the freshest
   drift measurement, use it directly
2. Add symmetric gradual slow-down: for small client-ahead drift
   (<=10 frames), skip physics ticks instead of hard reset. Mirrors
   the gradual catch-up. Hard reset stays for large drift.
3. Clear catch-up on drift flip: when a pong shows drift <= 0 within
   threshold, cancel `_catchup_frames_remaining` immediately

#### Results
- FF/s: 0.0 stable across entire match (was 2.8 -> 18.5)
- Zero hard resets during normal gameplay
- RB/s (rollbacks): ~4-11/s, expected with WebRTC latency
- PING: stable ~43-54ms (previously unstable due to oscillation)

### ICE port nightmare on GameLift container fleets

WebRTC worked perfectly in local testing and even on the
live fleet initially (March 29). Then it silently broke
after a fleet redeployment and stayed broken for a week.
SDP exchange succeeded every time, but ICE connectivity
checks timed out. The code hadn't changed.

#### The root cause was three problems stacked on top of each other

**Problem 1: Ephemeral ICE ports.**
The webrtc-native GDExtension v1.0.9 ignores
`portRangeBegin`/`portRangeEnd` in the `initialize()`
config dictionary. The underlying libdatachannel library
supports them, but the GDExtension's `_initialize()` C++
method only parses `iceServers`. The ICE agent binds to
an ephemeral UDP port (e.g., 38335). GameLift only
forwards declared container ports (4433/UDP, 4434/TCP).
Ephemeral ports are unreachable from the internet.

Fix: Patch the GDExtension at Docker build time. A
6-line C++ patch adds `portRangeBegin`, `portRangeEnd`,
and `enableIceUdpMux` parsing. The patched .so is
compiled from source in a Docker builder stage.

**Problem 2: Container port != host port.**
Even after pinning ICE to container port 4433, the
STUN-reflected (srflx) candidate advertised
`public_ip:4433`. But GameLift maps container port 4433
to a dynamic host port (e.g., 4205) from the
`InstanceConnectionPortRange` (4192-4211). Clients
trying to reach port 4433 are blocked because GameLift
uses port-preserving NAT for outbound STUN (the STUN
server sees source port 4433, not the host port).
Meanwhile, the inbound DNAT rule only forwards the
host port (4205) to the container.

Fix: The signaling server rewrites the srflx
candidate's port from the container port to the
GameLift host port before sending it to clients. The
host port is derived from the WSS port that the client
includes in its offer message (host_udp_port =
wss_port - 1). Also had to add port 4433/UDP to the
fleet's `InstanceInboundPermissions` for STUN return
traffic.

**Problem 3: libjuice mux mode not enabled.**
Each WebRTCPeerConnection creates its own libjuice ICE
agent. By default, libdatachannel v0.22.3 uses
`JUICE_CONCURRENCY_MODE_POLL`, which creates a separate
UDP socket per agent. The second PeerConnection fails
`set_remote_description` because it can't bind to port
4433 (already held by the first agent). Only the first
client connected. Setting `config.enableIceUdpMux = true`
switches to `JUICE_CONCURRENCY_MODE_MUX`, which creates
a shared UDP socket that demultiplexes STUN traffic by
username fragment. All clients then share port 4433.

#### Why it worked on March 29 and then stopped

Most likely: GameLift container networking previously
allowed ephemeral UDP outbound/inbound (possibly via
`--network host` or more permissive iptables). A fleet
redeployment between March 29 and April 6 triggered an
EC2 instance replacement or container agent update that
tightened networking. The security group only allows
4192-4211, but the March 29 test used ephemeral port
38335. The fleet config, container definition, and
application code were identical.

#### What NOT to do

- **Don't add more container ports.** Adding a third
  `ContainerPortRanges` entry (e.g., 4435-4437/UDP)
  caused GameLift to assign host ports beyond the
  `InstanceConnectionPortRange` (got port 4212 outside
  4192-4211). This broke the `Port+1` WSS offset that
  the backend relies on.

- **Don't rely on upstream webrtc-native supporting
  portRange.** As of v1.1.0 (May 2026) it still doesn't
  parse these config keys. Patch it yourself.

#### Debugging approach

- Node.js test client (using `node-datachannel`, same
  library as the GDExtension) to create real ICE
  connections from the CLI. Triggers matchmaking via
  API, connects to signaling WS, does full SDP/ICE
  exchange. This enabled testing without opening the
  game client.
- CloudWatch log analysis to correlate server-side ICE
  candidate generation with client-side failures.
- The `WebFetch` tool to read the webrtc-native
  GDExtension source on GitHub and find the missing
  `enableIceUdpMux` configuration.

