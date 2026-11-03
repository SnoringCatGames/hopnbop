# H156: Muse run 11, pictures of the two T19 candidates

Brief for Muse's eleventh run (Muse Code through Paseo), written by Claude
(claude session 0cfd9cf1) on 2026-11-02. Claude sends it, not Levi.
One job: build the two candidate looks for the in-match player list in a
throwaway worktree and capture them, so Levi can answer one question
with pictures: "which reads best mid-match: smaller full displays or
compact chips?" Nothing from the prototypes lands on main. The real build
is a later item, after Levi picks.

How to use it: section 1, then section 2. A fresh session resumes from
this file, ledger item H156 and `git log --oneline -15`. Re-read this
file after a compaction. This file is the authority; a Paseo message
changes it only when the message says so.

## 1. Rules

- H103's sections 1 and 2 (`docs/design/H103_muse_backlog.md`) apply:
  read "H103" there as H156, and ignore 1.3's last bullet (this file has
  no section 4). The commit and push grant (H103 1.1) stands: Levi gave
  it in his own words on 2026-10-29, your memory
  `feedback_commit_and_push.md` records it, and it covers runs Claude
  launches from a committed brief. No subagents or workflows (H103 1.2).
  You are the only writer in this checkout until you stop.
- **This checkout stays as it is.** Your only commit to main is the
  handoff entry at the end of this file. Prototype code lives in the
  worktree and, as patch files, under `.claude/probes/H143/prototypes/`
  (untracked, on this machine). Never push the prototype branch or any
  branch but main.
- **Hands off the platform.** `third_party/snoringcat-platform` in THIS
  checkout holds commits that wait for Levi's OK to deploy to production,
  which is why hopnbop's pointer shows as modified and has to stay that
  way. Reading its files is fine. Don't edit, commit, pull, check out,
  restore or reset anything in or under that path here, and don't run
  `git submodule update`, `git restore` or `git checkout` on it here.
  Claude may push those commits, or bump the pointer in a hopnbop commit,
  while you work: if a `git pull --rebase` brings that in, carry on.
  Never stage the platform pointer or `addons/rollback_netcode/`. Stage
  by name, and `git diff --cached --stat` must show only your files.
  Don't run `scripts/local-smoke-test.ps1`. The throwaway worktree is a
  different tree with its own submodule copies: there, and only there,
  you run `git submodule update --init --recursive` and
  `scripts/setup-platform-addon.ps1`. Read each script first and confirm
  it resolves its paths from its own location. If one reaches into the
  main checkout, stop and report.
- **Where the worktree goes.** `C:\Users\lsl\wt\h156`, outside
  `~/Repositories`, because Claude's daily jobs read every `LEDGER.md`
  under that folder and a second copy of this repo's ledger confuses
  them. Branch `h156-prototypes`. Remove both when you finish (section 2,
  Closing).
- **Public repo.** The docs, the commit message and the handoff log are
  public. No keys, tokens or secrets. No prod requests: the harness
  blackholes backends and stays on loopback.
- **Prose.** No em dashes or en dashes in anything you write (a period
  and a new sentence instead).
- **Read before editing.** You don't load the area rules, so read
  `.claude/rules/gdscript-style.md`, `.claude/rules/ui.md` and
  `scripts/agent/README.md` (the harness). On Windows run
  `Godot_v4.7.2-stable_win64_console.exe`, not `godot.exe`. Never pipe
  `godot --import` or any long command through `Select-Object`: the
  read times out, Paseo shows you as `error`, and the run looks dead.
  Redirect to a file under `.claude/probes/H143/` and read the file.
- **Ledgers.** Don't edit `LEDGER.md`: Claude closes H156 and files what
  you find. Write anything new, one line each, under "For Claude to
  file" in your handoff entry.
- No client release, no version bump, no deploys, no `game.yaml` edits
  (H103 1.3).
- **Stop rule.** Stop when the pictures, the patches, the index additions
  and the handoff entry are done, or after 90 minutes of wall clock,
  whichever comes first: run `Get-Date` at the start and at each
  milestone. Worktree setup is capped at 30 minutes: when the submodules,
  the addon copy or the import have not produced a tree that runs the
  existing "before" scenario by then, stop and write the handoff saying
  what blocked. A compaction is not a stop; after one, re-read this file
  and `git log` before going on. Two failed approaches to a prototype
  shelve it. Don't start anything this file does not list.

## 2. Work

Read first: `docs/design/H98_polish_and_player_list.md` (Options 1 and 3,
and the measured table), `.claude/probes/H143/index.md` (the "T19 before
pictures" and what they show), and the scenarios and run logs beside it.
The HUD and `PlayerDisplay` live under `src/`; find `Hud`,
`get_player_lists()` and `get_visible_player_list()`.

### Setup (cap 30 minutes)

1. From this checkout: `git worktree add C:\Users\lsl\wt\h156 -b
   h156-prototypes main`.
2. In the worktree: `git submodule update --init --recursive`, then
   `scripts/setup-platform-addon.ps1`, then one import with
   `Godot_v4.7.2-stable_win64_console.exe --headless --import --path
   C:\Users\lsl\wt\h156`, output redirected to a file. The import may exit
   non-zero on cosmetic warnings: read the file, not the exit code.
3. Prove the tree before changing it: run the existing four-display
   "before" scenario (`.claude/probes/H143/scenarios/t19-players-4.json`)
   from the worktree's `scripts/agent/run-game.ps1`, with `-OutDir` under
   this checkout's `.claude/probes/H143/`. Check the harness resolves the
   project from the worktree and not from the main checkout. Its picture
   should match `20261102-214313-h143-t19-players-4/client1/players-4.png`.

### The two candidates (written in the worktree, committed there)

- **Option 1, smaller full displays.** Shrink `PlayerDisplay`'s minimum,
  font and icon sizes as the player count grows, so the visible list fits
  a cap of 40% of its axis (window height for the vertical list, window
  width for the horizontal one). No scale factor: containers reset a
  child's scale (inferred for 4.7.2). The corners stay as today.
- **Option 3, compact chips.** During play each player is a chip: avatar,
  name and score, in a strip along the same edge as today, with no full
  displays. Keep what a player glances at mid-match: who is who and the
  score. The lobby and the game-over screen stay as they are. Ignore the
  adjective reveal, and say in the handoff what it would need.

Both are for pictures. No tests, no translations, no polish. One switch
(a constant or an `eval` step) that picks the option keeps both in one
tree.

### Pictures (harness, from the worktree)

For each option, four and eight displays, at 1360x765 and at 1100x900
(`-WindowSize`): eight pictures. Base them on the T19 scenarios in
`.claude/probes/H143/scenarios/`, with `-OutDir` into this checkout's
`.claude/probes/H143/` and run titles `h156-opt1-...` and
`h156-opt3-...`. Also capture option 1 at two and at three displays at
1360x765, since the H98 doc means option 1 for small counts.

**Numbers from the engine, not from the picture.** In every scenario add
`eval` steps that store, for each display or chip in the visible list,
its global rect and whether it lies fully inside the viewport, plus the
whole list's rect as a fraction of the window's axis, and the smallest
font size drawn. Read them back from `result.json` `.evals`. The first
draft of the H143 index described three of eight before pictures wrongly
(it said eight displays run off the bottom, when the stack is centred and
the middle four show), because it was written from the intended layout
and not from what was drawn. So open each picture and write down what it
shows: the displays fully visible, partly cut off and off screen. Check
those counts against the numbers, and where they disagree, say so.

### Closing

1. Save each option's diff as a patch under
   `.claude/probes/H143/prototypes/` (`option1.patch`, `option3.patch`),
   with a line in the index on how to apply it to main.
2. Extend `.claude/probes/H143/index.md` with a "T19 candidates" section:
   per picture its path, option, display count, window size, the measured
   numbers, what it shows, and the smallest text size in pixels.
3. Remove the throwaway: `git worktree remove --force C:\Users\lsl\wt\h156`,
   `git branch -D h156-prototypes`, `git worktree prune`. `git worktree
   list` must show only this checkout, and `git status --short` here must
   show what it showed at the start: the platform pointer and
   `addons/rollback_netcode`, nothing else.
4. Append your handoff entry to section 3: done or shelved, the setup time
   and what it took, the index path, what each option looks like in a
   sentence, anything the numbers and the pictures disagree on, anything
   for Claude to file. Commit that one file and push it. Check CI
   (`gh run list -R SnoringCatGames/hopnbop -L 3`).

## 3. Handoff log

Append one dated entry each time you stop.
