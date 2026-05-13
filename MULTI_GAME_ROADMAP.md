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

- **Current focus:** Stage 6 SDK extraction continuing. 6.2
  landed 2026-05-12, completing the auth extraction the
  previous 6.4/6.7 wave was waiting on. `src/core/auth_client.gd`
  is gone; the new `PlatformAuthApiClient` lives in
  `addons/snoringcat_platform_client/core/auth_api_client.gd`
  (mirrored in the submodule). The Nakama host / port / scheme /
  server_key / http_key constants — Snoring Cat platform
  infrastructure, not game-specific — moved out of the auth
  class entirely onto `Platform.{nakama_host, nakama_port,
  nakama_scheme, nakama_server_key, nakama_http_key}` and are
  passed in via `Platform.initialize`. The OAuth surface
  (`oauth_callback_url`, `google_token_broker_url`,
  `google_oauth_client_id`, `facebook_oauth_client_id`) is also
  on Platform now, fed in from `settings.tres` at boot. NakamaClient
  lazy-creation lives on `Platform.get_nakama_client()` so any
  addon subsystem that needs the client reads it from the same
  singleton; `Platform.get_nakama_base_url()` replaces the static
  `AuthClient.get_nakama_base_url()` helper. The post-login cloud-
  settings fetch (previously called from inside `_handle_auth_
  success`) moved into a `Platform.auth.auth_completed` listener
  in `global.gd._ready()` so the addon class doesn't reach back
  into `G.settings_cloud_sync`. ~70 callsites across 14 files
  migrated via sed: `G.auth_client.X` → `Platform.auth.X`,
  `G.auth_client._get_nakama_client()` → `Platform.get_nakama_
  client()`, `G.auth_client._build_session_from_store()` →
  `Platform.build_session_from_store()`, and the static
  `AuthClient.{Provider, PLATFORM_PROVIDERS, is_web_platform,
  get_platform_provider, get_nakama_base_url, get_nakama_http_
  key}` references rewrote to `PlatformAuthApiClient.*` /
  `Platform.*`. Editor pass refreshed
  `.godot/global_script_class_cache.cfg` with the new
  `PlatformAuthApiClient` entry; headless boot green (zero parse
  errors, autoloads initialize cleanly, the boot-time
  `update_and_get_presence` RPC fires against live Nakama via
  the new path with `game_id=hopnbop` in the JWT vars). Next
  focus: Stage 6.5 (`party_api_client.gd` + `party_manager.gd` →
  `Platform.party.*`) or Stage 6.6 (matchmaker + edgegap server
  provider → `Platform.matchmaking.*`). Both are now unblocked.
- **Last updated:** 2026-05-12.
- **Stages complete:**
  - Stage 0 (platform infra extraction — including the kickoff
    verification items 0.8 and 0.9).
  - Stage 2 (all seven tasks shipped 2026-05-12).
- **Stages in progress:**
  - Stage 1 — all five tasks (1.1a, 1.1b, 1.2, 1.3, 1.4, 1.5)
    have working code shipped. 1.5 UX polish (type-the-word
    confirmation + grace-period messaging) now also shipped via
    the new `DeleteAccountConfirmPanel`. Compliance-test green-
    light still gated on a Stage 8 socket harness for multi-user
    party scenarios.
  - Stage 3 — 8/10 tasks shipped 2026-05-12 (3.1, 3.2, 3.3,
    3.4, 3.6, 3.7, 3.8, 3.10). Open: 3.5 settings split
    (needs global-vs-per-game taxonomy decision) and 3.9
    protocol-version pre-check (needs matchmaker-entry session-
    vars access pattern).
  - Stage 4 — 5/8 tasks shipped 2026-05-12 (4.1, 4.2, 4.4,
    4.5, 4.6). Open: 4.3 (needs `matchmaker_rules.require_accept`
    in game.yaml), 4.7 (needs `matchmaker_rules.modes` schema),
    4.8 (region picker; optional, needs Edgegap region list).
  - Stage 5 — 10/11 tasks shipped 2026-05-12 (5.1, 5.2, 5.3,
    5.4, 5.5, 5.6, 5.8, 5.9, 5.10, 5.11). Open: 5.7 game-mode
    picker (deferred until game.yaml schema gains a `modes`
    list, mirrored by Stage 4.7).
  - Stage 6 — 5/11 tasks shipped 2026-05-12 (6.1 subsystem
    slots + register_subsystem helper, 6.2 auth_client →
    PlatformAuthApiClient + nakama / OAuth constants on
    Platform, 6.3 auth_token_store reconciliation + Platform.
    token_store migration across 22 files, 6.4
    PlatformFriendsApiClient, 6.7 PlatformPresenceApiClient
    split out from the old friends client). Open: 6.5
    (party_api_client + party_manager), 6.6 (matchmaker +
    edgegap_server_provider), 6.8 (settings_cloud_sync), 6.9
    (game_session_manager), 6.10 (mass consumer migration —
    partially done as a side-effect of each extraction), 6.11
    (screen templates).
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
   │   (5.4); ready toggle + all-ready gate (5.5);
   │   leader transfer via party_transfer_leadership RPC +
   │   party_leader storage override (5.6); party chat over the
   │   same notification socket (5.8); boot-time "still in a
   │   party?" rejoin prompt (5.9); join-by-code with two new
   │   server RPCs (5.10).
   │   Open: 5.6 leader transfer, 5.7 game-mode picker.
   └─→ Stage 6 (in progress, 2026-05-12) — Platform SDK extraction.
       6.1 subsystem slots, 6.3 auth_token_store reconciliation
       (22-file migration to Platform.token_store), 6.4
       PlatformFriendsApiClient, and 6.7 PlatformPresenceApiClient
       all shipped. Remaining: 6.2 auth, 6.5 party, 6.6
       matchmaking, 6.8 settings, 6.9 session, 6.10 consumer
       migration, 6.11 screens.
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
  - **UX polish shipped 2026-05-12** (second pass):
    - New `DeleteAccountConfirmPanel` (extends `SidePanel`,
      pattern lifted from `AddFriendPanel`). `DeleteAccountRow`
      now pushes this sub-panel via `manager.push_panel(...)`
      instead of calling `open_confirm_dialog`. The original
      single-step confirm dialog is gone.
    - Sub-panel renders three labels (header + grace-period
      body + type-the-word prompt) above a `TextInputRow` that
      accepts the localized verify word (`CONFIRM.DELETE_
      ACCOUNT_VERIFY_WORD`, uppercased for Latin-script locales
      and unchanged for non-Latin scripts where casing is a no-
      op). The Confirm Deletion `ActionRow` stays disabled
      until the input matches.
    - Success toast switched from `TOAST.ACCOUNT_DELETED`
      ("Account deleted") to `TOAST.ACCOUNT_DELETE_QUEUED`
      ("Account scheduled for deletion. Sign in within 30 days
      to cancel.") so the user sees the grace-period framing.
      `TOAST.ACCOUNT_DELETED` is retained in the CSV for
      historical strings still referenced from older entries
      (e.g. analytics dashboards), but no live code path emits
      it anymore.
    - 5 new translation keys × 13 locales: `CONFIRM.DELETE_
      ACCOUNT_DETAIL`, `CONFIRM.DELETE_ACCOUNT_TYPE_PROMPT`,
      `CONFIRM.DELETE_ACCOUNT_VERIFY_WORD`, `CONFIRM.DELETE_
      ACCOUNT_CONFIRM_BUTTON`, `TOAST.ACCOUNT_DELETE_QUEUED`.
      CSV verified at 14 fields per line.

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
- [x] **5.5 Ready / not-ready toggle per member**
      (2026-05-12)
  - Done — server: new `party_set_ready` RPC in
    `third_party/snoringcat-platform/runtime/party.go`.
    Validates session + game_id, rejects pending invitees
    (state=3), then writes / deletes the caller's row at
    `(party_ready, party_id, user_id)` with
    PermissionRead=2/Write=0 (server-only write so the
    RPC is the sole entry point and the fan-out
    notification can't be bypassed). Reuses the existing
    `party_state_changed` subject with a new
    `partyEventReadyChanged` event tag.
  - Done — server: AfterJoinGroup / AfterLeaveGroup /
    AfterKickGroupUsers now also call
    `clearPartyReadyRows` so any roster change drops the
    party's ready rows. The deliberate omission is
    AfterAddGroupUsers — inviting a friend doesn't
    change the active roster (the invitee is state=3
    until they accept), so the existing members' readies
    are preserved.
  - Done — client: `party_api_client.gd` `fetch_party_status`
    follows the list_group_users response with a batched
    `read_storage_objects_async` for every active
    member's ready row and merges `ready: bool` into
    each member dict. `set_ready(party_id, ready)`
    method calls the new RPC. `set_ready` is best-effort
    on the read path: a storage-read failure surfaces
    via `request_failed` but still emits the party so
    the panel can render with `ready=false` everywhere.
  - Done — client: `PartyManager` gains `set_ready`
    (optimistically patches the local member entry so
    the UI flips immediately rather than waiting on the
    RPC round-trip + notification refetch),
    `is_self_ready`, `all_active_members_ready`.
  - Done — UI: `PartyLobbyPanel` renders a Mark Ready /
    Mark Not Ready toggle ActionRow for every viewer
    (not just the leader) with checkmark + x icons.
    Each active member's row gets a green `[Ready]`
    badge once they toggle on. Leader's Start Match
    button shows `PARTY.WAITING_FOR_READY` and stays
    disabled until every active member is ready (in
    addition to the pre-existing >= 2 active-member
    threshold). The toggle is hidden during
    `status="matchmaking"` because changing ready mid-
    queue doesn't affect the already-enqueued ticket.
  - 4 new translation keys × 13 locales: `PARTY.READY`,
    `PARTY.MARK_READY`, `PARTY.MARK_NOT_READY`,
    `PARTY.WAITING_FOR_READY`. CSV verified — every
    line still has 14 fields.
  - Cascade story: `account.go`'s delete path scans
    every collection for user-owned rows and deletes
    them, so per-member ready rows are scrubbed
    automatically on `delete_account`. No additional
    code change needed.
  - Known limitation: there's no compliance test for
    the ready toggle yet (Stage 8.11/8.12 socket
    harness still pending). The flow is verified by
    code inspection + headless Godot autoload boot.
- [x] **5.6 Leader transfer / kick-and-promote** (2026-05-12)
  - Done — server:
    `third_party/snoringcat-platform/runtime/party.go` gains
    a new `party_leader` storage collection storing the
    optional `{user_id, transferred_at, transferred_by}`
    override row at `(party_leader, party_id, "")`,
    server-owned (UserID="") with PermissionRead=2 (clients
    fold it into their local view of leader_id) /
    PermissionWrite=0 (the transfer RPC is the sole mutation
    path). `resolvePartyLeader` reads the override and falls
    back to `group.CreatorId` when absent, keeping
    pre-existing parties working without migration. The new
    `party_transfer_leadership` RPC validates that the caller
    is the current leader, confirms the target is an active
    member (non-pending), writes the override, promotes the
    target to Nakama group-admin via `GroupUsersPromote` so
    the client's direct-Nakama kick / invite paths work for
    the new leader, then fans out `party_state_changed` with
    the `leader_changed` event tag. Previous leader is NOT
    demoted (Nakama can't demote the creator, and an
    ad-hoc demote of a non-creator previous leader would
    prevent them ever taking leadership back via another
    transfer).
  - Done — server: `partyStartMatchmakingRpc`'s leader
    check now consults `resolvePartyLeader` instead of
    comparing `group.CreatorId` directly, so a
    transferred-leader can start matchmaking.
    AfterLeaveGroup / AfterKickGroupUsers also call a new
    `autoTransferIfLeaderDeparted` helper: when the current
    leader leaves or is kicked, the runtime picks the first
    remaining active member, writes a new override pointing
    at them, and promotes them to admin. Covers manual
    leave, kicks, and the account-delete cascade
    (`account.go`'s flow calls `GroupUserLeave` which fires
    AfterLeaveGroup). When no remaining active members
    exist (everyone gone), the override row is dropped so
    a future reuse of the same `party_id` doesn't read a
    stale override.
  - Done — client: `PartyApiClient.fetch_party_status`
    batches the `(party_leader, party_id, "")` row into the
    existing `read_storage_objects_async` call alongside
    each member's ready row, then folds any returned
    `{user_id}` into `party["leader_id"]`, replacing the
    creator-id default. Per-member `role` and the viewer's
    `viewer_role` are recomputed against the resolved
    leader_id so the panel's crown / leader-only
    affordances reflect the override even when the original
    Nakama state hasn't been promoted (e.g., the new leader
    is still state=2 Member from Nakama's perspective).
    New `transfer_leadership(party_id, target_user_id)`
    method calls the RPC; new
    `party_leader_transferred(data)` signal echoes the
    response so consumers can react.
  - Done — client: `PartyManager.transfer_leadership(
    target_player_id)` passthrough that no-ops when the
    caller isn't the leader or the target is invalid /
    self.
  - Done — UI: `PartyLobbyPanel` renders a "Make %s the
    leader" ActionRow per eligible target (non-self, non-
    pending active member) when the viewer is the leader
    and the party isn't matchmaking. Tap opens a confirm
    dialog ("Make %s the new party leader? You will no
    longer be the leader."). On success the panel surfaces
    a toast ("Made %s the new leader") — the dropping of
    the leader-only rows on the next refetch would
    otherwise be silent. Leadership-transfer rows use
    `leaderboard_icon.png` as a placeholder icon; a
    dedicated promote icon is a small follow-up asset
    task.
  - 4 new translation keys × 13 locales: `PARTY.MAKE_LEADER`,
    `PARTY.MAKE_LEADER_CONFIRM`, `PARTY.LEADERSHIP_TRANSFERRED`,
    `CONFIRM.TRANSFER_LEADERSHIP`. CSV verified at 14 fields
    per line.
  - Compliance test for the transfer flow still pending;
    needs the Stage 8.11 socket harness + 8.12 multi-
    session helper.
- [ ] 5.7 Game-mode selection by leader before queuing.
  - Deferred 2026-05-12. Needs `matchmaker_rules.modes`
    schema in `game.yaml` plus per-mode matchmaker query /
    fleet routing in the runtime (mirrors Stage 4.7 with a
    UI surface). Single-mode pipeline keeps working; no
    user-visible blocker.
- [x] **5.8 Party chat** (2026-05-12)
  - Done — socket: `NotificationSocketClient` extended with
    `join_chat_group(group_id) -> channel_id`,
    `leave_chat(channel_id)`, `send_chat_message
    (channel_id, content)`, and a new
    `received_channel_message(message)` signal that
    flattens Nakama's `ApiChannelMessage` into a dict
    consumers can read without depending on the SDK types.
    The chat connection rides the long-lived notification
    socket — no second socket.
  - Done — manager: `PartyManager` owns `chat_channel_id`
    + `chat_history` (capped at 200 messages, oldest
    dropped). `_reconcile_chat_subscription()` runs on
    every `_on_party_status_received` and on
    `socket_connected` to ensure we're subscribed to the
    current party's channel (and to switch when the party
    changes). `load_chat_history()` async-fetches the last
    50 messages from the HTTP API on subscription so a
    freshly-opened panel has backlog. Sends route through
    `send_party_chat_message(text)` with a 500-char
    defensive cap.
  - Done — UI: new `PartyChatPanel` (`SidePanel` subclass).
    Renders message rows above a `TextInputRow` +
    Send `ActionRow`. Message rows are non-focusable
    `VBoxContainer`s with a sender header + autowrapped
    body label, so the SidePanel U/D navigation skips them
    and lands on the input/send pair. Auto-scrolls to the
    bottom on every render. New "Open Chat" row in
    `PartyLobbyPanel` triggers the push.
  - 7 new translation keys × 13 locales: `PARTY.OPEN_CHAT`,
    `PARTY.CHAT_HEADER`, `PARTY.CHAT_PLACEHOLDER`,
    `PARTY.CHAT_SEND`, `PARTY.CHAT_EMPTY`,
    `PARTY.CHAT_SEND_FAILED`. CSV verified at 14 columns
    per line.
- [x] **5.9 Persist party across launches** (2026-05-12)
  - Done — `PartyManager` tracks
    `_initial_party_check_done` (cleared on every
    `auth_completed`) and `_local_party_action_taken`
    (set in `_on_party_created` /
    `_on_party_joined`). On the first
    `_on_party_status_received` since auth, if the user
    is in an active party and *didn't* just create or
    join one this session, `_show_rejoin_dialog(party)`
    pops a `ConfirmOverlay` with accept = stay (no-op),
    reject = leave.
  - Pending invites take priority — the rejoin prompt
    suppresses when `pending_invites` is non-empty so
    the user resolves invites via their own dialog
    flow first. The dialog re-fetches `party_id` off
    `current_party` at button-tap time to defend
    against the user already leaving the party
    through some other surface between fetch and tap.
  - 2 new translation keys × 13 locales:
    `PARTY.REJOIN_PROMPT` and `PARTY.CONTINUE`.
- [x] **5.10 Deep-link / join-by-code** (2026-05-12)
  - Done — server: two new client-session RPCs in
    `third_party/snoringcat-platform/runtime/party.go`:
    - `party_get_invite_code`: any active member of the
      party can fetch (or generate on first call) the
      shareable 6-character code. Lazy-generates on
      demand; reuses on subsequent calls via a
      reverse-lookup row keyed by `party:<party_id>`.
    - `party_join_by_code`: validates the code,
      confirms the party still exists and has room,
      then calls `nk.GroupUsersAdd(ctx, "",
      groupID, []string{callerID})` — empty callerID
      invokes server authority, bypassing the
      closed-group invite-and-accept dance and adding
      the caller as state=2 directly.
    - Bidirectional storage rows in a new
      `party_invite_codes` collection, both
      server-owned (UserID="") with PermissionRead=0 /
      PermissionWrite=0 so the RPCs are the only
      access path. Forward row collision retries
      bounded at 5; alphabet excludes I/O/0/1 for
      readability. Stale rows (party disbanded since
      issuance) cleaned lazily on
      `party_join_by_code`.
  - Done — client RPC layer: `PartyApiClient` gains
    `get_invite_code(party_id)` and `join_by_code
    (code)` plus two new signals
    (`party_invite_code_received`,
    `party_invite_code_redeemed`). The redeem path
    also fires `party_joined` so `PartyManager`'s
    existing state machine takes over.
  - Done — `PartyManager`: passthrough
    `request_invite_code()` and
    `join_party_by_code(code)`.
  - Done — UI: `PartyLobbyPanel` empty state now
    surfaces a "Join by Code" row that pushes a new
    `JoinByCodePanel` (text input + length-gated
    Join button, modeled on `AddFriendPanel`).
    Active-party state surfaces a "Show Invite Code"
    row that flips to displaying the code once
    fetched; pressing it again copies to the
    clipboard via `DisplayServer.clipboard_set`.
  - 8 new translation keys × 13 locales:
    `PARTY.JOIN_BY_CODE`, `PARTY.JOIN_BY_CODE_HINT`,
    `PARTY.ENTER_CODE`, `PARTY.SHOW_INVITE_CODE`,
    `PARTY.FETCHING_INVITE_CODE`,
    `PARTY.INVITE_CODE_LABEL`,
    `PARTY.INVITE_CODE_COPIED`,
    `PARTY.JOINED_VIA_CODE`.
  - Deferred: the literal "deep-link" half of the
    audit's framing — a URL like
    `https://hopnbop.net/?code=ABC123` that pre-fills
    the join-by-code panel on web boot — isn't wired
    yet. The code surface alone covers the
    Discord-share-a-code use case, which is the
    primary value. URL handling requires touching
    the web export's `index.html` patch and the
    Godot bootstrap; deferred for a separate pass.
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

- [x] **6.1 Define `Platform.{auth,account,friends,party,
  matchmaking,presence,settings,session,screens}` subsystem
  property slots** (2026-05-12).
  - Done — submodule: added nine null-default subsystem slots to
    `addons/snoringcat_platform_client/core/platform.gd`, plus
    a `register_subsystem(subsystem_name, value)` helper the
    consuming game calls during bootstrap to wire its own
    implementations into each slot once an extraction lands.
    The helper validates against a closed allowlist of known
    names so typos surface at the call site rather than turning
    into silent nulls. Re-registration is allowed (last call
    wins) so a future test harness can swap an implementation
    without restarting.
  - All slots default to null; consuming code uses null-guards
    while extractions are pending (`if Platform.friends != null:
    Platform.friends.foo(...)` — falls back to `G.*` until the
    Stage 6.x for that slot lands).
- [x] **6.2 Extract `auth_client.gd` → `Platform.auth.*`;
      parameterize hardcoded Nakama + OAuth hosts** (2026-05-12).
  - Done — submodule: new
    `addons/snoringcat_platform_client/core/auth_api_client.gd`
    with `class_name PlatformAuthApiClient`. Surface: signals
    (`auth_completed`, `link_completed`, `unlink_completed`,
    `delete_completed`, `merge_completed`, `export_completed`,
    `guest_jwt_obtained`, `auth_status_changed`,
    `version_mismatch`), `Provider` enum + `PLATFORM_PROVIDERS`
    constant, static `is_web_platform()` /
    `get_platform_provider()`, instance methods
    `login_with_provider`, `submit_platform_token`,
    `login_anonymous`, `get_guest_jwt`, `refresh_token`,
    `link_provider`, `submit_platform_link`, `unlink_provider`,
    `confirm_merge`, `cancel_merge`, `delete_account`,
    `export_player_data`. OAuth flows (loopback / popup / platform-
    token) all preserved verbatim. `G.log.print` →
    `print()`, `G.log.warning` → `push_warning()` so the addon
    has no game-side dependencies.
  - Done — platform.gd: new fields `nakama_host`,
    `nakama_port`, `nakama_scheme`, `nakama_server_key`,
    `nakama_http_key`, `oauth_callback_url`,
    `google_token_broker_url`, `google_oauth_client_id`,
    `facebook_oauth_client_id`. New `get_nakama_base_url()`
    helper. New `get_nakama_client()` lazily creates the
    NakamaClient on first access and caches it on
    `Platform.nakama_client` (the same field every other addon
    subsystem reads). `Platform.initialize()` accepts all new
    keys.
  - Done — game-side bootstrap: `global.gd._enter_tree()` now
    passes the new keys to `Platform.initialize()` (Nakama host
    pinned to `nakama.snoringcat.games`, server_key + http_key
    are the same "soft secrets" as before; OAuth keys read from
    `settings.tres`). Replaced
    `auth_client = AuthClient.new()` with
    `var auth := PlatformAuthApiClient.new(); add_child(auth);
    Platform.register_subsystem("auth", auth)`. Replaced eager
    `auth_client._get_nakama_client()` with
    `Platform.get_nakama_client()`. Game-side `auth_client`
    field on `G` removed.
  - Done — post-login cloud-settings fetch: previously called
    from inside `_handle_auth_success`, moved into a
    `Platform.auth.auth_completed` listener in
    `global.gd._ready()` (gated on success + non-null
    `settings_cloud_sync`). Keeps the addon free of
    `G.settings_cloud_sync` reach-back.
  - Done — mass migration: ~70 callsites across 14 files via
    sed, in this order so the catch-all doesn't capture
    pre-specific patterns: (1)
    `G.auth_client._build_session_from_store()` →
    `Platform.build_session_from_store()`, (2)
    `G.auth_client._get_nakama_client()` →
    `Platform.get_nakama_client()`, (3) `G.auth_client` →
    `Platform.auth` (catch-all),
    (4) `AuthClient.get_nakama_base_url()` →
    `Platform.get_nakama_base_url()`,
    (5) `AuthClient.get_nakama_http_key()` →
    `Platform.nakama_http_key`,
    (6/7/8/9) `AuthClient.{is_web_platform,
    get_platform_provider, PLATFORM_PROVIDERS, Provider}` →
    `PlatformAuthApiClient.*`. Files touched:
    `backend_api_client.gd`, `crash_reporter.gd`,
    `friends_notification_poller.gd`,
    `game_session_manager.gd`, `match_result_reporter.gd`,
    `nakama_matchmaker_client.gd`,
    `notification_socket_client.gd`, `party_api_client.gd`,
    `party_manager.gd`, `auth_screen.gd`, `account_panel.gd`,
    `delete_account_confirm_panel.gd`, `export_data_row.gd`,
    `link_account_row.gd`.
  - Done — old file removed: `src/core/auth_client.gd` +
    `.uid` deleted.
  - Verification: editor pass refreshed
    `.godot/global_script_class_cache.cfg` with the new
    `PlatformAuthApiClient` entry (the prior `AuthClient`
    entry dropped). Headless boot clean (zero parse / compile
    errors); the first outgoing Nakama request after boot is
    `update_and_get_presence` against live Nakama, succeeding
    via the new path (Authorization Bearer from
    `Platform.build_session_from_store()`, RPC dispatch via
    `Platform.get_nakama_client()`, JWT vars carrying
    `game_id=hopnbop`).
  - Known limitation: no automated compliance test for the new
    class path (Stage 8.x client-unit-tests track not live).
    Confidence is from headless boot + live RPC smoke, not from
    a regression test. The HTTPRequest-callback-shaped dead
    code (`_on_auth_response`, `_on_guest_jwt_response`) was
    preserved verbatim during the extraction — they were
    dead before the move too (no `connect` to either) and
    cleaning them up is separate-PR work.
- [x] **6.3 Reconcile `auth_token_store.gd` with the addon's
  `PlatformAuthTokenStore`; migrate `G.auth_token_store` references
  to `Platform.token_store`** (2026-05-12).
  - Done — game side: deleted `src/core/auth_token_store.gd` (the
    duplicate class — addon's `PlatformAuthTokenStore` was already
    field-for-field identical save for the configurable file path
    and the omitted game-specific `LEGAL_VERSION` constant).
    Moved the constant + `get_current_legal_version()` static
    helper out into a new game-side `src/core/legal_version.gd`
    (`class_name LegalVersion`, static `get_current()`) so the
    consent screen and the runtime version_check resolver still
    have a game-owned home for "what version of terms do we
    require accepted". Migrated all 22 consumer files via sed
    find-replace: `G.auth_token_store` → `Platform.token_store`
    across `auth_client.gd` (45 sites), `game_panel.gd` (15),
    `party_manager.gd` (10), `account_panel.gd` + `consent_screen.gd`
    (7 each), and 17 more files with smaller counts.
  - Done — global.gd: removed the `var auth_token_store:
    AuthTokenStore` field declaration and the `auth_token_store =
    AuthTokenStore.new()` line from `_enter_tree`. Updated the
    `Platform.initialize` call in `_ready` to pass
    `auth_file_path = "user://auth.cfg"` so existing players'
    encrypted credentials remain readable across the upgrade —
    the addon's default of `user://%s_auth.cfg % game_id` would
    orphan every existing install.
  - Done — autoload UID bug fix: `project.godot`'s `Platform`
    autoload referenced `*uid://8yq6f46dmf44`, which was stale
    after the addon copy regenerated UIDs on import. The
    autoload was silently broken (Platform was `Nil`) — never
    surfaced before today because no game code actually read
    `Platform.token_store`. Switched the reference to a `res://`
    path. All other autoloads (G, Netcode, Nakama) already use
    path references; Platform was the outlier. The submodule
    intentionally ships without `.gd.uid` files, so any future
    re-import would have re-triggered the same drift.
  - Done — type-inference fixes: `Platform.token_store` is
    declared untyped on `Platform.gd` (the parser-cache bug
    workaround). That makes `var X := Platform.token_store.Y`
    fail the strict-typing check in Godot 4.7. Three patterns
    needed explicit annotations: (a) `var X: String =
    Platform.token_store.player_id` etc. for typed-field reads;
    (b) `var store: PlatformAuthTokenStore = Platform.token_store`
    in the five sites where a local handle was already used (so
    every downstream `store.X` infers cleanly); (c) `var is_self:
    bool = ...` for `==` comparisons against `Platform.token_store
    .player_id`. Headless boot + live Nakama smoke (JWT refresh,
    presence RPC, group list, settings storage read/write) all
    green after the fixes.
  - Compliance test still pending (Stage 8 socket harness). The
    confidence today comes from headless boot + live RPCs
    succeeding through the new path, not from an automated test.
- [x] **6.4 Extract `friends_api_client.gd` → `Platform.friends.*`**
      (2026-05-12).
  - Done — submodule: new
    `addons/snoringcat_platform_client/core/friends_api_client.gd`
    with `class_name PlatformFriendsApiClient`. Surface: friends
    list / requests / search / mark_seen / notifications. Reads
    `Platform.nakama_client` (new shared slot) and
    `Platform.build_session_from_store()` (new helper that
    constructs a NakamaSession from token_store's JWT + refresh
    token). Cached fields (`cached_friends`,
    `cached_sent_requests`, `cached_incoming_requests`) preserved
    so existing consumers keep working without API churn. All
    method names + signal names match the pre-extraction surface
    so the migration is a pure pointer swap.
  - Done — parent: `auth_client._get_nakama_client()` now also
    writes the new client to `Platform.nakama_client` on first
    create, making it the canonical shared reference (until
    Stage 6.2 moves the constants + creation into Platform
    itself). `global.gd._enter_tree()` calls
    `auth_client._get_nakama_client()` eagerly right after
    `add_child(auth_client)` so `Platform.nakama_client` is
    populated before any addon subsystem is registered.
  - Done — parent: 85 callsites across 10 files migrated.
    Presence-shaped names (`fetch_presence`, `cached_online_ids`,
    `cached_online_friends`, `is_presence_busy`,
    `presence_received`, `presence_received_rich`) routed to
    `Platform.presence.*`; everything else to `Platform.friends.*`.
    Multi-line `G.friends_api_client\` continuations had to be
    fixed by hand after the sed pass — the per-pattern map only
    matched single-line references, so the fallback `G.friends_
    api_client → Platform.friends` rewrote line 1 of split calls
    that should have routed to `Platform.presence` (e.g.,
    `Platform.friends\\\n.is_presence_busy()` and `Platform.friends\\\n
    .cached_online_ids.clear()`). Found via a follow-up grep
    for `Platform\.friends.*\\$` and corrected manually.
  - Done — parent: explicit type annotations added at every
    `var client := Platform.friends` callsite
    (`var client: PlatformFriendsApiClient = Platform.friends`)
    because `Platform.friends` is untyped on the autoload (the
    parser-cache bug workaround inherited from 6.3). Without
    the annotation, `:=` infers Variant and downstream `.X`
    reads fail strict-typing checks in Godot 4.7.
  - Done — parent: game-side `src/core/friends_api_client.gd`
    + `.uid` deleted. `friends_notification_poller.gd` kept
    game-side (too entangled with `G.toast_overlay`,
    `G.match_state`, `G.party_manager` to be a clean addon
    citizen) but updated to read `Platform.friends` +
    `Platform.presence`.
  - Done — parent: `Platform.initialize()` moved from
    `global.gd._ready()` to the top of `global.gd._enter_tree()`
    so addon subsystems can be instantiated and registered
    inline. The old position would have token_store null when
    addon subsystems' `_process` callbacks fired on frame N+1.
  - Verification: headless boot clean (zero parse / compile
    errors); the very first outgoing Nakama request after boot
    is `update_and_get_presence` against live Nakama, succeeding
    end-to-end through the new path (Authorization Bearer header
    from `Platform.build_session_from_store()`, RPC dispatch via
    `Platform.nakama_client`).
  - Known limitation: the addon class needed an editor-mode
    headless run (`godot --headless --editor --quit-after 15`)
    to register `PlatformFriendsApiClient` / `PlatformPresenceApiClient`
    in `.godot/global_script_class_cache.cfg` before plain
    `--headless` could resolve the type names. First-deploy
    instructions: run setup-platform-addon.ps1 → editor scan →
    plain headless. Documented inline in this task entry; not
    a recurring issue once the cache is populated.
- [ ] 6.5 Extract `party_api_client.gd` + `party_manager.gd` →
  `Platform.party.*`.
- [ ] 6.6 Extract `nakama_matchmaker_client.gd` +
  `edgegap_server_provider.gd` → `Platform.matchmaking.*`.
- [x] **6.7 Extract presence read/write into `Platform.presence.*`**
      (2026-05-12).
  - Done — submodule: new
    `addons/snoringcat_platform_client/core/presence_api_client.gd`
    with `class_name PlatformPresenceApiClient`. Surface:
    `fetch_presence(rich_presence, status)` writes the caller's
    presence row and reads back every online friend's presence
    via the runtime's `update_and_get_presence` RPC (one round
    trip). Cached fields `cached_online_ids` (Array[String]) +
    `cached_online_friends` (Dictionary, rich-presence payload).
    `is_presence_busy()` busy-flag + `clear_cache()` helper for
    log-out reset paths (currently unused — callers `clear()`
    the array fields directly, but the helper is there for any
    future caller that wants both fields cleared in one call).
  - Done — parent: shipped jointly with 6.4 (see above). The
    presence/friends split was naturally enforced by the
    addon-side split: callsites for presence-shaped names
    (`fetch_presence`, `cached_online_*`, `is_presence_busy`,
    `presence_received*`) routed to `Platform.presence`,
    everything else to `Platform.friends`.
  - Design call worth recording: the underlying RPC
    (`update_and_get_presence`) bundles a write (caller's
    presence) + a read (friends' presence) in one trip. The
    client-side split into two subsystems (Platform.presence
    writes/reads, Platform.friends manages list) matches the
    platform.gd subsystem-slot intent without changing the
    server contract. A game with no friend feature can still
    use `Platform.presence` for its own status indicator;
    conversely, a game that wants friends but not rich-presence
    can null out the timer in `friends_notification_poller`
    (currently game-side, will follow Platform.friends one day).
  - Compliance verification: the existing addon compliance test
    `test_presence.gd` is HTTP-only — it hits
    `/v2/rpc/update_and_get_presence` directly via the helper,
    independent of the new client class. Still green.
  - Known limitation: no GUT unit test exercising the new
    GDScript class (no Stage 8.x client-unit-tests track is
    live yet). Confidence today is from headless boot + live
    Nakama smoke (the boot-time presence call against live
    `nakama.snoringcat.games` succeeds), not from an automated
    test.
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
- **2026-05-12:** Stage 5.5 landed. Three design calls
  worth recording:
  - **Per-member rows, not a single party-wide blob.**
    Each ready row is `(party_ready, party_id, user_id)`
    with the user as owner. The alternative — a single
    storage row owned by the leader holding a
    `{user_id: bool}` map — would have needed a server
    round-trip for every read (the leader's owner_id
    isn't durable across transfer, so client batched
    reads couldn't target it cleanly). Per-member rows
    cost N batched reads on fetch_party_status but
    those run alongside the existing list_group_users
    response and parties cap at 4 members, so the call
    count is bounded.
  - **PermissionWrite=0, not Owner-writable.** Even
    though each user owns their own ready row, write
    permission is locked to server-only so
    `party_set_ready` is the sole entry point. A
    malicious client can't bypass the validation
    (active-member check, pending-invite rejection)
    or skip the fan-out notification by writing to
    their own storage row directly.
  - **Roster changes invalidate every ready row, not
    just the leaver's.** When a member joins, leaves,
    or is kicked, `clearPartyReadyRows` deletes
    everyone's ready entry. The alternative (only
    clear the affected user's) would leave existing
    members ready for a roster they no longer agree
    with — e.g., Alice and Bob are both ready, Carol
    joins, Alice and Bob remain "ready" without ever
    acknowledging Carol's presence. Clearing all
    forces a fresh "is this group still right?" beat.
    AfterAddGroupUsers (invite) is deliberately *not*
    in the clear set because the invitee is state=3
    until they accept; the active roster hasn't
    actually changed.
- **2026-05-12:** Stage 5 second wave (5.8 / 5.9 / 5.10)
  closed out the bulk of the party-UX backlog. Four design
  calls worth recording:
  - **Chat rides the existing notification socket, not a
    dedicated chat socket.** Nakama's realtime socket
    multiplexes notifications and channel messages on one
    connection. Adding chat to `NotificationSocketClient`
    instead of spinning a new `ChatSocketClient` kept the
    connection budget at one. The cost is a slight scope
    creep on the notification-socket abstraction — it's now
    the realtime-socket. Acceptable. Future stages that
    need other socket-side surfaces (matchmaker presence,
    typing indicators) hang off the same node.
  - **Chat history is in-memory only, server-paginated on
    demand.** PartyManager keeps the last 200 messages
    cached so re-opening the chat panel after closing it
    doesn't re-fetch. The HTTP API's
    `list_channel_messages_async` fetches the latest 50 on
    subscription. Older history is reachable only by adding
    a paging API to PartyManager and a "load earlier" row
    to the panel — deferred until users ask.
  - **Join-by-code uses two storage rows in one collection
    for O(1) lookup either direction.** Forward
    (`code:<CODE>` → party_id) for the join path; reverse
    (`party:<party_id>` → code) for the share path. Both
    rows server-owned with PermissionRead/Write=0 so the
    RPCs are the only access surface. The alternative —
    storing the code on the group's metadata via
    `GroupUpdate` — would have meant a heavier write op
    and a partial mirror of an opaque field. Two cheap
    rows in our own collection is simpler.
  - **Server-authority `GroupUsersAdd` bypasses the
    closed-group join-request dance.** Calling
    `nk.GroupUsersAdd(ctx, "", groupID, []string{userID})`
    with empty `callerID` lets the runtime add a user as
    state=2 (Member) directly, regardless of the group's
    open/closed flag. This is what makes join-by-code work
    without first issuing an invite. Without it, the code
    holder would land as state=3 (pending invite) and need
    a leader-side accept step — defeating the
    "frictionless join" goal.
  - **5.9 rejoin prompt suppresses when invites are
    pending.** Two competing dialog flows would otherwise
    pop simultaneously on boot. The invite dialog has
    actionable state changes (accept/decline), so it
    wins; the rejoin prompt can resurface on the *next*
    poll once invites have been resolved (though in
    practice users either accept-into the same party or
    decline-and-stay, so the prompt would be moot
    afterward).
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
- **2026-05-12:** Stage 5.6 leader transfer + 1.5 UX polish
  shipped. Five design calls worth recording:
  - **Override row, not Nakama group mutation.** Nakama's
    `creator_id` is immutable on the group, and demoting an
    existing superadmin is either impossible (creator) or a
    one-way street that prevents takebacks (admin). The
    cleanest reassignment surface is a separate storage row
    keyed by `party_id`. `resolvePartyLeader` reads the row
    first, falls back to `group.CreatorId` when absent. This
    keeps every existing party (no override row) working
    without a migration step.
  - **Override row is publicly readable.** PermissionRead=2
    (anyone can read), PermissionWrite=0 (only the runtime
    can write). The transfer RPC is the sole mutation
    surface; the client batched-reads the row in
    `fetch_party_status` alongside the per-member ready rows
    and folds the result into the existing `leader_id`
    field. Party_id isn't sensitive (it's already exposable
    via friends-list "in party" badges), so leaking "user X
    is the current leader of party Y" to a session that
    holds the party_id is acceptable.
  - **Promote the new leader, don't demote the old one.**
    `nk.GroupUsersPromote(target)` runs alongside the
    storage write so the new leader has Nakama-side admin
    rights for the standard kick / invite client paths. The
    previous leader is left at whatever Nakama state they
    were at — typically state=0 superadmin if they were the
    original creator. This leaves a "stealth admin" surface
    (a malicious previous-creator client could kick via
    direct Nakama API even after transfer) but the
    in-app UI hides those affordances and a fuller fix
    (move kicks behind a server-authoritative RPC) is
    Stage 6 / 7 territory.
  - **Auto-transfer on leader-departed.** When the current
    leader leaves or is kicked,
    `autoTransferIfLeaderDeparted` picks the first
    remaining active member, writes a new override, and
    promotes them. The alternative — disband the party
    when the leader leaves — would punish the other members
    for someone else's quit. Account deletion routes
    through the same hook (the cascade calls
    `GroupUserLeave` → `AfterLeaveGroup`), so a leader
    whose account is deleted hands off cleanly. When no
    members remain, the override is dropped so a future
    reuse of the same `party_id` doesn't read a stale row.
  - **1.5 polish lives in a sub-panel, not a tweaked
    confirm overlay.** The audit's strict reading wanted
    type-the-word verification + grace-period messaging in
    a single confirm dialog. ConfirmOverlay doesn't have a
    text-input field, and bolting one on would have added
    a generic affordance whose only caller was this one
    flow. The sub-panel pattern matches `AddFriendPanel`
    (already in the codebase) and keeps the confirm-
    dialog surface focused on yes/no choices. The
    delete-account row now does `manager.push_panel(...)`
    instead of `open_confirm_dialog(...)`.
- **2026-05-12:** Stage 6 kickoff — 6.1 + 6.3 shipped. Six
  design calls worth recording:
  - **Subsystem slots are passive properties + a
    `register_subsystem` writer, not preload-and-instantiate.**
    The addon could in principle preload each subsystem
    implementation and instantiate it from inside
    `Platform.initialize`, but every concrete subsystem so
    far still lives game-side (the Stage 6.4+ extractions
    haven't landed). Making the slots passive lets the
    consuming game wire its own implementations as each
    extraction lands incrementally — first `friends_api_client`
    as `Platform.friends`, then `party_api_client` as
    `Platform.party`, etc. — without rewriting the addon's
    `initialize` each time. The `register_subsystem` allowlist
    prevents typos from turning into silent nulls.
  - **`LEGAL_VERSION` is game-side, not addon-side.** Different
    games will eventually publish different terms/privacy/data-
    deletion text and so need different consent versions. The
    addon's `PlatformAuthTokenStore` already documented this
    intent (the file's preamble notes that the LEGAL_VERSION
    constant was deliberately *not* carried over from the
    game-side version). Stage 6.3 makes that real: the new
    `LegalVersion` static helper lives in `src/core/`, and
    `version_check` still flows the per-game server-side value
    through `BackendApiClient.server_legal_version` as before.
  - **Auth file path pinned to `user://auth.cfg` for backward
    compatibility.** `Platform.initialize`'s default is
    `user://%s_auth.cfg % game_id` = `user://hopnbop_auth.cfg`,
    which would orphan every existing player's encrypted
    credentials on first boot after the migration. Pinning
    the path preserves the upgrade path. A future migration
    step could move the file to the new convention, but the
    cost (forcing every player to re-sign-in) is unjustified
    for the cosmetic benefit of "the filename matches the
    game_id" — and now that the path is explicit in
    `global.gd`'s initialize call, the contract is documented.
  - **Mass find-replace via sed, not 22 Edit-tool round-trips.**
    `G.auth_token_store` → `Platform.token_store` is a
    mechanical substitution. Doing it via 22 Read+Edit calls
    would have been slow and error-prone (matching identical
    strings repeatedly). One `sed -i` across the file list is
    cleaner; the tradeoff is no per-file diff context in the
    conversation, but the substitution is uniform enough that
    a single command + a grep for residual references is
    sufficient verification.
  - **`Platform.token_store` is untyped on the autoload, typed
    at the call site.** The addon's `Platform.gd` keeps
    `var token_store` untyped (the parser-cache bug workaround
    documented in the file's preamble). Consuming game code
    that needs typed access uses `var store:
    PlatformAuthTokenStore = Platform.token_store` to bind a
    typed local handle; subsequent `store.X` reads then infer
    cleanly. The `class_name PlatformAuthTokenStore` IS
    registered in the global script class cache so the type
    name resolves outside the addon — just not in the addon's
    own files where the parser-cache bug fires.
  - **`project.godot`'s `Platform` autoload reference switched
    from UID to `res://` path.** The submodule intentionally
    ships without `.gd.uid` files (no game can pin a UID to
    a file it's about to copy into its own resource tree),
    which means each consuming game's import generates a fresh
    UID. Pinning the autoload to a specific UID in
    `project.godot` was a latent bug that only became visible
    when game code actually depended on the autoload. Other
    autoloads (G, Netcode, Nakama) already used path
    references; Platform was the outlier. Path references are
    stable across imports.
- **2026-05-12:** Stage 6.4 + 6.7 friends + presence extraction
  shipped. Six design calls worth recording:
  - **`Platform.nakama_client` as a shared slot, populated by
    game-side auth_client until 6.2.** The cleanest long-term
    fix is to move the Nakama host/port/scheme/server_key
    constants into Platform itself (they're snoringcat-platform
    infrastructure, not game-specific), and have Platform own
    the lazy creation of the NakamaClient. But that's
    explicitly Stage 6.2 work. For 6.4/6.7, the smaller move
    is a Platform.nakama_client field populated by
    auth_client._get_nakama_client() as a side effect of its
    existing lazy-create path. Addon subsystems read it. After
    6.2, auth_client's `_get_nakama_client()` becomes a thin
    delegate to `Platform.auth.get_nakama_client()` and the
    constants live on Platform. Path-incremental.
  - **`Platform.build_session_from_store()` as a shared helper
    on the autoload.** The session-reconstruction logic was
    private inside auth_client (`_build_session_from_store`).
    Both friends and presence clients need it. Duplicating
    the 5-line helper into each subsystem class would have
    worked but accreted. Centralizing it on Platform (where
    token_store lives) is cleaner and means future subsystems
    don't need to reinvent it.
  - **Presence split into its own subsystem, even though one
    RPC covers both write and read.** The underlying
    `update_and_get_presence` RPC is one round trip: it writes
    the caller's row and returns every online friend's row.
    The client-side split into PlatformFriendsApiClient (list
    management) and PlatformPresenceApiClient (write/read of
    rich-presence) matches the platform.gd subsystem-slot
    design intent without changing the server contract. The
    payoff is that a game with no friends feature can still
    ship presence (or vice versa) without dead code. Tradeoff:
    two classes carrying their own busy-flag + cache fields
    instead of one. Acceptable given the conceptual separation.
  - **`friends_notification_poller` stays game-side.** Reading
    `Platform.friends` and `Platform.presence` is straightforward;
    the entanglement with `G.toast_overlay` (UI),
    `G.match_state` (game state), `G.party_manager` (game-side
    coordination), and `G.notification_socket_client` (also
    game-side for now) makes the poller a coordination layer
    rather than a clean addon citizen. Moving it would force
    the addon to take dependencies on game-specific UI / state
    surfaces. The right pattern is: keep the *coordinator* (the
    poller) game-side, but factor each *API surface* it
    coordinates over into the addon. Same pattern friends_panel
    follows on the UI side: lives in the game, reads
    Platform.friends / Platform.presence directly.
  - **`Platform.initialize` moved from `_ready()` to top of
    `_enter_tree()`.** The old position (in
    `global.gd._ready()`) post-dated subsystem creation in
    `_enter_tree()`. Subsystem `_process` callbacks could
    therefore fire on frame N+1 with `Platform.token_store ==
    null` and crash. The new position runs Platform.initialize
    before any subsystem is created, so addon subsystems can be
    instantiated and registered inline within `_enter_tree()`
    with all Platform fields available. Side benefit: the
    "where do I register a new subsystem" mental model becomes
    "in `_enter_tree`, right after `add_child`" — one place,
    not two.
  - **Sed pattern map needs per-pattern routing for split
    extractions.** Stage 6.3's mass migration was a uniform
    `G.auth_token_store → Platform.token_store`. Stage 6.4's
    is heterogeneous: 85 callsites split across two
    destinations (`Platform.friends` vs `Platform.presence`)
    depending on which API/field. Solved by an iterative sed
    over the presence-shaped name list first
    (`G.friends_api_client.fetch_presence` → `Platform.presence
    .fetch_presence`, etc.) and a catch-all
    `G.friends_api_client → Platform.friends` second. Caught
    one class of misses: multi-line `\\`-continuation calls
    where pattern 1 only matched the leaf reference, not the
    `G.friends_api_client\\` line, so pattern 2 rewrote that
    line as `Platform.friends\\` and the leaf became
    `Platform.friends\n.is_presence_busy()` — wrong subsystem.
    Found via a `Platform\\.friends.*\\$` grep after the sed
    pass, fixed by hand. Lesson for future Stage 6.x sed
    passes: always grep for backslash-continuation residuals
    when the migration splits one source into multiple
    destinations.

- **2026-05-12:** Stage 6.2 auth extraction shipped. Six design
  calls worth recording:
  - **Nakama host / port / scheme / server_key / http_key moved
    to Platform, not duplicated per subsystem.** The previous
    pattern (constants on `auth_client.gd`, exposed via static
    `get_nakama_base_url()` / `get_nakama_http_key()` helpers
    that other code reached for) had two problems: every
    consumer needed to know "ask the auth client for the
    Nakama URL" (wrong responsibility), and a future second
    game would have to ship its own copy of those constants if
    the auth class moved into the addon as-is. The cleaner
    surface is `Platform.{nakama_host, nakama_port,
    nakama_scheme, nakama_server_key, nakama_http_key}` as
    plain fields populated by `Platform.initialize`. `Platform.
    get_nakama_base_url()` replaces the static helper.
  - **`Platform.get_nakama_client()` owns NakamaClient lifecycle,
    not the auth subsystem.** Stage 6.4 had auth_client lazy-
    create and side-effect-write `Platform.nakama_client`. With
    6.2 in place, lazy creation lives on Platform itself — any
    subsystem reads `Platform.get_nakama_client()` (or the
    cached `Platform.nakama_client` field, populated by the
    same call). Centralizes ownership and means the auth class
    isn't a special "must-be-first" subsystem; if a future game
    needs friends but not auth UI, presence still works.
  - **OAuth client IDs and callback URL pass through
    `Platform.initialize`, not read from `G.settings` by the
    addon.** The values still live on `settings.tres` (where
    they're editor-editable as `@export` vars), but
    `global.gd._enter_tree()` reads them at boot and passes
    into `Platform.initialize`. The addon class reads
    `Platform.oauth_callback_url`, `Platform.google_oauth_
    client_id`, `Platform.facebook_oauth_client_id`,
    `Platform.google_token_broker_url`. Keeps the
    addon→game dependency at zero.
  - **`G.log.print` / `G.log.warning` → `print` /
    `push_warning` in the addon.** The friends/presence
    extractions kept logging out entirely (they only emit
    signals on failure). The auth class has more pervasive
    diagnostic logs (OAuth state transitions, redirect parse
    results, broker HTTP responses) that aren't worth dropping.
    Replacing with the GDScript stdlib `print` and
    `push_warning` loses the `ScaffolderLog` categorization
    (network / system / etc.) but keeps the diagnostic value.
    A future "platform logger" abstraction could let games
    inject their own logger; not worth doing speculatively.
  - **Post-login cloud-settings fetch moved out to a
    `global.gd._ready()` listener.** The old
    `_handle_auth_success` called
    `G.settings_cloud_sync.fetch_and_merge_from_cloud()`
    directly. That's game-specific behavior — the addon's
    auth class shouldn't know that this game uses cloud
    settings or that the trigger is post-login. Moving the
    call to a `Platform.auth.auth_completed` listener in
    `global.gd._ready()` keeps the contract intact (cloud
    fetch fires after every successful non-link auth) while
    letting the addon class be game-agnostic.
  - **Dead HTTPRequest-callback code preserved verbatim.**
    `_on_auth_response` and `_on_guest_jwt_response` are
    callback shapes for `HTTPRequest.request_completed`. The
    flow that would have connected them died with the AWS
    decommission; nothing in the current code reaches them.
    They were preserved verbatim during the extraction so
    this change is a pure move-and-rename. Pruning them is
    separate-PR work — small, low-risk, and easier to review
    in isolation.

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
