# History

What changed, when, and why — kept out of always-loaded context
(claude-config `rules/context-budget.md`). Never imported. Primary
history lives in commit messages; this file holds the narratives that
used to pad CLAUDE.md, started by H34 (2026-10-13). Deploy- and
transport-flavored stories that double as operating rules moved to
`.claude/rules/deploy.md` and `.claude/rules/transport.md` instead.

## Platform migration timeline

- **Phase F (2026-05-03):** migration from AWS GameLift to
  Nakama + Hetzner + Edgegap completed. All hopnbop-* GameLift /
  Lambda / S3 / CloudFront / Route 53 resources deleted; the orphan
  `snoringcat-platform-backend` SAM stack and the Pulumi-state S3
  bucket were cleaned up the next day. Zero AWS resources remain;
  Pulumi state migrated to Cloudflare R2. Archeology:
  `docs/archive/MIGRATION_PLAN.md` and
  `docs/archive/platform-pivot-discussion.md`.
- **Single-host consolidation (2026-05-06):** the original two CPX11
  (Nakama + separate Postgres + full Prometheus/Grafana/Loki/Promtail
  observability) collapsed into one CPX11 with Postgres co-tenanted
  alongside Nakama.
- **Stage 7.11 (2026-05-13):** a lightweight observability subset
  (Prometheus + Grafana + node-exporter + postgres-exporter)
  re-introduced on the single host; Loki + Promtail stayed off (logs
  remain on `journalctl` / `docker logs`).
- **CPX21 upsize (2026-06-01):** nakama-prod-1 upsized in-place from
  CPX11, ahead of the 2026-06-15 Hetzner price hike and to make room
  for cohabiting local game-server containers. The CLAUDE.md cost
  line said ~$8/mo until 2026-10-11, which was never right;
  ~$14.59/mo is the September 2026 actual.
- **AWS SAM Lambda backend decommissioned (2026-05-03)** along with
  its pytest+moto suite. Server-side logic lives in the Nakama
  runtime plugin at `third_party/snoringcat-platform/runtime/`.

## Resolved issues

**Server stuck on "Waiting for Players" (2026-03-11, resolved
2026-03-17):** Godot's WebSocket server rejects HTTP upgrade requests
with an `Origin` header (all browsers send one), and GameLift port
mapping is unpredictable with 3+ container ports. Fixed by using
nginx with `ssl_preread` for TLS detection on 2 container ports, with
Origin stripping in the TLS termination path. (The nginx path itself
was later replaced by the stateless signaling proxy; see
`.claude/rules/transport.md`.)

**Native clients cannot connect via WSS (2026-03-16, resolved
2026-03-17):** Godot 4.5's native mbedTLS-based WebSocket client
could not establish `wss://` connections to any remote server. Worked
around by having native clients use plain `ws://` through nginx's
pass-through path. Status under the current Caddy-fronted proxy is
unverified; see "Godot native WSS limitation" in
`.claude/rules/transport.md`.

**WebRTC ICE fails on GameLift (2026-04-02, resolved 2026-04-09):**
WebRTC cross-play stopped working after a fleet deployment. SDP
exchange succeeded but ICE connectivity checks timed out. Three root
causes:
1. The webrtc-native GDExtension v1.0.9 ignores
   `portRangeBegin`/`portRangeEnd` in `initialize()`, so the ICE
   agent bound to ephemeral UDP ports not forwarded by GameLift.
   Fixed by patching the GDExtension at Docker build time.
2. The STUN-reflected srflx candidate advertised the container port
   (4433) instead of the GameLift host port. Fixed by rewriting the
   candidate port in the signaling server before sending to clients.
3. Multiple PeerConnections could not share port 4433 because
   libjuice's mux mode was not enabled
   (`JUICE_CONCURRENCY_MODE_POLL` default). Fixed by adding
   `enableIceUdpMux: true` to the initialize config, which sets
   `JUICE_CONCURRENCY_MODE_MUX`. Also required adding port 4433/UDP
   to the fleet's `InstanceInboundPermissions` (GameLift uses
   port-preserving NAT for outbound STUN, so return traffic arrives
   on host port 4433).

**Buffer overflow on shutdown (2026-03-16, fixed):** Server did not
disconnect clients when cancelling a match (grace period expiry) or
during process termination with no active match. Client did not close
the WebSocket on receiving the shutdown notification. Both fixed in
`gamelift_server.gd`, `game_panel.gd`, and `network_connector.gd`.

## Incidents that shaped the commit policy

- **2026-08-16:** a web session copied hopnbop's harness-injected
  `claude/...` branch name onto `snoringcat-platform`, which had no
  stated branch policy of its own. Both repos now spell out that
  harness branch names are not requests for feature branches.
