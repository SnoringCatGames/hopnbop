# H37 systems audit: report

Status: final (2026-10-14). The items in section 8 are filed in each
repo ledger (`LEDGER.md`), which now holds the live state. The SP70,
SP27 and H41 chain went in as Urgent: production runs the runtime tree
the audit tested (the 10-12 deploy of plat c4c7413), the condition in
section 7 row 1.

Read-only audit of hopnbop's non-gameplay systems and of how they are
tested, run on 2026-10-14 by eight agents (phase 1), two verify agents
(phases 2 and 2b) and this report (phase 3). Brief: `docs/design/H37_audit_brief.md`.
Repos at audit time: hopnbop 44f0093e to e03f8861, snoringcat-platform
8e85e8a, rollback_netcode 7d6ebd9.

How to read it:

- **Verdicts** are copied from the agent that found the item, never
  upgraded: Verified (a run, or a cited test that covers the case),
  Believed (code reading), Suspect, Broken. Where two agents disagree, the
  item says so.
- **Pointers.** `game:` is hopnbop, `plat:` is
  `third_party/snoringcat-platform/`, `rt:` its `runtime/`, `sdk:` its
  client addon, `net:` is `addons/rollback_netcode/`, `nakama:` is the
  Nakama 3.25.0 source. Bare paths are hopnbop.
- **IDs** (H38+, SP26+, RN6+, CC51+) were proposed here and are filed in
  each repo ledger; section 8 lists them. Another session filed CC50
  first, so the claude-config items are CC51 to CC57.
- **Sizes**: XS under 30 min, S under 2 h, M half a day to a day, L
  several days.
- **Appendices** (`docs/design/H37/<agent>.md`) are the agents' findings
  files, changed only by redaction. Probes and scenarios a follow-up can
  reuse are in `docs/design/H37/artifacts/<agent>/` (a `.gdignore` keeps
  Godot from importing or exporting them).

## 0. Read first

**What this is.** A read-only audit, requested by Levi on 10-14, of
everything in hopnbop around the gameplay and of how it is tested (brief:
`docs/design/H37_audit_brief.md`). Eight agents covered accounts, friends
and parties, matchmaking and transport, stats, settings, crash reports and
operations; ran every test suite locally; played real matches through a
local backend; dated and checked the 112 TODO-scratch notes; and recovered
where the 10-11 sessions left off. Two verify agents then re-ran the most
severe findings on a local stack. Nothing wrote to production; the only
production contact was public GETs. Sections 1 to 5 hold the findings, 6
to 8 the plan and the proposed ledger items, 9 what nobody checked, 10 the
appendices.

### 0.1 Top risks

Verdicts as the source gave them. Section 3 has the full row for each,
with every pointer.

| # | Item | Verdict (as given) | Fix sketch | Size | Proposed |
|---|---|---|---|---|---|
| 1 | **H40 (LG-1).** Terms, Privacy and Data Deletion open blank in every export, while the consent screen asks players to accept them (`export_presets.cfg:10,56,124,167`). | acct: Broken in the shipped web build (the production pck, by a public GET). verify2 item 4: Broken, Verified on all four presets (pack contents); the blank screen in a running export Believed | `include_filter="legal/*"` on every preset; a CI check that the pck holds the texts | S | Urgent |
| 2 | **SP32.** A party invite is a forced join: full membership with no consent, past a block, two parties at once (`rt:party.go:716-732`). | soc: Believed. verify item 3: Broken, Verified on a local stack | A stored invitation and an accept RPC; Before hooks that refuse raw group calls on `party-*` groups | M to L | Urgent candidate |
| 3 | **H38.** Clients crash (signal 11) when the server goes away mid-match: an ENet drop, a server crash, a container stop (`net:core/network_connector.gd:293,363`). | exec-b: Verified, 4 of 4 runs. verify item 1: Broken; Verified in editor builds, and in release builds at engine level by a minimal 4.7.2 repro (verify items 1 and 4f: 4 of 6 cells crash on the release template, 1 of 6 in the editor, 0 of 6 on the debug template, so editor and debug runs hide it); the shipped binary not run. verify: the same family as H25 | Defer both peer changes (reconnect attempt 1 and `client_exit_match()`) with `call_deferred`, as the normal match end does (`game_panel.gd:1443-1464`); check the fix on a release template | S | Next, top (exec-b: Urgent candidate). Supersedes H25 |
| 4 | **SP70, SP27 and H41: a takeover chain.** Together, any signed-in player can find a running match server, connect to it and take a slot. Link 1 (SP70): `match_metadata` (co-players' user ids) and `server_registrations` (server IP, port, FQDN) are readable by any signed-in player (`rt:fleet_allocator.go:1149,1174`). Link 2 (SP27, G1.2): session ids are `<userid>_<n>`, so they can be computed. Link 3 (H41, G1.1 and G1.3): the game server does not enforce them, and a claimed id takes over the slot (`net:core/network_connector.gd:602-642`). | Each link has its own verdict; nobody ran the chain end to end. SP70: verify item 4e: Broken, Verified on the local stack; production not checked. SP27: verify2 item 1: Broken, Verified. H41: mm: Broken; G1.1 and G1.3 Verified by a GUT probe | In this order: (1) PermissionRead 0 on `match_metadata`, `server_registrations` and `synthetic_matches`, plus random per-slot tokens and a token-to-user-id map on the server (closes H17); (2) then G1.1 together with the G1.3 re-claim rule. G1.1 alone would kick the owner and keep the thief | S, then M, then M | Next, top of batch 2. Urgent, and the production check, are Levi's calls (section 7) |
| 5 | **H15.** After log-out the realtime socket stays open: the next player on the device receives the old account's notifications, and their party is created as the old account. | verify item 4d: Broken, Verified end to end (2 runs) | Close the socket in SignOutRouter's shared cleanup and on every account change | S | Existing item, update |
| 6 | **H67 (ST1).** A settings change reverts two launches later, for every player with a session (`src/core/settings_cloud_sync.gd:33-42,90-93`). | Verified (probe) | Compare against `Settings.new()` defaults; advance sync-at on a successful save | S | Next |
| 7 | **H11.** CI never ran on 25 commits on main, the 0.54.0 release among them. exec-a's local runs of every suite pass. | Still true (exec-a) | `push: main` triggers on PR Validate and Compliance Matrix | XS | Existing item, update |
| 8 | **SP26.** The local port pool leaks a UDP/TCP pair per match; after 100 local matches since a Nakama restart every NA match fails, with no Edgegap fallback (`rt:local_allocator.go:323-346`). | mm: Broken, Verified by a Go probe. verify item 0: latent; with no real players, exhaustion about 16 to 17 weeks after a restart | Release the pair in `Stop`; reconcile with running containers | S | Next |
| 9 | **H57 (AN-1).** The guest upgrade signs in to the provider's account instead of linking; the guest's progress is abandoned while the panel says "Keep Your Progress". | acct: Broken by code. verify2 item 3: Broken, Verified (GUT probe) | Link the provider onto the guest's account, with a merge decision | M | Next |
| 10 | **SP30 + SP29.** No match forms for anyone while an allocation runs, and one player's 120 s timeout cancels the whole matched set's allocation. | verify2 item 2: Broken, Verified (both) | Allocate in a goroutine; an "allocating" message that stops the SDK timer | M + S | Next |

One decision sits next to these: **H39**, networked pause ships enabled,
and one player froze the server and the other client for 7 s (exec-b run
7: Verified on the editor path; triage T107: Believed; verify item 2:
Believed for release builds, not run; verify item 4f: a release run needs a
custom template, and with no debug gate a debug export behaves the same,
Believed). It is one line once Levi decides (section 7).

### 0.2 Answers to Levi's questions

- **Can Claude run the real game end to end?** Yes, with limits (1.2).
  exec-b walked a bunny into the rabbit hole, matchmade through a local
  Nakama into a real match on a local game server, played to GAME_OVER,
  queued again, and used the settings menu by key presses alone. Not yet:
  parties, more than 2 clients, gamepads, web or WebRTC, exported builds,
  real allocation. Section 4 is the plan that closes those gaps.
- **Is decoupling worth it?** Yes for a handful of narrow seams (a Go
  fake-`nk` harness, the phase 1 probes landed as tests, pure functions for
  server-side match decisions); no for a broad decoupling (1.3; H71).
- **Where did we leave off?** Section 2. The 0.54.0 release thread is
  closed; 22 loose threads are open under ledger IDs and 8 were unledgered
  (proposed in section 8).
- **TODO-scratch:** section 5. The six "fresh" notes are not regressions;
  all six were fixed on 10-11.

### 0.3 Two things that are not what they look like

- **The 10-14 DR drill reported red, but it was a tabletop exercise, not an
  outage.** Its scenario, Caddy's certificate renewal failing for 14 days,
  did not happen: cert-expiry ran at 05:43 PT on 10-14 and all three
  production certificates have 45 to 50 days left. The drill's gaps are
  still real proposals; G1, nothing pages while renewal fails, is CC51.
- **The weekly usage limit** (history; CC54). The week was at 72% at 08:51
  UTC on 10-14, and weekly-meta-audit expected the limit late 10-14 or
  early 10-15. LLM jobs then fail with no report and no status entry until
  10-19 19:00 UTC, so a missing digest in that window is the limit, not a
  new failure.

Levi's decisions are collected in section 7.

## 1. How we test, execute and verify

### 1.1 The layers

| Layer | What it covers | State on 10-14 | What is broken or missing |
|---|---|---|---|
| Runtime Go (`rt:`) | Unit tests per package: allocators, party, friends, privacy, export, crash reports, leaderboards. vet and staticcheck. | 181 tests and 225 subtests pass; vet and staticcheck clean (exec-a). Runs on every `runtime/**` push in `nakama-runtime.yml` and gates the deploy. | No fake `nk` harness, so hooks that take `nk` (party invites, friend caps, `matchmaker_matched` fan-out) are untested; social and matchmaking each built one ad hoc. `staticcheck@latest` unpinned (`nakama-runtime.yml:44`). 5 files not gofmt-clean and no gofmt gate (SP10). signaling-proxy and geoip-sidecar have no tests. Platform CLAUDE.md says no per-package tests exist. |
| Game and SDK GUT (`test/unit`, `test/integration`) | Netcode reconciliation, match state, crash reporter, auth refresh and privacy, consent, friends and party clients, settings sync, UI rows. | Unit 492/492 in 45 files, integration 135/135 in 16 files, run one file at a time (exec-a). | CI runs it only by manual dispatch (H11): 25 commits, including the 0.54.0 release, were never CI-checked. Directory runs can miss tests (H35). Fixtures log "no animation 'Rest'" 37 times per run. |
| Netcode GUT (`net:test/`) | Circular and rollback buffers, frame driver, state bundling, send rate, WebRTC signaling parsing. | 208/211 in 9 files (exec-a). | 3 failures in `test_webrtc_signaling.gd` are test bugs (RN6). The tests run nowhere in CI (RN3) and the addon compiles only inside hopnbop (RN1). |
| Compliance suite (`sdk:test/compliance/`, via `scripts/local-smoke-test.ps1`) | The SDK against a real local Nakama with the runtime plugin: auth, friends, party, matchmaking with mock allocation, export, delete. | 80/80 in 35 files, 79 s, clean teardown (exec-a). | Almost every case is single-user, so cross-user bugs (forced party join, start checks, block scope) pass; the invite test accepts membership state 2 or 3. Platform "Client SDK CI" runs no tests (63 green runs, zero tests). `local-smoke-test.ps1` rewrites the checkout it runs in. Compliance Matrix is dispatch-only (H11). |
| Agent harness (`scripts/agent/run-game.ps1`) | Real game processes driven by key presses: offline play, local matches, sign-out flows, consent, export, i18n, local-backend leaderboards. | Committed scenarios: 10 of 13 pass. `sign-out-local-match` and `sign-out-play-again` fail since 88e3089b raised `match_duration_sec` to 180 (H69); `leaderboard-local-backend` fails because nothing seeds scores. exec-b's 8 new scenarios: settings menu 77/77, persistence 27/27, pause, party-guest pass; the 4 matchmaking ones end with both clients crashing (H38). | See 1.2 for the gaps. |
| CI (GitHub Actions) | hopnbop: PR Validate (formatter, export smoke, Pulumi compile, parity, GUT, runtime Go), Compliance Matrix, Nightly Smoke, Game Server Deploy, Release. Platform: Client SDK CI, Nakama Runtime Deploy. Netcode: Parse check. | Newest runs all green (exec-a table, appendix `h37-exec-a.md` section 3). Nightly Smoke runs on schedule at 03:00 UTC. | PR Validate and Compliance Matrix trigger only on `pull_request` and dispatch, and work lands on main (H11). The formatter job skips everything (H9). `release.yml` has never run and no `v*` tag exists (H83). Two stale workflows still listed by `gh`. |
| Production probes and jobs (claude-config `jobs/`) | Synthetic match probe (local allocation 6 days a week, Edgegap on Wednesdays), prod-health-check (runtime build, crash counts), nightly smoke, player metrics, caddy-access-analytics, Edgegap deploy success rate, cost monitor, cert expiry, UptimeRobot, and a weekly DR drill, which is a tabletop exercise. | Green. The 10-14 DR drill reported red, but its scenario (Caddy's certificate renewal failing for 14 days) was a tabletop exercise, not a failure: cert-expiry ran at 05:43 PT on 10-14 and all three production certs have 45 to 50 days left. | Nothing exercises match_end, the leaderboard or the public route (OP2, SP58). caddy-access-analytics has reported nothing real since at least 10-01 (OP1, CC55). Player-metrics DAU counts the nightly-smoke accounts (OP3, H88, CC56). Grafana has no 5xx, 429 or RPC-error rules (OP6, SP65). The drill's gap G1 is real: nothing pages while renewal fails (CC51). The port-pool leak would show only as the probe going red (SP26). The probe cannot run against a local stack (CC53). Section 3.5 has the detail. |

### 1.2 Can Claude run the real game end to end?

Yes (h37-exec-b, appendix `h37-exec-b.md`). It walked a bunny into the
rabbit hole, matchmade through a local Nakama into a real match on a
local game server, played to GAME_OVER, and queued again. It opened and
used the settings menu by key presses only (77/77) and confirmed the
changes survive a relaunch (27/27).

| Capability | Verdict (exec-b) |
|---|---|
| Launch the game and drive a player | Yes (keyboard only) |
| Settings menu | Yes; the restart step is hand-rolled |
| Read state; take screenshots | Yes |
| Start a match (direct preview) | Yes |
| Matchmaking end to end on a local Nakama | Match 1 yes; match 2 on the same preview server has no bunnies (H26) |
| Server loss mid-match | Runs, but both clients crash (H38) |
| Networked pause | Yes |
| Local backend | Partly: exec-b's `stack.ps1`; no seeding |
| Parties | No: harness clients have no session, so `create_party()` does nothing |
| 3-4 players, gamepad, web or WebRTC, real allocation | No |

Recipes (exec-b; scenarios in `docs/design/H37/artifacts/h37-exec-b/`):

- **Settings menu:** `run-game.ps1 -Scenario h37-settings-menu`
  (offline, one process); `h37-settings-after-restart` checks persistence
  across one relaunch. Harness clients have no session, so neither run can
  catch ST1: settings revert two launches after a change for any player
  with a session (H67, section 3.4).
- **A matchmade match:** bring up the local stack with
  `artifacts/h37-exec-b/stack.ps1` (Nakama, Postgres and the runtime on
  free ports, mock allocation), then run `h37-mm-e2e` or `h37-mm-e2e-lobby`
  in match mode with 2 clients and
  `-Port 14433 -Backend http://127.0.0.1:<port> -AllowNetwork`. The client
  settings need `preview_connect_to_remote_server: true`, and
  `start_in_game: false` to start in the lobby.
- **A direct local match:** `-Scenario match-2-clients` (no backend).
- **Pause:** `h37-pause` (server plus 2 clients).

Harness gaps (exec-b), ranked by how often they block a test:

1. No committed script that only brings the local stack up, and no seed
   or restart step (H74). `leaderboard-local-backend` fails for this reason.
2. `-AllowNetwork` is required even for a loopback backend, and it then
   warns that the run may reach production (H73).
3. Client 2 starts 30 s late in matchmaker runs (`scripts/agent/run-game.ps1:441-462`) (H73).
4. Harness clients have no session, and there is no way to pass a value
   (an invite code) between processes, so parties cannot be tested (H75).
5. At most 2 clients (`run-game.ps1:315`) and keyboard input only
   (`agent_driver.gd:979-984`) (H76).
6. `ui_labels` returns translation keys, not the shown text, and
   screenshots are black for about 0.7 s after a screen change (H73).
7. The stack runs only the mock allocator, so a real local game-server
   allocation is untested (SP55, history's build item 5b).
8. No way to run an exported build: `scripts/.gdignore` keeps the agent
   scripts out of the pack, and the URL blackhole lives in the driver
   (`agent_driver.gd:16-21`), and the shipped templates refuse path
   overrides (verify item 4f), so an exported client cannot be sandboxed
   (h37-verify item 1) (H72).

### 1.3 Is decoupling worth it?

Nobody had analysed it: Levi asked on 10-11 (session 530145bc, 23:18 UTC)
and the work that followed built the harness instead (h37-history,
"Testability conversation"). This answer comes from the domain agents'
Testability lines and exec-b's harness gaps.

**Answer: yes for a handful of narrow seams, no for a broad decoupling.**
Every probe the agents wrote in this audit (fake Nakama for auth, fake
socket for matchmaking, fake multiplayer API for declarations, fake `nk`
for runtime hooks) worked by subclassing or overriding an existing method.
The code already has enough seams; what is missing is the fakes, landed
as shared test helpers, and a few decisions pulled out of node code into
pure functions. Ranked by value for cost:

| Rank | Seam, fake or harness feature | Unlocks | Cost | Source |
|---|---|---|---|---|
| 1 | Go fake-`nk` harness for runtime hooks (embed `runtime.NakamaModule`, capture NotificationSend, StorageWrite, GroupUsersAdd; fake allocators) | Party invites and starts, friend caps and rate limits, `matchmaker_matched` fan-out, allocation cancel | S for the harness, M for the hook tests | social R2, matchmaking F3 and proposal 15 |
| 2 | Land the phase 1 probes as regression tests: account probe (LK-1, DEL-2, PI-1, PI-2, SO-1), ghost-ticket and declare-validation probes, port-leak Go test, social Go probe, settings-echo probe (ST1) | The fixes for H15, H41, H61, H67, SP26, SP28, SP35, SP41 and SP43 come with tests already written (each probe asserts today's buggy behaviour, so it flips with the fix) | XS each | account, matchmaking, social, stats-ops |
| 3 | Pure functions for server-side match decisions: result-row assembly and demotion, pre-match abort, grace and idle decisions | G2.1 (H42), self-quit (H45), the grace window (H48), table tests with couch co-op accounts | S each | matchmaking F2, F12 |
| 4 | `scripts/dev-stack.ps1` from exec-b's `stack.ps1`, plus seed and restart steps | Local-backend scenarios, leaderboards, Claude matchmaking runs without hand setup | S | exec-b |
| 5 | Two- and three-user compliance cases | Forced join, start checks, leave and kick, block scope: all but the first fail today | S to M | social |
| 6 | Harness dev sign-in plus `publish` and `wait_shared` steps | Parties end to end in the harness | M | exec-b |
| 7 | Fake `Platform.party` and friends for GUT | Party UI and race tests without a backend | S | social |
| 8 | Provider grace and idle timers with a stubbed HTTP layer; signaling-proxy token table; transport classifier table | Edgegap provider and proxy logic | S each | matchmaking proposal 15 |
| 9 | Dev stack with the local allocator (history build item 5b) | Real local game-server allocation, the port leak end to end | M | history, matchmaking |
| 10 | More than 2 clients, gamepad input, golden screenshots | 3-4 player and controller flows, visual regressions | M to L | exec-b, history build item 7 |

Not worth doing (the report's judgment from the same sources):

- **Making the netcode addon standalone (RN1) for testability.** CI's
  parse check already runs it against stand-ins, and its tests are most
  useful run inside hopnbop (RN3 after RN6). Decide RN1 on reuse grounds.
- **Mocking Godot's MultiplayerAPI for peer-level unit tests.**
  Matchmaking found it hard; the declare probe needed only a thin fake,
  and the harness already runs real two-client matches on loopback.
- **A network fixture-replay system.** None exists, and the compliance
  suite plus the harness run the real stack locally in about a minute.
- **Re-architecting the SDK around injected interfaces.** Subclass and
  override seams already work, as every probe in this audit shows.

## 2. Where we left off

Source: h37-history (appendix `h37-history.md`), from the transcripts on
this desktop. Times are UTC.

### 2.1 Recap

- **The last long session** was 530145bc, 10-09 22:03 to 10-12 21:35: 144
  replies, 70 messages from Levi, 21 subagents. Its first reply found the
  party system finished (07-17), the game idle since 08-24, a release
  backlog (live web 0.47.0 against main 0.53.0, protocol 2, Edgegap v28)
  and local main diverged by timestamp-sweep.
- **What it did.** Levi answered "address all" (10-11 17:38) and sent
  game notes, fixed in a1b32155, bbf9694b, 7215b1d5, 28748f60, 10416583
  and eb4da2d3. pr-validate was repaired (13e5cbed, f9f8b38b). Levi
  approved the DR rebuild path ("Do it", 22:52) and a read-only
  Cloudflare token (23:13).
- **Where it stopped.** The release had not started: exported builds
  still shipped the debug values from `settings.tres`. 11 "Needs your
  call" items and about 15 heads-ups were open. Levi then moved to the
  laptop.
- **Since then.** The release is done: 0.54.0 is live (h37-history's GET
  of `hopnbop.net/version.json` at 09:49 PDT; stats-ops saw the same in
  version_check). H4, H14, H16 and H36 were finished on the laptop.
  Laptop transcripts after 10-12 21:22 are not on this machine, so that
  stretch is known only from commits.
- **The testability conversation** was one prompt, at 10-11 23:18:
  could Claude run the game, start a match and use the settings menu,
  and should systems be decoupled to test them? The answer was "yes, I
  can run the game headless or windowed and inject input". What followed
  built the harness v0 (5d913da4), separate preview session ids
  (247be983), the compliance helper (platform 55889b3), the local-smoke
  repair (f8706a76) and `-Backend` (3b7f5743). Four build items were
  never built or ledgered: 5b (a dev stack with the local allocator,
  SP55), 5c (`-AllowMock` on the synthetic probe, CC53), 6 (keep
  game-server logs, SP54, and a read-only SQL wrapper, CC52) and 7
  (golden screenshots, H78). The decoupling question was never answered;
  section 1.3 answers it.
- **Usage.** The 10-12 transcript-audit run hit the weekly limit and left
  no report and no status entry (CC54). Levi lifted the limit for this
  audit at 10:55 PDT on 10-14.

### 2.2 Loose threads

h37-history statused 46 threads: 14 done with a commit, 1 believed done,
1 covered by a release procedure, 22 open with a ledger ID, 8 unledgered.
Its appendix has the full table. Here each open thread points to where
this report picks it up.

| Thread | Status on 10-14 | Picked up in |
|---|---|---|
| Release of the backlog; H4, H14, H16; CC8; SP1; knotmaze push; UptimeRobot GET probe; 10-07 DR gaps A and B; dependency roundup; dead-man timer; cost monitor R2 and Pages; container docs; Edgegap spillover (platform 4668dd4, claude-config b293bec) | Done | - |
| "Watchdog checks dev" | Believed done, no commit found | - |
| Superseded Edgegap versions | Covered by the release procedure (H36) | - |
| H11, CI not run on push | Open, now 25 unchecked commits | 3.5 |
| H15, socket survives log-out | Open, wider (AN-1b) | 3.1, 3.2 |
| H17, declared backend id trusted | Open, Verified by probe | 3.3 (H41) |
| H18 to H22, matchmaking and party UX residuals | Open, all still true | 3.2, 3.3 |
| H3, H5, H6, H7 | Open, outside this audit's domains | 9 |
| H9, formatter skips everything | Open | 3.5 |
| H10 | Half done (4c04e908, f5efb52c) | 5 (T38) |
| H23 to H33, H35 (residuals) | Re-checked where in scope | 3.1 to 3.4 |
| SP2, SP3 (UptimeRobot v2 API, cost monitor GitHub block) | Open | 3.5 |
| SP9, SP10, SP14 to SP19, SP22 to SP25 | Re-checked where in scope | 3.1 to 3.5, section 8 |
| SP12, SP13 (Facebook, provider game_id check) | Waiting on Levi since 10-12 | 3.1, section 7 |
| SP20, SP21 | Open, not re-checked | 9 |
| RN1 to RN3 (netcode standalone, example, tests in no CI) | Open; RN3 now blocked by RN6 | 3.5 |
| CC10, CC31, CC32 | Open; CC31 (old key in the desktop credentials file) unchecked by rule | 9 |
| HG1 (hex-grid) | Open, outside this audit | 9 |
| Org-level `NAKAMA_HTTP_KEY` Actions secret may hold the rotated key | Unledgered, needs admin:org | H79, section 7 |
| Textures orphaned by b998107d | Unledgered | H80 |
| The DR rebuild path was never run for real | Unledgered | SP57 |
| Signed signaling URL in the client log | In the `LEDGERS.md` inbox since 10-13, with a stale line (`:325`, now `game_session_manager.gd:345-353`) | H70 |
| Testability build items 5b, 5c, 6, 7 | Unledgered | SP55, CC53, SP54 and CC52, H78 |
| 10-14 DR drill, a tabletop exercise that scored red | Not a failure (certs green, 45 to 50 days left); its gaps are real | SP56, CC51 |
| Limit-hit jobs leave no record | Unledgered | CC54 |
| Ledger SHAs killed by timestamp-sweep | Unledgered beyond CC34's submodule case | CC34 update, section 8 |

**Dead SHAs.** timestamp-sweep rewrote platform history after 530145bc,
so every platform SHA from that session is unreachable: SP4 to SP8, SP11,
SP17, SP24, and the platform SHAs in H1 and H17. h37-history's "SHA note"
maps each old SHA to its rewritten one; section 8 lists the pointer
updates.

## 3. By domain

Each domain gives the flows its agent walked, the top findings in one
table, test coverage, archived audits, and the verdicts on existing
ledger items. Appendix pointers use short names: `acct`
([h37-account](H37/h37-account.md)), `soc` ([h37-social](H37/h37-social.md)),
`mm` ([h37-matchmaking](H37/h37-matchmaking.md)), `ops`
([h37-stats-ops](H37/h37-stats-ops.md)), `exec-a`
([h37-exec-a](H37/h37-exec-a.md)), `exec-b` ([h37-exec-b](H37/h37-exec-b.md)),
`verify` ([h37-verify](H37/h37-verify.md)), `triage`
([h37-triage](H37/h37-triage.md)), followed by the flow or section heading.
Phase 2 and 2b results (both agents had finished by 11:46) are given
beside the source verdict as `verify item <n>` or `verify2 item <n>`; they
never replace it, and where the two differ both are shown. No finding is
still waiting on verification.

### 3.1 Account

**Flows walked** (acct "Flows"): sign-out (log-out, account deletion,
automatic sign-out); session lifecycle (boot refresh, expiry, backoff,
kept offline); sign-in (anonymous, Google, Facebook, Steam, Apple, Epic)
and its runtime hooks; linking and merge; guests and the upgrade path;
deletion; data export; legal consent and re-consent; display names;
profile images; two devices at once. Runs: a GUT probe against a fake
Nakama (`test_h37_account_probe.gd`, 5 tests, 24 asserts, each asserting
today's buggy behaviour) and exec-b's sign-out, session, export and
consent scenarios.

Solid, per acct: session refresh, backoff and kept-offline boots; consent
retention and re-consent; `legal_version` parity; server-side deletion,
cascade and export; email privacy.

| Finding | Verdict | Pointer | Fix | Size | ID |
|---|---|---|---|---|---|
| **LG-1** (= ops C7). In-game Terms, Privacy and Data Deletion are blank in exported builds: `legal/*.txt` is not a resource and every preset has `include_filter=""`. The consent screen asks players to accept pages it then shows empty. | acct: Broken in the shipped web build (seen in the production web pck by a public GET and in local exports; Windows and Android Believed). ops: Verified (artifact). verify2 item 4: Broken, Verified on all four presets (pack exports of Web, Windows Desktop, Linux Server and Android hold no `legal/` and no `.txt` entry, and each holds the reader); the blank screen in a running export Believed | `export_presets.cfg:10,56,124,167` | `include_filter="legal/*"` on every preset and a CI check that the pck holds `legal/en/privacy.txt`; then LG-2 (CI diff of web vs `legal/en` text) | S | H40 (Urgent proposed) |
| **AN-1.** The guest "upgrade" signs in to the provider's own account instead of linking. The guest's account and stats are abandoned while the panel says "Keep Your Progress", and nothing purges them. | Broken by code. verify2 item 3: Broken, Verified (GUT probe; the account switch Verified, what survives on the old account Believed). Side finding (verify2): a guest who does link keeps `is_anonymous=true` | acct "Anonymous accounts (guests) and the upgrade path" | Link Google onto the guest's device account, then clear `is_anonymous`. When the Google id already owns an account, Nakama answers AlreadyExists (`nakama:core_link.go:361-375`): merge, or tell the player | M | H57; SP23 update |
| **DEL-2.** A failed `delete_account` is reported as a failed sign-in (`auth_completed(false)`); `delete_completed` never fires and the Delete panel stays busy with no message. The notification socket also stops. | Verified by probe (the socket stop: Believed). verify2 item 3: Broken, Verified on both halves: the SDK probe re-run, and a new panel probe (the panel stays busy with Confirm disabled, a retry sends nothing, no error shows). Root cause: `_send_delete_request` clears `_is_deleting` before `_emit_failure` (`sdk:core/auth_api_client.gd:890,896`). The toast and the socket stop: Believed | acct "Account deletion" | Emit `delete_completed(false, ...)` from the failure paths; keep the probe as a test | S | SP41 |
| **SO-1 / H15 + AN-1b.** The matchmaking socket survives log-out and sign-in over a guest; `ensure_socket()` reuses it without checking whose session it carries, so the next account's tickets and party calls go out as the previous one. soc and mm also find H15 still true (sign-out never calls the matchmaker's `cleanup()`). | Client side Verified at unit level by probe, server side Believed. verify item 4d: Broken, Verified end to end (harness plus local stack, 2 runs): after log-out the socket keeps receiving the old account's notifications, and the next player's party is created as the old account. AN-1b proper (sign-in over a guest without a log-out) was not run and stays Believed | acct "Sign-out" | Close the socket in SignOutRouter's shared cleanup and whenever the account changes; assert it in `log-out-sign-in-cycles`; keep the probe as a unit test | S | H15 update |
| **AN-2.** Guests cannot export, delete or forget their server account, though the privacy and deletion texts promise it; the email route needs a player id no screen shows. | Broken by code | acct "Anonymous accounts (guests) and the upgrade path" | Give guests Export, Delete and "forget this device" | M | H58 |
| **PI-2.** Avatars from an earlier match show on the wrong players: the cache is keyed by the per-server player id and keeps entries until sign-out. | Verified at unit level | acct "Profile images" | Key the cache by URL or backend id; drop match entries at match end; add a cache test | S | H61 |
| **PI-1 + DN-2.** Names and avatar URLs are never validated. Every viewer fetches any avatar URL (http, any host, no size limit or timeout), which leaks the viewer's IP and can stall all three download slots. In-match name, avatar and backend id are whatever the client declares. | Cache half Verified at unit level by probe, the rest Believed | acct "Profile images", "Display names and usernames" | Allowlist avatar hosts with a size cap and timeout; a `BeforeUpdateAccount` hook for names; derive in-match identity from the validated session (with H41) | M | H60 (client), SP42 (server) |
| **SI-2 / SP12.** Facebook sign-in and link always fail, yet both panels offer Facebook and the privacy text names it. | Broken by code | acct "Sign-in" | Hide the Facebook rows and privacy lines until the code exchange works | S | SP12 update |
| **DN-1.** The Google profile name, often a real name, is the display name shown to players and on the public leaderboards, against TODO L50; there is no rename. | Decision for Levi (name applied: Verified by `test_auth_api_client_privacy.gd:161`; display: Believed) | acct "Display names and usernames" | Levi decides; if generated names win, a runtime hook after Google auth and link plus a rename screen | M | H59 |
| **LK-1.** A session refresh that lands while a link waits in the browser is reported as the link's success; the refreshed token is dropped and the real code then signs in instead of linking. | Verified by probe, latent | acct "Account linking and merge" | Skip `_check_auto_refresh` while linking, merging or deleting, or give refresh results their own route; keep the probe | S | SP43 |

Lower (acct summary item 11; one line each in section 8): LK-4/LK-2 merge
path dead (H62); TD-1 two devices unhandled (SP69); SI-1 non-crypto device
id, with TS-1 (SP44); SL-1 (SP45); DX-1, an expected export failure that
files a crash report (SP46); DEL-3, sessions not revoked on delete (SP47);
SI-4, SI-6 and SI-3, loopback robustness and a mobile sign-in path (SP48);
AP-1, Log Out without a valid token, with DEL-1 (H63); AN-3 (H64); LG-2 and
an in-session legal re-check (in H40); H22; SI-5 (= SP13).

**Test coverage.** Unit GUT, all passing (exec-a): auth_api_client_privacy
10, auth_api_client_refresh 17, auth_screen_resume 7, auth_file_isolation
2, consent_retention 12, sign_out_router 16, client_http_key 6,
export_data_row 4, player_display 14. The compliance suite (80/80 against
a local Nakama) covers server-side deletion, cascade and export. Harness:
the sign-out, session, export and consent scenarios pass except
`sign-out-local-match` and `sign-out-play-again`, which have failed since
88e3089b raised `match_duration_sec` from 10 to 180 s (copies with 10 s
pass; H69). Not covered: Google and the other OAuth sign-ins (a browser is
needed; `test-google-auth.py` is manual), the guest upgrade (AN-1), a
failed delete (DEL-2), the socket across accounts (SO-1), two devices, and
the sign-out router's party reset and avatar-cache clear
(`sign_out_router.gd:103,111`; H65).

**Archived audits.** The May friends audit's auth section and the
distributed-systems plan's M2, M4 and M16 have per-item verdicts in acct.

**Ledger verdicts** (acct). H15 still true and wider (AN-1b). H18 still
true: exec-b's artifacts show the export toast "Export failed:
HTTPRequest failed! (status=13, grpc=-1)" (`export_data_row.gd:96-99`), and
DEL-2 makes the delete toast unreachable. H22 still true (about 9 s
measured, about 12 s worst). H23 still true; DEL-2 adds a trigger. H32
still true. SP6 done in plat 8b891cd (refresh tests 17/17). SP9, SP12,
SP15, SP16 and SP23 still true. SP13 true for Custom, Game Center and FB
Instant; Email is already refused. SP17 not checkable.

### 3.2 Friends, parties and presence

**Flows walked** (soc F1 to F12): friend codes; requests (send, accept,
decline, cancel, remove); limits and request abuse; block list; presence;
the notification socket and HTTP poll; party create, invite and join;
leave, kick, disband and leadership; party state sync and chat; sign-out,
offline and quit; party matchmaking on the client; the social UI (panels,
toasts, the U/D/L/R contract). Runs: the runtime's `go test`, 26 pass (R1);
a Go probe of `BeforeAddFriends`, 2 pass (R2); 8 social GUT files, 110 pass
(R3); the harness scenario `i18n-party-strings` in lobby mode, 10
screenshots (R4). verify item 3 then ran the invite and start flows on a
local stack.

| Finding | Verdict | Pointer | Fix | Size | ID |
|---|---|---|---|---|---|
| 1. **A party invite is a forced join.** `party_invite` calls `nk.GroupUsersAdd`, which writes state 2 (full member): no consent, friendship, block or rate check, and a player can be in two parties. Each add leaves a persistent notice. There are no group Before* hooks, so the raw API does the same, and the compliance test accepts state 2 or 3. | soc: Believed (Nakama source plus code). verify item 3: Broken, Verified on a local stack (state 2 with no consent; works past a block; two parties at once; a persistent code -4 notice per add) | `rt:party.go:716-732`; `nakama:core_group.go:687` | A stored invitation and an accept RPC; friend, block and rate checks; Before{CreateGroup,AddGroupUsers,JoinGroup} hooks that refuse raw calls on `party-*` groups; fix the stale invite lambda (`party_manager.gd:229-266`) in the same change | M to L (1-2 days) | SP32 (Urgent candidate) |
| 2. **Any member can pull everyone into a match load.** `party_start_matchmaking` has no server-side ready check, and followers run `client_load_game()` after checking only that no game is loading or active. | soc: Believed. verify item 3: the start notice (transient code 100, no consent or ready field) Verified; the client load Believed | `rt:party.go:265-453`; `party_manager.gd:787-846` | Refuse a start unless every active member is ready and recently present; refuse a second start; clear ready on start; followers check the party id and their own readiness | M | SP33 |
| 3. **The creator can't leave while others remain.** Nakama refuses a leave by the last superadmin, a transfer only promotes to admin, nothing disbands a party, and a transferred leader's kick of the creator is a silent no-op. A kick doesn't keep anyone out either: the invite code is reused. | Believed (Nakama source); the kick part Believed. verify item 4a: Broken, Verified (local stack); a transferred leader cannot remove the creator either, and the client reports that no-op as success | `nakama:core_group.go:476-517,1030-1048`; `rt:party.go:2129-2228,2288-2440` | `party_leave` that hands superadmin on (or deletes the party when alone); `party_disband`; demote on transfer; ban or rotate the code on kick. Needs Levi's call on who gets control (TODO L127) | M | SP34 |
| 4. **The notification poll is frozen on the oldest 50 rows.** No cursor, Nakama lists oldest first, nothing deletes rows, and SP14 adds one per match: after about 50 matches, offline friend events never toast, and every launch re-toasts old ones. | Believed. verify item 4b: Broken, Verified (local stack). New: any user can push another past 50 rows in about a second with `party_invite`, so this is also a griefing vector | `friends_notification_poller.gd:149-153`; `nakama:core_notification.go:205-237` | Store `cacheable_cursor`; delete or prune handled rows (also fixes SP14); keep toast dedup across launches; poll only while the socket is down | M | H54, SP40 |
| 5. **One absent member stalls the party.** Membership and ready rows survive sign-out, quit and matches; Start stays disabled, or aborts after 20 s with `members_never_joined`. | Believed. verify item 4c: Broken, Verified (local stack; client screens Believed). A ready absent member leaves Start enabled, and every attempt stalls 20 s and aborts with `members_never_joined` | `sign_out_router.gd:111` | Sign-out leaves the party (needs SP34 for the creator), or the start skips stale members; clear ready at match end | M | H55 |
| 6. **H23, worse than filed.** Any failed auth result stops the notification socket until the next sign-in, and party start is transient-only, so the poll can't cover for it. | Believed | `sdk:notification_socket_client.gd:321-327` | Stop the socket only on a real sign-out; keep reconnecting through a transient refresh failure; add the GUT case from soc F6 | S | H23 update |
| 7. **50 pending outgoing friend requests block every accept.** | Verified (R2) | soc "F3. Limits and request abuse" | Exempt accepts from the cap of 50 | S | SP35 |
| 8. **No rate limit** on friend adds by id, party invites or join-by-code; each writes a persistent row and shows a toast. | Adds: Verified (R2). Invites: Believed | soc "F3. Limits and request abuse" | Limit adds (exempting accepts), invites and joins by code | S | SP35 |
| 9. **Blocking stops friend requests and nothing else.** A blocked user can still add you to a party and read your presence; presence rows are public-read and owner-writable. | Believed | `rt:presence.go:205-215` | Rows with read and write permission 0, served through the RPC; a server-stamped `updated_at`; cap `rich_presence`; drop blocked users | S | SP36 |
| 10. **Raw errors reach players** (H18, H21). The party panel toasts an English "Not authenticated" in every locale; the background poll toasts a raw error every 10 s while the friends panel is open, and re-enables rows in other panels. | H18 reproduced (R4) | `friends_panel.gd:342-354` | Per-operation failure signals in the SDK; map known errors to `tr()` keys; never toast background-poll failures | M | H18 update |
| 12. **Client races.** A follower who started matchmaking can't abort it; two members pressing Start together split the party; `fetch_party_status` replies can apply out of order. | Suspect | soc "F9", "F11" | Single-flight plus a dirty flag; let the starter abort; pair with SP33's double-start refusal | M | H53 |
| 13. **Controller players can't enter codes.** There is no on-screen keyboard; forward rows lack chevrons (two visible in R4); rows aren't mirrored for Arabic; the Join-with-code icon is wrong. | Believed | soc "F12"; `.claude/rules/ui.md:76-83` | A small `MenuRow` grid for the 32-symbol code alphabet; chevrons (XS); RTL mirroring; the icon | M | H56 |

Finding 11 (kick) is folded into row 3. Also: party chat has no
server-side length, rate or block limits (soc F9; SP37). Stale comments
(`rt:friends_limits.go:21-31`, `rt:party.go:231-264`,
`party_manager.gd:615`, the poller's lines 41-43) and dead code (the poll's
party-start route, the `status=="matchmaking"` branch, the "Request in
progress" checks) go with SP37 (platform) and H53 (game). A blocked pair
cancels whole matches and tells every player why through a persistent
`match_failed` (shared with section 3.3; SP14).

**Test coverage.** R3's 8 GUT files (friends_api_client 13,
friends_notification_contract 4, friends_notification_poller 26,
friends_poller_lifecycle 12, party_api_client 11, party_leave_contract 2,
party_manager 31, party_matchmaking_context 11) and the runtime's Go tests
pass. Compliance has 7 presence cases, and its invite test accepts state 2
or 3, so it cannot catch finding 1. Nothing runs two users: harness
clients have no session, so `create_party()` silently does nothing (exec-b
run 5), and only the legacy, non-party matchmaking path has tests.
Proposed seams: a Go fake-`nk` harness for RPC unit tests (SP38, S);
two-user compliance cases for invite state, creator leave, kick then
rejoin, an absent member, accept with 50 pending, 51 notifications and a
non-friend reading presence (SP39, M; all but the first fail today); a
fake `Platform.party` and `Platform.friends` for harness UI scenarios
(H75).

**Archived audits.** The May audit
(`docs/archive/FRIENDS_PARTY_MATCHMAKING_AUDIT.md`): most items resolved;
invite semantics not resolved, and worse than described; polling partial;
the party size of 4 and per-game scoping still open. The
distributed-systems plan's M9 (`docs/archive/DISTRIBUTED_SYSTEMS_PLAN.md`
1380-1430): done on Nakama; only discovery through the sign-in provider is
missing.

**Ledger verdicts** (soc). H18 true (R4). H21 true
(`nakama_matchmaker_client.gd:210-215`). H23 true and worse. SP14 true; it
causes the frozen poll. SP25 true, dormant. H35's file passes 11/11 alone.
H15 Believed true. H22 Believed true (`log_out` awaits `announce_offline`,
`sign_out_router.gd:76`).

### 3.3 Matchmaking, sessions and transport

**Flows walked** (mm F1 to F13): the connection payload and session
validation on the game server; disconnects before and during a match; the
`matchmaker_matched` hook and allocation (Edgegap, local, hybrid); tickets,
cancel and failure; transport and signaling; warm-up and match start;
match end and results; reconnect; game over and Play Again; local and
offline mode; preview; server lifecycle; skill pairing. mm ran Go and GUT
probes without a network; exec-b drove matchmaking end to end on a local
Nakama (exec-b section 4); verify items 0 and 1 sized the port pool and
the client crash.

| Finding | Verdict | Pointer | Fix | Size | ID |
|---|---|---|---|---|---|
| **Clients crash (signal 11) when the server goes away mid-match.** `disconnected` is emitted inside the engine's `peer_disconnected` dispatch; reconnect attempt 1 replaces `multiplayer_peer` there (or `client_exit_match()` closes it), and the engine fails after the handler returns. Triggers: ENet timeout or drop, server crash, container stop. The normal production match end does not crash: `is_match_ended` is already true and the cleanup is deferred. | exec-b: Verified, 4 of 4 runs (8 of 8 clients). verify item 1: Broken. Verified in editor builds; in release builds Verified at engine level by a minimal 4.7.2 repro (the release template crashes on any synchronous peer change in `peer_disconnected`, the editor only on some), not run with the shipped game binary. The pre-match abort path: not run. verify item 4f: the debug template crashes in 0 of 6 cells against 4 of 6 for release, so editor and debug runs hide it. verify: the same family as H25 | `net:core/network_connector.gd:363,293`; `src/core/reconnect_handler.gd:137,193`; `game_panel.gd:527-556,1275-1281`; verify "1." | Defer both peer changes (reconnect attempt 1 and `client_exit_match()`) with `call_deferred`, as `_client_transition_to_game_over` does (`game_panel.gd:1443-1464`); add a scenario that kills the server mid-match; check the fix on a release template | S | H38 (supersedes H25) |
| **Local port pool leak.** `LocalDockerAllocator.Stop` never releases its UDP/TCP pair (its comment admits it). Production runs hybrid, every NA match goes local, and a local failure has no Edgegap fallback, so after 100 local matches since a Nakama restart every NA match fails. | mm: Broken, Verified by a Go probe (100 cycles succeed, allocation 101 fails). verify item 0: Broken, latent: about 1 to 3 of 100 pairs used since the 10-13 restart; with no real players, exhaustion comes about 16 to 17 weeks after a restart (the synthetic probe alone used 70 in 85 days) | `rt:local_allocator.go:323-346`; `rt:fleet_allocator.go:1004-1017`; `game.yaml:73`; `plat:scripts/lib/nakama-env.ps1:89-90` | Keep `requestID -> (udp, tcp)` and release it in `Stop`; reconcile with running `match-local-*` containers before reporting exhaustion; land the probe as `local_allocator_test.go`. Detection today: the synthetic probe goes red with `allocation_failed`; players see LOADING.ALLOCATION_FAILED (`game_panel.gd:746-751`) | S | SP26 (Next) |
| **Session validation is not enforced on the game server.** G1.1: the provider's rejection is only a signal; the connector still sends ids and emits `peer_players_declared`. G1.2: session ids are `<userid>_<n>`, so guessable. G1.3: a second peer presenting a claimed session id gets the same player id and takes over the peer mapping. | Broken. G1.1 and G1.3 Verified by a GUT probe; G1.2 Believed. verify2 item 1: G1.2 Broken, Verified (Go and GUT probes): any member of a matched set can compute every other member's session id and claim it first | `net:core/network_connector.gd:602-642`; mm "F1" | Order matters (verify2 item 1): G1.1 alone would kick the owner and keep the thief. First SP70 (below) and SP27: the runtime mints random per-slot tokens, sends each user only their own, and gives the server a token-to-user-id map in place of `EXPECTED_SESSION_IDS`; the server derives `backend_player_id` from it (closes H17; a per-match secret also closes SP18). Then H41: the provider returns a result, the connector disconnects before assigning or sending ids, and only the same account may re-claim a token, after its earlier peer dropped (G1.3) | M | H41 (G1.1, G1.3), SP27 (G1.2), H17 update |
| **No match forms for anyone while an allocation runs.** Nakama waits for every `matchmaker_matched` hook, and the hook allocates synchronously, up to 3 attempts. | Believed (Nakama 3.25 source). verify2 item 2: Broken, Verified (Nakama 3.25.0's real matchmaker in a Go test) | mm "F3" | Return from the hook at once and allocate in a goroutine; the inflight registry and cancel path already exist | M | SP30 |
| **One player's 120 s SDK timeout cancels the whole matched set's allocation.** The timer runs from ticket creation and nothing marks an "allocating" phase. | Broken: both halves Verified (GUT probe; the runtime's `TestCancelInflightForUser`), the combination Believed. verify2 item 2: Broken, Verified (each link by a run, and the links meet) | mm "F3", "F4" | The runtime sends "allocating" at hook start and the SDK stops its timer; the SDK sends `cancel_matchmaking_allocation` only on an explicit Cancel (verify2). Cosmetic: the player who cancels is also told "Match cancelled by another player" | S | SP29 |
| **Ghost ticket.** A Cancel during `start_matchmaking`'s awaits leaves the client searching; the next Play is refused, and a match can start from the lobby. A socket close while searching only prints, and match_ready / match_failed carry no correlation id. | Broken: the SDK half Verified by a GUT probe, the game half Believed; the socket-close handler Verified | mm "F4" | A search generation counter that cancel bumps and start re-checks after each await; a correlation id on tickets and pushes; handle a socket close like the error path | S | SP28 |
| **Reconnect stale-peer race** (F8). When a known sid re-declares from a new peer, the old peer's later disconnect can despawn or demote the reconnected player. | First step Verified by the G1.3 probe; the old peer's later disconnect Suspect | mm "F8" | Disconnect the old peer first; despawn by player ownership, not by peer; a unit test with the probe's fake multiplayer API. After H38, best with H41 | S | H43 |
| **G2.1.** A disconnected leader keeps the win on a normal match end; demotion runs only on the forfeit path. | Suspect, high confidence | mm "F2" | Call `server_demote_disconnected_players()` on a normal end when anyone is disconnected; a row-assembly unit test | S | H42 |
| **H17.** The server stores whatever backend id the client declares. | The trust: Verified by probe. The merged result rows: Believed | mm "F1" | Derive the id from the validated session (H41) | (in H41) | H17 update |
| **Play Again splits a party** (each member files a solo ticket); there is no rematch. | Suspect (UX) | mm "F9" | A member's Play Again routes to the leader, who files a party ticket; a rematch vote is L | M | H44 |
| **Self-quit.** The server quits 12 s after all clients drop, inside the 30 s reconnect window, and sends no `match_cancel` (G2.2, G2.3, G12.1). Pairs with ops RT1: rows of matches that never ended stay forever. | mm: Believed. verify item 4e: Broken, low-medium, Verified in two halves (harness and local stack): neither `match_end` nor `match_cancel` reaches the runtime and the match rows stay; the Edgegap restart path Believed | mm "F12"; verify "4e"; `game_session_manager.gd:541-569` | Call `G.match_result_reporter.cancel(request_id, "all_clients_dropped")` before the quit, and quit after the reconnect grace rather than at 12 s | S | H45 |
| **Match rows are listable by any signed-in player** (verify 4e). `match_metadata` (the match's user ids) and `server_registrations` (server IP, port, FQDN) are written with read permission 2, so any signed-in player can list them. With SP27 and H41 this is the takeover chain in 0.1. | verify item 4e: Broken, Verified on the local stack; production not checked (it needs a production sign-in; section 7) | `rt:fleet_allocator.go:1149,1174`; `rt:match_lifecycle.go:177`; verify "4e" | Write `match_metadata`, `server_registrations` and `synthetic_matches` with PermissionRead 0 | S | SP70 |
| **A cancel without a registration is a no-op** (verify 4e). `match_cancel` for a match whose server never registered answers `noop` and leaves `match_metadata`. Test matches leave rows too, although two compliance tests say deleting the users cleans them. | verify item 4e: Verified (the dev stack's server key); the test comments: Believed (code) | `rt:match_lifecycle.go:694-711`; `sdk:test/compliance/test_party_to_matchmaking.gd:65-67`, `test_friends_block.gd:77-79` | Delete `match_metadata` on cancel even with no registration; RT1's sweep (SP58) for the rest; fix the comments | XS to S | SP71 |
| **Networked pause ships enabled.** Escape (and two gamepad buttons) sends a pause request with no `is_debug` gate; `settings.tres` turns pause on and the release overrides leave it on. One player froze the server and the other client for 7 s, and the other client could not unpause. | triage T107: Believed. exec-b run 7: Verified on the editor (debug) path. verify item 2: Believed for release builds, not run. verify item 4f: still not run, since no exported binary can be sandboxed with the shipped 4.7.2 templates (Verified); the pause path has no debug gate, so a debug export would behave the same (Believed, code) | `settings.tres:154`; `input_handler.gd:126-138`; `settings.gd:358-389`; `net:core/frame_driver.gd:449-471` | Levi's call (section 7): disable in `_apply_release_values`, or gate it | XS once decided | H39 |
| **H26 reaches players.** In a second match on a preview server neither client gets a bunny; each logs about 400 "Ignoring sync data" lines. A production server quits after one match, so this blocks dev and harness play-again tests only. | Verified (exec-b run 2); the production scope Believed | exec-b "4."; `game_session_manager.gd:554-569` | As H26 | (H26) | H26 update |

Smaller, one line each in section 8: `game.yaml` `matchmaker_rules` fields
nothing reads (`ticket_expiry_seconds`, `cross_play`, `rules`; the
same-device preference its comment claims doesn't exist; H52); couch co-op
totals uncapped, up to 16 bunnies in a 4-user match (SP31); the 10 s server
grace may be too short for WebRTC signaling (H48); transport.md drift: the
retry count, port 4433 vs the real 4434/TCP, a GameLift fleet paragraph
(H47); `level_id` always empty in `match_stats`
(`edgegap_server_provider.gd:266-270`, = ops S3; H49);
`test_network_connector.gd` crashed on exit in 1 of 3 runs (H46); the
warm-up stubs (`backend_api_client.gd:7-122`, `loading_screen.gd:115-135`;
H50); no connecting or waiting phase on the loading screen (H51); a refused
pause logs a format-string ERROR (`game_panel.gd:1854`, 1840-1842; H66);
pause stats always read 0 frames (`net:core/frame_driver.gd:711-712`; RN8).

**Test coverage.** GUT: nakama_matchmaker_client 28,
matchmaking_session_failures 11, disconnect_handling 9, network_connector
8, preview_session_provider 5, party_matchmaking_context 11; integration
lobby_to_networked_transition 8, multi_player_declaration 6,
pause_synchronization 4, webrtc_connection 5 and ten multiplayer files;
netcode 208 of 211 (RN6). The runtime tests allocation backoff, fallback
geographies and `TestCancelInflightForUser`. The harness's `match-2-clients`
passes, but it connects directly; no committed scenario goes through Nakama
matchmaking (exec-b's `h37-mm-*` runs did, on its own stack script; H74,
SP55). Not covered: a real allocation (the dev stack has only the mock),
WebRTC and the web build, more than 2 clients, exported builds (H72), the
pre-match abort, reconnect. mm's probes (`h37_local_port_leak_test.go`,
`test_h37_ghost_ticket.gd` 4/4, `test_h37_declare_validation.gd` 4/4,
`offline-play-again.json`) become regression tests with their fixes (H77).

**Archived audits** (mm). The May audit: resolved are the party queue
(realtime-party tickets), per-game `matchmaker_rules` (three documented
fields inert), the protocol check, per-game leaderboards, the block list in
matching (it fails open on a FriendsList error), allocation retry and
alternate region, the match-found push, and mid-queue cancel (which
introduced the shared-timeout cancel above). Mostly resolved: the queue UI
(no connecting phase, accept or ETA; H19). Open: skill brackets and
relaxation, backfill, a region picker (not needed while NA goes local), an
ENet fallback when cross-play ICE fails, the same account on two devices.
The distributed-systems plan: M6's Play Again vote, group re-queue and
progressive relaxation were not built (`game.yaml` claims relaxation); M10
is ENet and WebRTC plus the signaling proxy (native WSS unverified); M11 is
implemented.

**Ledger verdicts** (mm, exec-b, verify). Still true: H15, H19, H21, H24
(low), SP9, SP14, SP18, SP19. H17 still true (probe). H20 still true; fix
`copy_latest_state` at `game_panel.gd:673` and `779`, as at 694. H25: mm did
not reproduce it; verify finds it is H38's crash, mis-described, so H25
closes as superseded. H26: reaches the players (above). H27 Verified still
present; fix with an `is_local_mode` guard at
`net:core/frame_synchronizer.gd:120` and by skipping the local peer at
`src/level/networked_level.gd:307`, and commit `offline-play-again` as a
scenario that asserts zero errors.

### 3.4 Stats, leaderboards, settings and crash reporting

**Flows walked** (ops sections 1 to 5): per-player match stats (record,
post, dedup); leaderboards (writes, partitions, the public route, the
in-game screen, My Stats) and the live public board; settings (menu,
`local_settings`, level prefs, `device_config`, release overrides);
per-game config and versions; crash reporting (client queue, redaction,
the runtime RPC, retention). Runs: runtime Go 98 tests pass, vet clean;
GUT 106/106 in 8 files; one GUT probe for ST1; production got
unauthenticated GETs only.

Checked and fine (ops): the board is authoritative, so clients cannot post
scores (`rt:leaderboards.go:176-177`); the public route returns only rank,
display name and score (`rt:leaderboard_public.go:117-119`, Go tests, a
live GET); a forged match_end is refused and synthetic matches write
nothing (`rt:match_lifecycle.go:394`); `register_game` needs the admin key
and rejects bad boards before upserting; the live `version_check` equals
the repo (0.54.0, protocol 2, legal 1.2); CORS on the public routes; the
client crash queue, redaction and caps (53 GUT tests) and the runtime
limiter, prune and redaction (Go tests).

| Finding | Verdict | Pointer | Fix | Size | ID |
|---|---|---|---|---|---|
| **ST1. Settings revert two launches after a change**, for every player with a session, guests included: gore, critters, cheats, full screen, mute, offline mode. The cloud echo of the device's own save is re-applied because sync-at never advances, and `set_override` then erases each key because it compares against the live value, not the default (exec-b's `set_override` note). | Verified (probe: its two echo assertions fail as predicted) | `src/core/settings_cloud_sync.gd:33-42,90-93`; `src/core/local_settings.gd:136-143,187` | Compare against `Settings.new()` defaults; advance sync-at on a successful save; promote `test_probe_settings_echo.gd` (artifact) into `test/unit/` | S | H67 |
| **C7** is LG-1 (section 3.1). | Verified (artifact). verify2 item 4: Broken, Verified on all four presets | `export_presets.cfg:10,56,124,167` | See H40 | S | H40 |
| **CR6.** Script and engine errors that do not crash are never reported: only `G.log.error` feeds the reporter, and nothing calls `OS.add_logger`. V17's broken format strings are such errors. | Believed (grep), medium | ops "5." | An engine `Logger` that forwards errors to the reporter on the main thread and skips exit-time leak lines (H28) | S to M | H86 |
| **CR1, CR7.** CR1: a dedicated server's fatal error or engine crash is never reported (its queue dies with the container). CR7: web and Android engine crashes are never found (no log file). | CR1: Suspect (Believed mechanism), medium. CR7: Believed, low-medium | ops "5." | CR1: flush synchronously on the server role before a fatal quit, and record abnormal container exits. CR7: a JS error hook on web, a signal on Android | M | H87 |
| **S1 + OP2. match_end is not atomic**: a failed leaderboard or history write is logged at Warn and lost, and no monitor exercises match_end, the board, history or the public route. The production board had 0 records at the 10-14 backup; ops infers no real matches yet (OP3), and a match_end fault is not ruled out without the Nakama log. | medium (inferred cause; S1 not ruled out) | `rt:match_lifecycle.go:538-541,563-565` | Return a retryable error and keep the registration (the writes are idempotent); an hourly sweep of stale per-match rows that reports a "never ended" count (RT1); a probe variant that ends a match and reads the board | M | SP58 |
| **L2.** The public read scans 5 pages of 100 and guests are recorded on the board, so hidden records can starve the list; players below the scan get "-" for rank in My Stats. | Verified mechanism, Suspect consequence | ops "2." | Don't record guests, or keep a listable-only board | S to M | SP60 |
| **C1 + C2.** Legal parity is checked only by pr-validate, which never runs on push (H11), and `sync-game-config.ps1` publishes whatever `legal_version` `game.yaml` holds. | Suspect | ops "4." | Legal guards in the sync script; `push: main` on pr-validate | S | H68 (C2), H11 update (C1) |
| **S11.** The final match stats ride one unreliable RPC. | lower | `game_panel.gd:2165-2168`; `match_state_synchronizer.gd:387` | Send the final snapshot reliably | S | H89 |
| **ST2, ST3.** Failed cloud saves are dropped (`_on_request_failed` only clears pending fetches); the settings blob is last-writer-wins as a whole. | ST2 Believed, low-medium | ops "3." | Retry or surface failed saves; merge per key | M | H90 |
| **C3, C4, C5.** C3: `edgegap_app_version` is not in the sync's mustSurvive list. C4: unknown config keys are ignored. C5: doc drift. | lower; C5 trivial | `scripts/sync-game-config.ps1:148`; `rt:per_game_config.go:30-31,139-141` | Add to mustSurvive; warn on unknown keys; fix the comments | XS to S | H68 (C3), SP62 (C4, C5) |
| **CR4.** The 500 per day global crash cap starves servers. | lower | ops "5." | A separate server budget | S | SP61 |
| **ST5 = triage V27.** CLAUDE.md "Configuration" names `perf_tracker_enabled` and `debug_console_enabled`; the fields are `show_debug_console` and `show_perf_tracker`, and `dev_mode` is read nowhere. The debug toggles can't be reached in release builds (good). | Believed | `src/config/settings.gd:59,65-67` | Fix the names; drop `dev_mode` | XS | H85 |

Also lower: S3 is mm's empty `level_id` (H49); L3 is SP16 (a deleted
player stays listed for up to about 2 min); RT2 is SP14 (notification rows
grew from 476 to 508 in a week).

**Test coverage.** GUT 106/106 (ops, exec-a): leaderboard_data 13,
leaderboard_screen 8, my_stats_screen 5, crash_report_text 24,
crash_reporter 29, settings_release_values 2, device_config 9,
settings_cloud_sync 16. exec-b drove the settings menu by keys (77/77) and
saw changes survive one relaunch (27/27); ST1 bites at the second launch,
which no scenario covers. `leaderboard-local-backend` fails because nothing
seeds scores (H74). Not covered: the cloud echo (probe only), match_end
failure paths, `validateGameConfig`, `abortProtocolMismatch` and
account_cron (all SP63), an export's legal files (H40).

**Ledger verdicts** (ops). H11 open (C1). H28 not reproduced; it can't
reach crash reports today, and CR6's fix must skip exit-time leak lines.
H29 and H32 still true. H31 still true with a changed label set
(`credits_screen.tscn:40,55,70,85,114`). H33 not implemented. SP2 true
(`plat:scripts/phase-b.ps1:373-416`); SP3 Believed true (the host `.env`
unchecked); SP14 true; SP16 true; SP22 still true; SP23 true
(`plat:scripts/phase-a.ps1:1170`); SP24 true (`rt:player_data.go:42-50,200`).

### 3.5 Operations, CI and disaster recovery

**Flows walked**: ops sections 6 to 8 (which monitor notices a
regression; retention and cleanup crons; rate limiting and CORS); exec-a's
CI audit and full local runs; history's job trail and the 10-14 DR drill.
Local runs (exec-a): GUT unit 492/492 in 45 files, integration 135/135 in
16, netcode 208/211 in 9; compliance 80/80 in 79 s; runtime Go vet clean,
181 tests and 225 subtests, staticcheck clean. Section 1.1 has the CI
table.

**The 10-14 DR drill was a tabletop exercise, not an outage.** Its
scenario was "Caddy's Let's Encrypt renewal fails for 14 days"; it scored
RTO 2.5 h to 36 h and listed 16 gaps. The real certificates are fine:
cert-expiry ran at 05:43 PT on 10-14, and all three production certs are
green with 45 to 50 days left. The drill's gaps are still real proposals;
the first is G1, nothing pages while renewal fails.

| Finding | Verdict | Pointer | Fix | Size | ID |
|---|---|---|---|---|---|
| **H11, wider.** PR Validate and Compliance Matrix have only ever run by manual dispatch; 25 commits on main (`3b7f5743..9bbaa7ee`) were never checked by CI, the 0.54.0 release (`8ca156e7`) among them. exec-a's local runs cover all 25 and pass. | Still true (exec-a: `on:` blocks and run history) | `.github/workflows/pr-validate.yml`, `compliance-matrix.yml` | `push: main` triggers, or a nightly run | XS | H11 update |
| **RN6.** Netcode `test_webrtc_signaling.gd` fails 3 of 12 on every run: two tests trip GUT's engine-error check through `JSON.parse_string`; one reads hopnbop's live 30 Hz send rate instead of the addon default of 20. No CI runs these tests (RN3), and they would turn RN3's step red. | Verified (two runs); causes inferred | `net:test/unit/test_webrtc_signaling.gd:154,164,242`; `net:core/webrtc_signaling_server.gd:600` | `JSON.new().parse()` or `assert_engine_error`; assert against `NetworkSettings.new()` | S | RN6 |
| **Client SDK CI runs no tests**: 63 green runs, zero tests. The SDK is tested only when someone dispatches hopnbop's Compliance Matrix. | Verified (exec-a) | `plat:.github/workflows/client-sdk-ci.yml` | Run the compliance suite there, or rename the job | S | SP50 |
| **`release.yml` has never run**, and there is no `v*` tag; the tag row of CLAUDE.md's deploy table is unexercised. | Verified (exec-a) | `.github/workflows/release.yml` | Exercise it once, or mark it unused | S | H83 |
| **`local-smoke-test.ps1` rewrites the checkout it runs in** (deletes and re-copies the SDK addon, re-imports); its "several runs at once" holds only with one run per worktree. | Verified (exec-a) | `scripts/local-smoke-test.ps1` | Fix the header, or stage into a temp project | S | H81 |
| **gofmt and docs.** SP10's unformatted set is now friends_limits, helpers_test, local_allocator, main and party; no workflow runs gofmt. The platform CLAUDE.md says there are no per-package tests (there are 181) and that a workflow runs gofmt (none does). | Verified (exec-a, ops) | `plat:CLAUDE.md` | gofmt in CI plus `*.go eol=lf`; fix the two CLAUDE.md claims and the dead plan path (triage) | S | SP10 update, SP53 |
| **`staticcheck@latest` is unpinned** in the runtime deploy gate and in pr-validate. | Verified (exec-a) | `plat:.github/workflows/nakama-runtime.yml:44`; `.github/workflows/pr-validate.yml:305` | Pin a version | XS | SP51, H82 |
| **OP1.** caddy-access-analytics has reported nothing real since at least 10-01 (`jq -c` where it needs `-r`), so 429s and 5xx go unwatched. | Verified | claude-config `jobs/scripts/caddy-access-analytics.ps1:46-48` | `jq -r`; fix the stale comment | XS | CC55 |
| **OP3.** player-metrics' DAU equals the nightly smoke runs: each run leaves a new account. Same class as SP23. | Verified | `.github/workflows/nightly-smoke.yml:39,51` | Reuse one fixed `probe-` device id, or delete the account at the end; exclude probe accounts from metrics | S | H88, CC56 |
| **OP6.** Grafana watches only infrastructure: no rules for Caddy 5xx or 429 rates or Nakama RPC errors, though Prometheus already scrapes them. | low-medium | ops "6." | Add the three rules | S | SP65 |
| **RL3.** Any authenticated session can write unbounded storage; filling the one host's disk takes everything down. | Suspect, medium-low | ops "8." | A `BeforeWriteStorageObjects` allowlist with a size cap, and a per-IP Caddy zone on `/v2/storage` and `/v2/rpc` | M | SP59 |
| **RL5, RL6.** Nothing validates the Caddyfile before deploy or reloads it on deploy, and the Caddy build is unpinned. | RL5 Believed, low | ops "8." | `caddy validate` in CI, reload on deploy, pin the build; a dev-stack Caddy so local-smoke can assert 429s, CORS and log masking | S (M with the dev Caddy) | SP64 |
| **RT3, RT4, OP4, OP7.** RT3: disk is the only backstop for three unbounded stores (game-server images, container logs, per-match rows). RT4: account_cron has no test. OP4: prod-health-check's Postgres error count is small but not zero (1, 2, 1 on 10-07, 10-12, 10-14), and its source needs SSH. OP7: `get_match_history` reads every history row of the caller on each call. | RT3 Believed, low; OP4 Observed, low; OP7 Believed, low | ops "6.", "7." | Pruning; a test; read the Postgres log; paginate | S each | SP67, SP63, SP66, SP68 |
| **DR drill gaps** (tabletop, above). G1: nothing pages while renewal fails; cert-expiry only writes a status entry. 15 more gaps in the drill report. The DR rebuild path (built 10-11) has never been run for real; SP7 only compared the `.env` against production's 27 values. | Tabletop result; certs green | history "Loose threads" | Page on renewal failure; work the gap list; one real rebuild | S; M; M | CC51, SP56, SP57 |
| **A signed signaling URL is logged**: a 5-minute match token. The 10-13 `LEDGERS.md` inbox entry points at the old line 325. | Read in code (history) | `src/core/game_session_manager.gd:345-353` | Log the host only, or strip the query | XS | H70 |
| **Rotated key, possibly stored twice.** CC31 is open (the desktop's credentials file still holds the old key); the org-level `NAKAMA_HTTP_KEY` Actions secret is unchecked (needs admin:org) and in no ledger. | From the ledger; not checked | history | Levi checks the org secret | XS | H79, CC31 |
| **Jobs that hit the weekly usage limit leave no record**: the 10-12 transcript-audit run left no report and no status entry. | Seen in the status trail and that run's transcript | history | Write a status entry when a run hits the limit | S | CC54 |
| **Ops tooling for audits.** `Invoke-RemoteSql` defaults to the nakama user with no read-only guard; the synthetic probe fails any mock-mode match, so it can't run against a local stack; `AutoRemove: true` discards game-server container logs. | Read in code (history) | claude-config `jobs/scripts/_lib/Invoke-RemoteSql.ps1:34`, `jobs/scripts/_synthetic-match-probe-bin/probe.go:203-211`; `rt:local_allocator.go:219` | A read-only guard; `-AllowMock`; keep the logs | S each | CC52, CC53, SP54 |

Also: signaling-proxy and geoip-sidecar have no tests (vet clean; SP52); H9
still true, the formatter job is green but skips everything ("gdscript_formatter
not vendored; skipping"); test fixtures log "no animation 'Rest'" 37 times
per run (H84); `gh` still lists two workflows whose files are gone.

**Ledger verdicts** (exec-a, history, ops). H9 still true. H11 still true,
now 25 commits. H35 passes 11/11 per file (the directory case not rerun).
SP10 still true with a new file set. RN3 still true, and RN6 must land
first. CC31 open. CC34 covers only submodule pins; extend it to ledger and
doc SHAs.

## 4. Testability roadmap

Section 1.3 ranks the seams by value for cost. This section orders the
work, and names for each step the findings of this audit it would have
caught. Steps 1 and 2 are cheap and come first because every later test
is wasted while CI never runs on main.

| Step | Work | Would have caught | Size | IDs |
|---|---|---|---|---|
| 1. CI that runs | `push: main` triggers (or a nightly run) on PR Validate and Compliance Matrix; fix the 3 netcode test failures, then run the netcode tests in CI; run the compliance suite in the platform's Client SDK CI; vendor the formatter or delete its job; pin staticcheck; gofmt in CI with `*.go eol=lf` | 25 unchecked commits on main, the 0.54.0 release among them; the netcode failures; SP10's unformatted files | XS to S each | H11, RN6, RN3, SP50, H9, H82, SP51, SP53 |
| 2. Land the H37 probes as tests | Each probe moves into the suite that owns its code in the same commit as its fix, flipped to assert the fixed behaviour: the account probe (LK-1, DEL-2, PI-1, PI-2, SO-1), the ghost-ticket and declare-validation probes, the port-leak Go test, the social Go probe, the settings-echo probe, exec-b's 8 scenarios and verify's 2 scenarios. Fix the two failing sign-out scenarios so the committed suite is green again | ST1, the port leak, G1.1 and G1.3, the ghost ticket, DEL-2, LK-1, the forced join | XS each | H77, H69, and each fix's own ID |
| 3. A local backend Claude can bring up alone | `scripts/dev-stack.ps1` from exec-b's `stack.ps1`, with seed and restart steps; no `-AllowNetwork` for loopback, no 30 s client 2 delay; then the dev stack with the local allocator; then harness sign-in plus `publish` and `wait_shared` steps for parties | `leaderboard-local-backend`; matchmade runs without hand setup; the port leak end to end; parties end to end (SP34, H54, H55, H15) | S, then M, then M | H74, H73, SP55, H75 |
| 4. Exported-build runs | The shipped 4.7.2 templates refuse `--path`, `--main-pack` and `-s` (verify item 4f). First choice: a 4.7.2 template built with `disable_path_overrides=no` (debug for pause, release for crashes), driven by `run-game.ps1 -Godot <its console exe>` under the full driver sandbox; plus a published-mode recipe (windowed clients, the local matchmaker, a server on the mock-deploy port). An agent export preset touches shipped code, so it comes last | The client crash (H38) in a shipped build; LG-1's missing legal files; release-only settings such as pause and the debug toggles | M | H72, H40 |
| 5. Multi-user backend tests | Go fake-`nk` harness for runtime hooks; two- and three-user compliance cases | Forced join (SP32), start checks (SP33), leadership (SP34), rate limits (SP35), block scope (SP36), notification fan-out | S to M | SP38, SP39 |
| 6. Narrow seams | Pure functions for server-side match decisions; provider grace and idle timers with a stubbed HTTP layer; the signaling-proxy token table; the transport classifier table; runtime tests for match_end failure, `validateGameConfig`, `abortProtocolMismatch` and account_cron; `-AllowMock` on the synthetic probe | G2.1 (H42), the self-quit (H45), the grace window (H48), S1 (SP58), C4 (SP62) | S each | H42, H45, H48, SP63, CC53 |
| 7. Later | More than 2 clients and gamepad input in the harness; golden screenshots | 3 and 4 player HUD and spawns; controller navigation (T45); layout regressions (T19, T29) | M to L | H76, H78 |

Checks that are not tests but belong in the same pipeline: the V17
format-string scanner in pr-validate (H66), a check that the exported pck
holds `legal/` (H40), and the legal-version guards in
`sync-game-config.ps1` (H68).

What stays manual: OAuth sign-ins (a browser and production), web and
WebRTC play in a real browser, controller feel, art and audio by eye, and
the 2-client networked look at the 10-11 fixes (H92). Production checks
stay read-only.

## 5. TODO-scratch triage

h37-triage dated and checked all 112 notes in `TODO-scratch.md` (moved
out of `net:core/frame_driver.gd` in 407c6abd; numbered T01 to T112 in
file order). The full table is in the triage appendix, "Item table".

| Verdict | Count | Notes |
|---|---|---|
| Done | 21 | T02-T07 (the 10-11 fixes, below), T46, T56, T68, T69, T83, T85, T88-T90, T93-T98 |
| Verified working, partial coverage | 2 | T08, T09 (one keyboard player) |
| Believed Done, needs a look | 1 | T27 (bbf9694b) |
| Partly Done | 12 | T12, T43, T48, T54, T59, T63, T74, T92, T99, T100, T102, T110 |
| Stale | 9 | T47, T49, T52, T53, T57, T60, T62, T67, T87 |
| Reference | 7 | T01, T18, T51, T58, T64, T82, T112 |
| Idea | 13 | T50, T71-T73, T76, T80, T81, T86, T91, T106, T108, T109, T111 |
| Open, verify first | 5 | T16, T19, T25, T29, T45 |
| Open | 21 | T10, T11, T14, T15, T28, T37-T39, T41, T42, T61, T70, T75, T77-T79, T84, T101, T104, T105, T107 |
| Routed to the domain agents | 21 | Table at the end of this section |

**The six "fresh" notes are not regressions.** Levi pasted them into
session 530145bc on 10-11, and that session fixed all six the same day; a
Claude session committed the notes verbatim to netcode on 10-14
(6022552), which is why blame dates them 10-14. Fixes: crown recolor
a1b32155; death blink at the origin 7215b1d5 and 10416583; water respawn
splash 28748f60; resting bunny on the player card eb4da2d3; springs while
invincible bbf9694b; Godot 4.7.2 ee491657. None was tested in a networked
match, and neither were T16, T25, T27 and T29. Related residuals stay
open: H3, H6, H7, H8.

**Proposed order** (triage's, with the item that carries each step):

| # | Notes | Work | Size | ID |
|---|---|---|---|---|
| 1 | T107 | Decide networked pause (section 3.3) | S | H39 |
| 2 | V17 | Parenthesize the 22 broken format strings (17 hopnbop, 4 netcode, 1 platform) and run the scanner in pr-validate. exec-b's `game_panel.gd:1854` is not in V17's list, so the scanner misses at least one pattern | S to M | H66, RN7, SP49 |
| 3 | T02-T07, T16, T25, T27, T29 | One 2-client networked session with Levi; file what reproduces | S | H92 |
| 4 | T29 | Overhead label offset: fix what step 3 reproduces (offline shows none, V26); remove the diagnostic and its broken format string either way | S to M | H93 |
| 5 | T79 | A short input grace on the game-over screen and a stop to the reconnect loop at match end (V25, Believed, `game_panel.gd:538,574`); reproduce on web; delete the 24 `FIXME(end-of-match-debug)` breadcrumbs | M | H91 |
| 6 | T45, T08, T09 | A controller pass by hand, with two local players and an offline replay | S | H94 |
| 7 | T42 | A click sound on every MenuRow trigger, once in the shared dispatch (13 of 16 subclasses play nothing) | S | H95 |
| 8 | T10 | Alt+Enter full screen in hopnbop, scaffolder and bootstrapper | S | H96 |
| 9 | T41 | Let the snore finish on the splash (a 0.92 s clip on a 0.9 s splash); decide the web autoplay case | S | H95 |
| 10 | T12, Stale | Drop the dead plan path from the platform CLAUDE.md, archive `MULTI_GAME_ROADMAP.md`, delete the Done and Stale notes | S | H97, SP53 |
| 11 | V15 | Keep stray images out of exports; delete the 3 orphan `level_4_combined*.png.import` files | S | H80 |
| 12 | T43, T19 | A polish pass by eye (with H18, H31); the PlayerDisplay list at several window sizes with 4 players (V28: it covers the playfield with one) | M | H98 |
| 13 | T48 | Automate the rest of the release checklist (RPC channels, logging guards) next to the V17 scan | M | H99 |
| 14 | T84 | Add the two fly buzz `.ogg` files the code already loads (they never existed) | S once the audio exists | H95 |
| 15 | T15, T28, T14 | Level art: level_0 first, then level_4 and level_5 | L each | H100 |

**Quick wins** (no decision needed): V17, T42, T41, T10, T12 with the
stale notes, V15. T107 is one line once Levi decides.

**Stale notes and their replacements.** T47, T49, T52, T53, T57, T60,
T62, T67 and T87 describe the AWS and GameLift era or are superseded.
Their replacements are Hetzner plus Edgegap, the cost monitor in
`.claude/rules/deploy.md`, `NAKAMA_HTTP_KEY` on dedicated servers only,
and `release.yml`. Delete them with the 21 Done notes (H97).

**Notes that need Levi's intent:** T11 (a gore "rainbow": no rainbow
transition exists in code); T14 (what the foobar image is for:
`foobar.png` is unreferenced and ships in builds); T31 (the friends-panel
note is an empty bullet; section 3.2's rows may be what it meant).

**Next tier** (P3, small to medium; filed only if Levi wants them): T70
slimmer debug annotations, T78 ScaffolderTime (RN2), T55 OAuth consent
screen links (needs console access), T61 localized tooltips (social adds
a hover-versus-focus question), T77 web loading art, T99 the game-over
overlay in the lobby, T59 Inner-Tube Climber.

**Held back until the rest is polished:** T37 Steam and Epic, T38 and
T102 mobile touch (H10), T39 iOS, T74 and T75 bespoke art per level, T76
animated tiles, T100 follow camera and split screen, T108 sudden death,
T109 easter eggs, T111 holidays, T91 rollback debug UI, T72 level editor,
T73 cloud levels, T86 AssetLibrary, T104 netcode decoupling (RN1).

**Notes already in a ledger:** H3, H6, H7, H8 (residuals of the 10-11
fixes); H5 (T54's podium); H18 and H31 (T43); H10 (T38, T102); H9 (T101);
RN2 (T78, T105); RN1 (T104 and the rest of T12); H27 (T08's log noise).

**Correction to T17.** Triage's row says "names come from generated
adjective/name lists; no provider-name claim found by grep". h37-account
found the opposite (DN-1, section 3.1): after Google sign-in the profile
name, often a real name, becomes the public display and leaderboard name
(applied: Verified by `test_auth_api_client_privacy.gd:161`; display:
Believed). T17 (TODO line 50) is open, and it is a decision for Levi
(H59).

**Notes routed to the domain agents.** The agents cite TODO line numbers;
the triage appendix maps each line to its T number.

| Agent | Done or obsolete: delete the note | Open or partly, and the item that carries it | Not checked |
|---|---|---|---|
| Account | L17 (eb4da2d3); L250, L252 and L324 obsolete; L266-307 mostly obsolete, L303 done | L50 (H59); L82 partly (H57, H58, H64); L112 not done (SP69); L166-168 implemented, not shipped (H40); L178 mostly (SP12, H58); L330-333 partly (`game_session_manager.gd:196-200`) | L150-151 and L164 (no navigation run); L219 (console access) |
| Social | L82 done by design; L257 done | L81 partly; L83 open; L107-108 open, 5 defects (section 3.2); L122-127 all open (SP34 and the section 3.2 rows); L144-160: chevrons and RTL missing, check-mark icon wrong (H56); L164 open (H94); L241-242 not started (tooltip versus focus hint) | - |
| Matchmaking | 22 Verified works; 23 Verified fixed; 33-38 obsolete (H50); 138 and 162 Verified basic; 202-216 obsolete | 83 partial; 84 offline Verified, online Believed, parties split (H44); 110 Believed, no rematch (H44); 112 partial (SP69); 114-118 (H42); 122-127 as for 83; 187 skill pairing, feasible after G1 (H41); 330-333 half done (H51); 747 half done (H52) | - |
| Stats and ops | L87 covered by GUT; L95-105 resolved (ops L8, L2); L214 and L215 obsolete | L85, L148, L173-178, L253, L256 and L521 partly; L166-168 (H40); L670-676 one toggle, which ST1 reverts (H67); L759 not built; L788-790 open | - |
| exec-a | - | T66 "Get CI working again": CI works but never runs on push (H11). T103 "Fix broken tests": only the 3 netcode failures remain (RN6) | T65 "Review tests for slop": exec-a reported no notes assigned, and nobody reviewed the tests |

Where the agents disagree, both verdicts stand:

- **L792-795** (survey `G.check/ensure/error/fatal/alert`): matchmaking
  calls it moot (the API is now `G.log.*`, and the session files make no
  such calls); stats-ops calls it open, because only `G.log.error` feeds
  crash reports (CR6, H86).
- **L330-333** (loading-screen status text, T69): triage says Done
  (13bb063e, 3d392c6c); account says partly; matchmaking says half done,
  with no connecting or waiting phase (H51).
- **L670-676** (gore setting, T94): triage says Done; stats-ops says the
  toggle exists but ST1 reverts it (H67).
- **L82** (anonymous users, T21): account says partly (AN-1, AN-2,
  AN-3); social says done by design for its own features.
- **L83** (party matchmaking, T22): social says open; matchmaking says
  partial (unit tests pass, no live queue run).

## 6. Proposed work, in batches

Each batch is one agent stage or a few commits, in the order listed. A
probe moves into `test/` in the same commit as its fix (H77). Totals are
rough sums of the sizes in sections 3 to 5. Levi's decisions (section 7)
can reorder batches 1, 2 and 4.

| # | Batch | Items, in order | Rough total | Notes |
|---|---|---|---|---|
| 1 | Urgent and cheap | H40, H38, SP26, H67, H11, H70, H69, RN6, CC55; H39 once Levi decides | 1 to 2 days | H40 is the one item proposed as Urgent. H38's fix defers both peer changes; check it on a release template once H72 exists. SP26 is Next, not Urgent (verify item 0: latent, about 16 to 17 weeks to exhaustion with no real players). |
| 2 | Security and trust | SP70 and SP27 first; then H41 together with H43; then SP32 (with its compliance test), SP33, H15, SP41, SP43, SP35, SP36, SP44, SP47 | about 1.5 weeks | G1.1 must not ship alone: it would kick the owner and keep the thief. SP70 is S and closes the discovery link of the 0.1 chain at once. SP32, SP33 and SP34 share `rt:party.go`; H41 and H43 share `net:core/network_connector.gd`. |
| 3 | Matchmaking | SP30, SP29, SP28, H42, H45, SP71, SP58, H48, H44, H51, H52, SP31 | about 1 week | SP30 and SP29 are one change across the hook and the SDK. SP71 and SP58 share the stale-row sweep (RT1). |
| 4 | Account and social | H57, H62, H58, H64; then H59, SP34 and SP69 after section 7; H55, H54 with SP40, H23, H18, H60 with SP42, H61, H63, H53, SP37, SP45, SP46, SP48, H56 | 2 to 3 weeks | H57 needs H62's error mapping and a merge decision (Nakama answers AlreadyExists for a Google id another account holds). |
| 5 | Observability | CC51, H86, H87, H88 with CC56, SP65, SP56, SP61, SP64, SP59, SP60, H89, H90, H49, SP54, SP66, SP67, SP68, CC52, CC54 | about 1.5 weeks | CC51 is the DR drill's gap G1. The drill was a tabletop exercise; the certificates have 45 to 50 days left. |
| 6 | Testability | H77, H65, H74, H73, SP55, H75, H72, SP38, SP39, SP63, SP50, RN3, H9, H82, SP51, H68, H83, H81, H46, CC53 | 1.5 to 2 weeks | Section 4 steps 1 and 2 first. H72 needs a 4.7.2 template built with path overrides (verify item 4f). |
| 7 | Polish | H92 first, then H66 with RN7 and SP49, H93, H91, H94, H95, H96, H97 with SP53, H98, H99, H50, H85, H47, H80, SP62, RN8, CC57 | about 1.5 weeks | H92 is one 2-client session with Levi; H93 and H91 fix what it reproduces. |
| 8 | Ideas | H76, H78, H84, H100, SP52, SP57 | not scheduled | |

H71 and H79 are decisions, in section 7.

## 7. Decisions for Levi

| # | Decision | Options | Recommendation | Unblocks |
|---|---|---|---|---|
| 1 | Which items are Urgent | H40 (legal texts) is proposed Urgent. Candidates: SP32 (forced join), H38 (client crash), and the SP70, SP27 and H41 chain (0.1 row 4). SP26 stays Next: verify item 0 found it latent. | H40 Urgent. The chain Urgent if row 2 finds production matches the local stack. SP32 and H38 Next, top, unless real players are expected before batch 2 lands. | Batches 1 and 2 |
| 2 | SP70 in production | verify item 4e listed `match_metadata` and `server_registrations` as an ordinary signed-in player on the local stack. Production was not checked: that needs a production sign-in, which the audit did not allow. Options: (a) Levi lists both collections with an ordinary production session; (b) ship PermissionRead 0 without checking. | Ship SP70 (S) either way. Check production first only if the answer would change row 1. | SP70; the chain's priority |
| 3 | Networked pause (H39, T107) | Pause ships enabled, with no debug gate, and one player can freeze a match. (a) Off in `_apply_release_values`; (b) debug builds only; (c) keep it and fix the unpause. | (a) or (b) | H39 |
| 4 | Display names (H59, DN-1, TODO L50) | (a) Generated names, as L50 intends; (b) a rename screen; (c) keep the Google profile name, often a real name, public. triage's T17 note is wrong (acct, DN-1). | (a), with a rename screen later | H59, SP42 |
| 5 | Party control (SP34, TODO L127) | Today the creator cannot leave while others remain. Options: leaving hands leadership on; a disband RPC; a transferred leader gets full powers; any mix. | All three | SP34, H55 |
| 6 | Decoupling (H71) | Narrow seams (1.3; section 4 step 6) or a broad decoupling | Narrow seams only; decide RN1 on reuse grounds | H71, section 4 step 6 |
| 7 | One account on two devices (SP69, TD-1, TODO L112) | (a) One ticket per user at matchmaking time, as L112 says; (b) Nakama `single_socket`; (c) allow it and make presence per session; (d) document it. A Nakama setting is a production config change (`plat:infra/remote/nakama/config.yml`). Related: SP47. | (a) plus per-session presence; (b) if one device at a time is acceptable | SP69 |
| 8 | The org Actions secret (H79, CC31) | Checking the org-level `NAKAMA_HTTP_KEY` needs admin:org | Levi checks it and rotates it if stale; then CC31 closes | H79, CC31 |
| 9 | A 2-client session (H92) | T02 to T07, T16, T25, T27 and T29 need a person at two clients | One session before H93 and H91 | H93, H91 |
| 10 | What three TODO notes meant | T11: the gore "rainbow" (no rainbow transition exists in code). T14: `foobar.png`, unreferenced, ships in builds. T31: the friends-panel note is an empty bullet; section 3.2's rows may be what it meant. | Levi says | H80, H100 |
| 11 | SP12 and SP13, waiting since 10-12 | SP12 (acct SI-2): Facebook sign-in and link always fail, yet both panels offer Facebook and the privacy text names it (Broken by code). SP13: Custom, Game Center and FB Instant sign-ins skip the game_id check; Email is already refused. | Hide Facebook until it works; refuse the three unchecked providers until they are needed | SP12, SP13 |
| 12 | Tooltips (T61) | Hover only, or also on focus | On focus too, since mouse-only UI is not acceptable | T61 |
| 13 | `release.yml` (H83) | Run it once on a test tag, or mark the tag path unused in CLAUDE.md's deploy table | Run it once | H83 |
| 14 | Section 5's "Next tier" notes | Schedule now, or after batches 1 to 3 | After batches 1 to 3 | |

## 8. Proposed ledger items

IDs continue each ledger's numbering as of 10-14: hopnbop after H37,
platform after SP25, netcode after RN5, claude-config after CC50.
Re-check each ledger's highest ID before filing, since another session may
have filed items since. New items: 119 (hopnbop 63, platform 46, netcode
3, claude-config 7).

The `Row` column names where the item's verdict (as the source gave it),
its pointers and its fix sketch are; this section does not repeat them.
Items that appear only in a one-line list carry those cells here.

### 8.1 hopnbop (H38 to H100)

| ID | Ledger section | Item | Size | Row |
|---|---|---|---|---|
| H38 | Next, top (Urgent candidate) | Clients crash (signal 11) when the server goes away mid-match; defer both peer changes. Supersedes H25 | S | 3.3; 0.1 row 3 |
| H39 | Waiting on Levi | Networked pause ships enabled (T107) | XS once decided | 3.3; section 7 row 3 |
| H40 | Urgent (proposed) | Legal texts missing from every export (LG-1, ops C7) | S | 3.1; 0.1 row 1 |
| H41 | Next, after SP70 and SP27 | The game server does not enforce session validation (G1.1, G1.3). Ship with the G1.3 re-claim rule, never alone | M | 3.3; 0.1 row 4 |
| H42 | Next | A disconnected leader keeps the win on a normal match end (G2.1) | S | 3.3 |
| H43 | Next | Reconnect stale-peer race (F8) | S | 3.3 |
| H44 | Next | Play Again splits a party; there is no rematch | M | 3.3 |
| H45 | Next | The server self-quits inside the reconnect window and nothing reaches the runtime | S | 3.3 |
| H46 | Residuals | `test_network_connector.gd` crashed on exit | S | 3.3 list. mm: crashed in 1 of 3 runs. Fix: run the file 10 times and find what outlives the test |
| H47 | Residuals | transport.md drift: the retry count, port 4433 vs the real 4434/TCP, a GameLift fleet paragraph | XS | 3.3 list. mm (read). `.claude/rules/transport.md`. Fix: correct all three |
| H48 | Next | The 10 s server grace may be too short for WebRTC signaling | S | 3.3 list. mm: not measured. Fix: time signaling in a WebRTC run; start the grace after signaling |
| H49 | Residuals | `level_id` always empty in `match_stats` (ops S3) | XS | 3.3 list. mm; ops "lower". `edgegap_server_provider.gd:266-270`. Fix: pass the level id |
| H50 | Residuals | Delete the warm-up stubs (TODO 33 to 38, obsolete) | XS | 3.3 list. mm. `backend_api_client.gd:7-122`, `loading_screen.gd:115-135` |
| H51 | Next | The loading screen has no connecting or waiting phase (TODO 330 to 333, half done) | S | 3.3 list; section 5. mm. Fix: add the two phases |
| H52 | Residuals | Inert `game.yaml` `matchmaker_rules` fields; the same-device preference its comment claims does not exist | XS | 3.3 list. mm (read). Fix: delete `ticket_expiry_seconds`, `cross_play` and `rules`, or wire them; fix the comment |
| H53 | Next | Party client races: a follower cannot abort matchmaking; two Start presses split the party | M | 3.2 |
| H54 | Next | The notification poll is frozen on the oldest 50 rows (client half; SP40 is the server half) | M | 3.2 |
| H55 | Next, after section 7 row 5 | One absent member stalls the party | M | 3.2 |
| H56 | Next | Controller players cannot enter codes | M | 3.2 |
| H57 | Next | The guest upgrade signs in instead of linking (AN-1); a linked guest keeps `is_anonymous=true` | M | 3.1 |
| H58 | Next | Guests cannot export, delete or forget (AN-2) | M | 3.1 |
| H59 | Waiting on Levi | The Google profile name is the public display name (DN-1, TODO L50) | M | 3.1; section 7 row 4 |
| H60 | Next | Names and avatar URLs are never validated; any avatar URL is fetched (PI-1, DN-2; client half) | M | 3.1 |
| H61 | Next | Avatars from an earlier match show on the wrong players (PI-2) | S | 3.1 |
| H62 | Next | Link errors match AWS-era codes, so the merge path is dead (LK-4, LK-2) | S | 3.1 list. acct: LK-4 Broken by code. `link_account_row.gd:159,209`; `sdk:core/auth_api_client.gd:871-874` (prefix inferred). Fix: match Nakama's codes; route AlreadyExists to H57's merge decision |
| H63 | Next | The Log Out row is hidden when the access token has expired (AP-1), with DEL-1 | S | 3.1 list. acct: AP-1 Believed, low-medium. Fix: always offer Log Out; clear locally when the server call fails |
| H64 | Next | A guest's server calls go out with an expired JWT after 2 h (AN-3) | S | 3.1 list. acct: Believed, low. `backend_api_client.gd:528-536`. Fix: refresh the guest JWT when it expires, not only when none is stored |
| H65 | Next | Tests for the sign-out router's party reset and avatar-cache clear | S | 3.1 coverage. acct (no test). `sign_out_router.gd:103,111`. Fix: two GUT tests |
| H66 | Next | V17: 22 broken format strings, among them the refused-pause ERROR at `game_panel.gd:1854` (exec-b #10). 17 here; RN7 and SP49 hold the rest | S to M | section 5 row 2; 3.3 list |
| H67 | Next | A settings change reverts two launches later (ST1) | S | 3.4; 0.1 row 6 |
| H68 | Next | Legal parity is checked only by pr-validate, which never runs on push (C2); `edgegap_app_version` is not in the sync's mustSurvive list (C3) | S | 3.4 |
| H69 | Next | `sign-out-local-match` and `sign-out-play-again` fail since 88e3089b raised the match length to 180 s | XS | 3.1 coverage; section 4 step 2. acct, exec-b: copies with 10 s pass. Fix: a 10 s match length in both scenarios |
| H70 | Next | A signed signaling URL is logged; files the 10-13 inbox entry | XS | 3.5; 2.2 |
| H71 | Waiting on Levi | Decoupling: which seams to build | decision | 1.3; section 7 row 6 |
| H72 | Next | Exported-build runs for the harness (a custom 4.7.2 template) | M | section 4 step 4 |
| H73 | Next | Harness friction: loopback runs warn of production; client 2 starts 30 s late in matchmaker runs; screenshots are black for about 0.7 s after a screen change | S | 1.2 gaps; section 4 step 3 |
| H74 | Next | `scripts/dev-stack.ps1` from exec-b's `stack.ps1`, with seed and restart steps | S | 1.2 gaps; section 4 step 3 |
| H75 | Next | Harness sign-in plus `publish` and `wait_shared` steps; a fake `Platform.party` for GUT | M | 1.2 gaps; 1.3 rows 6 and 7; section 4 step 3 |
| H76 | Ideas | More than 2 clients and gamepad input in the harness | M to L | section 4 step 7 |
| H77 | Next | Land the H37 probes as tests, each with its fix | XS each | section 4 step 2 |
| H78 | Ideas | Golden screenshots (build item 7) | M | 2.2; section 4 step 7 |
| H79 | Waiting on Levi | Check the org-level `NAKAMA_HTTP_KEY` Actions secret (needs admin:org) | XS | 3.5; section 7 row 8 |
| H80 | Residuals | Textures orphaned by b998107d, `foobar.png` once T14 is answered, orphan `.import` files | XS | 2.2; section 5 |
| H81 | Residuals | `local-smoke-test.ps1` rewrites the checkout it runs in; "several runs at once" holds only per worktree | S | 3.5 |
| H82 | Next | Pin staticcheck in `pr-validate.yml:305` | XS | 3.5 |
| H83 | Next, after section 7 row 13 | `release.yml` has never run and no `v*` tag exists | S | 1.1 |
| H84 | Ideas | Test fixtures log "no animation 'Rest'" 37 times per run | XS | 3.5 list. exec-a (seen in every run). Fix: give the fixtures a `Rest` animation, or stop playing it |
| H85 | Residuals | CLAUDE.md names the debug toggles wrongly; `dev_mode` is read nowhere (ST5, triage V27) | XS | 3.4 |
| H86 | Next | Script and engine errors that do not crash are never reported (CR6) | S to M | 3.4 |
| H87 | Next | A dedicated server's fatal error or engine crash is never reported (CR1, CR7) | M | 3.4 |
| H88 | Next | Nightly smoke makes a new account each run, and player metrics count them (OP3; the workflow half) | S | 3.5 |
| H89 | Next | The final match stats ride one unreliable RPC (S11) | S | 3.4 |
| H90 | Next | Failed cloud saves are dropped (ST2, ST3) | M | 3.4 |
| H91 | Next, after H92 | A short input grace on the game-over screen (T79) | M | section 5 row 5 |
| H92 | Waiting on Levi | One 2-client networked session with Levi (T02 to T07, T16, T25, T27, T29) | S | section 5 row 3; section 7 row 9 |
| H93 | Next, after H92 | The overhead label offset (T29) | S to M | section 5 row 4 |
| H94 | Next | A controller pass by hand, with two local players (T45, T08, T09) | S | section 5 row 6 |
| H95 | Next | A click sound on every MenuRow trigger (T42) | S | section 5 row 7 |
| H96 | Next | Alt+Enter fullscreen (T10) | S | section 5 |
| H97 | Next | Finish T12; delete the 9 Stale notes (with SP53) | S | section 5 |
| H98 | Next | Finish T43; verify, then fix, T19 | M | section 5 |
| H99 | Next | Finish T48 | M | section 5 |
| H100 | Ideas | Level art (T15, T28, T14) | L each | section 5 |

### 8.2 snoringcat-platform (SP26 to SP71)

| ID | Ledger section | Item | Size | Row |
|---|---|---|---|---|
| SP26 | Next (not Urgent) | The local port pool leaks a UDP/TCP pair per match | S | 3.3; 0.1 row 8 |
| SP27 | Next, top of batch 2 | Session ids can be computed (G1.2): random per-slot tokens and a token-to-user-id map; lands before H41 | M | 3.3; 0.1 row 4 |
| SP28 | Next | A Cancel during `start_matchmaking` leaves a ghost ticket | S | 3.3 |
| SP29 | Next | One player's 120 s timeout cancels the whole matched set's allocation | S | 3.3 |
| SP30 | Next | No match forms for anyone while an allocation runs | M | 3.3 |
| SP31 | Residuals | Couch co-op totals are uncapped: up to 16 bunnies in a 4-user match | S | 3.3 list. mm (read). Fix: cap the total at ticket or join time |
| SP32 | Next, top (Urgent candidate) | A party invite is a forced join. Fix `sdk:test/compliance/test_party_invite_flow.gd:136-140` with it, since it accepts the join | M to L | 3.2; 0.1 row 2 |
| SP33 | Next | Any member can pull everyone into a match load | M | 3.2 |
| SP34 | Waiting on Levi | The creator cannot leave while others remain (TODO L127) | M | 3.2; section 7 row 5 |
| SP35 | Next | 50 pending outgoing friend requests block every accept | S | 3.2 |
| SP36 | Next | Blocking stops friend requests and nothing else | S | 3.2 |
| SP37 | Next | Party chat has no server-side length, rate or block limits; stale comments and dead code | S | 3.2 list. soc F9. Fix: limits in the chat hook; delete the dead routes |
| SP38 | Next | A Go fake-`nk` harness for runtime hooks | S to M | section 4 step 5; 1.3 row 1 |
| SP39 | Next | Two- and three-user compliance cases | S to M | section 4 step 5; 1.3 row 5 |
| SP40 | Next | The notification poll is frozen on the oldest 50 rows (server half) | M | 3.2 |
| SP41 | Next | A failed `delete_account` is reported as a failed sign-in (DEL-2); root cause `sdk:core/auth_api_client.gd:890,896` | S | 3.1 |
| SP42 | Next | Server-side validation of names and avatar URLs (PI-1, DN-2) | M | 3.1 |
| SP43 | Next | A refresh during a pending link is taken as the link's success (LK-1) | S | 3.1 |
| SP44 | Next | The guest device id is not crypto-random (SI-1); the token store passphrase is weak (TS-1) | S | 3.1 list. acct: SI-1 Suspect, low-medium; TS-1 Believed, low. Fix: a random 128-bit device id; a real key per platform. TS-1 accepted as obfuscation only (2026-10-30): the per-install key sits beside the file, so it resists casual inspection, not a copied user folder; no OS keystore. |
| SP45 | Next | Every hourly refresh emits the same `auth_completed(true, "")` as a sign-in, so subscribers redo sign-in work (SL-1) | S | 3.1 list. acct: Believed, low-medium. `_handle_auth_success` (1282) emits it; `global.gd:388-392` then refetches and merges cloud settings, and four more listeners react. Fix: a separate `session_refreshed` signal that sign-in listeners ignore |
| SP46 | Next | An expected export failure files a crash report (DX-1) | XS | 3.1 list. acct; exec-b's offline export run |
| SP47 | Next | Sessions are not revoked on account delete (DEL-3) | S | 3.1 list. acct |
| SP48 | Residuals | Desktop loopback OAuth is fragile (SI-4); Android sign-in (SI-6); Apple is listed with no flow (SI-3) | M | 3.1 list. acct: SI-4 Suspect; SI-6 Believed, not run on a device; SI-3 Believed |
| SP49 | Next | V17's broken format string in `sdk:test/compliance/test_account_delete.gd:118` | XS | section 5 row 2 |
| SP50 | Next | Client SDK CI runs no tests | S | 3.5 |
| SP51 | Next | Pin staticcheck in `nakama-runtime.yml:44` | XS | 3.5 |
| SP52 | Ideas | Tests for signaling-proxy and geoip-sidecar | M | 3.5 list. exec-a (vet clean) |
| SP53 | Residuals | Docs: CLAUDE.md "Testing" and "Code Style" claims, MULTI_GAME_ROADMAP, a dead plan path; SP10's gofmt set | S | 3.5 |
| SP54 | Residuals | `AutoRemove: true` discards game-server container logs (`rt:local_allocator.go:219`) | S | 3.5 |
| SP55 | Next | A dev stack with the local allocator (build item 5b) | M | section 4 step 3; 2.2 |
| SP56 | Next | Close the DR drill's gaps. The drill was a tabletop exercise, not an outage | M | 3.5; 2.2 |
| SP57 | Ideas | Run one real DR rebuild | M | 3.5; 2.2 |
| SP58 | Next | match_end is not atomic and nothing monitors it (S1, OP2); the stale-row sweep (RT1) | M | 3.4 |
| SP59 | Next | Any session can write unbounded storage (RL3) | M | 3.5 |
| SP60 | Next | The public leaderboard read scans 5 pages, and guests are recorded on the board (L2) | S to M | 3.4 |
| SP61 | Next | The 500 per day global crash cap starves servers (CR4) | S | 3.4 |
| SP62 | Next | Unknown config keys are ignored, and the other sync gaps (C4, C5) | XS to S | 3.4 |
| SP63 | Next | A test for account_cron (RT4) | S | 3.5 |
| SP64 | Next | Nothing validates or reloads the Caddyfile on deploy; the Caddy build is unpinned (RL5, RL6) | S | 3.5 |
| SP65 | Next | Grafana rules for 5xx, 429 and Nakama RPC errors (OP6) | S | 3.5 |
| SP66 | Next | Read the Postgres errors that prod-health-check counts (OP4) | S | 3.5 |
| SP67 | Next | Pruning for the three unbounded stores (RT3) | S | 3.5 |
| SP68 | Next | Paginate `get_match_history` (OP7) | S | 3.5 |
| SP69 | Waiting on Levi | One account can queue from two devices (TD-1, TODO L112) | M | 3.1 list; section 7 row 7 |
| SP70 | Next, top of batch 2 | Match rows are listable by any signed-in player | S | 3.3; 0.1 row 4; section 7 row 2 |
| SP71 | Next | `match_cancel` without a registration is a no-op; test matches leave rows; two wrong test comments | XS to S | 3.3 |

### 8.3 godot-rollback-netcode (RN6 to RN8)

| ID | Ledger section | Item | Size | Row |
|---|---|---|---|---|
| RN6 | Next | 3 `test_webrtc_signaling.gd` failures are test bugs; they block RN3 | S | 1.1; section 4 step 1 |
| RN7 | Next | V17: 4 broken format strings | S | section 5 row 2 |
| RN8 | Residuals | Pause stats always read 0 frames | XS | 3.3 list. exec-b: Observed in run 7's log ("paused for 0 frames"); cause Believed. `net:core/frame_driver.gd:711-712`. Fix: find why the count reads 0, then log the real length |

### 8.4 claude-config (CC51 to CC57)

| ID | Ledger section | Item | Size | Row |
|---|---|---|---|---|
| CC51 | Next | Page when certificate renewal fails (DR drill gap G1; the certificates are fine today) | S | 3.5; 2.2 |
| CC52 | Residuals | `Invoke-RemoteSql` defaults to the nakama user with no read-only guard | S | 3.5 |
| CC53 | Next | `-AllowMock` on the synthetic probe, so it can run against a local stack | S | 3.5; section 4 step 6 |
| CC54 | Next | Jobs that hit the weekly usage limit leave no report and no status entry | S | 3.5 |
| CC55 | Next | caddy-access-analytics has reported nothing real since at least 10-01 | XS | 3.5 |
| CC56 | Next | Exclude probe accounts from player metrics (OP3; the metrics half) | S | 3.5 |
| CC57 | Next | A lessons.md entry: PowerShell variable names ignore case. In this audit's phase 3, `$T` overwrote `$t` and truncated a copied file | XS | phase 3 (this report); claude-config `rules/lessons.md` |

### 8.5 Updates to existing items

- **H1:** platform SHA af566b9 is now 6081b82 (history's SHA map).
- **H9:** still true; the formatter job is green but skips everything
  (exec-a).
- **H11:** still true, now 25 commits (`3b7f5743..9bbaa7ee`), the 0.54.0
  release `8ca156e7` among them; legal parity (C1) depends on it.
- **H15:** still true and wider: sign-in over a guest too (AN-1b). verify
  item 4d: Broken, Verified end to end (2 runs).
- **H17:** add the probe evidence (mm); platform SHA 8ede126 is now
  f4424d5; SP27 and H41 fix it.
- **H18:** add the social R4 repro, the export toast
  (`export_data_row.gd:96-99`, exec-b) and the poll toast
  (`friends_panel.gd:342-354`).
- **H19, H21:** still true (mm).
- **H20:** still true; fix: `copy_latest_state` at `game_panel.gd:673` and
  `779`, as at 694 (mm).
- **H22:** still true, about 9 s measured (acct).
- **H23:** still true; DEL-2 adds a trigger (acct).
- **H24:** still true, low (mm).
- **H25:** Dropped: superseded by H38. verify finds the same family; H38
  has the full trigger set and the fix. (Or update H25 in place, if Levi
  prefers its ID.)
- **H26:** reaches players (exec-b run 2: Verified; the production scope
  Believed; section 3.3).
- **H27:** still present, Verified (mm); fix pointers: an `is_local_mode`
  guard at `frame_synchronizer.gd:120`, and skip the local peer at
  `networked_level.gd:307`.
- **H28:** see H86 (CR6).
- **H29, H32:** still true.
- **H31:** pointer `credits_screen.tscn:40,55,70,85,114`.
- **H33:** not implemented.
- **H35:** passes 11/11 per file (exec-a); the full-directory case was not
  rerun.
- **SP2:** still true (`plat:scripts/phase-b.ps1:373-416`). **SP3:**
  Believed.
- **SP4, SP5, SP7, SP8, SP11, SP17, SP24:** their platform SHAs were
  rewritten by timestamp-sweep; history's SHA map has the new ones.
- **SP6:** done in plat 8b891cd (refresh tests 17/17, acct).
- **SP9, SP14, SP15, SP16, SP19, SP24:** still true (SP14 is ops RT2, SP16
  is ops L3).
- **SP10:** still true; the set is now friends_limits, helpers_test,
  local_allocator, main and party.
- **SP12, SP13:** still true, waiting since 10-12 (section 7 row 11).
  SP12 is acct SI-2, Broken by code (3.1). SP13 holds for Custom, Game
  Center and FB Instant; Email is already refused.
- **SP18:** still true; shares the per-match-secret fix with SP27.
- **SP22:** still true by config, low.
- **SP23:** also purge orphaned guest accounts (AN-1; verify2 found nothing
  for them in `account_cron.go`).
- **SP25:** dormant.
- **RN3:** still true; blocked by RN6.
- **CC31:** still open.
- **CC34:** extend it to SHAs in ledgers and docs (history).

### 8.6 Inbox

File the 10-13 `LEDGERS.md` inbox entry (the signaling URL) as H70, with
the line corrected to `src/core/game_session_manager.gd:345-353`, and
delete it from the inbox. The 10-14 TCP-ports entry is outside H37.

## 9. What this audit did not check

The union of every agent's "not checked" list, grouped by why.

**Production access the rules ruled out** (no SSH, no sign-ins, no
credentials, no writes):

- The Nakama and Postgres logs on the host (S1, OP2, OP4), Docker log
  rotation, the host `.env` (SP3) and Caddy's access logs (ops, history).
- Production Grafana alert rules (a login) and UptimeRobot's current state.
- The org-level `NAKAMA_HTTP_KEY` Actions secret (admin:org) and the
  desktop credentials file behind CC31.
- Caddy's 429 paths, and whether production runs the committed
  Caddyfile: a check would trip production limits.
- Real OAuth and production sign-ins (SP17, TODO L219, T55's consent
  screen links); Nakama internals such as refresh-token rotation and
  unlinking the last identity.
- `edgegap-logs -Latest` under the hybrid allocator, and production
  crash counts.

**Not run locally:**

- The shipped binary. The client crash was reproduced in the editor and
  in a minimal 4.7.2 release-template project, not in a hopnbop export
  (verify item 1); only ENet was tested, and the pre-match "not enough
  players" path is undetermined.
- LG-1's blank screen in a running export (verify2 item 4 Verified the
  pack contents of all four presets, not a running build); networked pause
  in a release build (verify item 4f: a run needs a 4.7.2 template built
  with path overrides); the Edgegap restart path after a self-quit (verify
  item 4e); SP70 in production (needs a production sign-in, section 7).
- Web and WebRTC end to end (the dev stack has no signaling proxy),
  gamepads and controller navigation, 3 or 4 players, more than 2 local
  players.
- A real game-server allocation or a slow one (the stack has only the
  mock), HMAC key rotation, a double `matchmaker_matched`, whether
  Nakama can put one user twice in a matched set, and which other Nakama
  APIs show user ids to strangers.
- AN-1b proper (sign-in over a guest without a log-out); two devices on
  one account live; H26's repro; the 60 s auto-unpause.
- The Pulumi build, any Linux run, and the netcode tests in a project of
  their own (exec-a).
- The L792-795 logging survey outside the session files; more than 4
  players' spawns and HUD; the per-game Edgegap app; the TODO line 210
  export (matchmaking).

**Checked by no agent:**

- T65 "Review tests for slop": triage routed it to exec-a, which reported
  no notes assigned.
- Art, audio and polish quality by eye, and Levi's intent on T11, T14
  and T31.
- Ledger items outside this audit's domains, carried unchanged: H3, H5,
  H6, H7, SP20, SP21, CC10, CC31, CC32 and HG1.
- Laptop transcripts after 10-12 21:22 UTC (they are not on this
  machine), so laptop-only decisions may be missing; the platform plan
  file that triage could not find may also be there. The one Muse session
  holds only metadata.

## 10. Appendix index

Appendices are the agents' findings files, copied unchanged except where
noted. Pointers in this report name them by the short names in section 3.

| Appendix | Short name | What it holds |
|---|---|---|
| [h37-history](H37/h37-history.md) | history | Where we left off, the testability conversation, 46 loose threads, the dead-SHA map |
| [h37-account](H37/h37-account.md) | acct | Account, auth, consent, export and delete, names and avatars, legal texts |
| [h37-social](H37/h37-social.md) | soc | Friends, parties, presence, notifications, chat |
| [h37-matchmaking](H37/h37-matchmaking.md) | mm | Matchmaking, allocation, sessions, transport, reconnect, match end |
| [h37-stats-ops](H37/h37-stats-ops.md) | ops | Stats, leaderboards, settings, per-game config, crash reporting, observability, retention, rate limits. One redaction: the SP22 line ("[redacted]") |
| [h37-exec-a](H37/h37-exec-a.md) | exec-a | Import, every GUT file, the compliance suite, Go tests, the CI audit |
| [h37-exec-b](H37/h37-exec-b.md) | exec-b | Harness runs: 13 committed and 8 new scenarios, the capability table, harness gaps |
| [h37-triage](H37/h37-triage.md) | triage | All 112 TODO-scratch notes, dated and checked |
| [h37-verify](H37/h37-verify.md) | verify | Phase 2: port pool, the client crash, pause, forced join, items 4a to 4f. Complete (Done 11:46) |
| [h37-verify2](H37/h37-verify2.md) | verify2 | Phase 2b: G1.2, the allocation stall and timeout, AN-1, DEL-2, LG-1 on every preset. Complete (Done 11:45) |

Artifacts in `docs/design/H37/artifacts/<agent>/` (a `.gdignore` at the
top keeps Godot from importing or exporting them):

| Agent | Files | Use |
|---|---|---|
| h37-account | `test_h37_account_probe.gd` | GUT probe with a fake Nakama: LK-1, DEL-2, PI-1, PI-2, SO-1 (asserts today's bugs) |
| h37-social | `probe_social_test.go`, `run-gut.ps1` | Go probe of the party and friend hooks; a one-file GUT runner |
| h37-matchmaking | `h37_local_port_leak_test.go`, `test_h37_ghost_ticket.gd`, `test_h37_declare_validation.gd`, `offline-play-again.json` | The port-leak Go test, the ghost-ticket and declare-validation probes, an offline replay scenario |
| h37-stats-ops | `test_probe_settings_echo.gd`, `run-gut.ps1` | The ST1 probe (two echo assertions fail today); a GUT runner with a throwaway APPDATA |
| h37-exec-a | `run-gut.ps1`, `import.ps1`, `ci-summary.ps1` | One-file-at-a-time GUT runs, a sandboxed import, a CI run summary |
| h37-exec-b | `stack.ps1`, `run-scenarios.ps1`, `relaunch.ps1`, `kill-run.ps1`, `scenarios/` (10) | The local stack on free ports, batch scenario runs, and the scenarios of section 1.2 |
| h37-triage | `fmt_precedence_scan.py`, `precedence_test.gd`, `blame_dates.ps1`, `make_table.py`, `patch_items.py`, `offline-labels.json`, `offline-play-again-colors.json` | The V17 scanner and its engine check, blame dating, two offline scenarios |
| h37-history | `extract.py`, `search.py`, `jobstatus.py`, `lastreply.py`, `tools.py` | Transcript and status-trail extraction (their raw outputs were deleted: they held IPs and emails) |
| h37-verify | `stack.ps1`, `lib.ps1`, `item3.ps1`, `item4a.ps1` to `item4d.ps1`, `d4/rec.gd`, `scenarios/` (3), `repro/` | The local stack and REST helpers (loopback only), one script per verified item, the H15 log-out scenario, and the minimal 4.7.2 crash repro (editor versus release template) |
| h37-verify2 | `test_h37v2_guessable_sids.gd`, `test_h37v2_guest_upgrade.gd`, `h37v2_hook_test.go`, `h37v2_matchmaker_stall_test.go`, `list_pack.py` | G1.2 and AN-1 probes, the allocation hook and Nakama matchmaker stall tests, a pck lister for LG-1 |

Left out on purpose: raw outputs, logs, run directories, exports and
engine templates; copies of platform and Nakama source (stats-ops'
`gofmt/`, verify2's `runtime-copy/` and `nakama-src/`, except the two
test files above, which go back into those trees to run); two stats-ops
scripts that name a production account; and the scratch fragments
stats-ops used to rebuild its file.
