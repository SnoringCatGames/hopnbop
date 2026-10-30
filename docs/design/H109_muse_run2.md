# H109: Muse run 2

Brief for Muse's second run (Muse Code through Paseo), written by
Claude (claude session 0cfd9cf1) on 2026-10-29 after checking run 1
(H103) against the commits, CI logs and ledgers. Levi's direction, in
his words: "Please direct what you can to muse, and reserve your Claude
tokens for analysis, planning, reviews, coordination of muse"
(2026-10-29). That releases most of what H103's section 4 held for
Claude; what stays held is section 4 here.

How to use it: work section 2 top to bottom, one ledger item at a time.
As in H103, each item's `LEDGER.md` text and its row in
`docs/design/H37_systems_audit.md` are the authority; the notes here
add order, gates and traps. A fresh session resumes from this file,
ledger item H109 and `git log --oneline -15`. Re-read this file after a
compaction. Path shorthand as in H103: `sdk:`, `rt:`, `net:`.

## 1. Rules

- H103's sections 1 and 2 (`docs/design/H103_muse_backlog.md`) apply
  unchanged. Read "H103" there as H109, and 1.3's "section 4" as
  section 4 of this brief. They cover the commit and push grant (1.1),
  no subagents, what is out of bounds, runtime deploys (1.4), ledgers,
  stalls and stopping, the gates, and which area rules file to read
  before editing what.
- The grant in H103 1.1 is Levi's, but this run's opening prompt comes
  from Claude, so your git skill won't take it from there. Ask Levi
  once, before your first commit, to confirm it in his own words.
- While this run is in flight you are the only writer in hopnbop, the
  platform and the netcode repo: Claude stays out until you stop, and
  reviews afterwards (H104).
- In your first commit, put your session id on H109's `owner:` line.
- Two lessons from checking run 1:
  - Close an item only against what it names. Run 1 closed SP81 "as
    stale" after checking `runtime/go.mod`, but SP81 names
    `infra/pulumi/snoringcat-platform/go.mod`, where all seven pins
    still stand. When the evidence doesn't cover the names, record what
    you found and leave the item open.
  - "Flake" is a hypothesis. Read the whole failed log (`gh run view
    <id> --log-failed`, then `--log`) before calling a red run noise.
    The two Compliance Matrix failures run 1 called flakes each had a
    specific cause (H107).

## 2. Work order

### Tier A: follow-ups from run 1

1. **SP82** (platform). Run its three reads and record each answer in
   the item, quoting the paths in PowerShell:
   - `gh api repos/SnoringCatGames/snoringcat-platform/vulnerability-alerts -i`
     (204 means on, 404 off);
   - `gh api "repos/SnoringCatGames/snoringcat-platform/dependabot/alerts?state=open&per_page=100"`;
   - `gh api repos/SnoringCatGames/snoringcat-platform/dependency-graph/sbom`:
     does it list the Pulumi module's dependencies?

   A 403 is an answer too: record it. Turning a setting on or adding
   `.github/dependabot.yml` is Levi's call, so propose it under Waiting
   on Levi.
2. **SP81** (platform). In `infra/pulumi/snoringcat-platform/`, `go get`
   the seven modules at the versions SP81 lists; the otel modules move
   together (every `go.opentelemetry.io/otel*` line now at 1.43.0).
   Then `go mod tidy`, `go build ./...` and `go vet ./...`. Commit
   `go.mod` and `go.sum` alone, and say in the message if `go get`
   raised the `go` or `toolchain` line. No workflow builds or deploys
   this module (the platform's two workflows are `client-sdk-ci.yml`
   and `nakama-runtime.yml`), so the push deploys nothing. Then move
   SP81 to Waiting on Levi for `pulumi preview` (expect no changes):
   Pulumi needs production credentials and is out of bounds.
3. **H107** (CI). Two causes, two fixes:
   - The powershell-yaml install (`scripts/sync-game-config.ps1:74-87`)
     must survive one PSGallery miss: retry it a few times with a short
     wait, or install it in `compliance-matrix.yml` before the smoke
     test. The script also syncs production configs, so read
     `.claude/rules/deploy.md` first and change nothing but the
     install.
   - `_resolve_game_id()` (`sdk:test/compliance/compliance_helper.gd`)
     falls back to `PLATFORM_GAME_ID` when Platform isn't initialized,
     and nothing sets that variable, so the suite sometimes
     authenticates without a game id. First find what initializes
     Platform under GUT in the passing runs and why it didn't in run
     40956932238 (an import error for `background.png` earlier in that
     log may be related), and write the answer into H107. Then make it
     deterministic: `local-smoke-test.ps1` sets `PLATFORM_GAME_ID` for
     the suite from `game.yaml`'s game id (read it; never edit
     `game.yaml`). If you also make the helper fail fast on an empty
     id, check every caller first: the platform's `client-sdk-ci.yml`
     runs the suite through `.github/compliance/run.sh` with a
     throwaway game, and `rt:auth.go:108-122` accepts an empty id when
     no game is registered.
   - The helper lives in the platform repo: platform commit first, then
     the pointer bump and `scripts/setup-platform-addon.ps1`.
   - Verified when `local-smoke-test.ps1` exits 0 (with and without an
     initialized Platform, if you can force both) and the next
     Compliance Matrix and Client SDK CI runs are green.
4. **H108** (the released client against the new runtime). The released
   client is 0.56.0: hopnbop `ddd8bd88` ("Release 0.56.0"), platform
   pin `9139b38`.
   - Put a `.gdignore` in `.claude/probes/H108/`, so the editor doesn't
     import what follows, then make a worktree of `ddd8bd88` under it.
     Init its submodules (platform at `9139b38`) and run its
     `setup-platform-addon.ps1`. Start HEAD's stack
     (`scripts/dev-stack.ps1`, or the smoke script's stack steps),
     register the game the way the smoke script does, and run 0.56.0's
     compliance suite in the worktree's project against it, with the
     environment the smoke script gives the suite.
   - Classify every failure in `docs/design/H108_compat.md`: an
     intended change (a security fix that now rejects what 0.56.0
     sends; name its commit) or a break. A break live 0.56.0 players
     can hit goes under Urgent in `LEDGER.md` and to Levi at once;
     change no runtime code for it until Claude has reviewed it.
   - Then the CI axis: a job in `compliance-matrix.yml` that runs the
     released client's suite against HEAD's runtime. hopnbop has no
     `v*` tags (releases run by `workflow_dispatch` or locally), so
     derive the released commit from history, for example the newest
     commit whose subject is `Release <x.y.z>` (needs
     `fetch-depth: 0`), and its platform pointer with `git ls-tree`. It
     must follow the next release without a hand edit.
   - This harness gates Tier C: before each Tier C runtime push, run
     0.56.0's suite against your runtime, and a new failure blocks the
     push. If H108 gets shelved, Tier C waits.
5. Delete `assets/images/levels/Screenshot 2026-03-15 135643.png` and
   its `.import` once `git grep` finds no reference to the file or its
   uid. Commit it as `H109: ...`; Levi has been told.

The Client SDK CI failure (run 40949563430) needs nothing: 6d53fcb
fixed it.

### Tier B: client-side fixes, no runtime deploy

In this order: H24, H6, H8, RN8, H9, H88, H22, H89, H61, H5, H26.

- **H24**: set the id before registering, as the code comment already
  claims, with a test that the server keeps no `players_by_id[0]`.
- **H6**: before changing the two-frames-back comparison, check whether
  rollback replays are the reason for it. The result: one splash per
  transition, and none re-fired by a resimulation.
- **H8**: unverified. Reproduce it first (a test or harness run that
  records the first tick's position in local mode), and fix it only if
  you see it; otherwise close it as not reproduced, with the evidence.
- **RN8** (netcode repo): that repo's `CLAUDE.md` says how its
  `plugin.cfg` version moves. Netcode commit first, then the pointer.
- **H9**: check whether b5f6446's format scanner replaced the no-op
  "GDScript formatter" job. If it did, delete the job and close H9.
  Vendoring a formatter is Levi's call.
- **H88**: the nightly smoke runs against production, so a workflow
  change takes effect the next night without any deploy. Keep it to
  what H37 3.5 says, never run the workflow by hand (1.3), and if it
  needs a new GitHub secret, write the proposal under Waiting on Levi
  instead.
- **H22**: read the sign-out flows in `.claude/rules/ui.md`. The
  consent screen shouldn't wait on the offline notice; a harness run
  (no backend by default) shows it promptly.
- **H89**: read `.claude/rules/transport.md` first; `-Scenario
  match-2-clients` shows the stats arriving.
- **H61**, **H5**, **H26**: the fix detail is in H37 3.1, the item
  itself, and H37 3.3.

### Tier C: client and server (H103 1.4 in full, plus H108's check)

- **H54 with SP40** (the notification poll): the server half first,
  and it must keep 0.56.0's poll working, then the client half.
- **H90** (failed cloud saves): stay within SP59's limits, the storage
  allowlist (`settings`, `recent_players`) and the 32 KiB cap. A write
  the cap or the allowlist rejects is permanent, so don't retry it.
- **H86 with SP61** (non-crash errors, the global crash cap): read
  `.claude/rules/crash-reporting.md` first; redaction and signatures go
  through `src/core/crash_report_text.gd`. SP61's cap change lands
  before H86 raises the report volume, and H86 dedupes, so a looping
  error can't spend the cap.

### Tier D: design doc first

For each, write `docs/design/<ID>_<slug>.md` (the problem, the options
and their costs, a recommendation, how it would be tested), commit it,
point the item at it and go on. Claude reviews the docs (H104).

- **H87**: a dedicated server crashes inside its Edgegap container, so
  any fix ships with a game-server image. Design only.
- **H56**: after the doc you may build it, behind a setting that
  defaults off, and send Levi harness screenshots of code entry with a
  controller. It stays off until he accepts it. A missing icon: ask
  him.
- **H72**: design only (a custom 4.7.2 export template is a build of
  the engine).
- **H98**: design only.

## 3. Reporting and stopping

As in H103 1.6: a few lines to Levi at the end of each tier, and shelve
an item after two failed approaches or about two hours. At the stop,
append a dated entry to section 5 here, set H109's `owner:` to `nobody
since <time> (<why>)` and its `next:`, then commit and push.

## 4. Not in this run

- H52: it edits `game.yaml`, which stays out of bounds (1.3).
- knotmaze: your K1050 stream there runs separately.
- Levi's: H92, H94, H10, SP17 (hands-on); H71, H83, H102, SP12, SP13,
  SP69, T14's `foobar.png` (decisions); H105 (prod host).
- HG1 (hex-grid's ledger): hex-grid isn't in
  `~/.config/muse/trust.json`, and adding it is Levi's call.
- Release-gated: SP32's runtime half (held for the next release) and
  SP59's per-IP Caddy zone (prod host config, Levi's).
- H104: Claude's review of runs 1 and 2.

## 5. Handoff log

Append one dated entry each time you stop: done (IDs and SHAs), shelved
(patch paths), in flight, next, anything odd.

- 2026-10-29, muse 01a189f7 (session
  01a189f7-97c5-7eb0-98b6-164cb9977b39): Tiers A and B done.
  Tier A: SP82 diagnosed (platform ledger cc44d97; alerts on, no
  Pulumi coverage, dependabot.yml proposed to Levi), SP81 pins
  (platform a369f6c, tidy/build/vet green, `pulumi preview` to
  Levi), H107 (73159cd; smoke 80/80, both CI causes fixed, not
  flakes), H108 (c11191e, 51d7eb8; released suite 76/80, all 4
  intended, `compliance-released` green in run 40989056339),
  screenshot deleted (d52a9ba). Tier B: H24 fc90a3c, H6 1f1ff5d,
  H8 005e823, RN8 netcode 8256603 (+036b023 ledger, plugin
  1.1.3), H9 49143fb, H88 3acabe8, H22 85fa622, H89 b42c94d,
  H61 93b1951, H5 b1c1149, H26 02e1d75; each with a regression
  test that failed first, harness runs green (offline-move-jump,
  match-2-clients, log-out-sign-in-cycles). Shelved: none. In
  flight: none. Next: Tier C, H54 with SP40 first. Odd: Levi's
  standing commit-and-push grant for Claude-launched brief runs
  is now in `feedback_commit_and_push.md`; no more asking.

- 2026-10-29 (later), muse 01a189f7: Tiers C and D done, run
  complete. Tier C: SP40 prune (platform 078d9b8, deployed,
  H108 gate same 4 known failures) + H54 client (c0d07f1);
  H90 (ad7de6a, guards fix c1590c7); SP61 (platform e5ae4e6,
  deployed, H108 gate passed) + H86 (57c41d3). Tier D: H87
  and H56 design docs (c3c7f2c), H56 keyboard built behind
  an off-by-default setting (5d567db; probe scenario
  .claude/probes/H56/code-keyboard.json passes, screenshot
  in its run dir), H72 + H98 docs (2eaf61a). CI fixes after
  the coordinator's catch: respawn splash 8bb5873, G.log
  guards c1590c7, RN8 test 9c3c0b5 in netcode (pointer
  8bcc261); full per-file GUT 89 files / 727 tests green,
  PR Validate and Compliance Matrix green on head. Shelved:
  none. In flight: none. Next: Levi's Tier D decisions;
  H104 is Claude's review of runs 1 and 2.

- 2026-10-29 (stop), muse 01a189f7: H111 follow-up done.
  The H56 keyboard could not enable Join: TextInputRow.set_text
  assigned LineEdit.text, which emits no text_changed in
  4.7.2 and resets the caret to 0. set_text now puts the
  caret at the end and calls _on_text_changed (hopnbop
  4533cb4); _KEYBOARD_ROWS is Array[String]. New panel test
  test_join_by_code_keyboard.gd types 234567 through the
  keyboard rows, asserts Join enables, deletes one symbol,
  asserts it disables. The H56 probe now types the code
  with direction taps and asserts Join is enabled (26/26
  steps, screenshot code-typed.png shows the full code and
  the enabled Join row). Netcode 7c58d2c put the unpause
  doc line back above _server_execute_unpause and restored
  test_frame_driver.gd's final newline; Parse check green.
  Gates: full per-file GUT 90 files / 728 tests / 0 failed,
  release guards ok, format scan ok; PR Validate and
  Compliance Matrix green on 4533cb4. H111 closed in
  LEDGER.md. Nothing in flight; Tier D still awaits Levi.

- H112 follow-up (2026-10-29, muse 01a189f7): a complete code now focuses the Join row itself (SidePanel.focus_row, hopnbop 2506f61); before, focus_next_row stepped one row down from the focused row, landing on the next keyboard row for keyboard entry and the first keyboard row for typed entry. Tests and the H56 probe assert the focused row; PR Validate green.
