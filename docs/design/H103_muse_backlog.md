# H103: Muse works the backlog

Brief for Muse (Muse Code, driven by Levi from his phone through Paseo)
for the rest of the week of 2026-10-29, while Claude Code is near its
weekly limit. Levi and Claude agreed the list on 2026-10-29 (claude
session 0cfd9cf1). A fresh Muse session can resume from this file,
ledger item H103 and `git log`.

How to use it: read sections 1 and 2 once, then work section 3 top to
bottom, one ledger item at a time. Each item's text in its `LEDGER.md`
and its row in `docs/design/H37_systems_audit.md` are the authority
(section 3 of the audit has the fix detail, section 6 the batches,
section 7 Levi's decisions). The notes here add order, gates and the
traps Claude already found. After a context compaction, re-read this
file and `git log --oneline -15` before going on.

Path shorthand: `sdk:` is
`third_party/snoringcat-platform/addons/snoringcat_platform_client/`,
`rt:` is `third_party/snoringcat-platform/runtime/`, `net:` is
`addons/rollback_netcode/`.

## 1. Rules

### 1.1 Commit and push like Claude does

Levi, 2026-10-29: "I want muse to auto commit and push in the same way
you do."

- When an item is done and its gates (section 2) pass, commit it and
  push it to that repo's mainline without asking. Mainlines: `main` for
  hopnbop, the platform submodule and the netcode submodule; `master`
  for claude-config and hex-grid.
- Levi's opening message authorizes, for the session: commits; pushes
  to the mainline; `git pull --rebase --autostash` and
  `git rebase --autostash origin/<mainline>` to sync; `git checkout main`
  in the detached netcode submodule; restoring files that you or a test
  script changed; and `git revert` of your own runtime commit when its
  deploy fails (1.4). Nothing else: no force-push, no `--no-verify` or
  other hook skip, no amending a pushed commit, no tags, no pushes to
  any other branch, no new branches, no `reset --hard`, no `clean -f`.
  Muse's git skill accepts this only in Levi's own words in the session.
  If the opening message doesn't carry it, ask Levi once before the
  first commit.
- Never commit partial or broken work to a mainline. A stalled item is
  shelved as a patch (1.6), never committed.
- Stage files by name, never `git add -A` or `git add .`. The trees
  carry unrelated dirty files (`settings.tres`, the platform submodule
  pointer, hex-grid's `example/data/*/metadata.json`). Before each
  commit, `git diff --cached --stat` must show only your files.
- One ledger item per commit. Items this brief pairs (H66 with RN7 and
  SP49) share one commit per repo. Message: `<ID>: <what changed>`,
  then a line or two of why. End every message with
  `Muse-Session: <your session id>`, so Claude can find your commits
  later with `git log --grep Muse-Session`.
- Submodule first. Commit and push inside the submodule, then commit
  the new pointer in hopnbop (`git add third_party/snoringcat-platform`
  or `git add addons/rollback_netcode`), usually with the ledger close.
  After any platform pointer change, run
  `scripts/setup-platform-addon.ps1`: the addon hopnbop loads is a
  gitignored copy.
- The netcode submodule is checked out detached. Before its first
  commit: note `git -C addons/rollback_netcode rev-parse HEAD`, run
  `git -C addons/rollback_netcode checkout main` and
  `git -C addons/rollback_netcode pull --rebase`, then check that the
  old commit is in `main` (`git merge-base --is-ancestor <old> main`).
- Sync each repo you touch before starting an item, and again before
  each push.
- You commit as Levi, so a global post-commit hook moves weekday
  08:00-18:00 PT commits to 19:00-23:00 the same day. That changes the
  SHA: take it from `git rev-parse HEAD` after the commit, never from
  `git commit`'s output. The future-looking dates are intended.
- A push rejected as non-fast-forward, where `origin` holds
  patch-identical copies of your commits, is the hourly timestamp-sweep
  re-dating them: `git fetch`, then
  `git rebase --autostash origin/<mainline>`; the duplicates drop out
  (`git patch-id --stable` confirms). Never force. Any other rejection:
  stop and tell Levi.
- After each push, check the CI run it started (`gh run list -L 3` in
  that repo). A red run on your commit is the next thing you fix.
- Read a repo's `CLAUDE.md` before your first commit there; its rules
  bind you too. hopnbop: direct to `main`, no feature branches or PRs,
  ignore harness-generated branch names.
- Versions differ per repo (the table in `~/Repositories/CLAUDE.md`).
  Never bump hopnbop's `project.godot` versions: they move with
  releases, and releases are Levi's. The netcode repo bumps
  `plugin.cfg` in the same commit as any behavior change (its
  `CLAUDE.md`).

### 1.2 No subagents

Never spawn subagents or workflows of any kind. They kill the Paseo
provider (claude-config
`incidents/2026-10-14-paseo-muse-subagent-provider-kill.md`, CC59).
Work inline.

### 1.3 Out of bounds

- Deploys and prod: no `scripts/sync-game-config.ps1`, no
  `scripts/deploy-*.ps1`, no `gh workflow run`, no tags, no SSH to the
  Nakama host, no Caddy or host config, no `pulumi up` or
  `pulumi preview` (both need prod credentials). Never call a prod
  endpoint by hand; `register_game` replaces the whole config blob.
- `game.yaml`: never edit it; every sync posts all of it to prod.
- Secrets: don't open `~/.config/muse/auth.json`, `secrets/` folders or
  `.env` files. Keep credentials, tokens and private data out of
  commits and ledgers (ledgers may be public).
- Tests and the agent harness run against loopback only. They refuse
  anything else; never work around a refusal.
- Section 4's items: don't start them.

### 1.4 A push under `runtime/**` deploys to production

A push to the platform's `main` that touches `runtime/**` deploys the
Nakama plugin to prod (`.github/workflows/nakama-runtime.yml`: vet,
test, staticcheck, then deploy). No other push here deploys anything:
SDK, hopnbop and netcode pushes only run CI. With auto-push, your gates
are the whole review, so before committing a runtime change:

1. In `rt:`, `go vet ./...`, `go test ./...` and `staticcheck ./...`
   pass. Install staticcheck once with
   `go install honnef.co/go/tools/cmd/staticcheck@2025.1.1` (the CI
   pin).
2. From hopnbop's root, `pwsh scripts/local-smoke-test.ps1` exits 0. It
   builds the plugin and runs the whole compliance suite against a
   local Nakama. It also rewrites files in the checkout (H81): after
   each run, check `git status` in hopnbop and the platform, and
   restore what it changed before you stage anything.
3. The released client keeps working. Players run 0.56.0 (hopnbop
   commit `ddd8bd88`; `git ls-tree ddd8bd88 third_party/snoringcat-platform`
   names the SDK commit it shipped) until Levi's next release, and the
   runtime goes live the moment you push. When a fix changes what an
   RPC accepts or returns, or how a flow runs, read what that SDK
   sends and expects. If the change can't stay compatible (likely for
   SP32 invites, SP36 presence reads, SP42 name rules, and SP59 if 0.56.0
   writes a collection your allowlist misses), land the client half,
   shelve the runtime half as a patch (1.6) and move the item to
   Waiting on Levi: it has to ship with a release.
4. One runtime item per push, so a bad deploy has one cause. Watch the
   run: `gh run list --repo SnoringCatGames/snoringcat-platform
   --workflow nakama-runtime.yml -L 1`, then `gh run watch <id> --repo
   SnoringCatGames/snoringcat-platform`. If vet, test or staticcheck
   fail there, nothing deployed: fix forward. If the deploy job fails,
   `git revert` your commit, push it (that redeploys the previous
   plugin), and tell Levi.

### 1.5 Ledgers

- H103 (hopnbop `LEDGER.md`, In progress) is this run's resume handle.
  When you start, set its `owner:` to `muse <session id>`. Whenever you
  close an item, update its `last commit:` and `next:` lines in the same
  ledger commit.
- Items live in the ledger of the repo their prefix names: H in
  hopnbop, SP in `third_party/snoringcat-platform/LEDGER.md`, RN in
  `net:LEDGER.md`, HG in hex-grid. An H item whose code is in the SDK
  (H23) is fixed in the platform and closed in hopnbop.
- To close an item, move it to the top of its ledger's `Done` as one
  line, `- **<ID>** · <what>. Done in <sha> (<date>).`, with the fix
  commit's SHA. A ledger commit right after the fix, or after a few
  fixes in the same repo, is fine.
- File anything new the moment you find it: a follow-up, a residual, a
  decision for Levi. The next ID is the highest ever used plus one,
  counting the repo's `LEDGER.md`, `docs/ledger_done.md` and
  `docs/ledger_notes.md`
  (`node $HOME/Repositories/claude-config/tools/ledger.mjs add --repo <repo>`
  assigns it; its header lists the flags).
- Items stay one to three lines and Done entries one line; longer notes
  go to the bottom of `docs/ledger_notes.md` under `## <ID>`.
- Ledgers merge with `merge=union`. If an ID shows up twice after a
  pull, the copy written last is the live one; delete the other by
  hand.

### 1.6 Stalls, questions and stopping

- If two approaches to an item fail, or it runs past about two hours,
  shelve it: `git diff --output=<hopnbop>/.claude/probes/<ID>/wip.patch
  -- <your files>` in the repo you changed (keep every patch under
  hopnbop's `.claude/probes/`, which is gitignored, and say which repo
  it applies to), restore those files, write what you learned into the
  item, and go on to the next one.
- Ask Levi, briefly, only what the checks can't settle: a product
  decision that isn't recorded (SP34), a fix that needs a release or a
  prod change to be safe, a missing icon or asset, a failure you can't
  explain. Decide technical variants yourself, by the tests.
- At the end of each tier, send Levi a few lines: what landed (IDs and
  SHAs), what you shelved and why, what comes next.
- Stop when Levi says so, the list is done, or your usage runs low.
  Then append a dated entry to section 5 (done, shelved with patch
  paths, in flight, next, anything odd), set H103's `owner:` to
  `nobody since <time> (<why>)` and its `next:`, commit and push.

## 2. Gates: what "verified" means

- GDScript: the relevant GUT files, one file per run:
  `godot --headless -s --path . addons/gut/gut_cmdln.gd
  -gtest=res://test/unit/<area>/test_<name>.gd -gexit`. GUT exits 0 even
  when nothing ran (a version mismatch, a wrong `-gtest=` path), so read
  the summary and check the count of tests run isn't zero. Known
  failures are listed in `.claude/rules/testing.md`; when a failure
  looks unrelated, run the same file on a clean `main` before deciding.
- Bug fixes land with a regression test that fails without the fix,
  where a test is feasible. Where the audit wrote a probe for the bug,
  the probe becomes that test (H77).
- Gameplay or UI behavior: also an agent-harness run,
  `scripts/agent/run-game.ps1 -Scenario <name>` (`scenarios/*.json`;
  `-Mode lobby`; `-Scenario match-2-clients` runs a server and two
  clients). Judge by the `AGENT_RESULT {...}` line; exit 0 pass, 1 fail,
  2 bad scenario, 3 refused. Reference: `scripts/agent/README.md`.
- SDK or runtime: `pwsh scripts/local-smoke-test.ps1` exits 0. Runtime:
  all of 1.4 too.
- User-visible text: through `tr()`, with a row in
  `translations/ui_translations.csv` for every locale (real CSV: quote
  cells that contain commas, double inner quotes). Then
  `godot --headless --import`, commit the regenerated `.translation`
  files with the CSV, and run
  `res://test/unit/i18n/test_translation_csvs.gd`.
- UI: everything navigable with U/D and L/R on gamepad or keyboard;
  `MenuRow` is the focusable row. A missing pixel-art icon: ask Levi,
  never ship without one.

Claude Code loads hopnbop's area rules on its own; Muse doesn't, so
read the matching file before editing:

| Editing | Read first |
|---|---|
| `*.gd`, `*.tscn`, `*.tres` | `.claude/rules/gdscript-style.md` |
| `test/**` | `.claude/rules/testing.md` |
| `src/ui/**`, `src/level/**` | `.claude/rules/ui.md` |
| netcode, runtime, signaling, session glue | `.claude/rules/transport.md` |
| `src/core/crash_*` | `.claude/rules/crash-reporting.md` |
| workflows, deploy scripts, `web/**`, `legal/**` | `.claude/rules/deploy.md` |

The style rules that bite most: tabs, 80 columns, `not` over `!`,
everything typed, `@export` instead of `preload()` for resources,
trailing commas, comments end with periods, no em dashes, never maintain
`load_steps` in `.tscn`. Convert the legacy lines you modify; never
bulk-convert.

## 3. Work order

Work top to bottom. Skip a blocked item (say why in its ledger entry)
and return when it clears.

### Tier 0: warm-up, exercises the commit flow

- **SP51** is already done: `9139b38` pinned staticcheck `@2025.1.1`
  (`nakama-runtime.yml:46`). Close it in the platform ledger, push, and
  bump hopnbop's pointer (it already lags two ledger-only commits; the
  bump takes them too).
- **Platform inbox.** claude-config `LEDGERS.md` holds six
  snoringcat-platform lines: from 2026-10-21 the Edgegap $1 floor, the
  kernel reboot question, and the two cost-monitor bugs plus its
  hard-coded Hetzner rate; from 2026-10-28 the Pulumi pins and the
  Dependabot coverage check. File each into the platform ledger (the
  prod-host ones as Residuals or Waiting on Levi: filed, not worked),
  delete those lines from the inbox, and push claude-config (`master`).
  The hex-grid lines wait for Tier 6.

### Tier 1: security and party

Start with the party set (item 10) if Levi has decided SP34; otherwise
start at item 1 and switch to the party set when he answers.

1. **SP41** (SDK): a failed `delete_account` is reported as a failed
   sign-in, because `_send_delete_request` clears `_is_deleting` before
   `_emit_failure` (`sdk:core/auth_api_client.gd:890,896`).
2. **SP43** (SDK): a token refresh during a pending link is taken as
   the link's result. Skip `_check_auto_refresh` while linking, merging
   or deleting, or give refresh results their own route; the audit's
   probe becomes the test.
3. **H23** (SDK, closed in hopnbop): the notification socket stops on
   any failed sign-in result (`sdk:core/notification_socket_client.gd:321-327`).
   Stop it only on a real sign-out, keep reconnecting through a
   transient refresh failure, and add the GUT case from the audit's soc
   F6.
4. **SP47** (runtime): revoke sessions on account delete (DEL-3).
5. **SP35** (runtime): 50 pending outgoing friend requests block every
   accept. Exempt accepts from the cap; rate-limit adds (accepts
   exempt), invites and joins by code.
6. **SP37** (runtime): party chat gets length, rate and block limits in
   the chat hooks; delete the dead routes once you've confirmed 0.56.0
   never calls them.
7. **SP36** (runtime and SDK): blocking stops friend requests and
   nothing else. Presence rows at read and write permission 0, served
   through the RPC; `updated_at` stamped by the server; `rich_presence`
   capped; blocked users dropped (`rt:presence.go:205-215`). Two traps:
   rows already in prod keep their old permissions until rewritten
   (don't touch prod data; file a follow-up if they need a migration),
   and if 0.56.0 reads presence rows directly, the runtime half waits
   for a release (1.4 step 3).
8. **H60 with SP42**: names and avatar URLs are never validated. Client
   (H60): allowlist avatar hosts, cap the download size, add a timeout.
   Runtime (SP42): a `BeforeUpdateAccount` hook that validates names
   and avatar URLs, and in-match identity derived on the server.
   Existing accounts whose names fail the new rules must still sign in.
9. **SP59**, runtime half only: a `BeforeWriteStorageObjects` allowlist
   with a size cap. Before you deny anything, list every collection that
   0.56.0 and the dedicated server write. The per-IP Caddy zone is prod
   host config: leave it in the item for Levi.
10. **Party set: SP34, SP32, SP33, H53, H55.** They share `rt:party.go`
    and the client's `party_manager.gd`, so do them as one sequence.
    They need Levi's SP34 decision (platform ledger, Waiting on Levi;
    the audit's section 7 row 5 recommends all three options: leaving
    hands leadership on, a disband RPC, and a transferred leader gets
    full powers). If it's still open, ask Levi once and carry on with
    the other items.
    - **SP34**: record the decision in the item, then build it.
    - **SP32**, the most serious item here: `party_invite` calls
      `nk.GroupUsersAdd`, writing state 2 (full member) with no consent,
      friendship, block or rate check, and one player can be in two
      parties. Make an invite something the invitee accepts; check
      friendship, blocks and rate; allow one party per player (leaving
      the old party follows SP34's leader rule). Fix
      `test_party_invite_flow.gd:136-140` with it. 1.4 step 3 will
      almost certainly hold the runtime half for a release.
    - **SP33** (`rt:party.go:265-453`, `party_manager.gd:787-846`):
      refuse a start unless every active member is ready and recently
      present; refuse a second start; clear ready on start.
    - **H53** (client): single-flight plus a dirty flag, and the starter
      can abort. Pairs with SP33's refusal of a second start.
    - **H55**: one absent member stalls the party; it builds on SP34.
11. **SP44**, last in this tier: the guest device id isn't
    crypto-random, and the token store's key needs replacing, without
    losing existing guests. The store is an encrypted ConfigFile at
    `user://auth.cfg` (`sdk:core/auth_token_store.gd`:
    `save_encrypted_pass` at 241-242, `load_encrypted_pass` at 249-250,
    `_get_passphrase()` at 302). If new code can't read the old file,
    `sdk:core/auth_api_client.gd:1035-1038` mints a new id and the
    guest's account is orphaned. First commit: a migration test that
    saves a store with the current passphrase and proves the new code
    reads it and keeps `local_player_id`; a failed read must never mint
    a new id. Then give new installs a crypto-random id
    (`Crypto.generate_random_bytes`), leave existing ids alone, and
    re-key on the next save.

### Tier 2: matchmaking

1. **SP30** (runtime) first; the rest build on it. The
   `matchmaker_matched` hook blocks while an allocation runs, so no
   match forms for anyone. Return from the hook at once and allocate in
   a goroutine; the inflight registry and cancel path already exist.
   The audit reproduced the bug in a Go test against Nakama 3.25's real
   matchmaker: land that test.
2. **SP29** (runtime and SDK): one player's 120 s timeout cancels the
   whole matched set. The runtime sends "allocating" at hook start and
   the SDK stops its timer on it; the SDK sends
   `cancel_matchmaking_allocation` only on an explicit Cancel.
3. **SP28** (SDK, plus the runtime for the id): a Cancel during
   `start_matchmaking` leaves a ghost ticket. A search generation
   counter that Cancel bumps and start re-checks after each await; a
   correlation id on tickets and pushes; handle a socket close.
4. **SP71** (runtime): delete `match_metadata` on cancel even with no
   registration (`rt:match_lifecycle.go:694-711`); fix the test comments
   at `test_party_to_matchmaking.gd:65-67` and
   `test_friends_block.gd:77-79`.
5. **SP58** (runtime): `match_end` isn't atomic. Return a retryable
   error and keep the registration, since the writes are idempotent
   (`rt:match_lifecycle.go:538-541,563-565`); add an hourly stale-row
   sweep (RT1).

### Tier 3: tests and harness

- **H81** first: `local-smoke-test.ps1` rewrites the checkout it runs
  in (audit 3.5).
- **H77**: as each fix lands, its H37 probe becomes its test (audit
  section 4 step 2). Close H77 when the last probe has landed.
- **H65**, with H63 in Tier 4: tests for the sign-out router's party
  reset and avatar-cache clear.
- **H35**: `test_party_matchmaking_context.gd` fails 7 of 11 in a full
  directory run and passes alone (state bleed). Find and stop the
  bleed.
- **H46**: `test_network_connector.gd` crashed on exit in 1 of 3 runs.
  Run it 10 times and find what outlives the test.
- **H84**: test fixtures log "no animation 'Rest'" 37 times per run.
- **H73**: harness friction: loopback runs warn of production, client 2
  starts 30 s late, screenshots go black 0.7 s after a screen change.
- **H74**: `scripts/dev-stack.ps1`, from exec-b's `stack.ps1`.
- **H30**: `run-game.ps1 -Backend` input checking (read the item).
- **H68**: legal parity is checked only by pr-validate. You may edit
  `sync-game-config.ps1`'s `mustSurvive` list; never run the script.
- **H99**: finish T48 (audit section 5).
- **RN3** (netcode): run the addon's 9 GUT test files in its CI. Levi
  listed it for this run, so the offer is accepted: move it out of
  Waiting on Levi when you start.
- **SP50**: the client SDK's CI runs no tests; make it run them.
- **H75**, last: harness sign-in plus `publish` and `wait_shared` steps.

### Tier 4: spelled-out fixes

- **H20**: call `copy_latest_state` at `game_panel.gd:673` and `779`, as
  `694` already does.
- **H27**, netcode first: local mode logs "RPC on yourself is not
  allowed". Guard on `is_local_mode` at `frame_synchronizer.gd:120` and
  skip self at `networked_level.gd:307`.
- **H63** with H65: always offer Log Out, even with an expired access
  token, and clear the local session when the server call fails.
- **H21**: a party follower whose join fails gets two toasts.
- **H19**: the loading screen after a recoverable matchmaking failure
  (read the item).
- **H18** with **H31**: raw SDK error text reaches players, and the
  credits labels aren't translated. Credits labels at
  `credits_screen.tscn:40,55,70,85,114`; toasts at
  `export_data_row.gd:96-99` and `friends_panel.gd:342-354`. Translation
  gate (section 2).

### Tier 5: sweeps

- **H66 with RN7 and SP49**: V17's 22 broken format strings: 17 in
  hopnbop (one is the refused-pause ERROR at `game_panel.gd:1854`), 4 in
  netcode, 1 at `sdk:test/compliance/test_account_delete.gd:118`. One
  commit per repo.
- **H29**: delete the unused `BinaryToggle`, plus `fetch_player_stats`
  and `fetch_match_history` and their signals in
  `backend_api_client.gd`. Grep for every caller first.
- **H95**: one click sound for every MenuRow trigger, in MenuRow's
  shared dispatch.
- **H96**: Alt+Enter toggles fullscreen, in hopnbop only.
- **H97 with SP53**: finish T12, delete the 9 Stale notes, fix the docs
  claims. gofmt on runtime files is a runtime change (1.4).
- **SP20**, and **SP21**: `README.md` claims a `v1.4.0` tag. Check
  `git ls-remote --tags origin` and correct the text.
- **H80** (also audit V15, row 709): keep stray images out of exports;
  delete the textures b998107d orphaned and the orphan `.import` files,
  among them the three `level_4_combined*.png.import`. Grep every path,
  `.tscn` and `.tres` included, before deleting. `foobar.png` stays
  until Levi answers T14.

### Tier 6: other repos

- **hex-grid** (`~/Repositories/hex-grid`, `master`). Muse doesn't
  trust it yet (`~/.config/muse/trust.json`): ask Levi to allow it.
  File its two `LEDGERS.md` inbox lines (the showdown residual; move HG1
  to Next) and delete them from the inbox. Then **HG1**: remove the
  unused `@sendgrid/mail` and the dependencies only it pulls in, after
  checking that no tracked file but the manifests mentions sendgrid or
  axios; refresh the lockfile with npm; build and test as its
  `CLAUDE.md` says. Leave its dirty `example/data/*/metadata.json`
  alone.
- **Platform Pulumi** (filed in Tier 0). First the Dependabot coverage
  check, read-only, recording what each call shows:
  `gh api repos/SnoringCatGames/snoringcat-platform/vulnerability-alerts -i`,
  `gh api "repos/SnoringCatGames/snoringcat-platform/dependabot/alerts?state=open"`,
  `gh api repos/SnoringCatGames/snoringcat-platform/dependency-graph/sbom`.
  Then bump `infra/pulumi/snoringcat-platform/go.mod`: x/crypto 0.52.0,
  go-git 5.19.2, grpc 1.83.2, go-billy 5.9.0, klauspost/compress
  1.18.7, x/net 0.55.0, otel 1.45.0; `go mod tidy`; `go build ./...`.
  Don't run `pulumi preview` (prod credentials): move the item to
  Waiting on Levi with "run `pulumi preview`, expect no changes".

## 4. Not in this run

- Held for Claude after the weekly reset: H6, H8, H24, H26, H52
  (`game.yaml`), H54 with SP40, H56, H72, H86 with SP61, H87, H89, H90,
  RN8, and knotmaze. Levi may release any of them to you; until he
  does, don't start them.
- Levi's: H92, H94, H10, SP17 (hands-on); H71, H83, H102, SP12, SP13,
  SP34 until answered, SP69, T14's `foobar.png` (decisions); H105 (prod
  host).
- Not listed for this run: H5, H9, H22, H61, H88, H98.

## 5. Handoff log

Append one dated entry each time you stop: done (IDs and SHAs), shelved
(patch paths), in flight, next, anything odd.
