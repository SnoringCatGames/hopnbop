# Ledger notes

Text moved out of `LEDGER.md` by the ledger diet (`scripts/ledger_diet.mjs`
in knotmaze, K353; applied 2026-10-15), verbatim: the full text of items
that were shortened, moved or closed, under their ID. The ledger keeps each
item short and this file keeps the rest. New entries go at the bottom.

## H41 (2026-10-15, shortened by the diet)

- **H41** · The game server does not enforce session validation (G1.1,
  G1.3). Ship with the G1.3 re-claim rule, never alone. Lands after
  platform SP70 and SP27 (M; batch 2; `docs/design/H37_systems_audit.md`
  3.3, 0.1 row 4)

## H3 (2026-10-15, shortened by the diet)

- **H3** · The bunny reappears 1-2 frames before respawn. "Dead" ends on
  a frame count (`character_state_from_server.gd:38-52`), but respawn
  comes from a wall-clock timer (`player.gd:301`). In between, the
  invincibility blink shows the bunny while its collision is still off,
  and in local mode it drifts about 2 px before the respawn records its
  position. Decide whether to align the two. (Session 530145bc, agent
  a6c0fbc6 "Fix death blink and splash", 2026-10-11 ~11:39.)

## H15 (2026-10-15, shortened by the diet)

- **H15** · Offered: the realtime matchmaking socket survives log-out
  still signed in as the old account, and the next account would reuse
  it for its tickets; nothing calls `Platform.matchmaking.cleanup()`.
  Likely a one-line fix in `SignOutRouter`'s shared cleanup. Inferred
  from code, not reproduced. (Session 530145bc, client-fixes agent
  abdbfdf9, 2026-10-12.) H37 (10-14): Broken, Verified end to end in 2
  runs (verify item 4d); a sign-in over a guest hits it too (AN-1b).

## H48 (2026-10-15, shortened by the diet)

- **H48** · The 10 s server grace may be too short for WebRTC signaling.
  mm: not measured. Fix: time signaling in a WebRTC run; start the grace
  after signaling (S; batch 3; `docs/design/H37_systems_audit.md` 3.3
  list)

## H62 (2026-10-15, shortened by the diet)

- **H62** · Link errors match AWS-era codes, so the merge path is dead
  (LK-4, LK-2). acct: LK-4 Broken by code.
  `link_account_row.gd:159,209`; `sdk:core/auth_api_client.gd:871-874`
  (prefix inferred). Fix: match Nakama's codes; route AlreadyExists to
  H57's merge decision (S; batch 4; `docs/design/H37_systems_audit.md`
  3.1 list)

## H64 (2026-10-15, shortened by the diet)

- **H64** · A guest's server calls go out with an expired JWT after 2 h
  (AN-3). acct: Believed, low. `backend_api_client.gd:528-536`. Fix:
  refresh the guest JWT when it expires, not only when none is stored
  (S; batch 4; `docs/design/H37_systems_audit.md` 3.1 list)

## H63 (2026-10-15, shortened by the diet)

- **H63** · The Log Out row is hidden when the access token has expired
  (AP-1), with DEL-1. acct: AP-1 Believed, low-medium. Fix: always offer
  Log Out; clear locally when the server call fails (S; batch 4;
  `docs/design/H37_systems_audit.md` 3.1 list)

## H73 (2026-10-15, shortened by the diet)

- **H73** · Harness friction: loopback runs warn of production; client 2
  starts 30 s late in matchmaker runs; screenshots are black for about
  0.7 s after a screen change (S; batch 6;
  `docs/design/H37_systems_audit.md` 1.2 gaps, section 4 step 3)

## H75 (2026-10-15, shortened by the diet)

- **H75** · Harness sign-in plus `publish` and `wait_shared` steps; a
  fake `Platform.party` for GUT (M; batch 6;
  `docs/design/H37_systems_audit.md` 1.2 gaps, 1.3 rows 6 and 7, section
  4 step 3)

## H72 (2026-10-15, shortened by the diet)

- **H72** · Exported-build runs for the harness (a custom 4.7.2
  template) (M; batch 6; `docs/design/H37_systems_audit.md` section 4
  step 4)

## H68 (2026-10-15, shortened by the diet)

- **H68** · Legal parity is checked only by pr-validate, which never
  runs on push (C2); `edgegap_app_version` is not in the sync's
  mustSurvive list (C3) (S; batch 6; `docs/design/H37_systems_audit.md`
  3.4)

## H66 (2026-10-15, shortened by the diet)

- **H66** · V17: 22 broken format strings, among them the refused-pause
  ERROR at `game_panel.gd:1854` (exec-b #10). 17 here; RN7 and SP49 hold
  the rest (S to M; batch 7; `docs/design/H37_systems_audit.md` section
  5 row 2, 3.3 list)

## H7 (2026-10-15, shortened by the diet)

- **H7** · The check that keeps new spawns off other players can't see
  bunnies that are still blinking, so a respawn can land on one. Left
  alone as a player-versus-player rule. (Session 530145bc, invincibility
  agent a25807d3, 2026-10-11 13:19.)

## H8 (2026-10-15, shortened by the diet)

- **H8** · Possibly the same origin slide at first spawn (unverified).
  `networked_level.gd:337-339` adds the player before positioning it, so
  local mode may show a one-tick slide from the origin when a match
  starts. 7215b1d5 fixed the same pattern for the squish sprite. (Session
  530145bc, agent a6c0fbc6.)

## H9 (2026-10-15, shortened by the diet)

- **H9** · pr-validate's "GDScript formatter" job is a no-op. It logs
  "not vendored; skipping" because `addons/gdscript_formatter` isn't in
  the repo, though CLAUDE.md says it is. (Session 530145bc, agent
  aab30fcb, 13:52.) H37 (10-14): still true; the formatter job is green
  but skips everything.

## H10 (2026-10-15, shortened by the diet)

- **H10** · Android: run the game on the Pixel. The export preset
  half is done in 4c04e908 (2026-10-13): preset.3 "Android" (arm64,
  template export, INTERNET, `games.snoringcat.hopnbop`) plus the
  ETC2/ASTC import flag; a signed 67.7 MB debug APK built and
  verified on the laptop (`--export-debug "Android"
  build/android/hopnbop.apk`; webrtc arm64 lib included). Remaining:
  install/run on the Pixel — needs the phone on USB (`adb install`,
  then Godot one-click deploy for iteration) and a touch-input pass
  (the UI is gamepad/keyboard-driven; H10's original scope).

## H17 (2026-10-15, shortened by the diet)

- **H17** · `EdgegapServerProvider` trusts each player's declared backend
  user ID instead of checking it against the validated session ID. The
  runtime now drops outsiders from `match_end` (platform f4424d5), but a
  player can still claim a fellow match player's ID. (Session 530145bc,
  admin-key agent a654b0d8, 2026-10-12.) H37 (10-14): a probe confirmed
  it (report 3.3, G1.1 to G1.3); SP27 and H41 fix it.

## H18 (2026-10-15, shortened by the diet)

- **H18** · Raw SDK error text reaches players: the party panel shows
  SDK errors as-is (a "Not authenticated" toast), and the delete, export
  and merge failure toasts append raw errors. (Agent abdbfdf9.) H37
  (10-14): also the social R4 repro, the export toast
  (`export_data_row.gd:96-99`) and the poll toast
  (`friends_panel.gd:342-354`).

## H20 (2026-10-15, shortened by the diet)

- **H20** · Cancelling matchmaking, or a fatal matchmaking failure,
  returns to a lobby without the player's bunny. Inferred from code.
  (Agent abdbfdf9.) H37 (10-14): still true. Fix: `copy_latest_state` at
  `game_panel.gd:673` and `779`, as at 694.

## H22 (2026-10-15, shortened by the diet)

- **H22** · Log-out first tells the server the player went offline, so
  with no connection the consent screen appears only after that times
  out (about 9 s in the harness). (Agent abdbfdf9.) H37 (10-14): still
  true, about 9 s measured.

## H23 (2026-10-15, shortened by the diet)

- **H23** · The notification socket stops on any failed sign-in result,
  transient refresh failures included, until the next successful
  refresh. (Agent abdbfdf9.) H37 (10-14): still true; a failed
  `delete_account` (DEL-2, SP41) is one more trigger.

## H24 (2026-10-15, shortened by the diet)

- **H24** · `Player._enter_tree` registers the player before its id is
  set, leaving a stale `players_by_id[0]` entry on the server; the code
  comment there says the id is set first. (Session 530145bc, harness
  agent a9dc5b3c, 2026-10-11.) H37 (10-14): still true, low.

## H26 (2026-10-15, shortened by the diet)

- **H26** · After a preview server hot-reload, levels get
  auto-generated names (`@Node2D@39`), so each client logs about 35
  replication errors (Snail_0 not found, ids missing from the cache).
  (Agent a9dc5b3c.) H37 (10-14): it reaches players (exec-b run 2:
  Verified; the production scope Believed; report 3.3).

## H27 (2026-10-15, shortened by the diet)

- **H27** · Local/offline mode logs "RPC on yourself is not allowed"
  errors (`_server_rpc_ping`, `_rpc_init`). (Agent a9dc5b3c.) H37
  (10-14): still present, Verified. Fix: an `is_local_mode` guard at
  `frame_synchronizer.gd:120`, and skip the local peer at
  `networked_level.gd:307`.

## H28 (2026-10-15, shortened by the diet)

- **H28** · About half of lobby runs log an `AudioStreamWAV`
  (`pause_menu.wav`) leak warning at exit, before and after the
  PerfTracker fix. Noted in CLAUDE.md. (Agent a55477032.) H37 (10-14):
  see H86 (CR6).

## H29 (2026-10-15, shortened by the diet)

- **H29** · Unused code: `BinaryToggle`, and `fetch_player_stats`,
  `fetch_match_history` and their signals in `backend_api_client.gd`
  since the leaderboard and My Stats rewrite (f77828e8). (Leaderboard
  agent abbaef7c.) H37 (10-14): still true.

## H31 (2026-10-15, shortened by the diet)

- **H31** · The credits screen's existing labels ("Made by", "Sound",
  "Credits", "Thanks for playing!") have no translation keys, so other
  locales show English next to the translated DB-IP row (87523bb3).
  (Privacy agent a834b111.) H37 (10-14): the labels are at
  `credits_screen.tscn:40,55,70,85,114`.

## H35 (2026-10-15, shortened by the diet)

- **H35** · `test_party_matchmaking_context.gd` fails 7 of its 11 tests
  under a full `-gdir=res://test/unit -ginclude_subdirs` run but passes
  11/11 alone: state bleed from earlier scripts, not a product bug
  (2026-10-12, Godot 4.7.2 + GUT 9.7.1, suite otherwise 485/492).
  pr-validate's per-file loop doesn't hit it. H37 (10-14): 11/11 per
  file again (exec-a); the full-directory run was not repeated.

## H52 (2026-10-15, shortened by the diet)

- **H52** · Inert `game.yaml` `matchmaker_rules` fields; the same-device
  preference its comment claims does not exist. mm (read). Fix: delete
  `ticket_expiry_seconds`, `cross_play` and `rules`, or wire them; fix
  the comment (XS; batch 3; `docs/design/H37_systems_audit.md` 3.3 list)

## H47 (2026-10-15, shortened by the diet)

- **H47** · transport.md drift: the retry count, port 4433 vs the real
  4434/TCP, a GameLift fleet paragraph. mm (read).
  `.claude/rules/transport.md`. Fix: correct all three (XS; batch 7;
  `docs/design/H37_systems_audit.md` 3.3 list)

## H107 (2026-10-29, muse 01a189f7)

Diagnosis from the full failed logs (gh run view --log), not flakes.
Run 40957663588: Install-Package found no powershell-yaml on PSGallery
and scripts/sync-game-config.ps1 did not retry, so registration died.
Run 40956932238: every authenticate lacked vars.game_id. Under GUT the
Platform autoload is initialized by G (src/core/global.gd _enter_tree,
line 127) with game_id hopnbop, and the compliance helper reads that.
In this run res://settings.tres failed to load (Parse Error at
settings.tres:64: ext_resource referenced non-existent
res://assets/images/level_thumbnails/level_0.png; the background.png
errors are the same incomplete-import class), so G.settings was null,
settings.apply_release_overrides() errored at global.gd:108, _enter_tree
aborted before Platform.initialize, and _resolve_game_id() fell back to
a PLATFORM_GAME_ID that local-smoke-test.ps1 never set. With a game
registered, the runtime (runtime/auth.go validateGameIDInVars) rejects
an empty id. Fixes: sync script retries the install 3 times; the smoke
script sets PLATFORM_GAME_ID from game.yaml's game_id for the suite.
No helper fail-fast: the platform SDK CI (run.sh) already sets
PLATFORM_GAME_ID=sdkci for its throwaway game, and the runtime accepts
an empty id when no game is registered, so an empty-id push_error
would break that bootstrap path for no determinism gain.
