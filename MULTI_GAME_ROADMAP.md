# Multi-Game Platform Roadmap

## Context

`FRIENDS_PARTY_MATCHMAKING_AUDIT.md` (2026-05-12) catalogs the gap
between the platform's design ("one Nakama runtime, N games") and
reality ("one Nakama runtime, one game's worth of config baked into
env vars, plus several broken user-facing contracts"). This document
stages the work to close that gap.

The audit's TL;DR: the single-game Hop'n'Bop matchmaking pipeline is
live and largely working, but the multi-game refactor — the whole
point of splitting the platform into a separate repo — is roughly
40–60% wired. Several contracts are broken (party member list never
populated, `leader_id` never set, `party_start_matchmaking` RPC
referenced but not registered, `delete_account` RPC documented but
not registered).

This file is both the **plan** and the **progress tracker**. Update
task checkboxes inline as work lands; add notes under tasks as you
discover sub-items or blockers.

See also:
- `FRIENDS_PARTY_MATCHMAKING_AUDIT.md` — diagnostic gap inventory.
- `NEXT_STEPS.md` — short-horizon session log (post-Phase F work).
- `third_party/snoringcat-platform/PLATFORM_ARCHITECTURE.md` —
  runtime detail / target topology.
- `third_party/snoringcat-platform/STUDIO_ARCHITECTURE.md` — service
  inventory / repo map.

## Status summary

- **Current focus:** Stage 1 P0 contract fixes have landed end-to-
  end on the wiring side. Two UX polish follow-ups remain inside
  Stage 1 (delete-account second-confirm + grace-period
  messaging); both are non-blocking and tracked under 1.5. Next
  major focus is Stage 2 (multi-game foundation).
- **Last updated:** 2026-05-12.
- **Stages complete:** Stage 0 (platform infra extraction —
  including the kickoff verification items 0.8 and 0.9).
- **Stages in progress:** Stage 1 — all five tasks (1.1a, 1.1b,
  1.2, 1.3, 1.4, 1.5) have working code shipped. Open items
  inside Stage 1 are UX polish on 1.5 and the compliance-test
  green-light still gated on a Stage 8 socket harness for
  multi-user party scenarios.
- **Stages blocked:** none.

## Stage dependency graph

```
Stage 0 (mostly done) — platform infra moved into snoringcat-platform
   ↓
Stage 1 (mostly done, 2026-05-12) — P0 broken contracts: party RPC,
   leader_id, members, delete_account all shipped. Open: 1.5 UX
   polish + compliance-test rig (Stage 8).
   ↓
Stage 2 — Multi-game foundation (game.yaml, per_game_config.go, JWT game_id)
   ↓
Stage 3 — Apply game_id scoping (presence, settings, leaderboards, Edgegap)
   ↓
   ├─→ Stage 4 — Matchmaking UX
   ├─→ Stage 5 — Party UX
   └─→ Stage 6 — Platform SDK extraction (src/core/*_api_client.gd → Platform.*)
   ↓
Stage 7 — Resilience (retries, notifications, observability)

Stage 8 — Tests (parallel track from day one; doesn't block features)
```

## Stage 0 — Platform infra extraction (mostly done)

Tracked previously by `~/.claude/plans/in-general-we-have-quirky-dahl.md`.
Absorbed here so there is one source of truth.

Per the platform repo's CLAUDE.md, these directories now live under
`third_party/snoringcat-platform/`:

- [x] 0.1 `runtime/` (renamed from `nakama-runtime/`)
- [x] 0.2 `infra/remote/cost-monitor/`
- [x] 0.3 `infra/remote/nakama/`
- [x] 0.4 `infra/remote/postgres/`
- [x] 0.5 `infra/pulumi/snoringcat-platform/`
- [x] 0.6 `scripts/` (phase-a.ps1, phase-b.ps1, probe-runtime-status.ps1,
      migrate_ddb_to_nakama.py, test-google-auth.py, platform_smoke_test.gd)
- [x] 0.7 Cost-monitor section added to `hopnbop_private/CLAUDE.md`

**Open verification items (do at Stage 1 kickoff):**
- [x] 0.8 Grep `hopnbop_private/` for any cross-references to old
      paths (`nakama-runtime/`, `infra/remote/`, etc.) outside the
      submodule. Remaining hits (`CLAUDE.md`, `NEXT_STEPS.md`) are
      intentional descriptions of paths *inside* the submodule, not
      stale references to a top-level dir. Confirmed 2026-05-12.
- [x] 0.9 Confirmed `release.yml` and `nakama-runtime.yml`
      workflows check out the submodule via `SUBMODULE_PAT` and
      build from `third_party/snoringcat-platform/runtime`.
      Confirmed 2026-05-12.

## Stage 1 — P0 broken contracts

**Goal:** Make party + delete_account actually work as advertised.
Each is a single-game fix; no multi-game refactor required.

**Why first:** broken contracts are user-visible bugs and app-store
compliance issues. They can be fixed in isolation, ship fast, and
stay correct when Stages 2–3 scope everything by `game_id`.

### Tasks

- [x] **1.1a Server-side `party_start_matchmaking` RPC** (2026-05-12)
  - Done: new `third_party/snoringcat-platform/runtime/party.go`;
    registered in `runtime/main.go`. Validates caller is the party
    group's creator (leader), enumerates members, dispatches
    persistent `party_matchmaking_start` notifications to non-leader
    members, returns matchmaker_properties (incl. `party_id`) +
    leader_id + member_ids to the caller. Build verified via
    pluginbuilder Docker. Landed: snoringcat-platform `a9a19cb`.
  - Audit's original framing assumed server-side `nk.MatchmakerAdd`
    on behalf of members. The Nakama Go runtime can't add tickets
    without active session/presence info — so the design is
    notification-dispatch + client-driven enqueue instead.

- [x] **1.1b Client-side party-matchmaking listener + matchmaker
      integration** (2026-05-12)
  - Done:
    - `src/core/nakama_matchmaker_client.gd` `_build_string_props`
      passes through `party_id` and `game_mode` when present in
      `session_prefs`.
    - `src/core/game_session_manager.gd` `client_request_session`
      gains an `extra_props: Dictionary` arg that merges into the
      flattened prefs dict (no SessionPreferences class change).
    - `src/core/game_panel.gd`
      `_client_client_request_session_ids` consumes
      `G.party_manager.pending_party_match_context` and passes
      `matchmaker_properties` through as `extra_props`. Cleared
      after use so the next solo match doesn't inherit the
      property.
    - `src/core/party_manager.gd` gains
      `pending_party_match_context`, an
      `on_party_matchmaking_notification(content)` follower entry
      point, and a shared `_start_party_matchmaking(data)` that
      drives `G.game_panel.client_load_game()`. Both the leader's
      RPC-response handler and the follower's notification handler
      converge on this. Guarded against re-trigger when a match is
      already loading/active.
    - `src/core/friends_notification_poller.gd`
      `_on_notifications_received` now iterates the
      `notifications` array and dispatches by subject; for
      `party_matchmaking_start`, calls
      `G.party_manager.on_party_matchmaking_notification(content)`
      with per-notification-id dedup
      (`_known_party_match_start_ids`).
  - Hook update (still pending — future stage):
    `fleet_allocator.go` `OnMatchmakerMatched` can read `party_id`
    from each entry's properties to surface party context in logs
    / synthetic-probe detection. The single-Edgegap-deploy routing
    is already implicit — all matched entries land on one deploy
    regardless.
  - Known limitation: matchmaker query stays `*`, so party members
    have a `party_id` property but aren't a true matchmaker-party
    block. They tend to pair together but timing-dependent matches
    can split them. A proper fix uses Nakama's
    `MatchmakerAddParty` realtime API or a `+properties.party_id`
    filter; defer until Stage 3.8 lands per-game
    `matchmaker_rules`.
  - Verification (still pending): new compliance test
    `test_party_to_matchmaking.gd` — create party of 2, leader
    calls start_matchmaking, assert both receive `match_ready` for
    the same Edgegap deploy.

- [x] **1.2 Populate party member list in `fetch_party_status`**
      (2026-05-12)
  - Done: `src/core/party_api_client.gd` now follows the party-
    group lookup with a `list_group_users_async` call and emits
    `members: Array[Dictionary]` of `{user_id, username,
    display_name, role}`. Role is mapped from Nakama's group-user
    state enum (0→leader, 1→admin, 2→member, 3→invited). Included
    `display_name` even though the audit spec only listed
    `{user_id, username, role}`; the UI consumers (party_lobby,
    friend_details) want a renderable name and pulling it here
    avoids a second round-trip.
  - Two UI consumers updated to the new dict shape:
    `party_lobby_panel.gd` (member labels, pending-invite
    rendering, start-button enable threshold uses non-invited
    count) and `friend_details_panel.gd` (`_is_friend_in_party`
    now iterates dicts).
  - Verification (still pending): compliance test
    `test_party_members_populated.gd` — create party with 2 users,
    fetch status, assert `members.size() == 2`. Tracked under 8.x.

- [x] **1.3 Populate `leader_id` in party dict** (2026-05-12)
  - Done: emitted `leader_id = g.creator_id`. Combined into the
    same `fetch_party_status` edit as 1.2 since both fields live
    on the same dict.
  - `PartyManager.is_leader()` now actually returns `true` for the
    creator; leader-only UI (start matchmaking, invite, kick) now
    renders correctly.

- [x] **1.4 `delete_account` RPC (soft-delete + cascade)**
      (2026-05-12)
  - Done: new
    `third_party/snoringcat-platform/runtime/account.go`,
    registered in `runtime/main.go`. Flow:
    1. Queue an `account_deletion_queue` storage row keyed by
       user_id with `scheduled_for = now + 30d` and the original
       username/display_name preserved for future cancellation.
    2. `AccountUpdateId` anonymizes display name to "[deleted]".
    3. Cascade-clear: `FriendsDelete` over the paginated friends
       list, `GroupUserLeave` per group (with `GroupDelete` if the
       user was the creator of a `party-` group), `StorageDelete`
       for the presence record, `LeaderboardRecordDelete` for
       "ffa", and bulk `StorageDelete` of every user-owned object
       across collections (excluding the deletion-queue row).
    4. `UsersBanId` so the existing JWT and any retained identity
       provider stop authenticating during the grace period.
  - Landed: snoringcat-platform `d2712fb`; parent bump in `02cf113`.
  - Test update done: `test_account_delete.gd` now exercises the
    RPC end-to-end (create one-shot account → call
    `delete_account` → assert response payload → assert
    /v2/account no longer reads with the original token).
  - Hard-delete cron is **not yet implemented** — the deletion-
    queue audit trail is durable but no scheduled job currently
    consumes it. From the user's perspective the account is gone
    (banned + anonymized + cascade-cleared); the raw Nakama row
    will persist until either the cron lands or the grace window
    flow cancels it. Tracked as a Stage 7 follow-up; the soft-
    delete is already the user-facing fact.
  - Cancellation-from-grace UI also not yet implemented. The
    audit trail captures `original_username` /
    `original_display_name` so a future "resurrect from grace"
    screen has what it needs.
  - Cross-game scoping (purge per-game state by `game_id`)
    deferred to Stage 3.6 — `leaderboardsToScrub` is hardcoded to
    `["ffa"]` for now.

- [x] **1.5 Wire `delete_account` into the client UI**
      (2026-05-12)
  - Done on the wiring side: `auth_client._send_delete_request()`
    now calls our new RPC via `nakama_client.rpc_async("delete_
    account", "")` instead of `delete_account_async()` (Nakama's
    built-in DELETE /v2/account, which hard-deletes immediately
    and skips the cascade). The existing `DeleteAccountRow` +
    `AccountPanel` confirm-dialog UX is unchanged; users still
    see the single-step "Delete your account?" confirm and the
    success toast → consent-screen nav. Landed: parent `5903331`.
  - **UX follow-ups still open inside 1.5** (non-blocking on
    Stage 2):
    - Second-confirmation step (typing username or "DELETE") per
      the audit spec. Current single-step confirm dialog is
      inherited from before. Implementation needs either a new
      sub-panel (like `AddFriendPanel` with a `TextInputRow`) or
      a new modal-with-text-input. Defer until UX polish pass.
    - Grace-period messaging in the confirmation copy and the
      success toast. `CONFIRM.DELETE_ACCOUNT` still says only
      "Delete your account?" — users don't see the 30-day window.
      Needs new translation keys (`CONFIRM.DELETE_ACCOUNT_DETAIL`
      with grace-day count, `TOAST.ACCOUNT_DELETE_QUEUED` with
      cancellation instructions) across all 13 locales.

### Definition of done

All five tasks checked: ✓ as of 2026-05-12, with the noted UX
follow-ups inside 1.5 still open. New compliance tests green in
CI is the next outstanding gate — requires the multi-session
socket harness from Stage 8.11 and 8.12 (currently the
compliance suite is HTTP-only and single-session). End-to-end
manual smoke (create party of 2 → both queue → both land in
same match → one user deletes account → other's friend list
updates) is the eventual sign-off; not yet exercised because
the matchmaker query is still `*`, so two-user party-block
pairing is timing-dependent.

## Stage 2 — Multi-game foundation

**Goal:** Add the per-game config infrastructure that everything
else hangs off of.

**Why now:** can't scope state by `game_id` until there is a
`game_id` concept that flows through auth + RPCs.

### Tasks

- [ ] **2.1 Create `runtime/per_game_config.go`**
  - Struct `GameConfig` with `{game_id, name, protocol_version,
    matchmaker_rules, edgegap_app_name, edgegap_app_version,
    legal_version, ...}`.
  - Loader reads from `games` Postgres table at startup; caches with
    60s TTL or explicit invalidation.
  - Verification: `runtime_status` RPC reports the loaded games map.

- [ ] **2.2 Create `games` Postgres table**
  - Schema per `PLATFORM_ARCHITECTURE.md:316-326`.
  - Migration: SQL run via Nakama's startup migration hook or via a
    separate one-shot. Decide which during execution.
  - Verification: `psql -c "select game_id, name from games"`
    returns rows after deploy.

- [ ] **2.3 Create `hopnbop_private/game.yaml`**
  - Declarative source of truth for hopnbop's per-game config:
    `game_id`, `name`, `protocol_version` (must match
    `project.godot` `config/protocol_version`), `edgegap_app_name`,
    `edgegap_app_version`, `matchmaker_rules` (min=2, max=4,
    query="*"), `legal_version`.
  - Verification: YAML schema check passes; manual review.

- [ ] **2.4 Sync `game.yaml` → `games` table**
  - Approach option A: new script `scripts/sync-game-config.ps1`
    POSTs game.yaml to a privileged `register_game` RPC.
  - Approach option B: `scripts/sync-game-config.ps1` upserts via
    `psql` directly.
  - Decide at execution time; A is more uniform, B is simpler.
  - Run on each runtime deploy.
  - Verification: after deploy, `games` table contents match game.yaml.

- [ ] **2.5 Add `game_id` JWT claim**
  - Where: `runtime/auth.go` (authenticate hooks) and every client
    auth path in `src/core/auth_client.gd`.
  - What: client passes `game_id` as a vars/metadata field; runtime
    asserts `game_id` exists in `games` table; mint JWT with
    `game_id` claim per `docs/api-spec.md`.
  - Verification: decode JWT, assert `game_id` claim present.

- [ ] **2.6 Pass `game_id` through all client→runtime RPCs**
  - Every RPC that touches state reads `game_id` from the session
    token (not from client-passed params — don't trust the client).
  - Verification: RPC-level unit tests assert `game_id` is extracted
    correctly and rejected when missing.

- [ ] **2.7 CI guard: `game.yaml::protocol_version` ==
      `project.godot::config/protocol_version`**
  - Where: `.github/workflows/pr-validate.yml` (or new workflow).
  - What: parse both files, fail PR on mismatch.
  - Verification: intentional mismatch PR → CI red.

## Stage 3 — Apply game_id scoping

**Goal:** Now that config exists, scope all state by `game_id` so
two games can coexist on one Nakama instance.

### Tasks

- [ ] **3.1 Scope presence storage by `game_id`**
  (`runtime/presence.go:26-145`). Collection/key currently
  `presence/current` → `presence/{game_id}/current`.
- [ ] **3.2 Add explicit `game_id` field to presence record**
  (not just opaque `rich_presence` text).
- [ ] **3.3 Server-side friend-in-game filter** so the client can ask
  "which friends are in game X". Used by `update_and_get_presence`
  callers.
- [ ] **3.4 Remove `_OWN_GAME_ID := "hopnbop"` hardcode**
  in `friends_panel.gd:484`; read from `Platform.game_id` (or the
  initialized addon value).
- [ ] **3.5 Scope settings into `global` vs `game#{id}`** in
  `src/core/settings_cloud_sync.gd`.
- [ ] **3.6 Scope leaderboards by `{game_id}_ffa` prefix** instead of
  bare `"ffa"` in `runtime/match_lifecycle.go:293-338`.
- [ ] **3.7 Per-game `EDGEGAP_APP_NAME`/`EDGEGAP_APP_VERSION` from
      `games` table**, not single env vars in
      `runtime/fleet_allocator.go:52`. Eliminates the manual
      `runtime.env` bump after each game-server deploy.
- [ ] **3.8 Per-game `matchmaker_rules` from `game.yaml`** read by
  `src/core/nakama_matchmaker_client.gd:12-14` (currently hardcoded
  `_MIN_COUNT=2`, `_MAX_COUNT=4`, `query="*"`).
- [ ] **3.9 Per-game `protocol_version` pre-check at queue start**
  (before allocating Edgegap, so version mismatches don't burn ~$0.01
  per failed allocation).
- [ ] **3.10 Per-game `LEGAL_VERSION` from `games` table**
  (currently hardcoded constant in `auth_token_store.gd:17`).

## Stage 4 — Matchmaking UX

**Goal:** Add the missing UI surface for matchmaking. The audit
calls out near-zero UI for queue status, cancel, errors.

### Tasks

- [ ] 4.1 Queue status screen (time waiting, queue size estimate, ETA).
- [ ] 4.2 Cancel-queue button (sends `MatchmakerRemove`; returns to
  lobby).
- [ ] 4.3 Match-found dialog with accept/decline timer (only if
  `matchmaker_rules.require_accept`).
- [ ] 4.4 Connecting-to-server / spinner screen.
- [ ] 4.5 Version-mismatch error screen with "update" CTA.
- [ ] 4.6 Allocation-failure / no-servers error screen with retry.
- [ ] 4.7 Game-mode picker (reads `matchmaker_rules.modes` from
  `game.yaml`).
- [ ] 4.8 Region picker (optional; reads from Edgegap's region list).

## Stage 5 — Party UX

**Goal:** Make the party flow usable. Per the audit, the current
`PartyLobbyPanel` is a `CanvasLayer` overlay with raw `Button.new()`
widgets and no gamepad nav — breaks the project's `SidePanel`
pattern.

### Tasks

- [ ] 5.1 Refactor `PartyLobbyPanel` to `SidePanel` +
  `ScreenFocusNavigator` (gamepad U/D/L/R nav per the project's UI
  conventions in `CLAUDE.md`).
- [ ] 5.2 Party invite acceptance UI (notification toast → screen →
  accept/decline).
- [ ] 5.3 Friend display names in member list (instead of raw
  `player_id`).
- [ ] 5.4 Real-time party updates via Nakama socket (replace 3–10s
  polling in `party_manager.gd`).
- [ ] 5.5 Ready / not-ready toggle per member.
- [ ] 5.6 Leader transfer / kick-and-promote.
- [ ] 5.7 Game-mode selection by leader before queuing.
- [ ] 5.8 Party chat.
- [ ] 5.9 Persist party across launches / reconnects ("rejoin your
  last party?").
- [ ] 5.10 Deep-link / join-by-code invite link.
- [ ] 5.11 Pending-invite state in client (Nakama
  `add_group_users_async` adds immediately — currently faked locally).

## Stage 6 — Platform SDK extraction

**Goal:** Move `*_api_client.gd` from `hopnbop_private/src/core/`
into `addons/snoringcat_platform_client/`. After this, a second game
can drop in the addon and get the same API surface.

**Why mid-roadmap, not first:** until Stages 1–3 land, the clients
are tangled with broken contracts and hopnbop-hardcoded values.
Extract clean code, not bug-laden code.

### Tasks

- [ ] 6.1 Define `Platform.{auth,account,friends,party,
  matchmaking,presence,settings,session,screens}` autoload subsystem
  properties in `addons/snoringcat_platform_client/core/platform.gd`.
- [ ] 6.2 Extract `auth_client.gd` → `Platform.auth.*`; parameterize
  the hardcoded `hopnbop.net` OAuth callback host and
  `nakama.snoringcat.games` host.
- [ ] 6.3 Reconcile `auth_token_store.gd` with the addon's existing
  `PlatformAuthTokenStore`; migrate `G.auth_token_store` references
  to `Platform.token_store`.
- [ ] 6.4 Extract `friends_api_client.gd` → `Platform.friends.*`.
- [ ] 6.5 Extract `party_api_client.gd` + `party_manager.gd` →
  `Platform.party.*`.
- [ ] 6.6 Extract `nakama_matchmaker_client.gd` +
  `edgegap_server_provider.gd` → `Platform.matchmaking.*`.
- [ ] 6.7 Extract presence read/write into `Platform.presence.*`.
- [ ] 6.8 Extract `settings_cloud_sync.gd` → `Platform.settings.*`.
- [ ] 6.9 Extract `game_session_manager.gd` → `Platform.session.*`
  (delegating layer; game-specific session-provider stays in
  `src/core/`).
- [ ] 6.10 Migrate every consumer in hopnbop game code from
  `G.*_api_client` to `Platform.*`. Grep coverage check at the end.
- [ ] 6.11 Reusable screen templates in `Platform.screens.*`: auth,
  consent, anonymous-upgrade. Hop'n'Bop screens become thin wrappers.

## Stage 7 — Resilience

**Goal:** Cover the failure modes the audit catalogs in §7.

### Tasks

- [ ] 7.1 Edgegap allocation-failure retry with exponential backoff
  + alternate region (`fleet_allocator.go:473-505`).
- [ ] 7.2 Mid-queue cancel cleanly tears down Edgegap deploy if it
  has already started (currently fire-and-forget at client side).
- [ ] 7.3 Push notification for friend online / party invite / match
  found (currently UI-only toasts; no platform-level push).
- [ ] 7.4 Friend block list (schema + RPC + UI + matchmaker
  integration).
- [ ] 7.5 Friend pagination (>100 friends; currently silently
  truncated at `friends_api_client.gd:56`).
- [ ] 7.6 Recent-players list.
- [ ] 7.7 Full GDPR cascade verification (1.4 covers RPC; this
  verifies every state surface clears).
- [ ] 7.8 Account-merge flow UI (referenced by `_pending_merge_token`
  but no UI exists today).
- [ ] 7.9 Anonymous → permanent upgrade UI.
- [ ] 7.10 Backfill / rejoin for mid-match disconnect (design call
  required — not obvious whether to support this).
- [ ] 7.11 Re-introduce lightweight observability: match latency,
  matchmaker queue depth, allocation cold-start time. The stripped
  Prometheus/Grafana/Loki configs are still in
  `infra/remote/nakama/` for re-introduction.
- [ ] 7.12 Max pending friend request enforcement (spam vector).
- [ ] 7.13 Friend-code rate-limit / brute-force protection.

## Stage 8 — Test foundation (parallel track)

**Goal:** Build a regression net. Run concurrently with Stages 1–7;
prioritize tests that protect work landing in the current stage.

### Tier 1 — runtime unit tests (Go)

- [ ] 8.1 Add `go test ./runtime/...` step to
  `.github/workflows/nakama-runtime.yml` (passes with 0 tests
  initially).
- [ ] 8.2 Add `staticcheck` if not already running.
- [ ] 8.3 `runtime/fleet_allocator_test.go` — session-ID derivation,
  geo-list construction, env injection, transport routing,
  synthetic-probe detection, polling state machine.
- [ ] 8.4 `runtime/match_lifecycle_test.go` — stat bounding,
  request_id validation, idempotency on duplicate
  `match_end`/`match_cancel`, synthetic-probe leaderboard skip.
- [ ] 8.5 `runtime/transport_select_test.go` — table-driven platform
  combos.
- [ ] 8.6 `runtime/version_test.go` — mismatch matrix.
- [ ] 8.7 `runtime/presence_test.go` — friend filter, batched read
  shape.
- [ ] 8.8 `runtime/auth_test.go` — device-id vs OAuth, `game_id`
  claim (after 2.5).
- [ ] 8.9 `runtime/party_test.go` — `party_start_matchmaking` RPC
  (after 1.1).
- [ ] 8.10 `runtime/account_test.go` — `delete_account` cascade
  (after 1.4).

### Tier 2 — compliance suite expansion (GUT against live Nakama)

- [ ] 8.11 Reusable socket harness in
  `addons/snoringcat_platform_client/test/compliance/compliance_helper.gd`
  (currently HTTP-only).
- [ ] 8.12 Multi-session helper that spins up N concurrent auth
  sessions in one test.
- [ ] 8.13 `EDGEGAP_MOCK_DEPLOY=1` mode in runtime so tests don't
  burn real allocations.
- [ ] 8.14 `test_friends_multiuser.gd`.
- [ ] 8.15 `test_friends_block.gd` (after 7.4).
- [ ] 8.16 `test_friends_account_delete_cascade.gd` (after 1.4).
- [ ] 8.17 `test_party_invite_flow.gd`.
- [ ] 8.18 `test_party_to_matchmaking.gd` (after 1.1).
- [ ] 8.19 Un-pend `test_matchmaking.gd`
  (`pending("realtime-socket test rig not implemented yet")`).
- [ ] 8.20 `test_matchmaking_cancel_race.gd`.
- [ ] 8.21 `test_matchmaking_failure_modes.gd`.
- [ ] 8.22 `test_presence_game_filter.gd` (after 3.3).

### Tier 3 — client unit tests (GUT with doubles)

- [ ] 8.23 `test/unit/platform/test_friends_api_client.gd`.
- [ ] 8.24 `test/unit/platform/test_party_api_client.gd`.
- [ ] 8.25 `test/unit/platform/test_party_manager.gd`.
- [ ] 8.26 `test/unit/platform/test_nakama_matchmaker_client.gd`.
- [ ] 8.27 `test/unit/platform/test_friends_notification_poller.gd`.
- [ ] 8.28 `test/unit/platform/test_settings_cloud_sync.gd`.

### Tier 4 — end-to-end / smoke

- [ ] 8.29 Local docker-compose dev stack at
  `infra/dev/docker-compose.dev.yml` (Nakama + Postgres + fake
  Edgegap).
- [ ] 8.30 `scripts/local-smoke-test.ps1` (auth → friends → party →
  queue → match-ready).
- [ ] 8.31 GitHub Actions matrix: compliance suite against ephemeral
  docker-compose AND staging Nakama.

## Cross-stage notes

### Edge cases (test coverage targets — slot into the right stage's tests)

Identity & lifecycle:
- Receive friend request from user who deletes their account before
  acceptance.
- Accept a request the sender already cancelled (race).
- Friend code with mixed case / leading whitespace / unicode.
- Friend's `rich_presence` is malformed JSON.
- 99/100/101 friends boundary (after 7.5).
- Two devices simultaneously accepting the same incoming request.
- Presence RPC failure mid-polling — UI stays correct.
- Anonymous → permanent upgrade mid-party / mid-match / mid-queue.
- Two devices logged into the same account simultaneously.
- Token refresh failure during active socket connection.
- Legal-version bump invalidates current session.

Party / cross-game:
- Leader hard-crashes mid-queue.
- Member's session token expires mid-party.
- Invite a player who's at max-pending limit.
- Cross-game party guard (member is in a different game's match).
- Cross-platform party warning when `matchmaker_rules` disallow it.
- Party size > game's `max_players` — explicit handling.
- Leader-only privilege enforcement on the server (malicious client).
- Two members simultaneously added to two different matchmaker
  tickets.
- Leader and member both press "start matchmaking" simultaneously.

Matchmaking / failure:
- Player A queues solo → match-ready arrives → connect times out →
  re-queue or stuck?
- Edgegap 503 mid-allocation — all matched players get an error.
- Lost Nakama notification → 120s client timeout → fallback path.
- Player cancels exactly when match-ready arrives (race).
- 5th queuer with max=4 — waits or new match?
- Couch-coop (`player_count=2` each) into max=4 — slot reservation
  correct.
- WebRTC ICE fails → fall back to ENet? (currently no — explicit
  decision needed).
- Synthetic-probe accidentally matches a real player —
  `synthetic_matches` marker behavior.
- Same player adds themselves twice (multi-tab / multi-device).
- Edgegap container starts but never `register_server`s — 30s
  runtime timeout.
- `match_end` RPC fires twice — idempotency holds, no double-write.
- HMAC signing-key rotation while signaling URLs in-flight.
- Postgres failover during `match_end` — leaderboard write
  half-applied.
- Caddy reload mid-WSS-handshake.

Security:
- Forged `match_end` from malicious client (server-to-server check).
- Replayed signed `signaling_url` past 5-min TTL.
- `match_end` with negative scores / NaN / Inf / very large scores.
- Friend-code brute-force / enumeration rate-limit.
- Self-friend or self-party.
- SQL injection via display name (Nakama handles; verify).

### Operational concerns

- `EDGEGAP_APP_VERSION` and `NAKAMA_GAME_VERSION` currently bumped by
  hand on `runtime.env`. Stage 3.7 makes this read from the `games`
  table per request, eliminating the manual step.
- No staging Nakama at parity with prod. Stage 8.31 introduces this.
- DNS-watchdog and `pg-backup` systemd timers have no automated
  fail-safe / alerting. Cover in 7.11.
- Observability stack (Prometheus/Grafana/Loki/Promtail) stripped
  2026-05-06. Configs preserved in
  `third_party/snoringcat-platform/infra/remote/nakama/` for
  re-introduction. Cover in 7.11.

### Decisions log

- **2026-05-12:** Sequencing chosen: P0 broken contracts first, then
  multi-game foundation, then UX, then platform-SDK extraction, then
  resilience. Tracker file: `MULTI_GAME_ROADMAP.md` at repo root.
  Quirky-dahl plan absorbed into Stage 0.
- **2026-05-12:** Audit findings verified against live code (party
  RPC missing, member list never fetched, `leader_id` never set,
  `delete_account` not implemented, `game.yaml` / `per_game_config.go`
  / `games` table all absent, Platform autoload subsystems not
  defined).
- **2026-05-12:** Task 1.1 split into 1.1a (server RPC) and 1.1b
  (client wiring). Audit's framing assumed server-side
  `nk.MatchmakerAdd` on behalf of party members, but the Nakama Go
  runtime API can't add tickets without active session/presence —
  followers must self-enqueue via a notification listener instead.
- **2026-05-12:** 1.1b landed. Followers receive
  `party_matchmaking_start` via `friends_notification_poller`'s
  existing 10s HTTP poll (Nakama persistent notifications); chose
  HTTP poll over an always-on socket to avoid the larger refactor
  required to add a shared client-side notification socket. Tradeoff:
  up to 10s of join lag for followers, but the matchmaker's own
  120s timeout absorbs that. Revisit if Stage 5.4 (real-time party
  updates) lands a socket bus we can reuse.
- **2026-05-12:** Party matchmaker query stays `*` for now; party
  members carry a `party_id` string property but the matchmaker
  doesn't enforce block-pairing. Acceptable for the small player
  pool today; true party-block matching (Nakama's MatchmakerAddParty
  realtime API or a `+properties.party_id` query) deferred to
  Stage 3.8 when per-game `matchmaker_rules` lands.
- **2026-05-12:** 1.2 & 1.3 combined into one commit since both
  edits live in the same five-line block in `fetch_party_status`.
  Member dicts include `display_name` beyond the audit's
  `{user_id, username, role}` spec because every UI consumer
  needs a renderable name; pulling it from the existing
  list_group_users_async response is free.
- **2026-05-12:** 1.4 ships the soft-delete + cascade + ban,
  but the hard-delete cron and the cancellation-from-grace UI
  are deferred. Justification: from the user's perspective the
  account is already gone (banned, anonymized, cascade-cleared);
  the raw Nakama row's continued existence in Postgres is a
  housekeeping/cron concern, not a contract violation. The
  audit trail (`account_deletion_queue` storage rows with
  `scheduled_for` + original identity captured) is durable, so
  a future cron job has everything it needs. `leaderboardsToScrub`
  is hardcoded `["ffa"]` until Stage 3.6 introduces per-game
  leaderboard scoping.
- **2026-05-12:** 1.5 ships the backend switch but defers UX
  polish (second-confirmation typing the username + grace-period
  messaging across 13 locales). The audit's strict reading wants
  both; the pragmatic split is "fix the broken contract now,
  iterate on UX in a separate pass." The existing
  single-step confirm + the soft-delete's 30-day grace already
  provide an undo path, so the second-confirmation step is
  belt-and-suspenders rather than essential. Translation cost
  was the deciding factor — 4 new keys × 13 locales is meaningful
  scope.

## How to use this document

**At the start of each session:**
1. Read this file. Identify the current focus and check task
   statuses.
2. If a task is half-done, the previous session should have left
   notes under it. Continue from there.
3. If starting a new task, check the cross-cutting edge-case list
   for related tests to also write or update.

**During a session:**
- Mark a task `- [-]` (in progress) when you start it; add a note
  with date.
- Mark `- [x]` when fully done (code + tests + verification).
- If you discover a new sub-task or blocker, add it as a nested
  bullet under the parent task.
- Add a date-stamped entry to the "Decisions log" for any choice
  that affects later stages.

**At the end of a session:**
- Update the "Status summary" section at the top with current focus.
- Bump "Last updated".
- If a stage is complete, mark it complete in the dependency graph
  comment block.

**Commit cadence:**
- Per hopnbop's `CLAUDE.md`: work lands directly on `main`, no
  feature branches. Commit + push at natural stopping points when
  work is end-to-end functional.
- Cross-repo work (parent + submodule) commits the submodule first.
