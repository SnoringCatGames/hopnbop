# H37 stats-ops audit
Started 2026-10-14 09:34:17 -07:00. Repos at: hopnbop 44f0093e, platform 8e85e8a, netcode 7d6ebd9.

Scope: per-player match stats, leaderboards (writes, partitions, anonymous exclusion,
in-game screen, public web board + route, caching, rate limits), settings
(menu, local_settings, level_preferences, device_config, release overrides),
per-game config (game.yaml -> sync-game-config.ps1 -> register_game, version_check,
versions, legal parity), crash reporting (H32, H33), observability/ops
(prod-health-check, synthetic-match-probe, nightly-smoke, check-prod),
retention and cleanup crons, rate limiting and CORS (dadd2d16).

Status words: Verified (a run I did, or a cited test that covers the case),
Believed (code reading), Suspect, Broken.

## Summary (ordered by severity; written 10:43)

1. **ST1 Verified (probe), medium-high:** settings revert two launches after a player changes them, for every
   player with a session (guests included): gore, critters, cheats, full screen, mute, offline mode. The cloud echo
   of the device's own save is re-applied because sync-at never advances (`settings_cloud_sync.gd:33-42,90-93`),
   and `set_override` then erases each key because it compares against the live value, not the default
   (`local_settings.gd:136-143,187`). Section 3.
2. **C7 Verified (artifact), medium-high:** the in-game Terms, Privacy and Data-deletion screens are blank in
   exported builds: `res://legal/**/*.txt` is not a resource and every preset has `include_filter=""`. The consent
   screen's links open these screens. Cross-area with h37-account. Section 4.
3. **Crash-pipeline blind spots, medium.** CR1: a dedicated server's fatal error or engine crash is never reported
   (its queue dies with the container). CR6: script and engine errors that do not crash are never reported (only
   `G.log.error` feeds the reporter; no `OS.add_logger`). CR7: web and Android engine crashes are never found (no
   log file). Section 5.
4. **S1 + OP2, medium:** match_end is not atomic (a failed leaderboard or history write is logged at Warn and lost
   for good, `match_lifecycle.go:538-541,563-565`), and no monitor exercises match_end, the board, history or the
   public route. The prod board is empty: 0 `leaderboard_record` rows at the 10-14 backup. Inferred cause: no real
   matches (OP3); a match_end fault is not ruled out (needs the Nakama log). Sections 1, 2b, 6.
5. **OP1 Verified, medium:** caddy-access-analytics (claude-config) has reported nothing real since at least 10-01
   (`jq -c`), so 429s and 5xx are unwatched. Section 6.
6. **OP3 Verified, medium for metrics:** player-metrics' DAU is the nightly smoke, which leaves a new account on
   every run (`nightly-smoke.yml:39,51`). Same class as SP23. Section 6.
7. **RL3 Suspect, medium-low:** any authenticated session can write unbounded storage (no
   `BeforeWriteStorageObjects` hook, no Caddy zone on `/v2/storage` or `/v2/rpc`); filling the one host's disk
   takes down everything. Section 8.
8. **C1 + C2 Suspect, medium (process):** legal parity is checked only by `pr-validate`, which never runs on push
   (H11), and `sync-game-config.ps1` publishes whatever `legal_version` game.yaml holds. Section 4.
9. **L2 Verified mechanism, Suspect consequence, medium at scale:** the public read scans 5 pages of 100 and
   guests are recorded on the board, so hidden records can starve the listing and My Stats ranks. Section 2.
10. **RT1 + OP6, low-medium:** per-match rows of a match that never ends are kept forever, and Grafana watches only
    infrastructure. A sweep that counts "matches that never ended", plus 5xx and 429 rules over metrics Prometheus
    already scrapes, would cover items 3, 4 and 5. Sections 6, 7.

Lower: S3 (`level_id` always "", blocks per-level boards); ST2/ST3 (dropped saves, whole-blob last writer wins);
L3 = SP16 (a deleted player stays listed up to about 2 min); C3/C4 (`edgegap_app_version` not in mustSurvive,
unknown keys ignored); RT2 = SP14 (notifications grow, 476 -> 508 in a week); CR4 (the global crash cap starves
servers); S11 (final match stats ride one unreliable RPC); ST5 (stale CLAUDE.md "Configuration", dead `dev_mode`);
RL5/RL6 (no Caddy validate or reload, unpinned build); SP10 (gofmt drift, new file set); OP7, RT3, RT4.

Checked and fine: the board is authoritative, so clients cannot post scores (`leaderboards.go:176-177`); the public
route returns only rank, display name and score and never echoes input (`leaderboard_public.go:117-119`, Go tests,
live GET); forged match_end is refused and synthetic matches write nothing (`match_lifecycle.go:394`, tests);
register_game needs the admin key and rejects bad boards before upserting (tests); live version_check equals the
repo (0.54.0, protocol 2, legal 1.2); CORS on the public routes; IPv4 only and no CDN, so per-IP limits key the
client; the client crash queue, redaction and caps (53 GUT tests) and the runtime limiter, prune and redaction (Go
tests). Go 98 tests pass and `go vet` is clean (09:43); GUT 106 tests pass (09:46). Details under "Runs".

Not checked (constraints): the compliance suite and the `leaderboard-local-backend` scenario (need a local stack);
any 429 path and whether prod runs the committed Caddyfile (would mean tripping prod limits); the Nakama and
Postgres logs behind S1, OP2 and OP4, the host's Docker log rotation and the SP3 `.env` (SSH); prod Grafana's loaded
rules (login); H28 (lobby runs are h37-exec's).

## Flows

### 1. Per-player match stats: record, post, dedup (written 09:40)
- Cases needed: happy path (2-4 players, Edgegap and local-allocator); couch co-op (two players on one peer); leaver mid-match;
  all players leave mid-match; local/offline mode; preview; anonymous player; game server retry after timeout;
  duplicate match_end; Postgres blip mid-write; forged/oversized stats; empty game_id; synthetic probe match.
- Implementation: server accumulates `src/core/player_match_stats.gd` (18 fields) -> `game_panel.gd:1590 server_end_match()`
  -> `game_panel.gd:1735 _server_report_match_result()` (dedupes couch co-op by best rank; entries `{user_id,score,kills,bumps}`,
  winner = rank 1, stats `{duration_sec, level_id}`) -> `match_result_reporter.gd report()` (2 attempts, 5 s timeout,
  1 s backoff, retries transport errors and 5xx only) -> runtime `match_lifecycle.go:387 MatchEndRpc`.
  Runtime: registration read (dedup) -> metadata read (code 13 on error, retried) -> winner check -> restrict to matched
  users (`:462`) -> clamp (`:206`) -> synthetic skip (`:501`) -> per-player `LeaderboardRecordWrite` `{game_id}_ffa`
  (`:527`) + `match_history` row keyed by request_id (`:553`) -> cache invalidate (`:568`) -> recent players (`:584`)
  -> delete registration + metadata (`:593`) -> stop deployment (`:623`).
- Coverage: runtime Go unit `match_lifecycle_test.go` (validation, restrict, clamp; see run below); harness
  `leaderboard-local-backend` (exec-b's run); no GUT test of `_server_report_match_result`; no test of the
  game server -> runtime post against a real stack (CI has none; local-smoke-test runs the compliance suite only).
- Status / gaps:
  - S1 **Suspect (Believed, high confidence): match_end is not atomic and a failed leaderboard write is lost for good.**
    `match_lifecycle.go:538-541` logs `leaderboard write ... ` at Warn and carries on; `:563-565` same for match_history;
    the RPC then deletes the registration (`:593-613`) and returns ok, so the game server never retries and a later
    retry would be rejected as unknown request_id. A Postgres blip mid-loop records some players and not others.
    This is the archived audit §7 "Postgres failover during match_end (half-applied)" item: still open.
  - S2 Believed OK: duplicate/concurrent match_end (game server retries after its 5 s timeout while call 1 still runs)
    can pass the registration read twice and write twice. Harmless today only because the board's operator is `best`
    (`game.yaml:161`) and history is keyed by request_id (overwrite). An `incr`/`set` board or a counter would double-count.
    Nothing documents that `best` is load-bearing for idempotency.
  - S3 **Broken (Believed, high): `level_id` is always "" in match stats.** `edgegap_server_provider.gd:266-270`
    `server_get_selected_level_id()` returns "", and `_server_report_match_result()` reports it. The runtime ignores
    `stats` today, so no user-visible harm; any per-level board (DISTRIBUTED_SYSTEMS_PLAN M8) would be built on nothing.
  - S4 Believed (by design, undocumented): only score, kills and bumps reach the backend; the other 15
    `PlayerMatchStats` fields die with the match. Plan M7 "lifetime stats" was never built.
  - S5 Believed (low): an empty `metadata.GameID` (no game_id vote; `fleet_allocator.go:748-752`) writes the bare `ffa`
    board, which is never created (boards are `{game_id}_ffa`, `leaderboards.go`), so the write fails and S1 loses it.
    Only pre-3.10 clients send no vote; low.
  - S6 Believed (cosmetic): `game_session_manager.gd:560-568` comment says the reporter has a "10s timeout"; it has
    2 x 5 s + 1 s backoff = 11 s worst case under the 12 s quit timer. Margin is 1 s plus TLS setup.
  - S7 Believed: `match_result_reporter` posts to `Platform.get_nakama_base_url()`, hard-coded prod
    `https://nakama.snoringcat.games` (`global.gd:146-148`), while `register_with_runtime()` honors `NAKAMA_URL`
    (`edgegap_server_provider.gd:77-79`; local containers get `http://nakama:7350`, `local_allocator.go:208`).
    Prod works via the public hairpin; a game server pointed at a dev stack posts match_end to prod (401, lost).
    No local stack can exercise the full report path.
  - S8 Believed (by design): all players leaving mid-match -> `game_session_manager.gd:541-569` quits after 12 s with
    no match_end and no match_cancel; nobody is recorded and the deployment is not stopped by the runtime
    (left to the restart-idle-cancel cycle or the leak sweep). Lifecycle side is h37-matchmaking's.
  - S9 Believed OK: a leaver mid-match stays in `match_state.players_by_id` (only `lobby_level.gd:394` erases) and is
    demoted (`game_match_state.gd:365-399`), so they are reported as a loser. Local mode and preview never report
    (`game_panel.gd:1590-1644`), by design.
  - S10 Believed: a synthetic-marker read error counts as "not synthetic" (`match_lifecycle.go:340-348`), so a probe match
    can land on the board during a Postgres blip; probe accounts are filtered from the public list, so low.
  - S11 Believed, low (added 10:43): "the stats screen" is the game-over screen (`game_over_screen.gd:222-240,336-354`:
    rank, name, score, K/D). In a networked match the client receives PlayerMatchStats once, at match end
    (`game_panel.gd:2165-2168`), through an **unreliable** RPC (`match_state_synchronizer.gd:387`); the 0.5 s periodic
    send runs only in preview and local mode (`:368`). One lost packet leaves that client's game-over rows without
    K/D (`game_over_screen.gd:345`). Score is unaffected (it rides the player state). No GUT test covers the
    game-over screen (grep). Fix: send the final snapshot with a reliable RPC.
- Testability: a Go test with a fake `NakamaModule` whose `LeaderboardRecordWrite` fails once would pin S1 (cheap,
  `match_lifecycle_test.go` already fakes nk). A GUT test that stubs `G.match_result_reporter` and drives
  `_server_report_match_result()` with couch co-op and a leaver would cover the game side (medium).

### 2. Leaderboards: writes, partitions, public route, in-game screen, My Stats (written 09:44)
- Cases needed: write on match_end (winner, loser, leaver, duplicate call, synthetic probe, NaN/negative score,
  board missing); rating partitions; listing rules (guest, nameless, banned, deletion queued, probe prefix, renamed);
  ties; public route (GET, OPTIONS, other methods, bad params, oversized, read failure, never-created board, 0 rows);
  cache (TTL, invalidate on match_end, invalidate during a read, stampede, stale-on-error); rate limit; CORS/CORP;
  in-game screen (signed in, guest, offline, slow, close by X/Esc/Trigger/L/R); My Stats (ranked, unranked,
  guest, not signed in, failure); web board (`web/leaderboard/`); deleted account disappears.
- Implementation: `game_panel.gd:1735-1808` -> `match_result_reporter.gd` -> runtime `match_lifecycle.go:387-636`
  (write `{game}_ffa`, operator `best`, `game.yaml:158-162`); boards ensured by `leaderboards.go`; public route
  `leaderboard_public.go:336-408` (cache 219-261, read 535-587, list rules 592-684, rank 689); per-player
  `player_data.go:85-146` (`get_player_stats`), 238-322 (`get_match_history`); client `backend_api_client.gd:140-302`;
  screens `src/ui/leaderboard_panel/leaderboard_panel.gd`, `src/ui/screens/my_stats_screen.gd`.
- Coverage (run 09:43, `h37-stats-ops/go-test.log`: 98 matching runtime tests PASS, 0 FAIL; `go vet ./...` clean):
  - Verified (Go unit): validation, no input echo, response shape, empty board, listable-only, no identifiers,
    HTML escaping, limits, 5-page cap, per-board TTL, invalidate inside TTL, invalidate during a read, concurrent
    requests share one read, stale copy while reads fail, first read failure -> unavailable, board never created,
    methods (OPTIONS/405), ranking ties (`leaderboard_public_test.go`); boards ensure/drift/registry validation
    (`leaderboards_test.go`); match_end records only matched players, rejects outsiders/unallocated/unregistered ids,
    metadata read error retryable, invalidates cache, synthetic match writes nothing
    (`match_lifecycle_test.go:280-292`), clamp (`TestClampPlayerStats`); get_player_stats own/other/unranked null/
    unlisted no rank/no board/no reader; get_match_history newest-first, empty, read failure -> empty.
  - Compliance suite (`test_public_leaderboard.gd`, `test_player_stats.gd`): not run by me (needs a local stack;
    h37-exec owns that). GUT: see "Runs" below.
  - No coverage: a failing `LeaderboardRecordWrite` (the fake at `match_lifecycle_test.go:63-69` cannot fail), the
    real Caddy rate limit, the web page `web/leaderboard/`, deletion -> delisting latency.
- Findings:
  - L1 Believed (low, privacy): `get_player_stats` with `player_id` (`player_data.go:108-111`) returns any user's
    best_score and match count to any session, including guests and accounts queued for deletion, bypassing the
    public listing rules. Ids are visible via friends/party/recent players. Documented (PLATFORM_ARCHITECTURE:713),
    covered by `TestGetPlayerStatsForAnotherPlayer`, so intended; the deletion-queued case is the odd one.
  - L2 Verified mechanism, Suspect consequence (medium at scale): the public read stops after 5 pages of 100
    (`leaderboard_public.go:561-577`; `TestPublicLeaderboardStopsPagingAtTheCap` asserts 0 listed when the top 1000
    are nameless). Guests are recorded on the board (only listing filters them), so once more than 500 hidden
    records outrank eligible players, the board lists fewer than 100, and players below the scan get no rank
    in My Stats ("-"). Fix: skip guests at write time (or a second, listable-only board), not a bigger scan.
  - L3 Verified (by grep) SP16 still open: the only invalidation call is `match_lifecycle.go:569`; delete_account,
    bans and display-name changes do not invalidate, so a deleted player stays listed up to 60 s cache + 60 s
    `Cache-Control max-age` (`leaderboard_public.go:401`).
  - L4 By design: linked players are listed under their provider "name" claim (`auth_api_client.gd:1535-1567`) with
    no in-game rename or opt-out. Disclosed in `legal/en/privacy.txt:61-71`. Risk: full real names on a public page.
  - L5 H29 still true: `fetch_player_stats` (`backend_api_client.gd:305-323`, stale fallback `{"rating":1500,
    "matches":0}`), `fetch_match_history` (366-380) and their signals have no callers; `BinaryToggle` is unused.
  - L6 Partitions: AWS-era `rating_partition` is gone; one board per game (`hopnbop_ffa`). The archived audit
    section 1 "bare ffa" is resolved, except the empty-game_id fallback (S5).
  - L7 Believed OK: the cache entry mutex is held across the read with a 5 s timeout, so a stampede is one read and
    waiters are bounded (`leaderboard_public.go:219-261`; `TestPublicLeaderboardConcurrentRequestsShareOneRead`).
  - L8 Believed: the in-game screen shows rows as Labels in a ScrollContainer, not focusable rows; up/down scroll and
    Trigger/L/R/X/Esc close (`leaderboard_panel.gd:87-98` and `_unhandled_input`). No filter/tab UI remains
    (grep of `leaderboard_panel.tscn`). Acceptable under the UI contract since nothing in a row is actionable.
- Testability: L2 is pinned already; add a Go test "eligible player at record 501 is listed" to make the fix
  measurable (cheap). SP16: a Go test that `delete_account` calls `invalidate()` (cheap, same fake reader).

### 2b. Live public board (observed 09:53, written 10:04)
- Unauthenticated GET of the prod public route for `hopnbop_ffa`: 200, 163 bytes, **0 entries** (keys version,
  game_id, leaderboard, sort_order, operator, next_reset_at, generated_at, entries), `Cache-Control: public,
  max-age=60`, ACAO `*`. The board and route landed 2026-10-11 (platform fca14aa, f4424d5, 019499b).
- Cause undetermined, three candidates: no eligible (named, non-guest, non-probe) record has been written since;
  only hidden records exist (guests, probe accounts); or L2 starvation (needs over 500 hidden records, unlikely
  this early). Telling them apart needs an authenticated board listing, out of scope here. Worth a check by
  Levi: an empty public board two days after launch is either "no linked player has finished a match" or S1/L2
  in action, and no monitor would say which (section 6).
- Update (written 10:43): narrowed by section 6. The 10-14 backup-restore smoke counted 0 `leaderboard_record` rows
  in total, so no record of any kind, guests included, existed at that backup: the "only hidden records" and L2
  candidates are out. DAU equals the nightly-smoke runs (OP3). The game server image pushed on 10-12
  (`game-server.yml` from b370a2d9; `game.yaml:59,80` name `v29`) posts match_end through
  `match_result_reporter.gd`, unchanged since May. Inferred: no real match has finished since the board launched.
  A match_end or write failure (S1) is not ruled out; the Nakama log would settle it (SSH, not done).

### 3. Settings: menu, local_settings, level prefs, device_config, release overrides, cloud sync (written 09:49)
- Cases needed: toggle and persist; restart; reset to default; corrupt or missing cfg; release vs editor values;
  cloud: first device (no row), second device, same device echo, offline change, save failure, expired token,
  log-out and account switch, legacy row migration, two devices editing at once, unknown keys from a newer client.
- Implementation: `src/core/local_settings.gd` (cfg at `user://local_settings.cfg`, `OVERRIDABLE_KEYS` 40-54,
  `GLOBAL_OVERRIDABLE_KEYS` 61-66, `set_override` 133-151), boot `global.gd:341-355` (load, apply overrides, connect
  `auth_completed` -> `fetch_and_merge_from_cloud`), save on panel close `side_panel_manager.gd:90-101`, merge
  `src/core/settings_cloud_sync.gd:77-104`, SDK `settings_api_client.gd` (rows `settings/global`,
  `settings/game/{id}`, owner read/write), release values `settings.gd:354-390`, level prefs
  `local_settings.gd:267-309` (device only), `src/core/device_config.gd`.
- Coverage (GUT runs 09:46, `h37-stats-ops/gut/*.log`, real counts): `test_settings_cloud_sync.gd` 16/16 (partition,
  serialize, apply, sync-at round trip; NOT the merge decision in `_on_settings_received`),
  `test_settings_release_values.gd` 2/2, `test_device_config.gd` 9/9. No test for save failure, echo, account switch.
- Findings:
  - ST1 Verified (probe run, medium-high UX): a player's setting reverts to default two launches after they change
    it. Chain: the panel close saves the row (cloud update_time T1) but never advances the local sync-at
    (`settings_saved` is not connected; `settings_cloud_sync.gd:33-42`), so the next launch's fetch sees T1 > sync-at
    and re-applies the device's own values (`:90-93`). `_apply_scope` calls `set_override` (`:197`), whose "matches
    default, clear" test compares against the CURRENT `G.settings` value, which `apply_all_overrides` already set to
    the override (`local_settings.gd:136-143`, `:187`). So every echoed key is erased from the cfg; the value holds
    for that session only. Probe `h37-stats-ops/test_probe_settings_echo.gd` (GUT, 09:48): preconditions pass,
    "override survives the cloud echo" and "gore still on after restart" FAIL. Hits every signed-in player (guests
    included) on gore, critters, cheats, full screen, mute music/sfx, offline mode. The existing test hides it by
    resetting `G.settings` to resource defaults in `before_each` (`test_settings_cloud_sync.gd:33-37`).
    Fix: compare against `Settings.new()`/the resource default, not the live value; and set sync-at from the save.
  - ST2 Believed (low-medium): save failures are dropped (`_on_request_failed` only clears pending fetches, `:99-104`)
    and an expired token skips the save silently (`:47`, `side_panel_manager.gd:99-100`); nothing retries until the
    next panel close. A failed save after a successful one in the same session reverts on the next launch (ST1 path).
  - ST3 Believed: no per-key merge; each scope is last-writer-wins as one blob, and `_apply_scope` never removes keys,
    so two devices clobber each other's edits and a reset to default cannot propagate. (Archived audit section 5
    "timestamp only" and "no per-device tracking": still open.)
  - ST4 Believed (low): sync-at is per device, not per account. Log-out/deletion clear it (`sign_out_router.gd:140`,
    `local_settings.gd:335`), but an automatic sign-out keeps it, so a different account signing in next compares
    its row against the old account's sync-at.
  - ST5 Verified (test) release overrides cover only match length, HUD, overhead labels, splash
    (`settings.gd:385-389`). `dev_mode := true` (`settings.gd:59`) is never read; `perf_tracker_enabled` and
    `debug_console_enabled` exist nowhere in the repo, so CLAUDE.md "Configuration" is stale. `are_cheats_enabled`
    defaults true and ships (cheat codes are a player feature, `cheat_manager.gd:176`), and it is cloud-synced.
  - ST6 Believed: level preferences are device-local (not in the cloud rows); a second device starts from defaults.
- Archived audit: "no global vs game scope" resolved (rows `global`, `game/{id}`); "settings collision across games"
  resolved by the scope split; "timestamp only" and "stale device clobbers" still open (ST3), plus ST1.
- Testability: ST1 is one GUT test (the probe, cheap). ST2/ST3 need a fake `Platform.settings` that records
  saves and emits `request_failed` (medium, `PlatformSettingsApiClient` is a Node with three signals).

### 4. Per-game config and versions (written 09:54)

Chain: `game.yaml` + `project.godot` -> `scripts/sync-game-config.ps1`
(injects protocol/display versions, checks, optional ssh image pull)
-> `register_game` (HTTP key + `admin_key`) -> `games` row + in-memory
cache + leaderboards -> `version_check` (RPC and unauthenticated
`/snoringcat/version_check`) and the matchmaker's pre-allocation
protocol gate.

Coverage: go-test.log (09:43): TestRegisterGameRequiresAdminKey,
TestRegisterGameRejectsInvalidLeaderboards, TestEnsureGameLeaderboards*,
TestLeaderboardDrift, TestParseLegalVersionFromConfig,
TestVersionCheckRpc{CompatibilityMatrix,SurfacesPerGameConfig,EmptyPayload},
TestVersionCheckHTTP{MatchesRpc,Defaults,RefusesOversizedBody,RefusesOtherMethods}
all PASS. Live, unauthenticated GET (09:52): prod `version_check
?game_id=hopnbop&client_protocol_version=2` -> protocol 2, game_version
0.54.0 (= project.godot `config/version`), legal 1.2 (= game.yaml:186
and `src/core/legal_version.gd:25`), is_compatible true, mm 2-4, 2 modes;
`client_protocol_version=1` -> is_compatible false. Headers:
`Cache-Control: no-store`, `Access-Control-Allow-Origin: *`.
Not covered anywhere: the script itself (no test), `validateGameConfig`
(no direct Go test; grep finds no caller in `*_test.go`), the
pre-allocation protocol abort (no Go test; only the compliance test
`test_matchmaking_failure_modes.gd`, which needs a stack, not run here),
client handling of an incompatible answer (`main.gd:207-214`, no GUT test).

| Case | Status |
|---|---|
| Live config equals repo (protocol, display, legal) | Verified (GET 09:52) |
| game.yaml re-adds protocol/display version: script refuses (`sync-game-config.ps1:93`), pr-validate fails (`pr-validate.yml:75-81`) | Believed |
| Missing required field: script exit 2 (`:132-143`), runtime refuses (`per_game_config.go:266-284`) | Believed (no test) |
| Load-bearing key missing: mustSurvive refuses (`:148-159`) | Believed |
| HTTP key without admin key; runtime without GAME_ADMIN_KEY | Verified (TestRegisterGameRequiresAdminKey) |
| Invalid leaderboard entry refuses the whole call before upsert | Verified (TestRegisterGameRejectsInvalidLeaderboards) |
| Board creation fails after upsert: error 13 "config stored, but", script exit 1 with config live | Believed (`per_game_config.go:361-368`) |
| Image pull fails: sync aborts before register (`:223-251`) | Believed |
| version_check matrix (0 = compatible, equal, mismatch), HTTP = RPC | Verified (tests + GET) |
| version_check unreachable: client treats as compatible (`backend_api_client.gd:79-85`); ticket gate is the backstop (`fleet_allocator.go:774-805`) | Believed (gate covered only by compliance) |
| Legal parity game.yaml vs legal_version.gd | Verified now (both 1.2); enforcement Suspect, see C1 |

Findings:
- **C1 Suspect (process), medium.** The "hard fail" legal parity and the
  derived-version guard live only in `pr-validate.yml`, which triggers on
  `pull_request` and `workflow_dispatch` (`pr-validate.yml:16-19`). This
  repo never opens PRs; `gh run list` shows the last five runs were all
  `workflow_dispatch` (latest 2026-10-12 21:10Z). Neither
  `deploy-cf-pages.ps1` nor `sync-game-config.ps1` checks parity (grep:
  no `legal` match outside mustSurvive). So a mismatched pair can be
  committed and synced to prod with no check unless someone dispatches
  pr-validate by hand. CLAUDE.md's version table says "pr-validate parity
  check (hard fail)". This is ledger H11 (still open, Verified by
  `gh run list` 09:51) seen from this flow; C2's guard would close it for
  the deploy path without waiting on H11.
- **C2 Suspect, medium.** Nothing stops the documented hazard "every sync
  publishes a pending legal bump" (`.claude/rules/deploy.md`, Legal
  documents). The script syncs whatever `legal.legal_version` holds. A
  cheap guard: refuse when game.yaml's legal_version differs from the
  live `version_check` value unless `-PublishLegalBump` is passed, and
  refuse on game.yaml vs `legal_version.gd` mismatch (this also closes C1
  for the deploy path).
- **C3 Believed, low.** `edgegap_app_version` is not in mustSurvive
  (`sync-game-config.ps1:148-151`). Dropping it from game.yaml syncs
  cleanly and makes Edgegap allocations fall back to the host's
  bootstrap `EDGEGAP_APP_VERSION` env (`per_game_config.go:63-68`),
  probably a stale version, with no error. mustSurvive also checks key
  presence only (`legal: {}` passes).
- **C4 Believed, low.** Unknown or misspelled keys are silently accepted:
  `json.Unmarshal` ignores unknown fields, so the comment at
  `per_game_config.go:262-265` ("unknown keys ... are handled by
  encoding/json's unmarshal step") is wrong. A typo'd optional key outside
  mustSurvive (for example `edgegap_app_version`) silently means its default,
  here the env fallback of C3.
- **C5 doc drift, trivial.** `per_game_config.go:30-31` and `:139-141`
  say every register_game does a full Refresh; `upsert` (`:251-258`)
  updates one cache entry. `:405-407` still points at a future
  `get_protocol_version` RPC, superseded by the unauthenticated route
  (`version.go:163-178`). The vestigial `NAKAMA_PROTOCOL_VERSION` /
  `NAKAMA_GAME_VERSION` env fallback (`main.go:489`) is still there
  (deploy.md asks for its deletion).
- C6 OK: `register_game` replaces the whole blob (`per_game_config.go:229-235`),
  as documented, and the script guards it.
- **C7 Verified (artifact), medium-high, cross-area (consent is h37-account's; added 10:43): the in-game Terms,
  Privacy and Data-deletion screens are blank in exported builds.** `legal_doc_screen.gd:148-159` reads
  `res://legal/<locale>/<doc>.txt` with `FileAccess` and puts the result in `%Content.text`, with no web fallback.
  A `.txt` file is not a Godot resource, so an export includes it only when an `include_filter` names it, and all
  four presets have `include_filter=""` (`export_presets.cfg:10,56,124,167`; `git log -S legal` on that file is
  empty, so they never did). The local web export of 2026-07-16 (`build/web/index.pck`, Godot 4.7.1) holds
  `legal_doc_screen.gd` but no `legal/` path and no `.txt` at all (byte search; see Runs). The consent screen's Terms
  and Privacy links open this screen (`consent_screen.gd:79-94`), so a player is asked to accept terms the game
  shows as an empty page. Editor and harness runs read the files from disk, which is why no test or scenario sees
  it. Windows and Android share the empty filter (Believed; only the web artifact was inspected). Fix:
  `include_filter="legal/*"` on the three client presets, plus a check that an exported pack holds the files, or
  move the text into a resource.

Archived audit (FRIENDS_PARTY_MATCHMAKING_AUDIT.md):
- :59 "no game.yaml, no per_game_config.go": Resolved.
- :286-287 "protocol_version not enforced per game": Resolved
  (`version.go:138-146`, `fleet_allocator.go:785-805`).
- :288-289 / :492 "pr-validate doesn't check protocol parity": Superseded
  (the field is derived and forbidden in game.yaml), but see C1.
- :316-317 "get_protocol_version not in the RPC list": Superseded by
  `/snoringcat/version_check`.
- :529 "check protocol at queue time, not after Edgegap": Resolved enough
  (boot-time check plus the pre-allocation abort).

Testability: a `validateGameConfig` table test and an
`abortProtocolMismatch` unit test are cheap Go additions; the script's
checks could move into a `-DryRun` Pester or plain pwsh test that feeds
fixture YAMLs.

### 5. Crash reporting: client queue, redaction, runtime RPC, retention (written 10:04)
- Cases needed: client non-fatal error; duplicate signature; per-run and queue caps; client fatal error; engine
  crash found in the previous log; never-signed-in or offline player; expired session; editor build; server
  non-fatal error; server without `NAKAMA_HTTP_KEY`; server fatal error; server engine crash or OOM kill; runtime
  per-user, server and global caps; invalid payload; storage write failure; identity and redaction; retention
  and count cap; limiter after a runtime restart; alerting on a new signature.
- Implementation: `G.log.error(msg, category, should_crash)` (`src/scaffolder/scaffolder_log.gd:145-174`:
  `push_error`, then `G.crash_reporter.report_crash`, then on should_crash `OS.alert` and quit) ->
  `src/core/crash_reporter.gd` `report_crash` (143-178: redact first line and log tail, per-run signature
  dedup, enqueue in `user://`, flush unless fatal) -> `flush` (244-290; session for clients, `NAKAMA_HTTP_KEY`
  for servers, `_send` 391-411 through `Platform.get_nakama_client()`) -> runtime `crash_report.go` (parse and
  redact, limiter `reserve` 460-497, system-owned rows read 0 / write 0) -> hourly prune (30 days, 20,000 cap,
  `crash_report.go:100-117`) -> prod-health-check `crashes:` line. Engine crashes: the next run scans the
  previous `godot*.log` (`crash_reporter.gd:185-237`).
- Coverage: GUT (09:46) `test_crash_reporter.gd` 29/29, `test_crash_report_text.gd` 24/24. Go (09:43,
  go-test.log) TestParseCrashReport* (8), TestRedactCrashReportText* (2), TestCrashReportLimiter* (8),
  TestCrashReportRpc* (7), TestCrashReportKeysSortByReceiveTime, TestPruneCrashReports* (6),
  TestCrashReportConstantsStable: all PASS. Compliance `test_crash_report.gd` not run (needs a local stack).

| Case | Status |
|---|---|
| Client non-fatal error: redacted, queued, sent at once | Verified (GUT `test_queued_report_is_sent_once_a_session_exists`, `test_report_carries_no_account_values_or_tokens`) |
| Same signature twice, over 5 a run, queue over 5 | Verified (GUT `test_same_signature_*`, `test_reports_per_run_are_capped`, `test_queue_is_bounded_*`) |
| Client fatal error: queued, sent next run | Verified (GUT `test_fatal_report_waits_for_the_next_run`) |
| Client engine crash: found in the previous log next run | Verified (GUT `test_scan_queues_a_windows_crash`, `_linux_crash`) |
| Editor build: queues, never sends | Verified (GUT `test_editor_build_queues_but_never_sends`) |
| No session: queued, ages out after 7 days unsent | Verified mechanism (GUT `test_report_without_session_is_queued_not_sent`, `test_old_report_ages_out_unsent`); H32 |
| Rejected / rate-limited / failing send | Verified (GUT `test_rejected_*`, `test_rate_limited_*`, `test_failing_*`) |
| Server non-fatal error: sent with the HTTP key | Verified (GUT `test_dedicated_server_sends_with_the_http_key`; Go `TestCrashReportRpcStoresServerReport`) |
| Server without `NAKAMA_HTTP_KEY`: queues nothing | Verified (GUT `test_server_without_http_key_queues_nothing`) |
| Server fatal error or engine crash | Suspect: never reported (CR1) |
| Runtime caps 5/h per user, 200/day servers, 500/day global | Verified (TestCrashReportLimiter*) |
| Invalid payload costs no budget; failed write releases it | Verified (TestCrashReportRpcInvalidReportsDoNotConsumeBudget, ...ReleasesBudgetWhenWriteFails) |
| No caller identity stored; redaction before storing | Verified (TestParseCrashReportStoresNoCallerIdentity, ...RedactsBeforeStoring) |
| Retention 30 days, 20,000 cap, paged backlog | Verified (TestPruneCrashReports*) |
| Limiter state after a runtime restart | By design: in memory, resets (`PLATFORM_ARCHITECTURE.md` crash-report section) |
| End to end against a stack | Not run here |

- Findings:
  - CR1 **Suspect (Believed mechanism), medium: dedicated servers never report a fatal error or an engine crash.**
    A fatal `G.log.error(..., true)` queues its report and skips `flush()` on purpose (`crash_reporter.gd:173-178`:
    "its report waits for the next run"), then quits (`scaffolder_log.gd:169-174`). A game server has no next run:
    each match gets a fresh container (Edgegap deployment per match; local Docker `AutoRemove: true` with no
    volume, `local_allocator.go:219`), so the `user://` queue and the previous `godot*.log` die with it. Segfaults
    and OOM kills go the same way. The pipeline therefore sees only a server's non-fatal errors, and a crashed
    server shows up nowhere except as a match with no `match_end` (S8). The GUT fatal test covers client
    semantics only. Fix: on the server role, flush synchronously with a short timeout before quitting; and have
    the allocator or runtime record abnormal container exits (Docker exit code, Edgegap deployment status) as a
    server report.
  - CR2 Believed: H32 still true. `_get_credentials` (`crash_reporter.gd:381-388`) needs a live session, so an
    offline-only anonymous player's queue ages out unsent after 7 days (`:513-524`, documented `:13-14`).
  - CR3 H33 not implemented: `occurred_at` appears nowhere in the game or runtime (grep). Rows carry receive time
    only (`TestCrashReportKeysSortByReceiveTime`), so a fatal or offline report is dated at its send, days late.
  - CR4 Believed, low (documented trade-off): the 500/day global cap is checked first for every caller, servers
    included (`crash_report.go:468-474`). About 100 free anonymous accounts in an hour (5 each), or a handful over
    a day, fill it and blind crash reporting, server reports included, until midnight UTC. The first cap hit is
    logged once (TestCrashReportRpcLogsTheFirstDailyCapHit); see section 6 for whether anything alerts on it.
    Fix: give HTTP-key callers a budget outside the global cap.
  - CR5 Believed, low: server reports go through `Platform.get_nakama_client()` (prod host from `global.gd:146-148`),
    not the container's `NAKAMA_URL` (S7). Prod works through the public hairpin; a game server on a dev stack
    sends its dev HTTP key to prod and is refused, so no local stack can test server crash reports.
  - CR6 Believed (grep), medium (added 10:43): **only errors logged through `G.log.error` are reported; GDScript
    runtime errors and engine errors that do not crash are never seen.** The reporter has two sources by design
    (`crash_reporter.gd:6-8`: `G.log.error`, which `ensure` and `check` route through, plus a crash found in the
    previous log). Nothing registers an engine `Logger` (no `OS.add_logger` in `src/`), although GUT and the netcode
    parse check already use one (`addons/gut/error_tracker.gd:14`). `push_error` is called directly 4 times in `src/`
    and bypasses the reporter (grep). A script error in a release build (null access, bad call) logs and aborts the
    function without crashing, which is the usual shape of a GDScript bug in production. Fix: a `Logger` subclass
    registered at boot that forwards errors to `report_crash` on the main thread, skipping exit-time leak lines (H28);
    the reporter's per-signature dedup and caps already bound the volume.
  - CR7 Believed, low-medium (added 10:43): engine crashes on web and Android are never reported, and their reports
    carry no log excerpt. The next-run scan reads `user://logs/godot*.log` (`crash_reporter.gd:43,182-237`), and
    Godot enables file logging by default only for the `.pc` feature; `project.godot:38` sets only `max_log_files`.
    The GUT scan tests cover Windows and Linux logs. Web is the cross-play platform, so its crashes surface nowhere.
- Archived audits: nothing in FRIENDS_PARTY_MATCHMAKING_AUDIT.md covers crash reporting (it predates it);
  DISTRIBUTED_SYSTEMS_PLAN M5 (monitoring) is in section 6.
- Testability: CR1's client half is pinned; the server half needs a GUT test that a fatal error on the server
  role awaits a send before quit (cheap once the behavior exists). CR4 is one Go limiter test.

### 6. Observability and ops: which monitor notices a regression (written 10:17)

Sources: claude-config `jobs/scripts/*.ps1` and `_synthetic-match-probe-bin/*.go`; the platform's
`infra/remote/nakama/prometheus.yml` and its Grafana alerting provisioning; hopnbop `.github/workflows/nightly-smoke.yml`.
Job logs were read for their aggregate lines only (IPs masked, no player data copied).

Monitor inventory:

| Monitor | What it exercises | Signal |
|---|---|---|
| Grafana rules (`alerting/rules.yml:13-142`, Discord via `contactpoints.yml:10`) | Nakama up and Postgres up (2 min), PG connections > 90%, disk > 90% (5 min), CPU > 80% (15 min). Prometheus scrapes nakama, caddy, node, postgres, cadvisor (`prometheus.yml:22-68`) | infrastructure only; an always-zero slow-query rule was removed (`rules.yml:148-159`) |
| prod-liveness-ping (hourly), UptimeRobot (`phase-b.ps1:373-416`, SP2) | healthcheck | Discord on transitions |
| prod-health-check (daily) | runtime build, containers, vitals, `docker logs --since 24h` count of `error\|panic\|fatal` (yellow only at >= 100, `:163-168`), backups, timers (`:295-296`), crash reports (red at >= 200/24h, yellow on a new signature or spike, `:300-395`) | Discord on yellow/red |
| synthetic-match-probe, slo-burn-rate (logs every 15 min) | two fixed identities `probe-<host>-<slot>` (`probe.go:48-49`): auth, record_client_ip, version_check (records protocol_version, `:74-102`), matchmaker, allocation, signaling, WebRTC DataChannel, then `match_cancel` (`:250-252`) | burn rate 6h/24h against a 99.5% SLO |
| nightly-smoke (GitHub, 03:00 UTC) | healthcheck, device auth with `create=true`, runtime_status, web client HTML | workflow failure |
| edgegap-leak-sweep (hourly), edgegap-deploy-success-rate | stops Edgegap deployments older than 2 h (`edgegap-leak-sweep.ps1:3-30,52`); deploy outcomes in the last hour | yellow/red |
| nakama-runtime-version-drift, cert-expiry, disk-and-inode-trend, pg-bloat-and-slow-queries, postgres-deep-dive, backup-restore-smoke (weekly) | as named | status entries |
| player-metrics-daily, caddy-access-analytics | DAU/MAU/new users; HTTP status, latency, top URIs | info only, never alert |
| hopnbop-check-prod (claude-config skill, on demand; added 10:43) | healthcheck, runtime build, containers, vitals, 24 h error scan, backups, cost, Edgegap leaks (flags 4 h; the sweep stops them at 2 h), crash reports; its post-DR mode adds table counts against the restore smoke and a synthetic match on both allocator paths | manual report; nothing for match_end, the board, settings or Caddy |

Regression map, first monitor to notice:

| Regression | Notices first | Basis |
|---|---|---|
| match_end fails, or its leaderboard or history write fails (S1; logged at Warn, `match_lifecycle.go:538-541,564`) | nothing. The probe cancels instead of ending, nothing reads the board or history, and the error grep needs 100 lines a day | Verified by reading the probe and job code |
| Public leaderboard route broken or empty | nothing: no job calls `/snoringcat/leaderboard` (grep of `jobs/scripts`) | Verified (grep) |
| Settings revert or save failure (ST1, ST2) | nothing (client-only, no telemetry) | Believed |
| Dedicated-server fatal error or engine crash (CR1) | Edgegap matches: leak-sweep yellow, only if the deployment outlives 2 h. Local-Docker matches (`AutoRemove`, `local_allocator.go:219`): nothing | Believed |
| Client crash flood or cap abuse (CR4) | prod-health-check red at >= 200/24h, next morning | Believed |
| Runtime protocol or config drift | probe (protocol_version), version-drift job, nightly runtime_status | Believed |
| legal_version skew reaching prod (C1, C2, H11) | nothing | Believed |
| Rate-limit misfire, 429 storm, 5xx rate | nothing: caddy-access-analytics is broken (OP1) and no Grafana rule reads request metrics | Verified (OP1), Believed (rules) |
| Storage or notification growth (RL3, SP14) | Grafana disk > 90%; disk-and-inode-trend (> 5% week over week or < 30 days to full) | Believed |
| Junk accounts | nothing; they inflate player metrics (OP3) | Verified |
| Nakama or Postgres down | Grafana (2 min), liveness ping, UptimeRobot | Believed |

Findings:

- OP1 **Verified, medium (ops blindness): caddy-access-analytics has reported nothing real since at least 10-01.**
  `caddy-access-analytics.ps1:46-48` runs jq with `-c`, so every row is a quoted JSON string with a literal `\t`, and
  the awk at `:73-87` sees empty status, latency and URI fields. Every log in the window shows STATUSES as one bare
  count, p50/p95/p99/max 0.0000, TOPURIS as one bare count, and a "0% 5xx" headline. Local repro (10:06): `-c`
  printed `"0.0012\t200\t/v2/rpc/x"`, `-r` printed real tabs. The comment at `:96-101` ("Caddyfile doesn't enable
  access logs") is stale. Fix: `-r`. This is the only consumer of the Caddy access log, so 429s and 5xx are unwatched.
- OP2 **Verified (code and logs), medium: no monitor exercises match_end, the leaderboard write, match_history or the
  public board in prod.** The weekly restore smoke counted 0 `leaderboard_record` rows on 10-07 and 10-14, and the
  public route returned 0 entries at 09:53 (2b). A total match_end outage looks exactly like no traffic; the only
  distinguishing record is a Warn line in the Nakama log (needs SSH, not done).
- OP3 **Verified (two records agree), medium for metrics: player-metrics' DAU is the nightly smoke.** nightly-smoke
  authenticates a new device `ci-smoke-<epoch>` with `create=true` on every run (`nightly-smoke.yml:39,51`) and never
  deletes it; Nakama gives it a random username, so the only exclusion, `username NOT LIKE 'probe-%'`
  (`player-metrics-daily.ps1:55-61`), misses it. Observed: DAU was 1, 1, 3, 1 on 10-11..10-14, and `gh run list`
  shows exactly 1, 1, 3, 1 smoke runs in those 24 h windows (the 3 is the nightly run plus two manual dispatches on
  10-12/13). Between the two restore smokes users went 214 -> 223, and 9 smoke runs fell in that week (7 nightly, 2
  manual). Inferred: no real daily players on those days, which explains the empty board (OP2) without a match_end
  fault but does not rule one out. The header claim "ephemeral data that doesn't pollute live state"
  (`nightly-smoke.yml:6-8`) is false. Same class as SP23. Fix: reuse one fixed `probe-`-prefixed device id, as the Go
  probe does, or delete the account at the end of the run; then exclude it from metrics.
- OP4 Observed, low: prod-health-check's Postgres error count was 1 (10-07), 2 (10-12), 1 (10-14), 0 on the other
  days read. 10-07 and 10-14 are restore-smoke days (restore into a temp DB on the prod host at 05:37, before the 05:51
  check). Inferred, untested: the restore emits those lines; 10-12 does not fit that. Reading them needs the container
  log (SSH). Nothing alerts below 100 lines a day, so a slow trickle of real errors would also stay silent.
- OP5 Observed, info: the crash pipeline's only prod evidence is the test report counted on 10-12 (`test
  reports=1`); 10-14 shows `crashes: 24h=0, retained=0`. With no real daily players (OP3) a zero is expected and says
  nothing about CR1 or CR2.
- OP6 Believed, low-medium: Grafana alerting is infrastructure-only (`rules.yml:13-142`). Prometheus already scrapes
  caddy and nakama (`prometheus.yml:27,33`), so a 5xx-rate, 429-rate or RPC-error-rate rule needs no new job and would
  cover the rate-limit rows above. Not checked: that prod Grafana loaded these rules (needs a login).
- OP7 Believed, low: `get_match_history` reads every history row of the caller on each call, up to 100 list calls of
  100 rows, and its totals silently stop at 10,000 matches (`player_data.go:179-185,272-320`). No per-session limit
  applies (RL4). Harmless at today's scale.

Archived-audit verdicts (my area):

- FRIENDS_PARTY_MATCHMAKING_AUDIT section 6 "observability stripped" and P3 #25 "re-introduce observability": partly
  resolved. Prometheus and Grafana with five infrastructure rules are back; Loki and Promtail were left off on purpose (platform `infra/remote/nakama/docker-compose.yml:7-12`), so logs live only in `docker logs`; plus about 15 claude-config jobs; nothing
  watches application behavior (OP2, OP6).
- Section 6 "timers without alerting": resolved (`prod-health-check.ps1:295-296`).
- Section 6 "env versions bumped by hand": resolved by the per-game config; caveat C3.
- Section 6 "no staging": still true. `infra/dev/` has no Caddy, so CORS, rate limits and the public routes are
  exercised only in prod (RL5).
- Section 7 "forged match_end": resolved (`match_lifecycle.go:394`; `MatchCancelRpc` admits clients only for synthetic
  matches, `:650-674`). "Postgres failover during match_end": still open, as S1.
- Tier 4 "extend the probe with party and friends": not done, and the probe never ends a match (OP2).
- DISTRIBUTED_SYSTEMS_PLAN M5 (CloudWatch and crash-rate alarms): AWS-era; the equivalents are partial (crash alarm
  via prod-health-check, infrastructure via Grafana, no application error rate). M7 lifetime stats: not built (S4).
  M8 boards: all-time only; weekly, friends and per-level not built, per-level blocked by S3. M15: rate limits exist at
  Caddy for auth and the public routes and in the runtime for crash reports; `/v2/rpc` and `/v2/storage` are unlimited
  (RL3); no CDN (RL2); DAU/D1/D7 exist but measure the smoke (OP3).
- Decisions (`:107-112`): #22 weekly board and #23 friends board not built. #24 "all settings, prefer cloud": built,
  but ST1 makes the cloud echo erase local values, and ST3 (whole-blob last writer wins). #25 "last 5 matches": the
  runtime lists 50 and keeps every row (OP7, section 7). #26 "all PlayerMatchStats fields": only score, kills and bumps
  reach the backend (S4). #27 "email via SNS": replaced by Discord through the jobs and Grafana.

### 7. Retention and cleanup crons (written 10:19)

Case matrix (runtime paths under platform `runtime/` unless named):

| Data | Cleanup | Evidence |
|---|---|---|
| Accounts queued for deletion | account cron, hourly (`account_cron.go:44-50,68-110`), hard delete after the 30-day grace (`:121-186,220`) | Believed. None of `account_cron.go`'s six functions appears in a Go test (grep). Deletion itself is h37-account's flow |
| Pending profiles | `keepPendingProfileClear` each pass (`account_cron.go:186`) | Believed, no unit test |
| `client_ip` rows | stale-IP prune after each account-cron pass | Verified: TestClientIPRetentionKeepsUsableRecords (go-test.log, 09:43) |
| Crash reports | crash cron (`crash_report.go:651-692`): expiry plus a stored cap | Verified: six TestPruneCrashReports* tests |
| Friend-code limiter rows | pruned on each call | Verified: TestAllowFriendCodeCallPrunesIncrementally |
| Leaderboard records | none: `reset_schedule: null` (hopnbop `game.yaml:158-162`), all-time by design. A deleted account's records are scrubbed (TestLeaderboardIDsToScrub*), but the public cache keeps them (SP16, L3) | Verified (config, tests) |
| match_history | none: one row per player per match, keyed by request id (`match_lifecycle.go:544-566`), kept for the account's life (OP7) | Believed |
| Notifications | none, except on account deletion (`privacy.go:210,229`). `match_ready` and `match_failed` are persistent (`fleet_allocator.go:1224-1232,1445-1454`) | Believed (code); Observed: 476 -> 508 rows between the 10-07 and 10-14 restore smokes |
| server_registrations, match_metadata, synthetic_matches | deleted only by MatchEndRpc (`match_lifecycle.go:590-612`) and MatchCancelRpc (`:722-752`); no sweep | Believed (grep of every `StorageDelete`) |
| Anonymous and junk accounts | no reaper (SP23); nightly-smoke adds one per run (OP3) | Verified (OP3) |
| Game-server images on the Nakama host | pulled per release by hopnbop `scripts/sync-game-config.ps1:34-40`; nothing prunes them (no `image prune` or `rmi` in the platform's infra or scripts, or in claude-config jobs) | Believed |
| Container logs | no `logging:` options in the compose and no daemon.json in the repo; Loki and Promtail are off (`docker-compose.yml:7-12`); local game-server containers are auto-removed with their logs (`local_allocator.go:219`) | Believed; the host's Docker daemon config is unchecked (SSH) |
| Prometheus TSDB | 30 days (`docker-compose.yml:226-230`) | Believed |

Findings:

- RT1 **Believed, low-medium: per-match rows leak for every match whose server neither ends nor cancels.** A server
  crash (CR1), or an abandoned match where no restarted server cancels (S8), leaves its `server_registrations`,
  `match_metadata` and, for probes, `synthetic_matches` rows forever: only the two RPCs delete them. The rows are
  small; the cost is clutter and, more usefully, a lost signal. Fix: an hourly sweep that deletes rows older than
  the longest possible match plus margin, and logs or reports how many it found. That count is "matches that never
  ended", a free application-level monitor for OP2 and CR1.
- RT2 = SP14, still true, with numbers: the notification table grew 476 -> 508 in a week of near-zero real traffic
  (OP3). The daily synthetic probe alone adds two persistent `match_ready` rows a day (7 runs in that week, two
  identities, and the probe never deletes them). Each `match_ready` row holds the connection payload: the signed
  signaling URL and that player's session ids. Believed inert once the match is over (the URL signs a timestamp,
  `fleet_allocator.go:1213-1215`; session ids are per match), so this is retention, not exposure. Fix as SP14 says:
  send them non-persistent, or prune by age.
- RT3 Believed, low: disk is the backstop for three unbounded stores (game-server images, container logs, the rows
  above). Grafana's disk > 90% rule and disk-and-inode-trend would notice; nothing removes them. Whether the host's
  Docker daemon rotates logs is unchecked.
- RT4 Believed, low (coverage): the account cron's deletion queue, pending-profile scrub and hard delete have no
  Go unit test (grep). Any coverage is the compliance suite (not run here: it needs a local stack, which only
  h37-exec-a/b may start). Passed to h37-account.

### 8. Rate limiting and CORS (written 10:04)
- Cases needed: auth burst from one IP; public leaderboard and version_check bursts; 429 body and CORS on the
  public routes; preflight from any origin; per-IP keying (proxy, CDN, IPv6); RPC and storage floods from an
  authenticated free anonymous session; request size; runtime limiters (friends, crash reports); keys in access
  logs; config drift between repo and prod.
- Implementation: custom Caddy with mholt/caddy-ratelimit (`infra/remote/nakama/caddy/Dockerfile`,
  `docker-compose.yml:153-179`). `infra/remote/nakama/Caddyfile`: zone `authenticate` on
  `/v2/account/authenticate*` 30 per 5 min (:55-60), `public_leaderboard` 300/min (:74-79), `version_check`
  600/min (:82-87), all keyed `{remote_host}`; `handle_errors 429` adds `Access-Control-Allow-Origin: *` and a
  JSON body on the two public routes (:100-115); the access log masks `http_key` and `admin_key` (:23-40).
  Runtime limiters exist only for friends (`friends_limits.go:79-173`, `friend_code.go:348`) and crash reports
  (`crash_report.go:427-497`). History: platform 706f452 (2026-10-11) added CORS on 429s and the version_check
  zone and raised the leaderboard zone from 60 to 300/min; hopnbop dadd2d16 (2026-10-12) bumped to it.
- Coverage: no local test exercises Caddy at all (`infra/dev/` has no Caddy: 0 matches); compliance has no 429
  test outside the crash-report runtime limiter. Go: TestPublicLeaderboardValidation, ...Methods,
  ...ErrorsDoNotEchoInput, TestVersionCheckHTTP* (09:43), TestAllowFriendCodeCallPrunesIncrementally,
  TestCrashReportLimiter*.

| Case | Status |
|---|---|
| Public leaderboard 200 and OPTIONS with a foreign Origin carry ACAO `*` | Verified (live GET 09:53) |
| version_check 200 carries ACAO `*` and `Cache-Control: no-store` | Verified (live GET 09:52) |
| Bad params: `leaderboard=nope` 400, unknown game_id 404, `limit=100000` 400, no input echo | Verified (live 09:53 + Go) |
| 429 on public routes carries CORS and a JSON body | Believed (`Caddyfile:107-115`); not exercised: tripping it takes 300+ requests a minute against prod |
| Limits key the real client IP | Verified: response `Via: 1.1 Caddy`, no CDN headers, A record on the host, no AAAA record (Resolve-DnsName 10:02), so per-IPv4 keying holds |
| Auth burst over 30 per 5 min refused | Believed (`Caddyfile:55-60`), untested |
| RPC or storage flood from one authenticated session | No limit (RL3, RL4) |
| Friend-code and crash-report floods | Verified (Go limiter tests) |
| Keys masked in the access log | Believed (`Caddyfile:23-40`), untested |
| Prod runs the committed Caddyfile | Unverified (RL6) |

- Findings:
  - RL1 Verified: CORS `*` on every public response observed, preflight included. Fine for public read-only data.
  - RL2 Verified: no CDN or proxy in front and IPv4 only, so `{remote_host}` is the client IP and the per-IP
    zones mean what they say. If a CDN is ever added, every zone collapses onto the CDN's egress IPs.
  - RL3 **Suspect, medium-low (availability): any authenticated session can write unbounded storage.** The
    runtime registers no `BeforeWriteStorageObjects` hook (only BeforeAuthenticate*, BeforeSessionRefresh,
    BeforeLinkEmail, BeforeAddFriends), and Caddy limits nothing under `/v2/storage` or `/v2/rpc`. Nakama lets a
    user write objects it owns into any collection, up to the request size limit (`config.yml` sets none, so
    Nakama's default, believed 256 KiB). A free anonymous account in a loop can grow Postgres on the one CPX21
    host until the disk fills, which takes down everything. Smaller: a client can pre-create its own
    `match_history` rows (owner-read, so it fools only itself) and, after the hourly prune, its own `client_ip`
    row with a forged IP and fresh `ts` (`client_ip.go:20-141`, trusts `ts`), which steers its own region
    choice. Fix: a `BeforeWriteStorageObjects` allowlist (the `settings` collection the SDK writes directly, with
    a size cap), plus a per-IP Caddy zone on `/v2/storage` and `/v2/rpc`.
  - RL4 Believed, low: no per-session limit on other RPCs (stats, history, party, matchmaking calls); each costs a
    DB read. Covered by RL3's Caddy zone if added.
  - RL5 Believed, low: nothing validates the Caddyfile before deploy (grep: no `caddy validate` or `adapt` in
    workflows or scripts). A syntax error stops Caddy, and with it auth, RPCs, signaling and Grafana.
  - RL6 Suspect, low: phase-b copies the Caddyfile (`scripts/phase-b.ps1:301-302`) then runs
    `docker compose up -d --build --pull always` (`:324-325`). Caddy runs without `--watch` and the file is a
    bind mount, so a Caddyfile-only change takes effect only if compose recreates the container (image or config
    change); nothing reloads Caddy. Whether prod runs the committed limits cannot be checked from outside without
    tripping them. The Caddy build is also unpinned (`FROM caddy:2-builder`, plugin at latest), and its comment
    "bump the FROM tag" refers to a tag that floats.
- Archived audits: DISTRIBUTED_SYSTEMS_PLAN's rate-limit items are in section 6/7 verdicts.
- Testability: a dev-stack Caddy (same Caddyfile, `tls internal`) would let local-smoke-test assert the 429
  body, CORS and log masking (medium). RL3's hook is a cheap Go test.

## TODO-scratch notes (TODO-scratch.md at 407c6abd; written 10:43)

| Line | Note | Verdict |
|---|---|---|
| L85 | "Stats screen..." | Partly. My Stats exists (`my_stats_screen.gd`, GUT 5/5: best score, rank, matches); the game-over screen is the per-match view (S11, no GUT test). Lifetime stats (plan M7) not built (S4) |
| L87 | "Test leaderboard screen" | Covered by GUT (`test_leaderboard_screen.gd` 8/8, `test_leaderboard_data.gd` 13/13, 09:46). The `leaderboard-local-backend` scenario needs a local stack; not run here |
| L95-101 | Leaderboard screen: registered Screen, row list, close button with the X icon, close by X, double font | Resolved: registered screen (the scenario opens it by type), close row with the X icon (`leaderboard_panel.gd:265-287`), ui_cancel and close_menu close it (`:151-155`), `_FONT_SIZE := 28` (`:14,255-256`). Rows are Labels, not focusable rows (L8) |
| L102 | Exclude anonymous players from rankings | Done for listing (public list rules; the in-game screen shows a guest hint, `:81`). Guests are still recorded on the board (L2) |
| L103-105 | "filter", "tab", the number after "Your rank:" | Resolved: no filter or tab UI remains; Your rank shows one value (`:142`) |
| L148 | Polish: leaderboard screen | Partly (L8) |
| L166-168 | Legal docs in-game; what if offline? | The repo has in-game copies and a screen, but exported builds do not include the files (C7) |
| L173-178 | Release checklist: versions, Settings release values, legal docs | Partly automated. Versions derive from `project.godot` (the bump stays manual). Release overrides cover four groups only (ST5). Legal parity is checked only in PRs (C1), and shipped builds lack the in-game copies (C7) |
| L214 | GameLift `server_api_key` env | Obsolete: GameLift is gone; dedicated servers get `NAKAMA_HTTP_KEY` (local path `local_allocator.go:102-105,205`; Edgegap path not checked here) |
| L215 | Records lack `rating_partition` | Obsolete: partitions are gone, one board per game (L6) |
| L253 | M5 monitoring | Partial (section 6 verdicts) |
| L256 | M8 leaderboards | Partial: all-time board only; per-level blocked by S3 |
| L521 | Release tool that bumps versions | Partly: one source of truth plus derivation; the bump itself is manual (outside my area) |
| L670-676 | Gore setting | Built as one toggle in the Settings panel (`settings_panel.gd`), not as buttons on the main, pause and game-over menus; default off (`settings.gd:133`). Persistence exists, but ST1 reverts it for every player with a session |
| L759 | Setting to disable the (mobile controls) bar | Not built: no such setting in `settings.gd` |
| L788-790 | Organize Settings | Open: dead `dev_mode` (ST5), flat property list |
| L792-795 | Survey `G.check/ensure/error/fatal/alert` usage | Open. The names are stale: the API is `G.log.error/warning/ensure/check` (`scaffolder_log.gd:145-224`). Related: only `G.log.error` feeds crash reports (CR6) |

## Ledger items (verdicts; written 10:43)

hopnbop:
- H11 still open (C1): `gh run list` (09:51) shows pr-validate's last five runs were all `workflow_dispatch`
  (no PRs). C2's guard would cover the deploy path without it.
- H28 not reproduced (lobby runs are h37-exec's). It cannot reach crash reports today: it is an exit warning, and
  the crash scan matches only the two "Program crashed" lines (`crash_report_text.gd:20-23,207-215`). CR6's fix
  must skip exit-time leak lines, or H28 becomes a report on every second exit.
- H29 still true (L5): `fetch_player_stats`, `fetch_match_history` (`backend_api_client.gd:305-323,366-380`), their
  signals and `BinaryToggle` have no callers.
- H31 still true, with a different label set: "Credits", "Made by", "Sound", "Project management" and "Playtesters"
  are literal (`credits_screen.tscn:40,55,70,85,114`); "Thanks for playing!" no longer exists (grep); the only
  translation key there is `CREDITS.IP_GEOLOCATION`.
- H32 still true (CR2).
- H33 not implemented (CR3).

platform:
- SP2 still true: `phase-b.ps1:373,380,403,416` call UptimeRobot's `v2` API.
- SP3 Believed still true: `PLATFORM_ARCHITECTURE.md:1019-1021` says `GITHUB_TOKEN` is not rendered, so the cost
  monitor's GitHub block reads 0. The host `.env` is unchecked (SSH).
- SP10 still true, with a changed set (`gofmt -l` on LF copies of the HEAD blobs at 8e85e8a): still unformatted
  `friends_limits.go`, `main.go`; now clean `runtime_status.go`, `player_data.go`, `per_game_config.go`; newly
  unformatted `helpers_test.go`, `local_allocator.go`, `party.go`. CI runs vet, test and staticcheck only
  (`nakama-runtime.yml:31-45`). On Windows the CRLF working tree makes `gofmt -l` flag 48 of 49 files; `*.go eol=lf`
  in `.gitattributes` would fix that.
- SP14 still true (RT2, with numbers).
- SP16 still open (L3).
- SP22 still true by config, low. [redacted]
- SP23 still true: `phase-a.ps1:1170` creates `phase-a-smoke-$(Get-Random)`; OP3 is the same class.
- SP24 still true: `player_data.go:42-50,200` still return the deprecated `rating` and `matches`.

New items. The coordinator files them and assigns the IDs; the section numbers below point into this file.

hopnbop:
- ST1: settings revert to their defaults two launches after a change. Cause: the cloud echo plus `set_override`'s
  default test. Fix both and promote `h37-stats-ops/test_probe_settings_echo.gd` into `test/unit/` (section 3).
- C7: the legal docs are missing from exported builds (`include_filter=""` on every preset). Add the filter and a
  check that an exported pack holds the files (section 4; cross-area with h37-account).
- CR6: register an engine `Logger`, so that script and engine errors that don't crash reach crash reports
  (section 5).
- CR1: dedicated servers never report their fatal errors or engine crashes (section 5).
- CR7: engine crashes on web and Android are never found, because those builds write no log file (section 5).
- OP3: nightly-smoke creates one account per run. Use a fixed `probe-` device id instead, or delete the account at
  the end (`nightly-smoke.yml:39,51`).
- C2: `sync-game-config.ps1` publishes whatever `legal_version` game.yaml holds. Guard it: refuse a legal bump
  without `-PublishLegalBump`, and refuse a mismatch with `legal_version.gd` (section 4).
- C3: add `edgegap_app_version` to mustSurvive (`sync-game-config.ps1:148`).
- S3: report the real `level_id` (`edgegap_server_provider.gd:266-270`). This has to happen before any per-level
  board.
- S11: send the final match stats over a reliable RPC (`game_panel.gd:2165-2168`, `match_state_synchronizer.gd:387`).
- ST2/ST3: failed settings saves are dropped, and each settings scope is one blob where the last writer wins
  (section 3).
- ST5: CLAUDE.md "Configuration" lists `dev_mode`, which is dead, and the release overrides cover only four groups
  (section 3).
- H31 (update): the set of literal labels has changed (`credits_screen.tscn:40,55,70,85,114`).

snoringcat-platform:
- S1 + OP2 + RT1: match_end logs a failed write at Warn level and loses it. Instead, keep the registration and
  return a retryable error. Add an hourly stale-row sweep that reports "matches that never ended" (sections 1, 6, 7).
- RL3: storage writes are unbounded. Add a `BeforeWriteStorageObjects` allowlist with a size cap, and Caddy zones on
  `/v2/storage` and `/v2/rpc` (section 8).
- L2: guests are recorded on the board, and hidden records can starve the scan. Skip guests at write time
  (section 2).
- CR4: the 500/day global crash cap is checked first, so a client flood starves the dedicated servers' reports
  (section 5).
- C4 + C5: register_game silently accepts unknown keys, and the `per_game_config.go` comments have drifted
  (section 4).
- Tests: a `validateGameConfig` table test, `abortProtocolMismatch`, account_cron (RT4), and a failing-write fake
  for S1.
- RL5 + RL6: validate the Caddyfile in CI, reload Caddy on deploy, and pin the Caddy build (section 8).
- OP6: add Grafana rules for the Caddy 5xx and 429 rates and the Nakama RPC error rate (section 6).
- OP4: read the Postgres error lines from the restore-smoke days (needs SSH; section 6).
- RT3: nothing prunes game-server images or container logs. Check the host's Docker log rotation (SSH; section 7).
- OP7: `get_match_history` scans every row on each call, and its totals stop at 10,000 (low; section 6).
- SP10 (update): the set of unformatted files has changed. Add gofmt to CI and `*.go eol=lf`.

claude-config:
- OP1: change `jq -c` to `jq -r` in `caddy-access-analytics.ps1:46-48`. The job has reported nothing real since
  10-01.
- OP3: exclude the smoke accounts from player-metrics-daily.

## Proposals (ranked by value / effort)

1. ST1 (cheap, high): compare overrides against `Settings.new()` defaults, advance sync-at from a successful save,
   and promote `h37-stats-ops/test_probe_settings_echo.gd` into `test/unit/`.
2. C7 (cheap, high): `include_filter="legal/*"` on the Web, Windows and Android presets, plus a check that an export
   holds the files (or move the text into a resource).
3. OP1 (one character, claude-config): `jq -r` in `caddy-access-analytics.ps1:46-48`; fix the stale comment.
4. OP3 / SP23 (cheap): nightly-smoke reuses one fixed `probe-`-prefixed device id, or deletes its account at the end.
5. CR6 (cheap-medium): an engine `Logger` that forwards errors to the reporter on the main thread and skips
   exit-time leak lines (H28).
6. S1 + OP2 + RT1 (medium): on a failed match_end write, return a retryable error and keep the registration (the
   writes are idempotent, S2); an hourly sweep of stale per-match rows that reports a "never ended" count; a probe
   variant that ends a match and reads the board.
7. OP6 (cheap): Grafana rules for Caddy 5xx and 429 rates and Nakama RPC errors.
8. C2 + H11 (cheap): legal guards in `sync-game-config.ps1`; `push: main` triggers on pr-validate.
9. CR1 (medium): flush synchronously on the server role before a fatal quit; record abnormal container exits.
10. RL3 (medium): a `BeforeWriteStorageObjects` allowlist with a size cap, plus a per-IP Caddy zone on `/v2/storage`
    and `/v2/rpc`.
11. L2 (cheap-medium): do not record guests on the board, or keep a listable-only board.
12. SP16 (cheap): invalidate the public cache on delete, ban and rename.
13. SP14 / RT2 (cheap): send `match_ready` and `match_failed` non-persistent, or prune them by age.
14. S11 (cheap): send the final stats snapshot reliably.
15. Tests (cheap): a `validateGameConfig` table test, `abortProtocolMismatch`, account_cron (RT4), a failing-write
    fake for S1.
16. A dev-stack Caddy (medium): lets local-smoke-test assert 429 bodies, CORS and log masking (RL5).
17. gofmt in CI plus `*.go eol=lf` (cheap, SP10).
18. S3 (cheap once a per-level board is wanted): report the real `level_id`.
19. CR7 (medium): a crash signal for web (a JS error hook) and Android.

## Runs

| Time | What | Result |
|---|---|---|
| 09:43 | runtime `go test` (matching tests) and `go vet ./...` | 98 PASS, 0 FAIL; vet clean (`h37-stats-ops/go-test.log`, `go-vet.log`) |
| 09:46 | GUT, 8 files, console exe, throwaway APPDATA (`run-gut.ps1`) | 106/106 pass: leaderboard data 13, leaderboard screen 8, My Stats 5, crash text 24, crash reporter 29, release values 2, device config 9, cloud sync 16 (`gut/*.log`) |
| 09:48 | ST1 probe `test_probe_settings_echo.gd` | preconditions pass; the two echo assertions fail, as ST1 predicts |
| 09:51, 10:12 | `gh run list` (pr-validate, nightly-smoke, game-server) | C1 and OP3 counts |
| 09:52-09:53 | unauthenticated GETs: version_check (two protocol values), public leaderboard (GET, OPTIONS, bad params) | sections 4 and 8; the board has 0 entries |
| 10:02 | `Resolve-DnsName` A and AAAA | A only (RL2) |
| 10:06 | jq `-c` vs `-r` repro | OP1 |
| 10:05-10:20 | claude-config job scripts and logs (aggregate lines only, IPs masked) | section 6 |
| 10:20 | `gofmt -l` on LF copies of the runtime HEAD blobs (`gofmt/`) | SP10 set |
| 10:27-10:37 | git history (reporter, game.yaml, game-server runs); byte search of `build/web/index.pck` (2026-07-16, Godot 4.7.1); greps | 2b update, C7, S11, CR6, CR7 |
| 10:44-10:55 | an edit one-liner overwrote this file (PowerShell variable names ignore case, so `$T` replaced `$t`); rebuilt from the session transcript and the fragment files in `h37-stats-ops/` (`recover-build.ps1`) | the rebuilt 10:43 version has the original's size, 70,171 bytes; then the SP22 wording fix |

Not run: the compliance suite, the `leaderboard-local-backend` scenario, anything that trips a Caddy limit, SSH or
login checks (see the summary).

Done 10:55.
