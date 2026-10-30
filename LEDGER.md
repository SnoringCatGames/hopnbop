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
- **H102** · Real account merge for the PROVIDER_CONFLICT case: since H62 the game tells the player instead. Merging two accounts' stats/friends/boards is a platform feature; needs Levi's call on whether 'tell' is enough. (L)

## In progress

- **H109** · Muse run 2: the follow-ups from checking run 1 (H103), then
  most of what H103 held for Claude, released by Levi 2026-10-29
  (`docs/design/H109_muse_run2.md`).
  - owner: muse 01a189f7, launched through Paseo by claude 0cfd9cf1
    on 2026-10-29 (session 01a189f7-97c5-7eb0-98b6-164cb9977b39)
  - branch: mainline (hopnbop, platform, netcode); last commit:
    Tier A batch 2026-10-29, see `git log --grep Muse-Session`
  - evidence: `.claude/probes/<ID>/` per item; the brief's section 5
  - next: Tier B, H24 first
  - brief: `docs/design/H109_muse_run2.md`


## Next

- **H104** · Claude reviews Muse's commits from H103 and H109, security
  first (SP32, SP33, SP36, SP41 to SP44, SP47, SP59, H60, then H109's
  Tier C), plus H109's Tier D design docs: `git log --grep
  Muse-Session` here and in both submodules. Leads
  from a first check: `docs/design/H103_muse_backlog.md` section 5,
  Claude's 2026-10-29 entry.
- **H54** · The notification poll is frozen on the oldest 50 rows
  (client half; SP40 is the server half) (M; batch 4;
  `docs/design/H37_systems_audit.md` 3.2)
- **H61** · Avatars from an earlier match show on the wrong players
  (PI-2) (S; batch 4; `docs/design/H37_systems_audit.md` 3.1)
- **H56** · Controller players cannot enter codes (M; batch 4;
  `docs/design/H37_systems_audit.md` 3.2)
- **H86** · Script and engine errors that do not crash are never
  reported (CR6) (S to M; batch 5; `docs/design/H37_systems_audit.md`
  3.4)
- **H87** · A dedicated server's fatal error or engine crash is never
  reported (CR1, CR7) (M; batch 5; `docs/design/H37_systems_audit.md`
  3.4)
- **H88** · Nightly smoke makes a new account each run, and player
  metrics count them (OP3; the workflow half) (S; batch 5;
  `docs/design/H37_systems_audit.md` 3.5)
- **H89** · The final match stats ride one unreliable RPC (S11) (S;
  batch 5; `docs/design/H37_systems_audit.md` 3.4)
- **H90** · Failed cloud saves are dropped (ST2, ST3) (M; batch 5;
  `docs/design/H37_systems_audit.md` 3.4)
- **H77** · Land the H37 probes as tests, each with its fix (XS each;
  batch 6; `docs/design/H37_systems_audit.md` section 4 step 2)
  Landed 2026-10-29: ghost-ticket probe (SP28), account probe
  DEL-2 (SP41) and LK-1 (SP43), account PI-1 (H60), social probe
  (SP35). Still blocked on fixes outside this run: settings-echo
  (H67), declare-validation (H17), port-leak Go test (SP26),
  account PI-2 and SO-1 (H15), verify scenarios (H72 held).
- **H72** · Exported-build runs for the harness (custom 4.7.2 template);
  H38's release check waits on it (M; batch 6;
  `docs/design/H37_systems_audit.md` section 4 step 4)
- **H83** · `release.yml` has never run and no `v*` tag exists. Waits on
  Levi (report section 7 row 13) (S; batch 6;
  `docs/design/H37_systems_audit.md` 1.1)

- **H93** · The overhead label offset (T29). After H92 (S to M; batch 7;
  `docs/design/H37_systems_audit.md` section 5 row 4)
- **H91** · A short input grace on the game-over screen (T79). After H92
  (M; batch 7; `docs/design/H37_systems_audit.md` section 5 row 5)
- **H94** · A controller pass by hand, with two local players (T45, T08,
  T09) (S; batch 7; `docs/design/H37_systems_audit.md` section 5 row 6)



- **H98** · Finish T43; verify, then fix, T19 (M; batch 7;
  `docs/design/H37_systems_audit.md` section 5)


## Residuals (known, not fixed)

- **H5** · Podium bunnies never animate. (Session 530145bc, 2026-10-11
  12:00 "Noticed, not fixed".)
- **H7** · The check that keeps new spawns off other players can't see
  bunnies that are still blinking, so a respawn can land on one. Left
  alone as a player-versus-player rule.
- **H8** · Possible one-tick origin slide at first spawn in local mode
  (unverified): `networked_level.gd:337-339` adds the player before
  positioning it; same pattern as 7215b1d5.
- **H9** · pr-validate's "GDScript formatter" job is a no-op: it logs
  "not vendored; skipping" because `addons/gdscript_formatter` isn't in
  the repo, though CLAUDE.md says it is.
- **H10** · Android: run the game on the Pixel. Export preset done in
  4c04e908 (`--export-debug "Android" build/android/hopnbop.apk`
  builds). Left: install over USB, then a touch-input pass.
- **H22** · Log-out first tells the server the player went offline, so
  with no connection the consent screen appears only after that times
  out (about 9 s measured).
- **H26** · After a preview server hot-reload, levels get auto-generated
  names (`@Node2D@39`), so each client logs about 35 replication errors;
  it reaches players (H37 3.3, verified).
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
