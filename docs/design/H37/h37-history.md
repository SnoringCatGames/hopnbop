# H37 history audit (h37-history)

Started 2026-10-14 09:34 PDT. Repos at: hopnbop 44f0093e, platform 8e85e8a,
netcode 7d6ebd9.

Sources: claude session 530145bc transcript (main jsonl, 10.8 MB, plus 20
subagent transcripts), git logs of hopnbop / platform / netcode, the three
LEDGER.md files, claude-config followups reports and LEDGERS.md inbox, other
transcripts under `~/.claude/projects/`. Extraction scripts:
`.claude/probes/H37/h37-history/`.


## Where we left off

Session 530145bc (desktop) ran 2026-10-09 22:03 to 2026-10-12 21:35 UTC:
144 assistant replies, 70 human messages (many queued mid-turn, so they
exist only as `queue-operation` records), 21 subagents, two compactions.
Times below are UTC; "(q)" marks a message Levi queued mid-turn. Observed
from the transcript unless marked "Believed".

### First reply (10-09 22:03): what it found and how

Evidence it used: the hopnbop dev transcripts had aged out (30-day
retention; the project dir held only this session and an unrelated one),
so it worked from the 9/26 interactive systems-audit session (5a55915e,
workspace project dir), four 10/7 weekly job runs,
`claude-config/jobs/status/2026-10.jsonl` (weekly-dr-drill, dependency
roundup), git log/status/submodule status, `game.yaml` and `project.godot`.

| Workstream | Age on 10-09 | Where it stood |
|---|---|---|
| Party system (last feature) | landed 7/17 (54445fb3, 3126f5cc, b1be0ad7; platform bump 49ea69ea), about 12 weeks | Done |
| Game development | last commit 8/24 (netcode pointer bump) | Idle since late August; only ops/CI/docs commits after the party work; nothing in flight; submodule pins equal upstream |
| Release backlog | live web 0.47.0, main 0.53.0, protocol 2, Edgegap v28 | Six minor versions unreleased |
| Local main | diverged 6 and 6 from origin | timestamp-sweep rewrite (patch-ids identical); fixed by fetch + rebase --autostash |
| Production | | Green; ops items below |

Outstanding items it listed:
1. UptimeRobot monitor red since 4/29: a HEAD probe against a GET-only
   healthcheck (501).
2. 10/7 DR drill gaps. A: phase-a reads a defunct postgres address. B: no
   known_hosts re-pin after a rebuild. Minor: no README for decrypting the
   secrets, no written RTO/RPO, no post-DR verify mode.
3. Dependency roundup red, all hex-grid: showdown 3 medium XSS; the 2
   "criticals" are build-tool noise.
4. Smaller: host dead-man timer; cost-monitor blind to R2 and Pages;
   container docs list 8 containers where 10 run; watchdog checks only the
   default branch; Edgegap spillover path never exercised.

### Levi's decisions and what each produced

| When | Levi | Outcome |
|---|---|---|
| 10-11 17:38 | "The outstanding items: Let's address all of these." | Ops agents: UptimeRobot on GET plus hopnbop.net and levi.dev monitors; DR phase-a single-host, HostKeys step, CRLF fix, phase-b installs the backup; docs (RPO <= 24 h, RTO 60-90 min, secrets README, prod-check post-DR mode); credentials backup re-encrypted; hex-grid jade removed, showdown 2.1.0; host timer desktop-drain-watch; cost-monitor reports R2 and Pages; watchdog checks `dev`; runtime 9679db4 probe_allocator override, Wednesday Edgegap probe; repo-auto-sync realigns hex-grid |
| 10-11 17:39 (q) | Game notes: crown recolours the bunny, death blink at level origin, respawn splash misplaced, player card should show the resting bunny, springs ignore invincible bunnies, research Godot 4.7.2 | crown a1b32155, springs bbf9694b (layer 11 player_trigger), death blink 7215b1d5, splash 28748f60, tests 10416583, player card eb4da2d3; 4.7.2 needed no code changes, CI pins bumped (netcode 71c8b84, platform 08ce094, hopnbop ee491657) |
| 10-11 | Machine crash (WHEA cache-hierarchy MCE): "We did diagnose and adjust this before." | Logged in whea-watcher history (claude-config ef8c768) |
| 10-11 20:02 (q) | showdown: dismiss; trailers: "what is this"; card bunny: same size; invincibility: yes x3; DR: "what?"; token: "what?"; settings.tres: "for debugging"; pr-validate: yes | 52ab4ac5 (snail), 0a1a00a9 (gore and fly masks); pr-validate repaired 13e5cbed, f9f8b38b (Nakama service removed, addon copy + import, UID CRLF/LF) |
| 10-11 22:50 | Remove the Claude credit rule | claude-config c0cd004 |
| 10-11 22:52 (q) | "DR rebuild: Do it" | .env rendered from `scripts/lib/nakama-env.ps1` (27 vars, platform cd0cc6e); phase-a pulls the image; jobs reach the host by DNS name (claude-config 7b66b94, f4874d3; hopnbop 5cd77b80, 47e80c75); keep-alives ce07eb9. Never exercised by a real rebuild |
| 10-11 23:13 | Provided a read-only Cloudflare token | cost-monitor uses it |
| 10-11 23:14 (q) | "Let's fix all four" (CI build UID, SDK refresh loop, tokens in logs, dead crash reporter) | platform b2eecad (`scripts/ci/bridge-platform-addon.sh`, export-smoke job); SDK 0.5.2 backoff 8b891cd0 and WARNING-level logging 76a95723; bump 50cc1087, tests 0e6b8540; crash reporting runtime af566b9, client 6b0dc6d7, health check ad8c6ca |
| 10-11 23:16 (q) | "Rotating it ... Do it" | A database password echoed into the transcript was rotated |
| 10-11 23:16 (q) | "fix it" | sync-game-config pulls the image before registering (45c3cdf2) |
| 10-11 23:18 (q) | The testability prompt | See "Testability conversation" |
| 10-11 23:20 (q) | Pasted PR Validate failure email: "Are you aware of this?" | Old run; separately found b998107d (deleted `upgrade_levels.tscn`) broke the web export, fixed |
| 10-12 01:21 | "1. Yes 2. What? Probably do what's best. 3. Yes 4. Yes. 5. Yes and yes. 6. Can you fix this? 7. Yes to all." (security plan for the runtime HTTP key committed in public `src/core/global.gd` since May: admin key, keyless client, rotate after the release; plus fixes) | GAME_ADMIN_KEY gate on register_game and bulk_import; keyless client via `/snoringcat/version_check` (15498835) plus a CI test; match_end auth fixed; redaction (sync-game-config percent-encoded leak, Caddy access-log masking); crash reporting end to end; netcode 1.0.2 exit crash; dead AWS token poll removed; SDK 0.5.6 linked accounts; mid-session sign-out to auth screen; transient boot error keeps the session; privacy/legal 1.2 (93b9c6fc, cf3e9ea5, 312b4f50, 87523bb3); local token file deleted; GODOT var to 4.7.2; prod test accounts deleted; deploy-server skill rewritten (claude-config caa5ffb, 5c78453); import retry 4f360ce4 |
| 10-12 03:30 | "Still open for you: Fix all in the most-correct way possible" (7 items) | Leaderboard: prod never had boards, no score saved since May; platform 003665c (boards, public endpoint, site page), hopnbop 2c8cb82e, f4a6eead, get_player_stats fixed. Data rights: platform 46fc4fe, 78c08d9; hopnbop 380ebef3, bc7c1a52, 12c7352c; SDK 0.6.0; IPs expire after 1 h; email sign-in refused; stored emails purged. CSV comma fix plus 16-test check. Friends poller restart; sign-out closes the socket. Toast and "Authenticating..." hang. Consent kept on automatic sign-outs (51f0f630). Tooling: platform 24b59a4 (dead platform_smoke_test.gd deleted), test-google-auth.py fixed, netcode parse check made real (10b2f41), docs e0928803, 5cf0b87e |
| 10-12 05:54 | (weekly usage limit hit) | |
| 10-12 21:04 | "Usage has been reset. Resume..." | 21:16 wrap-up: CI green on f4a6eead (GUT 60 files / 625 tests, compliance 80/80), 11 "Needs your call" items (below) |
| 10-12 21:22 | "I want it" (the 0.54.0 release) | Not started; see blocker below |
| 10-12 21:22 (q) | "Please ensure all the other follow-ups are recorded in the ledger. I'm going to resume work from my laptop." | 21:32: hopnbop 8c9f5012 (H4 Urgent, H14, H15-H33 added; H1, H13 closed); platform f0a0287 (SP12-SP25; SP1, SP11 closed); pointer bumps 1050292a, 400c7763; netcode dea8925 (new LEDGER, RN1-RN5); claude-config dcc608b (CC13, CC14) |

### Still open at the end (10-12 21:35)

- **The release had not started; nothing was deployed.** Blocker found in
  the final turn: exported builds ship the committed debug values in
  `settings.tres`: match_duration_sec 10 (the live v28 server, built
  2026-06-02, has run 15 s matches since June), show_hud false (since
  c89bbda9), overhead labels off, skip_splash on. Recommendation:
  release-only overrides in code (180 s, HUD and labels on, splash shown),
  ship 0.54.0, then rotate the key (H14). The transcript ends with an
  away-summary asking Levi to confirm 3-minute matches; no answer in this
  session (he moved to the laptop).
- End state: hopnbop main 400c7763, prod runtime e6a47f6, SDK 0.7.0.
- The 11 "Needs your call" items: (1) Facebook sign-in probably broken
  (SDK passes the OAuth code as an access token); (2) CI runs only on
  dispatch, add push triggers; (3) matchmaking socket survives log-out;
  (4) custom, Game Center and Instant sign-ins skip the game_id check;
  (5) match notifications never expire; (6) a deleted player lingers on
  the public board up to a minute; (7) localized bunny names may not ship
  in exports; (8) two unused OAuth secrets on the host; (9) rollback_netcode
  standalone (stand-ins for G.is_lobby_active, SessionProvider,
  DeviceConfig, LevelPreferences), broken example project, its 9 test
  files not in CI; (10) UX papercuts: raw error toasts, empty lobby after
  cancel, 9 s offline log-out, double toast on a failed party join;
  (11) Google sign-in never tested with a real login (needs Levi).
- Other heads-ups raised along the way: bunny reappears 1-2 frames before
  respawn; podium bunnies never animate; networked splashes and skids fire
  twice; spawn-spacing check cannot see invincible bunnies (`level.gd`);
  probe's version_check omits game_id; knotmaze had 4 unpushed commits;
  hex-grid has unused Express-era deps; host `pg-backup.sh` lacks the
  2bfd448 double-ping guard; phase-b's UptimeRobot step uses the v2 API;
  cost-monitor lacks GITHUB_TOKEN; levi-dev-deploy skill expects 200 from
  a URL that 301s; `Platform.api` unused; platform README claims a v1.4.0
  tag that never existed; old Caddy access logs still hold the key (clear
  at rotation); CI's GUT CSV check runs only on dispatch.
  Statuses for all of these: "Loose threads".


## Testability conversation

### Where and when (observed)

- It happened once on this machine: claude session 530145bc, 2026-10-11
  23:18:11 UTC (16:18 PDT), typed while a turn was running. Mid-turn
  messages survive only as `queue-operation` enqueue records, so a search of
  ordinary user records misses it. Verbatim:
  > "Are you able to run the game at this point to debug and verify things?
  > If we don't have convenient quick shortcuts/commands/APIs for you to run
  > specific bits in isolation to quickly iterate, audit and build whatever's
  > helpful. I'm thinking both client-side app systems and interactions,
  > backend things, e2e things, whatever."
- Levi's 10-14 recollection (coordinator 40ecd3b7, 16:13 UTC) has three
  parts; only the first was asked in those terms before 10-14:
  1. How we test, execute and verify changes: asked 10-11, answered with
     tooling (below).
  2. Decoupling systems so they can be tested in isolation: the 10-11 prompt
     asked for "shortcuts/commands/APIs ... to run specific bits in
     isolation". No transcript here discusses decoupling or refactoring for
     testability ("decoupl" has no hit in 530145bc's assistant text, agent
     prompts or the audit report). The answer built tooling around the game
     as it is. **The decoupling question was never answered.**
  3. Running the real game end to end, starting a match, opening and using
     the settings menu: these words first appear on 10-14, in 40ecd3b7. The
     10-11 prompt's "e2e things" is the nearest.
- Searched: every jsonl under `~/.claude/projects/` since 10-01 (user,
  queued, agent-prompt and compaction-summary records; `search.py`), the one
  Muse session (2026-10-13: 8 metadata records, no turns), followups reports
  10-11, 10-13, 10-14, the LEDGERS.md inbox. The only other hits are
  transcript-audit runs quoting the 10-11 prompt, and a knotmaze "settings
  menu panel" request.
- Laptop: Levi moved there at 10-12 21:22 UTC and its transcripts are not on
  this machine, so a later conversation there cannot be ruled out. Commits
  since then that touch `scripts/agent/` or `test/unit/` are 3b7f5743
  (-Backend, written in 530145bc as f4a6eead), 8ca156e7 (release settings
  test) and 34971411 (README move): no new scenario, no decoupling work.
- Side finding: no 10-12 followups report exists because that day's
  transcript-audit run hit the weekly usage limit at 09:04 UTC ("You've hit
  your weekly limit") and wrote no status entry. weekly-meta-audit (10-14
  10:44 UTC) already reports it, and projects the limit again late 10-14 or
  early 10-15 (72% used at 10-14 08:51 UTC), with LLM jobs failing until
  10-19 19:00 UTC.

### What 530145bc did with it (observed in the transcript)

| UTC | Step |
|---|---|
| 10-11 23:20 | Agent a509c19d, "Audit game/backend debug tooling", audit only |
| 10-11 23:47 | Two build agents: harness v0 plus the preview session-id fix; compliance helper plus local smoke |
| 10-11 23:48 | Reply: "To your question: yes, I can run the game headless or windowed and inject input. So far that took throwaway scripts; the harness the agent is building replaces them." |
| 10-12 00:46 | Correction to the harness agent: random spawns made offline-move-jump flaky; make scenarios deterministic |
| 10-12 03:30-21:16 | Harness extended: -Backend for a local Nakama (f4a6eead, now 3b7f5743), sign-out and consent scenarios, i18n screenshots |

The audit's findings (its report; "verified" there means that agent's runs):
the game ran headless or windowed only through throwaway `-s` bootstraps, no
tools in the repo; `settings.tres` toggles had no CLI or env override; input
injection worked (`Input.parse_input_event`, `physical_keycode`); preview
clients shared one session id, so the second client never got a bunny; UDP
4433 was fixed; compliance socket asserts could not fail and the suite
defaulted to writing test accounts into prod; the local stack was
unreachable from a real client; game-server container logs were lost; prod
safety rested on convention.

Its build list and where each item stands (SHAs reachable from origin/main,
checked 09:54 PDT):

| # | Item | Status |
|---|---|---|
| 1 | Harness v0 | Done 5d913da4 (then 9c5f6921, 2907b515, 44d745c7, 59d683c0, 34971411) |
| 2 | Distinct preview session ids | Done 247be983 |
| 3 | Compliance helper (real socket asserts, refuses prod) | Done platform 55889b3, bump d95a4194 |
| 4 | local-smoke-test.ps1 repair | Done f8706a76; CI push triggers not done (H11) |
| 5a | Client backend URL override | Done 3b7f5743, SDK platform 6fa5ec4 |
| 5b | Dev stack with the local allocator (a real local game server) | Not done: `infra/dev` has no allocator or docker.sock config. Unledgered |
| 5c | `-AllowMock` on the synthetic probe | Not done: no such flag; the probe fails any mock-mode match (`claude-config:jobs/scripts/_synthetic-match-probe-bin/probe.go:203-211`). Unledgered |
| 6 | Keep match logs; read-only SQL wrapper | Not done: `platform:runtime/local_allocator.go:219` still sets `AutoRemove: true`; `claude-config:jobs/scripts/_lib/Invoke-RemoteSql.ps1:34` defaults to the nakama user with no read-only guard (prod-health-check adds its own `BEGIN READ ONLY`, `prod-health-check.ps1:321`). Unledgered |
| 7 | Golden-screenshot regression tests | Deferred "later" by the audit; not built. Unledgered |

The audit's "First slice" was items 1 to 3, to "cover the common asks:
reproducing a gameplay bug visually, driving a UI flow, and local
multiplayer".

### Levi's three questions as of 10-14 (Believed: files read, nothing run by me; h37-exec runs the harness)

1. **How we test.** GUT in CI (pr-validate, compliance-matrix: triggers are
   pull_request and workflow_dispatch only, so nothing runs on pushes to
   main, H11); `scripts/local-smoke-test.ps1` (local Nakama in mock-deploy
   mode plus the compliance suite); the agent harness
   (`scripts/agent/run-game.ps1`, 13 scenarios); daily prod probes
   (synthetic-match-probe, prod-health-check).
2. **Decoupling.** Never analysed. The one decoupling-shaped item is
   rollback_netcode standing alone (stand-ins for game globals, broken
   example project, its tests not in CI: RN1-RN3, waiting on Levi). The May
   plan `docs/archive/test-architecture-plan.md` left section 3 a
   placeholder. Of its ideas, three exist in some form: a Go headless client
   (the synthetic-match-probe binary, prod only), a fake Edgegap (the
   runtime's `EDGEGAP_MOCK_DEPLOY`, which gates `test_matchmaking.gd` and
   others in the compliance suite), a compose tier (`infra/dev`).
   Fixture-replay tests do not exist (no hits in either repo).
3. **The real game end to end.**
   - Start a match: yes, locally. Offline mode (offline-move-jump,
     sign-out-local-match, sign-out-play-again) and match mode (headless
     preview server plus 1-2 clients on a free UDP port, direct connect:
     match-2-clients). No scenario goes through Nakama matchmaking to an
     allocated server; that needs 5b. Matchmaking is covered only below the
     game, by the SDK compliance suite under mock deploy, with no game
     server.
   - Settings menu: three scenarios open it, all through `eval`, not input.
     export-data-offline calls `level.get_node('SettingsBook')._show_settings_ui(...)`,
     pushes the account panel and fires a row's `on_trigger()`;
     i18n-party-strings instantiates the side panel manager by hand;
     log-out-sign-in-cycles calls `sign_out_router.log_out()` directly. No
     scenario walks the bunny onto the settings book or navigates panels
     with key presses (`scripts/agent/scenarios/*.json`).


## Loose threads

Every deferred, offered or open item from 530145bc, statused against the
hopnbop, platform and netcode ledgers (plus claude-config's and hex-grid's
where the item lives there) and git log, 10-14 09:40-10:00 PDT. "Open"
means an item with that ID exists; "Unledgered" means no ledger holds it.
SHAs are current ones (see the rewrite note below).

| Thread (where raised) | Status | Pointer / evidence |
|---|---|---|
| 0.54.0 release; exported builds shipped debug `settings.tres` values (final turn) | Done, H4 | 8ca156e7 (`Settings.apply_release_overrides()`, `test_settings_release_values.gd`), 2abf477c. Verified live: GET `hopnbop.net/version.json` returned 0.54.0 at 09:49 PDT (my run) |
| Rotate the runtime HTTP key after the release (10-12 01:21 plan) | Done, H14 | 72753fa5, claude-config 6279e62 |
| - desktop credentials file still holds the dead key | Open, CC31 | claude-config LEDGER (Next) |
| - org-level `NAKAMA_HTTP_KEY` Actions secret may hold the dead key | Unledgered | named only in H14's Done text; checking needs admin:org |
| - old Caddy access logs hold the key | Done with H14 | log truncated at rotation per H14's text; not checked on the host |
| (1) Facebook sign-in probably broken | Open, SP12 | waiting on Levi since 10-12 |
| (2) CI runs only on PR and dispatch; GUT CSV check dispatch-only | Open, H11 | `on:` blocks of `.github/workflows/pr-validate.yml`, `compliance-matrix.yml` read 10-14: pull_request + workflow_dispatch only |
| (3) Matchmaking socket survives log-out | Open, H15 | waiting on Levi |
| (4) Custom, Game Center, Instant sign-ins skip the game_id check | Open, SP13 | waiting on Levi |
| (5) Match notifications never expire | Open, SP14 | |
| (6) Deleted player lingers on the public board up to a minute | Open, SP16 | |
| (7) Localized bunny names may not ship in exports | Done, H16 | f6a105fc (checked; no fix needed) |
| (8) Two unused OAuth secrets on the host | Open, SP15 | |
| (9) rollback_netcode standalone, example project, tests not in CI | Open, RN1-RN3 | waiting on Levi |
| (10) UX papercuts | Open, H18-H22 | |
| (11) Google sign-in never tested with a real login | Open, SP17 | waiting on Levi; its pointer 24b59a4 is dead (now 6ffa5fd) |
| Bunny visible 1-2 frames before respawn | Open, H3 | waiting on Levi |
| Podium bunnies never animate | Open, H5 | |
| Networked splashes and skids fire twice | Open, H6 | |
| Spawn spacing cannot see invincible bunnies | Open, H7 | |
| Probe's version_check omits game_id | Done, CC8 | claude-config cfdd8b8 (10-13) |
| knotmaze had 4 unpushed commits | Done | `master` level with `origin/master` (observed 10-14) |
| hex-grid unused Express-era deps | Open, HG1 | hex-grid LEDGER (Ideas); express, body-parser and others still in package.json |
| Host `pg-backup.sh` lacks the double-ping guard | Done, SP1 | |
| phase-b UptimeRobot step uses the v2 API | Open, SP2 | |
| cost-monitor lacks GITHUB_TOKEN | Open, SP3 | |
| levi-dev-deploy skill expects 200 from a URL that 301s | Open, CC10 | |
| `Platform.api` unused | Open, SP20 | |
| Platform README claims a v1.4.0 tag | Open, SP21 | |
| Textures left unreferenced when b998107d deleted `upgrade_levels.tscn` (10-11 23:52, "harmless, so I'm leaving them") | Unledgered (minor) | H12's Done text does not mention them |
| UptimeRobot monitor red, HEAD vs GET (first reply) | Done 10-11 | monitor moved to GET, plus hopnbop.net and levi.dev monitors; docs platform c41ecf3, claude-config 24dcfe2; current monitor state not checked |
| 10-07 DR drill gaps A, B and minors (first reply) | Done | platform ee3fe8a, 635b4f7, c41ecf3; claude-config 31fd03b, da38070, 46a8e27 |
| Dependency roundup red, hex-grid (first reply) | Done | hex-grid d2f2397, e03ee3c; 10-14 roundup: 0 open, 3 dismissed as accepted risk (Levi: "dismiss") |
| Host dead-man timer | Done | claude-config 90081fc; platform f0f9fde (desktop-drain-watch) |
| cost-monitor blind to R2 and Pages | Done | platform faf97e0 |
| Container docs list 8 of 10 containers | Done | platform c41ecf3 |
| Watchdog checks only the default branch | Believed done 10-11 | commit not identified |
| Edgegap spillover path never exercised | Done | platform 4668dd4 (probe_allocator), claude-config b293bec (Wednesday Edgegap probe); status trail: synthetic-match-probe kind=edgegap green 10-14 07:53 UTC (not my run) |
| DR rebuild ("Do it", 10-11 22:52) | Done in code, never exercised | platform 97fc542, 8c31f22; claude-config 7b66b94, f4874d3; hopnbop 5cd77b80, 47e80c75. SP7 compared the .env against prod's 27 values; no real rebuild. Unledgered |
| Superseded Edgegap versions stay active after each release | Covered | H36 text makes it a release step; check-prod step 10 flags it |
| Signed signaling URL in client logs (agent ac92c527, 10-11 23:55) | Unledgered | LEDGERS.md inbox since 10-13, unfiled; still logged at `hopnbop:src/core/game_session_manager.gd:345-353` (`", signaling_url=" + signaling_url`); the inbox's `:325` is stale |
| Testability build list 5b, 5c, 6, 7; no input-driven settings-menu scenario; no matchmaking scenario; decoupling never analysed | Unledgered | "Testability conversation" above |
| Weekly DR drill 10-14 red: Caddy LE renewal fails 14 d, RTO 2.5 h to 36 h, 16 gaps; G1 nothing pages while renewal fails | Unledgered | status trail 10-14 09:47 UTC; weekly-meta-audit notes nothing reads the Wednesday jobs |
| 10-12 transcript-audit hit the weekly limit, no report, no status entry | Unledgered (reported) | weekly-meta-audit 10-14 10:44 UTC; projects the limit again late 10-14 or early 10-15 |
| Ledger SHA pointers killed by the timestamp-sweep rewrite | Unledgered | CC34 covers submodule pins only; dead: platform SP4-SP8, SP11, SP17, SP24; hopnbop H1 (platform af566b9), H17 (platform 8ede126) |
| Remaining residuals filed 10-12 21:32 | Open | hopnbop H9, H10 (half done on the laptop: 4c04e908, f5efb52c), H17, H23-H33, H35; platform SP9, SP10, SP18, SP19, SP22-SP25; claude-config CC32 |

### SHA rewrite note

The platform history was rewritten after 530145bc, back to at least 08-15
(hopnbop 35e3e20d re-pins "onto the swept history"); every 530145bc-era
platform SHA is in no branch, local or origin. Old -> current, matched by
subject and author date:

- hopnbop: 2c8cb82e -> f77828e8, f4a6eead -> 3b7f5743, 8c9f5012 -> ba59dfa0,
  1050292a -> bb072cfa, 400c7763 -> 12220a14. Other hopnbop SHAs in this
  file are on main.
- platform: 8b891cd0 -> 187912d, 76a95723 -> e8ad312, b2eecad -> da8394d,
  003665c -> fca14aa, 46fc4fe -> 6b33bb0, 78c08d9 -> 5fc70cb,
  24b59a4 -> 6ffa5fd, cd0cc6e -> 97fc542, 9679db4 -> 4668dd4,
  08ce094 -> 744a40e, f0a0287 -> c4c7413, af566b9 -> 6081b82,
  e6a47f6 -> 706f452, 225c333 -> 8002684, ce07eb9 -> 8c31f22,
  8ede126 -> f4424d5, 392ab52 -> 019499b, 2bfd448 -> ba6c421.
- netcode: dea8925 -> 69438a2 (71c8b84, 10b2f41, 10b2b09 unchanged).
- claude-config: dcc608b -> df5f94c (others unchanged).
- "Where we left off" quotes SHAs as the transcript has them.

### Not checked

Laptop transcripts (10-12 21:22 UTC on; not on this machine); the org-level
Actions secret (needs admin:org); the desktop credentials file (off limits);
`edgegap-logs -Latest` under the hybrid allocator; the watchdog commit; the
UptimeRobot monitors' current state; the host's Caddy logs.

Done 10:00 PDT (2026-10-14).
