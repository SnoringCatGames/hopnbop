# H120: Muse run 3, the H104 stage 1 fixes

Brief for Muse's third run (Muse Code through Paseo), written by Claude
(claude session 0cfd9cf1) on 2026-10-30. Claude sends it, not Levi.
H104's stage 1 had two read-only agents review the security work of
runs 1 and 2 (H103, H109). Their findings are filed as platform SP83 to
SP94 and hopnbop H113 to H117; Levi's playtest that morning added H118
and H119.

How to use it: work section 2 top to bottom, one item at a time. Each
item's ledger text is the authority; the notes here add order, gates
and traps. A fresh session resumes from this file, ledger item H120 and
`git log --oneline -15` in hopnbop and the platform. Re-read this file
after a compaction. Path shorthand as in H103: `sdk:`, `rt:`, `net:`.

## 1. Rules

- H103's sections 1 and 2 (`docs/design/H103_muse_backlog.md`) apply
  unchanged: read "H103" there as H120, and 1.3's "section 4" as
  section 5 here. H109's two lessons (`docs/design/H109_muse_run2.md`,
  section 1) apply too.
- The commit and push grant (H103 1.1) stands. Levi gave it in his own
  words on 2026-10-29, your memory `feedback_commit_and_push.md`
  records it, and it covers runs Claude launches from a committed
  brief, so don't ask again.
- You are the only writer in hopnbop, the platform and netcode until
  you stop. Claude reviews your commits as they land (H104).
- In your first commit, put your session id on H120's `owner:` line.
- **The findings.** Each ledger item cites labels such as "1B F11": the
  stage 1 report of part B, finding F11. The reports are untracked and
  exist on this machine only: `.claude/probes/H104/stage1-A.md` and
  `stage1-B.md`, with their probes beside them. Read a finding's whole
  entry (where, failure, what was verified, the fix) before you change
  code. The fixes there are proposals: when you find a better one, do
  it and say why in the handoff log. When a finding is wrong, record
  why and leave its item open for Claude.
- **Public repos.** hopnbop and the platform are public. Commit
  messages, ledger text, code comments, test names and the handoff log
  say what a change fixes or enforces, never how to exploit the old
  behavior: no payloads, request recipes or bypass steps. Never commit
  the reports, and don't copy text from them. A probe may become a test
  (H103 section 2), except F18's, which stays untracked.
- hopnbop's platform pointer may trail the platform checkout by one of
  Claude's ledger commits. That is expected; bump it with your first
  SDK change.

## 2. Work order

1. **SP83** (platform `infra/`, Urgent): prepare it, don't land it.
   `stage1-B.md` F18 gives the cause and the fix: a guard on the Nakama
   site in `infra/remote/nakama/Caddyfile` and a memory limit on the
   Nakama service in `infra/remote/nakama/docker-compose.yml`. Those
   files deploy by hand to the prod host, so this change is committed
   only together with its deploy, after Levi approves it.
   - Don't commit or push it. Save it as `sp83.patch` in
     `.claude/probes/H104/F18/` (hopnbop, untracked), with a `notes.md`
     beside it: each value and why (the largest legitimate request,
     Nakama's own request limit, and what Postgres and the rest of the
     stack need on a 4 GB host), how you tested it, and how to roll it
     back. Then restore the two files, so the platform tree is clean.
   - Test it locally. `infra/dev/` has no Caddy, so build the prod
     Caddy image (`infra/remote/nakama/caddy/`) and run it in front of
     a local stack with the patched Nakama site block (a local port,
     plain HTTP). Show that the request F18 describes is refused at the
     proxy, that an oversized ordinary body is refused too, and that
     both HEAD's compliance suite and 0.56.0's (H108) pass through the
     proxy, realtime sockets included. Check that Nakama runs normally
     under the memory limit.
   - If a CI test for the guard is worth having (the compliance stack
     has no proxy today), describe it in the notes; it lands with the
     deploy.
   - In the handoff log, write only "SP83: patch ready" and the path.
2. **H119** (hopnbop): holding A starts left movement for an instant,
   then it stops. Diagnose before you change anything. Leads, none of
   them confirmed:
   - `move_left` is physical A in `project.godot`. The keyboard
     partitions in `src/core/input_device_manager.gd` read keys with
     `Input.is_physical_key_pressed`, and `get_is_action_pressed`
     returns false for every keyboard action while
     `is_text_input_captured` is set. TextInputRow sets and clears it
     on focus in and out, and H111 and H112 just changed focus in the
     join-by-code panel.
   - Levi types through kanata (Programmer Dvorak in userspace, no
     tap-hold). Claude is asking him whether it happens with kanata off
     and with the Left arrow. Harness input doesn't pass through
     kanata, so a harness repro puts the cause in the game.
   - Reproduce it with the agent harness: hold A for about a second in
     an offline level and log the character's velocity each frame. Try
     it again after opening and closing the join-by-code panel, and
     with H56's keyboard setting on and off.
   - Write the root cause in the handoff log, then fix it with a test
     that fails without the fix. If the harness can't reproduce it,
     record what you tried and go on; Claude takes it back to Levi.
3. **H118** (hopnbop): the squish sprites (a squished player, a
   squished snail) draw in front of the level's foreground layer. They
   belong with the characters, behind it.
   - Find how characters are ordered against the foreground (z_index,
     a CanvasLayer or tree order) and put the squish sprites at the
     same depth.
   - Then list everything else that can draw in front of the
     foreground: effects, particles, pickups, labels. Move only the
     world sprites that plainly belong with the characters. For the
     rest (name labels, popups, anything UI-like), take a harness
     screenshot of each in front of the foreground, save them in
     `.claude/probes/H118/`, and list them in the handoff log. Claude
     asks Levi about those.
   - Verify with harness screenshots from before and after, and look
     at them yourself.
4. **SP84** (runtime; reopens SP47).
5. **H113** (hopnbop client and game server; reopens H60). It reaches
   players with the next release, so its tests are the whole proof
   until then.
6. **SP85** (runtime; reopens SP36's party half). SP32's consent half
   stays held (section 5).
7. **SP86 with H114** (runtime, then client). Also correct SP33's Done
   line so it cites 0499a41.
8. **SP87** (runtime, plus hopnbop's compliance allowlist). F16 moves
   the compliance seeds to `match_end` and lists the three released
   seeds it names in `.github/compliance/released-known-failures.txt`:
   the one new entry this run allows (section 3).
9. **SP88** (runtime).
10. **SP89, H115, H116 and SP90** (SDK, then hopnbop). For SP90's TS-1,
    write the code comment and the audit note only: Claude accepted it
    as obfuscation. Push the SDK first, then bump hopnbop's platform
    pointer and rerun `scripts/setup-platform-addon.ps1`.
11. **SP91** (runtime). Migrate the old presence rows only if 0.56.0's
    suite stays green with the migration, then the SP36 nits.

## 3. Gates

H103's section 2 and 1.4 are the gates. On top of them:

- **A test that fails without the fix**, for every finding you fix.
  Run it once against the unfixed code, see it fail, and say so in the
  commit message.
- **GUT through the console build:**
  `& 'C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe'`
  with H103's arguments. The `godot.exe` on PATH is the GUI build: it
  prints nothing to PowerShell and exits 0.
- **Before every push:** the full per-file GUT suite and the release
  guards for hopnbop; vet, test, staticcheck and the smoke test for the
  runtime (H103 1.4).
- **The released client (0.56.0):** before each runtime push, run
  0.56.0's compliance suite against your runtime as
  `docs/design/H108_compat.md` describes. A failure that isn't already
  in `.github/compliance/released-known-failures.txt` blocks the push.
  - The one exception is SP87's three seeds. Review B found that
    0.56.0 never writes `recent_players` itself (`stage1-B.md`, the
    SP59 section); confirm that before you list them.
  - When any other fix would need an entry: commit what can land, save
    the runtime half as a patch in `.claude/probes/<ID>/`, move the
    item to Waiting on Levi with a line on why, and go on.
- **One runtime item per push**, and watch its `nakama-runtime.yml` run
  through the deploy (H103 1.4, step 4).
- **After every push:** watch PR Validate and Compliance Matrix on that
  commit, and fix red before you push anything else.
- **No prod actions.** SP83 stays a patch. No `sync-game-config.ps1`,
  no `register_game`, no workflow runs, no requests to prod hosts
  (H103 1.3).

## 4. Reporting and stopping

- Close each item in its ledger with its commit as you go (H103 1.5).
- Shelve an item after two failed approaches or about two hours: a line
  in its ledger entry and in the handoff log, then the next item.
- At the stop, append a dated entry to section 6: done (IDs and SHAs),
  shelved and why, questions for Levi or Claude. Set H120's `owner:` to
  `nobody since <time> (<why>)` and its `next:`, then commit and push.

## 5. Not in this run

- Levi's: SP83's deploy, SP92 and SP93, and SP59's per-IP proxy zone
  (prod host config).
- Held for the next release: SP32's consent half (SP94 is its idea)
  and H117, its client half.
- H104's stages 2 and 3: Claude, after the weekly usage reset.
- H109's section 4 items that are still open.

## 6. Handoff log

Append one dated entry each time you stop.

### 2026-10-30, muse 01a189f7 (run complete)

Done, in landing order (platform SHAs are that repo's):

- SP83 live on prod 2026-10-30 23:32:41 UTC (`e17586f`); v32 game
  server live (`4f6fde1d`); H122 looks (`f0f39d46`, confirmed by
  the coordinator); H119 key trace (`2d28d3cc`).
- Client 0.57.0 released 2026-10-30 (`7fd873fd`) by the local
  client-only deploy; web artifacts `f11d194b`; config synced
  (display 0.57.0, protocol 2, server still v32). Compliance
  Matrix 41154547444: released suite 94/94, no unclassified
  failures; the released allowlist is header-only again
  (`d6cf88f5`); H108_compat.md records the release.
- SP96 follow-ups (platform `2cf7a55`, follow-ups `b8e20d5`),
  SP87 (`d4e12c9`) + SP101 follow-ups (`4bef255`), SP88
  (`03884fa`), SP89 (`7d39613`), H115 (`4405cd3b`), SP90
  (`8832a3b`), H116 (`73aa04fd`), SP91 (`4d534b6`, prod deploy
  41161376621 green, version route 200). Every runtime push
  was one item, deployed, and checked against the version
  route before the next.
- SP93 closed (read-only prod count, nothing to clean).
  SP92's report is drafted; Levi sends it. SP98, SP99, SP100,
  SP101 filed along the way.

Not done, with owners:

- H83's Facebook-avatar post-release check: still not run. It
  needs a player signed in with Facebook; the lookaside
  redirect is still unconfirmed first-hand. Levi, at a
  browser, is the shortest path (same shape as SP17).
- H119 waits on Levi's next playtest: hold A, and if movement
  stalls, the log's `H119TRACE` dump is the evidence. The
  echo-faithful replay did not reproduce it on native; web
  was not replayed.
- Local note: `~/.hopnbop-migration/credentials.env`'s
  NAKAMA_HTTP_KEY and GAME_ADMIN_KEY no longer match prod
  (both syncs this run read the host's values over SSH
  instead, printing neither). Levi may want to refresh that
  file; nothing in the repos records the values.
- The platform ledger has one cosmetic double blank line in
  Next (left by SP90's move); harmless, tidied next time the
  file is edited.

Questions for Claude: none open. The coordinator's H122
confirmation arrived and the release followed it.
