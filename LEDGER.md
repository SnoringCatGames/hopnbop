# Hop'n'Bop ledger

Open work for hopnbop: follow-ups, known residuals, decisions waiting on
Levi, and ideas. Convention: claude-config `rules/ledger.md`. IDs (`H<n>`)
are stable and never reused. Platform items (SDK, runtime, prod host
scripts) live in `third_party/snoringcat-platform/LEDGER.md`.

Session pointers name their tool: "claude session 530145bc" refers to
Claude Code transcripts under `~/.claude/projects/` (kept 30 days),
"muse session 01a1390a" to Muse transcripts under
`~/.local/share/muse/sessions/`. Each item states its facts, so it
stands on its own after the transcript is gone.

Items stay short (the diet, claude-config CC64, 2026-10-15): one to three lines; an
In progress handle is its six fields, one line each; a Done entry is
one line, `- **H<n>** · <what>. Done in <commit> (<date>).` Shortened
items keep their full text in `docs/ledger_notes.md`, and older Done
entries move to `docs/ledger_done.md`; the next ID counts both files.

## Urgent


## Waiting on Levi

- **H92** · One 2-client networked session with Levi (T02 to T07, T16,
  T25, T27, T29) (S; batch 7; `docs/design/H37_systems_audit.md` section
  5 row 3, section 7 row 9)
- **H71** · Decoupling: which seams to build (decision;
  `docs/design/H37_systems_audit.md` 1.3, section 7 row 6)
- **H122** · Two look questions from H118's foreground-depth fix:
  match-end confetti now passes behind the lobby cave wall (Claude
  has asked), and gore now passes under the lobby landmarks
  (Title, ControlDisplays, AwardPodium). Pairs and inventory:
  `.claude/probes/H118/inventory.md`.
- **H102** · Real account merge for the PROVIDER_CONFLICT case: since H62 the game tells the player instead. Merging two accounts' stats/friends/boards is a platform feature; needs Levi's call on whether 'tell' is enough. (L)

## In progress

- **H104** · Claude reviews Muse's commits from H103 and H109 in three
  stages: security (SP32, SP33, SP36, SP41 to SP44, SP47, SP59, H60),
  then H109's Tier C, then its Tier D design docs. Reviewed 2026-10-29:
  the CI fixes (8bb5873, c1590c7, netcode 9c3c0b5) and H56's keyboard
  (H111, H112).
  - owner: claude 0cfd9cf1 (stage 1 done 2026-10-30 08:02; its findings are SP83-SP94 and H113-H117, and the fixes run as H120)
  - branch: mainline, read-only (the review makes no commits); the
    brief was committed with this entry
  - evidence: `.claude/probes/H104/stage1-A.md` and `stage1-B.md` (untracked, on the desktop only)
  - next: review H120's commits as they land; stages 2 and 3 after the weekly usage reset (2026-11-02)
  - brief: `docs/design/H104_review.md`
- **H120** · Muse run 3: the fixes from H104's stage 1 review and Levi's
  2026-10-30 playtest (SP83's patch, H119, H118, SP84, H113, SP85, SP86
  with H114, SP87, SP88, SP89 with H115, H116 and SP90, then SP91).
  - owner: muse 01a189f7-97c5-7eb0-98b6-164cb9977b39, launched by claude 0cfd9cf1 through Paseo on 2026-10-30
  - branch: mainline; last commit: this one
  - evidence: `.claude/probes/H104/` (the stage 1 reports, untracked; SP83's patch goes in `F18/`), and `.claude/probes/<ID>/` per item
  - next: SP83's patch, then H119
  - brief: `docs/design/H120_muse_run3.md`

## Next

- **H56** · Controller players cannot enter codes: design in
  `docs/design/H56_code_entry.md`; the symbol keyboard is built
  behind `is_code_keyboard_enabled` (off) for Levi's acceptance.
  The Join-with-code and delete-key icons are still to ask Levi for.
- **H87** · A dedicated server's fatal error or engine crash is never
  reported (CR1, CR7): design in
  `docs/design/H87_server_crash_reporting.md`, awaiting Levi.
- **H77** · Land the H37 probes as tests, each with its fix (XS each;
  batch 6; `docs/design/H37_systems_audit.md` section 4 step 2)
  Landed 2026-10-29: ghost-ticket probe (SP28), account probe
  DEL-2 (SP41) and LK-1 (SP43), account PI-1 (H60), social probe
  (SP35). Still blocked on fixes outside this run: settings-echo
  (H67), declare-validation (H17), port-leak Go test (SP26),
  account PI-2 and SO-1 (H15), verify scenarios (H72 held).
- **H72** · Exported-build runs for the harness: design in
  `docs/design/H72_exported_build_harness.md`, awaiting Levi.
  H38's release check waits on it.
- **H83** · `release.yml` has never run and no `v*` tag exists. Waits on
  Levi (report section 7 row 13) (S; batch 6;
  H113's avatar checks reach players with this release
  (client and game-server image);
  post-release check: a player signed in with Facebook sees
  their avatar load (confirms the provider's picture URL
  serves the image to this client, possibly over one redirect);
  `docs/design/H37_systems_audit.md` 1.1)

- **H93** · The overhead label offset (T29). After H92 (S to M; batch 7;
  `docs/design/H37_systems_audit.md` section 5 row 4)
- **H91** · A short input grace on the game-over screen (T79). After H92
  (M; batch 7; `docs/design/H37_systems_audit.md` section 5 row 5)
- **H94** · A controller pass by hand, with two local players (T45, T08,
  T09) (S; batch 7; `docs/design/H37_systems_audit.md` section 5 row 6)



- **H98** · Finish T43; verify, then fix, T19: design in
  `docs/design/H98_polish_and_player_list.md`, awaiting Levi.
- **H115** · SP41 client follow-ups: an expected delete failure logs
  through `G.log.error`, which files a crash report each time (log a
  warning); add the no-session case; make the verify2 panel probe a test
  (H104 1A SP41-1, SP41-4).
- **H116** · `test_auth_store_migration.gd` lacks three cases (H104 1A
  SP44-5).
- **H117** · SP32 client half, for when the consent change ships: show
  pending invites, accept and decline (H104 1A SP32-3).
- **H119** · Holding A starts left movement for an instant, then it
  stops (Levi, playtest 2026-10-30).
  Harness diagnosis 2026-10-30 (`.claude/probes/H119/`): not
  reproduced. Holding A moves at full speed until level geometry
  stops it: offline level, lobby after the join panel opened and
  closed, and lobby after typing a code on the H56 keyboard and
  closing. Back to Levi via Claude: does it happen with kanata
  off, and with the Left arrow?


## Residuals (known, not fixed)

- **H121** · The pending-deletion prompt (ConfirmOverlay from
  `AccountDeletionPrompt`) renders without a panel: its message
  wraps two to four words per line and runs over the lobby's key
  hints. Seen in the released client during SP84's check
  (`.claude/probes/SP84/06-cancel-prompt.png`) and confirmed at
  HEAD 2026-10-30 (`.claude/probes/SP84/head-cancel-prompt.png`).
  Not fixed in run 3.
- **H110** · The Compliance Matrix run on H26 (02e1d75a, run
  40991959543) failed when Docker Hub returned 502 Bad Gateway
  pulling `heroiclabs/nakama` during `docker compose up` in the
  local smoke step. That pull has no retry (H107 added one for
  PSGallery, not here). The run passed on the next commit.
- **H7** · The check that keeps new spawns off other players can't see
  bunnies that are still blinking, so a respawn can land on one. Left
  alone as a player-versus-player rule.
- **H10** · Android: run the game on the Pixel. Export preset done in
  4c04e908 (`--export-debug "Android" build/android/hopnbop.apk`
  builds). Left: install over USB, then a touch-input pass.
- **H28** · About half of lobby runs log an `AudioStreamWAV`
  (`pause_menu.wav`) leak warning at exit, before and after the
  PerfTracker fix; noted in CLAUDE.md; see H86 (CR6).

- **H32** · Anonymous players only get a session once they go online, so
  an offline-only player's crash reports expire unsent after 7 days.
  (Crash agent a1d23375.) H37 (10-14): still true.
- **H52** · Inert `game.yaml` `matchmaker_rules` fields
  (`ticket_expiry_seconds`, `cross_play`, `rules`): delete or wire them,
  fix the comment (XS; batch 3; `docs/design/H37_systems_audit.md` 3.3)
- **H80** · `foobar.png` once T14 is answered (the orphaned textures
  and `.import` files landed in 141e2fe)
- **H105** · Nothing prunes superseded game-server images on the prod
  host: disk +1.72 GB on 10-20 (v30, v31 pulled by `sync-game-config.ps1`),
  +0.86 GB on 10-13. Run `docker system df` there, then add a prune
  (weekly-cost-review 2026-10-21).
- **H106** · Local mode also logs "RPC on yourself is not allowed" for
  `_rpc_server_update_critter_stats` (seen in an offline-move-jump log,
  2026-10-29; not one of H27's named pair). Same fix shape when touched.


## Ideas (not scheduled)

- **H33** · An optional `occurred_at` on crash reports, clamped
  server-side, would date reports that sat queued for days. Needs a
  privacy-text check first. (Agent a1d23375.)
- **H76** · More than 2 clients and gamepad input in the harness (M to
  L; `docs/design/H37_systems_audit.md` section 4 step 7)
- **H78** · Golden screenshots (build item 7) (M;
  `docs/design/H37_systems_audit.md` 2.2, section 4 step 7)
- **H100** · Level art (T15, T28, T14) (L each;
  `docs/design/H37_systems_audit.md` section 5)

## Done

- **H114** · Followers act on any party start message: check it names their current party and that they are ready (`src/core/party_manager.gd:794`) (H104 1A SP33-G). Done in 3238dfd3 (2026-10-30).
- **H113** · Avatar URLs are parsed strictly and matched to exact provider hosts on the client, and the game server drops a declared URL that fails the same check instead of relaying it; redirects follow one checked hop and declared image dimensions are capped. Done in f4420f8, 3495f67e, 1d359bda, platform bade4f3, 10af8b1, 7e20229 (2026-10-30).
- **H118** · Squish sprites (and gore at z 2) drew in front of the foreground art. Squish remnants now sit in the characters' draw band, and the scenes carry the foreground depth themselves (art z 10, lobby landmarks z 11), so effects pass under the art. Done in 1bf5612, af62e37 (2026-10-30).
- **H109** · Muse run 2 (H103's follow-ups, then the Tier C and D work Levi released) is complete. Its leftovers have their own items: H56, H72, H87 and H98 for Levi, and H104 for Claude's review. Done in 9f74eaf (2026-10-29).
- **H112** · A complete code focused one row down instead of Join; the panel now focuses `_join_row` on `input_complete` via `SidePanel.focus_row`. Panel tests cover keyboard and field entry, keyboard on and off; the H56 probe asserts focus after the last symbol. Done in 2506f61 (2026-10-29).
- **H111** · H56's keyboard could not enable Join: `set_text` assigned `LineEdit.text`, which emits no `text_changed`; it now runs `_on_text_changed` with the caret at the end. Panel test types a code and checks Join; the H56 probe types one with direction taps. Netcode half restored the unpause doc line and a final newline. Done in 4533cb4, netcode 7c58d2c (2026-10-29).
- **H86** · Engine and script errors reach the crash reporter once per signature (warnings and exit noise skipped); SP61 split the server cap first. Done in 57c41d3, platform e5ae4e6 (2026-10-29).
- **H90** · Failed cloud saves retry (permanent rejections do not) and settings merge per key. Done in ad7de6a, guards fix c1590c7 (2026-10-29).
- **H54** · The notification poll froze on the oldest 50 rows; cursor poll, socket-down only, persisted dedup, server prune (SP40). Done in c0d07f1, platform 078d9b8 (2026-10-29).
- **H26** · Respawned levels got auto-generated names and replication errors; spawns now get unique names. Done in 02e1d75 (2026-10-29).
- **H5** · Podium bunnies never animated: a stopped animator swallowed the delayed replay, and the paused tree froze the rest. Done in b1c1149 (2026-10-29).
- **H61** · Avatars from an earlier match showed on the wrong players; the cache now binds images to their URL. Done in 93b1951 (2026-10-29).
- **H89** · The final match stats rode one unreliable RPC; the final snapshot has a reliable twin. Done in b42c94d (2026-10-29).
- **H22** · Log-out waited out the offline notice on dead connections; it no longer waits. Done in 85fa622 (2026-10-29).
- **H88** · Nightly smoke left a new account every run; it reuses one probe account now. Done in 3acabe8 (2026-10-29).
- **H9** · The no-op GDScript formatter CI job is deleted; no formatter is vendored. Done in 49143fb (2026-10-29).
- **H8** · Spawned players entered the tree at the origin for one tick; they are positioned before `add_child` now. Done in 005e823 (2026-10-29).
- **H6** · Splashes and landing skids fired twice per transition; effects now consume each transition once. Done in 1f1ff5d (2026-10-29).
- **H24** · Server registered players under id 0 before assigning the real id; registration now waits for the id. Done in fc90a3c (2026-10-29).
- **H108** · Released client's suite against HEAD's runtime, locally and as the `compliance-released` CI job (76/80; 4 intended failures). Done in c11191e8, 51d7eb8b (2026-10-29).
- **H107** · Compliance Matrix's two failures: PSGallery retry and deterministic `PLATFORM_GAME_ID` (detail in `docs/ledger_notes.md`). Done in 73159cda (2026-10-29).
- **H103** · The Muse backlog run (`docs/design/H103_muse_backlog.md`): Tiers 0 to 6 landed except SP32's runtime half, SP59's Caddy zone and HG1 (now in hex-grid's ledger); the review is H104. Done in 9fc089ef (2026-10-29).
- **H80** · Textures orphaned by b998107d, plus orphan `.import` files including `level_4_combined*.png.import`. Done in 141e2fe (2026-10-29).
- **H97** · Finish T12; delete the 9 Stale notes (with SP53). Done in eb80b83, platform 1caaf04 (2026-10-29).
- **H96** · Alt+Enter fullscreen (T10). Done in 850c5ac (2026-10-29).
- **H95** · A click sound on every MenuRow trigger (T42). Done in 97805e5 (2026-10-29).
- **H29** · Unused code: `BinaryToggle`, and `fetch_player_stats`, `fetch_match_history` and their signals. Done in 6c5974b (2026-10-29).
- **H66** · V17: 22 broken format strings, 17 here; RN7 and SP49 held the rest. Done in b5f6446, netcode a7b001d, platform 6987291 (2026-10-29).
- **H18** · Raw SDK error text reached players in party, delete, export and friends toasts. Done in 9da8a21 (2026-10-29).
- **H31** · The credits screen's labels lacked translation keys, so other locales showed English. Done in 9da8a21 (2026-10-29).
- **H19** · After a recoverable matchmaking failure the loading screen offered only "Try Again", with no way back to the lobby. Done in 70f4742 (2026-10-29).
- **H21** · A party follower whose join failed got two toasts for it. Done in 9368b7a (2026-10-29).
- **H63** · The Log Out row was hidden when the access token had expired. Done in 3600938 (2026-10-29).
- **H27** · Local mode logged "RPC on yourself is not allowed" for `_server_rpc_ping` and `_rpc_init`. Done in netcode d13ec20, f5f2268 (2026-10-29).
- **H20** · Cancelling matchmaking, or a fatal matchmaking failure, returned to a lobby without the player's bunny. Done in d1dafc5 (2026-10-29).
- **H75** · Harness sign-in plus `publish` and `wait_shared` steps; a fake `Platform.party` for GUT. Done in ed00d83 (2026-10-29).
- **H99** · Finish T48 (M; batch 7; `docs/design/H37_systems_audit.md` section 5). Done in f10044e (2026-10-29).
- **H68** · Legal parity is checked only by pr-validate, which never runs on push (C2); `edgegap_app_version` is not in the sync's mustSurvive (C3) (S; batch 6; `docs/design/H37_systems_audit.md` 3.4). Done in e5c92fb (2026-10-29).
- **H30** · `scripts/agent/run-game.ps1 -Backend` accepts a URL with no port; the driver then refuses it with exit 3. Done in 32de8a0 (2026-10-29).
- **H73** · Harness friction: loopback runs warn of production; client 2 starts 30 s late; screenshots go black 0.7 s after a screen change (S; batch 6; `docs/design/H37_systems_audit.md` 1.2, 4 step 3). Done in 32de8a0 (2026-10-29).
- **H74** · `scripts/dev-stack.ps1` from exec-b's `stack.ps1`, with seed and restart steps (S; batch 6; `docs/design/H37_systems_audit.md` 1.2 gaps, section 4 step 3). Done in 6020cac (2026-10-29).
- **H84** · Test fixtures log "no animation 'Rest'" 37 times per run. exec-a (seen in every run). Done in 0e50353 (2026-10-29).
- **H46** · `test_network_connector.gd` crashed on exit. mm: crashed in 1 of 3 runs. Closed without a fix 2026-10-29: 10 consecutive runs of the file pass with exit 0 and no crash; the exit-time leak lines (199 ObjectDB instances, 81 resources) are identical in unrelated suites, so they are engine headless noise, not something this test leaves behind. Done in 54c5859 (2026-10-29).
- **H35** · `test_party_matchmaking_context.gd` fails 7 of 11 tests in a full `-gdir=res://test/unit -ginclude_subdirs` run, passes alone (state bleed); pr-validate's per-file loop doesn't hit it. Done in 8d2a7fe (2026-10-29).
- **H65** · Tests for the sign-out router's party reset and avatar-cache clear. acct (no test). Done in 7e17dce (2026-10-29).
- **H81** · `local-smoke-test.ps1` rewrites the checkout it runs in; "several runs at once" holds only per worktree (S; batch 6; `docs/design/H37_systems_audit.md` 3.5). Done in 1dd09ce (2026-10-29).
- **H55** · One absent member stalls the party. Done in acd5bcb (2026-10-29).
- **H53** · Party client races: a follower cannot abort matchmaking; two Start presses split the party (M; batch 4; `docs/design/H37_systems_audit.md` 3.2). Done in 7483f45 (2026-10-29).
- **H60** · Names and avatar URLs are never validated; any avatar URL is fetched (PI-1, DN-2; client half) (M; batch 4; `docs/design/H37_systems_audit.md` 3.1). Done in afe43e2 (2026-10-29).
- **H23** · The notification socket stops on any failed sign-in result, transient refresh failures included, until the next successful refresh; a failed `delete_account` (DEL-2, SP41) is one more trigger. Done in ac95413 (2026-10-29).
- **H41** · Session validation enforced: SP27 tokens + netcode gate + derived backend ids (closes H17, with H43). Done in 6b399d03, netcode 6ae6765, platform 886aa10 (2026-10-20).
- **H43** · Reconnect stale-peer race: re-claim transfers ownership, stale peer disconnected deferred. Done in 6b399d03 (2026-10-20).
- **H42** · Disconnected players demoted on every match end (G2.1). Done in 6b399d03 (2026-10-20).
- **H45** · Unfinished all-dropped matches cancel with runtime; server waits out reconnect grace. Done in 6b399d03 (2026-10-20).
- **H48** · Connection grace restarts after each peer's signaling; signaling stamps logged. Done in 6b399d03 (2026-10-20). Measured same day (Levi: do it; synthetic probes on the local and Edgegap paths): signaling takes ~65 ms per player (server log: WS connect 0.279 s, answers+ICE done 0.346 s after boot; DataChannel open ≤ 0.65 s), so the 10 s window was never signaling-bound.
- **H44** · Play Again routes through party matchmaking (one party ticket). Done in 6b399d03 (2026-10-20).
- **H3** · Respawn aligned to the frame clock (same boundary as Dead). Done in 6b399d03 (2026-10-20).
- **H15** · Matchmaking socket closed on sign-out; SDK rebuilds sockets owned by another account. Done in 6b399d03, platform 886aa10 (2026-10-20).
- **H59** · Generated display names only (runtime hook at creation; SDK drops provider name). Done in 6b399d03, platform 886aa10 (2026-10-20). Follow-through (Levi, same day): 225 prod accounts renamed to generated names; match UI shows bunny names only (auth-name broadcast removed); spawn names captured at match end for the board and recent players (platform SP72). Done in a310422, platform e5538cc, netcode b98d490; deployed runtime + server v30 + web 0.55.0 (2026-10-20).
- **H79** · Org-level `NAKAMA_HTTP_KEY` Actions secret held the pre-rotation key; updated to the live key and verified against `runtime_status`. Done 2026-10-20 (no code commit).
- **H49** · `match_history` rows carry `level_id` (runtime write + read). Done in platform aa60b94 (SP76) (2026-10-20).
- **H50** · Warm-up stubs, lobby countdown, and loading warm-up branch deleted. Done in ac4d2a9b (2026-10-20).
- **H51** · Loading screen CONNECTING/WAITING phases, driven by GameSessionManager. Done in a2e8f049 (2026-10-20).
- **H57** · Guest upgrade links onto the device account; `is_anonymous` cleared on link. Done in 0dbdcef5, platform a8de879 (SP73) (2026-10-20).
- **H58** · Guests reach export, delete, and log out (SDK starts the guest session). Done in b0389aad, platform 4914f54 (SP75) (2026-10-20).
- **H62** · Link errors match Nakama codes (PROVIDER_CONFLICT/LAST_PROVIDER); conflict tells the player; dead merge flow removed. Done in 0dbdcef5, platform a8de879 (SP73) (2026-10-20).
- **H64** · Guest JWT refreshed on expiry in `BackendApiClient._ensure_session`. Done in d8389b8b (2026-10-20).
- **H82** · staticcheck pinned to 2025.1.1 (CI Go 1.25) in both runtime gates. Done in ac4d2a9b, platform 9139b38 (2026-10-20).
- **H85** · CLAUDE.md toggles corrected to `show_perf_tracker`/`show_debug_console`. Done in ac4d2a9b (2026-10-20).
- **H47** · transport.md drift fixed (4434 signaling, 12×750 ms retries, declared ports, WSS superseded). Done in ac4d2a9b (2026-10-20).
- **H101** · Device/custom accounts get generated display names at creation. Done in platform bca5a69 (SP74) (2026-10-20).
