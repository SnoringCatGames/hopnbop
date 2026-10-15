# H37 brief: systems audit, test run, history recap, TODO triage

Levi's request (2026-10-14, claude session 40ecd3b7), condensed:

1. Recap the recent testability work: how we test, execute and verify
   changes; whether to decouple systems so Claude can test them in
   isolation; whether Claude can run the real game end to end, start a
   match, and open and use the settings menu.
2. Recap what claude session 530145bc (2026-10-09 to 10-12) determined
   about where the months-old hopnbop work had left off. Find its loose
   threads and verify that its work now works.
3. A thorough audit, beyond the recent work, of every non-gameplay,
   distributed flow: account, social, stats, leaderboards, settings,
   matchmaking, ops. Do they cover the cases we need, and do they work?
   All of them should be executable and testable by Claude without a
   human, so find what would make that more seamless.
4. Triage `TODO-scratch.md` (Levi's notes, moved verbatim out of
   `frame_driver.gd`): stale, done, open. Then an ordered list weighing
   low-hanging fruit against priority, with large and aspirational items
   held until the rest is polished.
5. One thorough report, `docs/design/H37_systems_audit.md`, that a later
   session breaks into ledger items and works through.

This stage is report-only. Nothing in it fixes product code. Levi chose
quality over usage for it, so every agent runs on Opus.

## Method

- **Phase 1:** eight agents, run by the coordinating session. Each
  writes its findings to `.claude/probes/H37/<agent>.md` (untracked). If
  the session is lost, restart from its section below any agent whose
  findings file has no `Done` line.
- **Phase 2:** the coordinator briefs one or two Opus agents to run
  probes on the Suspect findings worth confirming.
- **Report:** the coordinator writes it, and commits the findings files
  as appendices under `docs/design/H37/`.

## Rules for every agent

- **Read-only.** Don't edit tracked files in any repo, commit or push.
  Write only under `.claude/probes/H37/` in hopnbop: your findings file
  `<agent>.md`, plus scratch scripts, logs and scenarios under
  `<agent>/`.
- **Public repo.** The findings files get committed to this public repo:
  no secrets, tokens, keys, emails, or production player data (names,
  ids) in them.
- **Production:** no writes, no sign-ins, no credentials
  (`credentials.env`, the token store). Unauthenticated GETs of public
  prod routes are fine. Harness runs and local stacks touch loopback
  only.
- **Godot and Docker:**
  - Nobody starts Godot before `.claude/probes/H37/import.done` exists.
    Only h37-exec-a runs `--import` or opens the editor.
  - `scripts/agent/run-game.ps1` sandboxes its own processes. Every
    other Godot process you start gets a throwaway `$env:APPDATA` under
    your probe dir, so runs share `user://` neither with each other nor
    with Levi's real data.
  - Only h37-exec-a and h37-exec-b start Docker or anything that binds a
    network port. That covers `test/integration/` files, scenarios with
    a server or `-Backend`, and local stacks. First they take
    `.claude/probes/H37/net.lock` (one line: owner and time), waiting
    for it in one blocking loop, and they delete it when done.
  - The other agents may run:
    - single-process offline scenarios and `test/unit/` files;
    - `go test` / `go vet` on runtime packages, targeted with `-run`
      where that's enough. To run an extra Go test, copy the package
      into your probe dir and run it there;
    - git, gh and searches.
- Use PowerShell for local commands (`godot`, `go`, `docker` are on its
  PATH). Spawn no helper agents. Keep tool output small: filter logs,
  never dump big files. Noise in your context costs quality.
- **Keep observed and inferred apart.** "Verified" needs a run you did
  or a cited test that covers the case. Code reading alone is
  "Believed". Cite `repo:path:line`.
- **Write the findings file incrementally**, one section at a time, so a
  stop loses little. Put your start time (`Get-Date`) at the top, and a
  last line `Done <time>` when finished.
- **Stop rule:** stop when your section is done or 2 h after your start,
  whichever comes first. Check `Get-Date` at each milestone. A
  compaction is not a stop: after one, re-read your section here and
  your findings file, then go on.
- The findings file is an appendix that a later session reads without
  this conversation. Make it self-contained and terse, with pointers
  over prose.
- **Final message** to the coordinator, at most 60 lines:
  - your 10 most important findings, ranked by severity;
  - your verdict on each TODO-scratch note and ledger item assigned to
    you;
  - what you could not check, and why;
  - `Ledger items`: new follow-ups and residuals.

### Findings shape for the domain audits

```
# H37 <area> audit
Started <time>. Repos at: hopnbop <sha>, platform <sha>, netcode <sha>.
## Summary (top findings, ordered)
## Flows
### <flow>
- Cases needed: happy path; failures (offline, timeouts, expired or
  revoked session, server restart); concurrency (two devices, races,
  retries, idempotency); abuse (spoofed ids, rate limits); anonymous vs
  linked accounts; web vs native.
- Implementation: entry points in the game, the SDK and the runtime.
- Coverage: which cases have a test, and at which layer (runtime Go
  unit, SDK or game GUT, compliance suite, harness scenario, CI, prod
  probe).
- Status per case: Verified / Believed / Suspect / Broken, with
  evidence.
- Gaps and bugs: path:line, failure scenario, confidence.
- Testability: the seam, fake or scenario that would let Claude run it
  unattended, and what it costs.
## TODO-scratch notes in this area (a verdict for each)
## Ledger items in this area (still true? fixed?)
## Proposals ranked by value/effort
```

Every domain audit also reads the archived audits,
`docs/archive/FRIENDS_PARTY_MATCHMAKING_AUDIT.md` and
`docs/archive/DISTRIBUTED_SYSTEMS_PLAN.md`. For each finding in its
area, say whether it is resolved. Its other background reading is
`third_party/snoringcat-platform/PLATFORM_ARCHITECTURE.md`.

## h37-history (Opus, 2 h)

1. **Where we left off.** Source: claude session 530145bc
   (2026-10-09 to 10-12), transcript
   `C:\Users\lsl\.claude\projects\c--Users-lsl-Repositories-hopnbop\530145bc-eab8-4e3c-8486-546435124a22.jsonl`
   (10.8 MB). Its subagent transcripts are in the folder of the same
   name. Don't read it raw: extract the assistant's text replies with a
   small script. Levi's prompts there (UTC):
   - 10-09 21:56 "Where'd we leave off with hopnbop workstreams?"
   - 10-11 17:38 "The outstanding items: Let's address all of these"
   - 10-12 01:21 answers to "Needs your call"
   - 10-12 03:30 "Still open for you: Fix all..."
   - 10-12 21:22 the release

   Record:
   - what the first reply determined: each workstream, how old it was,
     where it stood, and the evidence used;
   - the outstanding-items list;
   - Levi's decisions;
   - what was still open at the end.
2. **The testability conversation.** Levi remembers asking:
   - how we test, execute and verify changes;
   - whether to decouple systems so Claude can test them in isolation;
   - whether Claude can run the real game end to end, start a match,
     and open and use the settings menu.

   No user prompt on this machine matches it. Every project's prompts
   were already searched for "decoupl", "in isolation", "testable",
   "e2e" and "settings menu". Try other wordings too ("harness",
   "drive", "play the game", "screenshot", "automat", "verify"), and
   look in:
   - the assistant replies and subagent prompts of 530145bc (the
     harness, `scripts/agent/`, landed in 5d913da4 on 2026-10-11);
   - other transcripts under `C:\Users\lsl\.claude\projects\`;
   - Muse sessions under `C:\Users\lsl\.local\share\muse\sessions\`, if
     present;
   - claude-config `jobs/reports/followups/2026-10-*.md` and the
     `LEDGERS.md` inbox;
   - `docs/archive/test-architecture-plan.md`, `scripts/agent/README.md`
     and the harness commits.

   It may have happened on the laptop, whose transcripts aren't here.
   If so, say so, and reconstruct what was concluded and built from the
   commits and docs.
3. **Loose threads.** List every item from 1 and 2 that was deferred,
   offered or left open. Give each a current status from the three
   ledgers (hopnbop, `third_party/snoringcat-platform/`,
   `addons/rollback_netcode/`) and from `git log`: Done (commit), Open
   (ledger ID), or Unledgered.

Findings file: `h37-history.md`, with sections "Where we left off",
"Testability conversation" and "Loose threads".

## h37-exec-a (Opus, 2 h): CI, platform suites, compliance, GUT

1. Check the tools: `godot --version`, `docker info`, `go version`,
   `gh auth status`.
2. Prepare and import:
   - Run `scripts/setup-platform-addon.ps1` so the gitignored SDK copy
     matches the submodule.
   - Run `godot --headless --path . --import` once in hopnbop. CI
     retries a crashed import once; do the same.
   - Run `git status --short` and record any tracked file the import
     changed. Don't revert it.
   - Create `.claude/probes/H37/import.done` with the outcome in it,
     whether or not the import succeeded.
3. CI: run `gh run list` in hopnbop, the platform repo and the netcode
   repo, and record:
   - the newest run of each workflow on main;
   - anything failing in the last two weeks;
   - workflows that run only on pull_request or dispatch (H11), with
     their last run date.
4. Platform: `go vet ./...` and `go test ./...` in
   `third_party/snoringcat-platform/runtime`, plus any other suite the
   platform's CLAUDE.md lists.
5. Under `net.lock`, run `pwsh scripts/local-smoke-test.ps1`: the
   compliance suite against a local Nakama, about 1 min.
6. GUT in hopnbop, the way `.github/workflows/pr-validate.yml` runs it
   (a per-file loop): every `test/**/test_*.gd` with `-gexit`, one at a
   time. Hold `net.lock` while running `test/integration/`.
   - Record per-file passed, failed and pending, and the total.
   - Flag any file that says "Nothing was run". It exits 0 anyway (see
     CLAUDE.md "Testing").
   - H35 is a known bleed in full-directory runs; per-file should pass.
   - Then run the netcode addon's tests, if it has any.

For each failure, give the test, the assertion text, and a first guess
at the cause, labelled as inferred. Fix nothing. Findings file:
`h37-exec-a.md`; logs go under `h37-exec-a/`.

## h37-exec-b (Opus, 2 h): harness and end-to-end probes

This agent answers Levi's question: can Claude run the real game end to
end, start a match, and open and use the settings menu?

1. Before starting Godot, wait for `.claude/probes/H37/import.done`: one
   blocking PowerShell loop with a 15 min timeout.
2. Read `scripts/agent/README.md`. Run every scenario in
   `scripts/agent/scenarios/` that needs no backend, and record each
   `AGENT_RESULT` line and run dir.
   - Scenarios that start a server need `net.lock`.
   - Other agents run Godot at the same time, so re-run a failing
     scenario once. One that then passes is "flaky under load".
3. Under `net.lock`, start a local Nakama as the README describes for
   `-Backend`, and run the backend scenarios.
4. Probes, written as scenarios under `h37-exec-b/scenarios/`:
   a. **Settings.** From the lobby, reach the settings menu with the
      inputs a player uses, change a volume and a toggle, and back out.
      Show that the change took effect and survives a restart.
   b. **Matchmaking end to end.** Two clients against the local Nakama,
      through the real matchmaker, allocation, connect, match start,
      match end, game over and play again. Then a party of two, if the
      harness can form one. Where a step can't run, name exactly what is
      missing and what it would take.
   c. **Capability table** for the harness. For each capability, give
      yes, partly or no, with evidence: menu navigation, reading UI
      state, screenshots, assertions, several clients, local backend,
      parties, persistence across restarts, gamepad input, web build.
5. Stop every process and stack you started.

Fix no product code; a harness limitation is a finding. Findings file:
`h37-exec-b.md`; run dirs, screenshots and scenarios go under
`h37-exec-b/`.

## h37-account (Opus, 2 h)

Flows:
- **Sign-in:** anonymous or device sign-in, Google, and any other
  provider in the code; web vs native; "crossplay auth".
- **Session lifecycle:** boot refresh, expiry, backoff, sessions kept
  while offline, expiry mid-session.
- **Account linking and merge.**
- **Sign-out:** `SignOutRouter` and its shared cleanup; consent kept.
- **Legal consent and re-consent:** `legal_version` parity; the legal
  text in `web/` and `legal/`.
- **Account deletion and data export.**
- **Display names and usernames:** provider names must not leak.
- **Profile images.**
- **Two devices signed in at once.**
- **Anonymous accounts:** their limits, and the upgrade to a linked
  account.

Code:
- the game: `src/core/` (backend_api_client, account_deletion_prompt,
  profile_image_cache, legal_version, global, and the sign-out router)
  and the `src/ui/` auth, consent and account panels;
- the SDK: `third_party/snoringcat-platform/addons/snoringcat_platform_client/`;
- the runtime: `third_party/snoringcat-platform/runtime/` (auth,
  account, account_cron, data_export, admin_key, player_data).

Tests:
- `test/unit/platform/`;
- the runtime's `*_test.go`;
- the compliance suite;
- the harness scenarios `sign-out-*`, `consent-*`,
  `export-data-offline`, `log-out-sign-in-cycles` and `session-*`.

Background: `.claude/rules/ui.md` (sign-out flows).

Ledger: H15 (shared with h37-matchmaking), H18, H22, H23, and H32
(shared with h37-stats-ops). Also the platform `SP` items in this area.

TODO-scratch notes. These are a start; scan the file for more:
- "Don't use Google or Apple account usernames!"
- "Test everything with anonymous users"
- "Test trying to login on two devices at the same time..."
- "Fix crossplay auth"
- "Update Google Oauth (and facebook?) to have privacy and TOS links"
- "Should we include copies of legal docs in-game?"
- the polish items for consent and auth

## h37-social (Opus, 2 h)

Flows:
- **Friends:**
  - friend codes;
  - requests: send, accept, decline, cancel;
  - limits, removal, and the block list;
  - presence and how fresh it is;
  - the notification socket, with the poller as its fallback.
- **Parties:**
  - create, invite (friends and codes), join, leave, kick, disband;
  - leader handoff and control;
  - party state sync, and the party panel;
  - what happens to a party when a member signs out, goes offline or
    quits;
  - the client side of party matchmaking. h37-matchmaking owns tickets
    and allocation.
- **Social UI:** the friends and party panels, toasts and side panels,
  and their U/D/L/R navigation contract (`.claude/rules/ui.md`).
- **Abuse:** request spam, blocked users, rate limits, spoofed ids.

Code:
- the game: `src/core/` (party_manager, friends_notification_poller,
  and the party matchmaking context) and the `src/ui/` friends and party
  panels;
- the SDK's social modules;
- the runtime: friend_code, friends_limits, block_list, party, and
  presence.

Tests:
- `test/unit/platform/`, including `test_party_matchmaking_context.gd`;
- the runtime tests;
- the compliance suite.

Ledger: H18 (the party panel's error toasts), H21 and H23. Also the
platform `SP` items in this area.

TODO-scratch notes. These are a start; scan the file for more:
- "Test friends presence tracking"
- "Let's fix the friends panel"
- "Test/fix party formation, matchmaking, and lobbying"
- "Test party matchmaking" (shared with h37-matchmaking)
- the polish items for friends, side panels and toasts

## h37-matchmaking (Opus, 2 h)

Flows:
- **Tickets:** solo and party; platform attributes and the choice of
  transport; protocol-version gating.
- **Cancel and failure paths** (H19, H20).
- **The `matchmaker_matched` hook and allocation:** Edgegap, local
  Docker and the hybrid path; failures and timeouts; teardown and
  deactivation.
- **The connection payload** and session-ticket validation on the game
  server (H17).
- **Connecting** over ENet or WebRTC, including signaling.
- **Warm-up and match start.**
- **Disconnects, mid-match and during matchmaking:**
  - the player is removed;
  - the last player standing wins by default;
  - disconnected players lose on the game-over screen;
  - if every other client drops while matchmaking, the remaining one
    returns to the lobby.
- **Reconnect** (H25).
- **Match end and results:** `match_result_reporter`, the runtime's
  `match_lifecycle`.
- **Game over and play again,** including when one client replays and
  the other doesn't.
- **Local and offline mode:** play offline, end the match, play again
  (H27).
- **Preview sessions** (H26).
- **Server lifecycle and shutdown.**
- **Skill-based pairing:** a TODO idea; assess feasibility only.

Code:
- the game: `src/core/` (nakama_matchmaker_client,
  game_session_manager, edgegap_server_provider,
  local_only_session_provider, preview_session_provider,
  reconnect_handler, match_result_reporter, game_match_state,
  match_state_synchronizer, game_panel);
- the netcode addon's connector;
- the runtime: allocator, fleet_allocator, local_allocator,
  allocator_metrics, match_lifecycle, party, per_game_config;
- the SDK's matchmaking.

Tests:
- `test/integration/multiplayer/` and `test/unit/platform/`;
- the runtime tests;
- the compliance suite;
- the harness scenarios `match-2-clients` and `sign-out-*`.

Background: `.claude/rules/transport.md`, and `.claude/rules/deploy.md`
for the synthetic-match-probe.

Ledger: H15, H17, H19, H20, H21, H24, H25, H26 and H27, plus the
platform `SP` items in this area.

TODO-scratch notes. These are a start; scan the file for more:
- "Test party matchmaking"
- "Test play again"
- "Test one client replays and the other doesn't"
- "Test players disconnecting: ..."
- "Test the new warm-up logic", with its five sub-tests
- "play offline; end match; play again"
- "Test local mode" and "Test offline mode"
- the skill/rank pairing idea
- the AWS-era "Remaining items for end-to-end testing"

## h37-stats-ops (Opus, 2 h)

Flows:
- **Per-player match stats:** recording on the server, posting,
  idempotency, and what the client shows (My Stats, the stats screen).
- **Leaderboards:**
  - writes and rating partitions;
  - whether anonymous players are excluded;
  - the in-game screen;
  - the public web board and its runtime route;
  - caching and rate limits.

  f77828e8 reworked them.
- **Settings:**
  - the in-game settings menu;
  - `local_settings.gd` persistence, `level_preferences` and
    `device_config`;
  - the release overrides, `Settings.apply_release_overrides()`;
  - any server-side or synced settings.
- **Per-game config:** `game.yaml` → `sync-game-config.ps1` →
  `register_game`; version_check; the protocol and display versions;
  legal-version parity.
- **Crash reporting:** the client queue and redaction, the runtime RPC,
  H32 and H33.
- **Observability and ops:** prod-health-check, synthetic-match-probe,
  nightly-smoke and check-prod. Which of them would a regression in each
  flow trip?
- **Retention and cleanup crons.**
- **Rate limiting and CORS** (dadd2d16).

Code:
- the game: `src/core/` (player_match_stats, match_result_reporter,
  backend_api_client, local_settings, level_preferences, device_config,
  crash_reporter, crash_report_text, legal_version, global) and the
  `src/ui/` leaderboard, stats and settings screens;
- the runtime: leaderboards, leaderboard_public, player_data,
  crash_report, per_game_config, account_cron, client_ip.

Tests:
- `test/unit/`;
- the runtime tests;
- the compliance suite;
- the harness scenario `leaderboard-local-backend`.

Background:
- `.claude/rules/crash-reporting.md` and `.claude/rules/deploy.md`;
- `docs/design/crash_report_review.md`;
- claude-config `jobs/`, for what watches production.

Ledger: H28, H29, H31, H32 and H33, plus the platform `SP` items in this
area.

TODO-scratch notes. These are a start; scan the file for more:
- "Stats screen..."
- "Test leaderboard screen"
- "Let's fix the leaderboard screen", with every sub-bullet: the screen
  type, rows, the close button, X to close, font size, anonymous
  players, "filter", "tab", and the number after "Your rank:"
- "Existing player records won't appear on the leaderboard..."
- the release-checklist items about settings flags and versions

## h37-triage (Opus, 2 h)

Triage every note in `TODO-scratch.md`. Its lines 9-838 are lines 46-875
of `core/frame_driver.gd` at netcode commit 6022552.

1. **Date each line** with `git -C addons/rollback_netcode blame 6022552
   -L 46,875 -- core/frame_driver.gd`, which gives the first-added date
   and commit. The six "Main list" notes from 6022552 are fresh. Several
   restate bugs fixed on 2026-10-11: the death blink, the splash, and
   springs while invincible. Treat those as regressions or incomplete
   fixes, not as stale.
2. **Group lines into items**, each a note plus its sub-bullets. For
   each item, record:
   - area: gameplay, art, UI polish, distributed systems,
     platform/store, release process, business/ops, aspirational, or
     reference/prompt text;
   - verdict: Done (with the commit), Stale (with why), Open, Idea, or
     Reference;
   - size: S under 1 h, M under 1 day, L under 1 week, or XL;
   - priority: P1 player-facing bug or blocker, P2 quality, P3 nice to
     have;
   - low-hanging: yes or no.
3. **Verify** the gameplay, UI, art, release, platform/store and business
   items against code and history: search the code, run
   `git log -S` and `--grep` across hopnbop and the netcode and platform
   repos, and read both ledgers.
   - AWS-era items are likely stale (AWS was retired 2026-05-03, in
     Phase F). Say what replaced them.
   - The notes name a multi-game refactor plan by path. Check that it
     exists and what state it describes.
4. **Distributed-systems notes** (account, social, parties,
   matchmaking, disconnects, stats, leaderboards, settings): tag the
   domain agent that owns each (h37-account, h37-social, h37-matchmaking
   or h37-stats-ops) and give only a quick status. Those agents go deep.

Findings file: `h37-triage.md`. It holds the item table in file order,
then a proposed order: low-hanging and high-priority first, large and
aspirational last.

## Phase 2: h37-verify (Opus, 75 min)

Added 10:40, after six of the phase 1 reports. It confirms the findings
that may hurt production, in the order below, and records each one as
Verified, Broken or Suspect, with evidence. The rules above apply:
read-only, files in `.claude/probes/H37/h37-verify/`, PowerShell, no
production. h37-exec-a and h37-exec-b are done, so hold `net.lock` for
the whole run and delete it at the end. Docker is allowed. Start from
h37-exec-b's findings file and its `h37-exec-b/` folder: its
`stack.ps1` brings up the local Nakama stack, and its scenarios drive
matchmade and preview matches.

0. **How close production is to the port-pool leak** (h37-matchmaking
   finding 1, Broken and Verified by a Go probe). After about 100 NA
   matches since the last Nakama restart, every NA match fails to
   allocate. Use local records only:
   - the repo's config, to see whether production runs hybrid
     allocation;
   - prod-health-check and other job records in
     `C:\Users\lsl\Repositories\claude-config\jobs\status\2026-10.jsonl`
     (`Get-StatusEntries`) and `jobs\reports\`, for match counts and
     the last Nakama restart or deploy.

   As soon as you have an estimate, send the coordinator one line with
   SendMessage to `main`: NA matches since the last restart, and how
   sure you are. Then go on.
1. **Clients crash (signal 11) when the server goes away mid-match**
   (h37-exec-b finding 1, Verified on the editor binary). First, size
   it.
   - In the normal production flow, does the server quit
     (`game_session_manager.gd:554-569`) while clients are still
     connected?
   - Does that reach the crash path?
     1. `network_connector.gd:363` in `peer_disconnected`;
     2. `game_panel._on_connection_lost`;
     3. `reconnect_handler.gd:137` and `:193`;
     4. `network_connector.gd:293`, which replaces the peer while the
        old peer is still dispatching.

   Trace it. Then run a 2-client match to GAME_OVER, with the server
   set to quit after one match the way production does, and record
   whether the clients crash.

   Then repeat with exported release clients, if Godot 4.7.2 export
   templates are installed (don't download them):
   - Export the Windows preset with `--export-release` into
     `h37-verify/export/`.
   - Run the exported clients under the harness sandbox: throwaway
     `APPDATA` and blackholed backend URLs. Read `run-game.ps1` for how.
   - If you can't reproduce that sandbox for an exported binary, don't
     run it, and record why.

   Finally, compare with H25 in `LEDGER.md`: is it the same crash?
2. **Networked pause in a release build** (h37-exec-b finding 2,
   Verified on the debug path only). With the exported clients from 1,
   press Escape on client 1 mid-match. Record whether the server and
   client 2 pause.
3. **A party invite is a forced join** (h37-social finding 1, Believed
   from the Nakama source). On the local stack, create users A, B and C
   by device auth, over loopback REST only.
   1. A creates a party and invites B. B has never accepted anything
      and is not A's friend. Read B's membership state.
   2. B blocks C. C creates a party and invites B. Read B's state
      again.
   3. With A and B in A's party, A calls `party_start_matchmaking`.
      Record what B is sent (notifications, socket messages), and
      whether anything asks B first.

   Record the raw responses.
4. If time remains, any finding the coordinator sends you while you
   run.

Stop at 75 minutes, because the week is near Levi's usage limit. Hand
off the same way as the other agents. Findings file: `h37-verify.md`,
one section per item above.

## Phase 3: h37-report (Opus, 2 h)

Writes the report from the findings. It starts once every phase 1 agent
has reported. h37-verify's results come later, as a message or as
`h37-verify.md`.

Inputs:
- the findings files, `.claude/probes/H37/<agent>.md`;
- each agent's final report, extracted to
  `.claude/probes/H37/handbacks/<agent>.md`;
- Levi's request at the top of this brief;
- for current IDs, and to avoid duplicates, the ledgers:
  - hopnbop `LEDGER.md`;
  - `third_party/snoringcat-platform/LEDGER.md`;
  - `addons/rollback_netcode/LEDGER.md`;
  - `C:\Users\lsl\Repositories\claude-config\LEDGER.md`, plus the inbox
    in `LEDGERS.md`.

The findings files hold about 4,700 lines, more than one context can
hold. Work in this order:
1. Read the handbacks first.
2. Then read each file's Summary and Proposals.
3. Open the flow sections only when a section of the report needs
   them.

Write the report one section at a time, appending to the file. Keep a
`Status:` line at its top that names the finished sections, so a
restart after a compaction can carry on from there.

Outputs. Leave them uncommitted; the coordinator reviews and commits
them.
1. `docs/design/H37_systems_audit.md`, the report. It is written for a
   later Claude session that will split it into tasks, and for Levi.
   Every item carries:
   - its verdict, exactly as the source agent gave it. Never upgrade
     Believed to Verified. Where agents disagree, say so.
   - a `path:line` or appendix pointer;
   - a fix sketch and a rough size;
   - its proposed ledger ID.
2. `docs/design/H37/<agent>.md`: each findings file copied as an
   appendix, changed only by redactions.
3. `docs/design/H37/artifacts/<agent>/`: copies of the reusable text
   artifacts a follow-up needs, such as scenarios, `stack.ps1`, scan
   scripts and probe tests. No logs, run directories or app data.

The report's sections:
0. **Read first.** The most severe findings across all domains, each
   with its verdict. Several agents found the same bug from different
   sides, so deduplicate.
1. **How we test, execute and verify** (Levi's first question).
   - Cover every layer: runtime Go tests; SDK and game GUT; netcode
     tests; the compliance suite; harness scenarios; CI workflows;
     production probes and jobs. For each, say what it covers, its
     current state and what is broken.
   - Then answer directly: can Claude run the real game end to end,
     start a match and use the settings menu? Use h37-exec-b's
     capability table and recipes.
   - Then answer directly: is decoupling worth it?
     - Nobody had analysed this before (h37-history).
     - Answer it from the domain files' Testability lines and
       h37-exec-b's harness gaps.
     - Name the seams, fakes or harness features that would let Claude
       test each system unattended, ranked by value and cost.
     - Name the refactors that are not worth doing.
2. **Where we left off** (h37-history): the recap, and the
   loose-threads table with current status.
3. **The audit by domain:**
   - account;
   - friends, parties and presence;
   - matchmaking, sessions and transport;
   - stats, leaderboards and settings;
   - operations, CI and disaster recovery.

   For each, give: the flows and cases covered; the top findings; test
   coverage; and whether the archived audits' findings are resolved.
4. **Making the non-gameplay systems testable by Claude:** an ordered
   roadmap.
5. **TODO-scratch triage** (h37-triage). The per-note table stays in
   the appendix. Here, give:
   - the ordered list;
   - quick wins;
   - stale notes, and what replaced them;
   - notes that need Levi's intent;
   - the bucket held back until everything else is polished.
6. **One ordered work plan.** Merge 0, 3, 4 and 5 into batches that a
   session can take one at a time. Count both priority and effort.
7. **Decisions waiting on Levi.**
8. **Proposed ledger items**, one table per ledger, with these columns:
   - the proposed ID, the next free number in that ledger, counting
     Done items;
   - the section;
   - the bullet text, in the ledger's format;
   - a pointer into the report.

   Also list:
   - updates to existing items: H11, SP10, the dead SHAs h37-history
     mapped, and every existing item an agent re-checked;
   - the `LEDGERS.md` inbox entries to file.

   The coordinator files all of these as written, because subagents
   don't edit ledgers.
9. **What this audit did not check.**
10. **Appendix index.**

The repo is public. The report, the appendices and the artifacts must
not contain:
- secrets, keys or tokens;
- signed URLs;
- email addresses;
- production player ids or names;
- IP addresses the repo doesn't already publish.

Scan every file you copy and replace any such text with `[redacted]`.
List each redaction in your final report.

Style: plain sentences, no em dashes, and tables where they help. Be
thorough but keep the report easy to navigate: link to the appendices
for depth instead of copying them.

The stop rule above applies (2 h). Your final message: at most 60
lines, covering the sections written, the redactions, any judgment
calls, and anything you could not resolve.

## Phase 2b: more verification (added 11:00)

At 10:55 Levi lifted the usage limit for this audit ("finish this audit
regardless of usage limits"). Two changes follow.

**h37-verify runs for 2 h**, until about 12:45, instead of 75 minutes.
After items 0 to 3 it takes these on the local stack it holds, in
order, as sections 4a to 4f of `h37-verify.md`:

- 4a. h37-social finding 3: can a party's creator leave, and can
  anything disband a party?
- 4b. h37-social finding 4 (its F6; pairs with SP14): with more than 50
  notifications stored for one user, does the HTTP poll the client uses
  ever return a newer one?
- 4c. h37-social finding 5: a member whose client is gone. Does
  `party_start_matchmaking` wait, fail or go ahead, and what do the
  others see?
- 4d. H15 end to end (h37-account AN-1b, h37-social F10): after a
  client logs out, does its realtime socket stay open and keep
  receiving the old user's notifications or presence?
- 4e. h37-matchmaking finding 10 (its F12): when every client drops and
  the server quits 12 s later, does the runtime get `match_end` or a
  cancel, and what does the match row keep? Pairs with h37-stats-ops
  RT1.
- 4f. Item 2 without an exported release client: say exactly what
  blocks the sandbox for an exported binary, and whether a debug export
  run under the harness is a fair stand-in for the pause question. Run
  it only if it can be sandboxed.

**h37-verify2 (Opus, 2 h)** takes the high-severity findings that are
still Believed, starting with those that need no running stack.
Findings file `h37-verify2.md`, scratch files in `h37-verify2/`, the
rules above. Go and GUT tests that start no Nakama stack and no game
server need no lock. Exports, the stack, Docker and fixed ports wait
for `net.lock`, which h37-verify holds until about 12:45: take it once
the file is gone.

1. **G1.2, guessable session ids** (h37-matchmaking finding 2). Trace
   how the `matchmaker_matched` hook mints the session ids in the
   connection payload, and how the game server checks them
   (`network_connector.gd:602-642`). Can another player read or compute
   a valid id? Prove it either way with a Go or GUT probe, and say how
   the answer changes the fix for G1.1 and G1.3.
2. **No match forms while an allocation runs** (h37-matchmaking finding
   3). Probe it in a runtime copy with a slow fake allocator, the way
   h37-matchmaking's `runtime-copy/` probe works: while one matched set
   allocates, can a second set match and allocate? Then finding 4 (the
   120 s timeout cancels the matched set) the same way.
3. **AN-1, the guest upgrade signs in instead of linking**
   (h37-account). Trace the client flow down to the SDK and runtime
   calls, and prove with a GUT test against a fake client whether the
   guest's account, stats and friends survive the upgrade. DEL-2 as
   well, if it is cheap.
4. **LG-1 on every export preset** (h37-account LG-1, h37-stats-ops
   C7; the web pack is already Verified). Once `net.lock` is free,
   export only the pack for each preset in `export_presets.cfg` into
   `h37-verify2/export/` (`--export-pack`; a `.zip` target is easier
   to list) and record whether `legal/` is inside. If the export fails
   for want of templates, record that and drop the item; don't download
   them.
5. **On the stack**, once `net.lock` is free: whichever of 4a to 4e
   h37-verify did not reach, in that order. Read `h37-verify.md` first.

Hand off the same way as the other agents.
