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

- With PixelLab?

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
- Gameplay playable but noticeably less smooth than ENet

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
- WebRTCGamePeer: 3 negotiated DataChannels instead of 8 SCTP streams
- Reliable channel: negotiated=true, id=1, ordered=true
- Unreliable ordered channel: negotiated=true, id=2, ordered=true, maxRetransmits=0
- Unreliable channel: negotiated=true, id=3, ordered=false, maxRetransmits=0
- Fewer SCTP streams = less congestion window contention
- True fire-and-forget on unreliable channel (no head-of-line blocking for state sync)
- No double-polling (custom peer owns WebRTCPeerConnection polling entirely)
- 1-byte channel header per packet preserves Godot's transfer_channel routing
- SceneMultiplayer handles relay (is_server_relay_supported = false)
- Performance comparison: TBD after testing

