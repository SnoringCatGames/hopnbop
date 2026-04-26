# Platform pivot discussion (2026-04-26)

> **Decision: Pivot from in-flight AWS platform-extraction to fully-off-AWS
> architecture (Nakama on Hetzner + Edgegap game servers initially, with
> path to DIY Hetzner orchestration later).**
>
> This document is the artifact of an architecture discussion that
> evaluated the current AWS stack against alternatives and arrived at a
> decision to pivot. It is shareable input to the sister session that is
> currently mid-plan on the AWS platform extraction.

## Original questions

1. Is AWS GameLift the right host, or should we move to a cheaper
   alternative or DIY?
2. Are there cheaper alternatives for the rest of the AWS backend stack?
3. What systems should we re-architect, and what new systems should we
   add, given the goal of reusing this stack across future Godot
   multiplayer games?

## Sister session context

A separate active session (plan at
`~/.claude/plans/in-general-i-ve-been-snoopy-pearl.md`) is mid-plan on a
"Restructure into a reusable multi-game platform" effort. That plan is
structured around AWS Lambda + DynamoDB + SAM, with three new repos
(`snoringcat-platform`, `godot-rollback-netcode`,
`godot-gamelift-session-manager`), an OpenAPI/oasdiff CI strategy, and a
five-phase implementation. The user has decided to pivot the backend
half of that plan; the disposition (pause vs. finish-then-migrate vs.
hybrid) is delegated to the sister session.

---

## Verified AWS billing (April 2026)

Pulled from `aws ce get-cost-and-usage` for the hopnbop account, April
1-26 (partial month):

| Service | Cost | % |
|---|---|---|
| **Amazon GameLift** | **$26.91** | **78%** |
| Tax | $3.30 | 9.5% |
| AWS Secrets Manager | $1.67 | 4.8% |
| Amazon VPC (public IPv4) | $1.26 | 3.6% |
| Amazon ECR | $0.61 | 1.8% |
| Amazon Route 53 | $0.50 | 1.4% |
| Amazon S3 | $0.13 | 0.4% |
| Amazon API Gateway | $0.12 | 0.3% |
| AWS Cost Explorer | $0.08 | 0.2% |
| Lambda / DynamoDB / CloudFront | **$0** | — (free tier) |
| **Total** | **$34.59** | |

Annualized: ~$485/year, of which ~$370/year is GameLift. Prior 12 months:
literally $0 total.

**Three insights:**

1. **GameLift Spot transition appears incomplete.** April billed 244.87
   hrs of c5.large on-demand ($26.69) vs only 6.61 hrs of Spot ($0.21).
   At current usage, theoretical full-Spot pricing is ~$8/mo. **$19/mo
   savings sitting on the table** independent of any architecture
   decision. Verify old on-demand fleet is deleted.
2. **Non-GameLift backend bill is essentially free.** $7.66/mo total for
   everything other than GameLift. Lambda, DynamoDB, CloudFront are all
   $0 (free tier). Premature to optimize API Gateway → Function URLs or
   tighten log retention; saves pennies.
3. **Migration savings are about future scale, not today's bill.** At
   current scale, $35/mo is small money. The case for migration is
   architectural simplicity + cost-curve flatness as the platform scales
   to multiple games and more players, not $/mo today.

---

## The decided architecture

### High-level topology

```
                         ┌────────────────────────────────────┐
                         │ Hetzner CAX11 (Nakama)             │
                         │ - auth (OAuth, anonymous)          │
                         │ - friends graph                    │
                         │ - parties / groups                 │
                         │ - matchmaker (custom Go runtime)   │
                         │ - leaderboards                     │
                         │ - presence                         │
                         │ - storage / settings               │
                         │ - fleet manager plugin → Edgegap   │
                         └─────────────┬──────────────────────┘
                                       │
                         ┌─────────────▼──────────────────────┐
                         │ Hetzner CAX11 (PostgreSQL)         │
                         │ - Nakama state                     │
                         │ - server pool registry             │
                         └────────────────────────────────────┘

                         ┌────────────────────────────────────┐
                         │ Edgegap fleet                      │
                         │ - 615+ deployment locations        │
                         │ - container scheduling, 5-15 sec   │
                         │   cold start                       │
                         │ - true scale-to-zero               │
                         │ - allocator handled by Edgegap     │
                         │ - native Nakama plugin             │
                         └────────────────────────────────────┘
```

### Why Nakama for the metadata layer

Nakama (Heroic Labs, Apache 2.0) maps almost 1:1 onto what the AWS
platform plan was rebuilding from scratch:

- Auth (anonymous, custom, Steam, Apple, Google, Facebook, Discord)
- Friends, blocks, presence
- Groups / parties with invitations and roles
- Matchmaker (ticket-based, custom rules in Go/Lua/TS)
- Leaderboards (tiered, time-bucketed, friends-only views)
- Tournaments (scheduled with entry rules, prize distribution)
- Storage objects + RPCs for arbitrary game state
- Realtime sockets for chat, presence, signaling
- Authoritative match handlers for non-rollback games

Compared to building it from scratch on Lambda + DynamoDB:
- ~6-10 person-weeks migration vs. multi-month custom build
- Battle-tested by Zynga, Paradox (Crusader Kings III), Gram Games
- Performance: faster per operation (no Lambda cold start, no API
  Gateway hop, native WebSocket vs assembled-from-parts)
- Cost curve: flat at indie scale, scales linearly with VM size at
  larger scale (vs AWS's near-zero floor + steep linear slope)

### Why Edgegap for game-server hosting (initially)

Edgegap is a managed game-server orchestration platform with a native
Nakama integration. Compared to alternatives:

| | GameLift | Edgegap | DIY Hetzner |
|---|---|---|---|
| Cold start | 3-5 min | **5-15 sec** | 60-90 sec |
| Regions | ~30 | **615+** | 5 |
| Allocator code | Vendor | **Vendor** | We write ~500 LOC Go |
| Per-active-hour | $0.025 (Spot) | $0.138 | $0.011 |
| Baseline always-on | $0 (scale-to-zero) | $0 (scale-to-zero) | $6/mo (CX21) |
| Player-IP-aware placement | No | **Yes** | DIY |

At Hop 'n Bop's current scale (single-digit matches/day, regionally
concentrated, no DIY orchestration code written yet), Edgegap is
cheapest *and* fastest *and* simplest. Crossover where DIY Hetzner
becomes cheaper: ~20 matches/day (about a $7/mo bill on either path).
Migration Edgegap → DIY Hetzner is straightforward when the time comes
(both speak Docker + Nakama plugin; only the fleet-manager Go module
changes).

### Cost projections

| Player load | Monthly cost (this stack) | Monthly cost (current AWS) |
|---|---|---|
| Today (sub-50 DAU, ~5-10 matches/day) | **~$12-15** | $35 |
| 100 DAU | $18-25 | $80-120 |
| 1k DAU | $35-50 | $400-800 |
| 10k DAU | $140-200 (DIY Hetzner) | $2000-8000 |

The structural advantage isn't current dollars (small money either way).
It's that the new architecture's cost curve is flat at indie scale and
scales linearly with capacity, vs AWS's per-request linear slope where
every Lambda invocation, DDB op, and API Gateway request adds to the
bill.

---

## What deletes from the current architecture

Going off AWS removes a substantial amount of code and infrastructure.
The biggest win: **the entire warmup machinery becomes unnecessary**,
because warmup exists only as a workaround for GameLift's expensive
idle state. With true scale-to-zero on Edgegap (or a $6/mo Hetzner
baseline), there is no expensive idle state.

**Backend (delete entirely):**
- `/fleet/warmup` and `/fleet/status` Lambdas + handlers
- `scheduled_idle_check` Lambda + EventBridge rule
- `hopnbop-fleet-state` DynamoDB table
- `services/fleet_service.py` and `handlers/fleet_handler.py`
- All AWS Lambdas (replaced by Nakama RPCs / hooks in Go)
- All DynamoDB tables (data moves to Postgres + Nakama Storage)
- API Gateway (Nakama serves WebSocket + HTTP directly)
- Secrets Manager (env vars on Hetzner box)
- Route 53 dynamic DNS pre-warming logic
- ECR (push images to Edgegap registry instead)
- The entire `backend/template.yaml` SAM stack

**Client (delete entirely):**
- `BackendApiClient.warm_up_fleet()`, `is_fleet_ready()`,
  `is_fleet_warming_up()`, `get_fleet_estimated_remaining_sec()`
- The 10-second polling timer for `/fleet/status`
- Lobby `FleetWarmupLabel` UI + countdown
- `loading_screen.gd`'s `LOADING.WARMING_UP_SERVER` phase
- `LocalSettings.setting_override_changed` → re-warmup path
- The `prefer_offline_mode` ↔ warmup interaction

**Game server (delete entirely):**
- The multi-stage Docker build's GameLift Server SDK v5.2.0 builder stage
- The webrtc-builder patch script for `portRangeBegin`/`portRangeEnd`/
  `enableIceUdpMux` (the patch exists *because of GameLift's port
  remapping*; with fixed Edgegap/Hetzner ports, vanilla webrtc-native
  v1.0.9 works)
- `_gamelift.activate_game_session()` and the entire
  `gamelift_session_manager` addon's GameLift provider
- Server SDK GLIBCXX_3.4.32 / Ubuntu 24.04 requirement
- nginx `ssl_preread` TLS detection + ICE candidate srflx port rewriting
  + libjuice mux mode + `InstanceConnectionPortRange` parity / 4192-4211
  / 2-port-limit gymnastics
- Container group definition versioning (4-version limit, COPYING
  state delays)
- Route 53 hostname derivation from server IP

**What stays:**
- Rollback netcode (game-engine-agnostic, in its own addon)
- Character system, level system, player code
- WebRTC GDExtension for native + browser clients (vanilla v1.0.9)
- ENet / WebSocket transports (server binds fixed ports directly)
- Match result reporting (URL change only)

A huge fraction of the most operationally painful parts of the project
(per CLAUDE.md, the GameLift sections are the largest chunk of tribal
knowledge) becomes deletable code.

---

## Migration sequence (~7-9 person-weeks)

1. Set up Hetzner project, create 2× CAX11 (Nakama + Postgres). Install
   Docker on each, Caddy for TLS, set up firewalls. (~2 days)
2. Stand up Nakama + Postgres via Docker Compose. Configure
   authentication providers (Google, Apple, Steam, Facebook, Epic).
   (~3 days)
3. Build Nakama runtime modules (Go) for custom logic: matchmaker
   rules, leaderboard reset, custom RPCs, server registration RPC,
   match-end RPC. (~1 week)
4. Set up Edgegap account + push game server Docker image to their
   registry. Configure Edgegap-Nakama fleet manager plugin. (~2-3 days)
5. Strip GameLift-specific code from the game server: remove
   `gamelift_session_manager` GameLift provider, replace with a thin
   "I'm a platform-allocated server, register with Nakama" client.
   Replace patched WebRTC GDExtension with vanilla v1.0.9. Delete
   nginx TLS termination, Route 53 logic, port-range gymnastics.
   (~1 week)
6. Migrate client (Hop 'n Bop) to nakama-godot SDK. Replace
   `AuthClient` / `BackendApiClient` / `FriendsApiClient` /
   `PartyApiClient` with thin wrappers around Nakama session. Delete
   fleet warmup UI / countdown / polling entirely. (~2 weeks)
7. Migrate data: walk DynamoDB tables, write to Nakama via SQL or
   Storage RPCs. Friends graph, leaderboards, settings, players.
   (~1-2 weeks)
8. Cut DNS, decommission AWS stack. (~3 days)
9. Build the shared "snoringcat-platform" as Go modules in Nakama's
   server runtime, parametrized by `game_id`. Reusable across games.
   (~1 week)

---

## Future migration: Edgegap → DIY Hetzner

When match volume crosses ~20 matches/day, DIY Hetzner becomes
cheaper. Migration is bounded:

- ~1 week to write the Go allocator module (~500 LOC).
- Game server image, Nakama runtime, client SDK all stay identical.
- Swap fleet-manager plugin from Edgegap to DIY Hetzner.

### DIY allocator architecture (future state)

Three Postgres tables (added to Nakama's existing schema):

```
game_servers
  server_id (PK)
  game_id
  hetzner_server_id     -- nullable; null for baseline servers
  ip
  port_base             -- baseline TCP+UDP port; per-match offsets derived
  state                 -- booting | ready | draining | terminated
  is_baseline           -- bool; baselines are never auto-terminated
  capacity              -- max concurrent matches
  utilization           -- current concurrent matches
  last_heartbeat_at
  created_at

server_allocations
  match_id (PK)
  server_id (FK)
  game_id
  allocated_at
  expires_at            -- TTL after which allocation is reclaimed

server_pool_events     -- audit / telemetry
  event_id (PK)
  game_id
  event_type            -- boot_requested | boot_completed | terminated | scale_decision
  details (jsonb)
  created_at
```

**Allocator flow on `MatchmakerMatched` hook:**

1. SELECT servers WHERE game_id = $1 AND state = 'ready' AND
   utilization < capacity ORDER BY utilization DESC LIMIT 1
   (pack matches onto the busiest non-full server first).
2. If found: insert into `server_allocations`, increment server
   utilization, push connection details to clients via Nakama
   notification.
3. If not found: trigger scale-up.

**Scale-up flow:**

1. Insert `game_servers` row with state='booting'.
2. Notify clients of expected wait time (typical: 60-90 sec).
3. Call Hetzner Cloud API: `POST /servers` with image, server type,
   datacenter, SSH keys, cloud-init user-data.
4. cloud-init pulls Docker image, starts game server, game server
   registers with Nakama via signed RPC.
5. Nakama updates `game_servers.state = 'ready'`, allocates the
   pending match.
6. If boot fails or times out (e.g. 3 min), mark state='terminated',
   tell clients matchmaking failed, retry on a different DC.

**Scale-down flow (cron job in Nakama):**

1. Every 5 min: SELECT non-baseline servers WHERE state='ready' AND
   utilization=0 AND last_heartbeat_at < now()-15 min.
2. Mark state='draining', refuse new allocations.
3. After grace period (in-flight matches finish), call Hetzner Cloud
   API to destroy.
4. Mark state='terminated'.

---

## Open questions for the sister session

The sister session has the context on how much of the AWS platform
extraction is already executed, so it should pick the migration
approach:

- **Pause and pivot now**, abandoning recent AWS work in progress
  but saving the most total effort.
- **Finish a stable AWS milestone, then migrate**, accepting more
  total work for less concurrent risk.
- **Hybrid**: keep the recently-cut-over client API clients
  (`BackendApiClient`, `FriendsApiClient`, `PartyApiClient`,
  `AuthClient`, `CrashReporter`) as the integration seam. Re-point
  them at nakama-godot inside the platform addon. The HTTP/auth
  contracts shift but the call sites in the game don't change.

The hybrid approach is probably cheapest given recent commits show
those clients have just been cut over to the platform stack — they're
already at the right abstraction layer to swap implementations.

Other questions to resolve:

- Baseline pool size for Hop 'n Bop launch (recommend 0 — Edgegap
  scales to zero; DIY needs 1× CX21 if/when migrated).
- Region selection for Hetzner Nakama (recommend Hillsboro/US-West
  to match current us-west-2 player base).
- TLS strategy for game servers: per-server cert via Cloudflare DNS
  API vs central Caddy proxy (Edgegap handles this if you stay on
  Edgegap; only relevant when migrating to DIY Hetzner).
- Docker registry choice: Edgegap's registry initially; Docker Hub or
  self-hosted on CAX11 if migrating to DIY.
- Monitoring: Better Stack / UptimeRobot free tier for synthetic
  uptime checks, plus Nakama's built-in Prometheus metrics.
- Postgres backup destination: Hetzner Storage Box ($3/mo for 1TB)
  vs S3 vs Backblaze B2. Recommend Hetzner Storage Box for
  single-cloud simplicity.

---

## What from the sister plan survives

The sister session's plan is structured around AWS Lambda + DynamoDB +
SAM. The decision to pivot to Nakama + Hetzner means **the backend half
of that plan does not survive** — Lambdas, SAM stack, DynamoDB schema,
API Gateway routes, API versioning strategy, OpenAPI/oasdiff testing
strategy. None of that applies to Nakama.

What is still valuable:

- The repo structure (3 new repos: `snoringcat-platform`,
  `godot-rollback-netcode`, `godot-gamelift-session-manager`). Note:
  `godot-gamelift-session-manager` is renamed/repurposed since
  GameLift is no longer the host. Likely
  `godot-platform-session-manager` with multiple providers (LocalOnly,
  Preview, Edgegap-via-Nakama, Hetzner-via-Nakama).
- The client-side SDK extraction (`auth_client.gd`,
  `backend_api_client.gd`, `friends_api_client.gd`, etc.). Same files
  move to the platform addon; only the implementation changes
  (calling nakama-godot instead of HTTPRequest to API Gateway).
- The `Platform.*` autoload pattern.
- The compliance test suite concept (now tests the nakama-godot-backed
  Platform API instead of the AWS API).
- The repo split + submodule pattern.
- The cross-game presence + party gating UX flows (now backed by
  Nakama presence + matchmaker hooks).
- The `games` config table concept (now lives in Postgres, not
  DynamoDB).
- The migration script (now migrates DDB → Postgres + Nakama Storage).

What is replaced wholesale:

- The SAM template, all Lambda handlers, all DynamoDB table
  definitions.
- The OpenAPI + oasdiff CI strategy (Nakama provides its own
  gRPC-proto-derived API; client compatibility is enforced by
  nakama-common version pinning).
- The API versioning strategy.
- The Lambda Function URLs / API Gateway optimization (n/a).
- The synthetic monitoring against AWS endpoints (becomes synthetic
  monitoring against the Nakama instance).

---

## Reference: research findings on key decisions

### Why Nakama over building on AWS

- Maps 1:1 onto what AWS plan rebuilds from scratch.
- ~6-10 person-weeks vs. multi-month for AWS extraction.
- Apache 2.0 OSS, fork-able. Heroic Labs hit 10-year mark Aug 2025,
  active GitHub commits.
- Production users include Zynga, Paradox (Crusader Kings III), Gram
  Games, Lion Studios, GSN, Huuuge.
- nakama-godot last tag is v3.4.0 from March 2024. Master should
  work on Godot 4.5; expect to file 1-2 small PRs.
- Performance benchmarks: 1 vCPU/3GB Nakama + 8 vCPU separate Postgres
  delivered 20,277 CCU, 530 auth/s, 700 RPC/s.
- Documented Nakama-GameLift integration exists (so a "keep GameLift,
  swap only the backend" path was also viable but rejected as not
  going far enough toward the cleanest endpoint).

### Why Edgegap over GameLift / DIY

- 615+ deployment locations vs ~30 (GameLift) or 5 (Hetzner DCs).
- 5-15 sec container cold-start vs 3-5 min (GameLift) or 60-90 sec
  (Hetzner VM).
- Native Nakama integration via fleet manager plugin.
- True scale-to-zero with no baseline cost (vs DIY Hetzner $6/mo
  baseline).
- Per-vCPU-min billing is more expensive at high match volume but
  cheaper at low volume because of true scale-to-zero.
- Crossover with DIY Hetzner: ~20 matches/day. Below that, Edgegap is
  cheaper because no idle baseline cost.

### What was ruled out and why

- **Hathora**: shut down May 5, 2026.
- **Unity Multiplay**: exited March 31, 2026.
- **Cloudflare Containers**: not viable for UDP today.
- **Heroic Cloud (managed Nakama)**: $600/mo entry tier, wrong-sized
  for indie scale.
- **Hetzner game servers DIY at launch**: requires writing ~500 LOC
  Go allocator before launch; Edgegap absorbs that work and is
  actually cheaper at low match volumes anyway.
- **Supabase / Firebase / PocketBase**: don't natively cover
  matchmaking glue or game-server coordination; would still need a
  custom matchmaker.
- **Cloudflare Workers + D1**: matchmaking glue and game-server
  orchestration don't translate cleanly to Workers.

---

## Verification plan

End-to-end smoke test for the migration:

1. Hetzner provisioned, Nakama + Postgres up, Caddy serving TLS.
2. OAuth providers configured; test sign-in (anonymous + Google).
3. Edgegap account active, game server image deployed, fleet manager
   plugin connected to Nakama.
4. Hop 'n Bop client connects to Nakama, completes auth flow, lists
   friends, joins party, starts matchmaking.
5. Matchmaker fires `MatchmakerMatched` → Edgegap allocates → client
   receives `{ip, port, jwt}` notification → connects to game server.
6. Match plays end-to-end, results reported via Nakama RPC,
   leaderboard updates.
7. Web client (browser) joins same flow via WebRTC; no nginx in path.
8. Run existing GUT suite — no regressions.
9. Sustained-load test: spin up 10 simultaneous matchmaking tickets,
   verify Edgegap scales, all matches start within ~30 seconds.
10. AWS stack decommissioned; CloudWatch budget alarm set at $5/mo
    to detect any forgotten resources.
