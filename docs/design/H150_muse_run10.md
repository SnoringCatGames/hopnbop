# H150: Muse run 10, two poller fixes, the settings-sync design, the H98 pictures

Brief for Muse's tenth run (Muse Code through Paseo), written by Claude
(claude session 0cfd9cf1) on 2026-11-02. Claude sends it, not Levi.
Four jobs, in this order: H140 and H139 (two small fixes in the friends
notification poller), H135 stage 1 (a design doc for the settings cloud
sync bug, no code), and H143 (harness pictures for Levi's two looks at
the H98 doc). Levi decides on the doc and the pictures later. The two
fixes reach players with the next client release, which needs Levi's OK.

How to use it: section 1, then section 2's items in order. A fresh
session resumes from this file, ledger item H150 and
`git log --oneline -15`. Re-read this file after a compaction. This file
is the authority; a Paseo message changes it only when the message says
so.

## 1. Rules

- H103's sections 1 and 2 (`docs/design/H103_muse_backlog.md`) apply:
  read "H103" there as H150, and ignore 1.3's last bullet (this file has
  no section 4). That is the commit flow, the gates, and the table of
  area rules to read before editing. The commit and push grant (H103 1.1)
  stands: Levi gave it in his own words on 2026-10-29, your memory
  `feedback_commit_and_push.md` records it, and it covers runs Claude
  launches from a committed brief, so don't ask again. hopnbop pushes
  only run CI. No subagents or workflows (H103 1.2). You are the only
  writer in hopnbop until you stop.
- **Hands off the platform.** `third_party/snoringcat-platform` holds
  commits that wait for Levi's OK to deploy to production, which is why
  hopnbop's pointer shows as modified and has to stay that way. Reading
  its files is fine. Don't edit, commit, pull, check out, restore or
  reset anything in or under that path, and don't run
  `git submodule update`, `git restore` or `git checkout` on it. Claude
  may push those commits from there, or bump the pointer in a hopnbop
  commit, while you work: if a `git pull --rebase` brings that in,
  carry on. Don't run `scripts/local-smoke-test.ps1` or
  `scripts/setup-platform-addon.ps1`: nothing in this run needs either.
  Never stage the platform pointer or `addons/rollback_netcode/`. Stage
  by name, and `git diff --cached --stat` must show only your files.
- **Where the findings are.** H135's labels (H90-1 to H90-4) are in
  `docs/ledger_notes.md` under `## H135`. Claude's fuller stage 2 report,
  `.claude/probes/H104/stage2.md`, is untracked and on this machine
  only. Read its H90 section (the verdict, the findings, "Verified
  correct") before you write the H135 doc. Its fixes are proposals:
  when you find a better one, do it and say why in the handoff log.
  When a finding is wrong, record why and leave it out. Never commit the
  report or paste its text: write each doc in its own voice.
- **Verified and inferred.** The report labels each claim "verified"
  (read in the code or docs at a SHA) or "inferred" (reasoning, or read
  from the engine checkout at `~/Repositories/godot`, which is 4.4-dev,
  not 4.7.2). Keep that label in the doc wherever a claim still rests on
  an inference; never promote an inference to a fact. A number you
  measure yourself with the harness is "measured"; say how.
- **Public repo.** The docs, the ledger, commit messages and the handoff
  log are public. Say what a design must do. No keys, tokens or
  secrets, and no key values. No prod requests. Where a finding needs a
  fact only production can give, write it into the doc as an open check,
  name who can run it, and move on.
- **Prose.** No em dashes or en dashes in anything you write (a period
  and a new sentence instead). Keep each doc's headings, section order
  and line wrapping. A new doc follows the shape of
  `docs/design/H87_server_crash_reporting.md`: the problem, "Before
  deciding" when something must be checked first, "Options",
  "Recommendation", "How it would be tested", a size, and the question
  for Levi as a plain yes or no.
- **Read before editing code (H140, H139).** You don't load the area
  rules, so read `.claude/rules/gdscript-style.md` and
  `.claude/rules/testing.md`. For H143 also read `.claude/rules/ui.md`
  and `scripts/agent/README.md` (the harness). On Windows run
  `Godot_v4.7.2-stable_win64_console.exe`, not `godot.exe`. Never pipe
  `godot --import` or any long command through `Select-Object`: the
  read times out, Paseo shows you as `error`, and the run looks dead.
  Redirect to a file under `.claude/probes/<item>/` and read the file.
- **A test that fails without the fix** (H140, H139; H103 section 2).
  Run it against the unfixed code and see it fail, then with the fix.
- **Commits.** One per ledger item (H140 may take two, one per defect).
  Message `<ID>: <what changed>`, a line or two of why, then
  `Muse-Session: <your session id>`. Take SHAs from `git rev-parse HEAD`.
  After each push check CI (`gh run list -R SnoringCatGames/hopnbop
  -L 3`); a red run on your commit is the next thing you fix.
- **Ledgers.** Close H140 and H139 in `LEDGER.md` as H103 1.5 says.
  Leave H135, H143, H149 and H150 alone: they are Claude's. Do not file
  anything under `Waiting on Levi`: write each question for Levi into
  your handoff entry, one line each, as a plain question, and Claude
  files them. File anything else new the moment you find it (a
  follow-up, a residual). Claude has set H150's `owner:` line.
- No client release, no version bump, no prod requests, no deploys, no
  `game.yaml` edits (H103 1.3). Tests and the harness stay on loopback.
- **Stop rule.** Stop when the four jobs and the handoff entry are done,
  or after 2 hours of wall clock, whichever comes first: run `Get-Date`
  at the start and at each milestone. A compaction is not a stop; after
  one, re-read this file and `git log` before going on. Two failed
  approaches to an item shelve it (H103 1.6). Never commit partial work.
  Don't start anything this file does not list.

## 2. Work

Order: H140, H139, H135 (the doc), then H143. H140 comes first because
it can leave a signed-in player without their notifications.

### H140: the poller's two edges

Where: `src/core/friends_notification_poller.gd` (the notification
paging near `_notification_cursor` and `cacheable_cursor`, and the two
`Platform.friends.is_poll_busy()` checks, one in the poll loop and one
in the sign-in drain). Tests live in `test/unit/platform/`:
`test_friends_notification_poller.gd`, `test_friends_poller_lifecycle.gd`
and `test_friends_notification_contract.gd`. The ledger text, H134's
leftovers: "a full page with a repeated cursor would page forever, and a
stale in-flight fetch makes is_poll_busy() skip the sign-in drain of the
new session until the next socket connect."

Two defects, two fixes. Read the code, reproduce each in a test that
fails first, and pick the smallest fix that holds. Paging: the loop must
end when a page repeats its cursor, and also stop after a sane number of
pages in one poll (name the cap as a constant). Drain: a fetch left over
from the previous session must not make the new session's drain skip or
wait for the next socket connect. Say in the commit which design you
chose (a session generation, a retry, or something else) and why. If the
platform client addon's `is_poll_busy()` is part of the cause, you may
read it in `addons/snoringcat_platform_client/` but fix this on the
hopnbop side only; if that is impossible, shelve the half that needs it
and write down what the platform change would be.

### H139: the toast id and the dedup file

Where: the same file (`_load_seen_toasts`, `_save_seen_toasts`, and the
code near the `_seen_toast_order` append that caps the list). The
ledger text: "H54-3 rest: a toast id is marked seen before the toast
shows, so a quit in between drops it, and the dedup file is device-wide,
not per account." Find H54-3 with
`Select-String -Path docs/*.md -Pattern 'H54-3'`.

Two defects. Mark an id seen only once its toast has shown (or at the
moment it is shown, in the same frame; say which and why). And key the
seen list by account, so one player's seen ids don't hide another
player's toasts on a shared device. Think through the upgrade: a player
who already has seen ids in today's device-wide key must not get a flood
of old toasts again when the key changes. Say what you chose. The dedup
file's format change must keep working when an older client's file is
read. Tests as above, including the upgrade case.

### H135 stage 1: the settings cloud sync design (a doc, no code)

Write `docs/design/H135_settings_sync_merge.md`. The bug (H90-1, live in
0.57.0): `src/core/settings_cloud_sync.gd` reads a key's absence as a
deletion and saves the whole blob, so a stale device's save deletes
another device's new settings. The ledger says "tombstones and OCC";
the doc decides whether that is right.

It must cover, in this order: (1) what the code does today, with file
and line pointers (verified at the current SHA), and the loss
scenario step by step with two devices; (2) the storage contract, read
from `third_party/snoringcat-platform/` and the client addon (read
only): how the blob is stored, whether a write can carry a version
precondition, and what a conflict returns; (3) options, each with its
effect on the bug and its cost: per-key merge with a timestamp per key
and tombstones, optimistic concurrency on the stored object's version
with a retry-merge, both together, and the small option of never
deleting remotely (absence means unknown); (4) coexistence: released
0.57.0 clients keep writing whole blobs and keep deleting keys they
lack, so say what an old client's save does to any field a new client
adds, and what that means for the format, a new storage key or version,
and the order of releases; (5) a recommendation, with whether to fold
in H90-2, H90-3 and H90-4 and why; (6) how it would be tested (a fake
store, two simulated devices, and the H90-4 note that the tests write
the real `local_settings.cfg`); (7) a size and the question for Levi,
as a plain yes or no. If a product choice is hiding in it (for
example, whether resetting a setting on one device must reset it on
the others), put that in as a plain question too.

### H143: pictures for Levi's two looks (no code committed)

Read the H98 doc (`docs/design/H98_polish_and_player_list.md`), its
two looks, and `docs/ledger_notes.md` under `## H143`. Output goes under
`.claude/probes/H143/` (untracked, on this machine): the harness run
directories, and an index, `.claude/probes/H143/index.md`, listing every
picture's path, which surface it shows, its window size, and what it
should show. A reusable scenario belongs in
`scripts/agent/scenarios/` (tracked, documented in the harness
README, passing); a one-off does not.

1. **T43 surfaces.** Capture each surface the H98 doc lists (toasts,
   game over, friends, auth; `docs/design/H37/h37-triage.md:441`) that
   the harness can reach offline, at the default 1360x765 window. Use a
   `state` step beside each screenshot and check its `screen` name
   matches the surface, and that the picture file is not blank. A
   surface that needs a backend you may not run (the friends and auth
   screens may), you don't fake: record in the index that it needs one,
   and why.
2. **T19 before pictures.** The player list as it is now, at four and at
   eight displays, in the wide layout (the default window) and a narrow
   one (`-WindowSize`; the HUD hides the horizontal list at aspect 1.3
   or more). Make the displays the way the H98 doc's measured table was
   made; the H142 handoff log in `docs/design/H142_muse_run9.md` names
   the source runs. Do not build the H98 options as prototypes in this
   run: write in the handoff how a prototype could be captured without
   touching the main checkout (a throwaway worktree needs the submodule
   copies and the import cache; say what it would take), and Claude
   decides.

Cap H143 at 45 minutes.

## Closing

Close the items (H103 1.5). Then append your handoff entry to section 3:
done, with SHAs; shelved, with patch paths; for H140 and H139 the design
you chose and what the failing tests showed; the H135 doc's open
questions; the H143 index path and what each picture should show; the
questions for Levi (one line each); anything for Claude to file. Commit
and push.

## 3. Handoff log

Append one dated entry each time you stop.

- 2026-11-02, muse 01a19fe1-3736-7912-979b-324d3ce8ceab
  (started 21:28 PT, inside the 2 hour stop rule): all
  four jobs done. Nothing shelved. CI green on every
  push so far (PR Validate and Compliance Matrix).
  - H140, done in ae717e377e6827f4d1508eda40c26383b2145878
    (paging) and a7eeea15f1b6054e4bcd963fc277d4384773d822
    (drain). Paging design: an immediate-repeat check plus
    a per-poll page cap. A full page that hands back the
    cursor it was fetched with, or no cursor, ends the
    drain, and `_MAX_NOTIFICATION_PAGES_PER_POLL` (10)
    bounds any longer cycle. The next poll resumes from
    the stored cursor. Drain design: a pending flag
    retried from `_process`, not a session generation or
    a timer. A generation already guards the stale
    response (H54-2) and cannot make the addon fetch
    while busy, and `_process` already owns the poll
    cadence. `reset()` clears the flag. Failing tests
    first: a repeated cursor fetched 3 times unfixed
    (2 after), the cap case fetched 16 times (10 after),
    and a drain blocked by a stale fetch never ran
    unfixed (1 fetch after it cleared). After the fix,
    `test_friends_poller_lifecycle.gd` passes 21/21.
  - H139, done in 602a5bfd39242cb80bce2a10b4efefdc0720ac49.
    Timing design: an id is marked seen right after
    `show_toast` returns, in the same synchronous call,
    before the next event. Queueing records it only in
    memory, so a quit while a toast waits leaves it to
    toast on a later launch. A toast whose sender name
    does not resolve is unqueued unmarked, so a later
    delivery can show it. Account design: the same file
    now holds one list per account under an `accounts`
    dictionary. An account with no list starts from the
    legacy device-wide `seen_ids`, which is never updated
    again. That seeds every account from the old list.
    It is the anti-flood choice: pre-upgrade ids stay
    shared, and only ids shown after the upgrade are
    private. An older client still finds `seen_ids` and
    ignores the dictionary. Failing tests first: a queued
    id was already persisted unfixed, a second account
    got no toast (1 picture toast instead of 2), and a
    name miss lost the toast for good. After the fix,
    `test_friends_notification_poller.gd` passes 32/32,
    the lifecycle file 24/24 and
    `test_friends_notification_contract.gd` 4/4. The
    contract tests now use a throwaway dedup file. They
    used to write the real profile, which the per-account
    load then read back as a legacy seed.
  - H135 stage 1, done in
    f9f418509ebc930e923dc9b06d79d8296b3af27f. The doc is
    `docs/design/H135_settings_sync_merge.md`. It
    recommends tombstones and a Nakama version
    precondition together in one client release, gated
    on a local check of what a failed conditional write
    returns. It folds in H90-2 and H90-3, and H90-4 in
    part (untimed keys, the dead error substring, the
    test path). It leaves the per-device dirty flag as a
    follow-up. Its open questions are in Questions for
    Levi below.
  - H143, done, no code committed. The index is
    `.claude/probes/H143/index.md` (untracked, this
    machine), with the eight run directories beside it.
    T43 at 1360x765: toasts over the lobby (state
    `LOBBY`; two friend toasts naming the sender), game
    over (state `GAME_OVER`; results row plus Play again
    and Return to Lobby), friends (state `LOBBY` with the
    panel open; the shell an offline player sees, with a
    signed out toast), and auth (state `AUTH`; the three
    sign-in rows). T19 before pictures: four and eight
    displays at 1360x765, where four already run past the
    bottom and eight show only the first four, and at
    1100x900, where four across the bottom run off the
    bottom edge and eight run off both sides. The index
    says what each picture should show. Displays were
    added as `GamePlayerState` rows in `match_state`,
    the way the H129 source runs' list builds them. All
    eight runs passed and every picture was opened.
  - Prototype capture, for Claude to decide: build the
    H98 options only in a throwaway worktree
    (`git worktree add` outside this checkout). A fresh
    worktree has empty submodule directories, so it
    needs `git submodule update --init --recursive`
    inside it (or copies of `addons/rollback_netcode`
    and the platform submodule), then
    `scripts/setup-platform-addon.ps1` run there to make
    its addon copy, then one Godot import there to build
    its `.godot` cache. That is some minutes of setup
    and a few hundred MB. Run the same four T19
    scenarios from that tree with `-OutDir` pointing at
    a probes folder, capture four and eight at both
    window sizes per option, then remove the worktree.
    This checkout stays untouched throughout.
  - Questions for Levi:
  - OK to ship the H140 and H139 poller fixes with the next client release?
  - Ship the tombstone merge and the version precondition together in the next client release?
  - Must resetting a setting to its default on one device reset it on the player's other devices too?
  - If a reset must travel, must resetting the language to English on one device also reset it on the others?
  - Anything here to fix in the T43 pictures?
  - Which reads best mid-match: smaller full displays or compact chips?
  - For Claude to file: the six questions above, into
    Waiting on Levi. The H90-4 remainder (the per-device
    dirty flag and sync-at after an account switch) as a
    follow-up item, if it is not already tracked. A
    populated friends panel look still needs a signed-in
    run against a local backend on loopback. The H98
    prototype decision in the paragraph above. H135,
    H143, H149 and H150 were left alone, as instructed.
