---
paths:
  - "src/core/crash_*"
  - "test/unit/core/test_crash_*"
---

# Crash reporting lore

The full crash-reporting contract, moved verbatim from CLAUDE.md by
H34 (2026-10-13). CLAUDE.md keeps the two-line summary.

`src/core/crash_reporter.gd` (`G.crash_reporter`) sends reports to
the platform runtime's `crash_report` RPC; the text helpers
(redaction, signatures, crash detection) are in
`src/core/crash_report_text.gd`. RPC contract, storage, retention
(30 days), and SQL recipes: `PLATFORM_ARCHITECTURE.md` → "Crash
reports".

- **Sources:** `G.log.error`, and so `G.log.ensure` and
  `G.log.check`; plus a Godot crash found at boot in the previous
  session's log. Godot 4 copies the last `godot.log` to
  `godot<local time>.log` (e.g. `godot2026-10-11T13.25.20.log`), and
  the crash text is `CrashHandlerException: Program crashed with
  signal N` on Windows, `handle_crash: Program crashed ...` on Linux
  and macOS. Both were checked against a real 4.7.2 crash
  (`OS.crash`). Plain engine `ERROR:` lines are not reported.
- **Queue:** every report is redacted (tokens, account values,
  UUIDs, device ids, signaling-URL tokens, emails, IPs,
  home-directory user names) and
  written to `user://crash_reports.json` (at most 5) before any
  send. A player's reports go out once a live Nakama session exists:
  anonymous players get one only when they go online. Dedicated
  servers send with `NAKAMA_HTTP_KEY` from their environment and
  queue nothing without it. An entry leaves the queue when the
  server accepts it, rejects it as invalid, fails 5 times, or is 7
  days old; a crash's log is marked handled only then. At most 5
  reports per run, each signature once. A fatal error's report
  waits for the next run.
- **Editor builds never send.** Running from the editor (preview
  instances, the agent harness, GUT) uses
  `user://crash_reports_editor.json` and only queues, so
  development errors stay out of production's reports. Set
  `HOPNBOP_SEND_CRASH_REPORTS=1` to let an editor build send (point
  it at a local stack first). GUT runs skip the boot-time reporter
  entirely.
- **Reading them:** claude-config's daily `prod-health-check` has
  a `crashes:` line (24h count, new signatures, top signatures);
  the SQL to dig into one is in `PLATFORM_ARCHITECTURE.md`.
- **Tests:** `test/unit/core/test_crash_reporter.gd` and
  `test_crash_report_text.gd` (SDK and network doubled); the
  platform compliance suite's `test_crash_report.gd` posts reports
  to the local stack and reads them back through the Nakama
  console.
