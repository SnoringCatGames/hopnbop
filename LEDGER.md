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

- **H41** · Game server does not enforce session validation (G1.1,
  G1.3); ship with the G1.3 re-claim rule, never alone, after SP70 and
  SP27 (M; batch 2; `docs/design/H37_systems_audit.md` 3.3, 0.1 row 4)

## Waiting on Levi

- **H3** · The bunny reappears 1-2 frames before respawn: "Dead" ends on
  a frame count (`character_state_from_server.gd:38-52`), respawn on a
  wall-clock timer (`player.gd:301`). Decide whether to align the two.
- **H15** · Offered: log-out leaves the matchmaking socket signed in as
  the old account; call `Platform.matchmaking.cleanup()` in
  `SignOutRouter`'s shared cleanup (verified, H37 4d). Do it?
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

- **H43** · Reconnect stale-peer race (F8) (S; batch 2;
  `docs/design/H37_systems_audit.md` 3.3)
- **H42** · A disconnected leader keeps the win on a normal match end
  (G2.1) (S; batch 3; `docs/design/H37_systems_audit.md` 3.3)
- **H45** · The server self-quits inside the reconnect window and
  nothing reaches the runtime (S; batch 3;
  `docs/design/H37_systems_audit.md` 3.3)
- **H48** · The 10 s server grace may be too short for WebRTC signaling
  (unmeasured): time signaling in a WebRTC run, start the grace after it
  (S; batch 3; `docs/design/H37_systems_audit.md` 3.3 list)
- **H44** · Play Again splits a party; there is no rematch (M; batch 3;
  `docs/design/H37_systems_audit.md` 3.3)
- **H51** · The loading screen has no connecting or waiting phase (TODO
  330 to 333, half done). mm. Fix: add the two phases (S; batch 3;
  `docs/design/H37_systems_audit.md` 3.3 list, section 5)
- **H57** · The guest upgrade signs in instead of linking (AN-1); a
  linked guest keeps `is_anonymous=true` (M; batch 4;
  `docs/design/H37_systems_audit.md` 3.1)
- **H62** · Link errors match AWS-era codes: merge is dead (LK-4;
  `link_account_row.gd:159,209`). Fix: use Nakama's, route AlreadyExists
  to H57 (S; batch 4; `docs/design/H37_systems_audit.md` 3.1)
- **H58** · Guests cannot export, delete or forget (AN-2) (M; batch 4;
  `docs/design/H37_systems_audit.md` 3.1)
- **H64** · A guest's server calls use an expired JWT after 2 h (AN-3;
  `backend_api_client.gd:528-536`). Fix: refresh a guest JWT on expiry
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
  (AP-1, DEL-1). Fix: always offer it; clear locally when the server
  call fails (S; batch 4; `docs/design/H37_systems_audit.md` 3.1 list)
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
  starts 30 s late; screenshots go black 0.7 s after a screen change (S;
  batch 6; `docs/design/H37_systems_audit.md` 1.2, 4 step 3)
- **H75** · Harness sign-in plus `publish` and `wait_shared` steps; a
  fake `Platform.party` for GUT (M; batch 6;
  `docs/design/H37_systems_audit.md` 1.2, 1.3, section 4 step 3)
- **H72** · Exported-build runs for the harness (custom 4.7.2 template);
  H38's release check waits on it (M; batch 6;
  `docs/design/H37_systems_audit.md` section 4 step 4)
- **H82** · Pin staticcheck in `pr-validate.yml:305` (XS; batch 6;
  `docs/design/H37_systems_audit.md` 3.5)
- **H68** · Legal parity is checked only by pr-validate, which never
  runs on push (C2); `edgegap_app_version` is not in the sync's
  mustSurvive (C3) (S; batch 6; `docs/design/H37_systems_audit.md` 3.4)
- **H83** · `release.yml` has never run and no `v*` tag exists. Waits on
  Levi (report section 7 row 13) (S; batch 6;
  `docs/design/H37_systems_audit.md` 1.1)
- **H66** · V17: 22 broken format strings, 17 here (one is the
  refused-pause ERROR, `game_panel.gd:1854`); RN7 and SP49 hold the rest
  (S-M; batch 7; `docs/design/H37_systems_audit.md` 5, 3.3)
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
- **H17** · `EdgegapServerProvider` trusts a player's declared backend
  user ID over the validated session ID, so one can claim a fellow
  player's ID (confirmed, G1.1-G1.3). Fix: SP27 and H41.
- **H18** · Raw SDK error text reaches players: the party panel ("Not
  authenticated" toast), delete, export (`export_data_row.gd:96-99`),
  merge and poll (`friends_panel.gd:342-354`) toasts.
- **H19** · After a recoverable matchmaking failure the loading screen
  offers only "Try Again", with no way back to the lobby. (Agent
  abdbfdf9.) H37 (10-14): still true.
- **H20** · Cancelling matchmaking, or a fatal matchmaking failure,
  returns to a lobby without the player's bunny. Fix:
  `copy_latest_state` at `game_panel.gd:673` and `779`, as at 694.
- **H21** · A party follower whose join fails gets two toasts for it.
  (Agent abdbfdf9.) H37 (10-14): still true.
- **H22** · Log-out first tells the server the player went offline, so
  with no connection the consent screen appears only after that times
  out (about 9 s measured).
- **H23** · The notification socket stops on any failed sign-in result,
  transient refresh failures included, until the next successful
  refresh; a failed `delete_account` (DEL-2, SP41) is one more trigger.
- **H24** · `Player._enter_tree` registers the player before its id is
  set, leaving a stale `players_by_id[0]` entry on the server (the code
  comment says the id is set first). Low.
- **H26** · After a preview server hot-reload, levels get auto-generated
  names (`@Node2D@39`), so each client logs about 35 replication errors;
  it reaches players (H37 3.3, verified).
- **H27** · Local mode logs "RPC on yourself is not allowed"
  (`_server_rpc_ping`, `_rpc_init`). Fix: `is_local_mode` guard
  (`frame_synchronizer.gd:120`), skip self at `networked_level.gd:307`.
- **H28** · About half of lobby runs log an `AudioStreamWAV`
  (`pause_menu.wav`) leak warning at exit, before and after the
  PerfTracker fix; noted in CLAUDE.md; see H86 (CR6).
- **H29** · Unused code: `BinaryToggle`, and `fetch_player_stats`,
  `fetch_match_history` and their signals in `backend_api_client.gd`
  since the leaderboard and My Stats rewrite (f77828e8).
- **H30** · `scripts/agent/run-game.ps1 -Backend` accepts a URL with no
  port; the driver then refuses it with exit 3. (Agent abbaef7c.)
- **H31** · The credits screen's labels ("Made by", "Sound", "Credits",
  "Thanks for playing!") lack translation keys, so other locales show
  English (`credits_screen.tscn:40,55,70,85,114`).
- **H32** · Anonymous players only get a session once they go online, so
  an offline-only player's crash reports expire unsent after 7 days.
  (Crash agent a1d23375.) H37 (10-14): still true.
- **H35** · `test_party_matchmaking_context.gd` fails 7 of 11 tests in a
  full `-gdir=res://test/unit -ginclude_subdirs` run, passes alone
  (state bleed); pr-validate's per-file loop doesn't hit it.
- **H52** · Inert `game.yaml` `matchmaker_rules` fields
  (`ticket_expiry_seconds`, `cross_play`, `rules`): delete or wire them,
  fix the comment (XS; batch 3; `docs/design/H37_systems_audit.md` 3.3)
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
- **H47** · `.claude/rules/transport.md` drift: the retry count, port
  4433 vs the real 4434/TCP, a GameLift fleet paragraph. Fix: correct
  all three (XS; batch 7; `docs/design/H37_systems_audit.md` 3.3 list)
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

- **H11** · CI never ran on push to main; now `push: branches: [main]` triggers pr-validate and compliance-matrix. Done in 7dcb7cb8 (2026-10-14).
- **H69** · The `sign-out-local-match` and `sign-out-play-again` scenarios timed out at the 180 s match length; both now pin `match_duration_sec: 10`, harness-verified. Done in 7dcb7cb8 (2026-10-14).

- **H39** · Networked pause shipped enabled; off in release (Levi decided): `RELEASE_IS_SERVER_PAUSE_ENABLED = false`, editor and harness keep the settings.tres value. Done in a11e2223 (2026-10-14).

- **H40** · Legal texts missing from every export (LG-1, ops C7): `include_filter="legal/*"` on all four presets, plus a pr-validate pack check. Done in 41f29a07 (2026-10-14).
- **H37** · Systems audit, test run and history recap: report `docs/design/H37_systems_audit.md`, appendices and probes in `docs/design/H37/`; items filed H38-H100, SP26-SP71, RN6-RN8 and CC51-CC57. Done in 6910dce4 (2026-10-14).
- **H34** · CLAUDE.md slimmed to the context budget, 2,333 lines to 400; lore moved to path-scoped `.claude/rules/`, history to `docs/history.md`. Done in 34971411 (2026-10-13).
- **H36** · Edgegap v27 and v28 deactivated, only v29 active (Edgegap-side, no commit); `game-server.yml` leaves prior versions active, so deactivate the superseded one at each release. Done 2026-10-12.
- **H16** · Verified against the real 0.54.0 web export: the name and adjective CSVs ship, so localized bunny names work; nothing to fix. Done 2026-10-12.
- **H14** · Runtime HTTP key rotated right after H4 shipped (credentials blob, Nakama, Edgegap v29 env, repo secret); the desktop re-decrypt is CC31. Done 2026-10-12 (claude-config 6279e62).
- **H4** · Release 0.54.0 shipped and verified: exported builds enforce the shipping values in code, game server v29, no `v*` tag. Done in 8ca156e7 + 2abf477c (2026-10-12).
