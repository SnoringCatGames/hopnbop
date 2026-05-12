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

- **Current focus:** Stage 5.4 shipped today. The 3 s / 10 s
  party polling loop in `party_manager.gd` is gone; party
  state now flows over a long-lived Nakama realtime socket
  (`NotificationSocketClient`) driven by four new
  `AfterAddGroupUsers` / `AfterJoinGroup` / `AfterLeaveGroup`
  / `AfterKickGroupUsers` runtime hooks that fan out a
  transient `party_state_changed` notification on every
  membership change. The notification socket is shared:
  `FriendsNotificationPoller` also consumes
  `party_matchmaking_start` over it (near-instant) and keeps
  its 10 s HTTP poll as a fallback for socket-down windows.
  A 60 s catch-up `fetch_party_status` poll runs alongside
  for transient-notification gaps. Stage 5 remainders
  (5.5-5.10) still pending: ready toggle, leader transfer,
  mode picker, chat, persistence, deep link. Stage 3 still
  has 3.5 / 3.9 open; Stage 4 still has 4.3/4.7/4.8 deferred
  behind game.yaml schema extensions. Next focus is more
  Stage 5 (5.5 ready toggle is a small bite that unblocks
  the leader's "everyone ready?" UX, 5.6 leader transfer
  follows naturally) or Stage 6 (Platform SDK extraction).
- **Last updated:** 2026-05-12.
- **Stages complete:**
  - Stage 0 (platform infra extraction — including the kickoff
    verification items 0.8 and 0.9).
  - Stage 2 (all seven tasks shipped 2026-05-12).
- **Stages in progress:**
  - Stage 1 — all five tasks (1.1a, 1.1b, 1.2, 1.3, 1.4, 1.5)
    have working code shipped. Open items: UX polish on 1.5 and
    the compliance-test green-light still gated on a Stage 8
    socket harness for multi-user party scenarios.
  - Stage 3 — 8/10 tasks shipped 2026-05-12 (3.1, 3.2, 3.3,
    3.4, 3.6, 3.7, 3.8, 3.10). Open: 3.5 settings split
    (needs global-vs-per-game taxonomy decision) and 3.9
    protocol-version pre-check (needs matchmaker-entry session-
    vars access pattern).
  - Stage 4 — 5/8 tasks shipped 2026-05-12 (4.1, 4.2, 4.4,
    4.5, 4.6). Open: 4.3 (needs `matchmaker_rules.require_accept`
    in game.yaml), 4.7 (needs `matchmaker_rules.modes` schema),
    4.8 (region picker; optional, needs Edgegap region list).
  - Stage 5 — 5/11 tasks shipped 2026-05-12 (5.1, 5.2, 5.3,
    5.4, 5.11). Open: 5.5 ready toggle, 5.6 leader transfer,
    5.7 game-mode picker, 5.8 chat, 5.9 persist across launches,
    5.10 deep-link/join-by-code.
- **Stages blocked:** none.

## Stage dependency graph

```
Stage 0 (done) — platform infra moved into snoringcat-platform
   ↓
Stage 1 (mostly done, 2026-05-12) — P0 broken contracts: party RPC,
   leader_id, members, delete_account all shipped. Open: 1.5 UX
   polish + compliance-test rig (Stage 8).
   ↓
Stage 2 (done, 2026-05-12) — game.yaml, games table,
   per_game_config.go, register_game RPC, sync script, CI guard,
   BeforeAuthenticate* hooks, game_id-in-vars JWT claim, RPC
   plumbing all shipped.
   ↓
Stage 3 (mostly done, 2026-05-12) — game_id scoping: presence
   (storage + record field + friend filter), leaderboards
   (`{game_id}_ffa`), Edgegap app coords from games table,
   matchmaker rules + legal_version surfaced via version_check.
   Deferred: 3.5 (settings split), 3.9 (pre-allocate proto check).
   ↓
   ├─→ Stage 4 (mostly done, 2026-05-12) — Cancel button +
   │   recoverable-failure classifier; queue status / connect /
   │   version mismatch already in place. Deferred: 4.3
   │   (require_accept), 4.7 (modes), 4.8 (region picker).
   ├─→ Stage 5 (partial, 2026-05-12) — PartyLobbyPanel
   │   refactored to SidePanel + ActionRow nav and reachable
   │   from MainMenuPanel; pending-invite acceptance UI;
   │   fetch_party_status emit shape + state=3 distinction
   │   fixed; real-time socket updates via party_state_changed
   │   notification subject + long-lived NotificationSocketClient
   │   (5.4). Open: party ergonomics (5.5-5.10).
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

- [x] **2.1 Create `runtime/per_game_config.go`** (2026-05-12)
  - Done: new `third_party/snoringcat-platform/runtime/
    per_game_config.go`. `GameConfig` struct + `perGameConfig`
    cache + Postgres-backed loader with `Refresh`, `Get`, `List`,
    `GameIDs`, `upsert`. `register_game` RPC (server-to-server)
    accepts game.yaml-as-JSON, validates required fields, upserts
    via `INSERT ... ON CONFLICT ... DO UPDATE`, refreshes cache.
    `get_game_config` RPC (client session) returns a public
    projection.
  - Verification: `runtime_status` now includes
    `registered_games: ["hopnbop"]` after first sync.
  - Cache strategy: no TTL — load-all at module init, full cache
    refresh on every `register_game` write. Simple and
    sufficient until out-of-band Postgres edits are a real
    concern. Re-evaluate when adding a games-admin console.

- [x] **2.2 Create `games` Postgres table** (2026-05-12)
  - Done: DDL in `per_game_config.go`'s `gamesTableDDL` constant,
    run via `db.ExecContext(...IF NOT EXISTS...)` at module
    init. Idempotent — safe to re-run on every plugin reload.
    Schema matches `PLATFORM_ARCHITECTURE.md:316-326`.
  - No separate migration tooling needed; Nakama's plugin
    `*sql.DB` is sufficient and there's no name collision with
    the stock Nakama schema (verified against heroiclabs/nakama
    schema).
  - Verification: after a runtime restart, `psql -c "\d games"`
    will show the table; before any sync the row count is 0.

- [x] **2.3 Create `hopnbop_private/game.yaml`** (2026-05-12)
  - Done: `game.yaml` at repo root with `schema_version`,
    `game_id: hopnbop`, `display_name`, `edgegap_app_slug`,
    `protocol_version: 2` (matches `project.godot`),
    `display_version: 0.39.0`, `ports`, `transports`,
    `auth_providers`, `matchmaker_rules` (min=2/max=4/cross_play),
    `leaderboards: [ffa]` (matches current runtime hardcode),
    `legal` block including `legal_version: "1.1"` (matches
    `auth_token_store.gd:LEGAL_VERSION`).
  - Deviations from `PLATFORM_ARCHITECTURE.md` example: keeping
    `legal_version` as the string `"1.1"` (the current
    in-script constant) rather than the example's `4`; using
    bare `ffa` for the leaderboard ID (Stage 3.6 will prefix
    with `{game_id}_`). Both are honest reflections of current
    runtime state.

- [x] **2.4 Sync `game.yaml` → `games` table** (2026-05-12)
  - Done: new `scripts/sync-game-config.ps1`. Parses YAML via
    `powershell-yaml` (installs on demand to CurrentUser scope
    so the script runs without prereq install in CI), validates
    required fields locally, cross-checks `protocol_version`
    against `project.godot`, POSTs the JSON to
    `/v2/rpc/register_game?http_key=...&unwrap=true`. Supports
    `-DryRun` for parse-and-validate without POST.
  - Chose Option A (`register_game` RPC) over Option B (direct
    psql) because it lets the runtime own validation + cache
    refresh; the script needs no DB credentials, only the
    Nakama HTTP key. Dry-run verified locally 2026-05-12 (YAML
    → JSON conversion + field validation pass).
  - **CI wiring deferred.** Adding a step to
    `nakama-runtime.yml` or `release.yml` requires a new
    `NAKAMA_HTTP_KEY` GitHub secret. Until that secret is
    configured, this script runs as a manual post-deploy step.
    The first Stage 2 deploy needs a manual `sync-game-
    config.ps1` invocation regardless (no row exists yet).

- [x] **2.5 Add `game_id` JWT claim** (2026-05-12)
  - Done — server: new `validateGameIDInVars` helper +
    BeforeAuthenticate{Device,Google,Facebook,Apple,Steam} +
    BeforeSessionRefresh hooks registered in `main.go`.
    Each hook reads `game_id` from the inbound request's vars
    map and rejects unknown ids. Bootstrap exemption: when
    the `games` cache is empty (immediately after first
    deploy, before `sync-game-config.ps1` runs), all auths
    pass through so the runtime stays usable.
  - Done — client: `application/config/game_id="hopnbop"`
    added to `project.godot`; `auth_client.gd` builds a
    `{"game_id": ...}` vars dict from project settings and
    passes it on every `authenticate_*_async` + `session_
    refresh_async` call. Verified live: the refresh request
    body in a real run carried `"vars":{"game_id":"hopnbop"}`.
  - Done — addon plumbing: `Platform.initialize(...)` is now
    called from `global.gd._ready()` with `game_id` from
    project settings, so the autoload's `game_id` field is
    populated. Compliance helper's `_resolve_game_id()` reads
    this (or the `PLATFORM_GAME_ID` env var as fallback) when
    building the auth POST body, so every compliance test
    that hits `/v2/account/authenticate/device` directly now
    sends `vars`.
  - Implementation note (deviation from the audit's spec):
    the audit framed this as "mint JWT with `game_id` claim".
    Nakama's session-token JWT shape is fixed (it carries
    Nakama-defined claims like `uid`/`tid`/`exp`); the vars
    map is the platform-provided extension surface and gets
    propagated to runtime context as `RUNTIME_CTX_VARS`. So
    `game_id` lives there, not as a top-level JWT claim.
    Verification is reading `ctx.Value(RUNTIME_CTX_VARS)
    ["game_id"]` server-side, which `requireGameID` does.
  - Verification: live editor smoke confirms the outgoing
    refresh body carries the vars. End-to-end RPC verification
    is per-RPC (see 2.6).

- [x] **2.6 Pass `game_id` through all client→runtime RPCs**
      (2026-05-12)
  - Done — added `requireGameID(ctx, games)` helper in
    `auth.go`. Same bootstrap exemption as the auth hooks:
    when `games` is empty, the helper returns whatever vars
    the session carried (possibly "") without rejecting.
    Once the table is populated, missing or unknown game_id
    is INVALID_ARGUMENT (3).
  - Done — every stateful client-session RPC now calls it:
    - `update_and_get_presence` (presence.go)
    - `get_player_stats`, `get_match_history`,
      `export_player_data` (player_data.go)
    - `party_start_matchmaking` (party.go)
    - `delete_account` (account.go)
    - `get_game_config` (per_game_config.go) — defaults to
      session game_id when the payload doesn't override
  - Each affected RPC has been wrapped in a `xxxRpcFactory`
    that closes over `games`, so the dependency is explicit
    at registration time rather than via a package-level
    global.
  - Game-side reads/writes are not yet scoped to game_id —
    presence key is still `presence/current`, leaderboard is
    still bare `"ffa"`, etc. That's Stage 3. The session
    game_id is read at every entry point; how it's *used* is
    Stage 3's job.
  - Verification: `go vet ./... && go build ./...` clean;
    Docker pluginbuilder image produces a 19 MB
    `snoringcat.so`. RPC-level unit tests for game_id
    extraction (Stage 8.x) still pending; covered by manual
    smoke + the compliance suite once it runs against the
    deployed runtime.

- [x] **2.7 CI guard: `game.yaml::protocol_version` ==
      `project.godot::config/protocol_version`** (2026-05-12)
  - Done: new `game-config-parity` job in `pr-validate.yml`.
    Parses both files via grep/awk, fails the workflow with a
    GitHub annotation on mismatch. Verified locally that the
    grep/awk extracts `2` from both files cleanly.
  - The sync script also re-checks this at run time (defense in
    depth).

## Stage 3 — Apply game_id scoping

**Goal:** Now that config exists, scope all state by `game_id` so
two games can coexist on one Nakama instance.

### Tasks

- [x] **3.1 Scope presence storage by `game_id`** (2026-05-12)
  - Done: `presence.go` keeps `collection="presence"` but the
    key flips to `"{game_id}/current"`. The legacy bare
    `"current"` key is retained as a fallback for offline /
    bootstrap callers via `presenceKey("")`.
  - `account.go` cascade now iterates `games.GameIDs()` and
    deletes both per-game keys and the legacy key, so a
    grace-period soft-delete clears presence everywhere.
- [x] **3.2 Add explicit `game_id` field to presence record**
      (2026-05-12)
  - Done: `presenceRecord` JSON adds `game_id`. Friends
    consumers (e.g. `friends_panel.gd`'s "in another game"
    badge) read this directly instead of parsing
    `rich_presence` opaque text.
- [x] **3.3 Server-side friend-in-game filter** (2026-05-12)
  - Done: `update_and_get_presence` defaults to same-game-only
    reads (batched StorageRead keyed on the caller's game_id).
    Optional `include_other_games` arg fans the read out across
    every registered game's collection so a future "friends
    everywhere" UI can opt in. Dedup keeps the first row per
    user (caller's game wins when present).
- [x] **3.4 Remove `_OWN_GAME_ID := "hopnbop"` hardcode**
      (2026-05-12)
  - Done: `friends_panel.gd` compares `friend_game_id` against
    `Platform.game_id` (Stage 2.5 wired Platform.initialize at
    boot, so this is non-empty in production).
- [ ] **3.5 Scope settings into `global` vs `game#{id}`** in
  `src/core/settings_cloud_sync.gd`.
  - Deferred 2026-05-12. Needs an explicit taxonomy decision
    (which settings are global — locale, anonymous_color_hue —
    vs per-game) plus a one-shot migration step for existing
    rows. The current single-blob path keeps working; no
    user-visible bug. Revisit when a second game's
    requirements force the split.
- [x] **3.6 Scope leaderboards by `{game_id}_ffa` prefix**
      (2026-05-12)
  - Done — server: new `gameScopedLeaderboardID` helper turns
    bare `"ffa"` into `"{game_id}_ffa"`. `match_lifecycle.go`
    `MatchEndRpc` reads game_id from a new `match_metadata`
    storage row fleet_allocator writes at deploy time;
    `player_data.go` `get_player_stats` and
    `export_player_data` use the session-scoped game_id.
    `account.go` `leaderboardIDsToScrub` derives the cascade
    list from each game's `game.yaml.leaderboards[]` plus the
    legacy bare `"ffa"`.
  - Done — fleet_allocator: votes `game_id` from each matched
    entry's properties (clients pass `Platform.game_id` as a
    string property; unregistered ids dropped; ties broken
    deterministically by alphabetical winner). Pre-update
    clients (no vote) leave the match's game_id empty and
    fall back to the legacy bare board so a rollout doesn't
    drop results.
  - Done — client: `backend_api_client.gd` reads
    `"{game_id}_ffa"` instead of the pre-existing buggy
    `"ffa_%s" % type` (which never matched the server's bare
    write). The `type` parameter is retained for future per-
    window boards (`{game_id}_ffa_weekly`, ...) but currently
    routes both UI tabs to the same data.
  - Known limitation: pre-Stage-3.6 leaderboard records on
    bare `"ffa"` are not migrated. They're now invisible to
    `fetch_leaderboard` (which reads `"hopnbop_ffa"`). If
    surfacing them matters, write a one-shot RPC that copies
    `LeaderboardRecord("ffa", *)` → `LeaderboardRecord
    ("hopnbop_ffa", *)`; today the small live-player pool
    makes the data loss acceptable.
- [x] **3.7 Per-game `EDGEGAP_APP_NAME`/`EDGEGAP_APP_VERSION`
      from `games` table** (2026-05-12)
  - Done — schema: `GameConfig` gains `EdgegapAppVersion` field
    (read from `game.yaml.edgegap_app_version`). No DDL change
    needed; the field lives in the JSONB `config` column and is
    parsed into the typed struct at cache refresh. `game.yaml`
    now declares `edgegap_app_version: v8` (current prod pin).
  - Done — fleet_allocator: per-match `appName`/`appVersion`
    resolved from the games cache via `matchGameID`, falling
    back to env-var-supplied `a.appName`/`a.appVersion` when
    bootstrap or fields blank. Eliminates the manual
    `EDGEGAP_APP_NAME`/`EDGEGAP_APP_VERSION` env bump after
    each game-server image push.
  - Open: the CI workflow (`game-server.yml`) doesn't yet
    auto-bump `game.yaml::edgegap_app_version` after a
    successful image push. Until that lands, this value must
    be updated by hand in lockstep with the Edgegap dashboard's
    "active version" pin.
- [x] **3.8 Per-game `matchmaker_rules` from `game.yaml`**
      (2026-05-12)
  - Done — server: `version_check` response gains
    `matchmaker_min_players` / `matchmaker_max_players` /
    `matchmaker_query`, sourced from
    `game.yaml.matchmaker_rules` when the caller supplies a
    known `game_id` in the request payload. Empty values mean
    "no override; client uses compile-time defaults".
  - Done — client: `BackendApiClient.check_version` passes
    `Platform.game_id` in the request and caches the response
    on `server_matchmaker_{min_players,max_players,query}`.
    `nakama_matchmaker_client.gd` reads these via new
    `_resolve_min_count()` / `_resolve_max_count()` helpers and
    a server-aware `_build_query()`; the existing
    `_DEFAULT_MIN_COUNT=2/_DEFAULT_MAX_COUNT=4/
    _DEFAULT_MATCHMAKER_QUERY="*"` constants remain as
    fallbacks.
  - Implementation note: this surface piggybacks on
    `version_check` rather than introducing a new pre-auth
    config RPC. version_check already runs at boot,
    unauthenticated via HTTP key, so this is the cheapest
    place to hang static game-config values that the matchmaker
    needs before a session exists.
- [ ] **3.9 Per-game `protocol_version` pre-check at queue start**
  - Deferred 2026-05-12. fleet_allocator can't access matched
    players' session vars through `runtime.MatchmakerEntry` —
    only ticket properties are visible. To wire this without
    trusting client-supplied values, we'd either (a) have the
    client pass `client_protocol_version` as a ticket property
    and cross-check on the runtime side (still client-trusted,
    but the server can at least short-circuit allocation when
    mismatched), or (b) extend Nakama with a session lookup
    helper. The current client-side boot check
    (`backend_api_client.check_version`) already gates entry
    into the matchmaking flow, so the failed-allocation cost
    today is bounded by whatever clients lie or whose check
    races a deploy. Revisit when this becomes load-bearing.
- [x] **3.10 Per-game `LEGAL_VERSION` from `games` table**
      (2026-05-12)
  - Done — server: `version_check` response gains
    `legal_version` parsed from `game.yaml.legal.legal_version`
    when the caller's payload supplies a known `game_id`.
  - Done — client: `BackendApiClient.check_version` caches the
    response on `server_legal_version`.
    `AuthTokenStore.get_current_legal_version()` returns this
    value when populated, falling back to the in-script
    constant `LEGAL_VERSION = "1.1"` for offline / pre-fetch
    callers. `consent_screen.gd` routes both call sites
    (consent gate + on-accept persist) through the resolver.
  - Implementation note: the compile-time constant is retained
    deliberately so the consent screen works pre-network. The
    contract is "if the server reports a value, use it; else
    use ours". A mismatch surfaces as the consent screen
    forcing a re-consent on first online boot, which is
    annoying but safe. CI doesn't yet guard
    `game.yaml::legal_version` == `LEGAL_VERSION` parity; a
    parallel check to Stage 2.7's protocol_version guard would
    catch the mismatch at PR time.

## Stage 4 — Matchmaking UX

**Goal:** Add the missing UI surface for matchmaking. The audit
calls out near-zero UI for queue status, cancel, errors.

### Tasks

- [x] **4.1 Queue status screen (time waiting, ETA)** (2026-05-12,
      pre-stage)
  - Done pre-stage: `LoadingScreen` shows the matchmaker phase
    (authenticating / queued / searching / expanding_search /
    placing), elapsed seconds, and (when provided) estimated
    remaining via `LOADING.REMAINING`. `NakamaMatchmakerClient`
    emits `matchmaking_progress_updated(phase, elapsed,
    estimated)` on every `_on_elapsed_tick` and on matched.
  - Open sub-item: queue-size estimate. The runtime doesn't
    currently expose matchmaker pool depth — adding it would
    require either a periodic Nakama `ListMatchmakerEntries`
    call or a counter exposed via `version_check`. Not a
    blocker; deferred.
- [x] **4.2 Cancel-queue button** (2026-05-12)
  - Done: new `CancelButton` in
    `src/ui/screens/loading_screen.tscn`. Visible only during
    `queued` / `searching` phases (hidden during
    `authenticating` / `placing` / warmup / when connected /
    when a retry-on-failure is showing). Pressing it calls
    `G.game_panel.client_cancel_matchmaking()` which routes
    through `session_provider.clear_session()` (NakamaMatchmaker
    calls `remove_matchmaker_async(_ticket)`) and reopens the
    lobby screen. 3 new translation keys × 13 locales added.
  - The intentional "Cancel hidden during placing" rule avoids
    cancelling a match the fleet allocator already deployed —
    the other matched peers would still get the deploy, but
    this client would no-show. Hitting Back on the controller
    is still available as an escape hatch (handled higher up).
- [ ] 4.3 Match-found dialog with accept/decline timer (only if
  `matchmaker_rules.require_accept`).
  - Deferred: `game.yaml.matchmaker_rules` doesn't yet expose a
    `require_accept` flag, and there's no runtime support for
    the accept/decline round-trip in `fleet_allocator.go`.
    Both ends would have to land before this UI work pays off.
- [x] **4.4 Connecting-to-server / spinner screen** (2026-05-12,
      pre-stage)
  - Done pre-stage: `LoadingScreen` handles the post-match-
    ready window via `LOADING.WAITING_FOR_PLAYERS` once
    `Netcode.connector.is_connected_to_server` flips true.
    `LOADING.CONNECTING` is the pre-matchmaker fallback.
- [x] **4.5 Version-mismatch error screen with "update" CTA**
      (2026-05-12, pre-stage)
  - Done pre-stage: `src/core/main.gd` opens a confirm dialog
    with `VERSION.UPDATE_REQUIRED` body + `VERSION.CLOSE_GAME`
    CTA when `backend_api_client.check_version` reports a
    server version mismatch. Anonymous web clients reload the
    page with a loop-breaker query param to bust the SW cache.
- [x] **4.6 Allocation-failure / no-servers error screen with retry**
      (2026-05-12)
  - Done: `game_panel._on_matchmaking_failed` now routes through
    `_classify_matchmaking_failure(reason)` which picks one of
    three recoverable translation keys (`LOADING.NO_MATCH_FOUND`
    for timeouts, `LOADING.ALLOCATION_FAILED` for Edgegap /
    fleet allocation paths, `LOADING.CONNECTION_FAILED` for
    socket/disconnect/matchmaker-add failures). Recoverable
    failures pin the loading screen with a retry button;
    fatal cases (auth invalid, match_ready malformed,
    concurrent-session override) keep the old toast + back-to-
    lobby behavior. New `LoadingScreen.show_matchmaking_failure
    (key)` generalizes the old `show_matchmaking_timeout()`
    (kept as a delegating alias for older callers).
- [ ] 4.7 Game-mode picker (reads `matchmaker_rules.modes` from
  `game.yaml`).
  - Deferred: `game.yaml.matchmaker_rules` doesn't yet carry a
    `modes` list. The current single-mode pipeline (one
    matchmaker query, one fleet) keeps working; adding modes
    requires schema + runtime + UI in one go.
- [ ] 4.8 Region picker (optional; reads from Edgegap's region list).
  - Deferred: low priority. Edgegap's
    `Geo-IP → region` selection is automatic via the
    `client_ip` matchmaker property the matchmaker hook
    already reads. A manual override would only help cross-
    region parties, and parties don't yet land on the same
    fleet deploy reliably (Stage 1.1b limitation).

## Stage 5 — Party UX

**Goal:** Make the party flow usable. Per the audit, the original
`PartyLobbyPanel` was a `CanvasLayer` overlay with raw `Button.new()`
widgets, no gamepad nav, AND completely unreferenced (no scene
instantiated it). The 2026-05-12 first wave converted it to the
project's `SidePanel` pattern, wired it to the main settings menu,
and fixed two root-cause bugs that meant party state replication
was effectively dead before any UI work: the polling pipeline never
populated `current_party` (signature mismatch) and Nakama state=3
invitees were silently treated as accepted members.

### Tasks

- [x] **5.1 Refactor `PartyLobbyPanel` to `SidePanel`** (2026-05-12)
  - Rewrote `src/ui/party/party_lobby_panel.gd` as
    `extends SidePanel`; replaced the `CanvasLayer` +
    raw `Button.new()` widgets with `ActionRow` rows
    using the base class's `_row_container` /
    `_set_focus` / `rebuild_row_list` ergonomics.
    Members render in a custom `HBoxContainer` to fit
    the crown + name + status-suffix + kick chevron
    layout that `setup_label()` can't express.
  - New scene `src/ui/party/party_lobby_panel.tscn`
    inheriting from `side_panel.tscn` with seven icon
    exports (accept, decline, start_match, invite,
    leave, kick, open_friends) wired from existing
    `assets/images/gui/` PNGs.
  - `MainMenuPanel` adds a `SETTINGS.PARTY` trigger
    row gated on `not is_anonymous`, with a badge that
    surfaces a pending invite when polling discovers
    one. Uses `friends_icon.png` as a placeholder —
    a dedicated `party_icon.png` is a follow-up
    asset task (TODO in `main_menu_panel.gd`).
  - 11 new translation keys across 13 locales:
    `SETTINGS.PARTY`, `PARTY.MEMBERS`,
    `PARTY.EMPTY_STATE_HINT`,
    `PARTY.HAS_PENDING_INVITES`,
    `PARTY.PENDING_INVITES_HEADER`,
    `PARTY.ACCEPT_INVITE`, `PARTY.DECLINE_INVITE`,
    `PARTY.HANDLE_INVITE_FIRST`,
    `CONFIRM.LEAVE_PARTY`,
    `CONFIRM.DECLINE_INVITE` (the last is overlap
    with the accept-invite confirm copy path).
- [x] **5.2 Party invite acceptance UI** (2026-05-12)
  - The audit framing assumed this was greenfield UX
    work. In practice the existing
    `PartyManager._show_invite_dialog` was correctly
    wired to a ConfirmOverlay path but the
    `invite_received` signal it listens for never
    fired in production because `_on_party_status_
    received` couldn't read invites out of the
    flat-dict emit (see 5.11). After fixing that, the
    legacy toast + ConfirmOverlay path lights up by
    itself — instant notification + one-tap join with
    no panel navigation required.
  - The refactored panel also renders a dedicated
    pending-invites section: per-invite Accept row
    ("Accept invite from %s", checkmark icon) +
    Decline row (X icon, opens a confirm dialog). The
    panel is the canonical surface for handling
    multiple concurrent invites and for users who
    dismissed the popup.
  - Leader name resolution falls back to
    `tr("PARTY.SOMEONE")` when the friends cache
    doesn't have the leader as an accepted friend.
    Cross-game / non-friend leaders therefore show as
    "Someone" in the accept row; revisit when
    `pending_invite` entries can carry
    `leader_display_name` (would require either a
    server-side fan-out from
    `_user_groups[invite].creator_id` →
    `Users` lookup or a client-side
    `list_group_users_async` per invite).
- [x] **5.3 Friend display names in member list** (2026-05-12)
  - Verified already-correct: `PartyApiClient.
    fetch_party_status`'s `list_group_users_async`
    response carries `u.display_name` per-member, and
    the new `PartyLobbyPanel._add_member_row` reads
    it directly with a username → user_id fallback.
    Was de-facto working before this stage; checked
    off explicitly so it doesn't get re-audited.
- [x] **5.4 Real-time party updates via Nakama socket**
      (2026-05-12)
  - Done — server: four new lifecycle hooks
    (`AfterAddGroupUsers`, `AfterJoinGroup`,
    `AfterLeaveGroup`, `AfterKickGroupUsers`) in
    `third_party/snoringcat-platform/runtime/party.go`
    fan out a transient `party_state_changed`
    notification (`code=101`, `persistent=false`) to
    every current member of the affected group plus
    the freshly-invited / -kicked / -left target.
    Each hook gates on the group name starting with
    `party-` so non-party groups don't spam. Wired
    via new `registerPartyGroupHooks` in `main.go`.
    Landed: snoringcat-platform `8069796`; parent bump
    in the same parent commit as the client wiring.
  - Done — client: new
    `src/core/notification_socket_client.gd`
    (`NotificationSocketClient`) maintains a long-
    lived Nakama realtime socket on
    `auth_completed` for non-anonymous users. Emits
    `notification_received(subject, content, id)`
    on every persistent or transient notification +
    `socket_connected` / `socket_disconnected` for
    lifecycle. Exponential-backoff reconnect (1 s →
    30 s cap) on `closed` / `connection_error`.
    Wired into `G` ahead of `PartyManager` and
    `FriendsNotificationPoller` so consumer
    `_ready()` calls can connect to its signals.
  - Done — `PartyManager`: previous 3 s / 10 s
    interval-based polling collapsed to a single
    60 s catch-up tick. Real-time refresh path is
    `_on_socket_notification("party_state_changed",
    ...)` → `_request_immediate_fetch()` (with
    notification-id dedup so a stray duplicate from
    the matchmaker socket doesn't double-fire), and
    `socket_connected` triggers an immediate fetch
    so any party events missed while the socket was
    down get reconciled. Removed
    `_current_poll_interval` + the
    `_ACTIVE_POLL_INTERVAL_SEC` /
    `_IDLE_POLL_INTERVAL_SEC` constants.
  - Done — `FriendsNotificationPoller`: subscribes
    to the same socket and routes
    `party_matchmaking_start` deliveries through a
    shared `_handle_party_matchmaking_start(id,
    content)` helper. The existing 10 s HTTP poll
    keeps running as a fallback for socket-down
    windows; the existing notification-id dedup
    (`_known_party_match_start_ids`) handles dual-
    delivery between paths. This eliminates the
    "up to 10 s join lag for followers" tradeoff
    flagged in the 2026-05-12 decision log when
    1.1b shipped.
  - Compliance test for the new socket dispatch
    still pending; needs the Stage 8.11 socket
    harness + 8.12 multi-session helper to assert
    that party member join/leave fans out to all
    other members in under a second.
- [ ] 5.5 Ready / not-ready toggle per member.
- [ ] 5.6 Leader transfer / kick-and-promote.
- [ ] 5.7 Game-mode selection by leader before queuing.
- [ ] 5.8 Party chat.
- [ ] 5.9 Persist party across launches / reconnects ("rejoin your
  last party?").
- [ ] 5.10 Deep-link / join-by-code invite link.
- [x] **5.11 Pending-invite state in client** (2026-05-12)
  - The audit's "currently faked locally" framing
    undersold the issue: state=3 (Nakama JoinRequest,
    i.e. unaccepted invite) entries from
    `list_user_groups_async` were silently treated as
    full memberships. The viewer ended up with
    `current_party` populated for a party they hadn't
    actually accepted, the never-fired `_show_invite_
    dialog` couldn't recover, and the user's only
    options were "leave the party" (= decline) or
    "wait it out".
  - Fix: `PartyApiClient.fetch_party_status` now reads
    each `UserGroupListUserGroup.state` and splits
    state=3 entries into a `pending_invites` array
    while only state-0/1/2 rows seed `current_party`.
    The emit is wrapped: `{party, pending_invites}` so
    `PartyManager._on_party_status_received`'s pre-
    existing `data.get("party")` lookup (which never
    matched the flat shape) actually finds the data.
    Adds `viewer_role` to the party dict.
  - `PartyManager` gains `has_pending_invite()`,
    `accept_invite()`, `decline_invite()` with
    optimistic local-array updates, and a
    `_request_immediate_fetch()` helper that
    `_on_party_created/joined/kicked/invited` now use
    to backfill members from the next poll rather
    than clobbering `current_party` with the minimal
    server-response shape (a separate latent bug — every
    party signal was effectively emptying
    `current_party` until polling cycled).
  - The `invite_friend` auto-create flow now also
    short-circuits when the caller has a pending
    invite (don't silently leave the invite stranded
    by spinning up a competing party).

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
- **Stage 2.5/2.6 rollout ordering (one-time, post-deploy
  step):** the BeforeAuthenticate* hooks are bootstrap-graceful
  (pass through when `games` is empty), so deploying the new
  runtime to prod by itself does not break clients. The
  expected sequence is: (1) ship the runtime via
  `nakama-runtime.yml`, (2) ship the client release, (3) run
  `scripts/sync-game-config.ps1 -NakamaHttpKey <key>` once to
  populate the `games` table. After step 3 the hooks flip to
  strict; any client that authenticated against the runtime
  *before* step 2 (i.e., with no game_id in vars) will be
  rejected on next RPC and forced to re-authenticate. The
  client's auto-refresh path handles that path transparently
  because we pass vars on refresh too.

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
- **2026-05-12:** Stage 2 front half landed (2.1/2.2/2.3/2.4/2.7).
  Three design calls worth recording for the back half:
  - **Sync model: RPC-push, not filesystem-read.** The
    `PLATFORM_ARCHITECTURE.md` original framing had
    `per_game_config.go` read each game's `game.yaml` from the
    filesystem at module init. That's impractical — the Nakama
    container has no access to game repos. Instead, each game's
    release pipeline POSTs its config to a server-to-server
    `register_game` RPC. Updated the architecture doc to
    match. Bonus: per-game registration becomes a deploy-time
    event Nakama can log, not a startup-only operation.
  - **Cache invalidation: write-through only, no TTL.** Cache
    is refreshed on every `register_game` write. No background
    refresh, no TTL. Sufficient until out-of-band `UPDATE games
    ...` becomes a real workflow (games-admin console / dashboard).
  - **`legal_version` kept as the string `"1.1"`.** The
    architecture doc's example uses an integer, but the live
    constant in `auth_token_store.gd` is `"1.1"`. Game.yaml is
    the source of truth — diverging it from the code would
    invite the divergence the file is supposed to prevent.
    Stage 3.10 (read `legal_version` from games table) will
    decide the canonical type then.
- **2026-05-12:** Stage 2.4's CI wiring deferred. The sync
  script ships and works locally, but adding a `sync-game-
  config.ps1` step to `nakama-runtime.yml` needs a new
  `NAKAMA_HTTP_KEY` GitHub secret. Doing it in this session
  would either (a) ship a workflow that 401s until the secret
  exists, or (b) gate the step behind an `if: secrets.X != ''`
  guard that silently skips. Both are worse than just running
  the script manually after the Stage 2 deploy, which is also
  the only way to populate the (initially empty) `games` table.
  Re-revisit once the secret is configured.
- **2026-05-12:** Stage 3 substantially landed (3.1, 3.2, 3.3,
  3.4, 3.6, 3.7, 3.8, 3.10 — 8/10 tasks). Five design calls
  worth recording:
  - **Presence key, not collection, carries game_id.** The
    audit's literal proposal was
    `collection="presence/{game_id}", key="current"`. We did
    `collection="presence", key="{game_id}/current"` instead.
    Same uniqueness guarantee on the (collection, key,
    user_id) primary key; better ergonomics for the cascade
    scrub and any future `StorageList(collection="presence",
    user=X)` call that wants every game's presence row for a
    user in one read.
  - **`match_metadata` collection threads game_id to
    match_end.** The game server (Godot, in-container) doesn't
    know its game_id — it just runs whatever Edgegap booted.
    We need game_id at `match_end` time to scope the
    leaderboard write. Rather than push the value to the game
    server (and re-introduce a manual env-var coupling
    Stage 3.7 just removed), fleet_allocator stashes
    `{game_id, allocated_at}` in a new `match_metadata`
    storage row at deploy time. `match_end` reads it back.
    Missing rows fall back to bare leaderboard ID so a rollout
    doesn't drop results.
  - **Mixed-game matchmaker pool defaults: dominant vote, not
    reject.** Until Stage 3.8's query filter lands (the
    current query is still `*`), the pool can theoretically
    contain players from different games. The fleet allocator
    counts game_id votes from matchmaker entries' properties
    and picks the highest-vote winner; ties break
    alphabetically. Unregistered game_ids are dropped before
    voting. The alternative (reject mixed-game matches) felt
    worse — better to write a leaderboard record to *some*
    game's board than to drop a real player's result. The
    query filter (a future 3.8 follow-up or Stage 3.9 rev)
    will eliminate the ambiguity at the source.
  - **Static game config piggybacks on `version_check`, not a
    new pre-auth RPC.** `version_check` already runs at boot
    over the HTTP-key (unauthenticated) path. Stage 3.10's
    legal_version, Stage 3.8's matchmaker rules, and Stage
    3.7's effective Edgegap pins all flow through the
    `version_check` response now. Single round-trip; the
    client caches everything on `BackendApiClient`. The
    alternative (`get_public_game_config` RPC) would be
    cleaner long-term, but adds a second pre-auth surface
    without a clear caller story.
  - **3.5 and 3.9 deferred deliberately, not blocked.** 3.5
    (settings split) needs a global-vs-per-game taxonomy
    decision plus a one-shot migration; the existing single-
    blob save path keeps working and there's no user-visible
    bug. 3.9 (pre-allocate protocol check) needs a way for the
    matchmaker hook to read session vars off matchmaker
    entries, which Nakama-common doesn't expose. The client-
    side boot version_check already gates entry into the
    matchmaking flow, so the cost of a stale-client mismatch
    today is one failed allocation. Both items are clearly
    Stage 3-flavored but neither is on the critical path to
    Stages 4–6.
- **2026-05-12:** Stage 4 landed 4.2 + 4.6. Three decisions
  worth recording:
  - **"Recoverable failure" is a closed allowlist, not a
    catch-all.** `_classify_matchmaking_failure` returns a
    translation key only for substring matches against three
    bins (timeout / allocation-shaped / network-shaped).
    Anything else (auth invalid, match_ready malformed,
    concurrent-session override) still toasts + bounces to
    lobby. The alternative ("anything not-fatal is
    recoverable") would let the user retry into a loop on
    deterministic server-side bugs. The classifier is small
    and easy to extend when new failure shapes come up.
  - **Cancel button hides during `placing` phase.** Once the
    matchmaker has matched and `fleet_allocator.go` is
    waking up an Edgegap deploy, cancelling client-side just
    no-shows the deploy for the other matched peers. Hiding
    the button is the cheapest correctness fix; a fuller
    answer (notify the runtime so it tears down a deploy
    with no remaining peers) is Stage 7.2 territory.
  - **`LoadingScreen.show_matchmaking_failure(key)` is the new
    surface; `show_matchmaking_timeout()` delegates.**
    `game_panel` was already calling `show_matchmaking_timeout`
    based on a substring sniff; rather than introduce a
    parallel `show_matchmaking_failure` API and migrate the
    one caller, the old method now forwards to the new one
    with `LOADING.NO_MATCH_FOUND`. Single chokepoint for any
    future failure surface (e.g. "match-decline timed out"
    if 4.3 ever lands).
- **2026-05-12:** Stage 5 first wave (5.1/5.2/5.3/5.11)
  surfaced and fixed two latent bugs in the party data
  flow that meant party state replication had never
  actually worked end-to-end:
  - **`fetch_party_status` emit/receive shape mismatch.**
    `PartyApiClient.fetch_party_status` was emitting the
    bare party Dict; `PartyManager._on_party_status_
    received` was reading `data.get("party")` which
    always returned null. The else branch (no active
    party) ran on every poll, clearing `current_party`.
    Parties only persisted in the client because the
    party_created/joined/etc. signal handlers kept
    re-setting it — but those handlers had their own
    bug (they ran `current_party = data.get("party",
    {})` and the emit payload had no "party" key
    either), so `current_party` was effectively
    cleared on every party event and never repopulated
    until the next user action.
  - **State=3 entries treated as active membership.**
    Nakama exposes a closed-group invite as the
    invitee being associated with the group in state=3
    (JoinRequest). The old `fetch_party_status`
    iterated user_groups without checking state, so
    invitees got `current_party` populated as if they
    were a real member. The `invite_received` signal
    + `_show_invite_dialog` ConfirmOverlay flow was
    wired but never fired because the dispatch path
    (else-branch of the receiver) only runs when the
    party dict is empty, which never happened.
  - Both fixes are necessary to make 5.1's panel work
    at all — without them the panel renders nonsense.
    Bundled together for that reason; the audit had
    them as separate Stage 5 tasks (5.1, 5.2, 5.11)
    that turned out to share a fix surface.
  - **Main Menu icon: friends_icon as placeholder.**
    The CLAUDE.md "no buttons without icons" rule
    applies; no party_icon asset exists yet, and the
    refactor needed an entry point to validate
    reachability. Chose to reuse `friends_icon.png`
    in the meantime with a TODO so the work isn't
    blocked on an art task. Replace when a dedicated
    icon lands.
  - **Compliance test for the new shape still
    pending.** The fetched-emit shape (`{party,
    pending_invites}`) and the state=3 split are
    untested today; needs the Stage 8.11 socket
    harness + 8.12 multi-session helper to exercise
    leader-invites-invitee + invitee-accepts in a
    repeatable suite. The fixes are validated by
    code inspection + load-time smoke (Godot opens
    without parse errors and the autoload chain
    drives auth refresh cleanly), not by an
    automated test.
- **2026-05-12:** Stage 5.4 landed. Four decisions
  worth recording:
  - **Transient notifications, not persistent.**
    `party_state_changed` uses `persistent=false`, so
    Nakama doesn't store the message — it's delivered
    only to currently-open sockets and discarded
    otherwise. Persistent (the path
    `party_matchmaking_start` uses) would accumulate
    rows in every party member's notification inbox
    on every membership change, and the value of that
    inbox row is near-zero because the client always
    refetches state on socket reconnect anyway. The
    catch-up fetch on `socket_connected` + the 60 s
    catch-up poll absorb any missed events.
  - **Group-lifecycle hooks, not a custom RPC for
    every party op.** The audit's framing implied
    swapping `party_api_client.gd`'s direct
    `add_group_users_async` / `join_group_async` /
    etc. calls for server-side RPCs that bundle the
    Nakama write with the fan-out. Nakama already
    provides AfterX hooks for these specific
    operations; using them keeps the client API
    surface unchanged and means the fan-out
    automatically picks up any future caller (e.g.,
    a future games-admin console managing parties
    via direct Nakama API). Tradeoff: the hook
    fires after the Nakama write commits, so a
    failed write doesn't fan out. Acceptable —
    failure cases don't need notifications.
  - **One shared long-lived socket, not per-feature
    sockets.** `NotificationSocketClient` is the
    canonical bus; `PartyManager` and
    `FriendsNotificationPoller` both consume from
    it. The pre-existing
    `NakamaMatchmakerClient` socket remains
    separate (short-lived, scoped to active
    matchmaking) — folding it in would have been a
    larger refactor without paying back today. Two
    sockets to the same Nakama instance receive the
    same persistent-notification stream, so each
    consumer dedups by notification id (cheap, and
    `_known_party_match_start_ids` already existed
    on the HTTP-poll path).
  - **Catch-up poll stays, but at 60 s.** Removing
    polling entirely would leave a window between
    socket drop and reconnect where transient
    `party_state_changed` events are lost forever
    (Nakama doesn't replay non-persistent
    notifications on reconnect). The 60 s poll is
    cheap, never user-visible in latency (the
    `socket_connected`-triggered fetch handles the
    immediate-reconnect case), and provides a safety
    net that doesn't depend on the socket-event
    semantics being perfect. The 2026-05-12 1.1b
    decision log entry noting "Revisit if Stage 5.4
    lands a socket bus we can reuse" is now closed:
    `FriendsNotificationPoller` routes
    `party_matchmaking_start` over the new bus, so
    the 10 s join lag for party followers is gone in
    the happy path while the HTTP poll continues to
    cover socket-down windows.
- **2026-05-12:** Stage 2.5/2.6 closed out the foundation.
  Four design calls worth recording:
  - **`game_id` lives in Nakama's `vars` map, not as a
    top-level JWT claim.** The audit framing implied minting
    a custom claim into the JWT, but the Nakama session token
    has a fixed shape (`uid`/`tid`/`exp`/etc.). The
    platform-provided extension point is the `vars` field on
    every `Authenticate*Request`, which Nakama bakes into
    the issued session and exposes server-side via
    `RUNTIME_CTX_VARS`. So game_id rides there. The semantic
    effect ("session carries game_id, every RPC can read it")
    is identical; the encoding differs.
  - **Bootstrap-graceful auth hooks.** Both
    `validateGameIDInVars` (auth-time) and `requireGameID`
    (RPC-time) pass through unchecked when the `games` cache
    is empty. This makes the rollout safe: deploy the runtime
    first, deploy the client second, run sync-game-config
    third — at no point are existing clients locked out. Once
    the first game registers, validation flips to strict
    automatically. Cost: a small window of "trust whatever
    the client sent" right after a from-scratch deploy. Worth
    it for the simpler rollout story.
  - **RPC factory pattern over a package-level `games` global.**
    Each stateful RPC that needs the cache is now registered
    via `xxxRpcFactory(games)` that returns a closure. The
    extra ceremony makes the dependency explicit at
    registration time, which both reads better and makes
    future unit tests (Stage 8.x) easy to inject mocks into
    without touching package globals.
  - **`Platform.initialize()` wired from `global.gd._ready()`.**
    The autoload's `game_id` field is now populated in
    hopnbop. The actual `Platform.{auth,friends,...}` API
    surface is still empty (Stage 6 extraction is later); for
    now this just lets the compliance helper read
    `Platform.game_id` instead of hardcoding "hopnbop". The
    `api_base_url` arg is set to the live Nakama URL even
    though nothing reads it yet — `Platform.initialize` asserts
    it's non-empty, so we satisfy the contract.

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
