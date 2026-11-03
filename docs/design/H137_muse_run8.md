# H137: Muse run 8, three live client bugs from the H104 review

Brief for Muse's eighth run (Muse Code through Paseo), written by Claude
(claude session 0cfd9cf1) on 2026-11-02. Claude sends it, not Levi.
It holds the hopnbop-only client fixes that Claude's review of the H86
and H54 work (H104, stage 2) left: an offline RPC error that every
offline run now reports as a crash (H106), friend events that never toast
(H134), and crash reports sent twice (H136), plus the docs that describe
the reporter (H131). All four reach players with the next client release,
which needs Levi's OK.

How to use it: section 1, then section 2's items in order. A fresh
session resumes from this file, ledger item H137 and
`git log --oneline -15`. Re-read this file after a compaction. This file
is the authority; a Paseo message changes it only when the message says
so. Path shorthand: `net:` is `addons/rollback_netcode/`.

## 1. Rules

- H103's sections 1 and 2 (`docs/design/H103_muse_backlog.md`) apply:
  read "H103" there as H137, and ignore 1.3's last bullet (this file has
  no section 4). That is the commit flow, the gates, and the table of
  area rules to read before editing. The commit and push grant (H103 1.1)
  stands: Levi gave it in his own words on 2026-10-29, your memory
  `feedback_commit_and_push.md` records it, and it covers runs Claude
  launches from a committed brief, so don't ask again. hopnbop pushes
  only run CI. No subagents or workflows (H103 1.2). You are the only
  writer in hopnbop until you stop.
- **Hands off the platform.** `third_party/snoringcat-platform` holds
  four commits that exist nowhere else and wait for Levi's OK to deploy
  to production, which is why hopnbop's pointer shows as modified and has
  to stay that way. Don't edit, commit, pull, check out, restore or reset
  anything in or under that path, and don't run `git submodule update`,
  `git restore` or `git checkout` on it. Claude may push those commits
  from there while you work; a push changes no files here, so ignore it.
  Don't run `scripts/local-smoke-test.ps1` or
  `scripts/setup-platform-addon.ps1`: nothing in this run needs either.
  Never stage the platform pointer or `net:`. Stage by name, and
  `git diff --cached --stat` must show only your files.
- **The findings.** Ledger items cite labels such as "H54-1" and
  "H86-1": entries in Claude's stage 2 report,
  `.claude/probes/H104/stage2.md`, untracked and on this machine only
  (`Select-String -Pattern '^### H54-1'` finds one). Read a finding's
  whole entry (where, failure, what was verified, the fix) before you
  change code. The fixes there are proposals: when you find a better one,
  do it and say why in the handoff log. When a finding is wrong, record
  why and leave its item open for Claude.
- **Public repo.** Commit messages, ledger text, code comments, test
  names and the handoff log say what a change fixes or enforces. Never
  commit the report or copy its text.
- **Read before editing.** You don't load the area rules, so read these:
  `.claude/rules/gdscript-style.md`, `.claude/rules/testing.md` (GUT, the
  `wait_seconds` traps), `.claude/rules/transport.md` (2.1, local mode),
  `.claude/rules/crash-reporting.md` (2.3 and 2.4) and
  `scripts/agent/README.md` (the harness). On Windows run
  `Godot_v4.7.2-stable_win64_console.exe`, not `godot.exe`.
- **A test that fails without the fix.** Run it against the unfixed code
  and see it fail (H103 section 2). Where a unit test isn't feasible, a
  harness run before and after, with the numbers in the handoff log,
  stands in.
- **Commits.** One per ledger item (H136 may take two). Message
  `<ID>: <what changed>`, a line or two of why, then
  `Muse-Session: <your session id>`. Take SHAs from `git rev-parse HEAD`.
  After each push check CI (`gh run list -R SnoringCatGames/hopnbop
  -L 3`); a red run on your commit is the next thing you fix.
- **Ledgers.** Close H106, H134, H136 and H131 in `LEDGER.md` as H103 1.5
  says; a ledger commit after the fixes is fine. Leave H126 and H132
  alone: they are Claude's. File anything new the moment you find it. In
  your first commit, put your session id on H137's `owner:` line.
- No client release, no version bump, no prod requests, no deploys, no
  `game.yaml` edits (H103 1.3). Tests and the harness stay on loopback.
- **Stop rule.** Stop when the four items and the handoff entry are done,
  or after 2 hours of wall clock, whichever comes first: run `Get-Date`
  at the start and at each milestone. A compaction is not a stop; after
  one, re-read this file and `git log` before going on. Two failed
  approaches to an item shelve it (H103 1.6). Never commit partial work.

## 2. Work

### 2.1 H106: offline runs report an RPC on yourself (first)

`src/objects/client_stat_reporter.gd:133-138` sends
`_rpc_server_update_critter_stats` (declared at
`src/core/match_state_synchronizer.gd:447`) to the server. In local mode
the server is this process, and Godot refuses an RPC on yourself ("on
yourself is not allowed by selected mode"). Since H86, in the live
0.57.0, the engine logger turns that line into a queued crash report:
every offline run on a level with critters queues one (all 43 post-H86
harness runs on level_0 or level_4 did). So H106 is now a crash report
per offline run, not log noise.

Fix it as H27 did (`f5f2268c`, `net:` `d13ec20`): never RPC the local
peer in local mode. First read the callee. If its effect is something
local play shows (the match-end stats, say), call the function directly
in local mode (`Netcode.runs_server_logic`; CLAUDE.md, "Local mode RPC
pattern"). If nothing local reads it, skipping keeps today's behavior,
since the RPC never arrived. Say which in the commit. Networked play
must not change.

Check: a GUT test if the reporter can be driven in local mode. Either
way, run `scripts/agent/run-game.ps1 -Scenario offline-move-jump` before
and after and compare the run directory's queued crash report (the
sandboxed `user://`; `crash_reports_editor.json` in editor runs) and its
log. Before: one RPC report. After: none. If that scenario doesn't queue
it before the fix, use one that does (`-Mode level -Level level_0`).
Then run `-Scenario match-2-clients` once to show networked play still
passes.

### 2.2 H134: offline friend events never toast

Entries `### H54-1` to `### H54-3`. `src/core/friends_notification_poller.gd:166`
skips the notification list while the socket is healthy, so friend events
that arrived while the player was offline never toast. Drain the list
once at sign-in and again on every `socket_connected`, and keep the
seen-ids dedup so nothing toasts twice (once from the list, once from
the socket).

Tests: events waiting on the server at sign-in toast with a healthy
socket; the same after a reconnect; none toasts twice. The first two must
fail on the current code. Your tests must not touch the real profile:
H54-3 notes that the existing poller tests write the real dedup file, so
point yours at a throwaway path, and if the old tests can be redirected
the same way in a few lines, do that in the same commit. H54-2 (a late
poll response handing the old account's cursor to the next session) is in
the same file: fix it if the change is small and tested, otherwise log it
for Claude.

### 2.3 H136: crash reports sent twice (probe first)

Entries `### H86-1` to `### H86-4`. The review read the code and the
Godot 4.4 source on disk and **inferred** that every `G.log.error` is
reported twice: `error()` calls `push_error`, which reaches the engine
logger (`src/core/engine_error_logger.gd:40-44`), and then calls the
reporter directly (`src/scaffolder/scaffolder_log.gd:157`, `:164-165`).
The two copies differ in text, so dedup misses them, and a fatal one
flushes just before the quit. Nothing observed it: no `G.log.error`
fired in the 90 harness logs.

1. **Probe on 4.7.2 first.** In an offline harness run, call
   `G.log.error("h136 probe")` once with an `eval` step
   (`scripts/agent/README.md` lists the steps), then count the queue
   entries that carry the probe text. Keep the probe untracked, in
   `.claude/probes/H136/` (if the wrapper only reads
   `scripts/agent/scenarios/`, copy it there for the run and delete the
   copy). Put the counts in the handoff log. One entry means H86-1 is
   not reproduced: change nothing, leave H136 open for Claude with the
   evidence, and go on to 2.4.
2. **If two entries**, report a `G.log.error` once. Either have the
   logger skip G.log's own lines (a flag `error()` sets around its
   `push_error` is exact), or drop the direct call and let the logger
   report it, with the `FATAL` prefix meaning `is_fatal`. A fatal error
   must not flush before the quit. Test, from the entry: feed the logger
   the arguments `push_error` produces for a G.log line, then make the
   direct call; expect one entry, and no flush for a fatal one. It must
   fail on the current code.
3. H86-2's wording: the logger's header says an error loop can't spend
   the daily cap; make it say that holds once per run. Don't build the
   cross-run dedupe: it needs a runtime change, and Claude files it.
4. **H86-4, a re-entrancy guard** in `report_crash`
   (`src/core/crash_reporter.gd:165-177`), with a test that re-enters the
   reporter and fails without the guard. If you can't make the loop
   happen in a test, skip this one and say so.

### 2.4 H131: the reporter's docs (last)

After 2.3, make the docs say what the code does.
`.claude/rules/crash-reporting.md:26` still says plain engine `ERROR:`
lines are not reported; the header of `src/core/crash_reporter.gd`
(`:6-8`) and the doc of `report_crash` (`:158`) name only G.log and the
boot-time crash scan. Name the engine logger as the third source. Add the
two limits from the entry's "H86 nits" and H86-3: release templates never
print script errors, so a broken format string stays unreported (to catch
a specific one, put `G.log.check` at its call site), and errors raised
before `CrashReporter._ready` are not seen. Comments end with periods,
80 columns, no em dashes.

### Closing

Close the items (H103 1.5). Then append your handoff entry to section 3
(done, with SHAs; shelved, with patch paths; the probe's counts; anything
for Claude to file), set H137's `owner:` to `nobody since <time> (<why>)`,
commit and push.

## 3. Handoff log

Append one dated entry each time you stop.

- 2026-11-02, muse 01a19f7e-156d-7921-b3c4-f6a27e924c42 (run 8
  complete, 19:40 to 19:58 PT): all four items landed on main.
  H106 in a87d5d41: local mode applies the critter deltas in
  place (they feed the match-end stats local play shows); the
  handler's guard is runs_server_logic and a direct call
  validates as the local peer. New
  test_critter_stats_local_mode.gd fails unfixed, passes 2/2.
  Harness offline-move-jump: before, errors=1 with one queued
  RPC report (signature 6c3f471ec54dc498); after, errors=0 and
  no queue file. match-2-clients passes. H134 in 22069959:
  drain at sign-in and on every socket_connected, paging on
  full pages, H54-2 generation guard (a response landing
  after the new session's own fetch cannot be told apart;
  that window stays), H54-3 test-path redirect only (the
  seen-mark timing and the device-wide file are unchanged).
  Lifecycle 16/16 and poller 29/29; the sign-in and reconnect
  tests fail on the unfixed poller. Six lifecycle fetch counts
  rose by the sign-in drains and say so. H136 in 71d936f0:
  probe first (scenario kept in .claude/probes/H136/). One
  G.log.error queued 2 entries before the fix, the logger
  copy `ERROR  : h136 probe (core/variant/
  variant_utility.cpp:1023)` (e8d5ec1efadb27ec) and the
  direct copy (62ffe2ce3c396e21), and 1 entry after, the
  direct copy. So H86-1 reproduces on 4.7.2. The fix flags
  the push in ScaffolderLog.error; report_crash also drops
  re-entrant calls (H86-4, with a test whose log read errors
  back into the reporter); the logger header now scopes its
  cap claim to one run (H86-2). Three new tests fail
  unfixed; test_crash_reporter.gd passes 35/35. H131 in
  f33c3c5c: the rules file, the reporter header and
  report_crash doc, and the logger header name the engine
  logger and both limits. Shelved: none. For Claude to
  file: the rest of H54-3 (mark a toast id seen only once
  the toast shows; key the dedup file per account), and
  H86-2's cross-run dedupe, which needs the runtime change
  the brief reserves. The platform pointer was never
  staged; no release, version bump, or prod contact.
