# Hop'n'Bop ledger

Open work for hopnbop: follow-ups, known residuals, decisions waiting on
Levi, and ideas. Convention: claude-config `rules/ledger.md`. IDs (`H<n>`)
are stable and never reused. Platform items (SDK, runtime, prod host
scripts) live in `third_party/snoringcat-platform/LEDGER.md`.

Session pointers like "session 530145bc, agent aab30fcb" refer to Claude
Code transcripts under `~/.claude/projects/` (kept 30 days). Each item
states its facts, so it stands on its own after the transcript is gone.

## Urgent

- **H4** · Release 0.54.0 is prepared but **blocked on shipping settings**
  (Levi asked for the release 2026-10-12; nothing is deployed yet). Main
  is 0.53.0 plus 2026-10-11/12's work; live is web 0.47.0 and game
  server v28. Exported builds read `settings.tres` as-is, and its
  committed debug values would ship:
  - `match_duration_sec` (server-authoritative, `game_panel.gd:2074`):
    committed 10 s; live server v28 (built 2026-06-02 from 4c85619c) has
    run **15 s matches** since June; Levi's working copy 180 s;
    `settings.gd` default 60 s. Levi called the committed 10 s "for
    debugging purposes" (2026-10-11).
  - `show_hud = false` (since c89bbda9, 2026-03-07): `hud.gd:34` hides
    the in-game HUD until the player presses F1. Also
    `show_player_overhead_labels = false` and `skip_splash = true`.
  Recommended fix: release builds (not `OS.has_feature("editor")`) apply
  explicit release values in code, so settings edits can't ship. Levi to
  confirm the values (match length; HUD and name labels on; splash).
  Then the plan: bump to 0.54.0; `game.yaml` `edgegap_app_version` and
  `local_image_ref` to v29; patch notes in `web/blog/index.html`;
  `game-server.yml -f version=v29`; local web export plus a boot check;
  `scripts/deploy-cf-pages.ps1 -SkipExport` (its sync pulls v29 onto the
  host and publishes legal 1.2, so every player re-consents); verify
  with synthetic-match-probe, nightly-smoke and the check-prod skill. Do
  NOT push a `v*` tag: `release.yml` would redeploy. Then H14. Also
  ships the rebuilt website leaderboard (6c37fd59). (Session 530145bc.)

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
  public repo. (Session 530145bc.)
- **H15** · Offered: the realtime matchmaking socket survives log-out
  still signed in as the old account, and the next account would reuse
  it for its tickets; nothing calls `Platform.matchmaking.cleanup()`.
  Likely a one-line fix in `SignOutRouter`'s shared cleanup. Inferred
  from code, not reproduced. (Session 530145bc, client-fixes agent
  abdbfdf9, 2026-10-12.)

## In progress

- **H14** · Rotate the Nakama runtime HTTP key (step 3 of the leak plan)
  once the release from H4 ships the keyless client (15498835). The key
  was committed in this public repo from 12a93325 (2026-05-12) until
  15498835. Rotate it in `credentials.env`; `/opt/nakama/.env` plus a
  nakama recreate (the local allocator picks it up from there); the
  Edgegap app version's env (re-register v29); the hopnbop
  `NAKAMA_HTTP_KEY` Actions secret. Then delete the host's old
  `/var/log/caddy/access.log*`, which hold the key in request URIs from
  before the log filter (2026-10-12). 0.47.0 clients' version check then
  fails open. Steps 1 and 2 are done: platform b6c67ec and 9b28b3b,
  hopnbop 15498835, and the prod admin key (claude-config 52e1352).

## Next

- **H16** · Localized bunny names and adjectives probably don't ship.
  The game reads the `translations/adjectives` and `translations/names`
  CSVs at runtime, but they are imported as translations, so exported
  builds likely lack the source files and fall back to English. Check
  against an export. (Session 530145bc, agent abdbfdf9.)
- **H34** · Slim `CLAUDE.md` (2,332 lines, ~24k tokens, loaded into every
  session and subagent) to about 400 lines / 10k tokens under
  claude-config `rules/context-budget.md`. Keep binding rules,
  invariants, the architecture map and how to run and test. History goes
  to commit messages (or `docs/history.md`, never imported), design to
  `docs/design/`, and subsystem lore to path-scoped `.claude/rules/<area>.md`
  (commit `.claude/rules/`). Biggest sections: Deployment (~700 lines),
  Testing with GUT (~400), Code Style (~250). The daily follow-ups
  report tracks the size.

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
  aab30fcb, 13:52.)
- **H10** · No Android export preset: `export_presets.cfg` has no
  `platform="Android"` entry. The desktop's toolchain for Godot 4.7.2 is
  ready and verified since 2026-10-11 (SDK 36, build-tools 36.1.0, NDK
  r29, JDK 17.0.20); the laptop's is not (claude-config CC12). (Session
  c56311ec-2461-4905-a9f4-40d79be7d055, 2026-10-11 15:45.)
- **H17** · `EdgegapServerProvider` trusts each player's declared backend
  user ID instead of checking it against the validated session ID. The
  runtime now drops outsiders from `match_end` (platform 8ede126), but a
  player can still claim a fellow match player's ID. (Session 530145bc,
  admin-key agent a654b0d8, 2026-10-12.)
- **H18** · Raw SDK error text reaches players: the party panel shows
  SDK errors as-is (a "Not authenticated" toast), and the delete, export
  and merge failure toasts append raw errors. (Agent abdbfdf9.)
- **H19** · After a recoverable matchmaking failure the loading screen
  offers only "Try Again", with no way back to the lobby. (Agent
  abdbfdf9.)
- **H20** · Cancelling matchmaking, or a fatal matchmaking failure,
  returns to a lobby without the player's bunny. Inferred from code.
  (Agent abdbfdf9.)
- **H21** · A party follower whose join fails gets two toasts for it.
  (Agent abdbfdf9.)
- **H22** · Log-out first tells the server the player went offline, so
  with no connection the consent screen appears only after that times
  out (about 9 s in the harness). (Agent abdbfdf9.)
- **H23** · The notification socket stops on any failed sign-in result,
  transient refresh failures included, until the next successful
  refresh. (Agent abdbfdf9.)
- **H24** · `Player._enter_tree` registers the player before its id is
  set, leaving a stale `players_by_id[0]` entry on the server; the code
  comment there says the id is set first. (Session 530145bc, harness
  agent a9dc5b3c, 2026-10-11.)
- **H25** · Quitting during the mid-match reconnect loop crashes with
  signal 11. The game's own exit paths avoid it, and so does the
  harness. (Agent a9dc5b3c.)
- **H26** · After a preview server hot-reload, levels get
  auto-generated names (`@Node2D@39`), so each client logs about 35
  replication errors (Snail_0 not found, ids missing from the cache).
  (Agent a9dc5b3c.)
- **H27** · Local/offline mode logs "RPC on yourself is not allowed"
  errors (`_server_rpc_ping`, `_rpc_init`). (Agent a9dc5b3c.)
- **H28** · About half of lobby runs log an `AudioStreamWAV`
  (`pause_menu.wav`) leak warning at exit, before and after the
  PerfTracker fix. Noted in CLAUDE.md. (Agent a55477032.)
- **H29** · Unused code: `BinaryToggle`, and `fetch_player_stats`,
  `fetch_match_history` and their signals in `backend_api_client.gd`
  since the leaderboard and My Stats rewrite (2c8cb82e). (Leaderboard
  agent abbaef7c.)
- **H30** · `scripts/agent/run-game.ps1 -Backend` accepts a URL with no
  port; the driver then refuses it with exit 3. (Agent abbaef7c.)
- **H31** · The credits screen's existing labels ("Made by", "Sound",
  "Credits", "Thanks for playing!") have no translation keys, so other
  locales show English next to the translated DB-IP row (87523bb3).
  (Privacy agent a834b111.)
- **H32** · Anonymous players only get a session once they go online, so
  an offline-only player's crash reports expire unsent after 7 days.
  (Crash agent a1d23375.)

## Ideas (not scheduled)

- **H33** · An optional `occurred_at` on crash reports, clamped
  server-side, would date reports that sat queued for days. Needs a
  privacy-text check first. (Agent a1d23375.)

## Done

- **H1** · Crash reporting was dead (no client session lookup, and the
  runtime never had a `crash_report` RPC). Done in hopnbop 6b0dc6d7 and
  platform af566b9 (2026-10-11), live on prod; design review in
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
