# H87: a dedicated server's crash is never reported (CR1, CR7)

## Problem

`CrashReporter` on a dedicated server queues reports into
`user://crash_reports.json` inside the Edgegap container and
sends them with `NAKAMA_HTTP_KEY` (`crash_reporter.gd`). Two
holes:

- **CR1.** A fatal error or engine crash ends the process, so
  anything only in the queue dies with the container, which is
  ephemeral. The reporter's fatal path deliberately waits for
  the next run ("A fatal error's report waits for the next
  run"), and a dedicated server has no next run in the same
  container. The previous-session log scan at boot also reads
  a fresh container filesystem, so yesterday's crash log is
  gone.
- **CR7.** Web and Android engine crashes leave no log file
  at all, so the boot scan finds nothing there either.

Detection today is the leak-sweep's deployment-age signal
only if a deployment outlives about 2 h
(`H37_systems_audit.md` 3.4).

Any fix that changes the game server ships with a
game-server image (Edgegap), so this is design only here.

## Options

1. **Flush synchronously before a fatal quit.** On the
   server role, `report_crash(is_fatal)` awaits the send
   before the process exits. Cost: small client change, but
   it cannot cover engine crashes (no GDScript runs after
   `OS.crash` or a segfault), which are the crashes that
   matter most on servers. Partial.
2. **Container supervisor posts the log after exit.** The
   image's entrypoint runs Godot under a small supervisor;
   on a non-zero exit it tails the server log, builds a
   crash report (same redaction and signature rules,
   `crash_report_text.gd` semantics ported or shelled to a
   tiny helper), and posts it to the `crash_report` RPC with
   the container's `NAKAMA_HTTP_KEY`. Cost: an entrypoint and
   a poster in the image, plus keeping its redaction in step
   with the client's. Covers engine crashes, because the
   supervisor survives them.
3. **Record abnormal exits allocator-side.** The runtime's
   allocator already learns deployment outcomes; a deployment
   that ends without `match_end` or a clean deregistration
   writes a synthetic crash report (signature from exit
   status). Cost: platform-side only, but it knows nothing
   of the log, so reports carry no excerpt or stack, and
   distinguishing a crash from an Edgegap kill needs the
   deployment status Edgegap reports.
4. **Persist the queue outside the container.** No per-match
   volume exists on Edgegap; would need a queue upload on a
   timer, which is option 2 with worse timing.

## Recommendation

Option 2 for the crash itself, with option 3's signal as
the counting backstop: the supervisor posts the real log
excerpt (server budget, SP61, applies), and the runtime
counts deployments that vanished mid-match so
prod-health-check can alert even when a post fails. Do not
do option 1 alone: it only covers the fatal path that
already reaches GDScript. CR7 stays open for web (a JS
`window.onerror` hook into the same queue shape) and
Android (a signal handler is engine work) as separate
follow-ups.

## How it would be tested

- Local Docker: run the image against the mock-deploy
  stack, kill the server process mid-match with SIGSEGV
  (`kill -SEGV` cannot fake the engine text; use the
  harness's crash probe or a debug build's `OS.crash`),
  assert exactly one `crash_report` row with role `server`
  and a redacted excerpt lands in the local runtime.
- A clean exit posts nothing; a non-crash non-zero exit
  posts at most one report.
- The compliance suite gains a server-role case next to
  `test_crash_report.gd`.
