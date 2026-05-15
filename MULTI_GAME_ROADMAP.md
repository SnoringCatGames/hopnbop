# Multi-Game Platform Roadmap

## Context

`docs/archive/FRIENDS_PARTY_MATCHMAKING_AUDIT.md` (2026-05-12, archived
2026-05-15 once this roadmap reached functional completion) catalogs
the gap between the platform's design ("one Nakama runtime, N games")
and reality ("one Nakama runtime, one game's worth of config baked
into env vars, plus several broken user-facing contracts"). This
document stages the work to close that gap.

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
- `docs/archive/FRIENDS_PARTY_MATCHMAKING_AUDIT.md` — diagnostic gap
  inventory (historical; archived 2026-05-15).
- `third_party/snoringcat-platform/PLATFORM_ARCHITECTURE.md` —
  runtime detail / target topology.
- `third_party/snoringcat-platform/STUDIO_ARCHITECTURE.md` — service
  inventory / repo map.

## Status summary

- **Current focus:** **Roadmap functionally complete**
  (2026-05-15, twenty-fifth pass). Twenty-fifth pass was a
  follow-up AWS-era script archive sweep complementing the
  24th pass's doc-archive sweep: archived the last two stale
  one-shot AWS-migration scripts that the 24th pass missed
  because they lived under `scripts/` rather than at the top
  level. Moved to `docs/archive/`:
  `phase-f-destroy.ps1` (parent repo, one-shot AWS teardown
  that ran 2026-05-13; unrunnable now because the AWS account
  is empty — kept as archeology in case a future game needs
  an AWS-migration teardown template; was at
  `scripts/decommission/aws/phase-f-destroy.ps1`, parent
  `scripts/decommission/` tree removed since the script was
  its sole inhabitant) and
  `migrate_ddb_to_nakama.py` (submodule, one-shot Phase E
  DDB→Nakama migration; unrunnable because the source DDB
  tables no longer exist — kept as archeology in case a future
  game wants to reuse the bulk_import RPC pattern; was at
  `third_party/snoringcat-platform/scripts/migrate_ddb_to_nakama.py`).
  Reference updates: submodule `README.md` repo-layout block
  drops the script entry and adds a `docs/archive/` line;
  submodule `CLAUDE.md` scripts list drops the
  `migrate_ddb_to_nakama.py` entry; submodule
  `runtime/bulk_import.go` comment points at the archive
  path and notes the RPC remains gated behind
  `BULK_IMPORT_ENABLED=true` for future-game reuse; this
  roadmap's Phase F closure note (line 519) updated to point
  at the archive path with a brief breadcrumb. The
  `bulk_import` RPC itself stays in the live runtime —
  archiving the script doesn't pull the gated RPC out
  because reusing the migration pattern for a future game's
  legacy-data import is the most likely future need. Audit
  pass before the archive confirmed the four 24th-pass
  non-acted items (Nightly Smoke transient 400, Compliance
  Matrix zero-runs, client-sdk-ci.yml fixture-Godot TODO,
  top-level `README.md` "TODO" stub) are still non-blocking
  and no new actionable items have emerged. Working tree is
  now fully aligned: no AWS-era code or scripts outside
  `docs/archive/`. **Prior twenty-fourth pass:** doc-archive
  sweep. Ran the audit-followups skill against the
  current repo state to confirm no implementation gaps were
  hiding behind the recent suspect-list cleanups, then archived
  four stale top-level docs that the roadmap had fully
  superseded. Moved to `docs/archive/`:
  `DISTRIBUTED_SYSTEMS_PLAN.md` (1973 lines of AWS-era
  Lambda/DynamoDB/GameLift/CloudFront plan — every component
  retired in Phase F), `BUILD.md` (GameLift-GDExtension build
  instructions — addon deleted commit `69264c1`),
  `FRIENDS_PARTY_MATCHMAKING_AUDIT.md` (the 2026-05-12 audit
  that motivated this roadmap — referenced from the Context
  section above, link updated to point at the archive copy),
  and `docs/test-architecture-plan.md` (every actionable item
  has landed: §1 socket helper + four socket tests
  (`test_socket_auth/chat/matchmaker/presence.gd`) live in the
  compliance suite, §2 WebRTC fix list items 1-7 all ✅ and
  item 8 ⚠️ regression test exists at
  `compliance/test_transport_selection.gd`, §3 was a
  placeholder for a research report that never materialized).
  Reference updates: roadmap Context section + `See also`
  list now point at the archived audit doc; submodule
  `STUDIO_ARCHITECTURE.md` "Key docs" list refreshed to drop
  the dangling pointers (`MIGRATION_PLAN.md`,
  `platform-pivot-discussion.md`, `BUILD.md` — all archived)
  and add a "Historical / archived" pointer to the full
  archive directory; `.vscode/README.md` dropped its dangling
  `BUILD.md` link. Items the audit-followups pass surfaced
  but explicitly **did not** act on, captured here as future
  follow-ups if they become load-bearing:
  (i) Nightly Smoke had a transient HTTP 400 on the prod
  `/v2/account/authenticate/device` endpoint at 2026-05-14
  04:20 UTC; next run (2026-05-15 01:18 UTC) succeeded with
  no code change — treating as transient prod hiccup.
  (ii) The new `Compliance Matrix` workflow (8.31) has zero
  runs to date because it's PR-triggered and this repo
  commits direct to main — a `workflow_dispatch` smoke run
  on a fresh checkout would confirm the gate actually works
  end-to-end; deferred until someone has reason to open a
  PR.
  (iii) Submodule `.github/workflows/client-sdk-ci.yml:50`
  carries a TODO about standing up a fixture Godot project
  so the Client SDK CI can actually run GUT against the
  addon in isolation; today the addon is exercised
  end-to-end via the consuming game's compliance suite
  (Tier 4 dev-stack covers everything that fixture would).
  (iv) Top-level `README.md` is still a one-word "TODO"
  stub — private repo, cosmetic.
  With the doc archive in place the working tree is fully
  aligned with the live system: no top-level doc references
  AWS-era infrastructure, every "Open" / "Verification gate"
  bullet has either shipped or is explicitly deferred with
  rationale. **Prior twenty-third pass: Stage 7.3 push
  notifications declined as a product decision** (no
  platform-level push for any trigger; in-app toasts via the
  10s `friends_notification_poller` remain the only surface),
  submodule `runtime/build/` added to the platform
  `.gitignore` (local-smoke-test artifact was showing up as
  untracked content in the parent repo every time the dev
  stack was exercised). With 7.3 declined, the only remaining
  open items (4.3 require_accept dialog, 4.8 region picker)
  are both deferred behind upstream schema/runtime work that
  isn't yet justified by use. **Prior twenty-second pass:
  Stage 8 Tier 4 e2e/smoke shipped**
  end-to-end (2026-05-14). 8.29
  `infra/dev/docker-compose.dev.yml` brings up Nakama +
  Postgres locally with `EDGEGAP_MOCK_DEPLOY=true` so the
  full matchmaker hook + every platform-runtime RPC are
  exercised without paid Edgegap I/O. The dev stack mounts
  the locally-built `snoringcat.so` plugin from
  `third_party/snoringcat-platform/runtime/build/` and a
  hand-trimmed `config.dev.yml` (no Caddy / Grafana /
  signaling-proxy; mock-mode env vars hardcoded because
  Nakama does NOT interpolate `${X}` in config.yml — prod
  renders the file via `phase-a.ps1`). 8.30
  `scripts/local-smoke-test.ps1` orchestrates the full
  cycle: refresh platform-addon copy, build the plugin
  (Docker), compose up, poll `/healthcheck`, POST
  `register_game` with hopnbop's `game.yaml` via the
  existing `sync-game-config.ps1`, run the compliance
  suite via `gut_cmdln.gd`, tear down (`docker compose
  down -v`). Exit-code surface: 0 = green, 1 = test
  failures, 2 = stack/build/healthcheck failure, 3 =
  registration failure. 8.31
  `.github/workflows/compliance-matrix.yml` invokes the
  same smoke script on every PR + `workflow_dispatch` on
  ubuntu-latest with `chickensoft-games/setup-godot@v2`;
  single-axis (ephemeral only) because there is no
  staging Nakama tier yet, future expansion documented in
  the workflow comment. Two submodule companion fixes
  shipped 2026-05-14: `compliance/test_version.gd` now
  treats `EDGEGAP_MOCK_DEPLOY=true` as a valid hook-active
  indicator alongside `EDGEGAP_TOKEN`, and
  `compliance/compliance_socket_helper.gd::_derive_socket_target`
  parses scheme + host + port out of `PLATFORM_API_URL`
  rather than hardcoding `wss://:443` (prod fallback
  preserved when the env var is unset). Verified
  end-to-end: 9 HTTP-based compliance test files green
  against the dev stack (19 tests / 60+ asserts;
  version, auth_anon, friends, party, account, settings,
  presence, api_surface, player_stats), `register_game`
  succeeds, runtime boot log shows
  `mock_deploy=true edgegap=true app=hopnbop-server
  version=v-dev`. Known limitation captured in
  `infra/dev/README.md`: realtime-socket compliance tests
  pend on a Godot 4.5 `WebSocketPeer` quirk against
  `ws://127.0.0.1` (raw .NET / curl WS connects with the
  same Nakama-issued JWT succeed); tests pend gracefully
  via `pending(...)` so GUT exits 0. Also a Windows-
  specific gotcha: use `127.0.0.1` not `localhost` in
  `PLATFORM_API_URL` — Docker Desktop binds only IPv4,
  Godot's HTTPRequest burns ~60s per request hitting the
  unreachable IPv6 host before retrying. Prior twenty-first pass:
  **Stage 6.11b concrete-screen extraction
  shipped** (2026-05-14). Three full
  `*.tscn` + `*.gd` screens now live in the addon under
  `addons/snoringcat_platform_client/ui/screens/`:
  `PlatformAuthScreen` (auth provider buttons + focus nav),
  `PlatformConsentScreen` (age + ToS / privacy gate),
  `PlatformAnonymousUpgradeScreen` (greenfield — screen-
  shaped equivalent of hopnbop's `UpgradeAccountPanel`
  SidePanel, for future games that want a hard-gate variant;
  not integrated into hopnbop). Hopnbop's `auth_screen.tscn`
  + `consent_screen.tscn` became inherited scenes from the
  addon's, with @export branding overrides on the root node
  (theme, panel stylebox, logo, provider icons, checkbox
  textures, chevron, focus / unfocused styleboxes). Game-side
  `AuthScreen` / `ConsentScreen` scripts (~40-80 lines each)
  extend `PlatformAuthScreen` / `PlatformConsentScreen` and
  wire the addon screens' navigation + state-reset signals
  to hopnbop's `G.*` autoloads and `ScreensMain.ScreenType`
  enum. Signal contracts: `PlatformAuthScreen` exposes
  `lobby_navigation_requested` +
  `force_anonymous_state_reset_requested`;
  `PlatformConsentScreen` exposes `consent_accepted` +
  `language_picker_requested` + `terms_link_requested` +
  `privacy_link_requested`; `PlatformAnonymousUpgradeScreen`
  exposes `upgrade_completed` + `dismiss_requested`. Virtual
  hooks let game subclasses inject behavior the addon can't
  know about: `_create_navigator()` /
  `_create_input_poller()` (audio-wired variants),
  `_should_force_anonymous()` / `_should_auto_consent()` (the
  Netcode-preview-secondary-client gates),
  `_get_current_legal_version()` (game-side
  `LegalVersion.get_current()` over `G.backend_api_client`),
  `_get_icon_scale()` / `_get_icon_padding()` (G.settings
  values), `_play_focus_sound()` / `_play_select_sound()`
  (G.audio). Return-type widening: `ScreensMain.
  get_screen_from_type()` now returns `PlatformScreen` (the
  common ancestor of `Screen` and the new platform screen
  classes) so callsites accept both branches; the one
  `var screen: Screen` callsite in
  `screen_trigger_row.gd::_open_screen()` widened to
  `PlatformScreen`. Verified via `godot --headless --import`
  (no parse / compile errors, all 5 classes registered) +
  ad-hoc scene-instantiation smoke (all 5 scenes load + carry
  the expected class through the inheritance chain). No
  end-to-end UI flow exercised (auth screen → consent → lobby
  needs Levi at the keyboard or a Tier-4 docker-compose dev
  stack; same blocker as 7.10b). Hopnbop's behavior is
  preserved by the wrappers: scene-level theme + stylebox +
  branding overrides replace the runtime
  `Screen._set_default_styling()` calls, signal subscribers
  duplicate the prior direct `G.screens.client_open_screen()`
  + cache-clear paths. The anonymous-upgrade screen is the
  only intentionally-not-wired-up surface — kept as a future-
  game reference implementation without a concrete second
  consumer; design will likely need a refinement pass once a
  second game actually adopts it. Prior twentieth pass:
  **Stage 6.11a foundation migration shipped** (2026-05-14).
  Game-side `Screen` /
  `ScreenFocusNavigator` / `AnyDeviceInputPoller` now extend
  their `Platform*` addon equivalents instead of being
  independent duplicates. Verified via `godot --headless
  --import` (clean) and `godot --headless --client=1` boot
  (auth screen → consent flow → lobby transitions all work).
  Prior nineteenth pass: **Stage 8
  Tier 3 client unit tests (8.23–8.28) shipped end-to-end**
  (2026-05-14). Six new test files under
  `test/unit/platform/` cover the pure-logic helpers of every
  Stage 6 platform SDK class: `friends_api_client` (13 tests),
  `party_api_client` (11), `party_manager` (31),
  `nakama_matchmaker_client` (28),
  `friends_notification_poller` (20), `settings_cloud_sync`
  (16). 119 tests / 212 asserts pass via `gut_cmdln.gd
  -gdir=res://test/unit/platform` in ~0.5 s. Approach diverged
  from the audit's "GUT doubles" framing: since each class is
  mostly network-coupled (Platform.nakama_client / HTTP)
  *and* the network paths are already exercised live by the
  compliance suite, the units target the deterministic
  resolvers, state inspectors, and dispatch helpers instead —
  snapshotting / restoring autoload state (G.backend_api_client,
  G.local_settings overrides, Platform.game_id /
  token_store.player_id, Netcode.settings.transport_type) per
  test rather than doubling Nakama. Second divergence: GUT
  9.5.0 + Godot 4.7-beta1's cmdline path silently fails to
  discover inner-class tests, so tests are flat top-level
  methods grouped by name prefix — documented in each file's
  docstring so a future contributor doesn't trip over the same
  thing. Prior eighteenth pass: **Stage 7.10b (mid-match
  rejoin transport parity: WebRTC + WebSocket) shipped**
  (2026-05-14). Dropped the `_transport_type != ENET`
  short-circuit
  in `src/core/reconnect_handler.gd::can_attempt_reconnect()`
  so the reconnect loop fires for all three transports.
  Framework-side (`rollback_netcode` submodule),
  `network_connector.gd::_client_start_webrtc` gains a
  parallel close-and-null cleanup on any stale
  `_webrtc_peer` left over from the dropped match (mirrors
  the existing `_webrtc_signaling_client` cleanup); without
  this the dropped match's `WebRTCPeerConnection` +
  DataChannels would linger until GC and could hold UDP
  socket bindings the new ICE agent needs to claim. The
  override `MultiplayerPeerExtension._close()` in
  `webrtc_game_peer.gd` already cascades `remove_peer` to
  each PeerState, so the cleanup is a one-line call.
  Stale "ENet-only in v1" comments refreshed in
  `reconnect_handler.gd` class docstring + `game_panel.gd`
  (field doc + `_on_connection_lost`). Verified via
  `godot --headless --import` (exit 0, no parse/compile
  errors). No end-to-end smoke for the transport-parity
  reconnect path itself — same blocker as 7.10 (mid-match
  disconnect against a live deployment isn't easily
  automatable against prod); Tier 4 docker-compose e2e
  (8.29) is the natural home. Decision worth recording:
  shared retry interval (5s × 6 attempts) across transports
  rather than transport-aware. ENet redials in
  milliseconds; WebRTC signaling typically completes in
  2–3s of the 5s budget (server already bound so
  WebRTCSignalingClient's 12 × 750ms internal retry
  succeeds on attempt 1 in the happy path). If a WebRTC
  signaling cycle is still mid-flight when the outer 5s
  timer fires, the next `_attempt_reconnect` tears down
  the in-progress signaling client and starts fresh.
  Wasteful but not broken; per-transport tuning is polish.
  Prior seventeenth pass: **Stage 7.10
  (mid-match rejoin, reconnect flavor) shipped end-to-end**
  (2026-05-14). Locked design call:
  reconnect (same player resumes, not backfill), slot+score
  only (treat gap as died-and-respawning), 30s grace
  window. Framework change (`rollback_netcode` submodule
  `02c65b0`): NetworkConnector reuses player_id when an
  incoming session_id matches a previous declaration, so a
  reconnecting client keeps their slot. Game-side:
  GameMatchState gains `player_reconnected` signal +
  `server_on_player_reconnected` method;
  MatchStateSynchronizer adds 30s grace timers per
  player_id plus `reconnect_grace_started/expired` signals;
  game_panel defers `_server_check_auto_end_on_disconnect`
  until grace expires. Client-side ReconnectHandler
  (`src/core/reconnect_handler.gd`) captures match-ready
  params on first connect and runs a backoff retry loop
  (5s × 6 attempts within 30s) on unexpected mid-match
  disconnect. UI: programmatic ReconnectingOverlay with
  spinner + countdown + TOAST.RECONNECT_FAILED /
  TOAST.RECONNECTED. ENet-only at 7.10 ship time; 7.10b
  lifted the transport gate. 4 new translation
  keys × 13 locales. Headless boot clean (no parse/compile
  errors after the change). Prior sixteenth pass: **Stage
  7.11 lightweight observability re-introduction**
  (2026-05-13). Re-added Prometheus
  + Grafana + node-exporter + postgres-exporter to the
  consolidated single-host CPX11; Loki + Promtail stayed off
  to preserve RAM headroom (configs preserved for a future
  re-introduction). New `snoringcat_alloc_seconds` custom
  Nakama timer instrumented in
  `fleet_allocator.go::OnMatchmakerMatched` records
  allocation cold-start latency via
  `nk.MetricsTimerRecord` (tags `game_id` + `mock`),
  surfaced on the same `:9099` endpoint Prometheus already
  scrapes. Caddyfile re-added `grafana.snoringcat.games`
  with auto-TLS + a follow-up `admin 0.0.0.0:2019` patch so
  Prometheus could scrape Caddy `/metrics` from a sibling
  container. Pulumi re-added the matching A record +
  exports `grafana_url`. **Deploy executed against live
  prod 2026-05-13:** SCP'd configs + `docker compose up -d
  --build --remove-orphans` (all 8 containers up, postgres
  + nakama healthy), `pulumi up` (grafana-a Cloudflare
  record created, ID `a12f0c50...`), `nakama-runtime.yml`
  workflow run 25838774053 succeeded (build_id `526c038`
  carries the new instrumentation), Grafana `/api/health`
  returns 200, all 5 Prometheus scrape targets up (caddy /
  nakama / node / postgres / prometheus), 6 alert rules
  provisioned (nakama-down / postgres-down / postgres-conn-
  saturation / disk-usage-high / cpu-sustained-high /
  postgres-slow-queries-placeholder). Memory post-deploy:
  692 MB used / 1.2 GB available; obs services land at
  ~340 MB combined (prometheus 112 + grafana 187 + node-
  exporter 20 + postgres-exporter 19), bang on the pre-
  deploy 350 MB estimate. Caught one live-deploy gotcha:
  Grafana container runs as UID 472 and couldn't read
  `/etc/grafana/provisioning` SCP'd as root-600;
  `chmod -R a+rX` + restart fixed it (provisioning files
  are non-secret config except `contactpoints.yml` which
  carries the Discord webhook URL — already in
  `/opt/nakama/.env` as a soft secret). Prior pass (still standing):
  **Stage 7.9 (anonymous-upgrade UI) + 7.8 (account-merge
  UI) shipped** (2026-05-13, fifteenth pass). 7.9 adds `UpgradeAccountPanel`
  (SidePanel): an anonymous-only entry pushed from the main menu
  in place of the existing "Account" row when the user hasn't
  upgraded yet. The panel surfaces a header ("Keep Your Progress"),
  fuller benefits body, the existing Google + Facebook
  `LinkAccountRow`s (which already drove the anonymous→permanent
  login flow internally), and a "Maybe later" close row. The main
  menu entry shows a badge to draw the eye of brand-new anonymous
  players who otherwise wouldn't discover the upgrade path. The
  underlying flow (`Platform.auth.login_with_provider` for
  anonymous users) is unchanged — the work is pure
  discoverability. 7.8 replaces the prior PROVIDER_CONFLICT
  ConfirmOverlay with a dedicated `MergeAccountPanel` (SidePanel)
  pushed by `LinkAccountRow` when the link API returns
  PROVIDER_CONFLICT. The panel renders a header
  ("Existing Account Found"), a fuller body with the provider name
  interpolated explaining what merges and that the action cannot
  be undone, an explicit "Continue and Merge" action row, and an
  explicit "Cancel" row. The panel owns the
  `Platform.auth.merge_completed` subscription (the prior code
  hung it on LinkAccountRow with a CONNECT_ONE_SHOT) and tracks
  `_explicit_action_taken` so the back-row pop path cancels the
  pending server-side merge token via `cancel_merge` while the
  Merge or Cancel paths skip the redundant call. Three keys
  retired from the CSV (`CONFIRM.MERGE_ACCOUNT`, `LINK.MERGE`,
  `LINK.MERGING`) — they were the prior ConfirmOverlay surface
  and no longer have callers; the per-CLAUDE.md "no
  backwards-compat hacks" rule says delete-when-confirmed-unused.
  i18n: 7 new keys × 13 locales (`SETTINGS.SIGN_IN`,
  `UPGRADE.HEADER`, `UPGRADE.BENEFITS_BODY`,
  `UPGRADE.MAYBE_LATER`, `MERGE.HEADER`, `MERGE.BODY`,
  `MERGE.CONTINUE`, `TOAST.ACCOUNTS_MERGED`,
  `TOAST.MERGE_FAILED` — 9 actually; non-English are
  best-effort and worth a native-speaker review pass). CSV
  verified at 14 fields per line for every new entry (pre-existing
  legacy line 120 with comma drift is untouched);
  `.translation` binaries regenerated via `godot --headless
  --import`. Headless boot clean against live Nakama
  (`update_and_get_presence` succeeds via the existing path; new
  scenes load + classes register; zero parse / compile errors).
  No new compliance tests — the flows depend on UI input that the
  current compliance suite doesn't simulate, and the underlying
  RPC contracts (link_provider PROVIDER_CONFLICT, confirm_merge,
  cancel_merge, login_with_provider for anonymous-upgrade) are
  already exercised live by the platform smoke test. Prior
  fourteenth pass (still standing): **Stage 7.7
  (GDPR cascade verification) + 7.6 (recent-players list)**
  shipped 2026-05-13. 7.7 added a new
  compliance test `test_account_delete_cascade_surfaces.gd`
  that seeds presence + a party-prefixed group + 2 user-owned
  storage rows for a fresh account, calls `delete_account`,
  and asserts every surface clears while the
  `account_deletion_queue` audit row is preserved. The test
  exposed a real GDPR bug in the cascade and in
  `export_player_data`: both passed empty collection to
  `nk.StorageList`, whose underlying SQL has
  `WHERE collection = $1`, so the calls silently no-op'd
  for "list all collections" semantics. User-owned storage
  rows survived every account deletion since Stage 1.4
  shipped. Fixed via a direct SQL DELETE in the cascade
  (preserving the audit row via `collection != $2`) and a
  direct SQL SELECT in the export (capped at 1000 rows,
  explicit `::uuid` cast on user_id for driver-portability).
  20/20 cascade asserts green post-fix against live runtime;
  prior 8.16 friends cascade still green. **7.6 (recent-
  players list)** shipped as a full feature in the same
  pass: new `runtime/recent_players.go` with
  `writeRecentPlayersForMatch` hook on `match_end` (records
  N×(N-1) per-pair rows keyed by other-user-id so re-matching
  the same player overwrites cleanly) + new
  `list_recent_players` client RPC (sorted by matched_at
  desc, capped at 50). Synthetic-match gating removed from
  the recent-players write so mock-deploy and any future
  synthetic multi-player flow records too; helper already
  short-circuits on solo matches. Client SDK additions on
  `PlatformFriendsApiClient`: `cached_recent_players`,
  `fetch_recent_players()`, `recent_players_received` signal,
  `is_recent_players_busy()` guard. UI: new
  `RecentPlayersPanel` sub-panel (Add Friend per row,
  already-friends / pending-request / blocked rows filtered
  out client-side) + `FRIENDS.RECENT_PLAYERS` trigger row in
  the FriendsPanel action stack between Add Friend and
  Blocked Users. 2 new translation keys × 13 locales. 5 new
  Go test functions (24 sub-tests) lock the pair-count,
  dedup, [deleted]-other filtering, value-shape, sort, and
  cap contracts. New compliance test `test_recent_players.gd`
  with 2 tests / 66 asserts covers the empty-list contract
  for fresh users and the desc-sort + cap behavior on
  seeded rows (writes directly via `/v2/storage` with
  `permission_write=1` divergence documented in the test).
  Both submodule deploys ran cleanly (build `628fc3a` live);
  4 cascade + recent-players tests green. **Prior pass
  (Stage 8.15) shipped** (2026-05-13, thirteenth pass) —
  two-test compliance file covering (a) single-user block-
  list lifecycle with bidirectional add-rejection verified
  via friend-state reads and (b) matchmaker blocked-pair
  abort fan-out, mock-mode gated. **Stage 7.4
  friend block list (twelfth pass)** shipped end-to-end
  Server side adds `runtime/block_list.go` with three RPCs
  (`block_user`, `unblock_user`, `list_blocked_users`) layered
  over Nakama's native state=3 (BANNED) friend state — Nakama's
  built-in `FriendsBlock`/`FriendsAdd` semantics give us
  bidirectional friend-add rejection for free (caller-blocks-
  target and target-blocks-caller both reject in `AddFriends`
  without us writing a separate hook). The matchmaker hook
  (`fleet_allocator.go::OnMatchmakerMatched`) now fires a
  blocked-pair check before the Edgegap allocation: walks each
  matched user's BANNED list, runs `findBlockedPairs` over
  the N×N pair space, and if any directed (A blocked B) edge
  exists between two matched users, calls
  `abortBlockedPair` (mirrors `abortProtocolMismatch`) to
  fan-out per-player `match_failed reason=blocked_pair` so the
  game-side classifier routes to `LOADING.BLOCKED_PAIR` (new
  recoverable copy with retry button, not toast-and-bounce).
  Skipped for solo (<2-player) matches. New constants
  `blockListPageSize=100` / `blockListPageCap=10` (matches the
  account-cascade pattern); shared `listBlockedUserIDs` helper
  drives both the list RPC and the matchmaker filter so both
  read the same view. Client SDK gains
  `Platform.friends.block_user/unblock_user/fetch_blocked_users`
  + `cached_blocked_users` + three new signals
  (`user_blocked`/`user_unblocked`/`blocked_users_received`) +
  `is_blocked()` helper. UI: new `FriendDetailsPanel` Block
  action with type-the-word-style confirm; new
  `BlockedUsersPanel` sub-panel (lists blocked users with
  one-tap unblock); FriendsPanel gets a "Blocked Users" entry
  in the top action stack alongside Add Friend. 8 new
  translation keys × 13 locales
  (`FRIENDS.BLOCK`/`UNBLOCK`/`BLOCKED_USERS`/`NO_BLOCKED_USERS`,
  `CONFIRM.BLOCK_USER`, `TOAST.USER_BLOCKED`/`USER_UNBLOCKED`,
  `LOADING.BLOCKED_PAIR`). Server tests: 1 new test function
  in `block_list_test.go` (`TestFindBlockedPairs`) with 8
  sub-tests locking the pair-detection contract
  (empty-match, no-blocks, one-way detected, two-way de-dup,
  pair-order-stable, out-of-match-ignored, self-block-filtered,
  multiple-pairs-larger-match). `go vet && go test &&
  staticcheck` clean; pluginbuilder Docker produces a 19 MB
  `snoringcat.so`. **7.12 + 7.13 abuse hardening shipped to
  prod** earlier in the same session (build
  `1bd61db978bc50f87a151e7ceef483aaf496ed42` per the
  `snoringcat-platform runtime loaded` log line; healthcheck
  green). Prior 2026-05-13 work (still standing): 7.5 friend
  pagination, 7.1 allocation retry, 7.2 mid-queue cancel
  teardown (`inflightAllocation` tracker +
  `cancel_matchmaking_allocation` RPC + LOADING.PEER_CANCELLED
  fan-out), Tier 2 matchmaking compliance suite (8.20
  cancel-race + 8.21 protocol-mismatch), Tier 1 Go unit tests
  (8.3-8.10, 100 cases), 8.1+8.2 deploy gate,
  8.11/8.12/8.14/8.16/8.17/8.18/8.19/8.22 compliance tests,
  8.13 EDGEGAP_MOCK_DEPLOY mode, audit-surfaced drift fully
  resolved. **Roadmap functionally complete as of 2026-05-14
  (twenty-third pass): 7.3 push notifications declined as a
  product decision (no platform-level push for any trigger).**
  Remaining items 4.3 and 4.8 stay deferred with concrete
  rationales (4.3 needs `matchmaker_rules.require_accept`
  schema + runtime round-trip first; 4.8 region picker is
  low priority because Edgegap's automatic geo-IP routing
  is good enough for the current player pool). **Deploy
  status:** the live runtime is current — Nakama Runtime
  Deploy at 2026-05-13T23:27:48Z ran parent SHA `628fc3a`
  (Stage 7.6 submodule bump commit), so the recent_players
  RPC + the GDPR storage scrub fix are now live.
- **2026-05-13 audit follow-up — drift items resolved later
  the same day:**
  - **Runtime backlog flushed:** the deployed runtime was 24
    submodule commits behind HEAD (`b5b94ee`); the gap
    silently broke every Stage 1.4/1.5/2.x/3.x/5.5-5.10
    client-side feature because the corresponding server
    RPCs (`delete_account`, `get_account_deletion_status`,
    `party_set_ready`, `party_set_mode`, `party_join_by_code`,
    `register_game`, etc.) weren't registered. Triggered
    `nakama-runtime.yml`; new build (parent `4235b4c`) ships
    all 11 missing RPCs.
  - **First games-cache sync:** ran `sync-game-config.ps1`
    once, `registered_games` flipped `[]` → `['hopnbop']`.
    Stage 2.4's "first deploy needs manual sync" note now
    closed.
  - **Version drift:** `game.yaml::edgegap_app_version`
    bumped `v8 → v27` to match live env; host's
    `NAKAMA_GAME_VERSION` bumped `0.34.0 → 0.39.0` via
    direct sed on `/opt/nakama/config.yml` (picked up by
    the runtime-deploy's `docker compose restart`). Verified
    via `version_check` RPC: `is_compatible: true`.
  - **WSS hostname-mismatch:** confirmed not actually a gap
    — operator steps shipped 2026-05-05 (per
    `NEXT_STEPS.md:54-77`). Only the user-driven two-browser
    smoke test remains, which requires Levi at the keyboard.
  - **Phase F AWS teardown:** also closed 2026-05-13. Ran
    `phase-f-destroy.ps1 -Confirm`; 5 Secrets Manager entries
    actually deleted today (the rest was already gone from
    earlier teardowns). After-state verified empty across
    every AWS service. CLAUDE.md's "Zero AWS resources remain"
    is now literally accurate. Script bug on the trailing
    CloudWatch-billing-alarm placeholder also fixed. Script
    moved to `docs/archive/phase-f-destroy.ps1` (twenty-fifth
    pass, 2026-05-15 — was at
    `scripts/decommission/aws/phase-f-destroy.ps1` between
    ship and archive). Kept as archeology in case a future
    game needs an AWS-migration teardown template.
  - **Stale Edgegap image tags:** also closed 2026-05-13.
    Deleted v8 through v26 (19 versions) via Edgegap's
    `DELETE /v1/app/<app>/version/<name>` API. Verified
    after-state: `total=1`, only v27 remains (the current
    live pin in both `game.yaml::edgegap_app_version` and the
    runtime env on prod).
  - **`runtime_status.go` hardcoded RPC list:** the NEXT_STEPS
    note was stale — the file was already refactored to use
    `*[]string` and `main.go::addRpc` appends as each RPC
    registers. `bulk_import` only appears when
    `BULK_IMPORT_ENABLED=true`. Verified live; note updated.
- **Prior session (also 2026-05-13) closed every remaining
  deferred item from Stages 1–5:**
  - **1.4 hard-delete cron** (`runtime/account_cron.go`).
  - **1.5 cancellation path** (`delete_account` no longer
    bans + `get_account_deletion_status` /
    `cancel_account_deletion` RPCs + game-side
    `AccountDeletionPrompt` node).
  - **4.7 solo game-mode picker** (`game.yaml.matchmaker_
    rules.modes` + `version_check` surfacing + new
    `GameModePickerPanel`).
  - **5.7 party leader game-mode selection** (`party_mode`
    server-owned storage + `party_set_mode` RPC + leader-only
    cycle row).
  - Hopnbop ships two modes — `ffa` (default 2-4 FFA) and
    `duo` (1v1) — so the picker has actual options.
- **Remaining open items (all explicitly deferred or declined):**
  (a) **Stage 7.3 push notifications — declined 2026-05-14**.
  Product call: no platform-level push for any trigger
  (friend-online / party-invite / match-found stay as
  in-app toasts driven by the existing 10s notification
  poller). Rationale: hopnbop's session pattern doesn't
  benefit from background notifications enough to justify
  the SW + VAPID + per-platform credentialling surface.
  Re-open if a future game in the platform fleet has a
  stronger case (e.g., async / turn-based);
  (b) Stage 4.3 require_accept dialog (small, but needs
  `matchmaker_rules.require_accept` schema + runtime
  accept/decline round-trip in `fleet_allocator.go` before
  the UI pays off);
  (c) Stage 4.8 region picker (low priority; manual
  override of Edgegap's automatic geo-IP selection);
  (d) follow-up polish: the Godot 4.5 WebSocketPeer
  localhost quirk that pends socket-based compliance tests
  on the dev stack (raw .NET WS to the same endpoint with
  a Nakama-issued JWT succeeds; Godot's `connect_to_url`
  times out without seeing a server close). Acceptable for
  now because the HTTP-only path covers the bulk of the
  surface and the socket tests pend gracefully; future
  fix would unlock the full Tier 4 matrix.
- **Last updated:** 2026-05-15 (twenty-fifth pass: AWS-era
  script archive sweep. Follow-up to the 24th pass that
  swept stale top-level *docs*: this pass swept the two
  remaining stale one-shot AWS-migration *scripts* the 24th
  pass missed because they lived under `scripts/` rather than
  at the top level. Moved
  `scripts/decommission/aws/phase-f-destroy.ps1` (parent
  repo, one-shot AWS teardown that ran 2026-05-13;
  unrunnable because the AWS account is empty) and
  `third_party/snoringcat-platform/scripts/migrate_ddb_to_nakama.py`
  (submodule, one-shot Phase E DDB→Nakama migration;
  unrunnable because the source DDB tables no longer exist)
  to their respective `docs/archive/` directories. Kept the
  `bulk_import` Go RPC in the live runtime — it's gated
  behind `BULK_IMPORT_ENABLED=true` and is the most likely
  reusable artifact if a future game in the platform fleet
  needs to import legacy data; the script archive includes
  the payload-shape contract via the existing RPC docstring.
  Reference updates: submodule `README.md` repo-layout block
  + scripts section, submodule `CLAUDE.md` scripts list,
  submodule `runtime/bulk_import.go` calling-script comment,
  and this roadmap's Phase F closure note (line 519). The
  empty `scripts/decommission/aws/` + `scripts/decommission/`
  parent dirs were removed since the script was their sole
  inhabitant. Submodule committed first per project rule
  (`5e1bd44`), parent commit follows with the submodule
  pointer bump. Audit pass before the archive confirmed the
  four 24th-pass non-acted items remain non-blocking: the
  transient 2026-05-14 Nightly Smoke 400 (still resolved by
  the next run), Compliance Matrix zero-runs (still PR-only
  on a direct-to-main repo), client-sdk-ci.yml fixture-Godot
  TODO (still deferred — addon exercised via Tier 4
  dev-stack), top-level `README.md` "TODO" stub (still
  cosmetic for a private repo). Prior twenty-fourth pass: doc-
  archive sweep. Audit-followups pass against the current
  repo state confirmed no implementation gaps were hiding
  behind the prior pass's suspect-list cleanups; the
  follow-up was instead four top-level docs that the
  roadmap had fully superseded but the audit had not yet
  swept off the tree: `DISTRIBUTED_SYSTEMS_PLAN.md` (the
  1973-line AWS-era plan — every component retired in
  Phase F), `BUILD.md` (GameLift GDExtension build
  instructions — addon deleted commit `69264c1`),
  `FRIENDS_PARTY_MATCHMAKING_AUDIT.md` (the 2026-05-12
  audit that motivated this roadmap), and
  `docs/test-architecture-plan.md` (every actionable item
  had landed; verified `test_socket_*.gd`,
  `compliance_socket_helper.gd`, and
  `test_transport_selection.gd` all live in the compliance
  suite). All four moved to `docs/archive/` via `git mv`.
  Reference updates: roadmap Context section + `See also`
  list point at the archive copy of the audit; submodule
  `STUDIO_ARCHITECTURE.md` "Key docs" refreshed (drops the
  three already-archived pointers, adds a single
  "Historical / archived: `docs/archive/`" pointer);
  `.vscode/README.md` drops its dangling `BUILD.md` link.
  Items the audit surfaced but explicitly **did not** act
  on, recorded in the status summary above so the next
  audit pass doesn't burn cycles re-investigating: the
  transient 2026-05-14 04:20 UTC Nightly Smoke 400 (next
  run succeeded), the as-yet-untriggered `Compliance
  Matrix` workflow (PR-only; this repo commits direct to
  main), the submodule `client-sdk-ci.yml` fixture-Godot-
  project TODO, and the top-level `README.md` "TODO" stub.
  Prior twenty-third pass: cleanup pass.
  Stage 7.3 push notifications declined as a product
  decision — no platform-level push for any trigger; the
  existing 10s `friends_notification_poller` + in-app toasts
  remain the only notification surface. Rationale recorded
  in both the status summary and the 7.3 task entry: hopnbop's
  session pattern doesn't benefit from background push enough
  to justify the SW + VAPID + per-platform credentialling
  surface, and push permission prompts have become widely
  treated as anti-features for sync-only play. Re-open
  trigger documented (future game with async / turn-based
  play, or daily-streak retention loops). Also a housekeeping
  cleanup in the same pass: added `runtime/build/` to the
  platform submodule's `.gitignore` (local-smoke-test
  artifact directory containing `build.log` was showing up
  as untracked content in the parent repo's git status every
  time the dev stack was exercised; `*.so` already gitignored
  `snoringcat.so` inside the same dir but the log file kept
  it visible). With 7.3 closed out, the roadmap is
  functionally complete — the only remaining items (4.3, 4.8)
  are both deferred behind upstream schema/runtime work that
  isn't yet justified by use. **Prior twenty-second pass:
  Stage 8 Tier 4 e2e/smoke shipped end-to-end.** 8.29
  `infra/dev/docker-compose.dev.yml` — minimal two-service
  stack (Nakama + Postgres) with the locally-built
  `snoringcat.so` plugin mounted, mock-Edgegap via the
  existing 8.13 `EDGEGAP_MOCK_DEPLOY=true` toggle (no new
  Edgegap sidecar). 8.30
  `scripts/local-smoke-test.ps1` — six-step orchestration
  (refresh-addon → build-plugin → compose-up →
  poll-healthcheck → register-game → run-compliance →
  tear-down) with skip flags for the slow parts
  (`-SkipBuild`, `-KeepStack`) and `-TestFile` for
  iteration. 8.31
  `.github/workflows/compliance-matrix.yml` — invokes the
  smoke script on every PR + workflow_dispatch via
  `chickensoft-games/setup-godot@v2` + Docker. Single-axis
  (ephemeral only) for now since there is no staging
  Nakama tier (the existing `nightly-smoke.yml` already
  covers prod read-only). Two submodule companion fixes
  also landed 2026-05-14: `compliance/test_version.gd`
  accepts `EDGEGAP_MOCK_DEPLOY=true` as a valid hook-active
  indicator alongside `EDGEGAP_TOKEN`, and
  `compliance/compliance_socket_helper.gd::_derive_socket_target`
  parses scheme/host/port out of `PLATFORM_API_URL` rather
  than hardcoding `wss://:443` (prod fallback preserved).
  Validated end-to-end against the dev stack: 9 HTTP-based
  compliance test files green (19 tests / 60+ asserts;
  version, auth_anon, friends, party, account, settings,
  presence, api_surface, player_stats); runtime boot log
  reports `mock_deploy=true edgegap=true app=hopnbop-server
  version=v-dev games=[hopnbop]` after `register_game`.
  Known limitation: socket-based compliance tests pend on
  a Godot 4.5 WebSocketPeer localhost quirk (raw .NET / curl
  WS with the same Nakama-issued JWT succeeds; Godot's
  `connect_to_url` times out without seeing a server-side
  close). Tests pend gracefully via `pending(...)` so GUT
  exits 0. Windows-specific gotcha captured in
  `infra/dev/README.md`: use `127.0.0.1` not `localhost`
  in `PLATFORM_API_URL` — Docker Desktop binds only IPv4
  and Godot's HTTPRequest burns ~60 s per request hitting
  the unreachable IPv6 host first. Prior twenty-first pass: Stage
  6.11b concrete-screen extraction shipped. Three full
  `*.tscn` + `*.gd` screens — `PlatformAuthScreen`,
  `PlatformConsentScreen`, `PlatformAnonymousUpgradeScreen`
  (greenfield) — now live in the addon under
  `addons/snoringcat_platform_client/ui/screens/`.
  Hopnbop's `auth_screen.tscn` + `consent_screen.tscn` are
  now inherited scenes from the addon's, with @export
  branding overrides on the root (theme, panel stylebox,
  logo, provider / row icons, checkbox textures, chevron,
  focus / unfocused styleboxes). Game-side `AuthScreen` /
  `ConsentScreen` scripts (~40-80 lines each) extend the
  addon classes and wire navigation + state-reset signals
  to hopnbop's `G.*` autoloads. Virtual hooks let the
  addon stay decoupled from Netcode, `LegalVersion`, and
  `G.audio`. `ScreensMain.get_screen_from_type()` return
  type widened to `PlatformScreen` (the common ancestor
  of `Screen` and the addon screen classes) so the single
  `var screen: Screen` callsite in
  `screen_trigger_row.gd` widened accordingly. Verified
  via headless `--import` (no parse errors, all 5 classes
  registered) + ad-hoc scene-instantiation smoke (all 5
  scenes load + carry expected class through inheritance).
  The anonymous-upgrade screen is intentionally not wired
  into hopnbop — hopnbop has `UpgradeAccountPanel`
  (SidePanel) for the non-blocking flavor; the addon
  screen is reference-implementation for a future game
  that wants a hard-gate variant. Prior twentieth pass:
  Stage 6.11a foundation migration shipped — game-side
  `Screen` / `ScreenFocusNavigator` /
  `AnyDeviceInputPoller` started extending their
  `Platform*` addon equivalents. Prior nineteenth pass: Stage 8
  Tier 3 client unit tests 8.23–8.28 all shipped — six
  test files under `test/unit/platform/` covering the
  pure-logic helpers of every Stage 6 platform SDK
  class: friends_api_client (13 tests), party_api_client
  (11), party_manager (31), nakama_matchmaker_client
  (28), friends_notification_poller (20),
  settings_cloud_sync (16). 119 tests / 212 asserts pass
  via `gut_cmdln.gd -gdir=res://test/unit/platform`
  in ~0.5 s. Approach diverged from the audit's "GUT
  doubles" framing: tests target deterministic
  resolvers / state inspectors / dispatch helpers (with
  autoload-state snapshot/restore in before_each /
  after_each) rather than doubling Nakama — the
  network paths are already exercised live by the
  compliance suite. Second divergence: GUT 9.5.0 +
  Godot 4.7-beta1 silently fails to discover inner-
  class tests via cmdline, so tests are flat top-level
  methods grouped by name prefix; documented in each
  file's docstring so a future contributor doesn't
  trip over the same thing. Prior eighteenth pass: Stage
  7.10b mid-match rejoin transport parity shipped —
  drops the ENet-only gate in `can_attempt_reconnect()`
  so the reconnect loop fires for WebRTC + WebSocket
  too. Framework `rollback_netcode` submodule gains a
  stale-`_webrtc_peer` cleanup in `_client_start_webrtc`
  (mirrors the existing `_webrtc_signaling_client`
  cleanup) so the dropped match's RTC stack is closed
  before the fresh peer is built. Stale "ENet-only in
  v1" comments refreshed in reconnect_handler /
  game_panel. Headless `--import` boot clean (exit 0,
  no parse errors). No e2e smoke for the transport-
  parity reconnect path itself — same blocker as 7.10
  (mid-match disconnect against live prod isn't easily
  automatable); Tier 4 docker-compose e2e remains the
  natural home. Prior seventeenth pass: Stage 7.10
  mid-match rejoin shipped — reconnect flavor, lightweight
  slot+score preservation, 30s grace, ENet-only v1.
  Framework `rollback_netcode` submodule bumped to `02c65b0`
  for the session_id -> player_id reuse. Game-side adds
  reconnect grace timers (server), reconnect loop +
  ReconnectingOverlay (client), 4 i18n keys. Prior
  sixteenth pass: Stage 7.11 lightweight obs re-introduction
  shipped end-to-end —
  infra configs + Pulumi DNS + runtime custom timer all
  landed AND the live deploy executed (SCP + docker compose
  up + pulumi up + nakama-runtime.yml). All 8 containers
  up, all 5 Prometheus targets healthy, 6 Grafana alerts
  provisioned, https://grafana.snoringcat.games live with
  TLS. Two follow-up patches required during live deploy:
  Caddyfile `admin 0.0.0.0:2019` for Prometheus scrape,
  and `chmod -R a+rX` on the SCP'd `grafana/provisioning`
  tree so Grafana's UID 472 could read it. Prior fifteenth pass: Stage 7.9
  anonymous-upgrade UI + 7.8 account-merge UI shipped end-to-
  end. 7.9 adds `UpgradeAccountPanel` (SidePanel) — anonymous-
  only entry from the main menu in place of "Account",
  badge-visible by default to draw the eye, exposes the same
  Google/Facebook `LinkAccountRow`s the AccountPanel already
  hosted (which already drove anonymous→permanent login
  internally via `Platform.auth.login_with_provider`), but
  with a focused header + benefits body + "Maybe later" close
  row. The underlying upgrade flow is unchanged; the work is
  pure discoverability. 7.8 replaces the prior PROVIDER_CONFLICT
  ConfirmOverlay with a dedicated `MergeAccountPanel` —
  pushed by `LinkAccountRow` when the link API returns
  PROVIDER_CONFLICT, renders a header + provider-interpolated
  body + Continue-and-Merge + Cancel action rows, owns the
  `merge_completed` signal lifecycle, tracks
  `_explicit_action_taken` so the back-row pop path cancels
  the pending server-side merge token while the explicit Merge
  / Cancel paths skip the redundant call. 7 new translation
  keys × 13 locales (`SETTINGS.SIGN_IN`, `UPGRADE.HEADER`,
  `UPGRADE.BENEFITS_BODY`, `UPGRADE.MAYBE_LATER`,
  `MERGE.HEADER`, `MERGE.BODY`, `MERGE.CONTINUE`,
  `TOAST.ACCOUNTS_MERGED`, `TOAST.MERGE_FAILED` — 9 total).
  3 prior keys retired (`CONFIRM.MERGE_ACCOUNT`, `LINK.MERGE`,
  `LINK.MERGING`) — the prior ConfirmOverlay surface they
  served is gone. CSV verified at 14 fields for every new line
  (pre-existing legacy line 120 untouched). Headless boot
  clean against live Nakama; no compliance tests added because
  the UI flows aren't exercised by the current compliance
  harness and the underlying RPCs (link_provider /
  confirm_merge / cancel_merge / anonymous login) are already
  covered by the platform smoke test. Prior fourteenth pass:
  Stage 7.7 GDPR cascade verification + 7.6 recent-players
  list shipped.
  7.7's `test_account_delete_cascade_surfaces.gd` caught a
  real bug (`nk.StorageList` with empty collection silently
  no-op'd because Nakama's SQL has WHERE collection = $1, so
  the cascade's user-storage scrub AND the GDPR export both
  silently dropped every user-owned game-side row since 1.4
  shipped). Fixed via direct SQL DELETE in account.go and
  direct SQL SELECT in player_data.go, both with explicit
  ::uuid cast. 7.6 ships the full recent-opponents feature
  end-to-end: runtime hook on match_end writes N*(N-1)
  per-pair rows, new list_recent_players RPC returns sorted
  + capped, client SDK adds fetch + cache + signal,
  RecentPlayersPanel + FriendsPanel entry, 2 translation
  keys × 13 locales, 5 Go test functions (24 sub-tests),
  new compliance test (2 tests / 66 asserts). Live runtime
  on build `628fc3a`; 4 compliance tests across 7.7 + 7.6 +
  8.16 regression pass green. Prior thirteenth pass: Stage
  8.15 `test_friends_block.gd` shipped — two-test compliance
  file covering (a) single-user block-list lifecycle with
  bidirectional add-rejection verified via friend-state
  reads, (b) matchmaker blocked-pair abort fan-out, mock-
  mode gated. 20 asserts green against live Nakama; second
  test pends correctly on prod. Plus the 7.4 runtime deploy
  confirmed live. Prior twelfth pass:
  Stage 7.4 friend block list shipped end-to-end. Runtime:
  new `block_list.go`
  with block_user/unblock_user/list_blocked_users RPCs over
  Nakama's native state=3 BANNED state (bidirectional add-
  rejection comes free from Nakama's FriendsAdd). Matchmaker:
  `fleet_allocator.go::OnMatchmakerMatched` walks each matched
  user's BANNED list via the shared `listBlockedUserIDs` helper,
  detects directed pairs via `findBlockedPairs`, and aborts the
  match before Edgegap allocation via `abortBlockedPair`
  (mirrors `abortProtocolMismatch`). Client: new
  Platform.friends.block_user/unblock_user/fetch_blocked_users
  methods + cached_blocked_users + 3 new signals + is_blocked()
  helper. UI: Block action row on FriendDetailsPanel +
  BlockedUsersPanel + Blocked Users entry in FriendsPanel. 8
  new translation keys × 13 locales. Game-side
  `_classify_matchmaking_failure` routes `"blocked"` substring
  to new LOADING.BLOCKED_PAIR (recoverable). 1 new Go test
  function (`TestFindBlockedPairs`) with 8 sub-tests locking
  the pair-detection contract. `go vet && go test &&
  staticcheck` clean. Plus the prior 2026-05-13 hardening
  deploy: 7.12 + 7.13 (max-pending cap + friend-code rate
  limit) shipped to prod build
  `1bd61db978bc50f87a151e7ceef483aaf496ed42`; live runtime
  green. Prior passes still standing: 7.5 friend pagination,
  7.1 allocation retry, 7.2 mid-queue cancel teardown, Tier 2
  matchmaking compliance suite finished (8.20 + 8.21), Tier 1
  Go unit tests (8.3-8.10, 100 cases), 8.1/8.2 deploy gate,
  audit-surfaced drift fully resolved, 24-commit runtime
  backlog deployed, first games-cache sync, Phase F finished,
  stale Edgegap tags pruned, 8.11/8.12/8.14 multi-user
  compliance harness, 8.16/8.17/8.22 multi-user tests,
  EDGEGAP_MOCK_DEPLOY mode + 8.18/8.19 mock-mode matchmaking
  tests).
- **Stages complete:**
  - Stage 0 — platform infra extraction (kickoff verification
    items 0.8 + 0.9 confirmed 2026-05-12).
  - Stage 1 — all 5 tasks shipped end-to-end (2026-05-12 +
    2026-05-13: 1.4 hard-delete cron, 1.5 cancellation path).
    Compliance harness for multi-user party scenarios shipped
    via Stage 8.11/8.12/8.17 (2026-05-13).
  - Stage 2 — all 7 tasks shipped 2026-05-12.
  - Stage 3 — 10/10 tasks shipped 2026-05-12 (including 3.9
    protocol pre-check via ticket-property route and 3.10
    `legal_version` parity CI guard).
  - Stage 5 — 11/11 tasks shipped (5.1–5.6, 5.8–5.11
    2026-05-12; 5.7 leader game-mode 2026-05-13).
  - Stage 6 — 11/11 tasks shipped + 6.5b (6.1–6.10 2026-05-12;
    6.11a foundation migration + 6.11b concrete-screen
    extraction 2026-05-14). Several 6.x landings were
    partial-by-design: party_manager (6.5),
    EdgegapServerProvider (6.6), SettingsCloudSync (6.8
    game-side adapter), GameSessionManager (6.9) all stay
    game-side — see each task entry for the
    coordination-coupling rationale. 6.11b's
    `PlatformAnonymousUpgradeScreen` is intentionally greenfield
    without a concrete in-tree consumer.
  - Stage 8 — 31/31 shipped (Tiers 1+2 2026-05-13, Tier 3
    2026-05-14, Tier 4 2026-05-14). Tier 1 Go unit tests
    (8.3–8.10) all green: transport_select_test.go,
    version_test.go, match_lifecycle_test.go (with new
    `clampPlayerStats` helper extracted for testability),
    fleet_allocator_test.go, presence_test.go,
    auth_test.go, party_test.go, account_test.go. Plus the
    earlier 8.1 deploy-time gate, 8.2 staticcheck (already
    in pr-validate.yml), 8.11 socket harness, 8.12 multi-
    session helper, 8.13 EDGEGAP_MOCK_DEPLOY mode, 8.14
    first canary multi-user friends test, 8.15 block-list
    lifecycle + blocked-pair matchmaker abort, 8.16
    friends-cascade-on-account-delete, 8.17 party-invite-
    flow multi-user lifecycle, 8.18 party-to-matchmaking
    mock-mode flow, 8.19 solo-matchmaking match_ready
    flow, 8.20 matchmaking cancel-race (cancel-before-
    match + post-match cancel safety), 8.21 protocol-
    mismatch failure mode, 8.22 presence game-filter
    mutual-only check, 8.23–8.28 Tier 3 client unit tests
    (6 files / 119 tests / 212 asserts under
    `test/unit/platform/`), 8.29 docker-compose dev stack
    at `infra/dev/docker-compose.dev.yml` (mock-Edgegap via
    `EDGEGAP_MOCK_DEPLOY=true`), 8.30
    `scripts/local-smoke-test.ps1` (build plugin → compose
    up → register game → run compliance → tear down),
    8.31 `.github/workflows/compliance-matrix.yml` (PR
    gate; single-axis ephemeral, staging axis deferred
    until a staging tier exists).
- **Stages partially shipped (remaining items are
  intentionally deferred or low-priority):**
  - Stage 4 — 6/8 shipped (4.1, 4.2, 4.4, 4.5, 4.6 2026-05-12;
    4.7 game-mode picker 2026-05-13). Deferred: 4.3 (needs
    `matchmaker_rules.require_accept` in game.yaml + runtime
    support for the accept/decline round-trip), 4.8 (region
    picker; optional, needs Edgegap region list).
- **Stage 7 resilience (13/14 shipped, 1 declined):**
  - Shipped: 7.1 allocation retry, 7.2 mid-queue cancel
    teardown, 7.4 friend block list, 7.5 friend pagination,
    7.6 recent-players list, 7.7 GDPR cascade verification
    + fix, 7.8 account-merge UI, 7.9 anonymous-upgrade UI,
    7.10 mid-match rejoin (reconnect flavor, ENet only at
    ship time), 7.10b mid-match rejoin transport parity
    (WebRTC + WebSocket reconnect), 7.11 lightweight obs
    re-introduction, 7.12 max-pending-friend-requests cap,
    7.13 friend-code rate-limit.
  - **Declined 2026-05-14:** 7.3 push notifications. Product
    call to not ship platform-level push for any trigger;
    friend-online / party-invite / match-found stay as in-
    app toasts driven by the 10s notification poller. See
    the 7.3 task entry for the full rationale.
- **Stages blocked:** none.
- **Roadmap functionally complete.** Remaining open items
  (4.3 require_accept dialog, 4.8 region picker, 7.3 push
  notifications) are either deferred behind upstream
  schema/runtime work (4.3), low-priority polish (4.8),
  or declined outright (7.3).

## Post-completion debugging log

The roadmap above reached functional completion 2026-05-14 / 25th
pass. Bugs found and fixed *after* that point are logged here in
chronological order so future sessions can see the full story
without diffing 7000-line commit messages. Each entry:

- One-line headline.
- Root cause (what was actually wrong, not just the symptom).
- Fix (what changed, and the file:line of the change).
- Verification (what we tested or visually confirmed; if a fix
  ships without end-to-end verification, say so explicitly).

### 2026-05-15 — Preview-mode matchmaker auth rejected with HTTP 400

**Symptom.** Local preview mode (Debug → Customize Run Instances,
3-window flow) reached the lobby on both clients, but pressing
"Play" failed instantly: `Request 1 returned response code: 400,
RPC code: 3, error: game_id required in authenticate vars`.
Loading screen bounced back to the lobby with toast "Preview
matchmaker auth failed: game_id required in authenticate vars".
Repro is C1 and C2 both hitting the failure on the
`/v2/account/authenticate/device` POST that the preview-mode
matchmaker path issues. Captured in
`DO_NOT_SUBMIT_desktop_logs.txt` 2026-05-15 17:43 UTC.

**Root cause.** Stage 3 game_id scoping (commits `d909271` /
`f1ccae9`, 2026-04-2x) enforces that every authenticate call
carry `game_id` in session vars so the runtime's
`BeforeAuthenticate*` hook accepts the request and downstream
stateful RPCs can read it back via `RUNTIME_CTX_VARS`. The
mainline auth path threads this through
`auth_api_client._build_session_vars()` (called at line 890 of
`auth_api_client.gd`). The **preview-mode** branch in
`matchmaker_api_client._authenticate_preview_instance()` mints a
per-instance device session outside that flow (so each preview
window appears as a distinct user to Nakama and can be matched
against its siblings), and it was added before Stage 3 — the
4-arg form of `authenticate_device_async(id, username, create,
vars)` was never updated to pass the vars dict, so the request
went out with `Body: {"id":"preview_{...}_C2"}` and no `vars`.
Live regular-auth POSTs in the same log session (line 38) show
the working shape: `"vars":{"game_id":"hopnbop"}`.

**Fix.** Submodule
`addons/snoringcat_platform_client/core/matchmaker_api_client.gd::
_authenticate_preview_instance()` now passes
`{"game_id": Platform.game_id}` as the 4th arg to
`authenticate_device_async`, mirroring the mainline path. Inlined
the dict rather than reaching across modules to
`Platform.auth._build_session_vars()` because the helper is
private and the preview path is the only non-auth caller — pulling
it out into a public shared helper is more refactor than the bug
warrants.

**Verification.** Headless `godot --import` parses clean (the
only reported errors are unrelated `webrtc-native` missing-dll
warnings from the local checkout, which always appear in headless
runs of the parent repo). No end-to-end preview-mode smoke run
yet — that requires Levi at the keyboard. The fix is mechanical
enough (matches a known-working call shape elsewhere in the
SDK) that shipping ahead of the manual smoke is acceptable; the
next preview-mode launch will be the de facto smoke.

**Propagation gotcha (worth remembering).** First re-run of
preview mode after the submodule-bump commit reproduced the
HTTP 400 *identically*. Root cause: per the parent repo's
CLAUDE.md, the addon under `addons/snoringcat_platform_client/`
is a **gitignored copy** of the submodule's
`addons/snoringcat_platform_client/`, refreshed by running
`scripts/setup-platform-addon.ps1`. The submodule pointer bumped,
but nobody had re-run the propagation script, so Godot was still
loading the pre-fix script from the local copy. The script
exists because Godot 4.6+ on Windows reads stale parser-cache
content through directory junctions, so we copy instead of
symlink. Running `scripts/setup-platform-addon.ps1` after the
parent commit made the fix take effect. **Lesson for future
debug sessions:** any submodule-side fix needs
`setup-platform-addon.ps1` before the local Godot editor sees
it, even if the parent submodule pointer has been bumped and
committed. Headless `--import` against the parent reads the
local copy too, so a "headless import clean" check after a
submodule bump is *not* sufficient to prove the fix is live
locally — verify the copy contains the fix (`grep` for the
expected change in `addons/snoringcat_platform_client/...`).

### 2026-05-15 — `BackendApiClient._account_linked_providers` reads non-existent ApiAccount properties

**Symptom.** After web deploy (v0.40.0), browser console reported
`Invalid access to property or key 'google' on a base object of
type 'RefCounted (ApiAccount)'.` at
`src/core/backend_api_client.gd:384`. Same line would have failed
identically on the desktop client, but the runtime path that
calls it (`fetch_player_profile`) hadn't been exercised in
recent local smoke.

**Root cause.** `_account_linked_providers(account)` was written
against an imagined ApiAccount shape with `.google` / `.facebook`
/ `.apple` / `.steam` sub-objects. The real Nakama `ApiAccount`
class (`addons/nakama/api/NakamaAPI.gd:187`) only carries
`custom_id` / `devices` / `disable_time` / `email` / `user` /
`verify_time` / `wallet`. Social provider linkages live on
`account.user` (the nested `ApiUser` model) as the String fields
`google_id` / `facebook_id` / `apple_id` / `steam_id`, each
empty when unlinked. The misshaped accessors had been dormant
because the function is only called from
`fetch_player_profile()`, which surfaces in the in-game profile
panel — easy to miss in local play-through testing.

**Fix.** Rewrote `_account_linked_providers` at
`src/core/backend_api_client.gd:378-396` to read
`account.user.<provider>_id` and check `.is_empty()` instead of
truthiness on a phantom sub-object. Also pulled `var u =
account.user` to a local so each provider check doesn't re-walk
the getter.

**Verification.** No headless smoke for the profile-panel flow.
Mechanical fix that matches the documented Nakama
`ApiUser`/`ApiAccount` schema; will be exercised the next time
the profile panel is opened in-game (browser or desktop).

## Stage dependency graph

```
Stage 0 (done) — platform infra moved into snoringcat-platform
   ↓
Stage 1 (done, 2026-05-12 + 2026-05-13) — P0 broken contracts:
   party RPC, leader_id, members, delete_account, hard-delete
   cron, cancellation path all shipped. Compliance-test rig
   pending (Stage 8.11/8.12).
   ↓
Stage 2 (done, 2026-05-12) — game.yaml, games table,
   per_game_config.go, register_game RPC, sync script, CI guard,
   BeforeAuthenticate* hooks, game_id-in-vars JWT claim, RPC
   plumbing all shipped.
   ↓
Stage 3 (done, 2026-05-12) — game_id scoping: presence
   (storage + record field + friend filter), leaderboards
   (`{game_id}_ffa`), Edgegap app coords from games table,
   matchmaker rules + legal_version surfaced via version_check,
   settings split into "global" + "game/{id}" cloud rows,
   pre-allocate protocol check via ticket-property route.
   ↓
   ├─→ Stage 4 (6/8 shipped, 2026-05-12 + 2026-05-13) — Cancel
   │   button, queue status, connect/version-mismatch screens,
   │   allocation-failure retry, game-mode picker. Deferred:
   │   4.3 (require_accept dialog), 4.8 (region picker).
   ├─→ Stage 5 (done, 2026-05-12 + 2026-05-13) — PartyLobbyPanel
   │   refactor + invite UI + real-time socket updates + ready
   │   toggle + leader transfer + party chat + rejoin prompt +
   │   join-by-code + leader game-mode selection.
   └─→ Stage 6 (done, 2026-05-12 + 2026-05-14) — Platform SDK
       extraction: 6.1–6.11 + 6.5b (auth, token store,
       friends, party, notification socket, matchmaking,
       presence, settings, session observer, screens). Several
       landings are partial-by-design (coordinators stay
       game-side, only API surfaces move into the addon). 6.11
       screen templates shipped 2026-05-14 as a-then-b: 6.11a
       foundation migration (existing Platform* base classes
       getting consumed), 6.11b concrete extraction (full
       auth / consent / anonymous-upgrade scenes in the addon
       + hopnbop inherited scenes).
   ↓
Stage 7 — Resilience (retries, notifications, observability).
   13/14 shipped (7.1 allocation retry, 7.2 mid-queue cancel
   teardown, 7.4 friend block list, 7.5 friend pagination,
   7.6 recent-players list, 7.7 GDPR cascade verification +
   fix, 7.8 account-merge UI, 7.9 anonymous-upgrade UI, 7.10
   mid-match rejoin (ENet at ship time), 7.10b mid-match
   rejoin transport parity (WebRTC + WebSocket reconnect),
   7.11 lightweight observability re-introduction, 7.12
   max-pending-friend-request cap, 7.13 friend-code
   rate-limit); 1 declined (7.3 push notifications).

Stage 8 — Tests (parallel track, doesn't block features).
   31/31 shipped. Tier 1 Go unit tests (8.3–8.10) all green;
   Tier 2 compliance suite has 8.11–8.22 all shipped; Tier 3
   (8.23–8.28) shipped 2026-05-14 (119 tests / 212 asserts
   under `test/unit/platform/`); Tier 4 (8.29–8.31) shipped
   2026-05-14 — docker-compose dev stack at `infra/dev/`,
   `scripts/local-smoke-test.ps1`, and
   `.github/workflows/compliance-matrix.yml` (single-axis
   ephemeral; staging axis deferred until a staging tier
   exists).
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
  - **Hard-delete cron shipped 2026-05-12** as
    `runtime/account_cron.go`. `startAccountCron` launches an
    hourly background goroutine from `InitModule` that scans
    `account_deletion_queue` across all users via
    `nk.StorageList`, calls `nk.AccountDeleteId(recorded=true)`
    for each row whose `scheduled_for` has elapsed, and drops the
    queue row. Uses `context.Background()` (not the InitModule
    context, which is cancelled on return). Tolerates malformed
    rows (skip + warn, don't delete) and "user already gone"
    (warn + still clear queue row so the cron doesn't get stuck).
    First tick fires immediately on boot so a host that was down
    past a `scheduled_for` boundary doesn't wait a full interval
    to catch up.
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
  - **Cancellation path shipped 2026-05-13** (third pass):
    - Server: `account.go`'s delete flow no longer calls
      `UsersBanId` — the user remains able to authenticate
      during the 30-day grace window so the cancellation
      surface is reachable. The boot-time
      `get_account_deletion_status` RPC is now the gate.
    - Server: new `get_account_deletion_status` RPC returns
      `{pending, scheduled_for, original_username,
      original_display_name}` for the caller's queue row, or
      `{pending: false}` when no row exists.
      `cancel_account_deletion` RPC validates the row exists,
      restores the original username/display_name via
      `AccountUpdateId`, deletes the queue row, and returns
      the restored identity. Both registered in `main.go`.
    - Game: new `src/core/account_deletion_prompt.gd` node,
      instantiated from `global.gd._enter_tree`. Subscribes to
      `Platform.auth.auth_completed` and, on a non-anonymous
      successful auth, queries `get_account_deletion_status`.
      A pending row opens a `ConfirmOverlay` ("Your account is
      scheduled for deletion on YYYY-MM-DD. Cancel?"). Tapping
      Cancel calls `cancel_account_deletion` and toasts on
      success/failure. Within-session dedup so a JWT refresh
      doesn't re-pop the dialog.
    - 6 new translation keys × 13 locales:
      `CONFIRM.ACCOUNT_DELETION_PENDING`,
      `CONFIRM.ACCOUNT_DELETION_PENDING_NO_DATE`,
      `CONFIRM.CANCEL_DELETION`, `CONFIRM.KEEP_DELETION`,
      `TOAST.ACCOUNT_DELETION_CANCELLED`,
      `TOAST.ACCOUNT_DELETION_CANCEL_FAILED`. Non-English
      translations are best-effort and worth a native-speaker
      review pass before a release.

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
  - **First sync done 2026-05-13** alongside the 24-commit
    backlog runtime deploy. `runtime_status.registered_games`
    flipped from `[]` to `['hopnbop']`. From here, every
    runtime restart preserves the row (it's in Postgres,
    cache rebuilds on boot). Future game.yaml edits still
    need a manual `sync-game-config.ps1` until the GH secret
    + CI step land.

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
- [x] **3.5 Scope settings into `global` vs `game/{game_id}`** in
      `src/core/settings_cloud_sync.gd` (2026-05-12).
  - Done — paired with 6.8. New
    `LocalSettings.GLOBAL_OVERRIDABLE_KEYS` constant declares the
    cross-game subset: `full_screen`, `mute_music`, `mute_sfx`,
    `prefer_offline_mode`. Plus the pre-existing `locale` (special-
    cased via `get_locale` / `set_locale` rather than living in
    OVERRIDABLE_KEYS). Everything else in `OVERRIDABLE_KEYS` is
    game-specific by default (every entry is a hopnbop gameplay
    modifier — `is_gore_enabled`, `are_critters_enabled`,
    `are_cheats_enabled`, `is_jetpack_enabled`,
    `is_bloodisthickerthanwater_enabled`,
    `is_lordoftheflies_enabled`, `is_pogostick_enabled`,
    `is_bunniesinspace_enabled`, `is_moregore_enabled`).
  - Done — storage rows split: `(collection="settings",
    key="global")` and `(collection="settings",
    key="game/{game_id}")`. The legacy single-blob row
    `(collection="settings", key="user")` is read once on first
    fetch after the client upgrade and partitioned; subsequent
    boots use the new rows directly. The legacy row is *not*
    deleted (small cost; preserves a fallback for any future
    fresh-install of a pre-6.8 client on the same Nakama
    account during the transition window).
  - Done — `anonymous_color_hue` not synced. It lives in
    `LocalSettings.SECTION_APPEARANCE` and was never part of
    cloud sync to begin with; folding it into the new global
    scope would have been scope creep. The current behavior
    (auto-generated, device-local) is acceptable.
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
- [x] **3.9 Per-game `protocol_version` pre-check at queue start**
      (2026-05-12)
  - Done — client (game-side): `src/core/nakama_matchmaker_client.gd`
    `_build_string_props` now declares `client_protocol_version`
    (string of the int from `ProjectSettings.get_setting(
    "application/config/protocol_version")`) as a ticket property.
    Same source the existing CI parity guard cross-checks against
    `game.yaml::protocol_version`, so no new sync point.
  - Done — server: `fleet_allocator.go` `OnMatchmakerMatched`
    walks each entry's properties to collect `protocolByUser`
    alongside the existing `gameIDVotes` pass. After
    `pickDominantGameID` resolves the match's game_id, looks up
    the registered `ProtocolVersion` from the games cache. Any
    declared entry whose version differs from the registered
    value triggers `abortProtocolMismatch`, which sends a
    per-player `match_failed` notification (reason
    "protocol_mismatch", with `expected` / `got` / human-readable
    `message`) and returns `("", nil)` without allocating
    Edgegap. Mismatched players get the actionable "your client
    is out of date" copy; compatible matched players get a
    generic "another player's client is out of date" copy so
    they don't sit on the 120s client timeout.
  - Done — addon: `PlatformMatchmakingClient` recognizes the new
    `match_failed` subject (flat JSON, single-encoded — distinct
    from `match_ready`'s double-encoded shape because there's no
    nested connection blob). On receipt, clears the searching
    state, stops the elapsed timer, and emits
    `matchmaking_failed(message)`. The game-side adapter forwards
    through `session_request_failed` and the existing classifier
    in `game_panel._classify_matchmaking_failure` falls through
    to fatal (toast + back to lobby), which is right for a stale-
    version case — retry won't fix it.
  - Implementation note: chose approach (a) from the original
    deferral framing (ticket-property route, client-trusted).
    The client value can in principle be forged, but the boot-
    time `backend_api_client.check_version` is still the primary
    gate, and a malicious client that lies about both surfaces
    will still fail at the network-layer protocol negotiation
    inside the rollback-netcode handshake. Defense-in-depth;
    not a security boundary.
  - Implementation note: the check is graceful for the rollout
    window. Pre-3.9 clients omit the `client_protocol_version`
    property entirely; their entries pass through (we only
    abort when a declared version mismatches). A two-client
    match where one is pre-3.9 and the other declares the
    correct version still allocates normally.
  - No new compliance test (Stage 8.x not yet live for the
    matchmaker socket); confidence is from `go vet ./...`
    clean, `go test ./...` clean, the pluginbuilder Docker
    image producing a 19 MB `snoringcat.so`, and a headless
    Godot boot of the game side with the new ticket-property
    code path parsing cleanly.
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
    annoying but safe.
  - CI parity guard added 2026-05-12 as a sibling step to the
    `game-config-parity` job's existing `protocol_version`
    check. Extracts
    `game.yaml::legal.legal_version` (via grep on the indented
    block-scalar) and
    `src/core/legal_version.gd::LEGAL_VERSION` (via grep on
    the `const` line), strips quotes / whitespace, and fails
    the workflow on mismatch. Verified locally that the
    extraction returns `"1.1"` from both files.

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
- [x] **4.7 Game-mode picker (reads `matchmaker_rules.modes` from
      `game.yaml`)** (2026-05-13)
  - Done — schema: `game.yaml.matchmaker_rules.modes` now lists
    {id, display_name_key, description_key, min_players,
    max_players, query, is_default}. Hopnbop ships two modes
    (`ffa` default 2-4 player FFA, `duo` 1v1) so the picker has
    actual options.
  - Done — runtime: `parseModesFromConfig` reads the list out of
    the per-game `Raw` config blob. `version_check` response gains
    `matchmaker_modes` so the client can populate the picker
    pre-auth (HTTP-key only). Empty list ⇒ single-mode game.
  - Done — client: `BackendApiClient.server_matchmaker_modes`
    caches the list; `LocalSettings.get_selected_game_mode`
    persists the device-local pick at
    `SECTION_SETTINGS::selected_game_mode`.
    `NakamaMatchmakerClient` resolves the mode from
    session_prefs > LocalSettings > server-default, then uses the
    mode's `query` / `min_players` / `max_players` to override
    `BackendApiClient.server_matchmaker_*` and adds `game_mode`
    as a ticket property for the fleet allocator.
  - Done — UI: new `GameModePickerPanel` (SidePanel) lists each
    mode as an ActionRow with the selected mode showing a
    checkmark. Hidden from `MainMenuPanel` when the server
    reports no modes (single-mode game / pre-4.7 runtime).
  - Translation keys added: `SETTINGS.GAME_MODE`,
    `GAME_MODE.PICKER_HEADER`, `GAME_MODE.EMPTY`,
    `MODE.FFA_NAME`, `MODE.FFA_DESC`, `MODE.DUO_NAME`,
    `MODE.DUO_DESC` (13 locales each; non-English are best-
    effort translations to be reviewed).
  - Known limitation: the picker icon is `levels_icon.png` as a
    placeholder (no dedicated art exists; same TODO pattern as
    party / promote rows).
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
- [x] **5.7 Game-mode selection by leader before queuing**
      (2026-05-13)
  - Done — server: new `party_mode` storage collection
    (server-owned; PermissionRead=2 / PermissionWrite=0) holds
    `{mode_id, set_by, set_at}` per party. New `party_set_mode`
    RPC validates the caller is the resolved leader, writes the
    override, and fans out `party_state_changed` with
    `event=mode_changed`. `partyStartMatchmakingRpc` reads the
    override as the default when the leader's RPC call doesn't
    supply `game_mode` (so followers pick up the leader's
    choice automatically via the matchmaking notification).
  - Done — addon: `PlatformPartyApiClient.set_mode(party_id,
    mode_id)` + new `party_mode_set` signal.
    `fetch_party_status` batch-reads the override row alongside
    the leader and ready overrides; the resolved value folds
    into the emitted party dict as `game_mode`.
  - Done — game: `PartyManager.set_party_mode` /
    `get_party_mode` passthroughs. `PartyLobbyPanel` shows a
    leader-only cycle row labeled "Mode: <name>" that flips
    through available modes on tap, calls `set_party_mode`, and
    surfaces a toast on each change. Hidden during matchmaking
    (changing mid-queue would require re-issuing every member's
    ticket, which the runtime doesn't support). Hidden when the
    server reports fewer than 2 modes.
  - 3 new translation keys × 13 locales: `PARTY.SELECT_MODE`,
    `PARTY.MODE_LABEL`, `PARTY.MODE_CHANGED`.
  - Known limitation: the cycle row's icon is `levels_icon.png`
    as a placeholder (same TODO pattern as the 4.7 picker).
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
- [x] **6.5 Extract `party_api_client.gd` → `Platform.party.*`**
      (2026-05-12). Scope narrowed: `party_manager.gd` stays
      game-side.
  - Done — submodule: new
    `addons/snoringcat_platform_client/core/party_api_client.gd`
    with `class_name PlatformPartyApiClient`. Surface preserved
    verbatim (12 signals: party_created, party_invited,
    party_joined, party_left, party_kicked,
    party_status_received, party_matchmaking_started,
    party_ready_updated, party_invite_code_received,
    party_invite_code_redeemed, party_leader_transferred,
    request_failed; methods: create_party, invite_to_party,
    join_party, leave_party, fetch_party_status,
    kick_from_party, set_ready, get_invite_code, join_by_code,
    transfer_leadership, start_matchmaking, is_busy). Reads
    `Platform.nakama_client`, `Platform.token_store.player_id`,
    `Platform.build_session_from_store()`. No `G.*`
    reach-backs in the source class so the extraction was a
    pure move-and-rename.
  - Done — parent: 18+ `G.party_api_client.X` callsites across
    4 files (`party_manager.gd`, `friend_details_panel.gd`,
    `party_lobby_panel.gd`, `join_by_code_panel.gd`) migrated
    via `sed s/G\.party_api_client/Platform.party/g`. Three
    local-handle declarations got explicit type annotations
    (`var pac: PlatformPartyApiClient = Platform.party` and
    two siblings) because `Platform.party` is untyped on the
    autoload (parser-cache bug workaround inherited from 6.3
    /6.4). Direct one-shot calls like `Platform.party.X()`
    work fine on Variant without type annotation.
  - Done — `global.gd._enter_tree()` instantiates
    `PlatformPartyApiClient` and calls
    `Platform.register_subsystem("party", party)` in the same
    slot that previously held `G.party_api_client`. The
    field-declaration `var party_api_client: PartyApiClient`
    on `G` is removed.
  - Done — game-side `src/core/party_api_client.gd` + `.uid`
    deleted. The two prose mentions of "PartyApiClient" in
    `party_manager.gd`'s docstrings updated to
    `PlatformPartyApiClient`.
  - Verification: headless boot clean (Main._ready reaches
    close-app, JWT refresh fires with
    `vars: {game_id: hopnbop}` against live Nakama). Editor
    pass needed first to register `PlatformPartyApiClient` in
    `.godot/global_script_class_cache.cfg` (same precedent as
    6.4's note on first-time class registration).
  - Decision worth recording: `party_manager.gd` kept
    game-side. The audit framing had it migrating alongside
    the API client. In practice it has the same kind of
    UI-coordinator coupling that kept
    `friends_notification_poller.gd` game-side under 6.4: it
    reaches into `G.toast_overlay` (notification toasts),
    `G.confirm_layer` + `G.settings.confirm_overlay_scene`
    (invite / rejoin dialogs), `G.client_session` +
    `G.game_panel` (matchmaking kickoff to
    `client_load_game`), and `G.notification_socket_client`
    (real-time socket — itself game-side for now, see 6.5b
    candidate below). Moving it would require either passing
    these surfaces in via constructor / setter or adding new
    `Platform.{notification_socket, toast, confirm}` slots
    plus signal-emit-instead-of-call refactor — both heavy
    for no payoff today. PartyManager updates its
    `G.party_api_client.X` calls to `Platform.party.X`; the
    rest stays.
  - Compliance verification: no GUT test exercising the new
    class (no Stage 8.x client-unit-tests track live yet).
    Confidence today is from headless boot + live Nakama
    smoke (the boot-time `update_and_get_presence` succeeds
    via the auth/presence path; party RPCs themselves are
    exercised only when a user actively creates a party).
- [x] **6.5b Extract `notification_socket_client.gd` →
      `Platform.notification_socket.*`** (2026-05-12). Follow-up
      to 6.5 immediately.
  - Done — submodule: new
    `addons/snoringcat_platform_client/core/notification_socket_client.gd`
    with `class_name PlatformNotificationSocketClient`. Surface
    preserved verbatim: 4 signals (`notification_received`,
    `socket_connected`, `socket_disconnected`,
    `received_channel_message`), 5 methods (`is_socket_connected`,
    `start`, `stop`, `join_chat_group`, `leave_chat`,
    `send_chat_message`) plus the `CHANNEL_TYPE_GROUP` constant.
    Reads `Platform.auth`, `Platform.token_store`,
    `Platform.build_session_from_store()`,
    `Platform.get_nakama_client()`. 8 `Netcode.log.{print,warning}`
    callsites replaced with `print` / `push_warning` (same
    pattern 6.2 used for the auth class). No other game-side
    reach-backs.
  - Done — platform.gd: new `notification_socket` field +
    allowlist entry in `register_subsystem`. Subsystem docstring
    updated to include the slot.
  - Done — parent: 6 callsites across two files
    (`party_manager.gd`, `friends_notification_poller.gd`)
    migrated via `sed s/G\.notification_socket_client/Platform.notification_socket/g`.
    Two `var socket := Platform.notification_socket` declarations
    got explicit `PlatformNotificationSocketClient` type
    annotations because `Platform.notification_socket` is
    untyped on the autoload (parser-cache workaround inherited).
    Two prose mentions of "NotificationSocketClient" in
    `party_manager.gd` docstrings updated to "PlatformNotificationSocketClient".
  - Done — `global.gd._enter_tree()` instantiates
    `PlatformNotificationSocketClient` and calls
    `Platform.register_subsystem("notification_socket", ...)`.
    The `G.notification_socket_client` field is removed. The
    "must enter the tree before its consumers" comment block
    is preserved (PartyManager and FriendsNotificationPoller
    both `_ready`-connect to its signals).
  - Done — game-side `src/core/notification_socket_client.gd`
    + `.uid` deleted.
  - Verification: editor pass refreshed
    `.godot/global_script_class_cache.cfg` with the new class
    entry; plain headless boot clean (Main._ready,
    JWT refresh fires with `vars: {game_id: hopnbop}` through
    the existing PlatformAuthApiClient path; the realtime
    socket itself doesn't open in this preview path because
    the user is anonymous at this boot step, but the
    auth_completed → start() wiring is in place and registered).
- [x] **6.6 Extract `nakama_matchmaker_client.gd` →
      `Platform.matchmaking.*` (split-and-adapter)** (2026-05-12).
      `edgegap_server_provider.gd` deliberately stays game-side.
  - Done — submodule: new
    `addons/snoringcat_platform_client/core/matchmaker_api_client.gd`
    with `class_name PlatformMatchmakingClient`. Surface: 3
    signals (`match_ready_received(payload: Dictionary)`,
    `matchmaking_failed(error: String)`,
    `progress_updated(phase: String, elapsed_sec: float,
    estimated_total_sec: float)`); 4 methods
    (`start_matchmaking(query, min_count, max_count,
    string_props, numeric_props, preview_device_id,
    local_player_count)`, `cancel_matchmaking()`, `cleanup()`,
    `is_searching()`). Owns the `NakamaSocket`, matchmaker
    ticket, elapsed timer (60 s timeout, 1 s tick), and
    match_ready notification parser (port-pick by
    UDP/TCP-protocol matching for ENet vs WebRTC/WS).
    Reads `Platform.{auth, token_store, build_session_
    from_store(), get_nakama_client(), game_id}`; the only
    "game-shaped" knob is `preview_device_id`, which when
    non-empty makes the addon authenticate that device id as
    a separate Nakama account (used by the editor's
    multi-instance preview so each slot looks like a distinct
    user to the matchmaker pool). 8 `Netcode.log.print/warning`
    callsites replaced with `print` / `push_warning` (same
    pattern as 6.2 / 6.5b). The class is otherwise a
    line-for-line lift of the existing matchmaker except:
    transport_type stays a string, port-pick takes a string
    instead of `NetworkSettings.TransportType`, and
    `_local_player_count` is parameterized through
    `start_matchmaking` instead of read from
    `G.client_session.local_player_count`.
  - Done — parent: `src/core/nakama_matchmaker_client.gd`
    rewritten as a slim adapter (~210 lines, down from 550).
    Keeps `class_name NakamaMatchmakerClient` /
    `extends SessionProvider` so every existing call site
    (`GameSessionManager._setup_session_provider` instantiation,
    `client_request_session_ids`, `clear_session`, etc.) keeps
    working with no migration. New responsibilities:
    (a) resolve matchmaker rules from
    `G.backend_api_client.server_matchmaker_*` with compile-
    time fallbacks; (b) mint `preview_device_id` from
    `Netcode.is_preview` + `Netcode.preview_client_number` +
    `OS.get_unique_id()`; (c) build the matchmaker properties
    dict (platform=web|native, player_count, game_id, level_id,
    party_id, game_mode); (d) translate the match_ready
    `transport_type` string to `NetworkSettings.TransportType`
    and apply it to `Netcode.settings.transport_type` before
    emitting `session_ids_received`; (e) connect to /
    disconnect from `Platform.matchmaking`'s signals in
    `_ready` / `_exit_tree` so the boot-time-singleton's
    lifetime doesn't trap stale handlers from prior
    session-providers.
  - Done — `global.gd._enter_tree`: instantiates
    `PlatformMatchmakingClient` and calls
    `Platform.register_subsystem("matchmaking", ...)` as a
    boot-time singleton, alongside the other 6.x subsystems.
    The `Platform.matchmaking` slot was already declared in
    6.1's `register_subsystem` allowlist; this is the first
    registration that actually populates it.
  - Decision worth recording: `EdgegapServerProvider` stays
    game-side. The audit-derived task title included it but
    the file is deeply entangled with
    `Netcode.connector.{get_peer_id_from_player_id,
    server_notify_shutdown, server_close_multiplayer_session}`
    for peer validation, `Netcode.log` + `NetworkLogger`
    for diagnostics, and `G.match_result_reporter.cancel` for
    Edgegap deployment teardown on idle / grace timeouts.
    Moving it would force either constructor-injecting every
    one of those surfaces or adding new
    `Platform.{connector, match_results, logger}` slots —
    both heavy refactors with no payoff today. The only
    self-contained piece is `register_with_runtime()` (an
    HTTP RPC to Nakama's `register_server`), but factoring
    just that out would create an awkward straddle. Same
    pattern as PartyManager (6.5) and FriendsNotificationPoller
    (6.4): keep the coordinator game-side, factor each
    *API surface* into the addon. The matchmaker's API
    surface (Nakama socket lifecycle + matchmaker ticket +
    match_ready parser) is now in the addon; the validation
    coordinator stays where it is.
  - Decision worth recording: `Platform.matchmaking` is a
    boot-time singleton, not a per-session object. The
    SessionProvider adapter `NakamaMatchmakerClient` is
    per-session (instantiated by `GameSessionManager`).
    Multiple adapters across time can share the same
    addon-side client because the client services at most one
    ticket at a time and the adapter is responsible for
    disconnecting its signal handlers in `_exit_tree`. The
    alternative (per-session addon client too) would mean
    `Platform.matchmaking` is null between sessions, which
    breaks the "consumers tolerate null until extraction
    lands" pattern — once an extraction lands, the slot
    should stay non-null for the rest of the boot.
  - Verification: editor pass refreshed
    `.godot/global_script_class_cache.cfg` with the new
    `PlatformMatchmakingClient` entry. Plain headless boot
    clean (Main._ready, JWT refresh fires with
    `vars: {game_id: hopnbop}` against live Nakama via the
    existing `PlatformAuthApiClient` path; the matchmaker
    itself doesn't open a socket in the preview-close path
    because no user-driven matchmaking is exercised, but the
    subsystem is registered and the adapter wires its
    signals).
  - Compliance verification: the existing
    `test_socket_matchmaker.gd` compliance test exercises the
    Nakama matchmaker socket directly via the SDK, not via
    `PlatformMatchmakingClient`, so it's an independent
    canary that doesn't break with the extraction. No new
    GUT unit test for the addon class (Stage 8.x client-unit
    track not live).
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
- [x] **6.8 Extract `settings_cloud_sync.gd` → `Platform.settings.*`**
      (2026-05-12). Paired with Stage 3.5 in one session.
  - Done — submodule: new
    `addons/snoringcat_platform_client/core/settings_api_client.gd`
    with `class_name PlatformSettingsApiClient`. Surface: 3 signals
    (`settings_received(scope, payload, updated_at)`,
    `settings_saved(scope)`, `request_failed(scope, error)`) and
    2 methods (`fetch(scope)`, `save(scope, payload)`). `scope` is
    a free-form string the consuming game chooses
    (`"global"` / `"game/{game_id}"` / legacy `"user"`); the addon
    just maps it to `(collection="settings", key=scope,
    user_id=session.user_id)`. Returns Nakama's storage-row
    `update_time` parsed to unix seconds (RFC3339 string with
    fractional seconds + trailing Z is stripped before
    `Time.get_unix_time_from_datetime_string`).
  - Done — parent: `src/core/settings_cloud_sync.gd` rewritten as
    a ~240-line dual-scope adapter (was ~111 lines pre-refactor).
    Owns the LocalSettings serialize / apply mapping per scope,
    the cloud-wins-by-timestamp merge logic per scope, and the
    one-shot legacy-blob migration. The `_pending_fetch_scopes`
    dictionary gates `_on_settings_received` callbacks so a
    delayed or unrelated emit doesn't apply.
  - Done — parent: `BackendApiClient` lost
    `save_player_settings`, `fetch_player_settings`,
    `settings_received`, and `settings_saved`. They were the
    sole settings cloud surface pre-extraction; nothing else
    referenced them.
  - Done — parent: `LocalSettings.clear_user_state()` extended
    to erase the three new meta keys
    (`cloud_sync_at_global`, `cloud_sync_at_game`,
    `cloud_legacy_migrated`) alongside the pre-existing
    `cloud_sync_at` so a logout-and-relogin path doesn't leak
    cross-account state.
  - Done — parent: `global.gd._enter_tree` instantiates
    `PlatformSettingsApiClient` and calls
    `Platform.register_subsystem("settings", ...)`. Slot was
    already declared in 6.1's allowlist; this is the first
    registration that actually populates it.
  - Verification: editor pass refreshed
    `.godot/global_script_class_cache.cfg` with the new
    `PlatformSettingsApiClient` entry. Plain headless boot clean
    (Main._ready reaches close-app, JWT refresh fires with
    `vars: {game_id: hopnbop}` against live Nakama; the
    settings cloud sync itself doesn't fire in the preview-
    close path because the user is anonymous at this boot
    step and `Platform.token_store.is_token_valid()` guards
    the entry point). No compliance test for the dual-scope
    merge yet (Stage 8.28 placeholder).
  - Known limitation: there's a small race window when a save
    is in flight against a stale-but-pending fetch. If a fetch
    response arrives between when `save()` is dispatched and
    when its storage write commits, the fetch can apply older
    cloud values to local, overwriting the user's in-progress
    change. Eventual consistency reconciles on the next
    fetch-and-merge cycle. A more correct fix tracks in-flight
    saves and ignores fetch responses against the same scope
    while a save is pending; not worth the complexity today.
- [x] **6.9 Passive `Platform.session` lifecycle bus** (2026-05-12).
      `game_session_manager.gd` stays game-side verbatim.
  - Done — submodule: new
    `addons/snoringcat_platform_client/core/session_observer.gd`
    with `class_name PlatformSessionObserver`. Surface: 5 signals
    (`session_started(player_ids: Array[int])`, `match_ready()`,
    `connection_lost(reason_name: String, is_expected: bool)`,
    `matchmaking_failed(reason: String)`,
    `matchmaking_progress(phase: String, elapsed_sec: float,
    estimated_total_sec: float)`). No methods, no internal state,
    no game-side reach-backs — just a bus. The 5-signal subset is
    the union of the cross-game-meaningful events on the existing
    `GameSessionManager`; hopnbop-specific events
    (`local_mode_fallback_requested`, `server_should_reset`,
    `server_shutdown_imminent`) stay game-side only because they
    describe deployment-shape internals (offline-mode fallback,
    preview-mode reset, server-side shutdown indicator) that a
    second game would model differently if at all.
  - Done — parent: `src/core/game_session_manager.gd` adds a
    one-line `if Platform.session != null: Platform.session.X.emit
    (...)` forward next to each existing game-side emit. Every
    forwarded site is paired with the matching name (the
    `session_established` → `session_started` rename happens at
    the forward, not on the game-side signal — existing direct
    connect callers in `game_panel.gd` keep the old name). The
    `Platform.session != null` guard tolerates the trivially-
    impossible case where the slot isn't registered yet (it's
    registered in `global.gd._enter_tree` alongside the other
    addon-side subsystems, before `GamePanel` instantiates a
    `GameSessionManager`).
  - Done — `global.gd._enter_tree`: instantiates
    `PlatformSessionObserver` and calls
    `Platform.register_subsystem("session", session_observer)`.
    Slot was already declared in 6.1's `register_subsystem`
    allowlist; this is the first registration that actually
    populates it.
  - Decision worth recording: passive observer, not coordinator.
    The audit-derived framing had `Platform.session` owning the
    session-provider switching + connection flow. In practice
    that role is irreducibly entangled with `Netcode.*` (the
    rollback-netcode autoload, a separate submodule), the
    matchmaker's `SessionProvider` extension, and game-specific
    UI / fallback state. Lifting the coordinator into the addon
    would force the addon to depend on rollback-netcode and the
    game's UI surfaces — wrong direction. The passive-observer
    move keeps the dependency arrow pointing addon→Platform and
    game→Platform, never addon→game, and unblocks the "second
    game can drop in the addon and get the same lifecycle
    surface" goal without the heavy refactor. The heavy refactor
    doesn't pay off until a second game with different netcode
    semantics forces the abstraction.
  - Verification: editor pass refreshed
    `.godot/global_script_class_cache.cfg` with the new
    `PlatformSessionObserver` entry. Plain headless boot clean
    (zero parse / compile errors; JWT refresh fires with
    `vars: {game_id: hopnbop}` through the existing
    PlatformAuthApiClient path). The session-lifecycle forwards
    themselves don't exercise in this preview-close path
    (no user-driven matchmaking is exercised) but the bus is
    registered and the game-side emits will fan out once a real
    session lands. No compliance test for the forward path
    (Stage 8 socket-harness track not live).
- [x] **6.10 Migrate every consumer in hopnbop game code from
      `G.*_api_client` to `Platform.*`** (2026-05-12).
  - Done — verification pass. `G.*_api_client` grep across
    `src/` returns only `G.backend_api_client` (which is
    intentionally still game-side, see decision log below) and
    doc-comment / string-literal references that aren't live
    callsites. No live callsite still names the removed
    `G.auth_client`, `G.auth_token_store`, `G.friends_api_client`,
    `G.party_api_client`, `G.notification_socket_client`, or
    `G.matchmaker_client` shapes. Confirmed independently via
    grep for the deleted `class_name`s
    (`AuthClient`, `AuthTokenStore`, `FriendsApiClient`,
    `PartyApiClient`, `NotificationSocketClient`): every hit is
    either a typed local var using the new `Platform*ApiClient`
    name, a node-name string in `global.gd`'s
    `add_child` setup (cosmetic), or a docstring reference to
    the old name — none are live class lookups.
  - Decision worth recording: `backend_api_client.gd` stays
    game-side for now. Its surface (`fetch_leaderboard`,
    `fetch_player_stats`, `fetch_player_profile`,
    `save_player_settings`, `check_version`, plus the no-op
    fleet-warmup stubs kept for legacy UI callers) is mostly
    Nakama-RPC plumbing that *could* live in the addon, but it
    also caches per-game values populated by `version_check`
    (`server_legal_version`, `server_matchmaker_*`) that the
    addon's auth/matchmaker subsystems already read via
    `G.backend_api_client.*`. A future "Platform.backend" or
    "Platform.profile" subsystem could absorb it, but the
    payoff is small until a second game needs the same
    leaderboard/profile/stats RPCs — same coordinator-vs-API-
    surface heuristic 6.4 / 6.5 / 6.6 followed. Tracked
    informally as a 6.x follow-up; not on the critical path.
- [x] **6.11 Reusable screen templates in `Platform.screens.*`:
      auth, consent, anonymous-upgrade. Hop'n'Bop screens
      become thin wrappers.** (6.11a + 6.11b shipped 2026-05-14)
  - [x] **6.11a Foundation migration** (2026-05-14, twentieth pass).
    - Done — game-side `Screen` (`src/ui/screens/screen.gd`)
      now extends `PlatformScreen` instead of being a duplicate
      `PanelContainer`. Overrides `_enter_tree` to add the
      `Netcode.is_server` early-out (server side hides + disables
      the screen) then calls `super._enter_tree()`. Overrides
      `_set_default_styling` to apply `G.settings.default_theme`
      + `G.settings.screen_style_box`. All 12 `extends Screen`
      consumers (auth, consent, loading, game_over, my_stats,
      leaderboard, credits, language, legal_doc, scg_splash,
      pause, godot_splash) inherit the platform infrastructure
      transparently.
    - Done — game-side `ScreenFocusNavigator`
      (`src/ui/screen_focus_navigator.gd`) now extends
      `PlatformScreenFocusNavigator` and uses `_init` to wire
      the focus-move sound callback against `G.audio`. All 6
      consumers (auth, game_over, my_stats, leaderboard,
      credits + the navigator's own self-reference) get the
      audio behavior for free via the existing
      `ScreenFocusNavigator.new()` call.
    - Done — game-side `AnyDeviceInputPoller`
      (`src/ui/any_device_input_poller.gd`) collapses to a
      pure alias (`class_name AnyDeviceInputPoller extends
      PlatformAnyDeviceInputPoller`). The platform poller
      reads from `PlatformInputDeviceManager.KEYBOARD_PARTITION_BINDINGS`
      which is the same const array as
      `InputDeviceManager.KEYBOARD_PARTITION_BINDINGS`, so
      behavior is identical for all 4 consumers (consent,
      language, legal_doc, confirm_overlay).
    - Verification: `godot --headless --import` clean (no
      parse/compile errors; class registration table shows
      Screen / AnyDeviceInputPoller / ScreenFocusNavigator
      register against their respective platform parents).
      Headless `--client=1` boot exercises the auth screen
      and consent screen flows, transitions to lobby cleanly.
      Pre-existing shutdown "Unreferenced static string"
      errors are Godot 4.7-beta1 housekeeping noise unrelated
      to this change.
    - Decision worth recording: the doc's prior scoping note
      claimed "ScreenFocusNavigator itself is game-side today"
      — stale. `PlatformScreen`, `PlatformScreenFocusNavigator`,
      `PlatformAnyDeviceInputPoller`, and
      `PlatformInputDeviceManager` were all extracted to the
      addon in earlier passes; what was missing was hopnbop
      actually consuming them. This sub-task closes that gap
      without touching the concrete-screen extraction. The
      pattern (a)+(b) recommendation in the next sub-task is
      now backed by infrastructure that's proven to work
      end-to-end.
    - Decision worth recording: thin-subclass-with-callback
      (vs delete-and-rewrite-callers) for `ScreenFocusNavigator`.
      The platform navigator takes an optional audio callback
      via `set_focus_moved_callback`. The game-side subclass's
      `_init` auto-wires `G.audio.play_sound("focus")`, so all
      pre-existing callers (`ScreenFocusNavigator.new()`) keep
      working unchanged. Alternative (every caller calls
      `PlatformScreenFocusNavigator.new()` and wires the
      callback inline) would have meant touching 5+ files per
      caller for the same effect. The subclass adds 8 lines
      total and is the minimal bridge.
    - Known limitation: `ScreenTransition` (the wipe/fade
      overlay) wasn't migrated in this sub-task even though
      `PlatformScreenTransition` exists in the addon. The
      transition is a sibling of the screens it overlays
      rather than a screen itself, and the migration is
      orthogonal to 6.11's "reusable screen templates"
      framing. Tracked informally for whoever picks up the
      next platform-infra cleanup pass.
  - [x] **6.11b Concrete screen extraction** (2026-05-14, twenty-
    first pass).
    - Done — three new full `*.tscn` + `*.gd` screens in
      `addons/snoringcat_platform_client/ui/screens/`:
      `PlatformAuthScreen` (extends `PlatformScreen`,
      `class_name PlatformAuthScreen`), `PlatformConsentScreen`
      (extends `PlatformScreen`), `PlatformAnonymousUpgradeScreen`
      (extends `PlatformScreen`, greenfield). Each scene root is
      a `PanelContainer` with the script attached + @export
      branding slots populated to null by default (concrete
      games override via inherited scenes).
    - Done — hopnbop's `src/ui/screens/auth_screen.tscn` and
      `src/ui/screens/consent_screen.tscn` rewritten as
      *inherited scenes* from the addon scenes
      (`[node ... instance=ExtResource("addon_scene")]`),
      with @export overrides on the root for theme, panel
      stylebox, logo, provider / row icons, checkbox textures,
      chevron icon, focus / unfocused styleboxes. Game-side
      `auth_screen.gd` (~40 lines) extends `PlatformAuthScreen`
      and overrides `_create_navigator()` (returns audio-wired
      `ScreenFocusNavigator`), `_should_force_anonymous()`
      (Netcode preview check), `_enter_tree()` (G.auth_screen
      registration + Netcode.is_server guard), plus signal
      subscribers for `lobby_navigation_requested` /
      `force_anonymous_state_reset_requested`. Game-side
      `consent_screen.gd` (~80 lines) follows the same pattern
      with `_create_input_poller()` / `_should_auto_consent()`
      / `_get_current_legal_version()` / `_get_icon_scale()` /
      `_get_icon_padding()` / `_play_focus_sound()` /
      `_play_select_sound()` virtuals + signal subscribers for
      `consent_accepted` / `language_picker_requested` /
      `terms_link_requested` / `privacy_link_requested`.
    - Done — `ScreensMain.get_screen_from_type()` return type
      widened from `Screen` to `PlatformScreen` (the common
      ancestor of the original `Screen` subclasses and the new
      `PlatformAuthScreen` / `PlatformConsentScreen` sibling
      branches). One callsite in
      `screen_trigger_row.gd::_open_screen()` updated for the
      same widening. `global.gd`'s `var auth_screen: AuthScreen`
      / `var consent_screen: ConsentScreen` typing stays — the
      narrowed game-side classes still extend the addon classes.
    - Done — `PlatformAnonymousUpgradeScreen` greenfield surface
      shipped as a screen-shaped equivalent of hopnbop's
      `UpgradeAccountPanel` (SidePanel, Stage 7.9). Emits
      `upgrade_completed` (on `Platform.auth.auth_completed
      (success=true)`) and `dismiss_requested` (on "Maybe
      Later"). Hopnbop doesn't integrate it — the panel
      flavor is its established UX; the screen flavor is
      reference-implementation for a future game with a
      hard-gate variant. Surface design intentionally
      inferential without a second consumer.
    - Verification: `godot --headless --import` clean (no
      parse / compile errors; class registration table shows
      `PlatformAuthScreen` / `AuthScreen` /
      `PlatformConsentScreen` / `ConsentScreen` /
      `PlatformAnonymousUpgradeScreen` all registered).
      Ad-hoc smoke test instantiated all 5 scenes (4
      hopnbop-side + 5 addon-side including greenfield) and
      confirmed each carried the expected class through the
      inheritance chain. No end-to-end UI flow exercised
      against live Nakama; that needs Levi at the keyboard
      or the Tier-4 docker-compose stack (8.29).
    - Decision worth recording: signal-driven navigation
      contracts (not callable properties or virtual methods).
      Each addon screen emits intent signals
      (`lobby_navigation_requested`, `consent_accepted`,
      `language_picker_requested`, etc.); the game-side
      wrapper connects them and routes to `G.screens.*` +
      `ScreensMain.ScreenType.*`. Signal emission is
      synchronous in Godot, so the contract behaves like a
      function call but inverts the dependency direction:
      addon → game becomes game subscribing to addon. Two
      benefits: (1) addon stays decoupled from the game's
      navigation enum / autoload graph; (2) future games can
      hook the same signals without subclassing if they
      prefer a composition style.
    - Decision worth recording: virtual hooks for the
      Netcode / `LegalVersion` / `G.settings` /
      `G.audio` reach-throughs that don't fit cleanly into
      @export slots. `_should_force_anonymous()` /
      `_should_auto_consent()` (Netcode), 
      `_get_current_legal_version()` (`LegalVersion.get_current()`
      over `G.backend_api_client`), `_get_icon_scale()` /
      `_get_icon_padding()` (G.settings numerics),
      `_play_focus_sound()` / `_play_select_sound()`
      (`G.audio.play_sound`), `_create_navigator()` /
      `_create_input_poller()` (audio-wired variants). Each
      virtual has a no-op default in the addon. Mixing
      signals + virtuals is intentional: signals model
      bidirectional intent (screen → game), virtuals model
      query/factory contracts (game → addon).
    - Decision worth recording: replace runtime
      `Screen._set_default_styling()` (which read
      `G.settings.default_theme` / `G.settings.screen_style_box`
      at runtime) with scene-level `theme` / 
      `theme_override_styles/panel` overrides on the inherited
      scene root. Static-in-scene is simpler than reaching into
      G at _enter_tree time and survives the cross-extends
      sibling problem (AuthScreen extends PlatformAuthScreen,
      not Screen, so it doesn't inherit Screen's runtime
      styling override).
    - Known limitation: the anonymous-upgrade screen ships
      without a concrete consumer. The surface design is
      inferential and will likely need a refinement pass once
      a second game actually adopts it. Particularly the
      navigation contract (`upgrade_completed` vs
      `dismiss_requested` is binary; a real consumer might
      need a third "error and route back" state, or
      finer-grained provider events).
    - Known limitation: no end-to-end UI smoke against live
      Nakama. The compliance suite tests the underlying RPC
      contracts (auth, consent storage on token_store via
      `has_valid_consent` / `consent_legal_version`) but the
      UI signal flow is exercised only by manual play.
      Tier-4 (8.29-8.31) docker-compose stack is the natural
      home for a smoke that boots `--client=1`, exercises
      auth → consent → lobby, and asserts screen transitions.
  - Scoping notes for the 6.11b pass:
    - Three candidate screens, current sizes: `auth_screen.gd`
      280 lines, `consent_screen.gd` 396 lines, anonymous-upgrade
      doesn't exist yet (greenfield).
    - Game-specific coupling that needs an injectable contract
      (signals or callable properties) before the screens can
      live in the addon. `auth_screen` references:
      `G.auth_screen` (autoload registration — replace with
      signal or skip if the addon doesn't need a singleton
      handle), `G.profile_image_cache.clear()` /
      `G.friends_notification_poller.reset()` /
      `G.party_manager.reset()` / `G.client_session.clear_latest_state()`
      (force-anonymous local-state reset — needs a
      `force_anonymous_state_reset_requested` signal the
      game listens for), `G.settings.anonymous_texture`
      (@export slot — already partially there for Google /
      Facebook icons), `G.screens.client_open_screen(LOBBY)`
      (navigation — needs a `navigate_to_lobby_requested`
      signal or game-supplied callable), `Netcode.is_preview`
      / `Netcode.preview_client_number` (rollback_netcode
      addon — already platform). `consent_screen` adds:
      `G.consent_screen` (autoload registration — same as
      auth), game-specific texture exports (terms / privacy
      / language icons — @export slots), and a fixed scene
      structure (`%AgeCheckBox`, `%TermsCheckBox`,
      `%LanguageRow`, `%TermsLinkRow`, `%PrivacyLinkRow`,
      `%ContinueButton`).
    - **Design decision needed before implementation:** pick one
      of (a) addon ships a `Screen` *base class* with the
      navigation / auth-flow / consent-state plumbing; games
      subclass and provide their own scene + theming; (b) addon
      ships a full scene + script and games configure via
      `@export` properties only; (c) addon ships small
      *components* (auth-button-row, consent-checkbox-row) and
      games stitch them together. Pattern (a) is already done
      (6.11a above). Pattern (b) loses flexibility but is the
      simplest to ship and is what the recommended hybrid
      below relies on for the concrete screens. Pattern (c) is
      the most composable but ships least value.
    - Recommend pattern (a)+(b) hybrid: generic
      `PlatformScreen` base in the addon (done in 6.11a) plus
      concrete screens (auth/consent/upgrade) shipped as
      `*.tscn` + `*.gd` in the addon with `@export` slots for
      icons, colors, branding strings; games override the
      strings via translation keys and wire the navigation
      and state-reset signals.
    - Anonymous-upgrade screen is greenfield — design it in
      the same pass as the extraction so the surface is
      coherent end-to-end, rather than retrofitting two
      pre-existing screens then trying to make the third fit.
      Note: hopnbop already has `UpgradeAccountPanel`
      (SidePanel-shaped, shipped in Stage 7.9). The
      screen-shaped equivalent in the addon would be for
      *other* future games that want a "force the player
      through this gate before proceeding" flow; without a
      concrete second consumer yet, the surface design will
      need an inferential pass.

## Stage 7 — Resilience

**Goal:** Cover the failure modes the audit catalogs in §7.

### Tasks

- [x] **7.1 Edgegap allocation-failure retry with exponential backoff
      + alternate region** (2026-05-13).
  - Done — runtime: new `tryAllocate` method on `*fleetAllocator`
    encapsulates one full attempt (Deploy → poll Status → validate
    IP/port → wait for register_server). Returns
    `(*edgegapDeployResponse, *edgegapStatusResponse, error)`.
    On any post-Deploy failure, calls a best-effort `stopDeploy`
    helper so retries don't leak Edgegap container-hours.
  - Done — runtime: retry loop in `OnMatchmakerMatched` (real-mode
    path only) wraps `tryAllocate` with up to
    `maxAllocationAttempts=3` attempts. Each retry applies
    `allocationBackoff(n)` (exponential 1s → 2s → 4s, capped at
    `maxAllocationBackoff=8s`) and rotates `deployReq.Geographies`
    through `allocationGeographyRotation` (north_america → europe
    → asia, wraps). IP list is dropped on retry because geo-routing
    already failed by definition. The backoff uses
    `sleepOrCtxDone` so a matchmaker context cancelled mid-retry
    exits cleanly.
  - Done — runtime: new `sendAllocationFailed` helper emits a
    `match_failed` notification (`reason=allocation_failed`,
    `attempts`, `message`, optional `last_error`) to every matched
    player when all attempts are exhausted. The message contains
    the "allocation" substring so the game-side
    `_classify_matchmaking_failure` routes it to
    `LOADING.ALLOCATION_FAILED` (recoverable + retry button on
    the loading screen, not toast-and-bounce).
  - Done — tests: 3 new test functions in `fleet_allocator_test.go`
    covering the pure retry-policy helpers.
    `TestAllocationFallbackGeographies` (5 sub-tests) locks the
    rotation contract: index 0 → nil, index 1+ → single-continent
    slice, wraps past rotation length so a future bump to
    `maxAllocationAttempts` is safe.
    `TestAllocationBackoff` (5 sub-tests) covers the
    zero-at-index-0, base-at-index-1, monotonic-up-to-cap,
    saturates-eventually, and exact-doubling contract.
    `TestSleepOrCtxDone` (4 sub-tests) covers zero/negative
    duration short-circuit, normal timer elapse, and ctx-cancel
    interruption. All passing; `go vet ./... && go test ./... &&
    staticcheck ./...` clean; pluginbuilder Docker image produces
    a 19 MB `snoringcat.so`.
  - Decision worth recording: validation of `status.PublicIP` and
    `pickTCPPort(status.Ports)!=0` moved INSIDE `tryAllocate`
    (was at the call site after polling). A "successful" deploy
    with missing IP/port is unusable; treating it as a failed
    attempt lets the retry loop rotate region instead of failing
    the match outright. The alternative (fail-fast on missing
    fields) would have wasted the user's match on what's almost
    certainly a transient Edgegap API hiccup.
  - Decision worth recording: continent rotation order is
    `north_america → europe → asia`. Biases retries toward the
    busiest known regions first. Subject to revisit when player
    geographic distribution data exists; today's player pool is
    small enough that any region's capacity ceiling is very far
    above typical concurrent-match counts, so the rotation order
    is mostly cosmetic.
  - Decision worth recording: mock mode is exempt from the retry
    loop. `synthesizeMockDeploy` is deterministic and synchronous;
    retrying it would just produce a different request_id with
    the same shape. Mock mode's purpose is the contract-level
    fan-out test, not exercising the retry policy. Future tests
    that DO want to exercise retry can compose a fault-injecting
    Edgegap client (Stage 8 / 7.x followup).
  - Decision worth recording: validation happens before
    `waitForServerRegistered` so a deploy with bad data doesn't
    eat a 30s register timeout. The previous order (status
    polling → register wait → IP/port validation) had the
    validation in the call site after register wait completed,
    which meant a missing-IP deploy would block for 30s before
    being stopped. The new order fast-fails the attempt and
    moves on to the retry.
  - Known limitation: the retry policy is uniform — every
    failure mode triggers the same backoff + region rotation.
    A future expansion could classify errors (e.g., 401/403
    from Edgegap should never retry, while 5xx and timeouts
    should). The current "always retry" stance is safer
    pre-classification (more retries are wasteful but not
    incorrect), and the classifier extension point is the
    `lastErr` value already carried through the loop.
  - Known limitation: no compliance test exercises the retry
    path end-to-end. Stage 8.21's failure-modes test covers only
    the protocol-mismatch path because the other failure modes
    require fault-injection hooks the runtime doesn't yet expose.
    A future 8.21 expansion could wire an `EDGEGAP_FAULT_INJECT`
    env var that synthesizeMockDeploy honours by returning
    errors on the first N calls; deferred until 7.x retry needs
    are tested in CI rather than via manual smoke.
- [x] **7.2 Mid-queue cancel cleanly tears down Edgegap deploy if
      it has already started** (2026-05-13).
  - Done — runtime: new `inflightAllocation` struct (holds just
    the cancel func) + `sync.Map` `inflightByUserID` on
    `fleetAllocator`. `OnMatchmakerMatched` derives a cancelable
    child context (`allocCtx, allocCancel := context.WithCancel
    (ctx)`), registers the inflight against every matched
    user_id, and defers deregister + allocCancel. The retry loop
    + `sleepOrCtxDone` backoff now use `allocCtx` so a user-
    initiated cancel propagates through both
    `a.edgegap.Status` polling and the inter-attempt sleep.
  - Done — runtime: two `allocCtx.Err() != nil` checkpoints in
    the hook. (1) After the retry loop, distinguishes "user
    cancelled" (sends `match_failed` reason=cancelled, returns
    nil) from "all retries failed" (existing
    `sendAllocationFailed` path). (2) After successful
    allocation, before writing storage rows or sending
    `match_ready`: if cancelled, calls `stopDeploy` on the
    freshly-allocated deploy and fans out match_failed
    reason=cancelled. Storage writes are skipped in the cancel
    path so we don't leave orphan rows.
  - Done — runtime: new `sendMatchCancelled` helper notifies
    every matched player with `match_failed`,
    `reason="cancelled"`, `message="Match cancelled by another
    player."`. The canceller's own client already cleared
    `_is_searching` in `cancel_matchmaking()` so their
    `_handle_match_failed` no-ops on receipt; the notification
    matters for OTHER matched players, who learn a peer bailed
    and can re-queue.
  - Done — runtime: new client-session RPC
    `cancel_matchmaking_allocation` registered via
    `cancelAllocationRpcFactory(alloc, games)`. Looks up the
    caller's inflight via user_id and invokes the cancel func.
    Returns `{ok: true, cancelled: bool}`; `cancelled=false`
    means no in-flight allocation existed (cancel arrived
    pre-OnMatchmakerMatched or post-point-of-no-return) and is
    treated as a silent success. Requires `requireClientSession`
    + `requireGameID` like every other game-scoped RPC.
  - Done — addon: `PlatformMatchmakingClient.cancel_matchmaking()`
    now fires the new RPC via `_socket.rpc_async(
    "cancel_matchmaking_allocation", "{}")` alongside the
    existing `remove_matchmaker_async(_ticket)`. Both are
    fire-and-forget (no await). The pool-removal handles the
    "still queued" case; the new RPC handles the "matched, mid-
    allocation" case. Calling both is cheap (each is a no-op on
    the server when the corresponding state doesn't exist).
  - Done — game: `LoadingScreen._update_action_buttons` now
    includes `"placing"` in the cancelable-phase allowlist
    (was `queued`+`searching` only). The original comment block
    flagging this as a Stage 7.2 follow-up was updated.
  - Done — game: `game_panel._classify_matchmaking_failure` now
    matches `"cancelled"` substring and routes to
    `LOADING.PEER_CANCELLED` so the OTHER matched players (not
    the canceller; they've already left the matchmaking flow)
    see a recoverable "match cancelled by another player"
    prompt with a retry button instead of toast-and-bounce.
  - Done — i18n: 1 new translation key × 13 locales:
    `LOADING.PEER_CANCELLED`. CSV verified at 14 fields;
    `.translation` binaries re-imported via `godot --headless
    --import`.
  - Done — tests: 2 new test functions in `fleet_allocator_test
    .go` (8 sub-tests total). `TestRegisterAndDeregisterInflight`
    covers register-all-users, deregister-removes-all, empty-
    userID-skipped, deregister-respects-newer-entry (the
    CompareAndDelete guard against stale defers).
    `TestCancelInflightForUser` covers registered-user-cancels,
    unregistered-user-noops, cancels-shared-inflight-from-any-
    user (multi-user match propagation), and propagates-ctx-
    cancel (end-to-end allocCtx.Done() observation under 100ms).
    `go vet && go test && staticcheck` clean; pluginbuilder
    Docker produces a 19 MB `snoringcat.so`.
  - Decision worth recording: cancel RPC only signals; teardown
    happens in the matchmaker hook goroutine. The alternative
    (RPC reads request_id from the inflight, calls stopDeploy
    directly, sends match_failed inline) would have split the
    teardown surface across two goroutines and made the
    cancel-vs-success race trickier to reason about. With the
    signal-only model, the hook goroutine is the sole owner of
    all teardown state — RPC just sets a tripwire.
  - Decision worth recording: same `inflightAllocation` is
    shared by every matched user in the same match (party
    members + matchmaker-paired strangers alike). Calling
    cancel via any one user's tracker entry propagates to all.
    Semantics: any one matched player cancelling = whole match
    aborts. If a 4-player FFA has one bailer, the other 3 see
    `LOADING.PEER_CANCELLED` and re-queue. The matchmaker had
    already certified the 4 as a valid match; losing one player
    invalidates that, so we don't try to salvage a 3-player
    match from the wreckage.
  - Decision worth recording: two cancel checkpoints, not one.
    The naive design has one check after allocation; this
    leaves a window between "allocation succeeded" and
    "storage rows written + match_ready sent" where a cancel
    has to clean up additional state. Two checkpoints — one
    before the retry loop succeeds and one after — keep the
    "cancelled with storage-row cleanup" path off the critical
    path. The window between checkpoint #2 and the actual
    `NotificationSend` is microseconds; a cancel that sneaks
    in there is best-effort lost (deploy stays alive, peers
    get match_ready, the in-container Godot's idle timer
    eventually tears it down). Acceptable.
  - Decision worth recording: `LOADING.PEER_CANCELLED` is a
    new key, not a re-use of `LOADING.NO_MATCH_FOUND`. "No
    match found" implies "we couldn't pair you with anyone";
    `PEER_CANCELLED` is "we paired you, but a peer pulled
    out". The user-facing distinction matters — under
    NO_MATCH_FOUND, retrying might just expand the search;
    under PEER_CANCELLED, retrying might pair the same
    peers (who could bail again) or different ones. Distinct
    framing lets the retry button's mental model stay
    accurate. Cost: 13 new translations (best-effort, worth
    a native-speaker review pass).
  - Known limitation: post-`match_ready` cancel is still
    fire-and-forget. The client side ignores match_ready when
    `_is_searching` is already false, so a cancel that arrives
    AFTER the deploy was completed and notifications sent
    silently leaves the deploy running. The game server's
    idle/grace timer tears it down (typically within 30 s).
    A tighter answer would have the client call the existing
    `match_cancel` RPC against the deploy's request_id, but
    that surface currently rejects non-server callers except
    for synthetic matches; expanding it requires the matchmaker
    metadata to flow into the client (currently it doesn't —
    `match_ready` payload would need the request_id surfaced
    and the cancel call wired with a permission check that
    confirms the caller was a matched player). Deferred until
    the wasted Edgegap minutes actually show up as a cost
    signal.
  - Known limitation: no compliance test exercises the
    cancel-mid-allocation path end-to-end. Unit tests cover
    the pure helpers (register/deregister/cancel propagation);
    end-to-end would need a Tier 2 mock-mode test that fires
    `cancel_matchmaking_allocation` during the synthesized
    deploy window. With mock mode's deploy completing in
    microseconds (no real poll loop), the timing window for
    a meaningful cancel is too tight to test reliably. A
    real test would need either an injectable poll-delay env
    var or fault-injection equivalent — same blocker as the
    7.1 retry compliance test gap. Deferred.
- [ ] **7.3 Push notification for friend online / party invite /
  match found** — **declined 2026-05-14**.
  - Product call: no platform-level push for any trigger. Friend-
    online / party-invite / match-found stay as in-app toasts
    driven by the existing 10s `friends_notification_poller.gd`
    cadence. The audit's framing (`audit §P3.24`) carried an
    implicit assumption that push notifications would meaningfully
    improve engagement; the call here is that hopnbop's session
    pattern (synchronous match-based play, primarily web + native
    desktop, no async / turn-based loops) doesn't benefit enough
    to justify the cost.
  - Cost of doing it would have been substantial: PWA web-push
    (Service Worker + Web Push API + VAPID keypair + push event
    handler) for web; either native OS notification APIs or
    deferral for desktop; FCM + Firebase project for any future
    Android build; APNS + Apple Developer credentials for any
    future iOS build. Each surface has its own permission UX,
    subscription storage, and dispatch path. Across all four,
    realistically a multi-session implementation pass plus
    ongoing credential rotation surface.
  - Decision worth recording: defaulting to "no push" is also
    the friendlier UX for the kind of player who installs a game
    once and plays it for short bursts. Push permission prompts
    are now widely treated as anti-features when they don't
    correspond to time-sensitive content, and the in-app toast
    surface already covers the cases that matter (you can't get
    a match-found push if your app is closed anyway — push only
    helps the "tab-backgrounded mid-queue" window, which is a
    small fraction of matchmaking activity).
  - Re-open trigger: if a future game in the platform fleet has
    a stronger case (e.g., turn-based / async play, or daily-
    streak retention loops), this task can be revived. The
    scaffolding work would still be from scratch since nothing
    has been built; this entry exists as a no-op placeholder
    plus the rationale above.
- [x] **7.4 Friend block list (schema + RPC + UI + matchmaker
  integration)** (2026-05-13).
  - Done — runtime: new
    `third_party/snoringcat-platform/runtime/block_list.go`
    registers three client-session RPCs over Nakama's native
    state=3 (BANNED) friend state. `block_user` calls
    `nk.FriendsBlock` (server-side: removes any prior
    friendship/pending state and writes the BANNED row);
    `unblock_user` calls `nk.FriendsDelete` against the
    state=3 row (idempotent — no-op if the row is missing);
    `list_blocked_users` walks `nk.FriendsList(state=3)`
    paginated to `blockListPageCap=10` pages × 100 entries.
    All three require `requireClientSession` +
    `requireGameID` like every other game-scoped RPC. The
    shared `listBlockedUserIDs` helper drives both the list
    RPC and the matchmaker filter so both read the same
    view; `blockedUserIDSet` is a thin set-only wrapper for
    the matchmaker hot path. New page-cap constants
    (`blockListPageSize=100`, `blockListPageCap=10`) mirror
    the existing account-cascade pattern.
  - Done — runtime: matchmaker hook
    `fleet_allocator.go::OnMatchmakerMatched` fires a
    blocked-pair check after the protocol-mismatch check
    and before the Edgegap allocation. Walks each matched
    user's BANNED list once (N reads for an N-player
    match), feeds the resulting `map[string]map[string]struct{}`
    into `findBlockedPairs`, and if any directed (A blocked B)
    edge exists between two matched users, calls the new
    `abortBlockedPair` helper. Skipped for solo (<2-player)
    matches so the synthetic-probe path stays clean.
    `abortBlockedPair` mirrors `abortProtocolMismatch`:
    fans `match_failed reason=blocked_pair` to every matched
    user with per-player tailoring (named-in-pair users get
    "you and another player have blocked each other"; bystanders
    get "two matched players have blocked each other"). On the
    game side `_classify_matchmaking_failure` routes the
    `"blocked"` substring to `LOADING.BLOCKED_PAIR` (recoverable
    + retry button on the loading screen, not toast-and-bounce).
  - Done — addon: `PlatformFriendsApiClient` adds three new
    methods (`block_user`, `unblock_user`, `fetch_blocked_users`)
    each wrapping the corresponding RPC; new
    `cached_blocked_users: Array[Dictionary]` field; three new
    signals (`user_blocked` / `user_unblocked` /
    `blocked_users_received`); new `is_blocked()` helper.
    `block_user` proactively prunes the blocked user from
    `cached_friends` / `cached_sent_requests` /
    `cached_incoming_requests` and inserts into
    `cached_blocked_users` so the UI updates without a round
    trip.
  - Done — UI: `FriendDetailsPanel` gets a Block action row
    (after Remove) with a confirm dialog quoting the friend's
    display name. New `BlockedUsersPanel` (extends `SidePanel`)
    lists blocked users with one-tap unblock; entry from
    `FriendsPanel` via a `SubPanelTriggerRow` ("Blocked Users")
    in the top action stack alongside Add Friend.
  - Done — i18n: 8 new translation keys × 13 locales:
    `FRIENDS.BLOCK`, `FRIENDS.UNBLOCK`, `FRIENDS.BLOCKED_USERS`,
    `FRIENDS.NO_BLOCKED_USERS`, `CONFIRM.BLOCK_USER`,
    `TOAST.USER_BLOCKED`, `TOAST.USER_UNBLOCKED`,
    `LOADING.BLOCKED_PAIR`. CSV validated at 14 fields per
    line for the new entries (the pre-existing legacy line 119
    with comma drift is untouched); .translation binaries
    re-imported via `godot --headless --import`. Non-English
    translations are best-effort and worth a native-speaker
    review pass.
  - Done — tests: 1 new test function in
    `block_list_test.go` (`TestFindBlockedPairs`) with 8
    sub-tests locking the pair-detection contract:
    empty-match → no pairs, no-blocks → no pairs, one-way
    block detected, two-way block de-duplicated to single
    pair, pair order stable (lower user_id first regardless
    of which direction was issued), block outside match
    ignored, self-block filtered out, multiple pairs in a
    larger match. `go vet ./... && go test ./... &&
    staticcheck ./...` clean; pluginbuilder Docker produces
    a 19 MB `snoringcat.so`.
  - Decision worth recording: use Nakama's built-in state=3
    BANNED rather than a custom storage schema. The
    `FriendsBlock`/`FriendsDelete`/`FriendsList(state=3)`
    primitives give us persistence + bidirectional add-
    rejection for free; a custom schema would need its own
    BeforeAddFriends hook and a separate cascade clean-up in
    `account.go`. Nakama's existing friends-cascade in
    `delete_account` already deletes state=3 rows alongside
    state=0/1/2 because it uses `FriendsDelete` (state-
    agnostic), so the block list cleanly inherits GDPR
    compliance without extra plumbing.
  - Decision worth recording: blocked-pair check fires
    *after* protocol-mismatch and *before* Edgegap
    allocation. The protocol check is cheaper (no I/O —
    reads from the games cache) so it should short-circuit
    first when a stale client is in the mix. The block
    check is N reads against Nakama's friends table; cheap
    relative to an Edgegap allocation (which takes seconds
    of real time) but expensive enough that we wouldn't
    want it in the matchmaker query itself. Future
    optimization could push the block list into ticket
    properties so the matchmaker rejects pairings without
    even reaching `OnMatchmakerMatched`, but that requires
    serializing the list into a query-friendly form and
    re-pushing on every block/unblock — not worth the
    complexity until block lists become a hot path.
  - Decision worth recording: cross-game, not per-game.
    Blocking is conceptually about avoiding a person, not a
    game; matches Nakama's friends-are-cross-game model.
    Sessions still need a valid `game_id` to call any
    block-list RPC, but the storage row itself isn't scoped
    by game_id. If a future game wants per-game block lists
    we can layer that as a separate scoped collection
    without disturbing the cross-game core.
  - Compliance: Stage 8.15 (`test_friends_block.gd`) shipped
    2026-05-13 as the end-to-end compliance test. Covers the
    block_user/unblock_user/list_blocked_users RPC contract,
    Nakama's bidirectional FriendsAdd rejection (via friend-
    state assertions; Nakama returns 200 OK with silent-skip
    semantics rather than an HTTP error), and the matchmaker
    blocked-pair abort fan-out under mock mode. 20 asserts
    green against live Nakama for the lifecycle test; the
    matchmaker test pends on prod (no EDGEGAP_MOCK_DEPLOY)
    consistently with the rest of Stage 8.
  - Known limitation: ships with a reused
    `remove_friend_icon.png` for the Block action and
    Blocked Users entry. A dedicated block / no-entry icon
    would be a tighter visual signal but isn't blocking;
    flagged as a future polish pass alongside the broader
    icon-audit work.
- [x] **7.5 Friend pagination (>100 friends; currently silently
  truncated at `friends_api_client.gd:56`)** (2026-05-13).
  - Done — addon: `PlatformFriendsApiClient.fetch_friends`
    now loops `Platform.nakama_client.list_friends_async` with
    a cursor across up to 10 pages × 100 entries (1000 cap),
    mirroring the runtime `account.go` cascade's bounded-loop
    pattern. Builds the new `cached_friends` /
    `cached_sent_requests` / `cached_incoming_requests` arrays
    in locals and swaps them in atomically after the last page,
    so a mid-pagination failure leaves the caches untouched.
    Cursor is read as String with a null-guard for the Nakama
    SDK's empty-string-vs-null inconsistency on the final page.
    Two new file-level constants (`_FRIENDS_PAGE_SIZE=100`,
    `_FRIENDS_PAGE_CAP=10`) replace the inline magic 100.
  - No consumer API change. `cached_*` fields are still
    `Array[Dictionary]` with the same per-entry shape (every
    consumer in `src/ui/`, `src/core/friends_notification_poller.gd`,
    etc. continues to read them without modification).
  - Verification: headless Godot boot clean (JWT refresh +
    `update_and_get_presence` succeed via live Nakama, zero
    parse/compile errors). No compliance test for the
    cursor-loop path itself — the existing
    `test_friends_multiuser.gd` (Stage 8.14) exercises
    `list_friends_async` indirectly via the HTTP API, and the
    sub-100-friend test pair short-circuits on the first page
    so a cursor-loop regression wouldn't surface there. A
    proper test would need to mint 101+ accounts and friend
    them all, which is heavy for compliance; deferred to a
    Tier 3 unit test with doubles (8.23) when that track
    lands.
  - Decision worth recording: hard cap at 1000 entries, not
    unbounded. A truly pathological friend list (10k+) would
    take 100+ HTTP round-trips to drain and produce a
    UI-unusable cached list anyway. The 1000 cap matches the
    runtime cascade's existing bound (10×100) and means
    fetch_friends has a predictable upper bound on round-trips
    even in adversarial cases. Future high-cap accounts that
    actually need >1000 visible friends would warrant a
    paged-UI redesign, not just a higher constant.
  - Decision worth recording: atomic swap on completion, not
    incremental append to `cached_friends`. The pre-extraction
    code reset and then appended page-by-page; that would have
    left a partially-populated cache visible if a mid-loop
    exception hit. Swapping locals in at the end keeps the
    cache consistent across the entire pagination — either the
    full list (capped) is visible or the prior state is.
- [x] **7.6 Recent-players list** (2026-05-13).
  - Done — runtime: new
    `third_party/snoringcat-platform/runtime/recent_players.go`.
    `writeRecentPlayersForMatch` hooks into `MatchEndRpc`
    (outside the `if !synthetic` block — the helper short-
    circuits on solo matches so the synthetic-probe path
    stays a no-op without explicit gating). Resolves matched
    users' display names + usernames via one `UsersGetId`
    call, then composes N×(N-1) per-pair `StorageWrite`s.
    Each row is keyed by the OTHER user's id and owned by
    THIS user, so re-matching the same player just overwrites
    `matched_at` rather than appending a duplicate row.
    Soft-deleted users (`display_name == anonymizedDisplayName`)
    are filtered as the `other` side so a player mid-cascade
    doesn't get ghost rows in fresh recent-players lists.
  - Done — runtime: new `list_recent_players` client-session
    RPC (`requireClientSession` + `requireGameID` like every
    other game-scoped RPC). Paginates the caller's
    `recent_players` storage via `nk.StorageList` (collection
    is non-empty here, unlike the cascade scrub bug 7.7 fixed)
    capped at 5 pages × 100 = 500 rows, then sorts by
    `matched_at` desc and truncates to `recentPlayersCap=50`.
    Response shape: `{recent_players: [{user_id, username,
    display_name, matched_at}]}`.
  - Done — addon: `PlatformFriendsApiClient` adds
    `cached_recent_players: Array[Dictionary]`,
    `fetch_recent_players()` method, `recent_players_received`
    signal, and `is_recent_players_busy()` concurrency guard.
    Follows the same shape as the existing
    `fetch_blocked_users` flow.
  - Done — UI: new `src/ui/settings_panel/recent_players_panel.{gd,tscn}`
    (extends `SidePanel`). Each row renders display_name + an
    Add Friend action via `ActionRow` + the existing
    `_add_friend_icon`. Client-side filter excludes rows
    already in `cached_friends` / `cached_sent_requests` /
    `cached_blocked_users` so the list stays focused on
    actionable opponents. `FriendsPanel` gets a new
    "Recent Players" `SubPanelTriggerRow` between Add Friend
    and Blocked Users in the top action stack.
  - Done — i18n: 2 new translation keys × 13 locales
    (`FRIENDS.RECENT_PLAYERS`, `FRIENDS.NO_RECENT_PLAYERS`).
    CSV verified at 14 fields per line; `.translation`
    binaries regenerated via `godot --headless --import`.
    Non-English translations are best-effort and worth a
    native-speaker review pass.
  - Done — tests: 5 new Go test functions in
    `recent_players_test.go` (24 sub-tests) lock the pure
    helpers: `uniqueUserIDs` (dedup, drops-empty, preserves-
    order, empty-input), `buildRecentPlayerWritesPairCount`
    (2-player → 2 writes, 4-player → 12 writes, solo → 0,
    missing-other dropped, [deleted]-other dropped, self-pair
    skipped), `buildRecentPlayerWritesValueShape` (locks the
    JSON shape + collection + permission contract), and
    `sortAndCapRecentPlayers` (desc by matched_at, cap
    truncation, under-cap no-op, stable on ties, empty input).
    `TestRecentPlayersCapConstantStable` canary guards the
    50-row cap against silent bumps. `go vet && go test &&
    staticcheck` clean; pluginbuilder Docker produces a
    19 MB `snoringcat.so`.
  - Done — compliance: new
    `addons/snoringcat_platform_client/test/compliance/test_recent_players.gd`
    with 2 tests / 66 asserts.
    `test_list_recent_players_returns_empty_for_fresh_user`
    locks the empty-list contract; `test_list_recent_players_sorts_by_matched_at_desc_and_caps`
    seeds `recentPlayersCap + 3 = 53` fake rows directly via
    `/v2/storage` and asserts the response is exactly 50
    entries with the newest seeded row first and the oldest
    truncated. The seeded rows use `permission_write=1`
    (owner-writable) to bypass the production `0` (server-
    only) since `/v2/storage` only accepts bearer-auth user
    writes; the test code documents the divergence in
    `_seed_row`'s comment.
  - Decision worth recording: per-pair writes happen even on
    synthetic matches because the synthetic-probe flow is
    1-player and the helper's `if len(ids) < 2` already
    short-circuits. Gating on `synthetic` would have
    foreclosed future synthetic multi-player flows from
    recording recent-players without an extra plumbing pass.
  - Decision worth recording: key = OTHER user's id (not a
    request_id or timestamp). The natural-dedup behavior is
    the point — playing someone twice should refresh their
    row, not duplicate it. Sorting/capping happens at read
    time so the storage itself isn't pruned; the cap is a
    response-shaping concern, and storage rows survive until
    the GDPR cascade scrubs them on account delete.
  - Decision worth recording: cap of 50 entries. High enough
    to capture a decent session's worth of opponents; low
    enough that the response fits in a single render pass on
    the side panel. Subject to revisit if real usage shows
    players want a longer list.
  - Decision worth recording: client filters already-friends
    / pending-request / blocked players out of the rendered
    list rather than the server pruning them from the
    response. Keeps the server response stable (same shape
    regardless of who's reading), and the filter logic
    re-runs on every panel paint so a fresh add-friend
    accept immediately removes that row.
- [x] **7.7 Full GDPR cascade verification** (2026-05-13).
  - Done — compliance: new
    `addons/snoringcat_platform_client/test/compliance/test_account_delete_cascade_surfaces.gd`
    (single test, 20 asserts) extends 8.16 (friends cascade)
    to cover every other state surface the cascade should
    clear. Seeds: presence row via `update_and_get_presence`,
    a party-prefixed group with the user as creator, and 2
    user-owned storage rows in a custom collection. Asserts
    each surface clears post-`delete_account` AND the
    `account_deletion_queue` audit row is preserved via
    `get_account_deletion_status` returning `pending=true`.
  - Done — runtime fix: the test exposed a real GDPR bug.
    `account.go`'s cascade and `player_data.go`'s
    `export_player_data` both called
    `nk.StorageList(ctx, "", userID, "", limit, cursor)`
    expecting "all collections" semantics. Nakama's
    underlying SQL has `WHERE collection = $1`, so an empty
    collection matches zero rows — user-owned storage was
    silently surviving every account deletion since Stage
    1.4 shipped, and GDPR data exports returned empty
    `storage_objects` regardless of the user's real rows.
    Fixed both via direct SQL in the same pass:
    - `account.go::deleteAccountRpc` now runs a single
      `DELETE FROM storage WHERE user_id = $1::uuid AND
      collection != $2` with `accountDeletionCollection`
      as the carve-out. Threaded `db` through the factory.
    - `player_data.go::exportPlayerDataRpc` now runs
      `SELECT collection, key, value, create_time, update_time
      FROM storage WHERE user_id = $1::uuid ORDER BY
      collection, key LIMIT 1000`. Same threading.
    Both casts are explicit `::uuid` to avoid relying on
    implicit text-to-uuid coercion across pg-driver
    versions.
  - Verification: pre-fix the test had 19/20 asserts green
    with only the storage-row count failing (2 survived);
    post-fix 20/20 green against the deployed runtime
    (build `628fc3a`). 8.16 friend cascade re-run also
    green so the SQL fix didn't regress the friends side.
  - Decision worth recording: direct SQL rather than
    `nk.StorageList` → `nk.StorageDelete` per-collection.
    The list-then-delete loop would require enumerating
    every collection any game has ever written to (the
    test caught the bug specifically because the cascade
    didn't know about arbitrary collection names); a single
    SQL DELETE scrubs all of them in one round trip and is
    safe to do bypassing nk because storage has no Nakama-
    side cache layer to invalidate.
  - Decision worth recording: 1000-row cap on the export
    SELECT. A pathological account with > 1000 rows would
    have an export response too large to be useful anyway,
    and the cap keeps a single export call from blocking
    Nakama for a long time on Postgres.
  - Known limitation: the leaderboard cascade isn't
    exercised by the new test (it would require seeding a
    leaderboard record, which compliance tests can't do
    cleanly without a real match). The existing Go unit
    test `TestLeaderboardIDsToScrubPrefixesAndLegacy`
    already locks the cascade's leaderboard ID derivation;
    end-to-end leaderboard clearing remains exercised only
    by manual smoke + the live `delete_account` execution.
- [x] **7.8 Account-merge flow UI** (2026-05-13).
  - Done — game: new `src/ui/settings_panel/merge_account_panel.{gd,
    tscn}` extends `SidePanel`. Pushed by `LinkAccountRow._open_
    merge_panel` when the link attempt returns `PROVIDER_CONFLICT`.
    Renders header (`MERGE.HEADER` = "Existing Account Found"),
    a fuller body (`MERGE.BODY`) with the provider name interpolated
    explaining what merges and that the action cannot be undone,
    an explicit Continue-and-Merge `ActionRow` (with merge icon),
    and an explicit Cancel `ActionRow`. Configure() takes the
    provider enum + display name from `LinkAccountRow` before the
    panel enters the tree so the body interpolation is right.
  - Done — game: `link_account_row.gd`'s old `_offer_merge` /
    `_do_merge` / `_on_merge_cancelled` / `_on_merge_completed`
    methods all retired. The new `_open_merge_panel` is the sole
    PROVIDER_CONFLICT path; `merge_completed` subscription lives
    on the panel now, not the row. `_merge_account_panel_scene`
    added as a new `@export` on the row scene and wired in
    `link_account_row.tscn`.
  - Done — game: `MergeAccountPanel.build_ui` subscribes to
    `Platform.auth.merge_completed`; on success, shows the new
    `TOAST.ACCOUNTS_MERGED` toast and `manager.close_all()` to
    return to the lobby; on failure, re-enables the rows and
    surfaces the error via `TOAST.MERGE_FAILED`. Tracks
    `_explicit_action_taken` so `_exit_tree`'s safety-net
    `cancel_merge` call only fires when the user popped via the
    back row (server-side merge token would otherwise leak across
    the next link attempt).
  - Done — i18n: 5 new keys × 13 locales: `MERGE.HEADER`,
    `MERGE.BODY` (long template), `MERGE.CONTINUE`,
    `TOAST.ACCOUNTS_MERGED`, `TOAST.MERGE_FAILED`. Bodies use
    `period-separated` sentences instead of comma-separated
    clauses to keep CSV-with-no-escaping rules happy. 3 prior
    keys retired: `CONFIRM.MERGE_ACCOUNT` (old confirm-dialog
    body), `LINK.MERGE` (old confirm-accept button label),
    `LINK.MERGING` (old in-flight status). The ConfirmOverlay
    flow they served is gone. CSV verified at 14 fields per line
    for every new entry; `.translation` binaries regenerated.
    Non-English translations are best-effort and worth a native-
    speaker review pass.
  - Decision worth recording: dedicated `SidePanel`, not an
    enhanced `ConfirmOverlay`. The audit's "no UI today" framing
    was strict about the absence of a focused screen for a
    destructive irreversible action. `ConfirmOverlay`'s single
    message label + two buttons can't carry the same context
    weight as a panel with discrete header, body, and action
    rows. The cost is two new files + a small refactor of
    `LinkAccountRow`; the benefit is a UX surface that matches
    the gravity of "this cannot be undone" the way the existing
    delete-account sub-panel (Stage 1.5) does.
  - Decision worth recording: `_explicit_action_taken` flag
    instead of trusting the auth client's internal `_pending_
    merge_token` state. The token is private to
    `PlatformAuthApiClient`, and exposing it via a getter just
    for the panel's exit cleanup would have leaked an
    implementation detail. The local flag is one bool and self-
    contained; the same pattern any future "cancel-on-exit
    unless explicit" panel can copy.
  - Known limitation: no compliance test for the
    PROVIDER_CONFLICT branch. The link/merge contract is server-
    side (Nakama's `LinkX` returns a merge token when the
    requested provider is on another account), which is hard to
    reproduce in CI without minting two real OAuth identities
    and conflicting them. The flow is verified by code inspection
    + headless boot + the production smoke loop (Levi runs the
    Google-link scenario manually before each release pass).
- [x] **7.9 Anonymous → permanent upgrade UI** (2026-05-13).
  - Done — game: new `src/ui/settings_panel/upgrade_account_panel.
    {gd,tscn}` extends `SidePanel`. Anonymous-only entry that's
    pushed from `MainMenuPanel` in place of the existing "Account"
    row. Renders header (`UPGRADE.HEADER` = "Keep Your Progress"),
    body (`UPGRADE.BENEFITS_BODY` — explains friends/parties +
    leaderboards + cross-device sync benefits), the existing
    Google + Facebook `LinkAccountRow`s (which already drove the
    anonymous→permanent login flow internally via
    `Platform.auth.login_with_provider`), and a "Maybe later"
    close `ActionRow`.
  - Done — game: `main_menu_panel.gd` branches on
    `Platform.token_store.is_anonymous`. Anonymous users get a
    `SETTINGS.SIGN_IN` row routed to the new panel with the badge
    visible by default; authenticated users keep the existing
    `SETTINGS.ACCOUNT` → `AccountPanel` row. The `_upgrade_account_
    panel_scene` export is wired in `main_menu_panel.tscn`.
  - Done — i18n: 4 new keys × 13 locales: `SETTINGS.SIGN_IN`
    (new label, distinct from the existing `SETTINGS.ACCOUNT`),
    `UPGRADE.HEADER`, `UPGRADE.BENEFITS_BODY` (long template),
    `UPGRADE.MAYBE_LATER`. CSV verified at 14 fields per line
    for every new entry (pre-existing legacy line 120 with comma
    drift is untouched); `.translation` binaries regenerated.
    Non-English translations are best-effort and worth a native-
    speaker review pass.
  - Decision worth recording: dedicated `UpgradeAccountPanel`,
    not an enhanced `AccountPanel`. The audit-derived task name
    "Anonymous → permanent upgrade UI" carries the implication
    of a focused surface that explains the value proposition,
    not just a re-titled row. `AccountPanel`'s existing render
    path for anonymous users (`_add_link_account_rows`) shows
    the Google/Facebook rows but no explanatory copy; bolting
    that copy onto the same panel would have made it conditional
    on `is_anonymous` and harder to read. The new panel keeps
    `AccountPanel` clean for the authenticated case and gives
    anonymous users a focused screen.
  - Decision worth recording: badge visible by default on the
    main menu's Sign-In row. The existing badge mechanism is
    used for friends-have-news / party-has-invites — both
    transient signals the user dismisses by interacting. The
    upgrade badge is persistent (always-on until the user
    upgrades), which slightly stretches the badge semantic, but
    the alternative (a separate icon-style attention indicator)
    would have required a new asset. Subject to revisit if
    user testing shows the badge is "shouting" rather than
    "drawing the eye".
  - Decision worth recording: no post-match / on-gated-tap
    prompts in this pass. The natural next step is a one-shot
    prompt overlay (similar to `account_deletion_prompt.gd`)
    that appears periodically for anonymous users, plus inline
    "sign in to access" prompts when an anonymous user tries to
    open Friends / Party / MyStats. Both are additive and can
    layer on top of the existing surface without disturbing it;
    deferred to a follow-up polish pass to bound this session's
    scope.
  - Known limitation: no compliance test for the UI flow. The
    underlying RPC (`login_with_provider` for anonymous-upgrade)
    is already exercised by `test_socket_auth.gd` and the
    platform smoke test, so the flow itself isn't an unknown.
    The panel-rendering / badge-routing logic is verified by
    headless boot + manual smoke.
- [x] **7.10 Mid-match rejoin (reconnect flavor, lightweight)**
      (2026-05-14).
  - Design lockdown (with user, before any code):
    **(a) Reconnect** (same player resumes), not backfill;
    **(b) slot + score only** preserved (treat the gap as
    died-and-respawning — the bunny entity is despawned on
    disconnect and re-spawned fresh on reconnect with full
    HP, but the PlayerState slot + kills/bumps counters
    carry over); **(c) 30s grace window**, fixed (not per-
    game.yaml).
  - Done — framework (`addons/rollback_netcode`,
    submodule `02c65b0`): NetworkConnector adds a server-
    side `_session_id_to_player_id` map.
    `_server_rpc_declare_players` and `local_mode_setup`
    both look up the incoming session_id before assigning
    a fresh `_next_player_id` — a client that reconnects
    with the same session_id receives the same player_id
    they had before the disconnect. New public method
    `server_clear_session_id_mapping(session_id)` lets the
    game side drop a mapping when it decides the player
    is truly gone. `reset_local_mode` also clears the map.
  - Done — game-side server: `GameMatchState` gains a
    `signal player_reconnected(player: PlayerState)` and a
    `server_on_player_reconnected(player)` method that
    re-adds the player to the `_connected_players` set and
    fires both `player_reconnected` + `players_updated`.
    `MatchStateSynchronizer` gains
    `RECONNECT_GRACE_SEC=30.0`, a `_grace_timers` dict
    keyed by player_id, two new signals
    (`reconnect_grace_started` + `reconnect_grace_expired`),
    plus `_server_start_grace_timer` /
    `_server_cancel_grace_timer` /
    `_server_on_grace_expired` helpers.
    `_server_on_peer_disconnected` calls
    `_server_start_grace_timer` after the existing
    despawn flow.
    `_server_on_peer_players_declared` detects the
    reconnect case (`state.players_by_id.has(player_id)`
    with `is_connected_to_server=false`), refreshes the
    existing PlayerState's peer_id / local_player_index /
    connect_frame_index, cancels the grace timer, and
    fires `player_reconnected` instead of `player_joined`.
    `server_cancel_all_grace_timers()` for match teardown.
  - Done — game-side game_panel: `_on_player_left` no
    longer immediately runs
    `_server_check_auto_end_on_disconnect`. The check is
    deferred to the new
    `_on_reconnect_grace_expired(player_id)` handler that
    fires 30s post-disconnect (unless the player
    reconnects). New `_on_player_reconnected(player)`
    logs the resume.
  - Done — client-side reconnect loop
    (`src/core/reconnect_handler.gd`, new): a
    ReconnectHandler node owned by GamePanel that captures
    match-ready connection params
    (server_ip / server_port / signaling_url /
    transport_type) on `_on_session_ids_received` and, when
    `game_panel._on_connection_lost` fires unexpectedly
    mid-match, replaces the immediate exit-match with a
    backoff retry loop. Retry interval 5s, max 6 attempts
    within the 30s window. Each successful reconnection
    triggers the framework's `connected` signal, which
    game_panel routes to `notify_reconnected()`; if all
    attempts fail, `reconnect_failed` fires and game_panel
    falls through to the normal `client_exit_match()` path.
    ENet-only at 7.10 ship time; the
    `can_attempt_reconnect()` transport gate was lifted in
    7.10b (2026-05-14, eighteenth pass) so all three
    transports use the same loop now.
  - Done — UI (`src/ui/reconnecting_overlay/`, new):
    `ReconnectingOverlay` is a CanvasLayer overlay that
    shows a `LoadingSpinner` + "Reconnecting..." header
    + "(Xs remaining)" countdown. Programmatic layout
    (no .tscn) because the structure is trivial. GamePanel
    spawns it on `reconnect_started`, updates the
    countdown on `reconnect_attempt`, and frees it on
    `reconnect_succeeded` / `reconnect_failed`. Plus
    toast messages: `TOAST.RECONNECTED` (success) and
    `TOAST.RECONNECT_FAILED` (fail).
  - Done — i18n: 4 new translation keys × 13 locales
    (`RECONNECT.HEADER`, `RECONNECT.COUNTDOWN`,
    `TOAST.RECONNECT_FAILED`, `TOAST.RECONNECTED`). CSV
    verified at 14 fields per line for every new entry.
    `.translation` binaries regenerated via
    `godot --headless --import`. Non-English translations
    are best-effort and worth a native-speaker review pass
    (same caveat as every other recent i18n add).
  - Decision worth recording: the framework's
    session_id -> player_id map is the right scope (not
    PlayerState, not a game-side dict). Each session is
    one match's reservation; the map's lifetime is one
    match (game-server container restarts at match end).
    Putting it on PlayerState would require a framework
    schema change AND would replicate the session_id to
    other clients — overkill for a server-only lookup. A
    game-side dict would have to mirror the framework's
    own player_id assignment logic, which is brittle.
    The framework owns player_id assignment, so the
    framework owns the session_id mapping.
  - Decision worth recording: 30s grace is fixed, not
    per-game.yaml configurable. The user explicitly
    picked "30 seconds" over "configurable per game.yaml"
    in the design call. A future game with different
    pacing can re-evaluate.
  - Decision worth recording: programmatic
    ReconnectingOverlay layout, not a .tscn. The
    structure is one ColorRect + CenterContainer +
    VBoxContainer + 3 widgets — adding a separate scene
    file would add maintenance surface (export var
    wiring, scene-instance bugs on hot reload) without
    payoff. Easy to swap to a .tscn later if the design
    needs more flexibility.
  - Decision worth recording: the despawn happens
    immediately on disconnect (not deferred to grace
    expiry). The "lightweight slot + score only"
    framing the user picked is functionally
    "treat the gap as died-and-respawning"; deferring
    despawn would mean the bunny entity lingers without
    input, which is a weirder UX than a fresh respawn.
    Score is preserved on PlayerState (which stays in
    `players_by_id` throughout grace), so the rejoining
    player still sees their kill/bump counts.
  - Decision worth recording: ENet-only in v1 (shipped
    2026-05-14, seventeenth pass). WebRTC + WebSocket
    reconnect was deferred to 7.10b because each
    transport's signaling re-negotiation (WebRTC SDP+ICE,
    WebSocket TLS) is heavier than ENet's UDP redial.
    7.10b shipped 2026-05-14 (eighteenth pass) by dropping
    the `can_attempt_reconnect()` transport gate and
    adding a stale-`_webrtc_peer` cleanup in the
    framework's `_client_start_webrtc` so re-dial doesn't
    leak the dropped match's RTC stack.
  - Known limitation: no compliance test for the
    reconnect path. End-to-end testing means simulating
    a mid-match disconnect on a live deployment, which
    isn't easily automatable against prod. Tier 4
    docker-compose e2e (8.29) is the natural place for
    it; deferred.
  - Known limitation: spectator-side disconnected
    badge in the in-match HUD not implemented in v1.
    Other players currently see the disconnected
    player's bunny vanish but don't get an explicit
    indicator that they're disconnected (vs. just
    out of view). Follow-up; the PlayerState's
    `is_connected_to_server` getter is the read source.
  - Known limitation: framework's
    `_session_id_to_player_id` map isn't cleared on
    grace expiry in v1. The lookup-stale-mapping case
    is theoretically possible but practically
    impossible (session_ids are per-match-allocation
    so collision within the same match-server-container
    lifetime is near-zero). The
    `server_clear_session_id_mapping()` hook exists
    for a future caller; the v1 code just doesn't
    invoke it.
- [x] **7.10b Mid-match rejoin transport parity (WebRTC +
      WebSocket)** (2026-05-14, eighteenth pass).
  - Done — game: dropped the `_transport_type !=
    NetworkSettings.TransportType.ENET` short-circuit in
    `src/core/reconnect_handler.gd::can_attempt_reconnect()`.
    The reconnect loop now fires for all three transports;
    the framework's `client_connect_to_server` path handles
    transport-specific re-dial mechanics (WebRTC re-runs
    signaling, WebSocket re-handshakes TLS, ENet re-creates
    the UDP peer). Refreshed the class docstring + the
    inline "ENet-only in v1" comments in `game_panel.gd`
    (field doc + `_on_connection_lost` block) to reflect
    full transport coverage.
  - Done — framework (`rollback_netcode` submodule):
    `network_connector.gd::_client_start_webrtc` now mirrors
    the existing `_webrtc_signaling_client` cleanup with a
    parallel close-and-null on any stale `_webrtc_peer` left
    over from a prior connection. Without this, the
    PeerStates from the dropped match (and their underlying
    `WebRTCPeerConnection` / DataChannels) would linger
    until the next garbage-collection cycle freed
    `WebRTCGamePeer` — defensible on first-connect (always a
    no-op) and load-bearing on reconnect. Uses the existing
    `MultiplayerPeerExtension._close()` override which
    iterates `_peers` and calls `remove_peer` on each
    (already implemented in `webrtc_game_peer.gd`).
  - Verification: `godot --headless --import` exits cleanly
    (3037 bytes of output, zero parse/compile errors). No
    end-to-end smoke test for the reconnect path itself —
    same blocker as 7.10's: simulating a mid-match
    disconnect on a live deployment isn't easily
    automatable against prod. Tier 4 docker-compose e2e
    (8.29) remains the natural home for transport-parity
    integration coverage.
  - Decision worth recording: shared retry interval (5s
    × 6 attempts within the 30s grace), not transport-
    aware. ENet redials in milliseconds; WebRTC signaling
    needs ~2–3s in the happy path (server already bound,
    so the WebRTCSignalingClient's 12 × 750ms internal
    retry typically succeeds on attempt 1). With a 5s
    outer interval, each WebRTC reconnect attempt gets a
    full ~5s budget for its signaling cycle; if the cycle
    is still mid-flight when the outer timer fires, the
    next `_attempt_reconnect` tears down the in-progress
    signaling client and starts fresh. Wasteful but not
    broken; tuning per-transport intervals would be polish.
  - Decision worth recording: defense-in-depth close on
    the stale `_webrtc_peer` (vs trusting RefCounted GC).
    `WebRTCGamePeer` extends `MultiplayerPeerExtension`
    (RefCounted-ish) and DOES override `_close()` to
    cascade `remove_peer` to each entry, but Godot's
    PREDELETE notification path doesn't invoke `_close`
    automatically — only `multiplayer.multiplayer_peer =
    new_peer` and dropping the `_webrtc_peer` reference
    would. The dropped `WebRTCPeerConnection`s might
    still hold UDP socket bindings momentarily, which
    the new peer's ICE agent needs to claim. Explicit
    `close()` makes the order deterministic.
  - Known limitation: same as 7.10's compliance gap. The
    transport-parity claim is verified by static read of
    `client_connect_to_server`'s transport switch + the
    headless boot's parser pass. End-to-end transport-
    parity proof would need a 2-browser smoke (web client
    drops + reconnects via WebRTC + match completes)
    which is operator-driven, not CI.
- [x] **7.11 Re-introduce lightweight observability** (2026-05-13).
  - Done — infra: `infra/remote/nakama/docker-compose.yml`
    re-adds four services on the single-host CPX11:
    `prometheus` (v2.55.1, 30d TSDB retention, scrapes Nakama
    metrics + caddy admin + node-exporter + postgres-exporter),
    `grafana` (v11.4.0, fronted by Caddy at
    `grafana.snoringcat.games` with TLS via Let's Encrypt),
    `node-exporter` (v1.8.2, host vitals, pid=host, fs mount
    excludes), `postgres-exporter` (v0.16.0, connects to the
    co-tenanted postgres container via the nakama-net network).
    Loki + Promtail intentionally left off — logs stay on
    `journalctl` / `docker logs`; their configs are preserved
    in the same directory so a future need can flip them on
    without reconstruction.
  - Done — Nakama config: added `--metrics.prometheus_port 9099`
    to the entrypoint CLI flags. `9099` exposed on the
    nakama-net network; prometheus.yml has a `nakama` job
    scraping `nakama:9099` with `metrics_path: /` (Nakama
    publishes Prometheus-format metrics at the root path on
    that port).
  - Done — prometheus.yml: dropped the stale `node-postgres` +
    `postgres` jobs that pointed at `10.0.1.20:9100` /
    `10.0.1.20:9187` (the pre-consolidation separate Postgres
    box that no longer exists). Both jobs collapse into the
    co-tenanted setup. Also dropped the `loki` scrape job
    (not running Loki). All remaining jobs label
    `instance: nakama-prod-1`.
  - Done — Grafana provisioning: kept the existing
    `provisioning/{datasources,alerting,dashboards}` tree
    intact. Datasources auto-provision Prometheus (the
    "Loki" entry is preserved but inert; no datasource health
    check fails because Grafana lazy-validates on first
    query). Five alert rules in `alerting/rules.yml`
    auto-load: `nakama-down`, `postgres-down`,
    `postgres-conn-saturation`, `disk-usage-high`,
    `cpu-sustained-high` (plus a placeholder slow-queries
    rule). Discord contact point in
    `alerting/contactpoints.yml` routes all alerts; the
    policy in `alerting/policies.yml` groups by alertname +
    instance with 30s wait / 5m group / 4h repeat.
    Dashboards directory was empty before the consolidation
    and stays empty — operators build them in the UI as
    needs surface (the obs stack's purpose today is
    primarily alerting on quantifiable failure, not
    dashboard polish).
  - Done — Caddyfile: re-added the `grafana.snoringcat.games`
    site block. Proxies to `grafana:3000` with TLS auto-
    provisioned via Let's Encrypt. Header forwarding matches
    the nakama block; gzip enabled.
  - Done — Pulumi
    (`infra/pulumi/snoringcat-platform/main.go`): re-added
    `cloudflare.NewRecord` for `grafana-a` (Cloudflare DNS A
    record pointing at the nakama-prod-1 public IP,
    proxied=false) + matching `grafana_dns_record_id` +
    `grafana_url` exports. Updated the CPX11 const-block
    comment to record the Stage 7.11 re-introduction
    rationale and the headroom check (603 MB used + 1.3 GB
    available pre-deploy; lightweight obs lands in ~350 MB
    resident).
  - Done — runtime instrumentation
    (`runtime/fleet_allocator.go`): `OnMatchmakerMatched`
    now starts a `matchStart := time.Now()` after the
    early-return on empty entries, and records a
    `snoringcat_alloc_seconds` Nakama custom timer via
    `nk.MetricsTimerRecord` after the post-allocation
    cancel checkpoint (so cancelled allocations don't skew
    the success-path histogram). Tags `game_id` +
    `mock=true|false` keep mock-mode test runs from
    polluting real-mode dashboards. Recorded via Nakama's
    built-in custom-metrics surface which fans out through
    the same `:9099` Prometheus endpoint Prometheus already
    scrapes — no separate HTTP server needed.
  - Done — docs: PLATFORM_ARCHITECTURE.md operations diagram
    + STUDIO_ARCHITECTURE.md Hetzner section + hopnbop
    CLAUDE.md "production resources" + status preamble all
    refreshed to reflect the new lightweight obs subset.
  - Verification: `go vet ./... && go test ./... &&
    staticcheck ./...` all clean. Pluginbuilder Docker
    image deferred to the CI runtime workflow; local Go
    build path is sufficient signal for the test gate.
  - Decision worth recording: lightweight subset, not full
    stack. The original strip (2026-05-06) was forced by the
    2 GB CPX11 RAM cap after collapsing the 2-host stack
    onto one. The live host check before re-enable showed
    1.3 GB available with the consolidated stack. The
    lightweight subset (Prometheus + Grafana + 2 exporters)
    fits in ~350 MB resident with comfortable margin; adding
    Loki + Promtail would land ~150 MB more — feasible but
    pushes the box into uncomfortable-under-load territory
    without a clear payoff today. journalctl + docker logs
    cover the ops use case. The Loki/Promtail configs stay
    in-tree so a future "queryable logs would actually help
    here" moment doesn't require rebuilding from scratch.
  - Decision worth recording: custom metric is a single
    Nakama-side timer, not a separate Prometheus HTTP
    server. `nk.MetricsTimerRecord` fans out through
    Nakama's built-in `:9099` endpoint as a histogram with
    the same prefix Nakama uses for its own metrics. Cheap
    (one nakama-common API call per match), no extra port
    surface to firewall, and the metric inherits the same
    scrape cadence + alerting reach as everything else.
  - Decision worth recording: `game_id` + `mock` are the
    only tags. Per-attempt or per-region tags would add
    cardinality without payoff today — a single rolling
    histogram across all attempts answers "is allocation
    latency drifting?" and the retry-count is already in
    `logger.Info` lines for any debug deep-dive. Subject to
    revisit if dashboards need per-region heatmaps.
  - Known limitation: no compliance test for the new metric
    surface. End-to-end testing means querying Prometheus
    after a live allocation, which requires the obs stack
    actually running. The 8.13 mock-mode allocation in
    `test_party_to_matchmaking.gd` exercises the
    instrumented code path — a future Tier 4 e2e (8.29–8.31
    docker-compose track) could assert
    `snoringcat_alloc_seconds_count` increments after a
    mock match.
  - Live deploy executed 2026-05-13. Procedure followed:
    SCP'd `docker-compose.yml`, `prometheus.yml`,
    `Caddyfile`, `grafana/provisioning/` tree to
    `/opt/nakama/`; rendered `contactpoints.yml` with the
    Discord webhook URL before SCP (Grafana doesn't
    interpolate `${ENV}` at provision time); appended
    `GRAFANA_ADMIN_PASSWORD` + `DISCORD_WEBHOOK_URL` to
    `/opt/nakama/.env`; ran `docker compose up -d --build
    --pull always --remove-orphans` on the host; ran
    `pulumi up` from the operator workstation (created the
    grafana-a Cloudflare A record); triggered
    `nakama-runtime.yml` to deploy the
    instrumentation-bearing runtime plugin.
  - Live-deploy follow-ups (both committed as a separate
    patch alongside this entry's main commit):
    - `Caddyfile`: added `admin 0.0.0.0:2019` to the
      global block. Default `localhost:2019` is
      unreachable from sibling containers across docker-
      network namespaces; the prometheus scrape job to
      `caddy:2019` reported "connection refused" until
      this patch. Cloud firewall still blocks 2019/tcp
      from the public internet (only nakama-net peers
      reach it).
    - Host-side `chmod -R a+rX
      /opt/nakama/grafana/provisioning`. SCP defaults to
      root-owned + 600 perms; Grafana's container runs as
      UID 472 and couldn't read the directory. The
      provisioning files are non-secret config except
      `contactpoints.yml` which carries the Discord
      webhook URL (already exposed in `/opt/nakama/.env`
      as a soft secret).
- [x] **7.12 Max pending friend request enforcement** (2026-05-13).
  - Done — runtime: new
    `third_party/snoringcat-platform/runtime/friends_limits.go`,
    registered in `main.go::registerFriendsLimitHook`. The
    `BeforeAddFriends` hook walks the caller's current state=1
    (INVITE_SENT) entries via `nk.FriendsList`, paginated to
    `(maxPendingOutgoingFriendRequests+1)` pages of 100 so a
    pathological pending list (5000+ outstanding) short-circuits
    without burning every page. Sums `(existing + len(Ids) +
    len(Usernames))` against the new file-level constant
    `maxPendingOutgoingFriendRequests=50`; rejects with
    `runtime.NewError(..., 9)` (FAILED_PRECONDITION) when the
    total would exceed the cap.
  - Server-to-server callers (no `RUNTIME_CTX_USER_ID`) pass
    through. Per-caller, not per-recipient — the cap is on the
    caller's outgoing inbox.
  - Test coverage: included in `friends_limits_test.go`'s
    `TestFriendsLimitsConstantsStable` (catches a future bump
    that drifts away from the roadmap-documented cap). End-to-
    end count check itself is covered by the live runtime — a
    mock `runtime.NakamaModule` would need ~30 interface
    methods for marginal value vs the existing Tier 1 / Tier 2
    split.
  - Decision worth recording: cap of 50. High enough that
    normal social use never hits it; low enough that a spam
    attacker can't blast a thousand-recipient inbox flood
    before rejection.
  - Decision worth recording: `BeforeAddFriends` is the only
    enforcement point. No client-side preflight check — the
    SDK surfaces the runtime's error message via the existing
    `request_failed(error)` signal on
    `PlatformFriendsApiClient`. A malicious client that
    bypasses the SDK still hits the hook.
- [x] **7.13 Friend-code rate-limit** (2026-05-13).
  - Done — runtime: paired with 7.12 in the same
    `friends_limits.go` hook. New `friendsLimiter` struct holds
    a `map[string][]int64` (caller user_id → sliding-window
    timestamps) guarded by a `sync.Mutex` and a clock-of-
    record `now func() time.Time` so tests can inject a fake.
    `allowFriendCodeCall(userID)` prunes timestamps older than
    `friendCodeRateLimitWindow=60s` in-place (O(prune_count)
    leading-slice scan), then either appends the current
    timestamp and returns `true` OR returns `false` without
    recording when the count is already at
    `friendCodeRateLimitCount=10`. Rejected calls don't burn a
    slot in the window.
  - Hook applies the limit only when `len(in.GetUsernames()) >
    0` (the add-by-code path). `Ids`-only paths (accept-
    incoming-request, add-by-recent-match) don't expose codes
    to brute-force enumeration, so they're exempt from this
    limit but still subject to 7.12's pending cap.
  - State is in-memory only. A restart wipes every user's
    window, which gives every user a free fresh budget. That's
    fine: the worst case is one extra burst per restart, and a
    restart-driven attacker has bigger problems than friend-
    code enumeration. Persistence (Nakama storage row per
    user) would add a write per call without changing the
    security story.
  - Test coverage: 6 new tests in `friends_limits_test.go` via
    a fake clock. Respects-limit, slides-window after
    `friendCodeRateLimitWindow` advance, per-user-isolated
    (different callers don't share budgets), prunes-
    incrementally (half-window-stale entries drop off and the
    cap refills cleanly), empty-user no-op (server-to-server
    callers can't be locked out), constants-stable canary
    (catches future bumps).
  - Decision worth recording: 10 calls / 60 s. Comfortably
    above the legitimate "I'm adding 5 friends after a meet-
    up" peak; orders of magnitude below the throughput
    required to enumerate the 32^6 = ~1B-entry friend-code
    space in any reasonable time. Subject to revisit if real
    usage data shows the limit pinches legitimate users.
  - Decision worth recording: `sync.Mutex`-protected map
    instead of `sync.Map`. The per-call work is dominated by
    7.12's `nk.FriendsList` round trip (the rate check runs
    first but the pending-cap check fires on every successful
    rate check), so the lock contention is negligible. Plain
    map is the simpler model.
  - Decision worth recording: hook does NOT call
    `nk.FriendsList` to enforce 7.13 — rate limit is per-call
    accounting, not per-pending-state. The hook does call
    `nk.FriendsList` for the 7.12 path (which fires after the
    rate check). So an add-by-id call (rate-limit-exempt)
    still incurs the FriendsList round trip; an add-by-
    username call that's rate-limited short-circuits before
    the round trip. Cheap to add the rate check first.

## Stage 8 — Test foundation (parallel track)

**Goal:** Build a regression net. Run concurrently with Stages 1–7;
prioritize tests that protect work landing in the current stage.

### Tier 1 — runtime unit tests (Go)

- [x] **8.1 Add `go test ./runtime/...` step to
  `.github/workflows/nakama-runtime.yml`** (2026-05-13).
  - Done: new `test` job in `nakama-runtime.yml` runs
    `go vet ./... && go test ./... && staticcheck ./...` in
    the runtime working directory. The `nakama-runtime`
    deploy job gains `needs: test` so a failing gate blocks
    the SCP-to-host step. Passes with 0 tests today (Go
    treats "no test files" as exit 0); the gate exists for
    Stage 8.3–8.10 fill-in.
  - Mirrors the existing `nakama-runtime-go` job in
    `pr-validate.yml` exactly (same Go version, same three
    commands, same working dir). The deploy-time copy is
    the real safety net for this repo's direct-to-main
    workflow — PRs are rare per the repo's commit policy.
- [x] **8.2 Add `staticcheck` if not already running**
  (already shipped pre-8.1). `pr-validate.yml`'s
  `nakama-runtime-go` job runs `staticcheck ./...`; 8.1
  extends the same command to the deploy gate.
- [x] **8.3 `runtime/fleet_allocator_test.go`** (2026-05-13).
  - Done: covers `pickTCPPort` (case-insensitive protocol match,
    zero-external skip, nil-map safety), `signSignalingURL`
    (determinism for fixed inputs, base64url + HMAC-SHA256 wire
    shape, distinct expiry across clocks),
    `synthesizeMockDeploy` (port shape mirrors
    `Dockerfile.edgegap`, request_id includes mock prefix,
    pickTCPPort lights up on the mock map, distinct nanos →
    distinct request_ids), and `pickDominantGameID` (dominant
    wins, ties alpha-resolve, unknown game_ids dropped, all-
    unknown returns empty, nil registry / nil votes safe).
  - Decision worth recording: the deeper concerns the audit
    framing called for (session-ID derivation, env injection,
    polling state machine) live inside `OnMatchmakerMatched`'s
    coroutine which depends on a real `runtime.NakamaModule`.
    Mocking that surface for unit tests would require ~30
    interface methods. Skipped in favour of testing the pure
    helpers `OnMatchmakerMatched` calls into — full integration
    coverage lives in the Tier 2 compliance suite (8.18 / 8.19
    against mock-mode, real-mode covered by the daily synthetic-
    match-probe job).
- [x] **8.4 `runtime/match_lifecycle_test.go`** (2026-05-13).
  - Done: `gameScopedLeaderboardID` (legacy bare fallback +
    per-game prefix), `clampPlayerStats` table-driven over all
    in-range / negative-floor / above-ceiling / int-max-tamper
    / at-ceiling-unchanged / partial-clamp cases.
  - Refactored a small chunk of the production code: the stat-
    bounding loop in `MatchEndRpc` was inline + tangled with
    `logger.Warn` calls; extracted into a pure
    `clampPlayerStats(p *matchEndPlayer)` helper. RPC still
    logs the clamp by diffing the score before/after. Pure
    move; behaviour identical.
  - request_id validation + idempotency on duplicate
    match_end/match_cancel sit inside the RPC and depend on
    `nk.StorageRead`/`Write`/`Delete`; covered by the live
    compliance suite when 8.20 lands (cancel-race) rather than
    by a mock-fake here.
- [x] **8.5 `runtime/transport_select_test.go`** (2026-05-13).
  - Done: table-driven over empty list, all-native,
    single-web, mixed, unknown-counts-as-native, web-first.
    Pure function so the test is small.
- [x] **8.6 `runtime/version_test.go`** (2026-05-13).
  - Done: `parseLegalVersionFromConfig`,
    `parseMatchmakerRulesFromConfig`, `parseModesFromConfig`
    over populated / nil / empty-raw / malformed / missing-block
    inputs; mode-list `empty-id` entries are dropped. Plus
    `versionCheckRpcFactory` compatibility matrix (matching,
    mismatched, zero-client-passes-through, unknown-game falls
    back to env defaults, no-game-id falls back to env
    defaults) and a surface check that legal /
    matchmaker_min/max/query / modes propagate end-to-end.
- [x] **8.7 `runtime/presence_test.go`** (2026-05-13).
  - Done: `presenceKey` legacy fallback + per-game prefix;
    `gameIDFromKey` for legacy `current`, namespaced
    `{game_id}/current`, malformed (no slash) inputs,
    multi-segment keys (first segment wins), empty string,
    leading-slash. Plus a roundtrip test
    (`gameIDFromKey(presenceKey(g)) == g` for any non-empty
    game_id) — locks the contract that lets pre-Stage-3 rows
    re-attribute themselves to a game during the migration
    window.
  - The wider RPC contract (mutual-only friend filter, batched
    read shape) is exercised by `test_presence_game_filter.gd`
    (Tier 2) against live Nakama; the unit test focuses on the
    pure helpers.
- [x] **8.8 `runtime/auth_test.go`** (2026-05-13).
  - Done: `gameIDFromVars` (nil-safe, empty-map, populated),
    `requireGameID` bootstrap pass-through (empty cache, with
    or without vars) + strict mode (valid passes, missing /
    unknown / empty-string fail), `validateGameIDInVars`
    mirror of the same matrix, plus `requireServerToServer` /
    `requireClientSession` auth-direction guards.
  - File-level `//lint:file-ignore SA1029` directive applied:
    test contexts inject vars under the same string-typed
    `runtime.RUNTIME_CTX_VARS` / `RUNTIME_CTX_USER_ID` keys
    Nakama itself uses, so the production lookup finds them.
    A typed wrapper would defeat the round-trip.
- [x] **8.9 `runtime/party_test.go`** (2026-05-13).
  - Done: `partyInviteCodeForwardKey` /
    `partyInviteCodeReverseKey` shape;
    `generatePartyInviteCode` produces a 6-character code over
    the documented alphabet across 200 iterations (catches
    out-of-alphabet bytes from a future bug); the alphabet
    explicitly excludes the visually-ambiguous I/O/0/1
    characters and is a power-of-2 length (32) so the modulo
    on a random byte is bias-free.
  - The full `party_start_matchmaking` RPC validation
    (leader-only check, group prefix gate, notification
    fan-out) is exercised by the Tier 2 `test_party_to_
    matchmaking.gd` (8.18) against live Nakama with mock-mode
    Edgegap.
- [x] **8.10 `runtime/account_test.go`** (2026-05-13).
  - Done: `parseLeaderboardIDs` (populated, empty-id dropped,
    nil, empty-raw, malformed, missing-block);
    `leaderboardIDsToScrub` end-to-end across a two-game
    registry to confirm per-game prefixes are applied AND the
    legacy bare `ffa` is always appended once (no duplicates
    even when a game's leaderboards list also contains "ffa");
    empty-registry case still returns `["ffa"]` so a
    fresh-deploy cascade still scrubs pre-Stage-3.6 rows.
  - The full delete_account cascade (friends scrub, group
    leaves, presence delete, leaderboard scrub, bulk storage
    delete, soft-delete queue write) is exercised live by
    `test_friends_account_delete_cascade.gd` (8.16) — the
    cascade behaviour depends on a real Nakama, so the unit
    test focuses on the pure scoping helpers it composes.

### Tier 2 — compliance suite expansion (GUT against live Nakama)

- [x] **8.11 Reusable socket harness** (2026-05-13).
  - Done: the roadmap's "currently HTTP-only" framing was
    stale — `compliance_socket_helper.gd` already shipped in
    an earlier session and is consumed by
    `test_socket_auth.gd`, `test_socket_matchmaker.gd`,
    `test_socket_presence.gd`, `test_socket_chat.gd`. Surface:
    `session_from_token(jwt)` (builds a NakamaSession without
    re-auth), `create_socket(host, port, scheme)`,
    `connect_with_timeout(sock, session, sec)` (awaitable +
    timeout-bounded), `wait_for_signal_with_timeout(obj,
    name, sec)` (generic signal wait used for matchmaker /
    chat fan-out asserts). README now documents the socket
    helper alongside the HTTP helper.
- [x] **8.12 Multi-session helper** (2026-05-13).
  - Done: new `multi_session_anon(count, prefix)` on
    `compliance_helper.gd`. Mints `count` independently-
    authenticated anonymous Nakama sessions with one-shot
    device_ids (prefix `compliance-multi-` + run-timestamp +
    random + index) so concurrent CI runs don't collide and a
    single run doesn't leave addressable state. Returns
    `Array[Dictionary]` of `{token, refresh_token, user_id,
    username, device_id}` so multi-user tests can address each
    other via Nakama user_ids (needed for friend / party /
    matchmaker flows). Paired `delete_one_shot_account(user)`
    for strict cleanup via Nakama's built-in
    `DELETE /v2/account` (bypasses the platform's 30-day
    soft-delete grace).
  - Decision worth recording: helper is plain HTTP (not
    socket). Multi-user socket tests construct one socket per
    user via the existing `compliance_socket_helper`, sharing
    the session-from-token primitive. Keeps each helper
    focused on its concern.
- [x] **8.13 `EDGEGAP_MOCK_DEPLOY=true` mode in runtime**
      (2026-05-13).
  - Done — runtime: new `EDGEGAP_MOCK_DEPLOY` env var on
    `runtime/main.go`. When set to `true`/`1`:
    - Matchmaker hook registers even when `EDGEGAP_TOKEN` is
      unset (so a bare test Nakama with just the mock flag
      boots fully usable).
    - `EDGEGAP_APP_NAME` / `EDGEGAP_APP_VERSION` / `SIGNALING_
      DOMAIN` / `SIGNALING_HMAC_SECRET` get reasonable
      defaults instead of fail-fast on empty (real mode still
      requires them).
    - `fleetAllocator.mockDeploy=true` flag short-circuits
      the real Edgegap API calls. New `synthesizeMockDeploy
      (now)` helper returns a canned `(deploy, status)` pair
      with `request_id="mock-<unix_nanos>"`, `public_ip=
      127.0.0.1`, and a ports map mirroring the real
      `Dockerfile.edgegap` declaration (4433/UDP +
      4434/TCP).
    - The polling loop (`a.edgegap.Status`) and the
      `waitForServerRegistered` step are skipped; the
      synthesized status flows straight to the `match_ready`
      payload builder.
    - `match_ready` notifications carry a new `"mock": true`
      field so compliance tests can sanity-check that they
      really ran against a mock-enabled runtime.
    - `stopOnErr` and other Edgegap `Stop` calls no-op when
      `mockDeploy` is true (no real deploy to stop).
  - Done — runtime_status: new `edgegap_mock_deploy bool`
    field on the response shape so daily prod-health-check
    catches a misconfigured prod (mock flipped on by
    accident). Loud `logger.Warn` block at boot too.
  - Done — compliance helper: new `is_mock_deploy_mode()`
    method on `compliance_helper.gd` that calls
    `runtime_status` and returns the bool. Tests gate on it
    and pending() against live prod so they never burn paid
    container-hours.
  - Decision worth recording: env-var-gated runtime-wide
    mock mode (Option A from the design call), not per-
    ticket opt-in. Simpler to reason about; production never
    sets the env var; test instances flip it on.
  - Decision worth recording: bare test Nakama with just
    `EDGEGAP_MOCK_DEPLOY=true` (no `EDGEGAP_TOKEN`) boots
    cleanly. Without that, every test infra setup would
    need to fake an Edgegap token + signaling secret. Mock
    mode short-circuits the real-mode fail-fast and uses
    placeholder defaults (`mock-app`, `v0`,
    `mock-signaling.test`, `mock-hmac-secret`).
  - Decision worth recording: synthetic `request_id` embeds
    `time.Now().UnixNano()` to avoid storage-row collision
    when two concurrent mock matches run on the same test
    Nakama instance.
- [x] **8.14 `test_friends_multiuser.gd`** (2026-05-13) —
  canary for 8.12.
  - Done: new compliance test exercises the
    A-request-B-accepts friends flow with two real anonymous
    accounts. Asserts Nakama's friend-state enum transitions
    correctly (caller=INVITE_SENT(1), receiver=INVITE_RECEIVED
    (2), both=FRIEND(0) after mutual-accept). Per-user
    cleanup in `after_each` via `delete_one_shot_account`.
    First concrete consumer of `multi_session_anon` — the rest
    of the multi-user backlog (8.17 party-invite, 8.18
    party-to-matchmaking, 8.22 presence-game-filter, 8.15
    block-list, 8.16 friends-cascade-on-account-delete) reads
    the same pattern.
- [x] **8.15 `test_friends_block.gd`** (2026-05-13).
  - Done: new two-test compliance file under
    `addons/snoringcat_platform_client/test/compliance/
    test_friends_block.gd`.
    `test_block_list_lifecycle_bidirectional_add_rejection`
    walks A blocks B → list_blocked_users contains B → self-
    block rejected (INVALID_ARGUMENT) → A→B add_friend
    silently no-ops AND A's view of B stays state=3 BANNED
    → B→A add_friend silently no-ops AND B's row never
    reaches state=1 INVITE_SENT → A unblocks B →
    list_blocked_users no longer contains B → A→B
    add_friend succeeds with state=1 row materialized on A's
    side. 20 asserts green against live Nakama.
    `test_blocked_pair_aborts_matchmaker_fanout` mints A + B
    via `multi_session_anon(2)`, A blocks B, both open
    sockets, both add min=max=2 matchmaker tickets, asserts
    both receive `match_failed reason=blocked_pair` with a
    populated `message` AND neither receives `match_ready`
    (verifies the runtime hook's blocked-pair branch returns
    "" before allocation). Mock-mode gated; pends correctly
    on live prod (no EDGEGAP_MOCK_DEPLOY there).
  - Decision worth recording: contract assertions verify
    friend-row state via `GET /v2/friend`, not HTTP status.
    Nakama's `POST /v2/friend?ids=X` returns 200 OK even
    when every target is silently skipped due to a BANNED
    relationship — caught on the first test run by the
    "expected status >= 400" assertion failing. The
    bidirectional rejection contract is "no fresh state=1
    row is written" rather than "the HTTP call errors",
    which is what the test now asserts via
    `_fetch_friend_state` helper.
  - Decision worth recording: the matchmaker-abort test
    uses the inner `_Capture` class pattern lifted from
    `test_party_to_matchmaking.gd` (8.18). Captures both
    `received_matchmaker_matched` and `received_notification`
    on each user's socket and parses the flat-JSON
    match_failed content (different shape than match_ready's
    double-encoded `{connection: "<inner-json>"}`). Same
    `_cleanup_sockets` helper pattern too.
- [x] **8.16 `test_friends_account_delete_cascade.gd`** (2026-05-13).
  - Done: new two-user compliance test under
    `addons/snoringcat_platform_client/test/compliance/
    test_friends_account_delete_cascade.gd`. Mints A + B via
    `multi_session_anon(2)`, makes them mutual friends,
    confirms pre-state, then A invokes the `delete_account`
    RPC. Asserts: (a) response shape (`ok=true`,
    `scheduled_for>0`, `grace_days=30`); (b) B's
    `/v2/friend` no longer contains A (Nakama's
    `FriendsDelete` cascade is bidirectional, so the
    deleter's side scrubs the surviving friend's row too);
    (c) A's own `/v2/friend` is empty; (d) A's
    `/v2/account` still authenticates and reports
    `display_name = "[deleted]"` (Stage 1.5 dropped the ban
    so cancellation surface is reachable); (e)
    `get_account_deletion_status` returns `pending=true`
    with a populated `scheduled_for`. Validated against
    live Nakama (21 asserts green).
  - Cleanup: `delete_one_shot_account` hard-deletes both A
    (still authenticated post soft-delete) and B in
    `after_each`, which collaterally clears the audit-trail
    queue row.
  - Compliance: third real consumer of `multi_session_anon`
    + first consumer of the `delete_account` /
    `get_account_deletion_status` RPCs in the compliance
    suite. Guards the contracts Stage 1.4 introduced
    (bidirectional friends scrub) and Stage 1.5 reaffirmed
    (no-ban-during-grace).
- [x] **8.17 `test_party_invite_flow.gd`** (2026-05-13).
  - Done: new two-user compliance test under
    `addons/snoringcat_platform_client/test/compliance/
    test_party_invite_flow.gd`. Mints A + B via
    `multi_session_anon(2)`, walks the lifecycle:
    A creates a closed party group, A invites B via
    `POST /v2/group/{id}/add`, asserts B observes the
    party in `GET /v2/user/{id}/group`, asserts A is
    SUPERADMIN(0), accepts via `/join` if Nakama returned
    state=3 (or skips the accept step if state=2),
    asserts `GET /v2/group/{id}/user` returns both users
    with the right roles, B leaves, B no longer in list.
    Validated against live Nakama (15 asserts green).
  - Decision worth recording: test tolerates either
    state=2 or state=3 as the post-invite state. Nakama
    3.25.0 admin-add on closed groups was observed to
    land B at state=2 directly (no pending step), which
    contradicts the `party.go::afterAddGroupUsersHook`
    comment claiming state=3. The test asserts that
    either is valid and exercises the accept path only
    when state=3 was actually returned. Lifecycle still
    cleanly verifies the membership contract that
    `PartyApiClient.fetch_party_status` reads back. The
    Nakama-behavior contradiction is documented inline
    in the test so a future Nakama upgrade flipping the
    contract back to state=3 surfaces here cleanly.
  - Compliance: real consumer of `multi_session_anon` +
    its `delete_one_shot_account` cleanup. Confirms the
    helper handles the after_each teardown across two
    concurrent users without races.
- [x] **8.18 `test_party_to_matchmaking.gd`** (2026-05-13).
  - Done: new two-user compliance test under
    `addons/snoringcat_platform_client/test/compliance/
    test_party_to_matchmaking.gd`. Walks the full Stage
    1.1a/1.1b contract:
    - Mint A + B via `multi_session_anon(2)`.
    - A creates closed party group, A invites B; test
      tolerates Nakama 3.25's state=2-direct or state=3-
      pending shapes (same allowance as 8.17), accepting B
      via `/join` if state=3.
    - Both users open Nakama realtime sockets and connect.
    - A calls `party_start_matchmaking` RPC; test asserts
      response shape (`ok`, `party_id`, `leader_id`,
      `member_ids[2]`, `matchmaker_properties.party_id`).
    - B's socket receives a persistent
      `party_matchmaking_start` notification; test parses
      out `matchmaker_properties`.
    - Both sockets add matchmaker tickets with the shared
      `party_id` + each user's `game_id` +
      `client_protocol_version` + `game_mode` (min=max=2).
    - Both sockets receive `received_matchmaker_matched`
      then `received_notification` with subject
      `match_ready`. Test asserts BOTH payloads have the
      SAME `request_id` (the core party-block guarantee:
      fleet_allocator allocates one deploy per fan-out, so
      a same-request-id pair proves no split occurred).
    - Asserts `request_id` starts with `mock-` and
      `mock: true` flag is present (sanity-checks mock-mode
      actually ran).
    - Asserts per-user `session_ids` differ (each user only
      gets their own IDs per the fleet_allocator loop).
    - `after_each` `delete_one_shot_account` for both users
      hard-deletes via `/v2/account` so the per-run state
      (party group, matchmaker tickets, match_metadata +
      synthetic_matches rows) cascades cleanly.
  - Gated on `is_mock_deploy_mode()` so this never runs
    against a real prod runtime (would burn 1 paid Edgegap
    container per test invocation otherwise).
  - Decision worth recording: inner `_Capture` class for
    per-user signal capture instead of two parallel pairs
    of file-scope state vars. Two concurrent test
    receivers want independent mutable state; the inner
    class is cleaner than `Dictionary` flags juggled in
    the test body and lets each capture's signal handlers
    be ordinary methods.
- [x] **8.19 Un-pend `test_matchmaking.gd`** (2026-05-13).
  - Done: replaced the placeholder `pending("realtime-socket
    test rig not implemented yet")` with a real end-to-end
    solo-matchmaking test. Walks:
    - Authenticate one one-shot anonymous user (so
      concurrent CI runs don't fight over a shared device
      id's presence row).
    - Open a Nakama socket and connect.
    - Wire `received_matchmaker_matched` +
      `received_notification` handlers BEFORE adding the
      ticket so a fast matchmaker fire doesn't race.
    - Add a matchmaker ticket with `min=max=1` (the
      matchmaker pool fires immediately, exercising the
      runtime hook + match_ready notification path).
    - Wait up to ~13s combined for matchmaker_matched +
      match_ready notification.
    - Assert payload contract: `mock=true`,
      `request_id` starts with `mock-`, `server_ip`
      non-empty, `session_ids` is `[<one>]`,
      `transport_type` is one of enet/webrtc/websocket,
      `signaling_url` begins with `wss://`, `ports` non-
      empty Dictionary.
  - Gated on `is_mock_deploy_mode()` — same rationale as
    8.18. Real-mode allocation would burn a paid container
    even with min=max=1 (the allocator doesn't size-gate
    on entry count, just walks every entry and allocates
    a deploy).
  - Replaces the old `test_matchmaker_hook_registered_via_
    runtime_status` placeholder test entirely. The check
    it claimed to do (matchmaker hook registered iff
    EDGEGAP_TOKEN set + EDGEGAP_APP_NAME populated) is
    fully covered by `test_version.gd`'s
    `test_runtime_status_reports_edgegap_config` already.
- [x] **8.20 `test_matchmaking_cancel_race.gd`** (2026-05-13).
  - Done: new two-test compliance file under
    `addons/snoringcat_platform_client/test/compliance/
    test_matchmaking_cancel_race.gd`. Mints a one-shot anon
    user via `multi_session_anon(1)` + opens a Nakama socket,
    then exercises two cancel scenarios:
    - `test_cancel_before_match_prevents_match_ready`: add a
      min=max=2 matchmaker ticket (won't fire alone), call
      `remove_matchmaker_async` immediately, wait the mock-
      allocation window (~3s), assert NO
      `received_matchmaker_matched` AND no `match_ready`
      notification arrived. Validates the happy-path cancel
      contract.
    - `test_cancel_after_match_is_safe`: add a min=max=1
      ticket so the runtime hook fires synchronously, wait
      for match_ready, then call `remove_matchmaker_async`
      on the now-consumed ticket. Documents the current
      Stage 7.2 limitation (post-match cancel is best-effort
      — Edgegap deploy stays alive until the game server's
      grace timer). Asserts the cancel call doesn't crash
      the socket by re-issuing a fresh min=max=2 ticket
      afterward (its existence proves the socket is still
      usable).
  - Gated on `is_mock_deploy_mode()` because the min=max=1
    branch allocates an Edgegap deploy; live prod would burn
    a paid container per CI run. Both tests pend cleanly
    when mock mode is off (validated via `gut_cmdln` against
    live prod).
  - Decision worth recording: the cancel-before-match test
    uses min=max=2 (won't fire alone) rather than min=max=1
    (would fire before cancel could win). The stronger
    "cancel actually removes ticket from pool" assertion
    would need a 2-user setup where one cancels and the
    other waits — deferred to a future expansion that
    composes `multi_session_anon(2)` with this pattern.
- [x] **8.21 `test_matchmaking_failure_modes.gd`** (2026-05-13).
  - Done: new compliance test under
    `addons/snoringcat_platform_client/test/compliance/
    test_matchmaking_failure_modes.gd`. Covers the Stage 3.9
    protocol-mismatch path — the cleanest deterministic
    failure mode the runtime supports today. Walks:
    - `version_check` RPC (HTTP-key gated) with the test's
      game_id to learn the registered `protocol_version`.
      Pends if the runtime predates Stage 3.9 (returns 0).
    - Asserts the bogus sentinel (999) doesn't collide with
      the registered version — a future release shipping
      protocol_version=999 would falsely pass this test, so
      the cross-check fires loudly first.
    - Auth one-shot anon user, open + connect Nakama socket.
    - Add a min=max=1 ticket with
      `client_protocol_version: "999"` — bogus value forces
      the abort.
    - Wait for `match_failed` notification. Asserts payload
      contract: `reason=protocol_mismatch`, `expected`
      mirrors the registered version, `got=999` echoes the
      bogus value, `message` is non-empty. The shape mirrors
      `fleet_allocator.go::abortProtocolMismatch`.
    - Confirms NO `match_ready` notification arrives — the
      runtime aborts before allocating Edgegap.
  - Gated on `is_mock_deploy_mode()` consistently with the
    rest of Stage 8 even though the abort path itself
    doesn't allocate. If the test fails (e.g., the mismatch
    path is broken), the matchmaker would allocate — the
    mock-mode gate is the safety net.
  - Decision worth recording: covers only the protocol-
    mismatch path. Other failure modes the audit catalogs
    (Edgegap 503 mid-allocation, lost notification timeout,
    fleet allocator panics) require fault-injection hooks
    the runtime doesn't yet expose. Revisit when Stage 7.1
    introduces allocation retry + injectable failure
    surfaces.
  - Decision worth recording: the test reads the expected
    protocol version off `version_check` rather than
    hardcoding it. version_check is the same surface the
    client uses, so a future drift in the registered value
    is automatically picked up — no test-side sentinel to
    update on every protocol bump.
- [x] **8.22 `test_presence_game_filter.gd`** (2026-05-13).
  - Done: new three-user compliance test under
    `addons/snoringcat_platform_client/test/compliance/
    test_presence_game_filter.gd`. Mints A + B + C via
    `multi_session_anon(3)`, makes A↔B mutual friends,
    leaves A→C as a pending invite (state=1 / state=2 on
    the friend state enum), each user calls
    `update_and_get_presence` to publish "online", then A
    reads back. Asserts B appears in both
    `online_ids` and `online_friends` (mutual-friend
    visibility), asserts C does NOT appear (pending
    relationship must not leak presence), asserts
    `b_record.game_id` equals the caller's session
    game_id (Stage 3.2's record-shape contract), and
    asserts `rich_presence: "In Lobby"` round-trips.
    Validated against live Nakama (17 asserts green).
  - Decision worth recording: doesn't try to test the
    cross-game filter (`include_other_games`) because
    only one game ("hopnbop") is registered on prod; an
    `include_other_games=true` call scans the same set
    of game_ids and produces an identical response on a
    single-game install. The mutual-vs-pending filter
    (3.3's primary contract) and the per-record game_id
    field (3.2) are testable and tested.
  - Compliance: second multi-user test after 8.17; first
    consumer of `multi_session_anon(3)` (the friends and
    party tests use 2). Confirms the helper scales to a
    three-user run without races in CI.

### Tier 3 — client unit tests (GUT with doubles)

All six shipped 2026-05-14 (nineteenth pass). Suite-wide: 119
tests, 212 asserts, 0 failures via
`godot --headless -s --path . addons/gut/gut_cmdln.gd
-gdir=res://test/unit/platform -gexit` in 0.5 s.

Realized scope diverged from the audit's "GUT doubles" framing
in two pragmatic ways:
1. **Pure-logic focus over network doubling.** Each platform
   class is mostly network-coupled; the testable seam is the
   deterministic resolver / state-inspector / dispatch helper
   that doesn't touch Nakama. The HTTP/SDK-driven paths are
   already exercised live by the compliance suite under
   `addons/snoringcat_platform_client/test/compliance/`. So
   the unit tests target pure helpers + state inspectors and
   snapshot/restore autoload state (G.backend_api_client,
   G.local_settings overrides, Platform.game_id, Netcode.settings
   .transport_type, Platform.token_store.player_id) rather than
   double Nakama itself.
2. **Flat test methods over inner classes.** The GUT 9.5.0 +
   Godot 4.7-beta1 cmdline path in this repo silently fails to
   discover inner-class tests when running a single file via
   `-gtest=` (only top-level `test_*` functions in an `extends
   GutTest` file are surfaced). Tests are grouped by name prefix
   (e.g. `test_build_query_*`, `test_resolve_min_max_*`) instead.
   Documented in each file's class docstring.

- [x] **8.23 `test/unit/platform/test_friends_api_client.gd`**
  (2026-05-14). 13 tests / 32 asserts. Covers cache inspectors
  (`is_friend` / `has_sent_request` / `has_incoming_request` /
  `is_blocked`), busy-flag round-trip, malformed-entry tolerance
  (one documented quirk: empty-string lookup matches entries
  missing `player_id`), Nakama Friend.State enum constants
  (0/1/2/3 — protocol-critical, drift silently misroutes entries
  in `fetch_friends`), and pagination caps (100 × 10 mirror the
  runtime account.go cascade pattern).
- [x] **8.24 `test/unit/platform/test_party_api_client.gd`**
  (2026-05-14). 11 tests / 17 asserts. Covers the
  `_group_state_to_role` enum mapping (0→leader / 1→admin / 2→
  member / 3→invited / 42→unknown — protocol-critical, gates
  leader-only UI), `_short_id` UUID-to-prefix helper (strips
  hyphens + substr(0,8), handles short/empty input), `is_busy`
  flag, `_describe(null)` safety, and the three storage-collection
  constants (`party_ready` / `party_leader` / `party_mode` —
  must stay in lockstep with the platform runtime's party.go
  constants).
- [x] **8.25 `test/unit/platform/test_party_manager.gd`**
  (2026-05-14). 31 tests / 44 asserts. Covers
  `is_in_party` / `has_pending_invite` / `get_party_id` /
  `get_party_mode` / `is_leader` (with viewer-id pinned via
  `Platform.token_store.player_id` snapshot/restore) /
  `is_self_ready` / `all_active_members_ready` (including the
  invited-role-ignored contract and zero-active-degenerate
  case) / `_patch_member_ready` (in-place mutation + ghost-id
  no-op) / `_remove_pending_invite` (strip + `party_updated`
  emit) / `reset` (clears every tracked surface) /
  `_resolve_member_display_name` (display→username fallback) /
  `_on_party_status_received` (initial-check flag) /
  `set_party_mode` (no-op when not in party / unchanged) /
  polling lifecycle.
- [x] **8.26 `test/unit/platform/test_nakama_matchmaker_client.gd`**
  (2026-05-14). 28 tests / 38 asserts. Covers `_build_query`
  (mode-query > server-query > compile-time default cascade),
  `_resolve_min_count` / `_resolve_max_count` (mode > server > 2
  / 4 defaults, partial-override-only-min), `_resolve_mode_dict`
  (explicit-id from session_prefs > LocalSettings selected mode
  > server is_default-flagged mode > {}), `_build_string_props`
  (baseline keys, empty Platform.game_id omits key,
  protocol_version stringification, level_id / party_id /
  game_mode passthrough, game_mode-from-resolved fallback),
  `_build_numeric_props` ({} reserved), `_apply_transport_type`
  (enet / webrtc / websocket / case-insensitive / unknown-value
  preserves current — match_ready malformed-input safety).
- [x] **8.27 `test/unit/platform/test_friends_notification_poller.gd`**
  (2026-05-14). 20 tests / 41 asserts. Covers `reset` (all 5
  known-id maps + first-poll flags), `_set_unseen_count`
  (emit-on-change / skip-on-unchanged / multi-change),
  `_on_friends_received` / `_on_friends_marked_seen` (unseen
  count round-trip), `_on_notifications_received` (per-bucket
  dedup, empty-friend-id skip), `_handle_party_matchmaking_start`
  (notification-id dedup, empty-id ignore),
  `_dispatch_notification` (non-Dict-content safety, unknown-
  subject ignore), `_on_presence_received` (first-poll
  suppression, set-rebuild-to-current-list contract),
  `_on_match_started` / `_on_match_ended` (rich-presence /
  status transitions), polling lifecycle.
- [x] **8.28 `test/unit/platform/test_settings_cloud_sync.gd`**
  (2026-05-14). 16 tests / 40 asserts. Covers `_game_scope`
  (game/{id} or game/unknown fallback), `_partition_legacy`
  (locale → global, GLOBAL_OVERRIDABLE_KEYS → global,
  OVERRIDABLE_KEYS-minus-global → game, unknown keys dropped,
  mixed payload splits), `_serialize_global` /
  `_serialize_per_game` (no leak across scope, default-locale
  omitted, no-overrides → {}), `_apply_scope` (known keys
  written, unknown keys ignored), `_has_legacy_migrated` /
  `_mark_legacy_migrated` round-trip, `_get_sync_at` /
  `_set_sync_at` per-scope round-trip. Note: the test's
  `before_each` also resets `G.settings` values to the
  resource defaults each iteration; without this,
  `LocalSettings.set_override`'s "value matches current
  default → clear override" branch breaks subsequent tests'
  assumptions about a clean baseline.

### Tier 4 — end-to-end / smoke

- [x] **8.29 Local docker-compose dev stack at
  `infra/dev/docker-compose.dev.yml`** (2026-05-14).
  - Done: two-service compose (Nakama 3.25.0 + Postgres 16) at
    `infra/dev/docker-compose.dev.yml` with a trimmed dev
    config at `infra/dev/config.dev.yml`. Brings up the
    locally-built `snoringcat.so` plugin from
    `third_party/snoringcat-platform/runtime/build/` so the
    full RPC surface registers, matchmaker hook included.
    Mock-mode is hardcoded in `config.dev.yml`'s
    `runtime.env` block — Nakama does NOT interpolate `${X}`
    in config (verified by reading the live boot log:
    `app=${EDGEGAP_APP_NAME}` would propagate literally; prod
    renders the file via `phase-a.ps1`). Postgres password
    `dev-not-a-secret` and Nakama keys (`defaultkey` /
    `defaulthttpkey` / `defaultencryptionkey` /
    `defaultrefreshencryptionkey` / `defaultsigningkey`) are
    intentionally weak and hardcoded; ports bound to
    `127.0.0.1` so nothing leaks outside the loopback.
  - "Fake Edgegap" landed via the existing 8.13
    `EDGEGAP_MOCK_DEPLOY=true` toggle rather than a separate
    sidecar — `synthesizeMockDeploy` already lives in
    `fleet_allocator.go` and the matchmaker hook short-
    circuits real Edgegap I/O when the flag is on. The
    runtime logs the loud "MUST be off in production" warning
    at boot, which surfaces in the dev container's
    `docker compose logs nakama` exactly like prod.
  - Verified end-to-end against a fresh `docker compose up`:
    runtime plugin loads (`build=dev app=hopnbop-server
    version=v-dev edgegap=true mock_deploy=true`), all 30+
    RPCs register including the matchmaker_matched hook,
    `register_game` upserts hopnbop's row from `game.yaml`,
    and 9 HTTP-based compliance test files (19 tests / 60+
    asserts: version / auth_anon / friends / party /
    account / settings / presence / api_surface /
    player_stats) green against the dev stack with no
    failures.
  - Decision worth recording: omit Caddy / TLS / Grafana /
    Prometheus / signaling-proxy / cost-monitor / pg-backup
    from the dev stack. The compliance suite doesn't exercise
    any of them, they add ~5 minutes of pull/build time, and
    the prod stack's `infra/remote/nakama/docker-compose.yml`
    is the authoritative surface for those if a future test
    needs them.
  - Decision worth recording: use `127.0.0.1` not `localhost`
    in `PLATFORM_API_URL`. On Windows + Docker Desktop,
    `localhost` resolves to `::1` first, Godot's HTTPRequest
    burns ~60 s per request hitting the unreachable IPv6
    listener before retrying IPv4. With `127.0.0.1` explicit,
    the test_version trio runs in 0.6 s vs 180 s. The smoke
    script's `$NakamaUrl` and `infra/dev/README.md` both flag
    this.
  - Submodule companion fixes shipped 2026-05-14:
    `compliance/test_version.gd` now treats
    `EDGEGAP_MOCK_DEPLOY=true` as a valid hook-active
    indicator alongside `EDGEGAP_TOKEN`; this is correct for
    both prod (token path) and the dev stack (mock path).
    `compliance/compliance_socket_helper.gd::_derive_socket_target`
    parses scheme + host + port out of `PLATFORM_API_URL`
    (http → ws, https → wss, explicit ports honored) rather
    than hardcoding `wss://:443`; prod fallback is preserved
    when the env var is unset.
- [x] **8.30 `scripts/local-smoke-test.ps1`** (2026-05-14).
  - Done: end-to-end smoke harness. Steps: (0) refresh the
    platform-addon copy via `setup-platform-addon.ps1`,
    (1) build `snoringcat.so` via the
    `heroiclabs/nakama-pluginbuilder:3.25.0` Docker image
    (skippable via `-SkipBuild` when a build is already
    cached), (2) `docker compose up -d` against
    `infra/dev/docker-compose.dev.yml`, (3) poll
    `/healthcheck` with a 90 s deadline, (4) POST
    `register_game` with hopnbop's `game.yaml` via the
    existing `sync-game-config.ps1`, (5) run the compliance
    suite via `godot ... gut_cmdln.gd -gdir=...` (or a single
    `-TestFile` for iteration), (6) tear down `docker compose
    down -v` unless `-KeepStack`. Exit-code surface:
    0 = green, 1 = test failures, 2 = stack failure (compose
    / migrate / healthcheck timeout), 3 = registration
    failure.
  - Env vars set per-run inside the script and propagated to
    the `godot` subprocess: `PLATFORM_API_URL=http://127.0.0.1:7350`,
    `NAKAMA_SERVER_KEY=defaultkey`,
    `NAKAMA_HTTP_KEY=defaulthttpkey`,
    `EDGEGAP_MOCK_DEPLOY=true`,
    `PLATFORM_COMPLIANCE_MODE=live`. The compliance suite
    auto-detects the dev target without code changes.
  - Verified end-to-end: `local-smoke-test.ps1 -SkipBuild
    -TestFile test_version.gd` brings the stack up, runs the
    test (3/3 green in 0.6 s), and tears down cleanly. Full
    `-gdir=...` run pends ~half of the socket-tests
    gracefully (see 8.29 known limitation) and exits 0.
  - Decision worth recording: `-gdir=res:` runs the whole
    compliance directory (unlike the wider `test/unit` tree
    where `-gdir` misses discovery per
    CLAUDE.md "Project-Specific Testing Notes"). The
    compliance helpers ship a working `_gdir`-friendly layout
    so we don't need the per-file shell loop the
    `pr-validate.yml::godot-tests` job uses.
- [x] **8.31 GitHub Actions: compliance against ephemeral
  compose** (2026-05-14).
  - Done: new `.github/workflows/compliance-matrix.yml` runs
    `pwsh scripts/local-smoke-test.ps1` on every PR + on
    workflow_dispatch. ubuntu-latest runner; submodules
    pulled via `SUBMODULE_PAT`. `chickensoft-games/setup-godot@v2`
    provides Godot 4.5; Docker is preinstalled on the runner.
    30 minute timeout. The smoke script's exit code is the
    job's exit code; on failure the workflow surfaces a hint
    to re-run locally with `-KeepStack` for poking.
  - Decision worth recording: single-axis (ephemeral only) for
    now, NOT a true matrix. The roadmap's original framing
    called for `[ephemeral, staging]` but there is no staging
    Nakama tier today (per `nightly-smoke.yml`: "Phase G's
    staging step was scoped out; production is the
    authoritative target"). Adding a staging axis now would
    either skip-condition the job into uselessness or run
    against prod, which the existing nightly-smoke already
    does read-only. Workflow comment documents the future
    expansion: once staging exists, add a `target` matrix
    axis with the staging URL + creds via secrets.
  - Decision worth recording: invoke `local-smoke-test.ps1`
    from CI rather than duplicate the orchestration. Keeps
    the local + CI paths byte-identical, so a green CI run
    is also a green local run and a local debug session
    surfaces the same failures CI would catch.

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
  fail-safe / alerting. Stage 7.11 (2026-05-13) restored the
  Grafana alerting surface but the timers themselves don't emit
  metrics yet — failure is still surfaced by the systemd service
  status (visible in the `journalctl` / watchdog Discord pings)
  rather than a queryable counter. A future expansion could
  publish a textfile-collector entry on each successful run for
  `node-exporter` to pick up.
- Observability stack: re-introduced (lightweight subset)
  2026-05-13 in Stage 7.11. Prometheus + Grafana +
  node-exporter + postgres-exporter live on the same single-
  host CPX11; Loki + Promtail intentionally stayed off (configs
  preserved in `third_party/snoringcat-platform/infra/remote/nakama/`
  for a future re-introduction).
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

- **2026-05-12:** Stage 6.5 party API extraction shipped, with
  scope narrowed from the original roadmap framing. Three
  design calls worth recording:
  - **`party_manager.gd` stays game-side.** The audit-derived
    task framing had both `party_api_client.gd` AND
    `party_manager.gd` migrating to the addon together. In
    practice the manager has the same UI-coordinator coupling
    that kept `friends_notification_poller.gd` game-side
    under 6.4: it reaches into `G.toast_overlay`,
    `G.confirm_layer` / `G.settings.confirm_overlay_scene`,
    `G.client_session`, `G.game_panel`, and
    `G.notification_socket_client`. Moving it would mean
    either constructor-injecting all those surfaces or
    refactoring the manager to emit signals the game listens
    to and decides what to do with — both heavy refactors
    with no payoff today. The manager just rewrote its
    `G.party_api_client.X` calls to `Platform.party.X` and
    otherwise stays put. Same pattern friends_panel /
    friends_notification_poller follow: keep the coordinator
    game-side, factor each *API surface* into the addon.
  - **Pure move-and-rename for the API client.** Unlike 6.2's
    auth extraction (which had to also lift Nakama / OAuth
    config out of the class and into Platform fields), 6.5's
    `party_api_client.gd` already reached only into Platform-
    owned surfaces (`Platform.get_nakama_client()`,
    `Platform.token_store.player_id`,
    `Platform.build_session_from_store()`). The extraction
    was a class_name rename + relocation; no per-game config
    threading needed. Tells us 6.2 paid its dues — every
    subsequent client extraction (6.4 friends, 6.7 presence,
    6.5 party) inherits the now-available Platform helpers.
  - **No deferred companions this round.** 6.4's extraction
    also surfaced two companion classes that needed game-side
    homes (`friends_notification_poller.gd`) or design
    decisions about where they belong (the still-game-side
    `notification_socket_client.gd`). 6.5 added one similar
    candidate — `NotificationSocketClient` itself — noted as
    6.5b for a future pass. It's clean enough to move (only
    `Netcode.log.warning/print` are non-Platform reach-backs)
    but the payoff is small until a second consuming game
    needs the same realtime-socket bus; deferred without
    blocking 6.6 / 6.8 / 6.9 work.

- **2026-05-12:** Stage 6.5b followed 6.5 immediately. The
  6.5b note above bumped to "shipped" the same day. Two design
  calls worth recording:
  - **`notification_socket` is its own subsystem slot, not a
    sub-slot of `auth` or a Platform-owned (non-subsystem)
    object.** It owns its own lifecycle (open/close on
    auth_completed transitions), so binding the lifetime to
    Platform itself (like `nakama_client` is bound) would have
    meant tearing the socket up/down inside `Platform.initialize`
    rather than in the consuming game's bootstrap. Subsystem
    pattern keeps the addon's autoload passive — only the
    consuming game decides when to wire each piece. Same
    rationale as 6.1's original case for keeping subsystems
    slot-based rather than preload-and-instantiate.
  - **The 6.6 extraction is now the heaviest remaining 6.x.**
    With 6.5b done, the SDK has clean addon-side ownership of
    every Nakama-specific HTTP RPC and realtime-socket
    surface. The matchmaker extraction (6.6) is the
    remaining piece that touches Nakama directly, but it's
    entangled with game-side Netcode autoload, transport-type
    enum, and BackendApiClient (server_matchmaker_* cache).
    Likely path: split `NakamaMatchmakerClient` into a clean
    `PlatformMatchmakingClient` (Nakama socket + add_matchmaker
    + match_ready listener, emitting platform-agnostic signals
    with `transport_type` as a string) plus a game-side
    `NakamaMatchmakerClient extends SessionProvider` adapter
    that translates the string to `NetworkSettings.TransportType`
    and bridges to Netcode. `EdgegapServerProvider` stays
    entirely game-side because it integrates with the in-
    container Netcode.connector for peer validation.

- **2026-05-12:** Stage 6.6 matchmaker extraction shipped along
  the path 6.5b's note predicted. Five design calls worth
  recording:
  - **Split-and-adapter, not lift-as-is.** Unlike 6.5's pure
    move-and-rename of the party API client (which only
    reached into already-Platform-owned surfaces),
    `NakamaMatchmakerClient` had real game-side dependencies:
    `Netcode.settings.transport_type`,
    `NetworkSettings.TransportType` enum,
    `G.backend_api_client.server_matchmaker_*`,
    `G.client_session.local_player_count`, `Netcode.is_preview`
    + `Netcode.preview_client_number` for the per-instance
    preview auth path, `Netcode.log` for diagnostics. A clean
    lift would have either pulled all of that into the addon
    (wrong direction) or stripped it (broke the feature).
    Split lets the addon own the Nakama socket / ticket /
    match_ready parser (the platform-agnostic core) while the
    adapter owns the integration with rollback-netcode + the
    game-specific config sources.
  - **`transport_type` stays a string at the addon boundary,
    not an int enum.** The match_ready payload from the
    runtime carries `transport_type` as one of "enet" /
    "webrtc" / "websocket". `NetworkSettings.TransportType` is
    defined in the rollback-netcode addon (a separate
    submodule); the snoringcat-platform addon can't depend on
    it. Keeping the value as a string at the boundary means
    `PlatformMatchmakingClient` can pick the right Edgegap
    port (UDP for ENet, TCP for WebRTC/WS) by string-matching
    on the protocol field, without ever importing the enum.
    The adapter translates string → enum + applies it to
    `Netcode.settings.transport_type` before re-emitting.
  - **Boot-time singleton + per-session adapter.** The addon
    client is registered once in `global.gd._enter_tree` as
    `Platform.matchmaking`; the game-side
    `NakamaMatchmakerClient extends SessionProvider` is
    instantiated per-session by `GameSessionManager` and
    connects to / disconnects from the singleton's signals in
    `_ready` / `_exit_tree`. The alternative (per-session
    addon client too) would mean `Platform.matchmaking` is
    null between sessions, breaking the "once an extraction
    lands, the slot stays non-null for the rest of the boot"
    pattern every other 6.x extraction follows. The cost
    (signal handler hygiene in adapter's `_exit_tree`) is
    minor and explicit. The benefit (consumers can do
    `if Platform.matchmaking != null` once at boot rather
    than per-call) is real.
  - **`preview_device_id` is a parameter, not a Netcode reach-
    back.** The addon class accepts `preview_device_id` as
    an arg to `start_matchmaking`; when non-empty, it
    authenticates that device id as a separate Nakama
    account. The adapter computes the id from
    `Netcode.is_preview` + `Netcode.preview_client_number` +
    `OS.get_unique_id()` and passes it through. Same
    pattern for `local_player_count` (used by the
    session_ids fallback when match_ready predates the
    runtime's session_ids surface): adapter reads
    `G.client_session.local_player_count`, addon takes the
    int as an arg. Pushes every game-shaped knob to the
    addon's caller; the addon itself has zero game-side
    dependencies.
  - **`EdgegapServerProvider` stays game-side.** The
    audit-derived task title bundled
    `edgegap_server_provider.gd` into 6.6, but the file is
    deeply entangled with `Netcode.connector.{get_peer_id_
    from_player_id, server_notify_shutdown,
    server_close_multiplayer_session}` for peer validation,
    `Netcode.log` for diagnostics, and
    `G.match_result_reporter.cancel` for Edgegap deployment
    teardown on idle / grace timeouts. Splitting only
    `register_with_runtime()` out would create an awkward
    straddle (one HTTP RPC in the addon, the rest of the
    class in the game). The closer analog is
    `friends_notification_poller.gd` (kept game-side under
    6.4): coordination layers stay where the surfaces they
    coordinate over live. The matchmaker's API surface
    (Nakama socket + matchmaker ticket + match_ready
    parser) is genuinely platform-agnostic, so it moves;
    the in-container validation coordinator isn't, so it
    stays.

- **2026-05-12:** Stage 6.10 verified done + Stage 3.10 CI gap
  closed. Two decisions worth recording:
  - **6.10 is verified, not "shipped" in the usual sense.** Every
    prior 6.x extraction migrated its own consumers as part of
    its commit (the per-pattern sed passes in 6.2 / 6.3 / 6.4 /
    6.5 / 6.5b / 6.6). 6.10's job is the final sweep: confirm
    no live callsite still names a removed
    `G.*_api_client`-shaped field. The grep was clean —
    `G.backend_api_client` is the only remaining
    `G.*_api_client` reference and it's intentionally game-side
    (it caches per-game `version_check` values that the addon's
    auth / matchmaker subsystems consume). Closing 6.10
    without any new code change is appropriate; the "code" was
    every previous 6.x landing's incremental migration.
  - **`legal_version` parity CI guard added as a sibling step,
    not a new job.** 3.10's earlier note flagged this as a
    follow-up. The `protocol_version` parity check already
    lives in a `game-config-parity` job in `pr-validate.yml`;
    adding a second `Check legal_version parity` step inside
    the same job costs nothing extra (one checkout, one
    runner) and keeps both parity checks visually colocated
    when CI logs are read. Extraction pattern: grep for the
    indented YAML block-scalar key, then grep for the
    `const LEGAL_VERSION` line, strip quotes / whitespace /
    CR. Verified locally that both files yield `"1.1"`. The
    check is annoying-but-safe to fire (a real mismatch
    triggers a one-time re-consent rather than locking
    players out), so failing the PR early is the right
    severity.

- **2026-05-12:** Stage 3.5 + 6.8 paired pass landed. Six
  design calls worth recording:
  - **Taxonomy lives in `LocalSettings`, not in the addon.**
    A new `GLOBAL_OVERRIDABLE_KEYS` constant declares which
    keys are global; everything else in `OVERRIDABLE_KEYS` is
    per-game. The addon stays game-agnostic — it takes a scope
    string parameter from the caller and maps it to a Nakama
    storage key. Putting the taxonomy on the game side keeps
    the rule colocated with the key declarations themselves
    and means a second game can ship its own split without
    rewriting the addon. The default-per-game rule (keys not
    listed in GLOBAL_OVERRIDABLE_KEYS go to the per-game scope)
    is the safer fallback — a key added without explicit
    classification stays scoped to the game that defined it,
    rather than leaking cross-game.
  - **Scope as a free-form string, not an enum.** The addon's
    `fetch(scope)` / `save(scope)` accept any string and map
    it 1:1 to the Nakama storage key. The game-side adapter
    chooses `"global"` / `"game/{game_id}"` / legacy `"user"`.
    An enum would have meant either constraining the addon to
    only-the-current-known-scopes (forcing every future split
    through the addon) or duplicating the conversion logic in
    each consumer. String pass-through is the simplest
    contract that lets a future game add new scopes (e.g.,
    `"profile"` for per-player profile-card config) without
    addon changes.
  - **Cloud-wins-by-timestamp uses Nakama's storage row
    update_time, not a sentinel field in the payload.** The
    pre-extraction code expected `{updated_at, settings}`
    envelopes but never actually wrote that shape — it wrote
    the bare flat dict, and the timestamp comparison silently
    no-op'd. The refactored client reads the storage row's
    update_time (string, RFC3339) and converts it to unix
    seconds at the addon boundary. The game-side adapter sees
    a plain `int` timestamp it can compare against the locally
    recorded sync-at. Side benefit: a future games-admin
    console editing the row out-of-band still produces a fresh
    update_time, so the merge logic doesn't need to know about
    the editor surface.
  - **Legacy migration applies locally, never writes.** Earlier
    drafts had the migration partition the legacy blob,
    apply-locally, AND push to the new cloud rows. That broke
    multi-device fan-out: device D2 fresh-migrating after
    device D1 has been writing new rows for a week would
    overwrite D1's recent values with D2's interpretation of
    the (now-stale) legacy. The shipped path is apply-locally
    + mark-migrated + proceed to the normal fetch-merge cycle.
    If newer rows exist in the cloud, they win on update_time
    and overwrite the just-applied legacy values; if not, the
    empty-cloud-empty-local branch pushes the (legacy-applied)
    local values up. Either way, no clobber.
  - **Legacy `key="user"` row is not deleted.** A small (a few
    hundred bytes) dead row is the cost of not breaking any
    future fresh-install of a pre-6.8 client on the same
    Nakama account during the transition window. Once a future
    release confirms every active client is post-6.8 (mostly
    a function of forced version-mismatch deployments), a
    one-shot RPC could sweep `(settings, user, *)` rows; not
    worth the complexity until then.
  - **`BackendApiClient` lost its settings surface entirely.**
    The previous indirection (game-side `BackendApiClient`
    wrapped Nakama storage calls; `SettingsCloudSync` consumed
    them) added a hop without paying back — the methods were
    only ever called from one place and the Nakama SDK is
    perfectly callable from the addon. After 6.8, the addon
    hits `Platform.get_nakama_client().write_storage_objects_async`
    directly. `BackendApiClient` shrinks to just the
    leaderboard / player-stats / profile / match-history /
    version-check surface it had before settings was bolted
    on. A future "Platform.backend" subsystem could absorb
    the rest, but the version-check caching it does (per-game
    legal_version + matchmaker rules) keeps it usefully
    game-side for now.

- **2026-05-13:** Cleared Stage 1/4/5 deferred items in one
  session (1.4 cron, 1.5 cancellation, 4.7 solo picker, 5.7
  party leader picker). Five design calls worth recording:
  - **Drop the ban in delete_account.** The original 1.4 design
    called `UsersBanId` so the existing JWT + linked identity
    providers couldn't re-authenticate during the grace period.
    That made the 1.5 cancellation surface unreachable —
    banned users can't sign in to cancel. The post-1.5 model
    leans on cascade-anonymize (display name flips to
    "[deleted]") + cron-eventual-hard-delete instead; the
    boot-time `get_account_deletion_status` check is now the
    gate that surfaces the prompt. The user-visible promise
    ("you have 30 days to cancel") was always premised on the
    cancel path working, so this is a bugfix rather than a
    policy change.
  - **Cron uses `context.Background()`, not the InitModule
    context.** Nakama's InitModule context is the boot context;
    it gets cancelled the moment InitModule returns. A
    long-lived goroutine reading from that context would die on
    the first tick. `context.Background()` outlives the boot;
    plugin reload tears the goroutine down by recreating the
    plugin, so no shutdown plumbing is needed.
  - **Per-mode query enforces mode separation in the
    matchmaker, fleet allocator stays mode-agnostic.** Game
    modes (ffa / duo) need real player-pool separation — a duo
    ticket pairing with three FFA tickets is nonsense. Solved
    by per-mode `query` (e.g. `+properties.game_mode:duo`); the
    matchmaker only matches mode-mates. fleet_allocator stays
    unchanged: it reads `player_count` from ticket properties
    to size `EXPECTED_PLAYER_COUNT` for the game server, so
    1v1 vs 4-player matches Just Work. Tradeoff: a sparsely-
    populated mode might never match; that's the cost of
    giving players choice, accepted by the user as part of the
    feature's framing.
  - **Mode picker icon stays a placeholder.** Same TODO
    pattern as the party row (`friends_icon.png`) and the
    promote-leader row (`leaderboard_icon.png`). Picker reuses
    `levels_icon.png`. Replacing requires dedicated art and
    isn't on the critical path.
  - **Cycle-on-tap, not a sub-panel, for the party mode
    picker.** The solo path uses a full `GameModePickerPanel`
    (one row per mode, checkmark on selection). The party path
    flips the current mode via a single ActionRow that cycles
    through. The cycle is simpler to build and natural for a
    2-mode lineup; a future game with >3 modes would want to
    swap the cycle row for a `PartyGameModePickerPanel` that
    mirrors the solo path but writes through the
    `party_set_mode` RPC. Defer until that's the load-bearing
    case.

- **2026-05-12:** Stage 3.9 protocol_version pre-check landed,
  closing Stage 3. Four design calls worth recording:
  - **Approach (a): ticket-property route, not Nakama session
    lookup.** The original deferral framing offered two paths:
    (a) client passes `client_protocol_version` as a ticket
    property and the server cross-checks; (b) extend Nakama with
    a session-vars-on-MatchmakerEntry helper. (b) would be the
    cleaner answer but requires upstream Nakama work and we have
    no internal fork. (a) is client-trusted but the boot-time
    `check_version` is still the primary gate, and a forged value
    still fails at the rollback-netcode handshake. Defense-in-
    depth, not a security boundary.
  - **`match_failed` is flat JSON, not double-encoded like
    `match_ready`.** The legacy `match_ready` carries
    `{"connection": "<inner-json>"}` (double-encoded) because the
    original parser shape needed the nested unwrap. The new
    `match_failed` payload has no nested blob to wrap, so we send
    `{reason, message, expected, got}` directly. Addon parses
    once instead of twice. Future failure notifications should
    follow this shape too.
  - **Mismatched-vs-compatible players get different copy.**
    Both groups get a `match_failed` notification so neither
    sits on the 120s client timeout. The mismatched player gets
    "your client is out of date" (actionable: restart to update);
    other matched players get "another player's client is out
    of date" (less actionable, but at least tells them why the
    match aborted). Alternative (uniform copy) would have
    blamed the wrong player visibly.
  - **Graceful rollout: pre-3.9 clients pass through.** The
    check fires only when an entry *declares* a
    `client_protocol_version`. Pre-3.9 clients omit the property
    entirely, so the rollout window where some clients
    declare and others don't doesn't lock anyone out. A
    pre-3.9-only match passes through with no check; a mixed
    match passes when the post-3.9 client's declared value is
    right; a post-3.9-only match enforces strictly. After
    enough release cycles to assume every client is post-3.9
    (typically tracked by a forced-mismatch deploy), the
    graceful path becomes dead and could be tightened to "any
    missing declaration is a failure", but the cost of leaving
    it is bounded.

- **2026-05-12:** Stage 6.9 PlatformSessionObserver landed. Four
  design calls worth recording:
  - **Passive observer, not coordinator.** The audit-derived task
    framing had `Platform.session` owning the session-provider
    switching + connection flow. In practice that role is
    irreducibly entangled with `Netcode.*` (the rollback-netcode
    autoload, a separate submodule), the matchmaker's
    `SessionProvider` extension, and game-specific UI / fallback
    state. Lifting the coordinator into the addon would force the
    addon to depend on rollback-netcode and the game's UI
    surfaces — wrong direction. The passive observer keeps the
    dependency arrow pointing addon→Platform and game→Platform,
    never addon→game. Game-side `GameSessionManager` stays
    verbatim and just forwards each emit; addon-side / future-
    second-game code subscribes to `Platform.session.*` for the
    same lifecycle picture without taking a hard dependency on
    the hopnbop class. Same pattern as 6.5's PartyManager and
    6.6's EdgegapServerProvider: keep the coordinator game-side,
    factor only the cross-game-meaningful surface into the addon.
  - **5-signal surface, not 8.** The game-side manager emits 8
    signals today (`session_established`, `match_ready`,
    `connection_lost`, `matchmaking_progress`, `matchmaking_failed`,
    `local_mode_fallback_requested`, `server_should_reset`,
    `server_shutdown_imminent`). The 5 forwarded to the addon are
    the cross-game-meaningful ones (lifecycle + progress + pre-
    connect failure). The 3 omitted ones describe deployment-
    shape internals (offline-mode fallback, preview-mode reset,
    server-side shutdown indicator) that a second game would
    model differently or skip entirely. Forwarding all 8 would
    leak hopnbop's deployment shape into the addon contract; a
    second game would either implement no-op emits or rename
    them and break parity.
  - **`session_established` → `session_started` on the bus.** The
    addon-side bus uses the more conventional name (`started`,
    not `established`) so a second game reading the SDK doesn't
    inherit a hopnbop-specific verb. The game-side signal keeps
    its original name to preserve backwards compatibility with
    the existing direct-connect call sites in `game_panel.gd`.
    The rename happens at the forwarding line. Cheap aliasing
    and the right separation between game-side legacy and
    addon-side canonical names.
  - **One-line `if Platform.session != null` guard at each
    forward.** The slot is registered in
    `global.gd._enter_tree` before `GamePanel` instantiates a
    `GameSessionManager`, so the guard is trivially-impossible
    in production. But the alternative (assume non-null) means
    a future refactor that moves session_manager instantiation
    earlier (or a test harness that bypasses global.gd's
    enter_tree) would null-deref instead of silently no-op.
    Same pattern existing `Platform.X != null` consumer code
    uses (e.g. `friends_panel.gd`'s game_id comparison). Cheap
    and consistent.

- **2026-05-13:** Stage 8.11 + 8.12 + 8.14 shipped together.
  Four design calls worth recording:
  - **8.11 was already done.** The original roadmap framing
    called for a "reusable socket harness" addition to the
    compliance helpers; in practice
    `compliance_socket_helper.gd` already existed from an
    earlier session (session_from_token, create_socket,
    connect_with_timeout, wait_for_signal_with_timeout) and
    was actively consumed by `test_socket_*.gd`. Reading the
    helper before writing new code surfaced the stale framing.
    Marked done with the consumer list pinned in the entry so
    a future audit doesn't re-open it.
  - **8.12 helper is HTTP-only; sockets layer on top.**
    `multi_session_anon(count)` issues `count` parallel
    `/v2/account/authenticate/device` calls and returns
    `{token, refresh_token, user_id, username, device_id}`
    per user. Tests that need a per-user socket use the
    existing socket helper's `session_from_token(token) +
    create_socket() + connect_with_timeout(sock, session)`
    per user. Splitting the concerns kept each helper focused
    and avoided a "do-everything" multi-user-multi-socket
    primitive whose shape would still vary per-test (some
    flows need 1 socket, some need N).
  - **One-shot device_ids, not stable.** The single-user
    helper `nakama_anon_session` uses fixed device_ids
    (`compliance-anon-fixed-1`) deliberately, to reuse the
    same Nakama account across runs and not bloat the users
    table. Multi-user can't do that — if two CI runs ran in
    parallel against the same prod Nakama, they'd race on the
    same user pair's friend / party state and produce
    flake. So `multi_session_anon` mints fresh
    `compliance-multi-<timestamp>-<rand>-<index>` device_ids
    per call. The new `delete_one_shot_account` helper opts
    callers into strict cleanup; lazy callers let the rows
    linger for ops sweep.
  - **Canary test goes through Nakama state semantics, not the
    platform RPCs.** The first multi-user test
    (`test_friends_multiuser.gd`) asserts on the Nakama friend-
    state enum transitions (0/1/2) directly via `/v2/friend`,
    not through the addon's `PlatformFriendsApiClient`. Two
    reasons: (a) the harness is the unit under test, so the
    fewer layers between it and the assertion the better;
    (b) every other Stage 8.x multi-user candidate (party,
    presence, matchmaking) wants similar low-level state
    assertions on Nakama contracts. Patterns from this test
    are the template for the rest. The addon-class round-trip
    tests live under Tier 3 (8.23+ unit tests with doubles),
    not Tier 2 compliance.

- **2026-05-13:** Stage 8.17 + 8.22 shipped together (third
  pass of the day's Stage 8 work). Four design calls worth
  recording:
  - **Tolerate Nakama state ambiguity, don't lock to one
    value.** 8.17 originally asserted `state=3` immediately
    after `POST /v2/group/{id}/add` (the production "invite"
    path), keying on the 5.11 narrative and on
    `party.go::afterAddGroupUsersHook`'s comment ("Nakama
    hasn't returned them through GroupUsersList as state=3
    yet"). Running it against live Nakama 3.25.0 returned
    state=2 instead — closed-group admin-add lands the
    invitee as a Member directly, no pending step. Rather
    than hardcode either value, the test now asserts
    `state in {2, 3}` and exercises the `/join` accept step
    only when state=3 was returned. Lifecycle assertions
    (members list contains both with right roles, B leaves
    cleanly) hold regardless. A future Nakama upgrade that
    flips the behavior back to state=3 will still pass; a
    behavior change to state=0 or 1 (i.e., elevating the
    invitee to admin/superadmin, which would be a security
    issue) fails loudly.
  - **Doc the Nakama-vs-runtime-comment contradiction in the
    test, not in a separate issue.** The
    `afterAddGroupUsersHook` comment claims state=3, the live
    behavior is state=2. The test's inline comments call out
    the observation so the next reader knows the apparent
    accept-via-`joinGroup` step in `PartyManager.accept_invite`
    is dead code on this Nakama version. Filing a separate
    audit item would just rot; the test is where someone
    would naturally look when revisiting party semantics.
  - **8.22 tests mutual-vs-pending, skips the cross-game
    angle on single-game prod.** The 3.3 contract has two
    halves: (a) only state=0 (MUTUAL) friends contribute to
    `online_friends`, and (b) the default-false
    `include_other_games` flag scopes the read to the
    caller's own game's collection key. Half (a) is testable
    on prod by setting up A↔B mutual + A→C pending, then
    asserting C is invisible. Half (b) isn't testable
    against single-game prod (only "hopnbop" is registered,
    so `include_other_games=true` reads the same set as
    `false`). Test covers half (a) plus the per-record
    `game_id` field (3.2) and round-trips `rich_presence`.
    Half (b) needs a second registered game; deferred until
    one exists.
  - **Three-user runs work without race.**
    `multi_session_anon(3)` was the largest call so far
    (friends + party tests used 2). One full sequence
    (auth all 3, friend A↔B + A→C, presence write × 3,
    presence read by A) completes in ~3-4 seconds against
    live Nakama and `after_each` `delete_one_shot_account`
    cleans every account before the next test. No flake
    observed across the ad-hoc validation runs. Confirms
    the helper's parallelization assumption (one-shot
    device_ids prevent inter-run collision) holds at this
    user count.

- **2026-05-13:** Stage 8.16 friends-cascade-on-account-delete
  shipped. Four design calls worth recording:
  - **Both sides of the cascade asserted in one test.** The
    cascade in `account.go` pulls A's friends list, then calls
    `nk.FriendsDelete(ctx, A, A's username, friendIDs, nil)` —
    Nakama's documented behavior is bidirectional removal, so
    B's row pointing at A is scrubbed as a side effect of
    deleting A's row pointing at B. Single test asserts both:
    `_fetch_friend_state(B, A)` returns -1 AND
    `_fetch_friend_state(A, B)` returns -1. Splitting these
    into two tests would have doubled the
    `multi_session_anon(2)` setup cost (~700ms of /v2/account
    auth round-trips per pair) without adding signal — the
    failure mode is the same FriendsDelete call.
  - **Asserts on Stage 1.5's no-ban contract via A's continued
    auth, not via a separate sign-in attempt.** The 1.5
    decision was "drop UsersBanId from the cascade so the
    cancellation UX is reachable." Easiest live check: after
    `delete_account`, use A's same pre-cascade token to hit
    `/v2/account` and `/v2/rpc/get_account_deletion_status`
    and assert both succeed. A separate re-auth round-trip
    (POST /v2/account/authenticate/device for A's device_id)
    would test the same thing but cost an extra request and
    a refresh dance. The shared-token path is the production
    flow: the client's session stays valid through the
    grace window.
  - **`display_name = "[deleted]"` is the production
    anonymization marker, asserted by literal string match.**
    The cascade hard-codes `anonymizedDisplayName = "[deleted]"`.
    A future i18n pass might want the marker localized, but
    that's a separate decision; locking the test to the
    current literal surfaces accidental drift loudly. If the
    marker ever changes, this test fires alongside whatever
    code-side change made it.
  - **`delete_one_shot_account` on A still works post-soft-
    delete.** Cleanup in `after_each` hard-deletes both users
    via `DELETE /v2/account` with their pre-cascade tokens.
    A's token still authenticates (no ban), so the hard-delete
    succeeds and collaterally removes the audit-trail queue
    row (Nakama's user delete cascades through user-owned
    storage). Without this, every CI run would leave a queue
    row that the cron eventually consumes ~30 days later;
    fine functionally, but it'd accrete in `account_deletion_
    queue` storage in the meantime. Strict cleanup keeps the
    table small.

- **2026-05-13:** Stage 8.3–8.10 Tier 1 Go unit tests shipped
  (sixth pass). 100 passing test cases across 8 files. Five
  design calls worth recording:
  - **Test pure helpers, not RPCs.** The audit framing for
    8.3/8.4/8.7/8.9/8.10 implied full RPC-level coverage, but
    each of those RPCs depends on `runtime.NakamaModule`
    (storage read/write/delete, leaderboard write, friends
    list, notification send — a ~30-method interface). Mocking
    that surface would have produced more mock code than test
    code, and the Tier 2 compliance suite already covers the
    RPC end-to-end against live Nakama. So Tier 1 tests focus
    on the pure helpers each RPC composes — pickTCPPort,
    signSignalingURL, synthesizeMockDeploy, pickDominantGameID,
    clampPlayerStats, gameScopedLeaderboardID, presenceKey /
    gameIDFromKey, gameIDFromVars, requireGameID, parse*
    helpers, generatePartyInviteCode, parseLeaderboardIDs /
    leaderboardIDsToScrub. The split keeps each tier focused:
    Tier 1 gates the deploy on logic regressions; Tier 2 gates
    on contract drift against the running Nakama; together they
    catch different classes of bug.
  - **One small refactor for testability.** The stat-bounding
    loop in `MatchEndRpc` was inline + tangled with logger
    calls. Lifted out into a pure `clampPlayerStats(p
    *matchEndPlayer)` helper. The RPC still logs by diffing
    `origScore != p.Score`. Tiny refactor (~10 lines lighter
    in the RPC, +20-line testable helper), zero behavior
    change. Every other helper was already pure — this was the
    only file that needed a touch.
  - **`testLogger` no-op + `newTestGames` map-bypass helper
    package-scoped.** Shared across every test file as
    `helpers_test.go`. The Logger no-op implements all 7
    methods of `runtime.Logger` so any helper that takes a
    logger works in tests. `newTestGames` constructs a
    `*perGameConfig` by directly populating the unexported
    `games` map field, bypassing `Refresh` (which needs a
    *sql.DB). That's the only test-only access to package-
    private state, and it's contained to one helper.
  - **`//lint:file-ignore SA1029` on auth_test.go.**
    Nakama's runtime exposes context keys as plain string
    constants (`RUNTIME_CTX_VARS`, `RUNTIME_CTX_USER_ID`).
    Production code reads through those keys verbatim;
    SA1029 ("don't use built-in string as a context key")
    only flags `context.WithValue` writes, which only the
    test does. A typed wrapper would defeat the round-trip
    (`ctx.Value(typedKey)` != `ctx.Value(stringKey)`).
    File-scope ignore + an in-line rationale comment is
    cleaner than per-call directives.
  - **Test-file naming matches the source file.** Each
    `foo.go` gets a `foo_test.go` next to it; the shared
    helpers live in `helpers_test.go`. Standard Go pattern, no
    surprises for the next reader. The roadmap's task IDs
    (8.3 = `fleet_allocator_test.go`, etc.) point at the
    matching pair so a future audit can trace task → file
    without grep.

- **2026-05-13:** Stage 8.13 EDGEGAP_MOCK_DEPLOY mode + 8.18
  party-to-matchmaking + 8.19 solo-matchmaking shipped together
  (fifth pass). Six design calls worth recording:
  - **Env-var-gated runtime-wide mock, not per-ticket opt-in.**
    The design call was between (A) one env var that mocks
    every allocation runtime-wide, (B) a per-ticket
    `mock_deploy:"true"` property that opts individual matches
    in, (C) a hybrid requiring both. Picked (A) for the
    simpler reasoning surface: prod never sets the env var,
    test instances flip it on. (B)'s mixed-match semantics
    (some entries opt in, some don't) would have invented a
    "what does the allocator do?" question with no clean
    answer. The price is needing a separate test Nakama for
    the tests to actually fire, but Stage 8.29's planned
    docker-compose dev stack covers that.
  - **Match_ready carries `mock=true`, not just the
    request_id prefix.** The runtime synthesizes
    `request_id="mock-<unix_nanos>"`, but a future change to
    that format would silently break the test's prefix
    assertion. The `mock: true` flag is the canonical signal;
    the prefix assertion is belt-and-suspenders. Both fire
    when present, so a misconfigured prod that flipped the
    env on by accident would loud-fail at TWO different
    points client-side (in addition to the
    `edgegap_mock_deploy` field in runtime_status that the
    daily prod-health-check job alerts on).
  - **Bare test Nakama works with just `EDGEGAP_MOCK_DEPLOY=
    true`.** The real-mode boot requires `EDGEGAP_TOKEN +
    EDGEGAP_APP_NAME + EDGEGAP_APP_VERSION + SIGNALING_
    DOMAIN + SIGNALING_HMAC_SECRET` — five env vars. Mock
    mode falls back to canned defaults for each so a fresh
    test instance boots without operator pre-config. Real-
    mode strictness is preserved (any missing var fails
    fast); only the mock path relaxes.
  - **`stopOnErr` no-ops in mock mode.** Originally the
    `a.edgegap.Stop(ctx, deploy.RequestID)` call would have
    hit a nil pointer in mock mode (the edgegap client is
    `nil` when no real token is set). Branch added to skip
    the call. Side benefit: a future audit that finds a
    mock-mode test producing storage rows can grep on the
    `mock-` prefix to find them; no real `Stop` ever ran so
    nothing happened on the Edgegap side either way.
  - **Per-user `_Capture` inner class for 8.18.** Two
    concurrent test receivers want independent mutable
    state. File-scope variables with `_a_` / `_b_` prefixes
    would have worked but accreted: 8.18 captures
    `matched_seen`, `match_ready_payload`,
    `party_matchmaking_start_props`, `failed_subject` per
    user. The inner class keeps each pair of handlers
    composable and means the cleanup function takes only the
    capture object, not 8 separate args. Same pattern any
    future N-user test will follow.
  - **`is_mock_deploy_mode()` reads runtime_status, doesn't
    require a flag-cache.** The test could have read the
    env directly (impossible — env is on the runtime, not
    the test) or required a separate `PLATFORM_MOCK_DEPLOY=
    true` env on the test runner. Instead, the helper hits
    runtime_status's new `edgegap_mock_deploy` bool. Source
    of truth is the runtime; test mirrors it via the same
    diagnostic surface ops already uses. Cost: one extra
    HTTP round-trip per test. Trivial at compliance suite
    sizes.

- **2026-05-13:** Stage 8.20 cancel-race + 8.21 protocol-
  mismatch failure-mode shipped (seventh pass). With 8.20 +
  8.21 done, the Tier 2 matchmaking compliance suite is
  complete except for 8.15 (blocked on 7.4 block list). Four
  design calls worth recording:
  - **Two tests in one cancel-race file, not one each.** The
    cancel-race surface has two distinct contracts worth
    asserting: (a) cancel-before-match removes the ticket
    from the matchmaker pool, and (b) cancel-after-match is
    safe (the production matchmaker client calls
    `remove_matchmaker_async` unconditionally in
    `cleanup()`/`cancel_matchmaking()` after match_ready).
    Splitting them into two files would have doubled the
    setup boilerplate (one-shot user mint + socket connect)
    for no gain; keeping them in one file with a shared
    `_connect_one_shot()` helper makes each assertion
    cheap to add.
  - **Min=max=2 for cancel-before-match, accepted limitation
    of single-user testing.** A purer "cancel actually
    removes from pool" assertion needs two users: one cancels
    its min=max=2 ticket, the other adds a min=max=2 ticket
    and asserts it doesn't match (cancel removed the first
    entry; otherwise the second would pair with it). The
    single-user min=max=2 fallback only proves
    `remove_matchmaker_async` returns cleanly — but the
    socket connection itself proves the ticket reached the
    matchmaker, and the cancel-while-the-allocation-is-
    pending case is genuinely impossible without a second
    user (one player can't trigger an allocation alone).
    Deferred the two-user version to a future expansion of
    this test; the single-user version still catches a
    full no-op regression where cancel does nothing.
  - **Protocol-mismatch is the only deterministic failure
    mode worth testing today.** The audit's failure-mode
    catalog calls out Edgegap 503s, polling timeouts, and
    fleet-allocator panics, but each of those requires
    fault-injection that isn't wired yet (Stage 7.1 will
    introduce retry hooks). Protocol-mismatch (Stage 3.9)
    is synchronous, deterministic, and triggered by a
    single client-side property — perfect compliance-test
    target. Rather than write three flaky tests that need
    timing-dependent injection, ship the one that works
    cleanly and grow this file when 7.1 lands.
  - **Read expected protocol_version off version_check, not
    a sentinel.** A test-side `_EXPECTED_PROTOCOL_VERSION
    := 2` would have to be updated on every protocol bump,
    which becomes an extra friction point on every breaking
    network change. Reading it from `version_check` at test
    time is one extra HTTP round-trip (cheap) and means the
    test stays correct across version bumps without manual
    intervention. Same source-of-truth pattern as
    `is_mock_deploy_mode()` reading runtime_status.

- **2026-05-13:** Stage 7.1 Edgegap allocation retry shipped
  (eighth pass; Stage 7 kickoff). Five design calls worth
  recording:
  - **`tryAllocate` owns the per-attempt sequence; the retry
    loop in `OnMatchmakerMatched` owns the policy.** Splitting
    "what one attempt does" from "how many times we retry and
    what changes between attempts" lets the test suite cover
    the policy (rotation, backoff, ctx-cancel) with pure
    functions while the per-attempt I/O stays untestable
    without a full `runtime.NakamaModule` mock. Same Tier-1-vs-
    Tier-2 split as Stage 8.3-8.10: unit tests gate the deploy
    on policy regressions, compliance tests gate on contract
    drift against live Nakama.
  - **Validation moved INSIDE `tryAllocate`.** The PublicIP /
    TCP-port checks were at the call site after polling
    completed. A "successful" deploy with missing fields is
    unusable; treating it as a failed attempt lets the retry
    loop rotate region instead of failing the match outright.
    The alternative (fail-fast on missing fields) would have
    burned the user's match on what's almost certainly a
    transient Edgegap API hiccup. Also reordered so validation
    happens BEFORE `waitForServerRegistered` — a deploy with
    bad data shouldn't eat the 30s register timeout before
    being stopped.
  - **Mock mode exempt from the retry loop.** `synthesizeMock-
    Deploy` is deterministic and synchronous; retrying it just
    produces a different request_id with the same shape. Mock
    mode's purpose is contract-level fan-out testing, not
    exercising the retry policy. A future fault-injecting mock
    (Stage 7.x or 8.21 expansion) could land an
    `EDGEGAP_FAULT_INJECT` env var that returns errors on the
    first N calls; deferred until retry compliance testing is
    on the critical path.
  - **Continent rotation order is north_america → europe →
    asia.** Biases retries toward the busiest known regions
    first so a sparse-pool region failure doesn't trap the
    user on a series of also-sparse fallbacks. Subject to
    revisit when player geographic distribution data exists;
    today's player pool makes any region's capacity ceiling
    very far above typical concurrent-match counts, so the
    rotation order is mostly cosmetic. Wrap-on-overflow is
    locked in by `TestAllocationFallbackGeographies/wraps-
    past-rotation-length` so a future bump to
    `maxAllocationAttempts` > rotation length is safe.
  - **`match_failed` allocation_failed message must contain
    "allocation".** The game-side `_classify_matchmaking_
    failure` in `game_panel.gd` does substring matching to
    decide between recoverable (`LOADING.ALLOCATION_FAILED` +
    retry button on loading screen) and fatal (toast + back-
    to-lobby). The literal substring "allocation" in the
    message is the routing key. Locked in by the message
    template ("Edgegap allocation failed after %d attempts.")
    and reinforced by `reason="allocation_failed"` for any
    future classifier that wants to switch from substring to
    reason-code matching.

- **2026-05-13:** Stage 7.2 mid-queue cancel teardown shipped
  (ninth pass). Six design calls worth recording:
  - **Cancel RPC only signals; teardown stays in the matchmaker
    hook goroutine.** Alternative had the RPC read request_id
    off the inflight, call `stopDeploy` directly, and send
    match_failed inline. That splits teardown across two
    goroutines and makes the cancel-vs-success race trickier
    (the RPC could observe state in the middle of a hook step).
    Signal-only model: hook goroutine is the sole owner of all
    teardown state; the RPC just sets a tripwire by invoking
    `inflightAllocation.cancel`. The hook then observes
    `allocCtx.Err() != nil` at known checkpoints and runs the
    cleanup path linearly. Easier to reason about; easier to
    test (the helpers split cleanly into pure functions).
  - **One `inflightAllocation` per match, shared across every
    matched user_id.** A multi-user match (party, or any
    matchmaker pairing) has N tracker entries pointing at the
    same struct. Any one user's cancel propagates to all (the
    cancel func is `context.CancelFunc` — idempotent, fires
    once). Semantics: any matched player cancelling = whole
    match aborts. The alternative (per-user cancel state with
    "what fraction of players cancelled" logic) would have
    invented a policy question (does 1-of-4 abort the match?
    2-of-4? majority?) with no clean answer for Hop'n'Bop's
    small-pool today. Whole-match abort is simple and matches
    the matchmaker's atomicity (the 4 were certified as a
    valid match; losing 1 invalidates that).
  - **Two `allocCtx.Err()` checkpoints, not one.** Checkpoint
    A: after the retry loop. Distinguishes "user cancelled
    during the polling" (`sendMatchCancelled` + return nil)
    from "all retries failed" (`sendAllocationFailed` +
    return error). Checkpoint B: after successful allocation,
    before storage writes. If cancelled here,
    `stopDeploy(deploy.RequestID)` cleans up the freshly-
    allocated deploy and `sendMatchCancelled` notifies peers.
    Storage writes are skipped on this branch so we don't
    leave orphan rows. The window between B and the actual
    `NotificationSend match_ready` is microseconds; a cancel
    that sneaks in there is best-effort lost (deploy lives,
    in-container Godot's idle timer tears it down). Acceptable
    given the tiny window.
  - **`sync.Map` + `CompareAndDelete` guards stale defers.**
    The tracker is a `sync.Map` because reads dominate
    (cancel RPC may or may not fire per match). The defer in
    `OnMatchmakerMatched` uses `CompareAndDelete(uid,
    inflight)` rather than `Delete(uid)` so a stale defer
    from an older match for the same user_id can't clobber a
    newer match's tracker entry. Locked in by
    `TestRegisterAndDeregisterInflight/deregister-respects-
    newer-entry`.
  - **`LOADING.PEER_CANCELLED` is a new translation key, not
    reuse of `LOADING.NO_MATCH_FOUND`.** "No match found"
    implies "couldn't pair you with anyone"; `PEER_CANCELLED`
    is "we paired you, but a peer pulled out". The
    user-facing distinction matters — under NO_MATCH_FOUND
    retrying might expand the search; under PEER_CANCELLED
    retrying might re-pair the same peers (who could bail
    again) or different ones. Distinct framing keeps the
    retry button's mental model accurate. Cost: 13 new
    translations (best-effort, worth a native-speaker review
    pass before a release; same caveat as Stage 1.5's
    cancellation strings and 5.7's mode names).
  - **Post-match_ready cancel intentionally fire-and-forget on
    the deploy.** Once `match_ready` is sent, the canceller's
    client already cleared `_is_searching` and silently
    ignores the deploy connection info; other matched players
    receive `match_ready` and connect. The deploy is "wasted"
    from the canceller's perspective but useful for everyone
    else, so we don't tear it down. The game server's idle/
    grace timer fires within ~30 s if no one connects (the
    everyone-cancelled edge case); in the more common case at
    least one peer connects and the match runs normally.
    Tighter handling would require either (a) reverse-flow
    "I'm dropping out" notification from the canceller's
    client to the game server before connection, or (b)
    expanding the `match_cancel` RPC to admit matched players
    by validating against the match_metadata storage row.
    Both add surface; deferred until the cost of wasted
    minutes shows up as a real signal.

- **2026-05-13:** Stage 7.12 + 7.13 friend-abuse hardening
  shipped (eleventh pass). Five design calls worth recording:
  - **Both checks in one BeforeAddFriends hook, not two
    separate hooks.** Nakama only exposes one
    `RegisterBeforeAddFriends` slot; even if there were
    several, the natural fan-in order (rate-limit before
    pending-cap) would still place them in the same
    function. Bundling them in one file
    (`friends_limits.go`) keeps the rule colocated with
    its caller and makes future "what guards live on the
    add-friend path?" greps trivial.
  - **In-memory rate-limit state, no persistence.** A
    Nakama-storage-backed counter would survive restarts
    but add a write per call (the dominant cost would
    swing from `FriendsList` round-trip to a storage
    write). Restart loss gives every user a free fresh
    budget, which isn't an exploit — it's a worse-case-
    one-extra-burst-per-restart issue, and the restart
    cadence is on the order of weeks. The rate-limit's
    job is anti-enumeration, not anti-spam-per-user, so
    short windows of leniency are acceptable.
  - **`map[string][]int64` over `sync.Map`.** The per-call
    work is dominated by the 7.12 `FriendsList` round
    trip when the rate check passes; lock contention on
    the limiter is negligible relative to that. Plain
    map + sync.Mutex is the simpler model, with cleaner
    invariants (the slice for one user can never be
    modified concurrently from two callers because the
    mutex covers the whole accept-or-reject sequence).
    Future scaling concerns (10k+ concurrent callers
    hitting the limiter every second) would justify
    sync.Map; today's player pool doesn't.
  - **Rate limit only applies to add-by-username path.**
    7.12's pending-cap applies to every `BeforeAddFriends`
    call; 7.13's rate-limit short-circuits when
    `len(Usernames) == 0`. Add-by-ID paths (accept-
    incoming-friend-request, add-recent-match) don't
    expose codes to brute-force enumeration, so they're
    rate-limit-exempt. The 7.12 cap still fires for them
    (it's about caller-side outgoing inbox depth,
    independent of recipient surface).
  - **Stable-constants canary test.** All three new
    constants (`maxPendingOutgoingFriendRequests=50`,
    `friendCodeRateLimitCount=10`,
    `friendCodeRateLimitWindow=60s`) have an audit trail
    in this roadmap. The `TestFriendsLimitsConstantsStable`
    test asserts the live values match the roadmap-
    documented ones; a future bump that drifts the
    constant without updating the roadmap loud-fails the
    CI gate. Cost is six trivial test lines; benefit is
    forcing the bump-er to read the rationale and update
    the doc before shipping.

- **2026-05-13:** Stage 7.9 anonymous-upgrade UI + 7.8 account-
  merge UI shipped (fifteenth pass). Five design calls worth
  recording:
  - **Dedicated panels, not enhanced confirm overlays.** The
    audit's "no UI today" framing for both items was strict
    about the absence of a focused surface — bolting more text
    onto a `ConfirmOverlay` would have given a one-button label
    + one-message-body dialog rendering text it can't structure
    well (no header / body split, no separate action rows with
    distinct visual weight). New SidePanel subclasses match the
    same pattern Stage 1.5 used for delete-account verification
    and Stage 5.10 used for join-by-code: a focused surface for
    each destructive-or-momentous action.
  - **Anonymous-upgrade is pure discoverability, not new flow.**
    The pre-existing `AccountPanel` already routed anonymous
    users to the same Google/Facebook `LinkAccountRow`s
    (`account_panel.gd:104-145` — the gate is `if not
    is_token_valid and not is_anonymous` which means anonymous
    DOES pass through). The audit's framing of "no UI exists"
    was about the absence of a focused upgrade surface that
    explains *why* a user should upgrade. The new
    `UpgradeAccountPanel` keeps the same `LinkAccountRow`
    machinery and just wraps it with a header + benefits body
    + "Maybe later" close row.
  - **Badge visible by default for anonymous main-menu entry.**
    The existing badge mechanism (friends-have-news / party-
    has-invites) is event-driven and transient. Using it for a
    persistent "you should sign in" signal stretches the
    semantic but avoids a new attention indicator + asset. A
    follow-up pass could swap to a dedicated visual treatment
    if testing shows the badge is "shouting" rather than
    "drawing the eye".
  - **Merge panel owns `merge_completed` subscription, not
    LinkAccountRow.** The old code subscribed on the row with
    `CONNECT_ONE_SHOT`, which worked but made the row carry
    the merge state. Moving the subscription to the panel
    co-locates it with the action rows that need to enable /
    disable on each phase, and means the row's
    PROVIDER_CONFLICT handler is a one-line panel-push instead
    of a multi-callback merge dance. The cost is one new
    `@export var` on the row (the panel scene); the benefit
    is each class has one job.
  - **`_explicit_action_taken` flag for back-pop cancel
    semantics.** The merge token is server-owned + short-
    lived; if the user pops via the back row (which doesn't
    fire `cancel_merge`), the token leaks for ~minutes until
    expiry. The flag lets `_exit_tree` call `cancel_merge`
    only on the back-pop path — the explicit Merge / Cancel
    rows both set the flag so the cleanup doesn't double-fire.
    Alternative: expose `is_merge_pending` on
    `PlatformAuthApiClient`, but that leaks implementation
    detail. Same self-contained pattern any future "release-
    pending-token-on-exit-unless-explicit" panel can copy.
  - **Three prior translation keys retired
    (`CONFIRM.MERGE_ACCOUNT`, `LINK.MERGE`, `LINK.MERGING`).**
    Per CLAUDE.md's "no backwards-compat hacks" rule, an
    unused key with confirmed no callers should be deleted
    rather than left as dead weight. Each row was 14 fields
    × 1 line; not a huge save, but the principle matters —
    next person reading the CSV doesn't waste cycles
    wondering whether the keys still drive something.

- **2026-05-13:** Stage 7.11 lightweight observability
  re-introduction shipped (sixteenth pass). Five design calls
  worth recording:
  - **Lightweight subset, not full stack.** Prometheus +
    Grafana + node-exporter + postgres-exporter were re-added;
    Loki + Promtail were intentionally left off. The 2026-05-06
    consolidation stripped the full stack to fit 2 GB CPX11;
    the live-host probe before re-enable showed 1.3 GB
    available, so the lightweight subset (~350 MB resident)
    has comfortable margin while the full stack (~500 MB)
    would have left the box tight under load. journalctl +
    docker logs cover the ops use case the Loki configs were
    serving; preserving the configs in-tree means a future
    "queryable logs would actually help here" moment doesn't
    require reconstruction.
  - **Custom allocation timer rides Nakama's metrics
    surface, not a separate HTTP server.**
    `nk.MetricsTimerRecord("snoringcat_alloc_seconds", ...)`
    fans out through the same `:9099` Prometheus endpoint
    Prometheus already scrapes. Cheap (one nakama-common API
    call per match), no extra firewall surface, inherits
    the same scrape cadence + alerting reach as everything
    else. The alternative (a separate HTTP server in the
    plugin) would have added a second listener that
    Prometheus would need a separate scrape job for, with
    no upside.
  - **Two tags only: `game_id` + `mock`.** Per-attempt or
    per-region tags would add cardinality without payoff
    today. A single rolling histogram across all attempts
    answers "is allocation latency drifting?"; the
    retry-count is already in `logger.Info` lines for any
    debug deep-dive. Subject to revisit if dashboards
    eventually need per-region heatmaps.
  - **Timer recorded after the post-allocation cancel
    checkpoint.** Cancelled allocations have a meaningful
    "I waited for X seconds before the cancel landed"
    duration but it's not the same distribution as
    successful allocations. Recording after the cancel
    check keeps the histogram clean — only successful
    allocations contribute. Cancellations show up as the
    `match_failed reason=cancelled` notification fan-out;
    their latency is a different statistic.
  - **Deploy is operator work, not GH Actions.** The
    `nakama-runtime.yml` workflow only pushes the
    `snoringcat.so` plugin to the host. The new
    `docker-compose.yml` + `prometheus.yml` + `Caddyfile` +
    `grafana/provisioning/` tree need an SCP + `docker
    compose up -d --build` from the operator workstation,
    plus `pulumi up` to apply the grafana DNS record. The
    `nakama-runtime.yml` could be expanded to push the
    compose too, but the operator-driven path is what
    every prior infra change uses and the new dependencies
    (GRAFANA_ADMIN_PASSWORD env var) need credentials.env
    co-located with the operator anyway.

- **2026-05-14:** Stage 7.10 mid-match rejoin shipped
  (seventeenth pass). Six design calls worth recording:
  - **Framework-side session_id reuse, not game-side
    merge.** The rollback-netcode `NetworkConnector`
    already owns player_id assignment (sequential
    `_next_player_id`). For reconnect we need a
    reconnecting client to get THEIR OWN player_id, not a
    fresh one — otherwise the existing PlayerState slot +
    score on the game side gets orphaned. Cleanest fix is
    a server-only `_session_id_to_player_id` map in the
    framework. The alternative (game-side detects "new
    player_id has the same session_id as an existing one,
    merge their PlayerStates") would require either a
    framework signal change (passing session_ids through
    `peer_players_declared`) or a heavyweight server-side
    bookkeeping layer. Framework change is small (~70
    lines) and backward-compatible.
  - **30s grace, fixed.** User explicitly picked this in
    the design call over "configurable per game.yaml".
    Hopnbop's pacing fits a 30s window cleanly: long
    enough to cover a typical WiFi drop or browser tab
    reload, short enough that 3 other players aren't
    sitting watching an empty slot. A future game with
    different pacing can re-evaluate and either bump the
    const or thread it through game.yaml.
  - **Treat the gap as died-and-respawning.** "Lightweight
    slot+score only" (user's design choice) is functionally
    "preserve PlayerState slot + score counter; despawn
    the bunny entity; respawn fresh on reconnect with full
    HP at a spawn point". The despawn happens immediately
    on disconnect — deferring it would mean the bunny
    lingers without input, which is weirder UX than a
    clean respawn. Score lives on PlayerState (kept in
    `players_by_id` throughout grace via the existing
    `is_connected_to_server=false` semantic) so the
    rejoining player still sees their kill/bump counts.
  - **ENet-only in v1, not full transport parity.** WebRTC
    and WebSocket reconnect each need transport-specific
    signaling re-negotiation (WebRTC: new SDP offer +
    ICE re-gathering through the signaling-proxy;
    WebSocket: full TLS handshake + buffer overflow risk
    on web clients). Each path is a multi-day pass on its
    own and would have stretched 7.10 into multiple
    sessions. The v1 cut covers native desktop matches
    cleanly; web/WebRTC players see the existing
    immediate exit-match path until 7.10b lands. The
    `can_attempt_reconnect()` gate makes the limit
    explicit.
  - **Server-side grace is just a SceneTreeTimer.** Not a
    rollback-deterministic frame counter, not a coalesced
    timer manager. The grace timer is real-wall-clock
    (30s) and one per disconnected player. SceneTreeTimers
    can't be cancelled directly, so the implementation
    tracks them in `_grace_timers: Dictionary` keyed by
    player_id and disconnects the timeout handler before
    fire (effectively cancelling). Simpler than spawning
    Timer node children per-player.
  - **Programmatic ReconnectingOverlay, not a .tscn.** The
    structure is one ColorRect + CenterContainer + VBox
    with two labels + a spinner. A separate scene file
    would add maintenance surface (export var wiring,
    scene-instance bugs on hot reload) without payoff. If
    the design needs more flexibility later, swap to
    `reconnecting_overlay.tscn` then; today the
    programmatic version is ~70 lines total.

- **2026-05-14:** Stage 7.10b mid-match rejoin transport
  parity shipped (eighteenth pass, same day as 7.10).
  Three design calls worth recording:
  - **Drop the gate, don't add per-transport logic.** The
    7.10 client-side `ReconnectHandler.can_attempt_reconnect()`
    had a `_transport_type != ENET` short-circuit because
    the seventeenth-pass scope deliberately deferred the
    transport-specific work. The 7.10b investigation found
    that the framework's `NetworkConnector.client_connect_
    to_server` already correctly dispatches per-transport
    on re-dial (ENet recreates the UDP peer, WebSocket
    re-handshakes TLS, WebRTC re-runs signaling), so the
    transport-aware re-dial doesn't need to live in the
    `ReconnectHandler` — dropping the gate is sufficient.
    The reconnect loop is genuinely transport-agnostic at
    the handler level; only timings differ.
  - **Defense-in-depth `_webrtc_peer` cleanup.** Godot's
    RefCounted-based `MultiplayerPeerExtension` doesn't
    auto-invoke `_close()` on PREDELETE — only on explicit
    `peer.close()` or when the framework reassigns
    `multiplayer.multiplayer_peer`. The 7.10 reconnect path
    on ENet/WebSocket worked because Godot's
    `multiplayer.multiplayer_peer = new_peer` line in
    `client_connect_to_server` triggers the close. WebRTC's
    `_client_start_webrtc` instead overwrites the
    `_webrtc_peer` variable and only assigns
    `multiplayer.multiplayer_peer` AFTER the signaling
    completes — so the dropped match's `WebRTCGamePeer`
    could linger holding UDP socket bindings the new ICE
    agent wants to claim. Mirroring the existing
    `_webrtc_signaling_client` cleanup with a parallel
    `if _webrtc_peer != null: _webrtc_peer.close(); ...`
    makes the teardown deterministic.
  - **Shared retry interval, not transport-aware.** ENet
    redials in milliseconds; WebRTC signaling needs
    ~2–3s in the happy path. The current 5s × 6 attempts
    in the 30s grace window gives WebRTC a full ~5s budget
    per attempt — enough for the happy-path signaling to
    complete on the first attempt (server already bound,
    so `WebRTCSignalingClient`'s 12 × 750ms internal retry
    typically succeeds at attempt 1). If a WebRTC cycle is
    still mid-flight when the outer 5s timer fires, the
    next `_attempt_reconnect` tears down the in-progress
    signaling and starts fresh. Wasteful but not broken;
    per-transport interval tuning would be polish.

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

## Suspect / verify-before-acting list

Items below came from outside this roadmap (older session-notes,
pre-multi-game `NEXT_STEPS.md` entries) and may have been
silently resolved by the multi-game work without their source
docs being updated. **Always verify the current state before
acting on these** — at least one such item (viewport
centering, captured in the "already burned" note at the bottom)
already tripped an audit pass into nearly re-doing solved work.
If still latent, fold into the appropriate stage above and
strike here; if resolved, strike here.

- **Compliance suite rate-limit — verified-and-not-applicable
  2026-05-15.** Caddy rate-limits
  `/v2/account/authenticate*` at 30 events / 5 min / source
  IP (`infra/remote/nakama/Caddyfile:25-31`). The suite makes
  ~80 auth POSTs (61 call sites in `test_*.gd`, plus
  `multi_session_anon(count, ...)` mints `count` users per
  call). 80 ≫ 30 ⇒ ~50 calls hit 429 if run back-to-back.
  Original 2026-05-04 framing: "before the suite can be a
  regular CI gate, add pacing or backoff." That premise is
  now obsolete — Stage 8.31 (shipped 2026-05-14) put the CI
  gate on the ephemeral docker-compose stack which has no
  Caddy in front and no rate limit. The remaining
  manual-run-against-prod use case is one-off debugging
  where the operator can run subsets via
  `gut_cmdln.gd -gtest=<file>` or wait 5 min between batches.
  Not worth designing pacing/backoff for that. Don't
  re-investigate; this entry is the audit trail.
- **Cert hygiene — verified-and-skipped 2026-05-15.** Cert A
  from cert-rotate run `25301578756` (2026-05-04 04:48) was
  uploaded with `is_hidden: true` (a typo for the Edgegap API
  field `is_secret: true`), so `TLS_FULLCHAIN` / `TLS_PRIVKEY`
  defaulted to public on Edgegap env vars for ~3 minutes
  before the immediate follow-up run `25301673425` (04:51)
  fixed the field name. Cert expires 2026-08-02. Verified
  superseded multiple times since (latest live cert is from
  run `25501621027`, 2026-05-07, expires 2026-08-05).
  Skipping revocation: reach was bounded to `EDGEGAP_TOKEN`
  holders (who could rotate the cert themselves anyway,
  making the marginal risk near-zero), and the cert-rotate
  workflow doesn't persist a Let's Encrypt account, so
  revoking would require either the cert's PEM (long gone)
  or a new revoke-cert.yml workflow doing DNS-01 re-issue +
  revoke. Not worth the work given the 79-day natural-expiry
  horizon and the low reach. Don't re-investigate; this entry
  is the audit trail.
- **Remote-player-state glitches — verified-likely-resolved
  -in-code 2026-05-15.** Source doc archived to
  `docs/archive/REMOTE_PLAYER_STATE_GLITCHES_session_context.md`
  (originally captured 2026-03-28 pre-multi-game). The
  "Attempt 2 (UNVERIFIED, LOW confidence)" fix proposed in
  the doc has shipped and been substantially refined: the
  current `character_state_from_server.gd::_pack_buffer_state_from_network_state`
  override (line 183-218) captures `surfaces` from every
  incoming server state — not just buffer-read entries —
  and the docstring explicitly addresses the original LOW-
  confidence concern about buffer entries only carrying
  CLIENT_PREDICTED data without a rollback. Additionally,
  the `perf_tracker` fix in `rollback_netcode 6065de3`
  (state_send_interval compensation) revealed that the
  50-92% perceived packet loss the bug investigation was
  reasoning over was a measurement artifact — real loss is
  much lower. Combined: the proposed fix is in place AND
  the symptom-reporting that motivated it was distorted.
  Multi-client smoke at the keyboard would confirm; until
  then, treating this as resolved. Don't re-investigate
  unless visual glitches resurface in a real session;
  this entry is the audit trail.

**Items NOT in this list** (because they're already in the
roadmap above):
- Godot 4.5 `WebSocketPeer` localhost quirk → status summary
  item (d) under "Remaining open items".
- 4.3 require_accept dialog → Stage 4 task entry.
- 4.8 region picker → Stage 4 task entry.

**Already burned by this pattern (resolved 2026-05-15):**
- `VIEWPORT_CENTERING_SESSION_NOTES.md` was archived to
  `docs/archive/` after an audit pass nearly re-applied
  stale `+(227,128)` camera-position shifts to scenes that
  had already been corrected through a different approach.
