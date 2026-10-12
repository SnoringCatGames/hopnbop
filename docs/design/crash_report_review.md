# Crash reports: review notes for the H1 rewrite

Review of the crash-report contract in the H1 rewrite. The rewrite sits
uncommitted in worktree `.claude/worktrees/agent-a1d23375521d94902`:
`src/core/crash_reporter.gd` + `crash_report_text.gd` and the platform
`runtime/crash_report.go`. A parallel pass (knotmaze session, 2026-10-11)
read that contract while designing the same RPC, then stopped so as not to
duplicate it. These are its findings for whoever lands H1. Nothing here is
implemented.

The contract as read: the client sends `game_id`, `game_version`,
`protocol_version` (int), `platform`, `os`, `role` (client/server),
`message` (500 chars or fewer), `signature` and `log_excerpt` (6000 chars
or fewer). Dedicated servers report keyless through the HTTP key
(`rpc_async_with_key`). The runtime rejects payloads over 16 KiB, allows
5 reports per player per hour, and returns INVALID_ARGUMENT (3) for a
final reject and RESOURCE_EXHAUSTED (8) when rate limited.

## Abuse and auth

1. **The HTTP key is public.** It ships in the .pck. A keyless
   (role=server) call needs a payload `game_id` that names a registered
   game, a NULL user_id, and its own small hourly cap.
2. **Derive `role` from how the call authenticated, not from the
   payload.** Keyless means server; a session means client. Otherwise a
   session client can claim to be a server, and anyone with the key can
   claim to be a client.
3. **Add a global cap.** Device accounts are free to create, so a
   per-user limit of 5 an hour doesn't stop a flood. Age-based pruning
   alone still lets a sustained flood fill several GB (about 4 GB at
   120 an hour for 90 days with 16 KiB rows), so the pruner also needs a
   hard row or size cap.
4. **Document that rate limits reset on restart.** In-memory limiters
   reset every time Nakama restarts, and every runtime deploy restarts it.
5. **Session callers:** take `game_id` from the session vars
   (`requireGameID`), not from the payload.
6. **Validate every string on the server:** the signature's format and
   length, `game_version`, `os` and `platform`. Apply the 16 KiB check to
   the payload string the RPC receives. The HTTP body is that string
   JSON-escaped a second time, so it is larger.

## Privacy

7. **Storing the session's user_id makes each row personal data.** That
   means:
   - `delete_account`'s cascade must delete the rows. Its SQL scrub
     covers only Nakama storage today.
   - `export_player_data` must include them, capped.
   - Rows written during the 30-day grace window must go on hard delete.
     A foreign key to `users(id)` with `ON DELETE CASCADE` does this.
   - The client's doc line "carries no account, device, or player
     identifiers" becomes misleading, because the server links each row
     to an account.
8. **If the rows are Nakama storage objects instead,** GDPR delete and
   export come for free. But the export runs
   `ORDER BY collection, key LIMIT 1000`, so a crashy player's reports
   could push the rest of their data out of it. Cap the rows per player.
9. **`log_excerpt` redaction gaps.** Only the current account's values
   are redacted. That covers the device id (`local_player_id`) but misses
   these:
   - **Old tokens.** Logs written before platform SP5 (76a9572) hold
     nakama-godot DEBUG lines with bearer and refresh tokens and the
     server key. The previous-session scan reads up to 1 MiB of such a
     log, and tokens that were refreshed since won't match the current
     values. Redact JWT-shaped strings (`eyJ...`) and token/key fields by
     pattern.
   - **Another account's credential.** `matchmaker_api_client.gd:653`
     prints `Preview device_id=%s`, and a device id logs that account in.
   - **OS user names in paths:** `C:\Users\<name>`, `/home/<name>`,
     `/Users/<name>`.
   - **IPs and signaling URLs,** wherever the game logs them.

## Rollout and behavior

10. **Land the runtime before the client.** If the RPC isn't registered,
    the client counts a send as FAILED: five attempts over about 15
    minutes of backoff, then it drops the report. The runtime
    auto-deploys on push to platform `main`.
11. **Send when it happened.** Queued reports can arrive up to 7 days
    late, and the entry's `created_at` isn't in the payload. Send it as
    `occurred_at`. The server keeps `received_at` as the authoritative
    time and clamps `occurred_at`.
12. **The global cap pauses everyone.** RESOURCE_EXHAUSTED from it pauses
    every legitimate client for 10 minutes during a flood. Log or count
    cap hits so a flood is visible.
13. **Server reports need the HTTP key in the game-server
    environment.** Check that the Edgegap and local-allocator deploys
    pass `NAKAMA_HTTP_KEY`. Without it, dedicated servers silently queue
    nothing.
14. **Somewhere to read the reports.** Nothing surfaces crash counts
    yet. Put them where Levi already looks every day: the morning
    follow-ups digest, or a daily job.

## Platform repo hygiene (filed as platform SP9-SP11)

15. **The platform's CLAUDE.md is stale.** It says "No custom tables",
    but the `games` table exists, and its Runtime modules list will need
    the new file. It also says CI runs gofmt, but `nakama-runtime.yml`
    runs only go vet, go test and staticcheck. Several committed runtime
    files aren't gofmt-clean: friends_limits.go, runtime_status.go,
    player_data.go, main.go and per_game_config.go. Running a blanket
    `gofmt -w` in the crash-report commit would reformat unrelated files.
