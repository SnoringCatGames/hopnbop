# Test architecture plan

Captured 2026-05-03. Covers four threads the user asked to plan:

1. Outstanding tasks accumulated this session.
2. Realtime-socket test rig (currently `pending()` in
   `test_matchmaking.gd`).
3. WebRTC cross-play state + fix list + regression test.
4. Long-game: extensible distributed test architecture for our
   networked games. Internet research is queued via a background
   agent and will land in section 4 when it returns.

---

## 1. Outstanding tasks from this session

Beyond the compliance tests (now landed across two parent commits
`43db749` + `da8a389` and submodule commits `ffd2c56` + `c023b82`),
the open items I'm aware of are:

- **`addons/gamelift_session_manager` global-class registry leak.**
  The directory was deleted in commit `0b9b059`, but
  `.godot/global_script_class_cache.cfg` still references
  `SessionProvider` / `LocalOnlySessionProvider` /
  `PreviewSessionProvider`. Headless runs spit cascading parse
  errors that block compilation of `src/core/settings.gd`,
  `src/level/lobby_level.gd`, `src/objects/settings_book.gd`.
  Fix: open the project in the editor (which rewrites the cache),
  or wipe `.godot/`. Doesn't affect the compliance suite (which
  runs anyway), but does affect any other GUT run + the editor.
- **NEXT_STEPS.md is stale** (snapshot from 2026-05-02). Of the
  open follow-ups listed there:
  - Phase F teardown: ✅ done (commit `4f8cfe3`).
  - `runtime_status` static RPC list: ✅ done (commit `63affdd`).
  - Bump `NAKAMA_GAME_VERSION=0.33.0`: status unknown — likely
    still 0.32.0 on the Hetzner host.
  - Edgegap stale image cleanup (`v2`–`v7`): unknown.
  - Cyclic-ref `.get()` rewrites for 4 files: still open per the
    May 1 list.
  - CLAUDE.md cleanup post-Phase-F: partial — file paths and the
    `addons/snoringcat_platform_client` symlink claim are stale
    (it's a copy via `scripts/setup-platform-addon.ps1`, not a
    symlink).
- **Email containing R2 API key** still in the user's inbox.
- **Laptop bootstrap** to pick up new skills + the
  weekly-cost-review job: user task.

A `/audit-followups` run would surface anything I'm missing here.

---

## 2. Realtime-socket test rig

### What we need it for

`test_matchmaking.gd::test_matchmaker_socket_flow_pending` is
explicitly pending because the full matchmaker flow runs over
Nakama's realtime socket (`wss://nakama.snoringcat.games/ws`),
not REST. Same blocker for chat, presence push, and party
join/invite events. Today's compliance suite is HTTP-only.

### Protocol shape (confirmed from desktop logs)

The socket is JSON-framed messages over WSS with `?token=<jwt>`
in the query string. Three things matter for tests:

1. **Connect**: `wss://<host>/ws?lang=en&status=false&token=<jwt>`.
   Token is the access JWT from
   `/v2/account/authenticate/device`. Server sends `cid`-tagged
   responses; client uses an envelope of the form
   `{cid, rpc:{id,payload}}` for RPC-over-socket and
   `{matchmaker_add:{...}}` etc. for typed messages.
2. **MatchmakerAdd** payload (from log):
   ```
   { query:"*", max_count:4, min_count:2,
     numeric_properties:{},
     string_properties:{ platform:"native", player_count:"3" },
     count_multiple:null }
   ```
3. **match_ready** notification arrives as a
   `notifications` envelope, content is a JSON-stringified blob
   inside another JSON-stringified blob (the runtime wraps it
   twice — see `nakama_matchmaker_client.gd:311–324`).

### Rig design

Two viable shapes; I'd build #1 first, escalate to #2 if needed:

**Shape A — In-Godot socket helper (lowest cost, ~half a day).**

Add a `compliance_socket_helper.gd` that wraps the existing
Nakama SDK's `Socket` (lives at `addons/nakama/`). Tests use it
directly:

```gdscript
var sock = await _socket_helper.connect_authed(token)
var ticket = await _socket_helper.matchmaker_add(
    sock, {"platform":"native","player_count":"1"})
var matched = await _socket_helper.wait_for_matched(
    sock, _MATCH_TIMEOUT)
```

This unblocks single-client realtime tests (matchmaker ticket
issuance, presence push, chat send/receive) without standing up
fake game servers. The matchmaker-end-to-end test is *almost*
possible here — we can confirm a player gets matched + receives
a `match_ready`, but we can't drive the resulting game-server
handshake from a single test process.

Tests this enables (would land as new compliance files):

- `test_socket_auth.gd` — connect with valid + invalid tokens,
  expect open + closed-with-error respectively.
- `test_socket_matchmaker.gd` — add a single ticket with
  `min_count=1`; assert ticket id returned. Cancel; assert
  removed. (Doesn't get all the way to match_ready, but covers
  the surface.)
- `test_socket_presence.gd` — confirm presence push messages
  arrive when a friend's status changes.
- `test_socket_chat.gd` — channel join, send, receive.

**Shape B — Multi-process rig (higher cost, ~2-3 days).**

Spin up N headless Godot client processes from the test
runner, point them at a real Nakama (or a docker-compose'd
local one), and observe the full flow including game-server
allocation and handshake.

This is what the user is hinting at with the "client driver /
mock system" question — it's the realtime-multi-client rig.
Section 4 covers the architectural choices around this.

### Recommended path

Build A first as part of the compliance suite (single-process,
single-client realtime probes). Use it to land the 4 tests
above. Reserve B for the next-tier integration suite that lives
outside the compliance bundle (because the cost is much higher).

---

## 3. WebRTC cross-play

### Current state (audit findings)

I read `addons/rollback_netcode/core/webrtc_signaling_*.gd`,
`Dockerfile.edgegap`, `third_party/snoringcat-platform/runtime/fleet_allocator.go`,
and `src/core/nakama_matchmaker_client.gd`. The picture:

**What's still in place (good):**
- `WebRTCSignalingClient` / `WebRTCSignalingServer` /
  `WebRTCGamePeer` live in `addons/rollback_netcode/core/` —
  extracted out of this repo into the shared submodule.
- `addons/webrtc/` has the GDExtension binaries for every
  platform.
- `Dockerfile.edgegap` exposes 4433/UDP + 4434/TCP and copies
  the patched `webrtc-native` libs into the container.
- A unit test exists at
  `addons/rollback_netcode/test/unit/test_webrtc_signaling.gd`.
- Client matchmaker sends a `platform: "web"|"native"`
  property.

**What's broken (the regression):**

`fleet_allocator.go::OnMatchmakerMatched` does NOT:

- Read `platform` (or `is_web`) from any matched player's
  properties.
- Choose a `transport_type` (`enet` / `webrtc` / `websocket`).
- Include `transport_type` in the `match_ready` connection
  payload.

The current connection blob is just
`{server_ip, server_fqdn, ports, request_id, session_ids}`. So
even when a web client successfully reaches the matchmaker, the
runtime never tells anyone to use WebRTC, and the allocated
container never gets a hint to start its signaling server.

Net effect: **WebRTC cross-play silently doesn't work
post-Phase-F.** Native-only matches still work because ENet is
the default. Web-included matches fail at handshake.

CLAUDE.md describes the intended `transport_type` behavior in
detail but the code never landed it through the migration. The
compliance test `test_matchmaking.gd::test_matchmaker_hook_registered_via_runtime_status`
passes because it only checks that `EDGEGAP_TOKEN` is set —
not that transport selection is wired.

### Fix list

Ordered by what unblocks what. **Status updated 2026-05-03:
plumbing-layer fixes shipped; deeper rollback_netcode change
remains.**

1. ✅ **Runtime: read `platform` and set `transport_type`.**
   `fleet_allocator.go::OnMatchmakerMatched` now walks
   `entries[*].GetProperties()["platform"]` and computes
   `transport_type = "enet"` (default) or `"webrtc"` (any web
   player present). The choice is added to the `connInfo` map.
2. ✅ **Runtime: set Edgegap deploy env vars conditionally.**
   `TRANSPORT_TYPE` is added to the Edgegap deploy `EnvVars`
   alongside `EXPECTED_PLAYER_COUNT` / `EXPECTED_SESSION_IDS`.
   Always set (never empty), so the server can branch on it.
3. ✅ **Server-side: read TRANSPORT_TYPE on boot.**
   `Main._enter_tree` now reads `OS.get_environment("TRANSPORT_TYPE")`
   and sets `Netcode.settings.transport_type` before the
   network connector starts. (No nginx involvement — that was
   GameLift-era; Edgegap port-forwards directly.)
4. ✅ **Client: read `transport_type` from match_ready.**
   `nakama_matchmaker_client.gd::_handle_match_ready` reads
   `transport_type` from the connection blob and applies it
   via `_apply_transport_type()` before computing the port
   and connecting.
5. ✅ **Client: derive the right port for the transport.**
   `_pick_port()` now takes a `transport_type` argument and
   picks UDP (ENet) or TCP (WebRTC/WebSocket) based on it.

**Resolved:**

6. ✅ **rollback_netcode WebRTC signaling port mismatch.**
   Two complementary fixes shipped:
   - `signaling_port` field added to `NetworkSettings` (escape
     hatch for non-nginx deployments). When set non-zero, the
     signaling server listens on it instead of the game-data
     port. (rollback_netcode commit `51305ba`.)
   - With nginx restored in #7, the runtime no longer needs to
     inject `SIGNALING_PORT` — Godot signaling stays on internal
     4433/TCP, nginx fronts external 4434/TCP via `ssl_preread`,
     and Edgegap forwards 4434/TCP to the host. The "mismatch"
     is bridged by nginx, not eliminated at the netcode layer.
     (snoringcat-platform commit `553825b`.)
7. ✅ **WSS termination for web clients** (code) **/ cert
   rotation** (automation). Code: nginx is back in the
   game-server container with `ssl_preread`, terminating wss://
   for web clients on 4434/TCP and pass-throughing native
   ws://. Decision: Option A (nginx) + Auto-Option 2 (Edgegap
   secret rotation, ECDSA cert).

   Shipped in:
   - `9dd5a18` (parent): `Dockerfile.edgegap` adds nginx,
     `infra/game-server/nginx.conf` (new), `entrypoint.sh`
     writes `TLS_FULLCHAIN`/`TLS_PRIVKEY` to `/game/tls/` and
     starts nginx before exec'ing Godot.
   - `553825b` (platform): runtime drops the `SIGNALING_PORT`
     env var since Godot signaling is co-located on 4433/TCP
     internally and nginx fronts 4434/TCP.
   - First wildcard ECDSA cert issued via certbot
     `dns-cloudflare`, expiring 2026-08-02.
   - `.github/workflows/cert-rotate.yml`: weekly cron checks
     `TLS_ISSUED_AT` companion env var, renews via DNS-01 if
     within 30 days of expiry, PATCHes every active Edgegap
     version's env vars, Discord-pings.

   Verified locally: `docker build` succeeds; container boots;
   nginx terminates TLS 1.3 against the issued cert
   (`subject: CN=*.game.hopnbop.net`, issuer Let's Encrypt
   E7); ssl_preread routes wss → terminate → proxy and ws →
   pass-through. The Godot binary in my local `build/linux/`
   is stale (predates the gamelift addon removal) and crashes,
   but CI rebuild will produce a fresh one — that's a build
   pipeline concern, not a transport concern.

   **Remaining (deploy steps, gated on user direction):**
   1. Trigger `game-server.yml` CI workflow to build + push
      image as `v9`.
   2. Register `v9` in Edgegap (dashboard) so it appears in
      the active-versions list.
   3. Run `cert-rotate.yml` once (workflow_dispatch with
      `force_renew=true`) to populate cert env vars on `v9`.
   4. SSH to Hetzner, bump `EDGEGAP_APP_VERSION=v9` in
      `/opt/nakama/config.yml` (or via the same redeploy path
      as `NAKAMA_PROTOCOL_VERSION` was hot-fixed), restart
      Nakama.
   5. Real-world verify with a `web + native` test match.

   ### Constraint that drives the design

   - Web clients MUST connect via `wss://` (browser policy
     blocks plain `ws://` from an HTTPS page).
   - Native clients MUST connect via plain `ws://` per
     CLAUDE.md's "Godot Native WSS Limitation" (Godot 4.5's
     native client can't establish wss:// to remote servers).
   - **Both client types coexist in the same WebRTC match**,
     so we need both protocols available on the server.

   ### Options

   **A. Re-introduce nginx with `ssl_preread`** (matches
   pre-Phase-F). One declared port (4434), nginx sniffs TLS:
   wss → TLS-terminate → forward to Godot at a private port;
   ws → pass through. Proven config; the historical
   `nginx.conf` is in git history.
   - Pros: single declared port, both clients work, zero
     Godot/netcode changes from here.
   - Cons: adds nginx + a process supervisor to the container;
     extra binary; cert mounting/rotation logistics.

   **B. Caddy with auto-Let's-Encrypt.** Same shape as A,
   simpler config. Can issue cert at startup via DNS-01 if
   we hand it a Cloudflare API token.
   - Pros: simpler config, automated cert rotation.
   - Cons: still two processes; ACME during boot adds startup
     latency + a Cloudflare API dependency on every cold
     start.

   **C. Godot WebSocketMultiplayerPeer with `TLSOptions.server()`.**
   Two separate declared ports — 4434/TCP for wss (web),
   4435/TCP for plain ws (native). Each client picks based on
   `platform`.
   - Pros: single process; no extra binary; cleanest with the
     rollback_netcode design.
   - Cons: requires adding a third declared port to the
     Edgegap app + plumbing in the matchmaker hook to
     advertise both signaling ports; cert-rotation problem
     unchanged.

   **D. Drop native-cross-play; web-only WebRTC.** Force
   native clients in cross-play matches to use WebSocket
   (TCP, accepts the head-of-line latency hit) and only web
   gets a WebRTC connection. Server still terminates TLS for
   web; native goes through plain ws.
   - Pros: simpler than B/C in code.
   - Cons: degrades native cross-play perf — but CLAUDE.md
     already documents that WebSocket cross-play at 100ms
     ping with TCP HOL is "playable but noticeably less
     smooth". This is a product call.

   ### Cert provisioning (orthogonal)

   Independent of A/B/C/D, the cert has to come from somewhere:
   1. Baked into the container image at build time (manual
      Let's Encrypt DNS-01 every 60-90 days).
   2. Mounted via an Edgegap secret at deploy time (same
      cadence; cert lives on the platform side, not in the
      image).
   3. Auto-issued at container startup (Caddy/B; or a
      cert-manager script for A/C). Requires a Cloudflare API
      token in the container.

   ### Recommendation

   **A (nginx with ssl_preread) + cert mounted via Edgegap
   secret.** Closest to the working pre-Phase-F path; preserves
   single-port-per-client; defers ACME plumbing. The user
   should confirm before implementation since this brings
   nginx back into the game-server container.
8. ⚠️ **Layer 1 regression test** for transport selection.
   The compliance suite now has socket-rig support (§2);
   adding `test_transport_selection.gd` is straightforward
   once the port mismatch (#6) is fixed enough that the test
   can actually drive a match end-to-end. Today the test would
   succeed at `transport_type` selection but fail at handshake.

### Regression test design

Two layers:

**Layer 1 (cheap, ships today): add a runtime-level assertion
to the compliance suite.**

Add a `test_transport_selection.gd` that calls a new (or
existing) RPC like `runtime_status` or
`probe_match_ready_payload` that returns a synthetic example
of what the runtime *would* send for given platform mixes, then
asserts the `transport_type` field is present and correct.

If we don't want to add that probe RPC, an alternative is to
hit the matchmaker via socket (Shape A from §2), have a single
fake "web" player join, then either:
- Fail open (1-player ticket gets matched immediately because
  we set `min_count=1`).
- Inspect the match_ready payload for `transport_type=webrtc`.

**Layer 2 (harder, deferred to integration suite): two-process
end-to-end.**

Spin up:
- One process simulating a `web` client (sets
  `platform=web` in matchmaker ticket).
- One process simulating a `native` client.
- Real Nakama + real Edgegap (or Edgegap stubbed via
  `EDGEGAP_TOKEN_FOR_TESTING`).

Assert the actual ICE-handshake completes and a single
DataChannel message round-trips. This is the only thing that
catches "the WebRTC stack still works on the live container
image" — important because we patch `webrtc-native` at Docker
build time and that's brittle.

### Recommended order

Fix steps 1+4 first (runtime reads platform → client reads
transport_type) and ship a Layer 1 test. That alone unblocks
WebRTC cross-play and gives us the regression tripwire. Steps
2-3 (entrypoint env-var wiring) come after a real cross-play
match attempt confirms what the entrypoint actually does.
Layer 2 e2e test slots into §4's integration suite when we
build it.

### Doc sweep after the fix lands

Once the runtime + client + entrypoint changes ship, walk back
through the project docs and update them to describe what
actually exists, not the migration-intermediate state. Specific
items:

- `CLAUDE.md` § "Web Build Cross-Play" describes the
  `is_web` matchmaker property and the runtime hook reading it
  to set `transport_type`. The actual property name is
  `platform` (`"web"`/`"native"`), and at the time the fix
  lands, the runtime hook will be doing the read for the first
  time. Match the prose to the shipped behavior.
- `CLAUDE.md` § "Transport Architecture" → "Transport selection
  flow" needs the same property-name correction and a refresh
  of the step ordering against the post-Phase-F runtime.
- `CLAUDE.md` § "End-to-End Matchmaking Flow" similarly
  references `is_web`.
- `third_party/snoringcat-platform/PLATFORM_ARCHITECTURE.md`
  may have stale references to the AWS-era transport-selection
  flow; sweep for `is_web` / GameLift port-mapping language and
  rewrite for Edgegap.
- The compliance suite README's `test_matchmaking.gd` row should
  be expanded once the new transport-selection regression test
  lands (Layer 1).
- `MIGRATION_PLAN.md` is the historical record. Don't try to
  bring it forward — instead, retire it to `docs/archive/` once
  the post-migration system stabilizes (already noted as a
  follow-up in NEXT_STEPS.md).

The principle: docs should describe the system as it works
today, with archival material kept under `docs/archive/` for
archeology. Drift between code and docs caused at least one of
the bugs we just shipped (the transport_type regression went
unnoticed partly because CLAUDE.md still confidently described
the AWS-era behavior).

---

## 4. Long-game: distributed test architecture (placeholder)

A research agent is searching the open web for industry
patterns (Riot/Blizzard/Epic playbooks, testcontainers, replay
testing for rollback netcode, headless-Godot orchestration,
etc.) and will return a report I'll fold in here. Until then,
the early intuition based on what we already have:

- The Nakama Go SDK is the natural lever for a **headless
  client driver** — no Godot in the loop, just Go (or Python via
  the gRPC client) issuing realtime-socket frames. Cheap,
  deterministic, can run N=100 in a single CI job.
- For physics/replay determinism the `rollback_netcode`
  framework is amenable to **fixture-replay tests**: record a
  sequence of inputs + frames, replay, assert the same final
  state. We already have unit tests around the rollback buffer;
  this would be one tier above.
- For cross-play we'll likely need at least one **real Godot
  process** in the loop (to validate the WebRTC GDExtension end
  to end). One Godot + N Go-driver clients is probably the
  right blend.
- Cost-wise: docker-compose-on-CI for the integration tier
  (Nakama + Postgres + a fake-Edgegap stub), one runner per
  test, target <5 minutes per integration run. The compliance
  suite stays what it is.

The research report will land in this section once the agent
finishes.
