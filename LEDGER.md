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

## Urgent

- **H41** · The game server does not enforce session validation (G1.1,
  G1.3). Ship with the G1.3 re-claim rule, never alone. Lands after
  platform SP70 and SP27 (M; batch 2; `docs/design/H37_systems_audit.md`
  3.3, 0.1 row 4)

## Waiting on Levi

- **H3** · The bunny reappears 1-2 frames before respawn. "Dead" ends on
  a frame count (`character_state_from_server.gd:38-52`), but respawn
  comes from a wall-clock timer (`player.gd:301`). In between, the
  invincibility blink shows the bunny while its collision is still off,
  and in local mode it drifts about 2 px before the respawn records its
  position. Decide whether to align the two. (Session 530145bc, agent
  a6c0fbc6 "Fix death blink and splash", 2026-10-11 ~11:39.)
- **H11** · Offered: add `push: main` triggers to `pr-validate.yml` and
  `compliance-matrix.yml`. Both run only on `pull_request` and
  `workflow_dispatch`, and work lands straight on main, so none of their
  checks (GUT, export smoke, the translation-CSV check, the compliance
  suite) run unless someone dispatches them. Actions are free on this
  public repo. (Session 530145bc.) H37 (10-14): still true, now 25
  commits (`3b7f5743..9bbaa7ee`, the 0.54.0 release `8ca156e7` among
  them); the legal parity check (C1) depends on it.
- **H15** · Offered: the realtime matchmaking socket survives log-out
  still signed in as the old account, and the next account would reuse
  it for its tickets; nothing calls `Platform.matchmaking.cleanup()`.
  Likely a one-line fix in `SignOutRouter`'s shared cleanup. Inferred
  from code, not reproduced. (Session 530145bc, client-fixes agent
  abdbfdf9, 2026-10-12.) H37 (10-14): Broken, Verified end to end in 2
  runs (verify item 4d); a sign-in over a guest hits it too (AN-1b).
- **H59** · The Google profile name is the public display name (DN-1,
  TODO L50) (M; batch 4; `docs/design/H37_systems_audit.md` 3.1, section
  7 row 4)
- **H92** · One 2-client networked session with Levi (T02 to T07, T16,
  T25, T27, T29) (S; batch 7; `docs/design/H37_systems_audit.md` section
  5 row 3, section 7 row 9)
- **H71** · Decoupling: which seams to build (decision;
  `docs/design/H37_systems_audit.md` 1.3, section 7 row 6)
- **H79** · Check the org-level `NAKAMA_HTTP_KEY` Actions secret (needs
  admin:org) (XS; `docs/design/H37_systems_audit.md` 3.5, section 7 row
  8)

## In progress

## Next

- **H67** · A settings change reverts two launches later (ST1) (S; batch
  1; `docs/design/H37_systems_audit.md` 3.4, 0.1 row 6)
- **H70** · A signed signaling URL is logged; files the 10-13 inbox
  entry. At `src/core/game_session_manager.gd:345-353`; fix: log the
  host only, or strip the query (XS; batch 1;
  `docs/design/H37_systems_audit.md` 3.5, 2.2)
- **H69** · `sign-out-local-match` and `sign-out-play-again` fail since
  88e3089b raised the match length to 180 s. acct, exec-b: copies with
  10 s pass. Fix: a 10 s match length in both scenarios (XS; batch 1;
  `docs/design/H37_systems_audit.md` 3.1 coverage, section 4 step 2)
- **H43** · Reconnect stale-peer race (F8) (S; batch 2;
  `docs/design/H37_systems_audit.md` 3.3)
- **H42** · A disconnected leader keeps the win on a normal match end
  (G2.1) (S; batch 3; `docs/design/H37_systems_audit.md` 3.3)
- **H45** · The server self-quits inside the reconnect window and
  nothing reaches the runtime (S; batch 3;
  `docs/design/H37_systems_audit.md` 3.3)
- **H48** · The 10 s server grace may be too short for WebRTC signaling.
  mm: not measured. Fix: time signaling in a WebRTC run; start the grace
  after signaling (S; batch 3; `docs/design/H37_systems_audit.md` 3.3
  list)
- **H44** · Play Again splits a party; there is no rematch (M; batch 3;
  `docs/design/H37_systems_audit.md` 3.3)
- **H51** · The loading screen has no connecting or waiting phase (TODO
  330 to 333, half done). mm. Fix: add the two phases (S; batch 3;
  `docs/design/H37_systems_audit.md` 3.3 list, section 5)
- **H57** · The guest upgrade signs in instead of linking (AN-1); a
  linked guest keeps `is_anonymous=true` (M; batch 4;
  `docs/design/H37_systems_audit.md` 3.1)
- **H62** · Link errors match AWS-era codes, so the merge path is dead
  (LK-4, LK-2). acct: LK-4 Broken by code.
  `link_account_row.gd:159,209`; `sdk:core/auth_api_client.gd:871-874`
  (prefix inferred). Fix: match Nakama's codes; route AlreadyExists to
  H57's merge decision (S; batch 4; `docs/design/H37_systems_audit.md`
  3.1 list)
- **H58** · Guests cannot export, delete or forget (AN-2) (M; batch 4;
  `docs/design/H37_systems_audit.md` 3.1)
- **H64** · A guest's server calls go out with an expired JWT after 2 h
  (AN-3). acct: Believed, low. `backend_api_client.gd:528-536`. Fix:
  refresh the guest JWT when it expires, not only when none is stored
  (S; batch 4; `docs/design/H37_systems_audit.md` 3.1 list)
- **H55** · One absent member stalls the party. Waits for the
  party-control decision (SP34) (M; batch 4;
  `docs/design/H37_systems_audit.md` 3.2)
- **H54** · The notification poll is frozen on the oldest 50 rows
  (client half; SP40 is the server half) (M; batch 4;
  `docs/design/H37_systems_audit.md` 3.2)
- **H60** · Names and avatar URLs are never validated; any avatar URL is
  fetched (PI-1, DN-2; client half) (M; batch 4;
  `docs/design/H37_systems_audit.md` 3.1)
- **H61** · Avatars from an earlier match show on the wrong players
  (PI-2) (S; batch 4; `docs/design/H37_systems_audit.md` 3.1)
- **H63** · The Log Out row is hidden when the access token has expired
  (AP-1), with DEL-1. acct: AP-1 Believed, low-medium. Fix: always offer
  Log Out; clear locally when the server call fails (S; batch 4;
  `docs/design/H37_systems_audit.md` 3.1 list)
- **H53** · Party client races: a follower cannot abort matchmaking; two
  Start presses split the party (M; batch 4;
  `docs/design/H37_systems_audit.md` 3.2)
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
- **H65** · Tests for the sign-out router's party reset and avatar-cache
  clear. acct (no test). `sign_out_router.gd:103,111`. Fix: two GUT
  tests (S; batch 6; `docs/design/H37_systems_audit.md` 3.1 coverage)
- **H74** · `scripts/dev-stack.ps1` from exec-b's `stack.ps1`, with seed
  and restart steps (S; batch 6; `docs/design/H37_systems_audit.md` 1.2
  gaps, section 4 step 3)
- **H73** · Harness friction: loopback runs warn of production; client 2
  starts 30 s late in matchmaker runs; screenshots are black for about
  0.7 s after a screen change (S; batch 6;
  `docs/design/H37_systems_audit.md` 1.2 gaps, section 4 step 3)
- **H75** · Harness sign-in plus `publish` and `wait_shared` steps; a
  fake `Platform.party` for GUT (M; batch 6;
  `docs/design/H37_systems_audit.md` 1.2 gaps, 1.3 rows 6 and 7, section
  4 step 3)
- **H72** · Exported-build runs for the harness (a custom 4.7.2
  template) (M; batch 6; `docs/design/H37_systems_audit.md` section 4
  step 4)
- **H82** · Pin staticcheck in `pr-validate.yml:305` (XS; batch 6;
  `docs/design/H37_systems_audit.md` 3.5)
- **H68** · Legal parity is checked only by pr-validate, which never
  runs on push (C2); `edgegap_app_version` is not in the sync's
  mustSurvive list (C3) (S; batch 6; `docs/design/H37_systems_audit.md`
  3.4)
- **H83** · `release.yml` has never run and no `v*` tag exists. Waits on
  Levi (report section 7 row 13) (S; batch 6;
  `docs/design/H37_systems_audit.md` 1.1)
- **H66** · V17: 22 broken format strings, among them the refused-pause
  ERROR at `game_panel.gd:1854` (exec-b #10). 17 here; RN7 and SP49 hold
  the rest (S to M; batch 7; `docs/design/H37_systems_audit.md` section
  5 row 2, 3.3 list)
- **H93** · The overhead label offset (T29). After H92 (S to M; batch 7;
  `docs/design/H37_systems_audit.md` section 5 row 4)
- **H91** · A short input grace on the game-over screen (T79). After H92
  (M; batch 7; `docs/design/H37_systems_audit.md` section 5 row 5)
- **H94** · A controller pass by hand, with two local players (T45, T08,
  T09) (S; batch 7; `docs/design/H37_systems_audit.md` section 5 row 6)
- **H95** · A click sound on every MenuRow trigger (T42) (S; batch 7;
  `docs/design/H37_systems_audit.md` section 5 row 7)
- **H96** · Alt+Enter fullscreen (T10) (S; batch 7;
  `docs/design/H37_systems_audit.md` section 5)
- **H97** · Finish T12; delete the 9 Stale notes (with SP53) (S; batch
  7; `docs/design/H37_systems_audit.md` section 5)
- **H98** · Finish T43; verify, then fix, T19 (M; batch 7;
  `docs/design/H37_systems_audit.md` section 5)
- **H99** · Finish T48 (M; batch 7; `docs/design/H37_systems_audit.md`
  section 5)

## Residuals (known, not fixed)

- **H5** · Podium bunnies never animate. (Session 530145bc, 2026-10-11
  12:00 "Noticed, not fixed".)
- **H6** · Networked splashes and skids fire twice. Water and landing
  transitions compare against the frame two back, so they trigger on two
  consecutive frames. (Session 530145bc, agent a6c0fbc6.)
- **H7** · The check that keeps new spawns off other players can't see
  bunnies that are still blinking, so a respawn can land on one. Left
  alone as a player-versus-player rule. (Session 530145bc, invincibility
  agent a25807d3, 2026-10-11 13:19.)
- **H8** · Possibly the same origin slide at first spawn (unverified).
  `networked_level.gd:337-339` adds the player before positioning it, so
  local mode may show a one-tick slide from the origin when a match
  starts. 7215b1d5 fixed the same pattern for the squish sprite. (Session
  530145bc, agent a6c0fbc6.)
- **H9** · pr-validate's "GDScript formatter" job is a no-op. It logs
  "not vendored; skipping" because `addons/gdscript_formatter` isn't in
  the repo, though CLAUDE.md says it is. (Session 530145bc, agent
  aab30fcb, 13:52.) H37 (10-14): still true; the formatter job is green
  but skips everything.
- **H10** · Android: run the game on the Pixel. The export preset
  half is done in 4c04e908 (2026-10-13): preset.3 "Android" (arm64,
  template export, INTERNET, `games.snoringcat.hopnbop`) plus the
  ETC2/ASTC import flag; a signed 67.7 MB debug APK built and
  verified on the laptop (`--export-debug "Android"
  build/android/hopnbop.apk`; webrtc arm64 lib included). Remaining:
  install/run on the Pixel — needs the phone on USB (`adb install`,
  then Godot one-click deploy for iteration) and a touch-input pass
  (the UI is gamepad/keyboard-driven; H10's original scope).
- **H17** · `EdgegapServerProvider` trusts each player's declared backend
  user ID instead of checking it against the validated session ID. The
  runtime now drops outsiders from `match_end` (platform f4424d5), but a
  player can still claim a fellow match player's ID. (Session 530145bc,
  admin-key agent a654b0d8, 2026-10-12.) H37 (10-14): a probe confirmed
  it (report 3.3, G1.1 to G1.3); SP27 and H41 fix it.
- **H18** · Raw SDK error text reaches players: the party panel shows
  SDK errors as-is (a "Not authenticated" toast), and the delete, export
  and merge failure toasts append raw errors. (Agent abdbfdf9.) H37
  (10-14): also the social R4 repro, the export toast
  (`export_data_row.gd:96-99`) and the poll toast
  (`friends_panel.gd:342-354`).
- **H19** · After a recoverable matchmaking failure the loading screen
  offers only "Try Again", with no way back to the lobby. (Agent
  abdbfdf9.) H37 (10-14): still true.
- **H20** · Cancelling matchmaking, or a fatal matchmaking failure,
  returns to a lobby without the player's bunny. Inferred from code.
  (Agent abdbfdf9.) H37 (10-14): still true. Fix: `copy_latest_state` at
  `game_panel.gd:673` and `779`, as at 694.
- **H21** · A party follower whose join fails gets two toasts for it.
  (Agent abdbfdf9.) H37 (10-14): still true.
- **H22** · Log-out first tells the server the player went offline, so
  with no connection the consent screen appears only after that times
  out (about 9 s in the harness). (Agent abdbfdf9.) H37 (10-14): still
  true, about 9 s measured.
- **H23** · The notification socket stops on any failed sign-in result,
  transient refresh failures included, until the next successful
  refresh. (Agent abdbfdf9.) H37 (10-14): still true; a failed
  `delete_account` (DEL-2, SP41) is one more trigger.
- **H24** · `Player._enter_tree` registers the player before its id is
  set, leaving a stale `players_by_id[0]` entry on the server; the code
  comment there says the id is set first. (Session 530145bc, harness
  agent a9dc5b3c, 2026-10-11.) H37 (10-14): still true, low.
- **H26** · After a preview server hot-reload, levels get
  auto-generated names (`@Node2D@39`), so each client logs about 35
  replication errors (Snail_0 not found, ids missing from the cache).
  (Agent a9dc5b3c.) H37 (10-14): it reaches players (exec-b run 2:
  Verified; the production scope Believed; report 3.3).
- **H27** · Local/offline mode logs "RPC on yourself is not allowed"
  errors (`_server_rpc_ping`, `_rpc_init`). (Agent a9dc5b3c.) H37
  (10-14): still present, Verified. Fix: an `is_local_mode` guard at
  `frame_synchronizer.gd:120`, and skip the local peer at
  `networked_level.gd:307`.
- **H28** · About half of lobby runs log an `AudioStreamWAV`
  (`pause_menu.wav`) leak warning at exit, before and after the
  PerfTracker fix. Noted in CLAUDE.md. (Agent a55477032.) H37 (10-14):
  see H86 (CR6).
- **H29** · Unused code: `BinaryToggle`, and `fetch_player_stats`,
  `fetch_match_history` and their signals in `backend_api_client.gd`
  since the leaderboard and My Stats rewrite (f77828e8). (Leaderboard
  agent abbaef7c.) H37 (10-14): still true.
- **H30** · `scripts/agent/run-game.ps1 -Backend` accepts a URL with no
  port; the driver then refuses it with exit 3. (Agent abbaef7c.)
- **H31** · The credits screen's existing labels ("Made by", "Sound",
  "Credits", "Thanks for playing!") have no translation keys, so other
  locales show English next to the translated DB-IP row (87523bb3).
  (Privacy agent a834b111.) H37 (10-14): the labels are at
  `credits_screen.tscn:40,55,70,85,114`.
- **H32** · Anonymous players only get a session once they go online, so
  an offline-only player's crash reports expire unsent after 7 days.
  (Crash agent a1d23375.) H37 (10-14): still true.
- **H35** · `test_party_matchmaking_context.gd` fails 7 of its 11 tests
  under a full `-gdir=res://test/unit -ginclude_subdirs` run but passes
  11/11 alone: state bleed from earlier scripts, not a product bug
  (2026-10-12, Godot 4.7.2 + GUT 9.7.1, suite otherwise 485/492).
  pr-validate's per-file loop doesn't hit it. H37 (10-14): 11/11 per
  file again (exec-a); the full-directory run was not repeated.
- **H52** · Inert `game.yaml` `matchmaker_rules` fields; the same-device
  preference its comment claims does not exist. mm (read). Fix: delete
  `ticket_expiry_seconds`, `cross_play` and `rules`, or wire them; fix
  the comment (XS; batch 3; `docs/design/H37_systems_audit.md` 3.3 list)
- **H49** · `level_id` always empty in `match_stats` (ops S3). mm; ops
  "lower". `edgegap_server_provider.gd:266-270`. Fix: pass the level id
  (XS; batch 5; `docs/design/H37_systems_audit.md` 3.3 list)
- **H81** · `local-smoke-test.ps1` rewrites the checkout it runs in;
  "several runs at once" holds only per worktree (S; batch 6;
  `docs/design/H37_systems_audit.md` 3.5)
- **H46** · `test_network_connector.gd` crashed on exit. mm: crashed in
  1 of 3 runs. Fix: run the file 10 times and find what outlives the
  test (S; batch 6; `docs/design/H37_systems_audit.md` 3.3 list)
- **H50** · Delete the warm-up stubs (TODO 33 to 38, obsolete). mm.
  `backend_api_client.gd:7-122`, `loading_screen.gd:115-135` (XS; batch
  7; `docs/design/H37_systems_audit.md` 3.3 list)
- **H85** · CLAUDE.md names the debug toggles wrongly; `dev_mode` is
  read nowhere (ST5, triage V27) (XS; batch 7;
  `docs/design/H37_systems_audit.md` 3.4)
- **H47** · transport.md drift: the retry count, port 4433 vs the real
  4434/TCP, a GameLift fleet paragraph. mm (read).
  `.claude/rules/transport.md`. Fix: correct all three (XS; batch 7;
  `docs/design/H37_systems_audit.md` 3.3 list)
- **H80** · Textures orphaned by b998107d, `foobar.png` once T14 is
  answered, orphan `.import` files (XS; batch 7;
  `docs/design/H37_systems_audit.md` 2.2, section 5)

## Ideas (not scheduled)

- **H33** · An optional `occurred_at` on crash reports, clamped
  server-side, would date reports that sat queued for days. Needs a
  privacy-text check first. (Agent a1d23375.)
- **H76** · More than 2 clients and gamepad input in the harness (M to
  L; `docs/design/H37_systems_audit.md` section 4 step 7)
- **H78** · Golden screenshots (build item 7) (M;
  `docs/design/H37_systems_audit.md` 2.2, section 4 step 7)
- **H84** · Test fixtures log "no animation 'Rest'" 37 times per run.
  exec-a (seen in every run). Fix: give the fixtures a `Rest` animation,
  or stop playing it (XS; `docs/design/H37_systems_audit.md` 3.5 list)
- **H100** · Level art (T15, T28, T14) (L each;
  `docs/design/H37_systems_audit.md` section 5)

## Done

- **H38** · Clients crashed (signal 11) when the server went
  away mid-match. Fixed: the reconnect start, the first
  reconnect attempt, and both exit-match calls on the
  disconnect paths are now deferred out of the
  peer_disconnected dispatch, mirroring the normal match-end
  cleanup. Editor-path verified (connector GUT 3/3, harness
  offline-move-jump PASS); the release-template check still
  waits on H72, since the editor hides this crash family.
- **H39** · Networked pause shipped enabled. Decided by Levi
  2026-10-14 (off in release): `_apply_release_values` now sets
  `is_server_pause_enabled` from
  `RELEASE_IS_SERVER_PAUSE_ENABLED = false`; editor and harness
  keep the settings.tres value. Covered by
  `test_settings_release_values.gd` (2/2).

- **H40** · Legal texts missing from every export (LG-1, ops C7).
  Fixed: `include_filter="legal/*"` on all four presets, plus a
  pr-validate export-smoke step that fails if either pack lacks
  `legal/en/{terms,privacy,data_deletion}.txt`. Verified locally: web
  export pack contains all three (2026-10-14).
- **H37** · Systems audit, test run, history recap and TODO-scratch.md
  triage (Levi, 2026-10-14). Report `docs/design/H37_systems_audit.md`,
  appendices and reusable probes in `docs/design/H37/`. Its items are
  filed: H38-H100 here, SP26-SP71, RN6-RN8 and CC51-CC57. Done in
  6910dce4 (2026-10-14).
- **H25** · Quitting during the mid-match reconnect loop crashes with
  signal 11. The game's own exit paths avoid it, and so does the
  harness. (Agent a9dc5b3c.) Dropped: superseded by H38, which has the
  full trigger set and the fix (H37).
- **H34** · CLAUDE.md slimmed to the context budget: 2,333 lines /
  ~24k tokens → 400 lines / ~4.8k, the same split knotmaze used for
  K45. Binding rules stay; lore moved verbatim to path-scoped
  `.claude/rules/` (deploy, transport, testing, gdscript-style, ui,
  crash-reporting), the harness reference to
  `scripts/agent/README.md`, playbooks and the netcode explainer to
  `docs/`, history to `docs/history.md`. Done in 34971411
  (2026-10-13); Measure-ContextBudget now lists hopnbop within
  budget.
- **H36** · Edgegap v27 and v28 deactivated 2026-10-12 (API PATCH
  `is_active=false`); only v29 is active. Edgegap-side state, no commit.
  `game-server.yml` still leaves the prior version active after every
  release, so deactivate the superseded one as part of each release;
  check-prod step 10 flags actives piling up again.
- **H16** · Checked 2026-10-12 against the real 0.54.0 web export:
  mounted `index.pck` with `ProjectSettings.load_resource_pack` and
  probed `FileAccess.file_exists` on the exact paths
  `localized_name_config.gd` reads. All `translations/names/*` and
  `translations/adjectives/*` CSVs ship, so localized bunny names and
  adjectives work in exports. The suspicion (sources stripped by the
  translation importer) was wrong; nothing to fix.
- **H14** · Runtime HTTP key rotated 2026-10-12, right after H4
  shipped (leak plan step 3, closing the key committed here from
  12a93325 until 15498835). Rotated in `credentials.env` (blob
  re-encrypted, claude-config 6279e62), `/opt/nakama/.env` + nakama
  recreate (healthy; new key 200, old key 401), the Edgegap v29 env
  (PATCH), and a hopnbop repo-level `NAKAMA_HTTP_KEY` Actions secret.
  Caddy `access.log` truncated (no rotated files existed). Verified:
  synthetic matches green on both allocator paths (servers
  authenticated with the new key) and nightly-smoke green from CI
  (run 38325468725). Residue: the desktop re-decrypts (CC31), and gh
  here lacks admin:org, so if an org-level `NAKAMA_HTTP_KEY` exists it
  still holds the dead old key; hopnbop's repo secret shadows it.
- **H4** · Release 0.54.0 shipped and verified 2026-10-12 (laptop
  session). Levi confirmed the shipping values; exported builds now
  enforce them in code (180 s matches, HUD and overhead labels on,
  splash plays: `Settings.apply_release_overrides()` from
  `G._enter_tree`, GUT `test_settings_release_values.gd`) in 8ca156e7,
  boot page in 2abf477c. Game server v29 built and registered (run
  38313778919); web 0.54.0 on Pages + R2; `register_game` serves
  0.54.0 / v29 / legal 1.2. Verified: live hopnbop.net boot check
  (overrides applied, splash plays, no script errors), version_check,
  the check-prod checks all green, synthetic-match-probe green on both
  allocator paths with clean Edgegap teardown. No `v*` tag pushed.
- **H1** · Crash reporting was dead (no client session lookup, and the
  runtime never had a `crash_report` RPC). Done in hopnbop 6b0dc6d7 and
  platform 6081b82 (2026-10-11), live on prod; design review in
  `docs/design/crash_report_review.md`.
- **H2** · Local GUT runs loaded the real token store and refreshed that
  session against PRODUCTION Nakama on the first frame; a rejected
  refresh also signed the developer out. Done in the commit that moved
  this item here (2026-10-11): under GUT, in editor builds only, G hands
  Platform `user://test_auth.cfg`, deleted at boot, so every run starts
  signed out. Guarded by `test/unit/core/test_auth_file_isolation.gd`.
- **H12** · `upgrade_levels.tscn` failed to parse (dead ld58 content
  that broke exports). Done in b998107d (2026-10-11).
- **H13** · Nothing surfaced crash reports. Done in claude-config
  ad8c6ca (2026-10-11): prod-health-check's `crashes:` line (24 h count,
  new signatures, top 5) and step 9 of the hopnbop-check-prod skill.
