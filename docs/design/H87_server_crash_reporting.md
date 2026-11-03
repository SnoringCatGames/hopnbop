# H87: a dedicated server's crash is never reported (CR1)

## Problem

`CrashReporter` on a dedicated server queues reports into
`user://crash_reports.json` inside the Edgegap container and
sends them with the HTTP key (`crash_reporter.gd`). The hole:

- **CR1.** A fatal error or engine crash ends the process, so
  anything only in the queue is at risk. The reporter's fatal
  path deliberately waits for the next run. The previous
  session log scan at boot also reads the container
  filesystem. Whether either helps after a crash depends on
  what Edgegap does next, which the next section checks.

Detection today counts no server crash. The restarted
container's idle cancel ends the deployment about a minute
after the crash and deletes the match rows (inferred from
the code paths). So neither the leak sweep nor the 24 hour
stale match sweep sees it. The leak sweep (claude-config
`jobs/scripts/edgegap-leak-sweep.ps1`, hourly, about 2 h) is
for deployments that never end. The stale match sweep
(SP58) is for matches that never end. Today's only trace is
two Nakama log lines. The first is the idempotent
re-register. The second is the idle timeout cancel.

Any fix that changes the game server ships with a
game-server image (Edgegap), so this is design only here.

## Before deciding

Crash one server on a dev Edgegap deployment and record
what survives the restart. This check comes first. The
recommendation below depends on it.

- Edgegap restarts an exited container in the same
  deployment (verified: `edgegap_server_provider.gd` says
  so, and the restarted server re-registers). The runtime
  logs that as an idempotent re-register. The server then
  idles for 60 s and cancels with idle_timeout. That cancel
  deletes the registration and match rows.
- The open check is whether the restart keeps the
  container's writable layer, so a marker file written
  before the crash is still there after. Also record
  whether the restart keeps the request id and the
  connection info, which the counting signal in option 3
  needs.
- If the layer survives, the existing boot scan
  (`crash_reporter.gd`, `scan_previous_session_logs`) already
  reports a crash that printed its marker, and CR1 is much
  smaller than this doc first said. If it does not, the
  original claim holds and only a post-exit step can read
  the log.
- The local test does not cover this path. The local
  allocator runs with `AutoRemove: true` and no restart
  policy, so local Docker never restarts (verified).

Levi, or whoever runs the dev deployment, can run this
check. Edgegap's public documentation answers part of it
(read 2026-11-02, so documented, not verified):

- The restart is a per-version setting, Process Restart
  Policy (Apps and Versions page, Safety Guardrails).
  Always Restart is the default and restarts on exit 0 and
  on any error exit. Never Restart is Edgegap's
  recommendation and stops the deployment on either. Restart
  On Crash restarts on error exits only. This repo does not
  record the hopnbop version's value, and the first bullet
  above rests on a code comment, so read the value from the
  dashboard before relying on it. Under Never Restart a
  crash would stop the deployment, with no re-register, no
  boot scan and no idle cancel.
- The Deployments page says a crashed server process is
  restarted automatically. Its WSS note says an uncaught
  exception restarts "the deployment's container" and that
  server state may be lost, and the Persistence page says
  crash handling depends on the policy. No page says
  whether the writable layer, the request id or the
  connection info survive, so those three stay open.
- Edgegap's container logs are a dashboard view, deleted
  when the deployment stops unless the version has external
  log storage (Deployments page, Container Logs). They are
  no fallback for a crash report, which favors option 2.
- Not read: the API reference. Whether an endpoint reports
  a restart count or an exit code is unchecked.

## Options

1. **Flush synchronously before a fatal quit.** On the
   server role, `report_crash(error_message, is_fatal := false)`
   awaits the send before the process exits. Cost: small
   client change. It cannot cover engine crashes. No
   GDScript runs after `OS.crash` or a segfault, which are
   the crashes that matter most on servers. Partial. The
   rerun in option 2 makes this one unnecessary.
2. **Rerun the same binary in a report-only mode.** The
   image's entrypoint runs Godot under a small supervisor.
   On a crash exit the supervisor runs
   `/game/hopnbop_server.x86_64` once more under `timeout`
   with a new report-only flag. In that mode the binary
   skips server start and `register_server`, sets
   `forced_role = "server"`, runs
   `scan_previous_session_logs()` and `flush()`, then
   quits. Verified: the scan, the dedupe and the role code
   exist. Inferred: that no other autoload does network work
   before the flag can stop it. Check this when building it.
   The container filesystem lives as long as PID 1 does, and
   the second boot rotates `godot.log` to `godot<time>.log`.
   The existing scan therefore finds the marker. File
   logging is on for desktop exports by default.
   `project.godot` sets `max_log_files=3`. The rerun also
   sends a fatal error's queued entry. Redaction, signatures,
   the payload cap and the HTTP key path are then identical
   by construction. Porting `crash_report_text.gd` would mean
   two redaction and signature implementations that must stay
   in step forever, alongside the runtime's third near copy.
   The rerun records the log in its handled set, so a restart
   that keeps the layer does not report it twice. A shell
   poster would not record it, so a restart could report it
   again. The cost is a small GDScript flag plus about ten
   lines of entrypoint shell.
   The entrypoint is `infra/game-server/entrypoint.sh`. It
   now `exec`s Godot as PID 1. Curl and jq are already in the
   image, so a shell poster would be a few lines. Dropping
   `exec` changes PID 1 signal handling. Today, TERM to PID 1
   is ignored, because Godot installs no TERM handler
   (inferred for 4.7.2). The stop falls back to SIGKILL
   after the grace period. A bash supervisor as PID 1 is
   likewise deaf to TERM unless it traps it. If it traps TERM
   and forwards it, the exit rule below must exclude the
   resulting exit. Name the signal plan when building it.
   The poster must never print the request. The RPC key
   travels in the query string, and the container's stdout
   goes to Edgegap's logs. The rule is no `set -x`, no
   `curl -v`, never log the URL. The runtime's re-redaction
   is the backstop.
   Post only when the log has a crash marker or the exit is
   SEGV, ILL, FPE, ABRT or BUS. Never post for exit 0 or
   after a stop signal the supervisor itself received.
   Every normal end stops the deployment. A supervisor that
   forwards TERM sees Godot exit with status 143. At one
   report per match, that drains the 200 per day server cap
   and buries real crashes. The rerun gets this rule for
   free, because the scan needs a marker. What stays
   uncovered is an OOM SIGKILL (137, no marker) and hangs.
   Only the counting signal and the sweeps see those.
3. **Count restarts from the re-register signal.** The
   runtime already sees a restarted server. The register
   RPC takes the idempotent branch for a request id that is
   already registered. That needs no Edgegap deployment
   status API and no image change. The fix is a counter, or
   one synthetic `crash_reports` row with role `server`
   written from that branch, which prod-health-check already
   reads by role. This only works if the restart keeps the
   request id and the connection info. Check that in the
   Before deciding step. The claim that the runtime's
   allocator already learns deployment outcomes is
   unverified. No such code was found.
4. **Persist the queue outside the container.** No per-match
   volume exists on Edgegap. It would need a queue upload on a
   timer, which is option 2 with worse timing.

## Recommendation

The recommendation depends on the Before deciding check.

If the restart keeps the writable layer, the boot scan
already covers the crash itself. Ship only the option 3
counter as the backstop, so prod-health-check can alert
even when a post fails. The server budget (SP61) applies.

If the layer does not survive, ship option 2 for the crash
itself, with option 3's counter as the counting backstop.
The supervisor posts the real log excerpt. The runtime
counts deployments that vanished mid-match. Do not do
option 1 alone. It only covers the fatal path that already
reaches GDScript.

Either way the `crash_report` RPC contract is unchanged,
so the released clients are unaffected (inferred).

CR7 is not part of this item. Web and Android engine
crashes leave no log file at all, so the boot scan finds
nothing there either. They need their own items. Web needs
a JS `window.onerror` writing to localStorage, since
GDScript cannot run after a WASM abort (inferred). Android
is engine work.

## How it would be tested

- Entrypoint level Docker case. Run the image against the
  mock-deploy stack. A crash posts exactly one
  `crash_reports` row with role `server` and a redacted
  excerpt in the local runtime. A stop posts none. This is
  the case that fails today. The compliance case for the
  server role already exists and passes without the change,
  so do not add another one like it.
- A GUT case for the report-only mode. It runs the scan and
  flush and quits without starting a server.
- Use `kill -SEGV <pid>` as the crash fixture. The Linux
  handler prints the crash text for a sent signal too
  (inferred for 4.7.2). Use `kill -ABRT` (no handler, so no
  marker) or `kill -KILL` as an exit without a marker. No
  shipped code calls `OS.crash`, and it is not debug only.
- A clean exit posts nothing. A non-crash non-zero exit
  posts nothing unless the marker or signal rule above
  matches.
- The local Docker test does not cover the Edgegap restart
  path. Say so in the test.

Size: M.

Ship server crash reports (rerun mode plus restart
counter, about M) with the next game-server image?
