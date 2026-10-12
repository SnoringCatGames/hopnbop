# Hop'n'Bop ledger

Open work for hopnbop: follow-ups, known residuals, decisions waiting on
Levi, and ideas. Convention: claude-config `rules/ledger.md`. IDs (`H<n>`)
are stable and never reused. Platform items (SDK, runtime, prod host
scripts) live in `third_party/snoringcat-platform/LEDGER.md`.

Session pointers like "session 530145bc, agent aab30fcb" refer to Claude
Code transcripts under `~/.claude/projects/` (kept 30 days). Each item
states its facts, so it stands on its own after the transcript is gone.

## Urgent

- **H1** · Crash reporting is dead. `src/core/crash_reporter.gd:36` reads
  `G.get("auth_token_store")`, which no longer exists (it is the only
  reference left), so the reporter always takes its no-session path and
  never sends a report. Found by the pr-validate CI agent (session
  530145bc, agent aab30fcb, 2026-10-11 13:52). Still true at 18:20 the
  same day. The server half is missing too: the runtime never
  registered a `crash_report` RPC (the AWS `/telemetry/crash` endpoint
  went with the SAM backend in platform 21e6fb7). In progress as of
  19:00 in this repo's session, worktree `agent-a1d23375521d94902`
  (client rewrite plus runtime `crash_report.go`). Review notes:
  `docs/design/crash_report_review.md`.

## Waiting on Levi

- **H3** · The bunny reappears 1-2 frames before respawn. "Dead" ends on
  a frame count (`character_state_from_server.gd:38-52`), but respawn
  comes from a wall-clock timer (`player.gd:301`). In between, the
  invincibility blink shows the bunny while its collision is still off,
  and in local mode it drifts about 2 px before the respawn records its
  position. Decide whether to align the two. (Session 530145bc, agent
  a6c0fbc6 "Fix death blink and splash", 2026-10-11 ~11:39.)

## In progress

## Next

- **H4** · Before tagging the next release: main is six versions ahead
  of the live web client, and nothing has had a live networked test yet.
  Also confirm that a release build doesn't ship the committed
  `settings.tres` 10 s debug match length (Levi: "that's for debugging
  purposes"; CLAUDE.md documents the committed 10 s match for the test
  harness). (Session 530145bc, report 2026-10-11 12:00 and reply 13:06.)
- **H13** · After H1 lands: nothing surfaces crash reports. Put daily
  counts where Levi already looks (the morning follow-ups digest or a
  daily job). See `docs/design/crash_report_review.md` point 14.

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

## Ideas (not scheduled)

- **H11** · Add a `push: main` trigger to `.github/workflows/pr-validate.yml`.
  Today it runs only on `pull_request` and `workflow_dispatch`, so a
  broken job sits unseen: its GUT job died from 2026-04-29 until
  2026-10-11. (Session 530145bc, agent aab30fcb, 13:52.)

## Done

- **H2** · Local GUT runs loaded the real token store and refreshed that
  session against PRODUCTION Nakama on the first frame; a rejected
  refresh also signed the developer out. Done in the commit that moved
  this item here (2026-10-11): under GUT, in editor builds only, G hands
  Platform `user://test_auth.cfg`, deleted at boot, so every run starts
  signed out. Guarded by `test/unit/core/test_auth_file_isolation.gd`.
- **H12** · `upgrade_levels.tscn` failed to parse (dead ld58 content
  that broke exports). Done in b998107d (2026-10-11).
