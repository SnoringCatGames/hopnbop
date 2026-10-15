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

- **H37** · Systems audit, test run, history recap and TODO-scratch.md
  triage (Levi, 2026-10-14). Report-only; the report becomes
  `docs/design/H37_systems_audit.md`.
  - owner: claude 40ecd3b7-60b2-4364-9b2a-122aa3afad90. Phase 1: eight
    Opus agents (09:35), all reported by 10:55. Phase 2: h37-verify and
    h37-verify2, both finished 11:46. Phase 3: h37-report (10:46),
    running.
  - branch: mainline; last commit: the latest one touching the brief
    (`git log -1 -- docs/design/H37_audit_brief.md`)
  - evidence: `.claude/probes/H37/`: one `<agent>.md` findings file per
    agent, plus `<agent>/` for logs, run dirs and probe scenarios.
    Final reports go in `handbacks/`. The report is drafted, uncommitted,
    in `docs/design/H37_systems_audit.md` (its `Status:` line names the
    finished sections) and `docs/design/H37/`.
  - next: review the report, commit it with the appendices, and file the
    ledger items it proposes. Then delete `h37-verify2/export/` and
    `h37-verify2/nakama-src/` (about 108 MB). In a fresh session,
    restart h37-report from the brief if the report's `Status:` line
    does not list every section.
  - brief: `docs/design/H37_audit_brief.md`

## Next

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
- **H35** · `test_party_matchmaking_context.gd` fails 7 of its 11 tests
  under a full `-gdir=res://test/unit -ginclude_subdirs` run but passes
  11/11 alone: state bleed from earlier scripts, not a product bug
  (2026-10-12, Godot 4.7.2 + GUT 9.7.1, suite otherwise 485/492).
  pr-validate's per-file loop doesn't hit it.

## Ideas (not scheduled)

- **H33** · An optional `occurred_at` on crash reports, clamped
  server-side, would date reports that sat queued for days. Needs a
  privacy-text check first. (Agent a1d23375.)

## Done

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
