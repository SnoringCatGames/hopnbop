# H142: Muse run 9, the stage 3 design-doc rewrites and the reveal fix

Brief for Muse's ninth run (Muse Code through Paseo), written by Claude
(claude session 0cfd9cf1) on 2026-11-02. Claude sends it, not Levi.
Claude's review of the Tier D design docs (H104, stage 3) found three
docs that are unsound or stale as written, H87 (server crash reporting),
H72 (exported-build harness) and H98 (polish and player list), and one
client bug beside them (H130). Levi decides on these docs later; the job
is to make what he reads true. The H130 fix reaches players with the next
client release, which needs Levi's OK.

How to use it: section 1, then section 2's items in order. A fresh
session resumes from this file, ledger item H142 and
`git log --oneline -15`. Re-read this file after a compaction. This file
is the authority; a Paseo message changes it only when the message says
so.

## 1. Rules

- H103's sections 1 and 2 (`docs/design/H103_muse_backlog.md`) apply:
  read "H103" there as H142, and ignore 1.3's last bullet (this file has
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
  Never stage the platform pointer or `addons/rollback_netcode/`. Stage
  by name, and `git diff --cached --stat` must show only your files.
- **The findings.** Ledger items cite labels such as "H87-1" and "H98-3":
  entries in Claude's stage 3 report, `.claude/probes/H104/stage3.md`,
  untracked and on this machine only. It has one section per doc
  (`## H87`, `## H72`, `## H98`) and a last section, `## Ledger items`.
  Each finding is a bullet that starts `- **H87-1 · high · ...`
  (`Select-String -Pattern '^- \*\*H87-1 '` finds one; read it with
  `Get-Content <file> | Select-Object -Skip <n> -First <m>`). Read a
  doc's whole section (the verdict, the findings, "Verified correct")
  and the doc itself before you edit it. The fixes there are proposals:
  when you find a better one, do it and say why in the handoff log. When
  a finding is wrong, record why and leave it out.
- **Verified and inferred.** The report labels each claim "verified"
  (read in the code or docs at a SHA) or "inferred" (reasoning, or read
  from the engine checkout at `~/Repositories/godot`, which is 4.4-dev,
  not 4.7.2). Keep that label in the doc wherever a claim still rests on
  an inference; never promote an inference to a fact. A number you
  measure yourself with the harness is "measured"; say how.
- **Public repo.** The docs, the ledger, commit messages and the handoff
  log are public. Say what a design must do. Never commit the report or
  paste its text: write each doc in its own voice. No keys, tokens or
  secrets, and no key values (the HTTP key is "the HTTP key"). No prod
  requests. Where a finding needs a fact only production or Edgegap's
  console can give, write it into the doc as an open check, name who can
  run it, and move on. If Edgegap's public documentation answers it, cite
  the page and mark the claim "documented", not "verified".
- **Prose.** No em dashes or en dashes in anything you write (a period
  and a new sentence instead). Keep each doc's headings, section order
  and line wrapping.
- **Read before editing code (H130 only).** You don't load the area
  rules, so read `.claude/rules/gdscript-style.md`,
  `.claude/rules/testing.md`, `.claude/rules/ui.md` and
  `scripts/agent/README.md` (the harness). On Windows run
  `Godot_v4.7.2-stable_win64_console.exe`, not `godot.exe`. Never pipe
  `godot --import` or any long command through `Select-Object`: the
  read times out, Paseo shows you as `error`, and the run looks dead.
  Redirect to a file under `.claude/probes/H130/` and read the file.
- **A test that fails without the fix** (H130; H103 section 2). Run it
  against the unfixed code and see it fail.
- **Commits.** One per ledger item (H130 may take two). Message
  `<ID>: <what changed>`, a line or two of why, then
  `Muse-Session: <your session id>`. Take SHAs from `git rev-parse HEAD`.
  After each push check CI (`gh run list -R SnoringCatGames/hopnbop
  -L 3`); a red run on your commit is the next thing you fix.
- **Ledgers.** Close H127, H128, H130 and H129 in `LEDGER.md` as H103 1.5
  says. Leave H98, H126 and H132 alone: they are Claude's. Do not file
  anything under `Waiting on Levi`: write each question for Levi into
  your handoff entry, one line each, as a plain question, and Claude
  files them. File anything else new the moment you find it. In your
  first commit, put your session id on H142's `owner:` line.
- No client release, no version bump, no prod requests, no deploys, no
  `game.yaml` edits (H103 1.3). Tests and the harness stay on loopback.
- **Stop rule.** Stop when the four items and the handoff entry are done,
  or after 2 hours of wall clock, whichever comes first: run `Get-Date`
  at the start and at each milestone. A compaction is not a stop; after
  one, re-read this file and `git log` before going on. Two failed
  approaches to an item shelve it (H103 1.6). Never commit partial work.

## 2. Work

Order: H127, H128, H130, then H129. H129 comes last so the H98 doc
describes the adjective reveal as H130 leaves it.

### 2.1 H127: the H87 doc (server crash reporting)

Doc `docs/design/H87_server_crash_reporting.md`; report section `## H87`.
Apply H87-1 to H87-12, high first.

H87-1 is the one that changes the doc's recommendation. The doc treats a
crashed game server as gone and unreported. The review found that
Edgegap restarts a crashed server in the same container, which changes
which designs are possible. Make the recommendation conditional on the
open check the entry names (whether the restart keeps the container's
writable layer, so a marker file written before the crash is still there
after), and put that check first under a "Before deciding" heading. H87-2
to H87-5 are medium and shape the design (report-only rerun instead of
porting the redaction, post only on a crash marker or signal, fix
"Detection today", re-cost option 3). Then the low items and the nit. For
H87-12, end the doc with a size (M) and one yes/no question for Levi.

The entry's residual, that `.claude/rules/crash-reporting.md:26` has been
stale since H86, is already fixed (H131, `f33c3c5c`). Check it and skip.

### 2.2 H128: the H72 doc (exported-build harness)

Doc `docs/design/H72_exported_build_harness.md`; report section `## H72`.
The review found the plan unsound as written: stock 4.7.2 export
templates refuse `--path` and ignore `-s`, so the path-override template
is the main option, not a footnote. Apply H72-1 to H72-8. Keep the doc's
goal and change the plan to match the findings, so this is a rewrite of
the plan sections, not a patch of single lines. Keep each claim's
verified or inferred label. For H72-8, end the doc with a size (M) and
the two yes/no questions for Levi.

### 2.3 H130: the adjective reveal runs on the hidden list (probe first)

Entry `- **H98-3 ` in the report (a side bug, not in the doc).
`reveal_adjectives` in `src/ui/celebration/match_end_celebration.gd`
(about lines 400-475) reads only `G.hud.player_list`, the horizontal
list. At a window aspect of 1.3 or more (the default 1360x765 window and
every 16:9 screen), `src/ui/hud/hud.gd` (about lines 82-101) hides that
list and shows the vertical one, a second `PlayerList`. So the reveal
freezes the adjective labels of displays nobody sees and parents its
popups to hidden displays, while the displays on screen show the new
adjectives as they replicate (`player_display.gd` about line 140), which
the freeze exists to prevent. The review inferred all this from the code
and did not run it, so:

1. **Probe first.** Offline harness run at the default window size, on a
   match that ends (shorten it with the scenario's `settings`, such as
   `{"match_duration_sec": 20}`; the README says how), with `eval` or
   `state` steps just before and during the reveal that record which
   list is visible, whether each list's displays have
   `is_adjective_frozen`, and where the popup is parented. Keep the
   scenario in `.claude/probes/H130/` (copy it into
   `scripts/agent/scenarios/` for the run only if the wrapper needs it,
   then delete the copy). Put what you saw in the handoff log. If the
   visible displays are frozen and the popup sits over a visible one,
   the bug is not reproduced: change nothing, leave H130 open for Claude
   with the evidence, and go on to 2.4.
2. **If reproduced**, make the reveal work on the list that shows:
   freeze the displays of every list that exists (a resize during the
   reveal must not spoil it) and parent each popup to a visible display.
   Do not change when a list shows or hides: that is H98's design and
   Levi's call. Add a GUT test that fails on the current code.
   `reveal_adjectives` returns at once when `Netcode.is_server`, which
   defaults to true under GUT, so a test sets it false and restores it in
   `after_each`.
3. **Pictures for Claude, who views them.** Before and after the fix, at
   1360x765 and at a window narrower than aspect 1.3 (`-WindowSize
   1100x900`), save the screenshot taken just before the reveal and one
   taken during it, under `.claude/probes/H130/` (untracked). List the
   paths in the handoff log with what each should show.

### 2.4 H129: the H98 doc

Doc `docs/design/H98_polish_and_player_list.md`; report section `## H98`.
Required: H98-1, H98-2, H98-4 and H98-12. Also do the cheap doc fixes
H98-5, H98-6, H98-7, H98-8, H98-10 and H98-11. H98-3 is H130 (2.3):
point the doc at it and don't describe it twice. H98-9 asks for a HUD
layout test that fails today: put it in the doc's plan as the first step
of any option, and don't write it.

The numbers (H98-1, H98-4): the doc sizes its options with the display's
minimum size, about half its rendered height. Redo them with the
rendered display, and measure instead of inferring. In harness runs at
`-WindowSize` 1280x720, 1360x765, 1920x1080 and 2560x1440, `eval` the
rendered `size` and `global_position` of the visible list and of one
`PlayerDisplay`. An offline run has one display and `match-2-clients`
has two; derive four and eight displays from the measured display size
and the list's separation, and say which numbers are derived. Put the
table in the doc, marked "measured", with each size's share of the
window height for four stacked displays.

H98-2: option 3's game-over premise is wrong, and the doc should say
what each option does to the adjective reveal (as 2.3 leaves it).

H98-12: end the doc with Levi's two looks as plain questions (the T43
surfaces, and the T19 candidates side by side), and say the pictures are
agent work still to do. Don't capture them in this run: Claude files
that as its own item (H143).

## Closing

Close the items (H103 1.5). Then append your handoff entry to section 3:
done, with SHAs; shelved, with patch paths; what the H130 probe saw; the
H98 measured table's source runs; the screenshot paths with what each
should show; the questions for Levi (one line each); anything for Claude
to file. Set H142's `owner:` to `nobody since <time> (<why>)`, commit and
push.

## 3. Handoff log

Append one dated entry each time you stop.
