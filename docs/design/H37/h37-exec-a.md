# H37 exec-a: CI, platform suites, compliance, GUT

Started 2026-10-14 09:34:18 -07:00 (claude session 40ecd3b7, agent h37-exec-a).
Repos at: hopnbop 44f0093e, platform 8e85e8a, netcode 7d6ebd9.
Logs and scratch scripts: `.claude/probes/H37/h37-exec-a/`.

## Summary (ranked; details in the numbered sections)

Every suite at HEAD passes except three netcode tests: GUT unit 492/492 (45 files), integration
135/135 (16), compliance against a local Nakama 80/80 (35), runtime Go 181 tests + 225 subtests,
staticcheck clean. The import was clean and changed no tracked file. No file printed "Nothing was run".

1. **H11 still true, and wider:** PR Validate and Compliance Matrix have only ever run by dispatch.
   25 commits on main (`3b7f5743..9bbaa7ee`) were never CI-validated, among them the 0.54.0 release
   `8ca156e7` and its new test. My local runs cover them all and pass (§3, §6).
2. **Netcode `test_webrtc_signaling.gd` fails 3 of 12, deterministically.** Two fail on GUT 9.7.1's
   engine-error tracking, triggered by `JSON.parse_string`; one asserts the addon's 20 Hz default
   while hopnbop's config is 30 Hz. All three are inferred to be test bugs, not product bugs. No CI
   runs these tests (RN3), and they would turn RN3's proposed CI step red (§6c).
3. **Platform "Client SDK CI" runs no tests:** 63 green runs and zero tests. The SDK is tested only
   when someone dispatches hopnbop's Compliance Matrix (§3).
4. **H9 still true:** the "GDScript formatter" job passes while skipping, because the formatter is
   not vendored (§3).
5. **`release.yml` has never run, and no `v*` tag exists.** The tag-release path that CLAUDE.md's deploy
   table documents is unexercised (§3).
6. **`scripts/local-smoke-test.ps1` mutates the checkout it runs in:** it rmdirs and re-copies
   `addons/snoringcat_platform_client/` and runs `--import`. Its header says concurrent runs are fine,
   which holds only one per worktree (§5).
7. **SP10 still true, but its file list has drifted:** the five unformatted files are now
   friends_limits, helpers_test, local_allocator, main and party (§3).
8. **The platform CLAUDE.md "Testing" section is stale.** It says the runtime has no per-package unit
   tests, but it has 181 (§4).
9. **`staticcheck@latest` is unpinned** in `nakama-runtime.yml:44` (which gates the deploy) and in
   `pr-validate.yml:305` (§3).
10. **signaling-proxy and geoip-sidecar have no tests.** Vet is clean (§4).

## 1. Tools (observed 09:34)

| Tool | Result |
|---|---|
| `godot --version` | `4.7.2.stable.official.ed1daf0bf` (`C:\Program Files\Godot\godot.exe`) |
| `go version` | `go1.25.5 windows/amd64` |
| `gh auth status` | logged in (keyring), scopes `read:org, repo, workflow` |
| `docker info` | daemon NOT running at start (`npipe:////./pipe/dockerDesktopLinuxEngine` missing); Docker Desktop installed but not launched. Started it for step 5 (see there). |

Baseline `git status --short` before any step: ` M LEDGER.md` only (coordinator's edit, not mine;
it landed as 9bbaa7ee "ledger: H37 in progress" during step 2, so HEAD moved 44f0093e -> 9bbaa7ee,
ledger-only, same code).

## 2. Prepare and import (observed 09:35-09:36)

- `scripts/setup-platform-addon.ps1`: exit 0, 133 files copied. Before running it, the gitignored
  `addons/snoringcat_platform_client/` already matched the submodule byte for byte (MD5 compare, 0
  differences), so no SDK drift on this machine.
- `godot --headless --path . --import` (script: `h37-exec-a/import.ps1`, throwaway APPDATA): exit 0
  on attempt 1 in 17 s (`.godot/` already existed from 2026-10-11, so incremental). No crash, no
  retry. `GutTest` registered in `.godot/global_script_class_cache.cfg`.
- Tracked files changed by the import: **none** (`git status --short` clean, submodules clean).
- Import stderr (`h37-exec-a/import-1.err.log`), all non-fatal:
  - `ERROR: Unrecognized UID: "uid://ixpa4aivrfqd"`: that UID is `default_bus_layout.tres:1`,
    referenced by `project.godot:27` (`buses/default_bus_layout`). Believed benign: the editor reads
    project settings before the UID cache loads. It does NOT recur in GUT processes (no `UID_WARN`
    flag in the GUT summaries below), so runtime bus loading is not affected.
  - `ERROR: Can't save resource to empty path` (source not identified; one line, no effect seen).
  - `WARNING: Detected another project.godot at res://addons/rollback_netcode/examples/simple_game`
    (expected; the folder is ignored).
  - exit-time leak warnings (25 ObjectDB instances, 15 resources): usual for headless runs.
- `.claude/probes/H37/import.done` written 09:36:19.

## 3. CI (observed 09:37-09:40 via `gh run list -L 200`; raw JSON in `h37-exec-a/ci/`)

Remotes: `SnoringCatGames/hopnbop`, `SnoringCatGames/snoringcat-platform`,
`SnoringCatGames/godot-rollback-netcode` (gh's full history: 180 / 200+ / 26 runs; hopnbop's oldest is
2026-05-22). Times UTC.

### Newest run per workflow on main

| Repo | Workflow | Triggers (`on:`) | Newest run on main |
|---|---|---|---|
| hopnbop | PR Validate | pull_request, workflow_dispatch | 2026-10-12 21:10 dispatch, success (38308919181) |
| hopnbop | Compliance Matrix | pull_request, workflow_dispatch | 2026-10-12 21:10 dispatch, success (38308922584) |
| hopnbop | Nightly Smoke | schedule 03:00 UTC, dispatch | 2026-10-14 03:01 schedule, success (38504112263) |
| hopnbop | Game Server Deploy | workflow_dispatch only | 2026-10-12 21:57 dispatch, success (38313778919) |
| hopnbop | Release | push tags `v*.*.*`, dispatch | **never run** (0 runs in gh history; no `v*` tag exists on the remote, only `pre-platform-extraction`) |
| platform | Client SDK CI | push main + PR (SDK paths) | 2026-10-12 21:43 push, success (38312437807) |
| platform | Nakama Runtime Deploy | push main (`runtime/**`), dispatch | 2026-10-12 21:43 push, success (38312437743) |
| netcode | Parse check | push main, PR | 2026-10-14 16:19 push, success (38597118795) |

Stale entries in gh's list (no workflow file any more): hopnbop "Nakama Runtime Deploy" (last
2026-05-22) and platform "Synthetic monitor" (99 schedule runs, last 2026-05-03, failure; the AWS-era
monitor retired at Phase F). Game Server Deploy's 4 `push` failures are from 2026-06-01, when it still
had a push trigger.

### Failures in the last two weeks (since 2026-09-30)

All five were on 2026-10-11/12 during session 530145bc's fixes, each followed by a green run; none
is open now.

| Run | Workflow | Failed step |
|---|---|---|
| 38165736527 (10-11 18:53) | PR Validate | GUT unit + integration > Initialize containers |
| 38172690365 (10-11 20:33) | PR Validate | GUT unit + integration > Run GUT (per-file) |
| 38185533488 (10-11 23:46) | PR Validate | Export smoke > Export Web and Linux server |
| 38190186583 (10-12 01:00) | Compliance Matrix | Run local smoke test |
| 38197711586 (10-12 02:55) | Compliance Matrix | Run local smoke test |

### PR/dispatch-only workflows (H11): still true

- PR Validate (14 runs) and Compliance Matrix (10 runs) have only ever run by `workflow_dispatch`;
  work lands straight on main, so `pull_request` never fires. Last runs 2026-10-12 21:10 on
  `f4a6eead` (pre-sweep SHA of `3b7f5743`).
- **25 commits on main have never been validated** (`3b7f5743..9bbaa7ee`), including the 0.54.0
  release commit `8ca156e7` (src/core/settings.gd, global.gd, project.godot, game.yaml,
  settings.tres, and a new test file `test/unit/core/test_settings_release_values.gd` that CI has
  never run), the Android preset `4c04e908`, and `88e3089b` "Update settings" (settings.tres).
  Verified: my per-file GUT run below covers them locally.
- The platform side of those 25 commits is content-identical to what the last green runs checked:
  the pin at `3b7f5743` is `e6a47f6` (pre-sweep SHA, not an ancestor of platform HEAD), and
  `git diff --stat e6a47f6 HEAD -- runtime infra addons` in the platform is empty. All 7 jobs of
  those runs passed (38308919181: formatter, export smoke, Pulumi compile, parity, GUT, runtime Go;
  38308922584: compliance).
- Game Server Deploy and Release are dispatch/tag only by design.

### Other CI findings

- **Platform "Client SDK CI" runs no test.** Verified by reading
  `snoringcat-platform:.github/workflows/client-sdk-ci.yml`: its only job downloads Godot, prints
  `godot --version`, and emits a `::notice::` that the compliance suite runs in the consuming game.
  63 green push runs, zero tests executed. So an SDK change pushed to the platform repo gets no
  automated test until someone dispatches hopnbop's Compliance Matrix (dispatch-only, see H11).
- **H9 still true** (observed): PR Validate's "GDScript formatter" job is green while checking
  nothing. Its log in 38308919181 says `gdscript_formatter not vendored; skipping`
  (`pr-validate.yml:40-44`), and `addons/gdscript_formatter/` does not exist.
- Platform runtime Go checks do run on every `runtime/**` push (`nakama-runtime.yml:31-45`: vet,
  test, staticcheck, gate the deploy). The last one covered runtime commit `c4c74139`; only a ledger
  commit (`8e85e8a`) follows it. hopnbop's `pr-validate.yml:288-306` repeats them (dispatch-only).
- `staticcheck@latest` is unpinned in both workflows (`nakama-runtime.yml:44`,
  `pr-validate.yml:305`): a new staticcheck release can turn the runtime deploy red with no code
  change. Low.
- Platform CLAUDE.md "Code Style" says runtime Go is "gofmt ... clean (the nakama-runtime workflow
  runs both)". False: no workflow runs gofmt, and 5 of 49 runtime files are not gofmt-clean at HEAD
  (checked on the LF blobs, since `core.autocrlf=true` makes every working-tree file look dirty):
  `friends_limits.go`, `helpers_test.go`, `local_allocator.go`, `main.go`, `party.go`
  (field alignment and doc-comment indentation; cosmetic). Low.
- Submodule pins equal their remotes' main: platform `8e85e8a`, netcode `7d6ebd9`.

## 4. Platform Go suites (observed 09:40-09:41, Go 1.25.5 local; CI pins 1.23)

| Module | go vet | go test | Notes |
|---|---|---|---|
| `runtime` | exit 0 | exit 0, 1 package, **181 top-level tests + 225 subtests pass, 0 fail, 0 skip** (0.9 s) | `staticcheck` 2026.2.1: exit 0, clean |
| `infra/remote/signaling-proxy` | exit 0 | exit 0, `[no test files]` | no tests at all |
| `infra/remote/geoip-sidecar` | exit 0 | exit 0, `[no test files]` | no tests at all |
| `infra/pulumi/snoringcat-platform` | not run | not run | CI only builds it (`pr-validate.yml:308-320`). Skipped (large module download); unchanged since b8f8963 (2026-06-14) and "Pulumi project compile" passed in 38308919181 on identical content |

Logs: `h37-exec-a/go-*.log`, `staticcheck-runtime.log`. Platform CLAUDE.md "Testing" says the runtime
is "currently smoke-tested via the live runtime_status probe ... rather than per-package unit tests";
stale: 21 `*_test.go` files hold 181 tests against 28 source files.

## 5. Compliance suite against a local Nakama (observed 09:43-09:44, under net.lock)

`pwsh scripts/local-smoke-test.ps1 -LogDir .claude/probes/H37/h37-exec-a/smoke`: **exit 0 in 79 s.
"Tests: 80 declared, 80 reported, 80 passed, 0 failed, 0 pending/other"; "OK: compliance suite
green against the local stack."** Plugin built with `nakama-pluginbuilder:3.25.0`; compose project
`hopnbop-smoke-20261014-094315-5548` on free ports; torn down afterwards (no containers left;
verified with `docker ps -a`). Per file (`smoke/results.xml`), all 0 failures, 0 skipped:

account 2, account_delete 4, account_delete_cascade_surfaces 1, admin_key 4, api_surface 2,
auth_anon 3, auth_link 2, crash_report 6, data_export 3, email_privacy 4, friends 2,
friends_account_delete_cascade 1, friends_block 2, friends_multiuser 1, match_loopback 4,
matchmaking 1, matchmaking_cancel_race 2, matchmaking_failure_modes 1, party 1, party_invite_flow 1,
party_to_matchmaking 1, player_stats 3, presence 2, presence_game_filter 1, presence_status 2,
public_leaderboard 3, recent_players 2, settings 1, socket_auth 2, socket_chat 1,
socket_matchmaker 1, socket_presence 2, token_refresh 3, transport_selection 5, version 4
(35 files, 80 tests).

- stderr has one `Invalid status code. Got: '401', expected '101'` (believed: the socket-auth test's
  deliberate rejected handshake) and exit-time leak warnings. No `SCRIPT ERROR`.
- The suite runs in one process with `-gdir`, the mode CLAUDE.md calls unreliable for discovery;
  the script guards it by comparing declared `func test_` counts with reported results (80 = 80).
- **Side effect on a shared checkout (testability finding):** the script re-runs
  `setup-platform-addon.ps1` (`rmdir /S /Q` + `xcopy` of `addons/snoringcat_platform_client/`) and
  `--import` in the working tree (`local-smoke-test.ps1:305-313, 400-414`). Its header says "Several
  runs can go at once (one per agent or worktree)", but two runs, or any Godot process starting in
  the same checkout during the ~1 s delete/copy window, can find the Platform autoload missing. This
  run did that at 09:43:15-09:43:20, when other H37 agents may have been running Godot (not checked); any odd
  autoload/parse failure they saw at that minute is mine. Safe only per worktree.

## 6a. GUT unit, per file (observed 09:36-09:42)

Runner `h37-exec-a/run-gut.ps1` mirrors `pr-validate.yml:177-238`: one Godot process per file,
`-gexit`, `-gpost_run_script=res://test/hooks/fail_on_nakama_traffic.gd`, 300 s timeout, and an
empty user:// per file (fresh `$env:APPDATA`; CI uses `XDG_DATA_HOME`). Ran concurrently with other
agents' Godot processes. Results: `h37-exec-a/gut/unit/summary.tsv` and per-file logs.

**45 files, 492 tests, 492 passing, 0 failing, 0 pending; every exit 0.** No file printed "Nothing
was run", none ran zero tests, none tripped the NAKAMA TRAFFIC hook, no `SCRIPT ERROR` or
`Parse Error` in any log. Total 322 s (6-9 s per file, nearly all of it engine boot).

Per file (tests/passing/failing/pending), all under `test/unit/`:

| File | T/P/F/Pe | File | T/P/F/Pe |
|---|---|---|---|
| character/test_bump_reconciliation | 16/16/0/0 | platform/test_auth_api_client_privacy | 10/10/0/0 |
| character/test_character_state_from_server_caching | 1/1/0/0 | platform/test_auth_api_client_refresh | 17/17/0/0 |
| character/test_forwarded_player_input_from_server | 11/11/0/0 | platform/test_auth_screen_resume | 7/7/0/0 |
| character/test_invincibility_through_bounces | 7/7/0/0 | platform/test_client_http_key | 6/6/0/0 |
| character/test_player_input_from_client_validation | 3/3/0/0 | platform/test_consent_retention | 12/12/0/0 |
| core/test_auth_file_isolation | 2/2/0/0 | platform/test_friends_api_client | 13/13/0/0 |
| core/test_crash_report_text | 24/24/0/0 | platform/test_friends_notification_contract | 4/4/0/0 |
| core/test_crash_reporter | 29/29/0/0 | platform/test_friends_notification_poller | 26/26/0/0 |
| core/test_disconnect_handling | 9/9/0/0 | platform/test_friends_poller_lifecycle | 12/12/0/0 |
| core/test_leaderboard_data | 13/13/0/0 | platform/test_nakama_matchmaker_client | 28/28/0/0 |
| core/test_match_state_get_player_score | 6/6/0/0 | platform/test_party_api_client | 11/11/0/0 |
| core/test_match_state_interaction_deduplication | 11/11/0/0 | platform/test_party_leave_contract | 2/2/0/0 |
| core/test_matchmaking_session_failures | 11/11/0/0 | platform/test_party_manager | 31/31/0/0 |
| core/test_player_id_format | 19/19/0/0 | platform/test_party_matchmaking_context | 11/11/0/0 |
| core/test_preview_session_provider | 5/5/0/0 | platform/test_platform_nakama_logging | 2/2/0/0 |
| core/test_settings_release_values | 2/2/0/0 | platform/test_settings_cloud_sync | 16/16/0/0 |
| core/test_sign_out_router | 16/16/0/0 | player/test_costume_overlays | 2/2/0/0 |
| i18n/test_translation_csvs | 16/16/0/0 | scaffolder/test_scaffolder_log | 2/2/0/0 |
| input/test_device_config | 9/9/0/0 | ui/test_export_data_row | 4/4/0/0 |
| input/test_input_device_manager | 18/18/0/0 | ui/test_leaderboard_screen | 8/8/0/0 |
| input/test_text_input_row | 9/9/0/0 | ui/test_my_stats_screen | 5/5/0/0 |
| networking/test_network_connector | 8/8/0/0 | ui/test_player_display | 14/14/0/0 |
| networking/test_reconcilable_networked_state_three_nodes | 4/4/0/0 | | |

- H35 (party_matchmaking_context bleed in directory runs): per file it passes 11/11, as expected.
- `core/test_settings_release_values.gd` (new in the never-CI-validated 0.54.0 commit) passes 2/2.

## 6b. GUT integration, per file (observed 09:44-09:47, under net.lock)

Same runner, `-Tag integration -Roots test/integration`; lock released 09:48:02.
**16 files, 135 tests, 135 passing, 0 failing, 0 pending; every exit 0;** no flags (no
"Nothing was run", no zero-test file, no NAKAMA TRAFFIC, no `SCRIPT ERROR`/`Parse Error`). 6-14 s
per file. Results: `h37-exec-a/gut/integration/summary.tsv`.

| File (under `test/integration/`) | T/P/F/Pe | File | T/P/F/Pe |
|---|---|---|---|
| full_flow/test_lobby_to_networked_transition | 8/8/0/0 | multiplayer/test_multi_player_rollback | 6/6/0/0 |
| gameplay/test_death_respawn_visuals | 6/6/0/0 | multiplayer/test_player_collision_interactions | 15/15/0/0 |
| input/test_lobby_level_spawning | 18/18/0/0 | multiplayer/test_rollback_flow | 10/10/0/0 |
| multiplayer/test_character_rollback | 21/21/0/0 | multiplayer/test_spring_invincibility | 3/3/0/0 |
| multiplayer/test_edge_cases | 7/7/0/0 | multiplayer/test_state_synchronization | 10/10/0/0 |
| multiplayer/test_forwarded_input_flow | 7/7/0/0 | networking/test_multi_player_declaration | 6/6/0/0 |
| multiplayer/test_frame_synchronization | 5/5/0/0 | networking/test_pause_synchronization | 4/4/0/0 |
| multiplayer/test_invincibility_gore_and_flies | 4/4/0/0 | networking/test_webrtc_connection | 5/5/0/0 |

Engine errors in the unit + integration logs that failed no test. GUT 9.7.1 fails a test on an
engine error raised inside its body (default `failure_error_types = ["engine", "gut", "push_error"]`,
`addons/gut/gut_config.gd:57`), but tracking starts only after `before_each()`
(`addons/gut/gut.gd:612-627`, read):
- `ERROR: There is no animation with name 'Rest'` 37x (player_collision_interactions 26,
  forwarded_input_flow 7, player_input_from_client_validation 3, character_state_from_server_caching 1),
  from `src/scaffolder/character/character.gd:292` (`_ready` plays "Rest"). The real
  `src/player/bunny_animator.tscn:411` defines "Rest", so believed: test fixtures build Characters
  whose AnimatedSprite2D lacks the animation, in setup, outside the tracked window. Noise, not a game
  bug.
- Every file ends with exit-time leak reports (195-305 ObjectDB instances, RIDs, "resources still
  in use"). Believed: GUT/engine shutdown noise; not investigated.
- The rest are warnings the tests provoke on purpose (auth refresh retries, a malformed fixture CSV).

## 6c. Netcode addon GUT, per file (observed 09:48-09:50)

The addon has no project of its own that runs its tests (`.github/parse-check/` skips `test/`, RN3),
so they ran inside hopnbop with the same runner: `-Tag netcode -Roots addons/rollback_netcode/test`.
**9 files, 211 tests, 208 passing, 3 failing, 0 pending.** Eight files exit 0;
`test_webrtc_signaling.gd` exits 1. A rerun at 09:50 failed identically (deterministic).
Results: `h37-exec-a/gut/netcode/summary.tsv`, `h37-exec-a/gut/netcode-rerun/`.

| File (under `addons/rollback_netcode/test/unit/`) | T/P/F/Pe | File | T/P/F/Pe |
|---|---|---|---|
| test_array_pool | 13/13/0/0 | test_send_rate | 21/21/0/0 |
| test_circular_buffer | 47/47/0/0 | test_split_packed_state | 15/15/0/0 |
| test_frame_driver | 32/32/0/0 | test_state_bundler | 15/15/0/0 |
| test_reconcilable_state | 36/36/0/0 | **test_webrtc_signaling** | **12/9/3/0** |
| test_rollback_buffer | 20/20/0/0 | | |

Failures, all in `netcode:test/unit/test_webrtc_signaling.gd`:

1. `test_invalid_message_type_ignored` (line 154) and 2. `test_empty_string_returns_empty_dict`
   (line 164): `[Failed]: Unexpected Errors: [1] <engine-0>Condition "error != Error::OK" is true.
   Returning: Variant()`; stderr `Parse JSON failed. Error at line 0: Expected 'true', 'false', or
   'null', got 'not'` and `... Unknown error getting token`. Their own asserts (empty dict) pass.
   Inferred cause: `WebRTCSignalingServer.parse_message` calls `JSON.parse_string(text)`
   (`netcode:core/webrtc_signaling_server.gd:600`), which raises an engine error on malformed input,
   and GUT 9.7.1 counts that as a failure. Behavior is right; the tests were never run under this
   GUT. Fix either side: `JSON.new().parse()` (returns an Error, raises nothing) or
   `assert_engine_error(...)` in the tests (`addons/gut/test.gd:2348`). `parse_message` has no caller
   outside tests in netcode, hopnbop `src/`/`scripts/` or the platform (git grep), so production is
   unaffected.
3. `test_webrtc_send_rate_default` (line 242): `[30.0] expected to equal [20.0]: Default WebRTC
   send rate should be 20 Hz` (line 243). Inferred cause: the test reads the live
   `Netcode.settings`, which inside hopnbop is the game's resource: hopnbop `settings.tres:152` sets
   `webrtc_state_send_fps = 30.0` (since 8abb1f39, 2026-03-24), while the addon default is 20.0
   (`netcode:core/network_settings.gd:91`). It asserts the addon default through a consumer's config,
   so it cannot pass in hopnbop. Not a product bug; assert on a fresh `NetworkSettings.new()`.

All three would turn RN3's proposed CI step red on day one: fix them before wiring the tests in.

## 7. Verdicts on ledger items touched

- **H11** (hopnbop): still true, now covering 25 commits, including the 0.54.0 release (§3).
- **H9** (hopnbop): still true (observed in the log of 38308919181) (§3).
- **H35** (hopnbop): per file, `test_party_matchmaking_context.gd` passes 11/11, as expected. The
  full-directory bleed was not rerun, since per file is how CI runs it.
- **SP10** (platform): still true. The list is stale: runtime_status, player_data and
  per_game_config are now clean, while helpers_test, local_allocator and party are new.
- **RN3** (netcode): still true. Three failing tests have to be fixed first (§6c).
- TODO-scratch notes: none are assigned to h37-exec-a.

## 8. Not checked

- The Pulumi module's local vet and build: skipped because of the download size. CI built it green on
  identical content (§4).
- H35's full-directory run, and any of these suites on Linux. Every local run was on Windows; CI
  runs on Ubuntu.
- The netcode tests in a neutral project: none exists, so test 3's verdict is inferred.
- Google sign-in: it needs a browser and production, which the rules forbid.
- gh's run history for hopnbop starts at 2026-05-22.

## 9. Ledger items (proposed; the coordinator files them)

- hopnbop H11: update the count to 25 unvalidated commits, including 0.54.0 `8ca156e7`.
- netcode (new): `test_webrtc_signaling.gd` has 3 failures. Two need `JSON.new().parse()` or
  `assert_engine_error`; one should assert on `NetworkSettings.new()`. This blocks RN3 (§6c).
- platform (new): Client SDK CI runs no tests. Either run the compliance suite there, or rename the
  job so its green check doesn't read as tested.
- platform SP10: update the file list (§7).
- platform (new, residual): the CLAUDE.md "Testing" section is stale (181 runtime unit tests).
- platform + hopnbop (new, low): pin staticcheck (`nakama-runtime.yml:44`, `pr-validate.yml:305`).
- hopnbop (new): `release.yml` has never run and no `v*` tag exists. Exercise it once, or mark it
  unused in CLAUDE.md's deploy table.
- hopnbop (new, residual): `local-smoke-test.ps1`'s "several runs at once" holds only per worktree,
  because it rewrites the addon copy and re-imports the shared checkout.
- platform (idea): signaling-proxy and geoip-sidecar have no tests.
- hopnbop (idea, low): test fixtures log "no animation 'Rest'" 37 times per full run (§6b).

Done 2026-10-14 09:53:16 -07:00

