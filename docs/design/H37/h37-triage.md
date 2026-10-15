# H37 TODO-scratch triage

Started 2026-10-14 09:34:17 -07:00 (h37-triage, claude session 40ecd3b7 coordinator).
Repos at: hopnbop 44f0093e, platform 8e85e8a, netcode 7d6ebd9.
Scripts and data: `h37-triage/blame_dates.ps1` (maps each TODO line to its
first-added date), `h37-triage/line_dates.csv` (per-line date + commit).

## Dating (method and result)

- `git -C addons/rollback_netcode blame 6022552 -L 46,875` attributes lines
  52-838 (and 9-12, 30-49) to 78427ce0, the 2026-04-25 bulk import
  ("Phase 3a: Extract addon contents from hopnbop_private"), which hides the
  real age. Real first-added dates come from hopnbop's own pre-submodule
  history: `git -C hopnbop blame -M -C 26966654 -L 46,870 --
  addons/rollback_netcode/core/frame_driver.gd` (follows the file back to
  `src/networking/network_frame_driver.gd` and `src/core/game_panel.gd`).
  Lines were aligned by exact text; all 830 matched.
- Age bands (TODO-scratch line ranges):
  - 14-21: 2026-10-14, netcode 6022552 (the six fresh "Main list" notes).
  - 13, 22-29, 50-51: 2026-07-16, netcode b4c94737.
  - 30-49: 2026-03-28 to 04-25 (multi-game refactor 04-25, warm-up 04-11,
    foobar 04-10, level_0 art 04-01, remote-anim glitches 03-28).
  - 52-245: 2026-03-02 to 03-31 (test list, leaderboard/friends/party,
    disconnects, AWS-era notes, release tasks; water splash L225 03-31).
  - 246-523: 2026-02-06 to 03-10 (milestones, setup checklist, art plans,
    devlog, input-delay reference, GitHub Actions).
  - 524-838: 2026-01-11 to 02-21 (rollback debug-UI plan, early polish
    list, UI fixes, camera, mobile, decoupling, after-everything list,
    holidays, devlog). Everything before 2026-05-03 predates the end of
    the AWS era.

## Finding 1: the six "fresh" notes are the input to the 10-11 fixes, not new reports

Observed in claude session 530145bc's transcript: at 2026-10-11 17:39 UTC
Levi pasted exactly these six notes ("Also, I have these notes from a
recent session. Please address each of them."). At 19:00 UTC the session
reported "six game notes are done, pushed, and verified. Nothing was
tested in a live networked match", verified by frame-stepping tests,
screenshots and the local suite. At 23:09 UTC a `git diff` in that session
already shows the six lines as uncommitted additions to
`core/frame_driver.gd`. A Claude session committed them verbatim on
2026-10-14 00:34 as netcode 6022552 ("queue six more items"), which is why
blame dates them 10-14. So the brief's premise (notes written after the
fixes, hence regressions) does not hold: they are Done, pending Levi's
in-game check, ideally in a networked match. Commits:
- crown recolor: hopnbop a1b32155 "crown: re-export overlay without the
  brown body layer";
- death blink at origin: 7215b1d5 (squish sprite placed before add_child)
  + 10416583 (frame-stepping death/respawn test); related open residuals
  H3 (blink 1-2 frames before respawn) and H8 (possible first-spawn slide);
- water respawn splash: 28748f60 (refresh water state while dead); related
  H6 (splashes fire twice);
- resting bunny on the player card: eb4da2d3 (HUD card);
- springs while invincible: bbf9694b; related 52ab4ac5, 0a1a00a9, H7;
- Godot 4.7.2: ee491657 (CI pins); the session's research concluded none
  of the 57 fixes needs code changes (assistant reply 10-11 18:06 UTC,
  citing godotengine.org/article/maintenance-release-godot-4-7-2).

## Verification notes (evidence per item; the table below cites these)

- V1 multi-game refactor (L30-31): the named plan
  `~/.claude/plans/in-general-i-ve-been-snoopy-pearl.md` does not exist on
  this machine (no `~/.claude/plans/` at all; the 2026-05-12 audit,
  `docs/archive/FRIENDS_PARTY_MATCHMAKING_AUDIT.md:589-593`, already found it
  missing, possibly laptop-only). The work it named was done as
  `MULTI_GAME_ROADMAP.md` (hopnbop root, 7,472 lines, a99e1061 2026-05-12),
  57 "multi-game:" commits 05-12..05-22; its status summary (line 34) says
  "Roadmap functionally complete (2026-05-15, twenty-fifth pass)". Stale
  pointers remain: `third_party/snoringcat-platform/CLAUDE.md:15-17` still
  sends readers to the dead plan path, and the roadmap itself sits at the
  repo root instead of `docs/archive/`. The decoupling it did not finish is
  netcode RN1 (addon compiles only inside hopnbop).
- V2 offline colors (L23, added by 07-16): ac2f6bf8 (2026-06-17) fixed
  "declare-then-count flows (e.g. offline play) never assign colors"
  (`src/core/match_state_synchronizer.gd:162-178`). The note postdates that
  fix, and it sits under "play offline; end match; play again", so the open
  suspicion is the play-again path. Unverified.
- V3 Alt+Enter (L24): no Alt+Enter handler in hopnbop (`src/core/
  window_manager.gd:15-33` only applies `G.settings.full_screen`; the
  settings toggle calls it, `src/ui/settings_panel/toggle_row.gd:109`),
  nor in scaffolder (`src/scaffolder/scaffolder_shell.cpp:39-44`, applies
  the setting once) or bootstrapper. Care: Enter is a jump key
  (`src/core/input_device_manager.gd:34`).
- V4 rainbow gore (L25-27): no rainbow, hue-cycle or color-sequence code in
  `src/objects/gore/` or any shader; `git log -S rainbow` finds only the
  log banner. The effect the note describes is not in the tree (maybe
  never committed, or it is a texture/animation asset). Open; needs Levi to
  say which effect he means.
- V5 remote-player animation glitches (L48, 03-28): the investigation doc
  is `docs/archive/REMOTE_PLAYER_STATE_GLITCHES_session_context.md` (stuck
  facing, walk/jump jitter, remote bunnies always in jump-fall, in
  3-instance preview). `MULTI_GAME_ROADMAP.md:7438-7459` marks it
  "verified-likely-resolved-in-code 2026-05-15": the doc's proposed fix
  shipped (`character_state_from_server.gd::_pack_buffer_state_from_network_state`
  captures `surfaces` from every server state), and netcode 6065de3 showed
  the 50-92% "packet loss" behind the theory was a perf_tracker artifact.
  It also says "Multi-client smoke at the keyboard would confirm; until
  then, treating this as resolved." Believed done; never observed fixed.
  Verdict: Open-verify (a networked look, not code work).
- V6 overhead labels (L93, 03-14 21:49): `src/ui/hud/player_overhead_labels.gd`
  was last changed 03-14 13:51 (58ff99fb), eight hours before the note, so
  nothing has touched the complaint since. The investigation left a
  diagnostic in every client (`player_overhead_labels.gd:74-102`): every 2 s
  it compares `pixel_viewport_manager.get_world_to_screen_transform()` with
  the sub-viewport's native screen*canvas transform and prints "LABEL
  XFORM MISMATCH" on a difference. Its format string is broken: `%` binds
  tighter than `+`, so only the last fragment gets the six arguments.
  Verified with a headless Godot 4.7.2 copy of the expression
  (`h37-triage/gdtest/precedence_test.gd`): it logs "ERROR: String
  formatting error: not all arguments converted" and prints the raw `%s`
  placeholders. Engine errors don't reach the crash reporter (it reports
  only `G.log.error` and previous-session crashes, `crash_reporter.gd:6-9`),
  so the cost is log noise plus a diagnostic that cannot report. No
  harness log under `.claude/probes/H37/` contains the mismatch line.
  Verdict: Open, M, P2; the offset did not reproduce offline (V26), so
  it needs a networked repro first.
- V7 springs "still broken sometimes" (L89, 03-28): the only spring change
  since is bbf9694b (10-11): respawn invincibility cleared the player layer
  the spring trigger watched, so invincible bunnies passed through springs,
  and level_4/5 spawns sit next to springs ("came up constantly"). That is
  a likely cause of "sometimes". Remaining by code reading: the bounce is
  server-only from an Area2D `body_entered` (`src/objects/spring/spring.gd:11-22`,
  `src/player/bunny.gd:126-145`) and is skipped while the server is
  resimulating. Believed Done by bbf9694b; Open-verify.
- V8 standing on players at an angle (L86, 03-28): the kill/bump code in
  `src/player/bunny.gd` (swept foot-through-head check near line 1060) last
  changed 02-20 (711908f9); no later commit mentions it. Open, unverified;
  needs a two-bunny repro.
- V9 snore on the studio splash (L140, 03-13): `scg_splash_screen.gd:9-22`
  plays "scg_splash" (`assets/audio/old/single_cat_snore.wav`, about 0.92 s)
  on open and leaves after `scg_splash_duration_sec := 0.9`
  (`settings.gd:123`); neither file changed after 03-08. It plays through
  the global `G.audio` (`scg_splash_screen.gd:12`), so the clip is not cut
  off; the screen simply leaves as the clip ends, and any opening
  transition comes out of the 0.9 s (inferred). On web the first sound
  before any user gesture is blocked by browser autoplay rules, so a
  delay alone cannot fix web. Open, S, P3.
- V10 sfx on every button (L142, 03-13): `MenuRow.on_trigger()` is a no-op
  (`src/ui/menu_row.gd:82`) and `side_panel.gd:392-394` dispatches triggers
  without a sound; 13 of 16 MenuRow subclasses (action, back, close,
  credits, delete-account, export-data, link-account, link, log-out, quit,
  screen-trigger, sub-panel-trigger, text-input rows) never call
  `play_sound`; only toggles, level prefs and language rows play "select".
  Some get an indirect "focus" sound when a panel opens. Believed Open, S,
  P3, low-hanging (one call in the dispatcher).
- V11 tooltips (L241, 03-13): zero `tooltip_text` in `src/` and no tooltip
  keys in `translations/ui_translations.csv`. Open, M, P3; worth less in a
  gamepad-first UI.
- V12 lingering FIXMEs (L399, 02-21): 25 in `src/` (none in the netcode
  addon); 24 are `FIXME(end-of-match-debug)` web breadcrumbs from 05-18
  (4b70b09d). `src/core/web_debug_watchdog.gd:33-46` says the investigation
  is open: black-screen-after-match was fixed in f2fc40ea, but a web
  GAME_OVER -> LOBBY 0.5 s auto-dismiss "was never reproduced ... and
  remains unexplained". That bug is in no ledger. The one other FIXME:
  `src/scaffolder/character/one_way_collision_validator.gd:10`.
- V13 polish list (L144-160, 03-13 23:35): heavy UI work since (commits
  touching game over 16, friends 17, auth 11, leaderboard 8, credits 7,
  consent 6, loading 6); the toast alert icon landed 30 min before the
  note (fda8c3bb) and the toast changed again 03-14 (58ff99fb). Needs a
  fresh pass by eye; known leftovers are H18 (raw SDK errors in toasts)
  and H31 (credits labels lack translation keys).
- V14 Done items with commits: legal docs in-game (L166-168):
  `src/ui/screens/legal_doc_screen.gd:152-154` loads `res://legal/<locale>/`
  with an `en` fallback, added 64f5eb8e (03-14); age gate (L303):
  `CONSENT.AGE_CONFIRM` "I am 13 years or older", 13bb063e (03-10);
  loading-screen status text (L330-333): `LOADING.CONNECTING`,
  `AUTHENTICATING`, `IN_QUEUE`, `EXPANDING_SEARCH`, `WARMING_UP_SERVER`
  (`loading_screen.gd:93-156`, 13bb063e and 3d392c6c); lobby podium
  (L216): `src/level/lobby_level.tscn:95` instances AwardPodium (H5 says
  its bunnies never animate); controller (L164): 35 joypad events in
  `project.godot`, not yet tested by hand (the harness drives keys only).
- V15 level art (L40-46, L90-92): level_0 art is mid-update
  (efe2959f 05-23 "art: WIP level 0 update"); `level_4.tscn` and
  `level_5.tscn` reference no image textures (tiles only), so their art is
  Open; `assets/images/levels/foobar.png` (the "foobar image", last
  touched 04-12) is referenced by nothing. Cruft that ships: every export
  preset uses `all_resources` with no exclude for these, so the unused
  `Screenshot 2026-03-15 135643.png` (300 KB), `foo.png`, `foobar.png`,
  `levels.png` and `level_0_combined.png` go into every build, and three
  `level_4_combined*.png.import` files have no PNG.
- V16 Snoring Cat presence (L233-235): `inner-tube-climber`'s last commit
  is 2021-03-31 (Open); `snoringcat.games` moved to Cloudflare on 04-27 and
  its index mentions Hop 'n Bop (believed Done for "update").
- V17 string-format precedence bug class (relates to L93 and the release
  checklist's logging line L180). GDScript `%` binds tighter than `+`, so
  `"a %d:" + " b" % x` formats only the last fragment. Verified with
  Godot 4.7.2 (`h37-triage/gdtest/precedence_test.gd`, output in
  `precedence_test.log`): the engine logs `ERROR: String formatting error:
  not all arguments converted during string formatting` and the message
  prints with raw `%s` placeholders; execution continues. A static scan
  (`h37-triage/fmt_precedence_scan.py`, hits in `fmt_precedence_hits.txt`)
  finds 22 sites, Believed by reading:
  - hopnbop `src/` (17): `core/cheat_manager.gd:130`;
    `core/game_panel.gd:1842, 1856, 2300, 2502, 2533, 2547, 2563, 2579`
    (pause rejections and warnings); `level/networked_level.gd:239`;
    `player/bunny.gd:260, 285`; `scaffolder/draw_utils.gd:50` (a fatal);
    `scaffolder/geometry.gd:778` (an ensure);
    `scaffolder/character/character_state_from_server.gd:1322`;
    `scaffolder/character/player_input_network_state.gd:145`;
    `ui/hud/player_overhead_labels.gd:93` (the V6 diagnostic, unguarded).
  - netcode (4): `core/network_connector.gd:284` (a `log.error`, so the
    crash report would carry the raw placeholder);
    `core/webrtc_game_peer.gd:78`; `core/webrtc_signaling_server.gd:371,
    432`.
  - platform (1): `addons/snoringcat_platform_client/test/compliance/
    test_account_delete.gd:118`.
  The bunny and character_state_from_server hits are behind
  `Netcode.log.is_verbose`; the argument is still evaluated whenever the
  call runs, so a guard is what keeps them quiet. Engine ERROR lines are
  not crash-reported (`src/core/crash_reporter.gd:6-9` reports `G.log.error`
  and previous-session crashes only), so nothing upstream sees these.
  Fix: wrap each concatenation in parens; the scanner could become a
  pr-validate step (S-M, P2, low-hanging).
- V18 rollback debug UI plan (L524-652, 01-19): nothing of it exists. No
  hits for `is_network_pause_debug_shortcut_enabled`,
  `is_network_rollback_state_buffer_debug_ui_visible`,
  `is_network_pause_on_rollback_enabled`,
  `is_visualizing_server_instead_of_client_rollbacks`,
  `RollbackVisualInterpolationOffset` or F1/F4/F12 shortcuts; the only
  EditorPlugin is `addons/rollback_netcode/plugin.gd`. Idea, XL.
- V19 fly audio (L486-493): code done, assets missing.
  `src/objects/flies/fly_swarm.gd:115-122` points at
  `res://assets/audio/sfx/fly_buzz_positional.ogg` and
  `fly_buzz_ambient.ogg`; lines 139-140 and 511+ build the positional and
  ambient players with pan noise; `assets/audio/sfx/` does not exist, so
  flies are silent. The loads sit behind `ResourceLoader.exists`
  (`fly_swarm.gd:512`, `:526`), so nothing logs it: every networked level
  spawns `fly_swarm_count` swarms (`networked_level.gd:15`, `:527-531`)
  and the two offline runs (V24, V26) show no audio error. Open, S once
  the sounds exist (needs audio).
- V20 older items that are Done (Believed, by code): adaptive input delay
  (L453-478 reference) is `addons/rollback_netcode/core/
  frame_synchronizer.gd:360-385` `_update_input_delay()` (target = one-way
  latency in frames, +-1 per pong; `network_settings.gd:121,125`
  enabled, max 8 frames), added 3e46cd61 (02-09); screen shake
  (L654) `src/core/camera_shaker.gd:36`, called from `bunny.gd:685,731`
  and `match_end_celebration.gd:113`; countdown sounds (L695-706)
  `match_start_countdown.gd:109-111`, `match_end_countdown.gd:95,103`,
  `bunny.gd:852`; sleeping bunnies during the countdown (L707-708)
  `bunny.gd:343-348`; lobby control indicator (L693-694) done as
  `src/level/control_displays.gd` (instanced `lobby_level.tscn:8`); gore
  setting (L670-676) `SETTINGS.GORE`, default off `settings.gd:133`,
  persisted `local_settings.gd:41,52`; "remove claude/anthropic mentions"
  (L782-816): only three comments pointing at CLAUDE.md remain
  (`cheat_manager.gd:123`, `cricket.gd:148`, `snail.gd:646`).
- V21 camera (L728-734): each level has one static `level_camera`
  (`.claude/rules/ui.md:184-197`); no follow camera, no split screen. The
  static mode is Done; the other modes are Ideas.
- V22 networked pause (L774 "Disable networked pause", 02-21): still on.
  `addons/rollback_netcode/core/network_settings.gd:99` defaults
  `is_server_pause_enabled := false`, but the committed `settings.tres:154`
  sets it `true` (and `:155` `pause_request_cooldown_sec = 0.5`);
  `Settings._apply_release_values()` (`src/core/settings.gd:385-389`)
  overrides only match duration, HUD, overhead labels and splash. Limits
  enforced by `game_panel.gd:1833` `_server_validate_pause_request`
  (default 1 pause per client, 60 s max). Open: a decision for Levi.
- V23 web loading screen (L387-388): `export_presets.cfg:30` uses
  `res://web/shell.html`, which shows `logo.png` over a dark background
  with a progress bar (38777e2c, 03-10; the Godot splash `img` is
  `display: none`). Bespoke level-inspired art: Open, art, P3.
- V24 offline play again + colors (L22-23, 07-16): Verified working for
  one local keyboard player. Harness run
  `h37-triage/runs/20261014-095855-offline-play-again-colors/` (scenario
  `h37-triage/offline-play-again-colors.json`: offline level_4, 10 s match,
  `G.game_panel.client_play_again()` with `prefer_offline_mode` on): PASS
  16/16; `base_color` is `(1, 0, 0, 1)` in both matches, the log shows
  "Assigning colors to 1 players" and a red "Applied outline" after the
  replay, and `match2.png` shows the second countdown. The 16 engine
  errors are H27's "RPC on yourself" lines. Not covered: two or more
  local players (controllers), and the real button path.

### Addendum to V22 (networked pause is reachable in release)

Believed, by code: `src/core/input_handler.gd:126-138` sends
`client_request_toggle_pause()` on `toggle_pause` (Escape,
`physical_keycode` 4194305) whenever `G.settings.is_server_pause_enabled`
and a networked level is active, with no `Netcode.is_debug` guard (the
debug toggles above it have one). So in a release online match each
player can pause everyone once, for up to 60 s. Dating: the limits were
added c8f168c4 (02-05) and `settings.tres` turned the flag on 2d2444ba
(02-06); the "Disable networked pause" note is from 02-21, after both.

### V25. T79: web GAME_OVER -> LOBBY auto-dismiss (code reading only; Believed, not reproduced)

The breadcrumbs (`web_debug_watchdog.gd:33-46`) were never captured on a
repro. Reading the paths that can leave GAME_OVER for LOBBY:

Ruled out by reading:
- `screens_main.gd:190-201` (opening GAME_OVER while `is_game_active`
  calls `client_exit_match()`): `_client_transition_to_game_over`
  (`game_panel.gd:1443`) defers `_client_cleanup_after_match`, which
  clears `is_game_active` (`:1268`), ahead of the deferred
  `_client_free_levels_and_open_screen(GAME_OVER)`, so the flag is
  already false when the screen opens. The V24 offline run agrees
  (GAME -> GAME_OVER, no LOBBY).
- A normal end classed as an unexpected disconnect: the client's
  `is_match_ended` is set only by `client_notify_match_ended`
  (`game_match_state.gd:178`) and cleared only by `clear()` in
  `_client_spawn_lobby` / `_client_start_local_mode`; the server's own
  reset (`game_panel.gd:1625`) is not replicated. Note the server never
  sends `MATCH_FINISHED` (only the enum, `network_connector.gd:48`, and
  the check, `game_session_manager.gd:499`), so `is_expected` rests
  entirely on that one client flag.

Remaining candidates, cheapest to test first:
1. **Input, no grace period.** The screen returns to the lobby on any
   fresh Left edge (`game_over_screen.gd:76-90`; Left is the movement
   key, read via `Input.is_action_pressed(&"move_left")` in the
   platform poller, so a stick resting at the deadzone can flicker)
   and on `close_menu` (`:70`; Escape, which is also the networked
   pause key). `prime()` (`:133`, `:582`) masks only keys held at open.
   The existing breadcrumbs (`navigator_poll_returned_true` with its
   direction, `_unhandled_input.close_menu`) separate this case at
   once.
2. **A reconnect loop that outlives the match.** `reconnect_handler`
   is started at `game_panel.gd:538` and nothing outside it calls
   `stop()`. A loop begun by a late-match blip runs on through
   GAME_OVER; on give-up (`_GRACE_SEC` 30 s, `reconnect_handler.gd:48`)
   `_on_reconnect_failed` calls `client_exit_match()` (`:574`), which
   has no screen guard (`:1414`). That dismissal comes with a
   RECONNECT_FAILED toast and at an arbitrary delay, so it fits the
   symptom only loosely.
3. A lost or late `client_notify_match_ended` on WebRTC makes the
   disconnect "unexpected" (`:556` -> LOBBY), but then GAME_OVER never
   shows first: it explains a skip, not a dismiss.

Suggested fix order: a 0.3-0.5 s input grace on the game-over screen;
stop the reconnect loop in `_client_transition_to_game_over`; then one
web 2-client match with the breadcrumbs on before deleting them (T79).

### V26. T29 labels offline (Verified for one local player, two window sizes)

Harness runs, offline, level_4, one keyboard player, labels forced on:
- `h37-triage/runs/20261014-101535-offline-labels/` (scenario
  `h37-triage/offline-labels.json`, `-WindowSize 1100x900`): PASS 7/7.
  `get_world_to_screen_transform()` and the sub-viewport's native
  screen*canvas transform evaluate identical (scale 2.426471, origin
  (821.7647, 738.75)); `labels.png` shows the name centered over the
  bunny; no "LABEL XFORM MISMATCH" line and no format error in
  `process.log`. The 8 errors are H27's RPC-on-yourself lines (7
  `_server_rpc_ping`, 1 `_rpc_init`) plus the usual resources-at-exit line.
- The V24 run (default 1360x765) has no mismatch line either.

So the diagnostic never fired here and the offset is not a
single-player, windowed, offline effect. Untested: remote bunnies in a
networked match (the note says labels differ across clients),
fullscreen, web, and odd scale factors. T29 stays Open, verify first.

### V27. Debug toggles in release (Believed, code reading)

- Every shipped export uses `--export-release` (`release.yml:115`,
  `scripts/deploy-cf-pages.ps1:109`, `game-server.yml:153`), so
  `Netcode.is_debug` (`network_orchestrator.gd:186`:
  `OS.is_debug_build() or is_preview`) is false for players and the
  debug console, annotations and perf-tracker toggles
  (`input_handler.gd:12`, `:41-61`) stay unreachable. The pause toggle
  (`input_handler.gd:126-138`) has no such guard (V22 addendum).
- Doc drift: hopnbop `CLAUDE.md` "Configuration" names
  `perf_tracker_enabled` and `debug_console_enabled`, which do not exist
  (the fields are `show_debug_console` and `show_perf_tracker`,
  `settings.gd:65-67`), and `dev_mode` (`settings.gd:59`, default true)
  is read nowhere in the three repos. S, P3.

### V28. T19 PlayerDisplay list layout (observed for one player; rest inferred)

The note (L80, 03-28) asks to test a layout that already existed:
`src/ui/hud/hud.gd:78-101` (8abb1f39, 03-24) shows the vertical list at
the right when the window aspect is at least 1.3 (`hud.gd:5`) and the
horizontal list at the bottom otherwise. Each display is at least
180x90 (`player_display.tscn:27`), the horizontal list separates them by
20 (`player_list.tscn:11`) and has no wrap or scale logic
(`player_list.gd` extends `BoxContainer`); matches hold 2-4 players
(`game.yaml:111-112`).
- Observed, one player: at 1360x765 the vertical panel sits over the
  level's right wall and corner (V24 `match1.png`); at 1100x900 the
  horizontal panel covers part of the floor at bottom centre (V26
  `labels.png`).
- Inferred: four stacked displays would cover the right-hand platforms
  at 16:9; four side by side need about 780 px of UI width. Not
  checked: four players, party members, live resizing, web or mobile.
Verdict stays Open, verify first; S to look, M if the panel needs to
move off the playfield.

## Item table (file order)

Lines are `TODO-scratch.md` lines; Added is the first-added date range
(2026, from `h37-triage/line_dates.csv`). Areas: gameplay, art, UI (UI
polish), dist (distributed systems), store (platform/store), release
(release process), biz (business/ops), aspir (aspirational), ref
(reference/prompt text). Size S < 1 h, M < 1 day, L < 1 week, XL more.
Pri: P1 player-facing bug or blocker, P2 quality, P3 nice to have. LH:
low-hanging. Owner: the H37 domain agent for distributed items, a ledger
item, or Levi where only he can act. Rows marked "Quick:" or "Owner:" leave
the full verdict to that agent. Generated by
`h37-triage/make_table.py` from `h37-triage/items.txt`.

| ID | Lines | Added | Note | Area | Verdict and evidence | Size | Pri | LH | Owner |
|---|---|---|---|---|---|---|---|---|---|
| T01 | 9-13 | 01-27..07-16 | Section headers | ref | Reference | - | - | - | - |
| T02 | 14 | 10-14 | Crown pickup changes bunny color | gameplay | Done a1b32155 (10-11, Finding 1); live 2-client look pending | - | - | - | - |
| T03 | 15 | 10-14 | Death blinks sprite at level origin | gameplay | Done 7215b1d5, test 10416583 (Finding 1); H3, H8 nearby | - | - | - | - |
| T04 | 16 | 10-14 | Water respawn splash at wrong position | gameplay | Done 28748f60 (Finding 1); H6 nearby | - | - | - | - |
| T05 | 17 | 10-14 | Resting bunny on the player card | UI | Done eb4da2d3 (Finding 1) | - | - | - | - |
| T06 | 18 | 10-14 | Springs ignored while invincible | gameplay | Done bbf9694b, 52ab4ac5, 0a1a00a9 (Finding 1); H7 nearby | - | - | - | - |
| T07 | 19 | 10-14 | Research Godot 4.7.2 changes | release | Done ee491657 (Finding 1) | - | - | - | - |
| T08 | 22 | 07-16 | Play offline, end match, play again | gameplay | Verified for 1 keyboard player (V24); 2+ local players and the button path untested; H27 log noise | S | P2 | yes | triage, h37-matchmaking |
| T09 | 23 | 07-16 | Colors not working offline | gameplay | Verified assigned after replay for 1 player (V24); fix ac2f6bf8 (06-17) predates the note; 2+ local players untested | S | P2 | yes | triage |
| T10 | 24 | 07-16 | Alt+Enter fullscreen in scaffolder, bootstrapper, hopnbop | UI | Open: absent in all three (V3); Enter is a jump key | S | P3 | yes | - |
| T11 | 25-27 | 07-16 | Gore rainbow: random preset sequences, random offset; white sprites | art | Open, needs Levi: no rainbow transition found in code (V4) | S | P3 | no | Levi |
| T12 | 30-31 | 04-25 | Multi-game architecture refactor (plan file) | dist | Done as MULTI_GAME_ROADMAP.md (a99e1061, 05-12); plan file gone; stale pointers (V1); RN1 left | S | P3 | yes | - |
| T13 | 33-38 | 04-11 | Test the new warm-up logic | dist | Quick: labels exist (`src/level/lobby_level.gd:97,100`, `src/ui/screens/loading_screen.gd:130`), runtime `runtime_status.go`; the 15 and 45 min timing checks are the owner's | - | - | - | h37-matchmaking |
| T14 | 40-42 | 04-10 | Finish the foobar image | art | Open: `foobar.png` unreferenced, ships in builds (V15) | M | P3 | no | Levi |
| T15 | 44-46 | 04-01 | Fix level_0 art | art | Open, WIP efe2959f (05-23) (V15) | L | P3 | no | Levi |
| T16 | 48 | 03-28 | Remote player animation glitches | gameplay | Open (verify): roadmap says likely resolved; 6065de3 traced loss to perf_tracker (V5) | S | P2 | yes | Levi (2-client look) |
| T17 | 50 | 07-16 | Don't expose Google/Apple usernames | dist | Quick: names come from generated adjective/name lists; no provider-name claim found by grep | - | - | - | h37-account |
| T18 | 52-77 | 03-28 | Image-generation prompts | ref | Reference | - | - | - | - |
| T19 | 80 | 03-28 | Responsive layout of the PlayerDisplay list | UI | Open (verify): aspect switch exists (8abb1f39); one-player screenshots show the panel over the playfield (V28) | S | P3 | yes | - |
| T20 | 81 | 03-28 | Friends presence tracking | dist | Quick: presence code and tests exist in the SDK and runtime | - | - | - | h37-social |
| T21 | 82 | 03-28 | Everything with anonymous users | dist | Quick: device (anonymous) auth implemented with tests | - | - | - | h37-account |
| T22 | 83 | 03-28 | Party matchmaking | dist | Quick: party code and tests exist | - | - | - | h37-matchmaking, h37-social |
| T23 | 84 | 03-28 | Play again | dist | Offline replay Verified (V24); online path with the owner | - | - | - | h37-matchmaking |
| T24 | 85 | 03-28 | Stats screen | dist | Quick: `src/ui/screens/my_stats_screen.gd` exists | - | - | - | h37-stats-ops |
| T25 | 86 | 03-28 | Standing on players when approaching at an angle | gameplay | Open (verify): kill check in `bunny.gd` unchanged since 711908f9 (02-20) (V8) | M | P2 | no | - |
| T26 | 87 | 03-28 | Leaderboard screen test | dist | Quick: leaderboard screen exists; see T30 | - | - | - | h37-stats-ops |
| T27 | 89 | 03-28 | Spring jump still broken sometimes | gameplay | Believed Done bbf9694b (invincibility cleared the watched layer); verify (V7) | S | P2 | yes | Levi (2-client look) |
| T28 | 90-92 | 03-28 | Level 0, 4 and 5 art | art | Open: level_4/5 use tiles only (V15) | L each | P3 | no | Levi |
| T29 | 93 | 03-14 | Overhead labels off-center, differ across clients | UI | Open, verify first: files unchanged since 58ff99fb (03-14); diagnostic with a broken format string (V6, V17); not reproduced offline at two window sizes (V26) | M | P2 | no | - |
| T30 | 95-105 | 03-14 | Leaderboard screen fixes (patterns, font, anon, filter, tab, rank) | dist | Quick: public board skips anonymous accounts (`runtime/leaderboard_public.go:40`) | - | - | - | h37-stats-ops |
| T31 | 107-108 | 03-14 | Friends panel fixes | dist | Quick: the note has no details (L108 is an empty bullet) | - | - | - | h37-social |
| T32 | 110 | 03-14 | One client replays, the other doesn't | dist | Quick: not checked here | - | - | - | h37-matchmaking |
| T33 | 112 | 03-14 | Same player on two devices | dist | Quick: no single-socket or single-session setting found by grep | - | - | - | h37-account, h37-matchmaking |
| T34 | 114-118 | 03-21 | Players disconnecting | dist | Quick: removal in `_server_on_peer_disconnected`; wins-by-default text exists (`src/ui/celebration/match_end_celebration.gd:230,234`) | - | - | - | h37-matchmaking |
| T35 | 120 | 03-14 | Crossplay auth | dist | Quick: Google sign-in has no automated coverage (CLAUDE.md) | - | - | - | h37-account |
| T36 | 122-127 | 03-14 | Party formation, matchmaking, lobbying | dist | Quick: party code and tests exist; who-gets-control is the owner's | - | - | - | h37-social |
| T37 | 131-132 | 03-13 | Steam and Epic next steps; testers | store | Open; not checkable without store accounts | L | P3 | no | Levi |
| T38 | 134 | 03-14 | Android build | store | In progress as H10: arm64 debug APK 4c04e908 (10-13); touch controls open | L | P3 | no | H10 |
| T39 | 136 | 03-14 | iOS build | store | Open: needs a Mac and an Apple developer account | XL | P3 | no | Levi |
| T40 | 138 | 03-10 | Test local mode | dist | Offline harness runs pass (V24, h37-exec-b) | - | - | - | h37-matchmaking |
| T41 | 140 | 03-13 | Snore must play on the SCG splash | UI | Open: 0.92 s clip vs 0.9 s splash; web autoplay blocks it (V9) | S | P3 | yes | - |
| T42 | 142 | 03-13 | SFX on every button click | UI | Open: 13 of 16 MenuRow subclasses play nothing (V10) | S | P3 | yes | - |
| T43 | 144-160 | 03-13 | Polish list (toasts, game over, friends, auth, ...) | UI | Partly Done (V13); needs a pass by eye; H18, H31 | M | P2 | no | Levi |
| T44 | 162 | 03-13 | Test offline mode | dist | Offline harness runs pass (V24, h37-exec-b) | - | - | - | h37-matchmaking |
| T45 | 164 | 03-13 | Test with a controller | UI | Open (verify): 35 joypad events in project.godot; harness drives keys only (V14) | S | P2 | yes | Levi |
| T46 | 166-168 | 03-13 | Legal docs in-game | UI | Done 64f5eb8e (V14) | - | - | - | - |
| T47 | 170-171 | 03-08..03-13 | AWS $100 credit | biz | Stale: AWS retired 05-03 (Hetzner + Edgegap) | - | - | - | - |
| T48 | 173-181 | 03-10 | Release checklist | release | Partly automated (7883e992, 8ca156e7, derived versions, 93b9c6fc); RPC-channel and logging checks manual; V17 is a logging bug class | M | P2 | no | - |
| T49 | 184 | 03-08 | AWS hard billing limit | biz | Stale: AWS retired; cost monitor in `.claude/rules/deploy.md` | - | - | - | - |
| T50 | 187-190 | 03-07..03-14 | Pair players by skill | dist | Idea | - | - | - | h37-matchmaking |
| T51 | 192-196 | 03-14 | Jitter reasoning note | ref | Reference; relates to T16 | - | - | - | - |
| T52 | 202-204 | 03-07 | GameLift M3 remaining items | dist | Stale: GameLift retired (Edgegap + Nakama) | - | - | - | - |
| T53 | 207-210 | 03-07 | E2E items: server API key, client test, PlayerInputNetworkState | dist | Stale: key is `NAKAMA_HTTP_KEY` on servers; class resolution covered by the circular-dependency rule | - | - | - | - |
| T54 | 213-216 | 03-07 | API key, leaderboard backfill, lobby podium | dist | API key Stale; backfill to h37-stats-ops; podium Done (`lobby_level.tscn:95`, H5 open) | - | - | - | h37-stats-ops |
| T55 | 219 | 03-05 | OAuth consent screen privacy and TOS links | store | Not checkable without console access | S | P3 | yes | h37-account |
| T56 | 225 | 03-31 | Water death respawn splash | gameplay | Done, same as T04 (28748f60) | - | - | - | - |
| T57 | 228 | 03-04 | Additional $100 from AWS | biz | Stale: AWS retired | - | - | - | - |
| T58 | 231 | 03-04 | Discord channel link | ref | Reference | - | - | - | - |
| T59 | 233-235 | 03-04 | Snoring Cat online presence | biz | Site believed Done (Cloudflare 04-27); Inner-Tube Climber not touched since 2021-03-31 (V16) | M | P3 | no | Levi |
| T60 | 239 | 03-08 | Review GameLift code, audit AWS usage | dist | Stale: AWS retired; H37 is the successor review | - | - | - | - |
| T61 | 241-242 | 03-13 | Localized tooltips on every button | UI | Open: no `tooltip_text`, no keys (V11) | M | P3 | no | - |
| T62 | 247-263 | 03-02 | AWS-era milestones | release | Stale: plan predates Phase F | - | - | - | - |
| T63 | 266-307 | 03-02..03-04 | Launch setup checklist | biz | Mostly Stale; age gate Done 13bb063e; legal pages hosted under `web/`; store accounts unknown | - | - | - | - |
| T64 | 313-317 | 03-02 | Art prompts | ref | Reference | - | - | - | - |
| T65 | 319 | 03-02 | Review tests for slop | release | Owner: test review | - | - | - | h37-exec-a |
| T66 | 321 | 03-02 | Get CI working again | release | Owner: CI status | - | - | - | h37-exec-a |
| T67 | 324 | 02-21 | Ask where auth fits with GameLift | dist | Stale: GameLift retired | - | - | - | - |
| T68 | 326-328 | 02-21 | Web transport choice | dist | Done: WebRTC for web, 30 FPS physics (`.claude/rules/transport.md`) | - | - | - | - |
| T69 | 330-333 | 02-21 | Loading-screen status text | UI | Done 13bb063e, 3d392c6c (V14) | - | - | - | - |
| T70 | 338 | 03-04 | Skinnier player annotations | UI | Open: debug overlay `src/player/player_annotations.gd`, unchanged since 03-02 | S | P3 | yes | - |
| T71 | 340-343 | 03-04 | AI art tools | art | Idea | - | - | - | - |
| T72 | 345-351 | 03-04 | Level editor | aspir | Idea | XL | P3 | no | - |
| T73 | 353 | 03-04 | Cloud-hosted levels | aspir | Idea | XL | P3 | no | - |
| T74 | 358-361 | 03-02 | Bespoke art for one level (PixelLab, occlusion, reactive) | art | Partly: level_0 under way (efe2959f WIP); occlusion and reactive art not started | L | P3 | no | Levi |
| T75 | 367-371 | 02-21..02-25 | Bespoke art and occlusion decorations for every level | art | Open; depends on T74 | XL | P3 | no | Levi |
| T76 | 373-382 | 02-07..02-25 | Animated tiles | aspir | Idea | L | P3 | no | - |
| T77 | 387-388 | 03-10 | Bespoke web loading-screen art | art | Open: shell shows the logo and a progress bar (V23) | M | P3 | no | Levi |
| T78 | 393-396 | 02-06..02-21 | Review netcode examples; retire ScaffolderTime | dist | Open: RN2; ScaffolderTime used only in `addons/rollback_netcode/utils/perf_panel.gd` | S | P3 | yes | RN2 |
| T79 | 399 | 02-21 | Lingering FIXMEs | release | Open: 24 web breadcrumbs for an unexplained GAME_OVER to LOBBY auto-dismiss, in no ledger (V12); candidate causes in V25 | M | P2 | no | - |
| T80 | 401-407 | 03-02 | Targeted reviews of key systems | release | Idea; H37 covers part | - | - | - | - |
| T81 | 410 | 03-07 | Security review of everything | release | Idea; H37 covers part | - | - | - | - |
| T82 | 413-451 | 02-21 | Devlog drafts | biz | Reference; GameLift parts Stale | - | - | - | - |
| T83 | 453-478 | 02-21..03-02 | Dynamic input delay reasoning | ref | Done as adaptive input delay 3e46cd61 (V20) | - | - | - | - |
| T84 | 486-493 | 02-21 | Fly buzz sounds | gameplay | Open: code done, sound files missing (V19) | S | P3 | no | Levi (audio) |
| T85 | 495-498 | 02-21 | Networking concepts docs | ref | Done: `docs/networking-concepts.md` | - | - | - | - |
| T86 | 503-505 | 02-21 | Publish netcode plugin to the AssetLibrary | release | Idea, blocked on RN1-RN3; GameLift GDExtension part Stale | L | P3 | no | - |
| T87 | 507 | 02-21 | Re-enable the Build GDExtension workflow | release | Stale: it built the retired GameLift extension | - | - | - | - |
| T88 | 512 | 02-21 | Local-only mode | gameplay | Done: `Netcode.is_local_mode` | - | - | - | - |
| T89 | 514 | 02-07 | Daily GitHub Actions | release | Done: nightly-smoke (03:00 UTC); health with h37-exec-a | - | - | - | h37-exec-a |
| T90 | 516-521 | 02-07 | Release workflow (dev branch, itch, AssetLib, zips, version bump) | release | Done as `release.yml` (tag to Edgegap + web); dev branch Stale (direct-to-main); itch, AssetLib, zips Idea | - | - | - | - |
| T91 | 524-652 | 01-11..01-25 | Rollback debug UI plan, parts 2-8 | aspir | Idea: nothing built (V18) | XL | P3 | no | - |
| T92 | 654-664 | 01-19..02-06 | Screen shake; PixelLab | gameplay | Shake Done (V20); PixelLab Idea | - | - | - | - |
| T93 | 665-669 | 01-19 | Hook up bunny animations and gore | art | Done (rest, walk, jump, gore effect in use) | - | - | - | - |
| T94 | 670-676 | 01-19 | Gore setting | UI | Done (V20) | - | - | - | - |
| T95 | 677-692 | 01-19..01-24 | Gore particles | gameplay | Done: `src/objects/gore/` | - | - | - | - |
| T96 | 693-694 | 01-26 | Lobby control indicator | UI | Done differently: ControlDisplays (V20) | - | - | - | - |
| T97 | 695-706 | 01-19..02-07 | Sounds (kill, jump, land, walk, countdown, menu) | gameplay | Done except menu clicks (T42, V10, V20) | - | - | - | - |
| T98 | 707-708 | 02-06 | Sleeping bunnies during countdown | gameplay | Done: `bunny.gd:343-348` | - | - | - | - |
| T99 | 710-726 | 01-24..02-06 | Lobby, pause and game-over UI | UI | Lobby hole start Done; pause screen exists; game over is still a screen, not the in-lobby overlay | M | P3 | no | Levi |
| T100 | 728-734 | 01-25..02-06 | Camera modes | gameplay | Static camera Done; follow and split screen Idea (V21) | L | P3 | no | - |
| T101 | 736-743 | 01-25 | Formatting pass | release | Open as H9 | - | - | - | H9 |
| T102 | 745-762 | 01-27..03-31 | Web and mobile | store | Web Done; mobile touch controls Open (H10) | L | P3 | no | H10 |
| T103 | 764 | 02-20 | Fix broken tests | release | Owner: test status | - | - | - | h37-exec-a |
| T104 | 765-770 | 02-20 | Decouple the netcode plugin | dist | GameLift parts Stale; RN1 remains | L | P3 | no | RN1 |
| T105 | 771 | 02-20 | Netcode examples | dist | Open as RN2 | - | - | - | RN2 |
| T106 | 772 | 02-20 | Review docs | release | Idea | - | - | - | - |
| T107 | 774 | 02-21 | Disable networked pause | gameplay | Open, decision: committed `settings.tres:154` enables it; release overrides leave it on (V22) | S | P2 | yes | Levi |
| T108 | 776 | 02-20 | Sudden death | gameplay | Idea: no code | M | P3 | no | - |
| T109 | 778-780 | 02-21 | Easter eggs | aspir | Idea (cheats exist) | M | P3 | no | - |
| T110 | 782-816 | 01-21..02-06 | After-everything list | release | Claude mentions Done (V20); GameLift GDExtension Stale; plugin extraction mostly done (RN1-RN3) | - | - | - | - |
| T111 | 818-830 | 02-21 | Holiday themes | aspir | Idea: no code | L | P3 | no | - |
| T112 | 833-837 | 01-25 | Devlog notes | ref | Reference | - | - | - | - |

## Verdict summary (112 items)

- Done (21): T02-T07 (the 10-11 fixes, Finding 1), T46, T56, T68, T69,
  T83, T85, T88, T89, T90, T93, T94, T95, T96, T97 (menu clicks aside),
  T98.
- Verified working with partial coverage (2): T08, T09 (one keyboard
  player, V24).
- Believed Done, needs a look (1): T27 (bbf9694b).
- Partly Done (12): T12, T43, T48, T54, T59, T63, T74, T92, T99, T100,
  T102, T110.
- Stale, AWS/GameLift era or superseded (9): T47, T49, T52, T53, T57,
  T60, T62, T67, T87. Replacements: Hetzner + Edgegap, the cost monitor
  in `.claude/rules/deploy.md`, `NAKAMA_HTTP_KEY`, `release.yml`.
- Reference (7): T01, T18, T51, T58, T64, T82, T112.
- Idea or aspirational (13): T50, T71, T72, T73, T76, T80, T81, T86,
  T91, T106, T108, T109, T111.
- Open, verify first (5): T16, T19, T25, T29, T45.
- Open (21): T10, T11, T14, T15, T28, T37, T38 (H10), T39, T41,
  T42, T61, T70, T75, T77, T78 (RN2), T79, T84, T101 (H9), T104 (RN1),
  T105 (RN2), T107.
- With domain agents (21): T13, T17, T20-T24, T26, T30-T36, T40, T44
  (h37-matchmaking, h37-social, h37-account, h37-stats-ops); T55
  (h37-account); T65, T66, T103 (h37-exec-a).

## Proposed order

Low-hanging and high priority first; large and aspirational held back.
Distributed-systems items are ranked by their domain agents.

1. T107: decide networked pause; if it goes, flip `settings.tres:154`
   or force it off in `Settings._apply_release_values()`. S, P2, Levi.
2. V17: parenthesize the 22 broken format strings (17 hopnbop, 4 netcode,
   1 platform) and run the scanner in pr-validate. S-M, P2.
3. One 2-client networked session (Levi): the six 10-11 fixes (T02-T07),
   T16 remote glitches, T27 springs, T25 standing on players, T29 label
   consistency. File what reproduces. S, P2.
4. T29: fix the label offset that item 3 reproduces (offline shows none,
   V26); remove the diagnostic and its broken format string either way.
   S-M, P2.
5. T79: add a short input grace to the game-over screen and stop the
   reconnect loop at match end (V25), reproduce on web with the
   breadcrumbs on, then remove the 24 `FIXME(end-of-match-debug)`
   breadcrumbs. M, P2.
6. T45 + rest of T08/T09: controller pass by hand, with two local players
   and an offline replay. S, P2, Levi.
7. T42: click sound on every MenuRow trigger, once in the shared
   dispatch. S, P3.
8. T10: Alt+Enter fullscreen in hopnbop, scaffolder, bootstrapper. S, P3.
9. T41: let the snore finish (splash length or clip start); decide the
   web autoplay case. S, P3.
10. T12 + Stale notes: drop the dead plan path from platform `CLAUDE.md`,
    archive `MULTI_GAME_ROADMAP.md`, delete Done and Stale notes from
    `TODO-scratch.md`. S, P3.
11. V15: keep stray images out of exports (delete or exclude), delete the
    three orphan `.import` files. S, P3.
12. T43 + T19: polish pass by eye with H18 and H31; PlayerDisplay list at
    several window sizes with four players (V28: the panel already
    overlaps the playfield with one). M, P2.
13. T48: automate the rest of the release checklist (RPC channels,
    logging guards) next to the V17 scan. M, P2.
14. T84: add the two fly buzz `.ogg` files the code already loads. S once
    the audio exists, P3.
15. T15, T28, T14: level art, level_0 first, then level_4 and level_5;
    decide what foobar is for. L each, P3.

Next tier (P3, small to medium): T70 skinnier debug annotations, T78
ScaffolderTime and RN2, T55 OAuth branding links, T11 gore rainbow (ask
Levi what he meant), T61 tooltips, T77 web loading art, T99 game-over
overlay in the lobby, T59 Inner-Tube Climber.

Held back until the rest is polished: T37 Steam/Epic, T38/T102 mobile
touch (H10), T39 iOS, T74/T75 bespoke art for every level, T76 animated
tiles, T100 follow camera and split screen, T108 sudden death, T109
easter eggs, T111 holidays, T91 rollback debug UI, T72 level editor, T73
cloud levels, T86 AssetLibrary, T104 RN1 decoupling.

## Not checked

- Live networked play and release or web exports: every "verify" item,
  T79's web bug, T107's pause in release, the label diagnostic in
  release. Only h37-exec-a/b may bind ports, and I built no exports.
- Controllers and two or more local players: the harness drives keys
  for one device.
- Store, OAuth and console state (T37, T55, T63): needs credentials.
- Levi's intent: T11 (no rainbow transition in code), T14 foobar, T31
  (empty bullet).
- The missing plan file may still exist on the laptop.
- Art, audio and polish quality by eye; production crash counts.

Done 2026-10-14 10:21:19 -07:00
