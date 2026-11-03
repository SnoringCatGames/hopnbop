# H126: Muse run 7, three platform follow-ups from the run 6 review

Brief for Muse's seventh run (Muse Code through Paseo), written by Claude
(claude session 0cfd9cf1) on 2026-11-02. Claude sends it, not Levi.
It holds the platform ledger items the review of run 6 (H125) left:
a missing test (SP110), a registration the one-list test cannot see
(SP111), and a cancelled deletion that leaves the account nameless
(SP113).

**You commit locally and you do not push the platform.** A push to the
platform's `main` that touches `runtime/**` deploys the Nakama plugin to
production, and Levi has not OK'd these deploys. Claude asks him after
you stop and pushes one commit at a time. Everything else in H103 and
H125 holds.

How to use it: section 1, then section 2's items in order. A fresh
session resumes from this file, ledger item H126 and
`git log --oneline -15` in hopnbop and the platform. Re-read this file
after a compaction. Path shorthand: `rt:` is
`third_party/snoringcat-platform/runtime/` and `sdk:` is
`third_party/snoringcat-platform/addons/snoringcat_platform_client/`.
This file is the authority; a Paseo message changes it only when the
message says so.

## 1. Rules

- H125's section 1 applies, with H126 in place of H125. It carries
  H123's and H120's rules and, through them, H103's sections 1 and 2:
  the public-repo rule, the one-writer rule, no subagents, the
  out-of-bounds list, the gates, and a test that fails without the fix.
  The exceptions are below.
- **No platform push, for any reason.** This overrides the commit and
  push grant (H103 1.1) and the push step of 1.4 for the platform:
  commit on its local `main`, run every gate, and stop. No `git push`
  there (not `origin <sha>:main` either), no workflow runs, no tags.
  If a step seems to need a push, stop and say so in the handoff log.
  hopnbop pushes are fine (they only run CI): your one is the handoff
  commit at the end.
- **Three commits, in this order, one per item:** SP110, SP111, SP113.
  Each passes its checks on its own, so Claude can push them one at a
  time. Message `<ID>: <what changed>`, a line or two of why, then
  `Muse-Session: <your session id>`. Take SHAs from
  `git rev-parse HEAD` after the commit.
- **Checks per commit**, in `rt:`: `go vet ./...`, `go test ./...`,
  `staticcheck ./...` (CI pins `honnef.co/go/tools/cmd/staticcheck@2025.1.1`)
  and `gofmt -l .`, which must print nothing. SP111 and SP113 also need
  `pwsh scripts/local-smoke-test.ps1` from hopnbop's root (H103 1.4,
  step 2) and the released-client gate: the compliance suites of 0.57.0,
  the live release (`7fd873fd`), and 0.56.0 (`ddd8bd88`) against your
  candidate runtime, as `docs/design/H108_compat.md` describes. SP110
  changes test files only, so the plugin binary is identical and it needs
  neither. Known failures: H124's section 3 and the two SP106 entries in
  `.github/compliance/released-known-failures.txt`. A failure outside
  those blocks the commit, except the SP113 case in 2.3. A blocked item
  is shelved as a patch (H103 1.6) and the next one goes on.
- **Ledgers.** Don't edit the platform's `LEDGER.md` or the allowlist
  file. Claude closes SP110, SP111 and SP113 with their pushed SHAs and
  lands the allowlist lines with the pointer bump. Put anything new in
  the handoff log and Claude files it. H126's handle is Claude's until
  you stop (see Closing).
- **Staging.** By name, never `git add -A`. Never stage hopnbop's
  `third_party/snoringcat-platform` pointer or `addons/rollback_netcode`:
  the pointer trails the platform checkout on purpose, and Claude bumps
  it after the deploys. The smoke test rewrites files in both checkouts
  (H81): after each run, check `git status` in hopnbop and the platform
  and restore what it changed before you stage anything.
- **Read before editing.** `.claude/rules/testing.md` (GUT and the
  compliance suite), `.claude/rules/gdscript-style.md` (the compliance
  test is GDScript) and `.claude/rules/transport.md` (SP111 moves the
  matchmaker hook). The Go style is `gofmt` plus `staticcheck`-clean,
  with comments in full sentences and no em dashes. After editing any
  `sdk:` file, re-run `scripts/setup-platform-addon.ps1`: the addon the
  smoke test loads is a copy.
- **Stop rule.** Stop when the three commits and the handoff entry are
  done, or after 2 hours of wall clock, whichever comes first: run
  `Get-Date` at the start and at each milestone. A compaction is not a
  stop; after one, re-read this file and `git log` before going on.
  Two failed approaches to an item shelve it. Never commit partial work.
- No client release, no prod requests (Claude does the prod checks), no
  platform change outside these three items.

## 2. Work

Run 6 is accepted: SP107 to SP109 are deployed and green.

### 2.1 SP110: the pending-deletion sign-in test (test only)

The after-authenticate function for Google, Facebook and Steam
(`rt:account_validation.go`, `registerAfterAuthenticateHooks`, the
`work(true, true, true)` calls) first clamps the display name, which
rewrites the `[deleted]` marker of an account whose deletion is pending,
and then runs `enforceSignInPrivacy` (`rt:privacy.go`). Its
`enforcePendingDeletionProfile` puts the marker back with one
`UPDATE users ...` through `db.ExecContext`, guarded by an `EXISTS` on
the account's deletion-queue row. Production ends right, but no test pins
the pair: run 6 covered device, which skips the clamp.

Test, in a new `_test.go` file beside `rt:after_auth_hooks_test.go`
(reuse its `recordingInitializer`, `fakeAfterAuthNk` and `afterAuthCtx()`
as they are or extend them minimally): for each of Google, Facebook and
Steam, an existing account (not just created) that has a pending
deletion and the display name `[deleted]` signs in, and ends with
`[deleted]`.

Seeing the end state needs a stateful pair. The fake nk keeps the
account's name; a `*sql.DB` built on a tiny fake `database/sql/driver`
(standard library only: no sqlmock, no new module) applies the scrub
`UPDATE` to that same account when it is pending. Read the SQL the
sign-in path issues (`clearImportedEmail` too) and make the fake accept
what it must. Add one control, so the fake is not just returning the
marker: the same stored `[deleted]` on an account that is **not**
pending ends with a generated name.

Fails-without-the-fix: temporarily skip the `enforceSignInPrivacy` call
(or the fake's scrub), see the three cases fail, restore, and say so in
the commit message. No production code changes in this item.

### 2.2 SP111: one list that really holds every hook

`registerHooks` (`rt:main.go`, SP109) says it registers every hook the
runtime installs, and `TestNoHookRegisteredTwice` calls it, but
`RegisterMatchmakerMatched` is still called from `InitModule`, inside
the block that builds `alloc := &fleetAllocator{...}`. A second matchmaker
registration would escape the test.

Preferred: move it in. `registerHooks` takes the matchmaker handler (or
the allocator; whichever keeps the test simple), nil when fleet
allocation is disabled, and registers the hook itself. `alloc` is built
from values `InitModule` computes after the current `registerHooks`
call, so this is a reorder, not just a parameter: either build the
allocator earlier or call `registerHooks` after that block. Read
`InitModule` for anything that depends on the order, and keep these
exactly: the hook is registered once when allocation is enabled (a real
`EDGEGAP_TOKEN` or mock deploy), never when it is not, with the same
handler; the `cancel_matchmaking_allocation` RPC stays beside the
allocator; every error that aborts `InitModule` today still aborts it.
Extend `recordingInitializer` to count `RegisterMatchmakerMatched`, make
the duplicate test cover it, and add the disabled case (nil handler: zero
registrations). Prove the extended test: add a second matchmaker
registration temporarily, see it fail, remove it. The smoke stack runs the
mock-deploy allocator, so it exercises the enabled path against a real
Nakama; the disabled path is covered by the unit test alone.

Fallback, only if the reorder turns out to need more than the above
(something else in `InitModule` depends on the hook order): leave
`InitModule` as it is and narrow the comments of `registerHooks` and the
test to say exactly what they cover. Say in the commit message which you
chose and why.

### 2.3 SP113: a cancelled deletion leaves a name

`cancelPendingDeletion` (`rt:privacy.go`) clears the `[deleted]` marker
with `display_name = NULL`, so the account stays nameless until its next
sign-in or session refresh heals it (SP108). Every account has a
generated name (H59), so assign one in the same statement:

- Call `generatedDisplayName()` (`rt:display_name.go`) and set
  `display_name` to the result in the `UPDATE`, keeping the
  `AND display_name = $2` guard: only the marker is replaced.
- If generating a name fails, the cancel still completes: log it and
  fall back to `NULL` as today (SP108's healing covers it). A naming
  error never fails a cancel and never leaves the marker in place.
- Fix any text that says the name stays empty after a cancel: search the
  platform's `PLATFORM_ARCHITECTURE.md` ("Account deletion"), its other
  docs and the `sdk:` comments.

Tests:

1. The compliance suite, `sdk:test/compliance/test_account_delete.gd`,
   has two cancel cases that assert an empty name after the cancel:
   `test_soft_delete_then_cancel_keeps_account_without_profile` and
   `test_cancel_clears_marker_on_account_without_display_name`. Both
   encode the bug. Change them to expect a generated name (not empty and
   not `[deleted]`; match the generated shape if SP107 or SP108 left a
   helper for it) and fix their failure messages. Show the change: run
   the smoke test with the new assertions against the unfixed runtime
   (see them fail), then with the fix (see them pass), and say so in the
   commit message.
2. A Go test too, if SP110's fake driver extends cheaply to the cancel
   transaction (`BeginTx`, the `DELETE ... RETURNING`, the `UPDATE`). If
   it doesn't, say the compliance cases are the coverage and move on.

The released-client gate. The 0.57.0 and 0.56.0 copies of those two cases
still assert the empty name, so they fail against the fixed runtime (one
of them, `test_cancel_clears_marker_on_account_without_display_name`, is
already allowlisted by SP106's entry). Those are the only new failures
acceptable, and only when all of this holds, which you check and record:

- (a) the failing assertions are exactly the post-cancel name checks in
  those cases;
- (b) no other test in either suite fails beyond the known ones;
- (c) a read of each release's SDK shows no client code depends on an
  empty name after `cancel_account_deletion` (the client shows the
  server's profile).

Then do not edit the allowlist. Write the exact `file::test` lines the
gate needs, each with a one-line dated reason, into the handoff log and
into `.claude/probes/H126/allowlist-lines.txt`. Claude lands them with
the pointer bump so hopnbop's CI stays green. If (a), (b) or (c) fails,
do not commit SP113: shelve it as a patch under `.claude/probes/H126/`
and report.

### Closing

Append your handoff entry to section 3. Set H126's `owner:` in
`LEDGER.md` to `nobody since <time> (<why>)`, its `last commit:` to the
newest platform SHA and its `next:` to "Claude reviews the local platform
commits". Commit those two files only (`docs/design/H126_muse_run7.md`
and `LEDGER.md`) and push hopnbop. Then report.

Claude's part afterwards: review the three commits against the code,
ask Levi once for the deploy OK, push one commit at a time with each
`nakama-runtime.yml` run watched to green, bump hopnbop's platform
pointer together with the allowlist lines (and run
`scripts/setup-platform-addon.ps1`), watch hopnbop's CI, and close
SP110, SP111, SP113 and H126.

### Not in this run

- H104's stages 2 and 3 (Claude), SP112's recount (Claude, after
  2026-11-07), and everything Levi owns (SP83, SP92, SP93, H119).
- Any change to `game.yaml`, the version files, or a client release.

## 3. Handoff log

Append one dated entry each time you stop: per item, the local platform
SHA, the checks you ran and what they printed (vet, test, staticcheck,
gofmt, smoke, the 0.57.0 and 0.56.0 failure lists), anything shelved with
its patch path, the SP113 allowlist lines, and anything new for the
ledger.
