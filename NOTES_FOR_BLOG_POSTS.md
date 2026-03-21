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

