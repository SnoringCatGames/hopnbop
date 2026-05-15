# Friends / Party / Matchmaking — Full System Audit

> Audit conducted 2026-05-12. Scope: friends, party/squad, and matchmaking
> systems across the snoringcat-platform + hopnbop_private repos, in the
> context of the multi-game architecture extraction.

## TL;DR — what state are we in?

The migration off AWS (Phase F, 2026-05-03) is done and the **single-game**
Hop'n'Bop matchmaking pipeline is **live and largely working**. But the
multi-game refactor (the whole point of the snoringcat-platform extraction)
is roughly **40–60% wired through**:

- **Friends** — Nakama-backed and functional for one game. No GDPR cascade,
  no blocking, no recent-players, no pagination, and presence is
  "game-aware" only by virtue of the client stuffing `game_id` into an
  opaque `rich_presence` string. UI is mature.
- **Party** — **Broken contract.** The client calls `party_start_matchmaking`
  RPC, which **does not exist** in the runtime. Member lists are never
  populated. `leader_id` is never set. Polling-based, no real-time signals.
  UI breaks the project's SidePanel pattern.
- **Matchmaking** — End-to-end pipeline is production-ready for one
  hardcoded game (`"*"` query, min=2/max=4, hardcoded `EDGEGAP_APP_NAME`).
  No `game.yaml` ingestion, no per-game rules, no protocol-version
  pre-check (wastes Edgegap allocations), no rejoin/backfill, almost no UI
  for queue status / cancel / errors.
- **Platform SDK** — The `addons/snoringcat_platform_client/` package is
  largely a skeleton with a compliance test directory. The actual subsystem
  implementations live in `hopnbop_private/src/core/*_api_client.gd` and
  have not been moved/extracted into the addon yet.
  `Platform.{auth,account,party,friends,matchmaking,presence,settings,session}.*`
  autoload subsystems are *not* the real API surface in code — game code
  talks to `G.friends_api_client`, `G.party_manager`, etc. directly.
- **Tests** — Solid coverage of rollback netcode primitives (~90 tests).
  **Zero Go runtime tests.** Compliance suite covers HTTP surface contracts
  but **no multi-user flows, no socket flows** (`test_matchmaking.gd` is
  literally `pending("realtime-socket test rig not implemented yet")`).

Below is the detailed inventory, organized into:
1. **Architecture gap map** (what's "multi-game-ready" vs not)
2. **System-by-system gaps** (friends / party / matchmaking)
3. **Cross-cutting gaps** (auth, presence, settings, UI, runtime)
4. **Edge cases to test**
5. **Test-automation plan**
6. **Prioritized roadmap**

---

## 1. Multi-game architecture readiness — design vs reality

| Design principle | Status | Where it's violated |
|---|---|---|
| Every state-bearing thing has `game_id` | ❌ | `runtime/presence.go` storage collection `presence` / key `current` (no game scoping → two games collide). `runtime/match_lifecycle.go` writes leaderboard `"ffa"` with no `game_id` prefix. `settings_cloud_sync.gd` saves all settings as one blob, no `global` vs `game#{id}` scope. |
| Identity is global | ✅ | Nakama users + linking work. |
| Friends are global | ✅ | One row per pair, Nakama-native. |
| Presence single-row, current-game-aware | ⚠️ | Single row ✅, but the "current-game" bit is an opaque text field the client populates; server can't filter or reason about it. `_OWN_GAME_ID := "hopnbop"` is hardcoded in `friends_panel.gd:484`. |
| Settings split into `global` and `game#{id}` | ❌ | Not implemented anywhere. |
| Compliance scope is global by default | ⚠️ | `delete_account` RPC documented but **not implemented**. `LEGAL_VERSION := "1.1"` is one constant in `auth_token_store.gd:17`. |
| Per-game config declarative in `game.yaml` | ❌ | No `game.yaml` file exists in `hopnbop_private/`. `per_game_config.go` referenced in PLATFORM_ARCHITECTURE.md doesn't exist in `runtime/`. `EDGEGAP_APP_NAME` / `EDGEGAP_APP_VERSION` / `NAKAMA_GAME_VERSION` are env-globals on the Nakama host. |
| JWT carries `game_id` claim (per `api-spec.md`) | ❌ | Auth flow goes straight at Nakama; no per-game claim. |
| `runtime_status` RPC reports per-game build_id | ⚠️ | Reports one build_id for the whole instance. |

**Bottom line:** the runtime is *one Nakama instance, one game's worth of
config baked into env vars*. None of the per-game-ID routing is plumbed.
Adding ggj26 today would require code changes, not just a new `game.yaml`.

---

## 2. Friends system — detailed gaps

### Implemented & working
- `Platform.friends` (actually `G.friends_api_client`) — list, add by code,
  accept, decline, cancel, remove (`friends_api_client.gd:47–146`).
- Custom `update_and_get_presence` RPC: batched friend-presence read with
  status filter (`runtime/presence.go:44–145`).
- Friend code = Nakama username; lookup via `get_users_async`
  (`friends_api_client.gd:148–167`).
- Notification polling (10s for requests, 30s for presence) with dedup via
  `_known_*_ids` sets (`friends_notification_poller.gd:98–111`).
- 13-language i18n coverage; full SidePanel + ScreenFocusNavigator gamepad
  support.

### Missing / broken
| Item | Where | Notes |
|---|---|---|
| **GDPR cascade on account delete** | `runtime/main.go` (no `delete_account` registered) + `test_account_delete.gd:28–33` | Documented in PLATFORM_ARCHITECTURE.md §"Account deletion"; test asserts it's not implemented. Friendships become dangling. |
| **Block list** | nowhere | No schema, no RPC, no UI, no matchmaker interaction. |
| **Recent players** | nowhere | Common social pattern; not started. |
| **Pagination** | `friends_api_client.gd:56` | Hardcoded `limit=100`, `null` cursor. >100 friends silently truncated. |
| **Per-game friend filter** | `friends_panel.gd` | All friends shown regardless of which game they own. |
| **Presence `game_id` field** | `runtime/presence.go:26–39` | `presenceRecord` is `{rich_presence, status, updated_at}`. `game_id` is buried in client-formatted `rich_presence` text. Server can't say "show me friends in game X". |
| **Friend code in platform layer** | `friends_panel.gd:180–184` | UI reads friend code from legacy `G.backend_api_client.fetch_player_profile()` instead of `Platform.account`. |
| **Hardcoded game ID** | `friends_panel.gd:484`: `_OWN_GAME_ID := "hopnbop"` | Will break the moment another game uses the same SDK. |
| **Max pending request enforcement** | none | Spam vector if not added. |
| **Notification-on-online-status** | partial | Toasts only — no platform-level "Levi just came online" push. |

### Edge cases to test
- Receive a request from a player who then deletes their account before
  you accept.
- Accept a request that the sender has already cancelled (race).
- Add by code with mixed case / leading/trailing whitespace / unicode.
- Block someone you're already friends with (when blocking lands).
- Friend's `rich_presence` is malformed JSON.
- 99/100/101 friends boundary on the page.
- Two devices simultaneously accepting the same incoming request.
- Presence RPC failure mid-polling — does the UI go stale or show offline?

---

## 3. Party / squad system — detailed gaps

### What's actually there
- `PartyApiClient` calls Nakama's built-in **groups** API:
  `create_group_async`, `add_group_users_async`, `join_group_async`,
  `kick_group_users_async`, `leave_group_async`
  (`src/core/party_api_client.gd:1–175`).
- `PartyManager` polls every 3-10s (`src/core/party_manager.gd:1–316`).
- `party_lobby_panel.gd` overlays a CanvasLayer with member list +
  leader/invite/start/leave buttons.

### Broken / critical
| Issue | Where | Severity |
|---|---|---|
| **`party_start_matchmaking` RPC does not exist** | client calls it at `party_api_client.gd:131–153`; not registered in `runtime/main.go` | **Critical** — party-block queuing is a no-op. Will fail silently / time out. |
| **Members list never populated** | `fetch_party_status` only returns `{party_id, name, member_count}` (`party_api_client.gd`) — never calls `list_group_users_async` | **Critical** — UI shows empty roster even with members present. |
| **`leader_id` never set** | populated nowhere; UI compares against it at `party_manager.gd is_leader()` | **Critical** — leader-only buttons never show; leader transfer impossible. |
| **No party_id prefix scoping per-game** | `party-*` string-prefix hack for "is this a party group" — every game shares the namespace | High |
| **Polling-based, not socket-based** | up to 10s lag to discover invites | High |
| **Invite semantics wrong** | `add_group_users_async` adds immediately — no pending state; client constructs fake "pending" list locally | High |
| **No party_id in matchmaker query** | The runtime matchmaker hook can't recognize a party block as one party | High |
| **Hardcoded party size = 4** | `party_api_client.gd` | Should derive from per-game `matchmaker_rules.max_players`. |
| **UI breaks SidePanel pattern** | `party_lobby_panel.gd:17–88` extends `CanvasLayer`, raw `Button.new()` everywhere, no `ScreenFocusNavigator`, no U/D nav. | Affects gamepad UX. |
| **No party-invite-accepted UI** | invite translation exists but no clickable acceptance flow. | High |

### Missing features
- Party chat
- Game-mode selection by leader before queuing
- Member ready/not-ready toggles
- Leader transfer / kick-and-promote
- Cross-game party guard (member is in a different game right now)
- Cross-platform party warning (some matchmaker_rules disallow it)
- Persist party across launches / reconnects ("rejoin your last party?")
- Deep-link / join-by-code invite link
- Player presence subset for party UI (ping, level, status)

### Edge cases to test
- Leader hard-crashes mid-queue — does the party survive? Who's leader?
- Member's session token expires mid-party
- Invite a player who's already at max-friends-pending limit
- Invite a player to a game-X party while they're in a game-Y match
- Two members of the party are simultaneously added to two different
  matchmaker tickets
- Leader and one member both press "Start matchmaking" at the same time
- Party member is the only one of the group on web (cross-play implications)
- Party member protocol_version is behind everyone else's
- Party size > game's max_players (impossible match)
- Leader-only privileges enforcement on the server (a malicious client
  trying to send leader-only RPCs)

---

## 4. Matchmaking — detailed gaps

### What works (production-grade for one game)
- Nakama matchmaker + `fleet_allocator.go` MatchmakerMatched hook
  (`runtime/fleet_allocator.go:1–571`)
- Per-player session-ID allowlist passed via `EXPECTED_SESSION_IDS` env to
  the Edgegap container (`edgegap_server_provider.gd:301–321`)
- Transport auto-selection: any `web` → `webrtc`, else `enet`
  (`runtime/transport_select.go`)
- Match-ready notification with server endpoint + signed `signaling_url`
  (HMAC, 5-min TTL)
- Server-to-server `register_server` + `match_end` + `match_cancel` RPCs
  (`runtime/match_lifecycle.go:1–510`), idempotent, request-ID-gated
- Stat bounding to prevent leaderboard spam
  (`match_lifecycle.go:251–274`)
- Synthetic-match probe flow for daily smoke tests
- Recorded client IP via `record_client_ip` RPC → Edgegap geo hint
- Multi-instance preview support (Godot multi-window dev mode)
- Grace-period match-cancel on under-quorum (idle 60s, grace 10s, cancel
  via runtime)

### Missing for multi-game readiness
| Item | Where | Notes |
|---|---|---|
| **Per-game `matchmaker_rules` from `game.yaml`** | hardcoded in `nakama_matchmaker_client.gd:12-14` (`"*"`, min=2, max=4) | No game.yaml file exists. |
| **Game-mode bucketing** (ranked/casual/etc.) | nowhere | One queue per game. |
| **Skill / MMR bracket** | nowhere | |
| **Time-based relaxation** | nowhere | matchmaker query is fixed. |
| **Region preference** | nowhere | Edgegap auto-picks by IP only. |
| **Protocol-version pre-check at queue start** | only after match-ready arrives | Wastes ~$0.01 of Edgegap each time. |
| **Edgegap allocation-failure retry** | `fleet_allocator.go:473–505` errors out after 90s polling | No retry, no alternate region. |
| **Mid-queue cancel after match-ready notif** | client `clear_session()` is fire-and-forget | Will the Edgegap deploy still spin up? Probably yes → wasted money. |
| **Backfill / rejoin** | none | Player drops mid-match = match plays short. |
| **Spectator mode** | none | |
| **Per-game leaderboard schema** | `match_lifecycle.go:293–338` writes hardcoded `"ffa"` board | |
| **Per-game `EDGEGAP_APP_NAME` lookup** | `fleet_allocator.go:52` reads env var globally | |

### Matchmaking UI — almost entirely missing
- ❌ No "queue status" screen (time, count, ETA)
- ❌ No cancel-queue button
- ❌ No match-found dialog with accept/decline timer
- ❌ No "connecting to server" / spinner screen
- ❌ No version-mismatch error screen
- ❌ No "no servers available" / "allocation failed" error
- ❌ No region picker
- ❌ No game-mode picker
- ❌ Single-player / vs-bot / private-match paths weren't even auditable —
  likely bypass the matchmaker entirely
- ⚠️ Match-end / requeue / view-stats screens exist for hopnbop game flow
  but weren't comprehensively reviewed

### Edge cases to test
- Player A queues solo → match-ready arrives → connection times out → does
  A get re-queued, or stuck?
- Edgegap returns 503 mid-allocation → does the matchmaker hook return an
  error to all matched players?
- Nakama notification is lost in transit (rare but possible) → 120s client
  timeout fires → fallback to local-mode? With one player?
- Player cancels exactly when match-ready arrives → who "won" the race?
- 5 players queue with `max=4` — does the 5th wait or get a new match?
- Player has protocol_version 1, server has 2 — caught at queue, at match,
  or at game-server connect?
- Two players' couch-coop (`player_count=2` each) queue for a `max=4`
  slot — works? Slots reserved correctly?
- Web+native cross-play match: transport=webrtc, native players'
  GDExtension fails to ICE — fall back to ENet? (no, stuck)
- Synthetic-probe player accidentally matches with a real player —
  `synthetic_matches` marker behavior
- Same player adds themselves twice (multi-tab / multi-device) —
  duplicate ticket?
- Edgegap container starts but never calls `register_server` — runtime
  times out at 30s, then what?
- Match-end RPC fires twice due to retry — idempotency check holds, but
  does any state get double-written?
- HMAC signing-key rotation while signaling URLs are still in-flight

---

## 5. Cross-cutting platform gaps

### Auth (`src/core/auth_client.gd`, `runtime/auth.go`, `addons/snoringcat_platform_client/core/auth_token_store.gd`)
- Hardcoded `hopnbop.net` OAuth callback (`auth_client.gd:123`).
- Hardcoded Nakama host (`auth_client.gd:91`).
- `_NAKAMA_SERVER_KEY` / `_NAKAMA_HTTP_KEY` embedded as constants — not
  injected from per-game config.
- `LEGAL_VERSION := "1.1"` is one global constant; can't bump per-game
  terms.
- JWT has no `game_id` claim (api-spec.md requires one).
- Anonymous → permanent account upgrade UI does not exist.
- Account-merge flow is referenced (`_pending_merge_token`) but no UI.

### Account
- `delete_account` RPC documented, **not implemented** in `runtime/main.go`.
- Profile name is global (no per-game display name).
- Profile image is global.
- No GDPR export endpoint (`/v1/account/export` in spec, not in runtime).

### Presence (`runtime/presence.go`)
- Storage key not game-scoped → two games collide on the same Nakama
  instance.
- `game_id` only present in the client-formatted `rich_presence` string,
  opaque to the server.
- No event-driven push (friends learn about your presence change only when
  they poll).
- No "joinable" / "open to invites" flag in the schema.

### Settings (`src/core/settings_cloud_sync.gd`)
- No `global` vs `game#{id}` scope split — design says yes, code says no.
- Conflict resolution = timestamp only.
- No per-device tracking → easy to clobber from a stale device.

### Session
- `Platform.session.connect/disconnect` is documented as a delegating
  layer; in code, game-specific `GameSessionManager` does everything
  directly.
- Edgegap allocator hard-codes `EDGEGAP_APP_NAME` from env.

### Screens
- No `Platform.screens.auth_screen` reusable component. Hop'n'Bop ships
  its own auth screen with bespoke layout.
- No `Platform.screens.consent_screen` template.
- No `Platform.screens.anonymous_upgrade_screen` template.

### Versioning
- Per-game `protocol_version` correctly *designed* but not *enforced
  per-game* — runtime has one global `NAKAMA_PROTOCOL_VERSION`.
- `pr-validate.yml` doesn't yet check `game.yaml::protocol_version` ==
  `project.godot::config/protocol_version` (CI guard mentioned in
  PLATFORM_ARCHITECTURE.md is missing).

### Per-game config — the elephant
- `per_game_config.go` referenced in PLATFORM_ARCHITECTURE.md line 55 —
  **does not exist** in `runtime/`.
- `games` table SQL in PLATFORM_ARCHITECTURE.md lines 316–326 —
  **does not exist** in Postgres.
- `hopnbop_private/game.yaml` — **does not exist**.
- `docs/per-game-config.md` references obsolete DynamoDB `snoringcat-games`
  table.
- Without these, the entire "add a new game" 8-step procedure can't run.

---

## 6. Backend / runtime gaps

### `runtime/` files inventory
`auth.go`, `bulk_import.go`, `client_ip.go`, `fleet_allocator.go`,
`match_lifecycle.go`, `player_data.go`, `presence.go`, `runtime_status.go`,
`transport_select.go`, `version.go`, `main.go`. **Zero `_test.go` files.**

### Missing RPCs (referenced from client but unimplemented)
- `party_start_matchmaking` (called by `party_api_client.gd:131-153`)
- `delete_account` (documented in platform arch + test asserts
  not-implemented)
- `/v1/account/export` (GDPR; api-spec.md required)
- `get_protocol_version(game_id)` (mentioned in PLATFORM_ARCHITECTURE.md
  §Per-game protocol versioning; not in main.go RPC list)
- Per-game `matchmaking/start/status/cancel/result` (api-spec.md lists them
  under `/v1/games/{game_id}/...`; runtime uses Nakama-native socket
  matchmaker only)
- Per-game `party/{create,invite,accept,leave,get}` (same; uses
  Nakama-native groups)

### Operational / infra
- Observability stack (Prometheus/Grafana/Loki/Promtail) **stripped
  2026-05-06**. Visibility is daily Claude job + UptimeRobot + cost-monitor.
  Mid-flight match latency / allocation cold-start / matchmaker queue depth
  metrics are gone.
- `EDGEGAP_APP_VERSION` and `NAKAMA_GAME_VERSION` bumped by hand on the
  Nakama host's `runtime.env` after each game-server / runtime deploy. No
  GitOps loop.
- No staging Nakama at parity with prod (CI uses ephemeral docker-compose,
  prod is its own thing).
- DNS-watchdog and pg-backup systemd timers exist but no automated
  fail-safe / alerting if they stop running.

---

## 7. Edge cases & failure modes worth explicit test coverage

A condensed catalog beyond the per-system lists:

**Identity & lifecycle**
- Anonymous → permanent upgrade mid-party / mid-match / mid-queue
- Two devices logged into the same account simultaneously
- Token refresh failure during an active socket connection
- Account deleted in another game while present in current game
- Legal-version bump invalidates current session

**Multi-tenancy / cross-game**
- Same player has presence rows for game-A and game-B (currently impossible
  due to collision)
- Friend in game-A invites me — but I only own game-B
- Party in game-A, matchmaker request in game-B simultaneously
- Settings collision when game-A and game-B both define a key called
  `master_volume`

**Network / failure**
- Nakama restarts mid-queue — what tickets survive?
- Edgegap region outage — allocation hangs
- Cloudflare DNS write failure during pre-warming — web players can't
  connect
- Caddy reload mid-WSS-handshake
- Postgres failover during match_end RPC — leaderboard write half-applied

**Concurrency**
- Race: friend accept arrives via socket *and* via poll within 1s
- Race: party leader leaves, member becomes leader, another invite arrives
- Race: matchmaker_matched fires twice (Nakama bug?), Edgegap deploys twice

**Security**
- Forged `match_end` RPC from a malicious client (server-to-server check)
- Replayed signed `signaling_url` past 5-min TTL
- Friend code brute force / enumeration rate-limit
- Self-friend or self-party
- Match-end with negative scores, very large scores, NaN, Inf
- SQL injection via display name (Nakama handles, but verify)

**Migration & versioning**
- Game-A and game-B share a friends list — A bumps `protocol_version`, B
  doesn't — does this affect friends UI?
- Player added in game-A, then deletes game-A — should friendship survive
  (since friends are global)?

---

## 8. Test-automation plan

Currently: **91 GDScript tests** (mostly rollback/character/input), **zero
Go runtime tests**, compliance suite tests HTTP surface contracts only (no
multi-user, no realtime).

### Tier 1 — runtime unit tests (Go) — biggest hole

Create `runtime/*_test.go` covering pure-logic functions with the Nakama
interfaces mocked:

```
runtime/fleet_allocator_test.go      // session-ID derivation, geo-list construction,
                                     // EDGEGAP env injection, transport selection routing,
                                     // synthetic-probe detection, polling state machine
runtime/match_lifecycle_test.go      // stat bounding, request_id validation,
                                     // idempotency on duplicate match_end/match_cancel,
                                     // synthetic-probe leaderboard skip
runtime/transport_select_test.go     // table-driven: all platform combos
runtime/version_test.go              // mismatch matrix, "0 client" wildcard
runtime/presence_test.go             // friend filter, batched read shape
runtime/auth_test.go                 // device-id vs OAuth flows
```

Wire `go test ./runtime/...` into `nakama-runtime.yml` and `pr-validate.yml`
as a hard gate. Add `staticcheck` if not already running.

### Tier 2 — compliance suite expansion (GUT against live Nakama)

Extend the existing `addons/snoringcat_platform_client/test/compliance/`
harness:

```
test_friends_multiuser.gd            // A sends, B receives, B accepts, both see each other
test_friends_block.gd                // pending
test_friends_account_delete_cascade  // create friendship, delete A, B's list updates
test_party_invite_flow.gd            // create, invite, accept (multi-user), kick, leader xfer
test_party_to_matchmaking.gd         // party of N → all enter MM together → all get same match
test_matchmaking_socket.gd           // un-pending the existing stub: realtime socket harness
test_matchmaking_cancel_race.gd      // cancel exactly when match-ready arrives
test_matchmaking_failure_modes.gd    // Edgegap 503 (via env-injected fake), version mismatch
test_presence_game_filter.gd         // (after game_id scoping lands) filter friends in game-X
```

**Infrastructure work needed:**
- A reusable **socket harness** in `compliance_helper.gd` — currently
  HTTP-only.
- A **multi-session helper** that spins up N concurrent auth sessions in
  one test.
- An **Edgegap mock** mode (env-toggled `EDGEGAP_MOCK_DEPLOY=1` in the
  runtime) so tests can run without burning real allocations.

### Tier 3 — client unit tests (GDScript with doubles)

```
test/unit/platform/test_friends_api_client.gd
test/unit/platform/test_party_api_client.gd
test/unit/platform/test_party_manager.gd       // state machine, signal sequences
test/unit/platform/test_nakama_matchmaker_client.gd
test/unit/platform/test_friends_notification_poller.gd
test/unit/platform/test_settings_cloud_sync.gd
test/unit/ui/test_party_lobby_panel.gd         // (once it's refactored to SidePanel)
test/unit/ui/test_friends_panel_signals.gd
```

These use GUT's `double()` / `stub()` to fake the Nakama SDK responses.
Cover:
- Success path
- Empty path
- Error paths (timeout, 4xx, 5xx, malformed JSON)
- Signal-emission order and idempotency
- Polling-cadence edge cases
- Cache coherence

### Tier 4 — end-to-end / smoke

- **Local dev docker-compose** for Nakama + Postgres + a fake Edgegap
  (HTTP mock) — committed to `infra/dev/docker-compose.dev.yml`. None
  exists today.
- **`scripts/local-smoke-test.ps1`** (Windows-first per CLAUDE.md):
  authenticate → fetch friends → create party → queue matchmaker → assert
  match-ready. Mirrors the prod nightly smoke locally.
- **GitHub Actions matrix** for the compliance suite: run against (a)
  ephemeral docker-compose Nakama (already done) and (b) staging Nakama
  (new).
- Existing `synthetic-match-probe` job + `prod-health-check` job already
  exercise the matchmaker end-to-end against prod nightly — keep them,
  extend with party + friends probes.

### Tier 5 — load / soak / chaos

Not urgent but worth bookmarking:
- Run 100 concurrent matchmaker tickets against the runtime to validate
  fleet allocator concurrency.
- 100 friend-list reads/sec to validate the batched-storage-read in
  `presence.go`.
- Kill the Nakama container mid-matchmake to validate client retry /
  reconnect.

### Quick wins to implement this week
1. **Add `go test ./runtime/...` step** to `nakama-runtime.yml` (will pass
   with 0 tests). Then incrementally add unit tests — every existing
   function gets a regression net.
2. **Un-pend `test_matchmaking.gd`** by building a 30-line socket helper.
3. **Add the missing `pr-validate.yml` CI guard** for
   `game.yaml::protocol_version` == `project.godot::config/protocol_version`
   (currently advertised in CLAUDE.md as existing).
4. **Add a `local-smoke-test.ps1`** matching the prod nightly smoke —
   useful when iterating on RPC changes.

---

## 9. Prioritized roadmap

### P0 — broken contracts blocking real use

1. **Register `party_start_matchmaking` RPC in `runtime/main.go`** and
   implement it (matchmaker_add with party_id property so the matchmaker
   hook can group them; see Nakama party-block matching docs). Currently a
   silent fail.
2. **Populate party members in `fetch_party_status`** — add a
   `list_group_users_async` call. Currently the UI is permanently empty.
3. **Populate `leader_id`** in the party dict from Nakama's group
   `creator_id` or owner. Currently leader-only buttons never render.
4. **Implement `delete_account` RPC** — required for app-store compliance
   and TOS. Documented but not implemented.

### P1 — multi-game readiness (the whole point of the refactor)

5. **Create `hopnbop_private/game.yaml`** + `runtime/per_game_config.go` +
   `games` Postgres table — the foundation everything else hangs off of.
6. **Add `game_id` claim to JWT** and have all runtime RPCs read it
   (auth.go, presence.go, match_lifecycle.go, version.go).
7. **Scope presence storage by game_id** (presence.go).
8. **Scope settings into `global` vs `game#{id}`** (settings_cloud_sync.gd
   + storage schema).
9. **Scope leaderboards by game_id** prefix (match_lifecycle.go writes
   `{game_id}_ffa` not `ffa`).
10. **Per-game `EDGEGAP_APP_NAME` lookup** in fleet_allocator.go instead of
    single env var.
11. **Per-game `matchmaker_rules`** from game.yaml read by the client
    matchmaker config and the runtime hook.
12. **Per-game `protocol_version`** check at queue time, not after Edgegap
    deploys.

### P2 — UX / quality gaps

13. **Matchmaking queue UI**: status screen, cancel button, match-found,
    connecting, error states.
14. **Refactor `PartyLobbyPanel`** to follow the
    SidePanel/ScreenFocusNavigator pattern (gamepad support).
15. **Party invite acceptance UI** (notification → clickable
    accept/decline).
16. **Anonymous → permanent upgrade UI** + account-merge UI.
17. **Friend display names** in party member list (instead of player_id).
18. **Pagination** in friends list (>100).
19. **Friend block list** (schema + UI + matchmaker integration).

### P3 — resilience

20. **Edgegap allocation-failure retry** with exponential backoff and
    alternate region.
21. **Backfill** for mid-match disconnects (controversial — design call
    needed).
22. **Region picker** in matchmaking UI.
23. **Real-time party update** via socket (replace 10s polling).
24. **Notification system** push for friend online / party invite / match
    found.
25. **Re-introduce observability** stack (or a lightweight equivalent) —
    match latency, allocation cold-start, queue depth.

### P4 — test automation foundation (parallel track)

26. **`go test ./runtime/...` in CI** (Tier 1 above).
27. **Socket harness in compliance suite** + un-pend `test_matchmaking.gd`.
28. **Local docker-compose dev stack** + `local-smoke-test.ps1`.
29. **Edgegap mock mode** in runtime (env-gated).
30. **Multi-user compliance tests** (friends accept, party invite,
    party-to-MM).
31. **Client unit tests** for `*_api_client.gd` and managers using GUT
    doubles.

---

## Things to double-check before acting

A few things the parallel audits flagged that should be verified before
changing anything:

- **`hopnbop_private/game.yaml`**: couldn't confirm the file is absent vs
  just gitignored. Worth a direct `Get-ChildItem` to confirm.
- **`runtime/per_game_config.go`**: same — referenced in
  PLATFORM_ARCHITECTURE.md but verify it really isn't anywhere in the
  runtime/ directory.
- **`Platform.*` autoload**: the audits returned mixed signals about
  whether the `Platform` autoload subsystems (`Platform.friends`,
  `Platform.party`, etc.) are real APIs or just naming used in docs. In
  actual code, game code talks to `G.friends_api_client`, `G.party_manager`,
  etc. The extraction-to-addon is incomplete; the addon directory has
  compliance tests but the actual subsystem implementations still live in
  `hopnbop_private/src/core/`. Confirming this before refactoring saves a
  lot of churn.
- **Active plan file**: the platform CLAUDE.md references
  `~/.claude/plans/in-general-i-ve-been-snoopy-pearl.md`; one agent
  reported it's missing, with a similar file
  `in-general-we-have-quirky-dahl.md` (2026-05-02) in its place. Worth
  re-reading whichever the live plan is before kicking off a roadmap.
