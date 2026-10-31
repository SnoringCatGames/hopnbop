# H104: Claude's review of Muse's runs (H103, H109)

Claude reviews what Muse landed in run 1 (H103) and run 2 (H109) in
three stages: security first, then the client and server work, then the
Tier D design docs. Muse implements and Claude reviews. Review agents
report their findings to the coordinating session, which files them in
the right ledger and sends the fixes to Muse.

## Stages

1. **Security** (2026-10-30, two agents in parallel; done at 08:02,
   its findings filed as SP83 to SP94 and H113 to H117, and fixed in
   H120):
   - **A:** SP32, SP33 and SP44 (they share hopnbop c5a189c8 and
     e65cb159), then SP36 and SP41.
   - **B:** SP42 with H60 (they share hopnbop 49a329be), then SP43,
     SP47 and SP59.
2. **Client and server** (H109 Tier C): H54 with SP40, H90, and H86
   with SP61. Not started. It waits on usage: work pauses at 95% of the
   weekly limit.
3. **Tier D design docs:** H87, H72 and H98. H56 is built, and its code
   was reviewed as H111 and H112. Not started.

## Finding the commits

Every Muse commit carries a `Muse-Session:` trailer. To list the
commits for an item ID:

    git -C <repo> log origin/main -E --grep Muse-Session --grep '<ID>([^0-9]|$)' --all-match --format='%h %s'

The repos are hopnbop (this checkout), the platform at
`third_party/snoringcat-platform` and netcode at
`addons/rollback_netcode`. The submodule checkouts sit at their pinned
SHAs, so read them by SHA or as `origin/main:<path>`, not from their
working trees.

Stage 1's commit map (2026-10-30):

| Item | platform | hopnbop |
|---|---|---|
| SP32 | 44d9fd8 79a17ce | c5a189c8 e65cb159 |
| SP33 | 0499a41 e28e77f 8cf642b | e65cb159 |
| SP44 | c8013fb b2eb9cd | c5a189c8 |
| SP36 | 90ec6d4 475d22a | 44e392ab |
| SP41 | 703400e 69c4b6b | 2cd7c650 |
| SP42 | 3975289 d37393f | 3e23aff0 49a329be |
| H60 | | 49a329be afe43e21 |
| SP43 | 752c4d3 22055ff | 8736e088 |
| SP47 | d33ebf3 4ccc33b | b2983b69 |
| SP59 | f2d4469 fcd92d4 3c65a1e | 6f0c2c7a |

Some of these commits only touch a ledger; skip those. A later commit
that changed the same code may not mention the item's ID, so also run
`git log origin/main -- <file>` on each file you review.

## What to read per item

- **The item's ledger entry.** For the platform, read
  `origin/main:LEDGER.md` and `origin/main:docs/ledger_done.md`. For
  hopnbop, read `LEDGER.md` and `docs/ledger_done.md`. Follow the
  entry's pointer to the audit or design doc that names the hole.
- **Leads from Claude's first pass:** section 5 of
  `docs/design/H103_muse_backlog.md`, in Claude's 2026-10-29 entry.
- **The code:** the diffs first, then the surrounding code as it now
  stands on `origin/main`.

## What to check

- **Does the change close the hole?** Test it against both a hostile
  client and an unauthenticated caller.
- **Can it be bypassed?** Look for:
  - another RPC or route that reaches the same data;
  - a check that only runs on the client;
  - a user ID read from the payload instead of the session;
  - a limit that is applied only after the work is done.
- **Is the check enforced on the server?** A client-side check is UX,
  not security.
- **Does it break the released 0.56.0 client?** Breaks are allowed only
  where H108 allowlisted them: see
  `.github/compliance/released-known-failures.txt` and
  `docs/design/H108_compat.md`.
- **Would its tests fail without the fix?** A test that passes either
  way proves nothing.
- **Errors and logs:** no secrets, tokens or personal data in messages
  or logs. Failures fail closed.
- **New limits** (sizes, rates, counts): enforced on the server, with
  sane values, and the client handles the rejection.

## Rules

- **Read-only.** Don't edit tracked files, commit, push or stash.
- **Nothing touches production:** no deploys, no
  `sync-game-config.ps1`, no `register_game`, no requests to prod
  hosts.
- **Local unit tests are fine:** `go test` under the platform's
  `runtime/`, or a GUT file run through
  `Godot_v4.7.2-stable_win64_console.exe`. Plain `godot` run from
  PowerShell prints nothing.
- **Read code through the shell:** `git show <sha>`,
  `git show origin/main:<path> | Select-Object -Skip <n> -First <m>`,
  and `Select-String`. Use no helpers or subagents.
- **Report as you go.** Write your report to
  `.claude/probes/H104/stage1-<A|B>.md` (untracked) and update it after
  each item, so a stop loses nothing.
- **Report format:**
  - For each item: the commits you reviewed, then a verdict (OK, or
    findings).
  - For each finding:
    - its severity: critical, high, medium, low or nit;
    - its location as `file:line`;
    - the concrete failure: the inputs or state, then what goes wrong;
    - the fix you would make.
  - Say what you verified and what you inferred.
  - End with a `Ledger items` list (each finding as a one-line item for
    the repo it belongs to), then your stop line.
- **Stop rule.** Stop when your items are done or two hours after you
  started, whichever comes first. Run `Get-Date` at the start and after
  each item.
  - A compaction is not a stop. After one, re-read this brief and your
    report, then go on.
  - When you stop, finish the report entry you are on and note what is
    left. Then reply with the report's path and its findings in a few
    lines.
