# Migration plan: AWS → Nakama + Hetzner + Edgegap

> Companion to `platform-pivot-discussion.md` (architecture decision
> doc). This file is the **executable plan**: phased steps, manual
> checklist, state-file format, and verification gates. Replaces
> `platform-pivot-discussion.md` once the migration completes.

## Status (confirmed decisions)

- **Execution model:** phased autonomous, not single-session.
- **Domain:** `nakama.snoringcat.games` for the Nakama instance.
  Game server hostnames continue using the existing
  `s-{ip}.game.hopnbop.net` pattern (just pointed at Edgegap-allocated
  IPs instead of GameLift IPs).
- **OAuth MVP providers:** Google + Facebook. Anonymous always
  available. Apple/Steam/Epic deferred.
- **Payment:** Hetzner (~$10-15/mo), Edgegap (usage-based, ~$0-15/mo
  at current scale), UptimeRobot (free tier), Cloudflare/DNS (free).
- **Plan location:** this file
  (`hopnbop_private/MIGRATION_PLAN.md`).

---

## Recommended improvements (DECIDE: in/out)

Each item below has a verdict line. Override any default by saying
"drop X" or "upgrade Y to in-scope."

---

### IN SCOPE during migration

#### 1. Per-game config schema

**What it is.** A structured `game.yaml` per game declaring
everything platform code needs to know about that game: `game_id`,
display name, Edgegap app slug, port mapping, transports enabled,
matchmaker rules, legal doc paths, supported auth providers,
leaderboard definitions, max player count, etc. Nakama runtime
reads it at startup and registers per-game RPCs / hooks accordingly.

**Pros:**
- This *is* the platform. Without it, "deploy a new game" requires
  backend code changes — defeating the entire reusable-platform
  goal.
- New game onboarding becomes config-only — encourages
  experimentation.
- All game-specific behavior is auditable in one file.
- Test fixtures become trivial (load a fake `game.yaml`).
- Forces clean separation of game-specific from cross-cutting
  logic.

**Cons:**
- Schema-design cost: getting the shape right before you've built
  2 games is hard.
- Risk of over-abstraction; the second game may want something
  schema v1 doesn't support.
- Adds an indirection layer (look up config, return value vs.
  hardcoded constant).
- Dynamic config means runtime errors instead of compile-time
  errors when keys are mistyped.

**Verdict: keep IN SCOPE.** Build a minimal v0 with just the
fields you need today (game_id, app slug, ports, providers,
matchmaker rules); grow organically.

---

#### 2. Shared Snoring Cat identity

**What it is.** One account = one Snoring Cat player. Sign in
once with Google/Facebook; friends, presence, and (optionally)
achievements carry across all your games. Already in place from
Phase 4 of the AWS extraction; this is "verify it survives the
migration."

**Pros:**
- Friends list carries across games — major social retention
  win.
- Single sign-in experience reduces friction across the studio.
- Cross-game presence ("Levi is online, in Hop 'n Bop") draws
  players into other titles.
- Cross-game leaderboards / season passes / studio-wide unlocks
  become possible later.
- Lower support burden (one auth flow to debug, not N).

**Cons:**
- Couples games operationally — Nakama down means all games
  down. (Mitigated by Nakama's high reliability + monitoring.)
- Privacy considerations: friends in game A see your activity
  in game B unless you opt out (need an "appear offline"
  per-game setting).
- Account deletion deletes player from all games at once (could
  be undesired if regions / TOSes differ).
- If a future game needs to be regionally restricted, you may
  need per-game visibility filtering.

**Verdict: keep IN SCOPE.** Already shipped; just preserve it.

---

#### 3. Centralized observability with `game_id` labels

**What it is.** One Grafana, one Prometheus, one Loki for all
games. Every metric and log carries a `game_id` label.
Dashboards are filterable per game.

**Pros:**
- One pane of glass for ops — no "wait, which monitoring stack
  is this?"
- Cross-game patterns visible (e.g., simultaneous Postgres
  slowdown across all games → infrastructure issue, not game
  logic).
- Compounding value: every dashboard you build benefits future
  games.
- Cheaper than one Grafana per game.
- Easier on-call routing.

**Cons:**
- Single point of failure for observability — if Grafana box
  dies, you're blind across all games. (Mitigated by UptimeRobot
  external checks + replicated Postgres backup.)
- Cardinality risk: per-player or per-match metrics × game count
  can blow up Prometheus storage. (Discipline: don't tag metrics
  with player_id.)
- Requires discipline to add `game_id` label everywhere — easy
  to forget early on.

**Verdict: keep IN SCOPE.** Default is correct; calling it out
so we don't accidentally split per-game during the build.

---

#### 4. Account linking flow (anon → permanent)

**What it is.** A player launches the game and starts playing
immediately as an anonymous account (no signup screen). Later,
they upgrade to a permanent Google/Facebook account without
losing progress.

**Pros:**
- Lowest possible signup friction — no auth wall blocking the
  door.
- Captures players who'd never sign up if asked upfront.
- Industry standard for casual / mobile-style multiplayer.
- Permanent-account upgrade unlocks cross-device play (huge
  retention driver).
- Letting players "try before they commit" raises eventual
  conversion.

**Cons:**
- Anonymous account state lives on the device; nuking save data
  loses progress.
- Two code paths in auth UI (sign in fresh vs. link existing
  anon).
- Edge case: player accidentally creates both anon and permanent
  accounts; need merge UX.
- Storage cost for every anon player who never returns; may
  need TTL purge job.

**Verdict: keep IN SCOPE.** Standard pattern, Nakama supports
natively.

---

#### 5. Account deletion flow

**What it is.** A "delete my account" button that actually
deletes (or anonymizes) all the player's data across the
platform.

**Pros:**
- Legally required: GDPR (EU), CCPA (California), and many
  other jurisdictions.
- Required for app store approval (Apple App Store, Google
  Play, increasingly Steam).
- Trust signal — players are more willing to sign up when they
  know they can leave.
- Data hygiene: less stuff lying around to ever leak.

**Cons:**
- Implementation complexity: scrub from leaderboards (or
  anonymize), match history, friends graphs.
- Risk of accidental deletion — needs confirmation UX +
  recovery window.
- Affects friends' UX (someone in their friend list "vanishes").
- Affects competitive integrity (a player under cheat
  investigation could delete to destroy evidence).
- Backups must be purged within legal window (~30 days for
  GDPR).

**Verdict: keep IN SCOPE.** Non-negotiable for distribution in
regulated regions and on app stores.

---

#### 6. Per-game protocol versioning

**What it is.** Each game has its own `protocol_version`
integer, tracked in the Postgres `games` config table.
Client-server compatibility validated per-game. When game X
ships a breaking network protocol change, only X's version
bumps; other games are untouched.

**Pros:**
- Allows independent client-server protocol evolution per game.
- Letting one game ship a breaking change without affecting
  others' release schedules.
- Trivially easy (~1 hour) to implement when the platform is
  being designed from scratch (vs. retrofit later).
- Becomes critical the moment you have 2+ games on shared
  Nakama.
- Locks in the "platform is multi-game from day one" property.

**Cons:**
- One more thing to remember to bump on protocol changes.
- Tiny added complexity in the version-check code path.

**Verdict: IN SCOPE (upgraded by user).** Even with one game
today, the platform is designed to be multi-game from day one;
adding this now is much cheaper than retrofitting. Bump
procedure documented in
`third_party/snoringcat-platform/PLATFORM_ARCHITECTURE.md` and
referenced from project CLAUDE.md.

---

#### 7. Infrastructure as Code (Pulumi) — scoped

**What it is.** Define infrastructure declaratively in Go.
Deploys via `pulumi up`. Pulumi has good providers for Hetzner
Cloud, Hetzner DNS, and AWS. **Scope for now:** Hetzner Cloud
(servers, networks, firewalls), Hetzner DNS records, and AWS
resource teardown. **Out of scope:** Edgegap (no clean Pulumi
provider; REST API is fine), Docker Compose / Nakama runtime
config (just files on a box, not an IaC fit).

**Pros:**
- **Idempotent recovery** for phased autonomous execution. If
  Phase A or F fails halfway, Pulumi state lets the next
  session resume cleanly without me reconstructing what got
  created.
- "Deploy a new game" later becomes ~30 min via a new stack
  instead of a day of CLI commands.
- All infra changes go through PR review — auditable.
- Reproducible: nuke and recreate from scratch.
- Disaster recovery: if Hetzner deletes your project, you're
  back in hours, not days.
- Drift detection.
- Diff-able infrastructure history.

**Cons:**
- Upfront cost: ~0.5-1 day on top of writing CLI commands I'd
  write anyway. (The 3-5 day estimate I'd given before assumed
  a full retrofit; for greenfield Hetzner provisioning the
  delta is small.)
- Adds Pulumi as a dependency (runtime + state backend).
  State stored in an S3 bucket (`hopnbop-pulumi-state`) for
  durability and to keep Pulumi free.
- Pulumi-specific gotchas (provider bugs, rare state
  corruption).
- One game's stack changes can affect another's if shared
  infra isn't carefully scoped — mitigated by per-game stacks
  with shared modules.

**Verdict: PARTIAL IN SCOPE (recommended by me as the agent).**
The recoverability benefit during phased autonomous execution
is real. Pulumi project + state bucket created in Phase A;
Hetzner provisioning expressed declaratively; AWS teardown
done via Pulumi adopt-and-destroy in Phase F. Edgegap and
Docker config remain CLI/API-driven.

---

### DEFERRED (add post-migration, easy to retrofit)

#### 8. In-game store / IAP

**What it is.** Real-money purchases inside the game. Cosmetics,
currency, season passes, premium content.

**Pros:**
- Recurring revenue beyond initial purchase price.
- Lets you ship base game cheaper (or free) and monetize
  engagement.
- Industry-standard for F2P; increasingly common in premium
  games.

**Cons:**
- Per-platform billing integration is real work: Apple
  StoreKit, Google Play Billing, Steam IAP, each separate.
- Server-side receipt validation required (otherwise trivially
  cheatable).
- Compliance overhead: tax handling, regional pricing, age
  verification, parental controls.
- Receipt validation, refund handling, chargeback flows.
- Platform fees: Apple/Google ~30% (15% under $1M); Steam ~30%.
- Easy to slip into predatory mechanics (Pavlovian dailies,
  loot boxes) — design discipline required.
- Player attitudes vary; perceived exploitation hurts
  reception.
- Roughly 4-8 weeks of work for clean cross-platform support.

**Verdict: DEFERRED.** Only build when you have a concrete
monetization plan and have shipped at least one game to see
real player engagement. Don't preemptively design around IAP.

---

#### 9. Tournaments / seasons

**What it is.** Time-bound competitive events with leaderboards
that reset, prizes (or cosmetic rewards), special matchmaking
rules. Nakama has tournament primitives.

**Pros:**
- Re-engagement driver — gives lapsed players a reason to come
  back.
- Content-cheap: reuse existing gameplay with new rules /
  scoring.
- Builds community (leaderboards become talking points).
- Engineering cost is low (~3-5 days for basic version) thanks
  to Nakama.
- Pairs well with social features (friend competitions).

**Cons:**
- Operational overhead: someone has to schedule, set rules,
  communicate.
- Empty tournaments feel sad — needs a player base big enough
  to populate them.
- Anti-cheat becomes more important as stakes rise.
- Becomes a content treadmill: players expect new ones; if you
  stop, they churn.
- Prize fulfillment if real prizes (legal/operational
  complexity).

**Verdict: DEFERRED.** Add when there's a content reason (a new
mode, a holiday, a launch event). Don't add for its own sake.

---

#### 10. Anti-cheat beyond server-authoritative

**What it is.** Replay review system, behavioral anomaly
detection, automated shadow-bans, ML on telemetry to flag
cheaters.

**Pros:**
- Server-authoritative is foundational, but determined cheaters
  still automate inputs (bots), exploit timing windows, or
  coordinate to grief.
- Replay system doubles as a level-design / balance tool.
- Shadow-bans avoid the cat-and-mouse of obvious bans
  (cheaters keep playing thinking they're winning).
- Anomaly detection catches patterns humans miss.

**Cons:**
- Significant ML / data-pipeline work for serious detection.
- False positives are catastrophic — banning legit players
  destroys trust.
- Requires ongoing tuning as cheat techniques evolve.
- Replay storage cost (lots of bytes per match).
- Can become a full-time job for someone — scope creep risk.

**Verdict: DEFERRED.** Server-authoritative + chat reporting +
manual review is enough until competitive play is a marketed
feature and there's evidence of cheating affecting retention.

---

#### 11. Feature flags in Nakama Storage

**What it is.** A runtime config table where you flip behavior
on/off per game, region, or player segment, without redeploying.
Code reads `is_feature_enabled("foo", game_id)` at runtime.

**Pros:**
- Ship dark, enable when ready.
- Safer rollouts (1% → 10% → 100%).
- Quick rollback for bad features (flip a flag, no redeploy).
- A/B test variants.
- Per-game customization without code changes.

**Cons:**
- Flags accumulate cruft; dead flags 6 months later that
  nobody dares delete.
- Implicit branching of the codebase — which combinations are
  even tested?
- Adds a "is this on?" check at every gated code path.
- Without discipline, becomes a configuration hellscape.

**Verdict: DEFERRED.** Add when you're nervous about a specific
feature you're shipping or want to A/B test. ~half day of work
when the time comes.

---

#### 12. Telemetry → ClickHouse warehouse

**What it is.** Pipe match events (every kill, bump, ability
use, position sample) to a separate analytical database.
Self-host ClickHouse on a third small Hetzner box (~$5/mo). Run
ad-hoc analytical queries without thrashing prod Postgres.

**Pros:**
- Answers questions like "how often is map X played", "what's
  the win-rate of strategy Y", "where do new players churn".
- Doesn't load production Postgres.
- Unlocks balance / design decisions backed by data.
- Open-source, self-hostable.

**Cons:**
- Pipeline complexity: events → Loki/Kafka → ClickHouse.
- Storage grows fast (every match × every event).
- Schema design matters; bad schemas make queries slow.
- Privacy/GDPR — more data = more compliance surface.
- Without a data-analysis culture, it's just expensive logs.

**Verdict: DEFERRED.** Don't preemptively build a warehouse
without a specific question. Add when there's a question
production Postgres can't answer cheaply.

---

### SPECULATIVE (probably never)

#### 13. Rust runtime modules via Nakama fork

**What it is.** Fork Nakama, add a Rust runtime SDK alongside
the official Go/Lua/TS ones, write all custom logic in Rust.

**Pros:**
- Stack is fully Rust if you go all-in.
- Marginal performance edge over Go (rarely material at indie
  scale).
- Aesthetic preference if Rust is your strong preference.

**Cons:**
- Forking Nakama means owning the Nakama codebase forever.
- Falls behind upstream improvements; you re-merge or stop.
- The Rust runtime SDK doesn't exist — you'd be inventing it.
- Performance gains are marginal; Go's runtime is fast enough.
- Loses "community-supported" property of vanilla Nakama.
- 6-12 months of work for what real-world gain?

**Verdict: NEVER.** Reconsider only if you build a serious team
with Rust infrastructure expertise.

---

#### 14. Multi-region active-active Nakama

**What it is.** Run Nakama instances in multiple geographic
regions (US-West + EU + APAC), with replicated Postgres,
routing players to the closest region.

**Pros:**
- Lower latency for global players.
- Survives regional outages.
- Required at significant scale.

**Cons:**
- Postgres replication across regions is hard (eventual vs.
  strong consistency tradeoffs; conflict resolution).
- Cross-region network costs.
- Player routing complexity.
- Operational burden multiplies (N Nakamas to maintain, deploy,
  monitor).
- Premature optimization at indie scale — Edgegap already
  handles game-server geography; Nakama latency for
  matchmaking/auth is non-realtime and tolerates one region.

**Verdict: NEVER (at current scale).** Reconsider when DAU > 1k
or you have measurable retention loss from non-US regions.

---

#### 15. P2P player-hosted matches

**What it is.** Skip dedicated game servers. One player hosts;
others connect peer-to-peer.

**Pros:**
- Free (no server costs).
- Low latency for nearby players.
- Resilient to backend outages.
- Suitable for jam games / casual coop.

**Cons:**
- NAT traversal is brutal — STUN/TURN servers needed, fallback
  rates significant.
- Host-quitting issues (need migration logic).
- Cheating much harder to prevent without server-authoritative.
- Casual UX: some players need port forwarding, which kills
  accessibility.
- Doesn't fit rollback netcode well (rollback assumes
  authoritative server).
- Complicates matchmaking (need to filter by network
  conditions).

**Verdict: NEVER (for Hop 'n Bop).** Possibly for a future
small jam game with 2-4 players where ranked play isn't a
goal.

---

## Execution model

**One pre-flight session (you, ~60-90 min in browser)** produces a
credentials file. Then **6 autonomous phases (me, 2-4h each)** with
manual gates between certain ones. Each phase reads a state file at
start, writes at end, is idempotent on re-run.

**State file:** `~/.hopnbop-migration/state.json` (non-sensitive
infra IDs, IPs, phase status). See [State file format](#state-file-format)
below.

**Credentials:** stored as an **age-encrypted file** in your
existing `claude-config` dotfiles repo (synced across
desktop/laptop via the existing PostToolUse auto-push hook).
Decrypted on demand to `~/.hopnbop-migration/credentials.env`
(gitignored, mode 0600). SSH private keys for Hetzner stored
the same way. age uses multi-recipient encryption so each
machine has its own private key; private keys never leave the
machine they were generated on.

**Kicking off phase N:**
> Open Claude Code in `C:\Users\lsl\Repositories\hopnbop_private`,
> paste:
> `Run phase <X> of MIGRATION_PLAN.md. State file at ~/.hopnbop-migration/state.json. Use --dangerously-skip-permissions.`
> The session reads the plan + state file, runs the phase, updates
> state, posts a summary to Discord when done.

**Why not one big autonomous run?** See architecture doc; short
version: account-creation gates, OAuth dev consoles, AWS-decommission
approval, context-window decay, and external wall-clock waits all
break the single-session model. Phased structure preserves
autonomy within phases without pretending the manual gates don't
exist.

---

## Pre-flight manual checklist (you do this once, ~60-90 min)

Do these in order. Secrets get written to a local
`credentials.env` on the desktop you're running pre-flight from,
then encrypted with **age** to a multi-recipient `.age` file in
your `claude-config` dotfiles repo. The dotfiles repo's
PostToolUse auto-push hook syncs the encrypted file to the
laptop. Each machine decrypts to a local
`~/.hopnbop-migration/credentials.env` when needed.

### Pre-flight security gate (run first, both machines)

Before generating any keys or pasting any tokens, verify the
following on each machine. If any check fails, fix it before
continuing — don't just paper over.

1. **`claude-config` repo is PRIVATE on GitHub.**
   ```powershell
   gh repo view levilindsey/claude-config --json visibility
   # expect: {"visibility":"PRIVATE"}
   ```
   If `PUBLIC`: encrypted `.age` blobs become world-readable.
   Crypto is still strong, but defense-in-depth fails. Flip to
   private at https://github.com/levilindsey/claude-config/settings.

2. **Full-disk encryption is on** (mitigates "stolen unlocked
   laptop" → all secrets exposed). Settings → Privacy & security
   → Device encryption (Home) or BitLocker (Pro). Should show
   "On". PowerShell check:
   ```powershell
   manage-bde -status C:
   # look for: Conversion Status = Fully Encrypted
   ```
3. **Back up the age private key off-machine** *after* you
   generate it (step 0 below). Recommended: print
   `$HOME\.config\age\key.txt` to paper, store in a drawer or
   safe-deposit box. **Do not** sync the private key via
   OneDrive, Dropbox, etc. — that defeats the "key never
   leaves the machine" property and creates a third copy you
   don't control. If your disk dies and you have no backup,
   every credential ever encrypted to that key is unrecoverable
   from this machine; you'd recover via the other machine's key
   and rotate.
4. **Edit `credentials.env` in a real editor (Notepad, VS
   Code), not via shell redirection.** Pasting tokens via `>>`
   puts them in PowerShell history, which is a recoverable
   plaintext leak even after encryption.

When all four checks pass, proceed to step 0.

### 0. age + dotfiles setup (one-time, both machines)

**On each machine:**

1. Install `age`:
   ```powershell
   winget install FiloSottile.age
   ```
   (Restart PowerShell after install so PATH picks up.)

   > **WinGet shim caveat:** the shim at
   > `$env:LOCALAPPDATA\Microsoft\WinGet\Links\age.exe` is a
   > 0-byte symbolic link that doesn't launch from PowerShell
   > ("No application is associated…"). The real binary lives
   > at `$env:LOCALAPPDATA\Microsoft\WinGet\Packages\FiloSottile.age_*\age\age.exe`.
   > Phase scripts find and invoke the real binary directly.
   > For interactive use, plain `age` and `age-keygen` usually
   > work because the shell resolves them via PATH; if you hit
   > the launch error, use `& "<full-path-to-real-age.exe>"`.

2. Generate this machine's keypair:
   ```powershell
   New-Item -ItemType Directory -Path $HOME\.config\age -Force | Out-Null
   age-keygen -o $HOME\.config\age\key.txt
   ```
   (`chmod 600` is a no-op on Windows; user-profile NTFS perms
   already restrict the file to your user.)

3. Copy this machine's **public** key (last line of the keygen
   output, starts with `age1…`). You'll paste it into the
   recipients file in step 4.

**On the desktop (where you'll run pre-flight):**

4. In your `claude-config` dotfiles repo, create the recipients
   list (public keys for both machines that should be able to
   decrypt). `secrets/` is tracked by claude-config and synced
   across machines, but `~/.claude/secrets` is a junction to
   the real path. Use the real path here:
   ```powershell
   $secrets = "$HOME\Repositories\claude-config\secrets"
   New-Item -ItemType Directory -Path $secrets -Force | Out-Null
   @"
   # Desktop
   age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   # Laptop
   age1yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
   "@ | Out-File -Encoding ASCII "$secrets\hopnbop-migration.recipients"
   ```
   (Public keys aren't sensitive; the recipients file is safe
   in git.)
5. Create the `~/.claude/secrets` junction so the standard path
   resolves to the synced claude-config dir:
   ```powershell
   cmd /c mklink /J $HOME\.claude\secrets $HOME\Repositories\claude-config\secrets
   ```
6. Set up the local working directory (gitignored, machine-only):
   ```powershell
   New-Item -ItemType Directory -Path $HOME\.hopnbop-migration\ssh -Force | Out-Null
   New-Item -ItemType File -Path $HOME\.hopnbop-migration\credentials.env -Force | Out-Null
   ```
7. Add `$HOME\.hopnbop-migration\` to your global gitignore.

After this, work through steps 1-10, populating the **local**
`$HOME\.hopnbop-migration\credentials.env`. Step 11 encrypts
and pushes.

### 1. Hetzner Cloud account

1. https://www.hetzner.com/cloud → Sign up (use `admin@snoringcat.games`).
2. Confirm email link. Add credit card or PayPal.
3. Create project: **`snoringcat-platform`**.
4. Project → Security → API Tokens → Generate. Name: `migration`.
   Permissions: **Read & Write**.
5. Append to `~/.hopnbop-migration/credentials.env`:
   `HCLOUD_TOKEN=<paste-token>`

### 2. (skipped) Hetzner DNS &mdash; not used

Originally this step set up Hetzner DNS for studio domains.
That changed once we settled on Cloudflare Pages for static
hosting: Cloudflare Pages requires the domain to be a
**Cloudflare zone** (DNS managed by Cloudflare) before you can
attach it as a custom domain. Trying to add a custom domain
without a zone fails with "Only domains active on your
Cloudflare account can be added."

So all studio DNS is on Cloudflare instead of Hetzner. See
step 7 below for the Cloudflare zone + nameserver-change flow.
Hetzner Cloud is still used for compute (Nakama box, Postgres
box, staging box); Hetzner DNS is not used at all.

**No `HETZNER_DNS_TOKEN` is needed.** The original step's
output of that env var is removed from the credentials list.

### 3. Edgegap account

1. https://app.edgegap.com → Sign up.
2. Confirm email. (Account may be held for review — message
   support if so: "Godot indie dev migrating from GameLift".
   Approval typically <24h.)
3. Add payment method.
4. User → API Tokens → Create.
5. Append:
   - `EDGEGAP_TOKEN=<paste-token>`
   - `EDGEGAP_ORG=<your-org-slug>` (visible in account settings)

### 4. GitHub Personal Access Token

1. https://github.com/settings/tokens → Generate new (classic).
2. Scopes: `repo`, `workflow`, `admin:org` (if pushing to
   SnoringCatGames org).
3. Append: `GITHUB_TOKEN=<paste-token>`

### 5. Discord webhook

Already in `~/.claude/jobs/discord-config.json`? Append the URL:
`DISCORD_WEBHOOK_URL=<paste-url>`

If not: Discord server → channel → Integrations → Webhooks →
New, copy URL, append.

### 6. UptimeRobot (free)

1. https://uptimerobot.com → Sign up.
2. My Settings → API Settings → Main API Key.
3. Append: `UPTIMEROBOT_API_KEY=<paste-key>`

### 7. Cloudflare account + Pages + studio website cutover

This step ends with `snoringcat.games/privacy/`,
`snoringcat.games/terms/`, and `snoringcat.games/data-deletion/`
serving live pages on Cloudflare Pages. Both Google and Facebook
OAuth (steps 8 and 9) reference those URLs in their consent
screens, so they need to resolve before you can complete OAuth
setup.

1. https://dash.cloudflare.com → Sign up (use
   `admin@snoringcat.games`).
2. Confirm email + 2FA.
3. **Generate an API token** for `wrangler` and CI use:
   - My Profile → API Tokens → Create Token → "Custom token".
   - Permissions:
     - **Account → Cloudflare Pages → Edit**
     - **Account → Account Settings → Read**
     - **Zone → DNS → Edit** (only if you also move DNS to
       Cloudflare; skip otherwise)
   - Account Resources: include the snoringcat-games account.
   - Zone Resources: include all zones (or none, if DNS stays
     at Hetzner).
4. Append: `CLOUDFLARE_API_TOKEN=<paste-token>`,
   `CLOUDFLARE_ACCOUNT_ID=<paste-from-dashboard-sidebar>`
5. **Connect the `snoringcat.games` repo to Cloudflare Pages:**
   - Workers & Pages → Create application → Pages → Connect to
     Git.
   - Authorize the SnoringCatGames GitHub org.
   - Pick `SnoringCatGames/snoringcat.games`.
   - Build configuration:
     - Framework preset: **None**
     - Build command: *(leave empty)*
     - Build output directory: `public`
   - Save and Deploy.
   - First deploy completes in ~30s; you get a preview URL like
     `snoringcat-games.pages.dev`.
6. **Verify the preview URL** loads the landing page and the
   three legal pages
   (`snoringcat-games.pages.dev/privacy/`, `/terms/`,
   `/data-deletion/`). Spot-check a redirect:
   `snoringcat-games.pages.dev/squirrel-away/privacy` should
   308 to the Google Doc.
7. **Add custom domains** in the Pages project: each of
   `snoringcat.games`, `www.snoringcat.games`,
   `snoringcatgames.com`, `www.snoringcatgames.com`. Cloudflare
   gives you the DNS records to create.
8. **DNS cutover at Hetzner Console** (this flips production
   traffic from levi.dev's Heroku app to Cloudflare Pages):
   - Lower TTL on the existing four records to 60s. Wait 24h if
     possible (or accept 1-4h propagation).
   - Replace each record per Cloudflare's instructions:
     - Apex (`snoringcat.games`, `snoringcatgames.com`):
       ALIAS / ANAME (Hetzner calls this "CNAME at apex")
       → `snoringcat-games.pages.dev`.
     - `www.*` subdomains: CNAME →
       `snoringcat-games.pages.dev`.
9. **Wait for propagation** (typically 5-30 min with low TTL):
   ```powershell
   "snoringcat.games","www.snoringcat.games","snoringcatgames.com","www.snoringcatgames.com" |
     ForEach-Object { Resolve-DnsName -Name $_ -Type A | Select-Object Name, IPAddress }
   ```
   Each should resolve to a Cloudflare IP.
10. **Cloudflare auto-provisions TLS** within ~10-15 min after
    DNS propagates. Verify:
    ```powershell
    curl.exe -sSI https://snoringcat.games/privacy/ | Select-Object -First 5
    ```
    Should show `HTTP/2 200`.
11. **Don't forget:** edit `levi.dev`'s `package.json::domains`
    array to remove the four `snoringcat.*` and
    `snoringcatgames.*` entries. Re-deploy levi.dev so Heroku
    stops trying to bind certs for those domains. (You can do
    this any time post-cutover; not blocking the migration.)

After this, your studio-level legal pages are live at
`https://snoringcat.games/{privacy,terms,data-deletion}/`. You
need them serving 200 before you finish steps 8 and 9, because
both OAuth provider consent screens point at those URLs.

> **Note: hopnbop.net stays on AWS for now.** It moves to
> Cloudflare Pages in Phase F of the migration. Until then,
> Hop 'n Bop's legal pages stay at `hopnbop.net/{privacy,
> terms,data-deletion}/`.

### 8. Google OAuth (for Google sign-in)

**Prerequisite:** step 7 complete (snoringcat.games legal pages
serving 200).

1. https://console.cloud.google.com → create or pick project
   (e.g. "Snoring Cat Games").
2. APIs & Services → OAuth consent screen → Configure.
   - User type: **External**.
   - App name: `Snoring Cat Games`. Support email + dev contact:
     yours (`admin@snoringcat.games`).
   - **Application home page:** `https://snoringcat.games/`.
   - **Application privacy policy link:**
     `https://snoringcat.games/privacy/`.
   - **Application terms of service link:**
     `https://snoringcat.games/terms/`.
   - Authorized domains: `snoringcat.games`.
   - Scopes: `email`, `profile`, `openid` (default).
   - Test users: add your email until you publish.
3. APIs & Services → Credentials → Create Credentials →
   OAuth client ID → **Web application**.
4. Authorized redirect URIs:
   `https://nakama.snoringcat.games/v2/account/authenticate/google`.
5. Append:
   - `GOOGLE_OAUTH_CLIENT_ID=<id>`
   - `GOOGLE_OAUTH_CLIENT_SECRET=<secret>`

### 9. Facebook OAuth (for Facebook sign-in)

**Prerequisite:** step 7 complete (snoringcat.games legal pages
serving 200). Facebook will spider the URLs during App Review;
they must respond 200.

1. https://developers.facebook.com → Log in (Facebook account).
2. My Apps → Create App.
   - Use case: **Authenticate and request data from users with
     Facebook Login**.
   - App type: **Consumer**.
   - App name: `Snoring Cat Games`.
3. Add product: **Facebook Login** → Web.
4. Settings → Basic:
   - App Domains: `snoringcat.games`.
   - Privacy Policy URL:
     `https://snoringcat.games/privacy/`.
   - Terms URL: `https://snoringcat.games/terms/`.
   - User data deletion URL:
     `https://snoringcat.games/data-deletion/`.
   - Save changes.
5. Facebook Login → Settings:
   - Valid OAuth Redirect URIs:
     `https://nakama.snoringcat.games/v2/account/authenticate/facebook`.
6. Settings → Basic → copy App ID and App Secret.
7. Append:
   - `FACEBOOK_APP_ID=<id>`
   - `FACEBOOK_APP_SECRET=<secret>`
8. **App Review:** when you go beyond test users, submit for
   review (Facebook requires this for production). Reviews take
   1-7 days. **Do this in parallel with the migration**, not
   blocking.

### 10. Verify AWS access still works

```powershell
aws sso login --profile hopnbop
aws sts get-caller-identity --profile hopnbop
```
Should print account `270469481989`. If expired, the SSO login
re-prompts in a browser.

(AWS credentials are managed by the AWS SSO flow on each
machine — not in `credentials.env`. The CLI handles caching.)

### 11. Generate SSH keypairs

Generate locally; we'll encrypt them in step 12.

```powershell
ssh-keygen -t ed25519 -f "$HOME\.hopnbop-migration\ssh\nakama"   -N '""' -C "nakama"
ssh-keygen -t ed25519 -f "$HOME\.hopnbop-migration\ssh\postgres" -N '""' -C "postgres"
```

Note the `-N '""'` (single-quoted double quotes) — that's the
PowerShell incantation that passes a literal empty string for
the passphrase to `ssh-keygen.exe`. Plain `-N ""` doesn't
work; PowerShell drops the empty argument before the exe sees
it.

Public keys (`*.pub`) are non-sensitive and stay readable.
NTFS user-profile perms already restrict the private keys.

### 11b. Generate Pulumi state passphrase

Pulumi encrypts the secrets it stores in its S3 state file
(server IDs are non-sensitive but we'll also store generated
secrets like the Hetzner project's API token cache there). The
encryption uses a **passphrase** that needs to be available
whenever `pulumi up` runs. Cleanest: store it in
`credentials.env` so it's age-encrypted alongside everything
else.

Generate a strong passphrase and append:

```powershell
$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$pw = [Convert]::ToBase64String($bytes)
"PULUMI_CONFIG_PASSPHRASE=$pw" |
  Out-File -Append -Encoding ASCII $HOME\.hopnbop-migration\credentials.env
Remove-Variable bytes, pw
```

Phase A's Pulumi commands set `PULUMI_CONFIG_PASSPHRASE` from
the sourced `credentials.env`. If you ever lose this passphrase,
you can't decrypt Pulumi-stored secrets in the state file —
re-create the stack from scratch (Hetzner resources still
exist; Pulumi state can be rebuilt with `pulumi import`).

### 12. Encrypt and push to claude-config

Encrypt `credentials.env` and the two SSH private keys to the
multi-recipient `.age` files. Use the real claude-config path
(not the `~/.claude/secrets` junction — PowerShell sometimes
refuses to traverse it as an "untrusted mount point"):

```powershell
$age = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\FiloSottile.age_*\age\age.exe" -ErrorAction Stop).FullName
$secrets = "$HOME\Repositories\claude-config\secrets"
$recipients = "$secrets\hopnbop-migration.recipients"
$mig = "$HOME\.hopnbop-migration"

& $age -R $recipients -o "$secrets\hopnbop-migration.env.age"          "$mig\credentials.env"
& $age -R $recipients -o "$secrets\hopnbop-migration-nakama-ssh.age"   "$mig\ssh\nakama"
& $age -R $recipients -o "$secrets\hopnbop-migration-postgres-ssh.age" "$mig\ssh\postgres"
```

Commit + push (the PostToolUse auto-push hook may handle this;
if not, run manually):

```powershell
Push-Location $HOME\Repositories\claude-config
git add secrets/hopnbop-migration.recipients `
        secrets/hopnbop-migration.env.age `
        secrets/hopnbop-migration-nakama-ssh.age `
        secrets/hopnbop-migration-postgres-ssh.age
git commit -m "Add encrypted hopnbop migration credentials"
git push
Pop-Location
```

**Sanity check the encrypted file:**

```powershell
$count = (& $age -d -i "$HOME\.config\age\key.txt" "$secrets\hopnbop-migration.env.age" |
          Select-String -Pattern "^[A-Z_]+=").Count
"Decrypted line count: $count  (expected: 13)"
```

### 13. On the laptop: pull and decrypt

After pulling the latest claude-config on the laptop:

```powershell
$age = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\FiloSottile.age_*\age\age.exe" -ErrorAction Stop).FullName
$key = "$HOME\.config\age\key.txt"
$secrets = "$HOME\Repositories\claude-config\secrets"
$mig = "$HOME\.hopnbop-migration"

New-Item -ItemType Directory -Path $mig\ssh -Force | Out-Null

# Decrypt with -o (avoids PowerShell `>` redirect adding a UTF-16 BOM
# that would corrupt SSH keys).
& $age -d -i $key -o $mig\credentials.env  "$secrets\hopnbop-migration.env.age"
& $age -d -i $key -o $mig\ssh\nakama       "$secrets\hopnbop-migration-nakama-ssh.age"
& $age -d -i $key -o $mig\ssh\postgres     "$secrets\hopnbop-migration-postgres-ssh.age"

# Regenerate public keys (cheap, derived from private). Use Out-File
# -Encoding ASCII so .pub files aren't UTF-16-with-BOM.
ssh-keygen -y -f $mig\ssh\nakama   | Out-File -Encoding ASCII $mig\ssh\nakama.pub
ssh-keygen -y -f $mig\ssh\postgres | Out-File -Encoding ASCII $mig\ssh\postgres.pub
```

Now the laptop has a working copy. Both machines are in sync.

### Runtime credential consumption (how the agent reads secrets)

Phase scripts source the already-decrypted file directly into
the current PowerShell session's environment. No per-session
decrypt needed:

```powershell
Get-Content $HOME\.hopnbop-migration\credentials.env | ForEach-Object {
  if ($_ -match '^([A-Z_]+)=(.*)$') {
    Set-Item "Env:$($Matches[1])" $Matches[2]
  }
}
```

If you want paranoid mode (decrypt fresh each phase, never sit
on disk between sessions): re-decrypt to a temp directory,
import to env, scrub on completion:

```powershell
$age = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\FiloSottile.age_*\age\age.exe" -ErrorAction Stop).FullName
$temp = New-Item -ItemType Directory -Path "$env:TEMP\hopnbop-mig-$(New-Guid)" -Force
try {
  $envFile = "$($temp.FullName)\credentials.env"
  & $age -d -i $HOME\.config\age\key.txt -o $envFile `
        "$HOME\Repositories\claude-config\secrets\hopnbop-migration.env.age"
  Get-Content $envFile | ForEach-Object {
    if ($_ -match '^([A-Z_]+)=(.*)$') { Set-Item "Env:$($Matches[1])" $Matches[2] }
  }
  # ... do work ...
} finally {
  Remove-Item -Recurse -Force $temp.FullName
}
```

Default phase scripts use the persistent-decrypt approach
(file at `$HOME\.hopnbop-migration\credentials.env`,
gitignored). Switch to paranoid mode by setting
`$env:MIGRATION_DECRYPT_FRESH = "1"` before running a phase.

### Adding new secrets generated during phases

Phase A generates the Postgres password, Nakama console password,
server key, and session encryption key. The agent appends those
to `$HOME\.hopnbop-migration\credentials.env`, re-encrypts to
`hopnbop-migration.env.age`, and the auto-push hook propagates
to the other machine. Pull on the other machine + re-decrypt to
sync.

### Key and credential rotation

Three rotation scenarios. Run these procedures *before* the
incident, not after.

**A. Adding a new machine (e.g., a new laptop).**

1. On the new machine: install `age`, run `age-keygen`, save the
   public key.
2. On any existing machine: pull `claude-config`, append the new
   public key to `secrets/hopnbop-migration.recipients`, commit,
   push.
3. On any existing machine: re-encrypt `credentials.env` and
   the SSH `.age` files using the updated recipients list (same
   commands as pre-flight step 11). Commit, push.
4. On the new machine: pull `claude-config`, decrypt to
   `~/.hopnbop-migration/` (same commands as pre-flight step
   12), create the `~/.claude/secrets` junction.

No live credential rotation needed — the new key has access to
the same secrets, that's the point.

**B. A machine is lost / its age private key may be compromised.**

This is serious. Old `.age` blobs in `claude-config` git
history are decryptable forever by anyone holding that key, so
you must assume **every credential ever encrypted to that key
is exposed**. Procedure:

1. Remove that machine's public key from
   `secrets/hopnbop-migration.recipients`. Commit, push.
2. Rotate **every** secret in `credentials.env`:
   - Hetzner Cloud token: revoke at console.hetzner.com, create
     new one.
   - Hetzner DNS token: revoke + create.
   - Edgegap token: revoke + create.
   - GitHub PAT: revoke at github.com/settings/tokens, create
     new.
   - Discord webhook: delete + recreate at the channel.
   - UptimeRobot API key: rotate.
   - Google OAuth client secret: rotate at console.cloud.google.com.
   - Facebook App Secret: rotate at developers.facebook.com.
   - Pulumi passphrase: re-encrypt the Pulumi state with a new
     passphrase via `pulumi stack change-secrets-provider`.
   - Hetzner SSH keys: generate new pair, add to `authorized_keys`
     on the boxes, remove old key.
   - Postgres password, Nakama console password, server keys,
     session encryption key: rotate by editing Nakama config and
     restarting (use `pulumi up` if Pulumi-managed).
3. Re-encrypt fresh `credentials.env` to a new `.age` blob using
   the trimmed recipients list. Commit, push.
4. Optionally: rewrite `claude-config` git history to remove old
   `.age` blobs (`git filter-repo` or `bfg-repo-cleaner`). Note
   that this is cosmetic — anyone who already cloned has them
   forever. The cred rotation in step 2 is what actually
   matters.

**C. Routine rotation (annually, or after major project events).**

Rotate the high-value subset on a schedule:
- AWS-related: rotated automatically by SSO; nothing to do.
- Hetzner / Edgegap / GitHub tokens: rotate annually. Same
  procedure as B step 2 but only for those tokens.
- Discord / UptimeRobot: low-value; rotate every couple of years.
- Pulumi passphrase: rotate every couple of years.
- age private keys: rotate when machines are replaced.

**Rotation does NOT require:** revoking and reissuing the OAuth
provider apps themselves (Google / Facebook). Those are stable
across token rotations; you only rotate the *client secret*
within the same app.

---

## State file format

`~/.hopnbop-migration/state.json` (non-sensitive only — all
secrets live in the age-encrypted credentials file):

```json
{
  "version": 1,
  "started_at": "2026-04-27T18:00:00Z",
  "current_phase": "A",
  "phases": {
    "A": { "status": "pending", "completed_at": null, "notes": [] },
    "B": { "status": "pending", "completed_at": null, "notes": [] },
    "C": { "status": "pending", "completed_at": null, "notes": [] },
    "D": { "status": "pending", "completed_at": null, "notes": [] },
    "E": { "status": "pending", "completed_at": null, "notes": [] },
    "F": { "status": "pending", "completed_at": null, "notes": [] },
    "G": { "status": "pending", "completed_at": null, "notes": [] }
  },
  "infrastructure": {
    "hetzner_nakama_server_id": null,
    "hetzner_nakama_ip": null,
    "hetzner_postgres_server_id": null,
    "hetzner_postgres_ip": null,
    "hetzner_staging_server_id": null,
    "hetzner_staging_ip": null,
    "hetzner_private_network_id": null,
    "nakama_url": "https://nakama.snoringcat.games",
    "nakama_version": null,
    "edgegap_app_name": "hopnbop-server",
    "edgegap_app_version": null,
    "edgegap_image_uri": null
  },
  "verification": {
    "phase_a_healthcheck_at": null,
    "phase_b_alert_test_at": null,
    "phase_c_allocation_test_at": null,
    "phase_d_smoke_test_at": null,
    "phase_e_data_reconciliation_at": null,
    "phase_f_aws_decommission_at": null,
    "phase_g_ci_green_at": null
  },
  "known_issues": []
}
```

Each phase reads state at start, validates expected fields are
populated, writes updates at end. Phase scripts treat `pending`/
`in_progress`/`completed`/`failed` as a state machine; re-running
a `failed` phase is safe (idempotent).

---

## Phase A — Foundation: Hetzner, Nakama, Postgres, Caddy, auth

**Estimated time:** ~3 hours.
**Manual gates:** none.
**Prerequisites:** pre-flight done; nameserver propagation
complete (verify with `dig +short ns snoringcat.games`).

### Goal

Healthy Nakama at `https://nakama.snoringcat.games`. TLS valid.
Postgres reachable on private network. Google + Facebook OAuth
configured. Admin console accessible from your IP only.

### Steps

1. **Source credentials** from
   `~/.hopnbop-migration/credentials.env` (decrypted in
   pre-flight step 12/13). Validate all 13 expected vars are
   non-empty (10 provider tokens + `CLOUDFLARE_API_TOKEN` +
   `CLOUDFLARE_ACCOUNT_ID` + `PULUMI_CONFIG_PASSPHRASE`).
   `HETZNER_DNS_TOKEN` was dropped because Cloudflare manages
   all studio DNS now (see pre-flight step 2).
   If file is missing, decrypt from
   `~/.claude/secrets/hopnbop-migration.env.age`.
   Export `PULUMI_CONFIG_PASSPHRASE` and
   `CLOUDFLARE_API_TOKEN` so subsequent `pulumi` commands can
   manage Hetzner Cloud + Cloudflare DNS resources.
2. Initialize state file at `~/.hopnbop-migration/state.json` if
   missing.
3. **Pulumi project setup** (one-time, idempotent):
   - Create directory `infra/pulumi/snoringcat-platform/`.
   - `pulumi new hetzner-go --name snoringcat-platform`.
   - Add Cloudflare provider too:
     `cd infra/pulumi/snoringcat-platform && go get github.com/pulumi/pulumi-cloudflare/sdk/v5`.
   - State backend: S3 bucket `hopnbop-pulumi-state` (create if
     not exists, in `us-west-2`, versioning + encryption on).
   - Configure both providers' tokens:
     - `pulumi config set hetzner:token $HCLOUD_TOKEN --secret`
     - `pulumi config set cloudflare:apiToken $CLOUDFLARE_API_TOKEN --secret`
4. **Declare infra in Pulumi** (Go code under
   `infra/pulumi/snoringcat-platform/`). Two providers, one
   stack:

   **Hetzner Cloud (compute):**
   - SSH key resources: load `*.pub` files from
     `~/.hopnbop-migration/ssh/`, register with Hetzner.
   - Private network `snoringcat-internal` (10.0.0.0/16).
   - Server `nakama-prod-1` (CAX11, Hillsboro, Ubuntu 24.04,
     attach to private network).
   - Server `postgres-prod-1` (CAX11, Hillsboro, Ubuntu 24.04,
     attach to private network).
   - Hetzner Cloud Firewall rules:
     - Nakama: 22/tcp from your IP, 80+443/tcp from world.
     - Postgres: 22/tcp from your IP, 5432/tcp from Nakama
       private IP only.

   **Cloudflare DNS (records in the existing
   `snoringcat.games` zone — created during pre-flight by
   the user adopting the zone in Cloudflare):**
   - A record `nakama.snoringcat.games` → Nakama public IP.
     Proxied: **off** (gray cloud) &mdash; Nakama uses
     long-lived WebSocket and gRPC, Cloudflare's free-tier
     proxy has timeouts that don't fit, and we don't need
     Cloudflare's caching for an API endpoint. TTL: Auto.
   - (Phase B will add `grafana.snoringcat.games`; Phase G
     will add `nakama-staging.snoringcat.games`. Both follow
     the same DNS-only pattern.)

   **Pulumi outputs:** server IDs, public IPs, private IPs,
   DNS record IDs.
5. `pulumi up`. State persists to S3. Outputs written to state
   file.
6. SSH in to both boxes (using the private keys at
   `~/.hopnbop-migration/ssh/`). Poll until reachable, then:
   - `apt update && apt upgrade -y`
   - Install Docker + Docker Compose (`get.docker.com` script).
   - Install fail2ban, ufw (configure to match cloud firewall).
7. **Postgres box** (`/opt/postgres/docker-compose.yml`):
   - Postgres 16, persistent volume `/var/lib/postgresql/data`.
   - Strong password generated by the agent and appended to
     `~/.hopnbop-migration/credentials.env` as
     `POSTGRES_PASSWORD=...`. After Phase A completes, the
     credentials file is re-encrypted to
     `~/.claude/secrets/hopnbop-migration.env.age` and pushed
     via the dotfiles auto-push hook (so the laptop gets the
     new value on next pull + decrypt).
   - `pg_hba.conf` restricts to private network CIDR.
   - Bring up; verify `psql` connection from Nakama box over
     private network.
8. **Nakama box** (`/opt/nakama/docker-compose.yml`):
   - Nakama latest stable.
   - Caddy with automatic Let's Encrypt for
     `nakama.snoringcat.games`.
   - Nakama config:
     - `database.address` → Postgres private IP.
     - Console password, server key, session encryption key all
       generated and appended to
       `~/.hopnbop-migration/credentials.env` as
       `NAKAMA_CONSOLE_PASSWORD`, `NAKAMA_SERVER_KEY`,
       `NAKAMA_SESSION_ENCRYPTION_KEY`.
     - Google + Facebook OAuth credentials sourced from the
       running shell (loaded in step 1).
   - Bring up Caddy first; verify TLS issuance (poll Caddy logs
     until `certificate obtained successfully`).
   - Bring up Nakama; verify container healthy.
9. Hit `https://nakama.snoringcat.games/healthcheck` (poll up to
   60s, expect 200).
10. SSH-tunnel to console port `:7351`, log in with admin
    password, verify console loads.
11. Smoke test: `curl -X POST` Nakama anonymous-auth endpoint
    with a test device ID, verify session token returned.
12. **Re-encrypt updated credentials**:
    `age -R ~/.claude/secrets/hopnbop-migration.recipients
    -o ~/.claude/secrets/hopnbop-migration.env.age
    ~/.hopnbop-migration/credentials.env`. The dotfiles
    auto-push hook syncs to remote. (On laptop: pull
    claude-config and re-decrypt to pick up Phase A's generated
    secrets.)
13. Update state: phase A `completed`, populate infrastructure
    fields.
14. Post Discord summary: "Phase A complete. Nakama healthy at
    {url}. Generated secrets re-encrypted to claude-config."

### Verification (autonomous)

- Healthcheck 200.
- Anonymous auth returns valid session token.
- Console reachable.
- Postgres connection from Nakama box succeeds.

### Manual gate before Phase B

None. Can chain immediately, or you can hit
`https://nakama.snoringcat.games/healthcheck` in a browser to
confirm. ~30 sec.

---

## Phase B — Operations stack

**Estimated time:** ~2 hours.
**Manual gates:** none.

### Goal

Prometheus + Grafana + Loki self-hosted on Nakama box. All
exporters scraping. Discord-wired alerts. UptimeRobot synthetic
checks. Daily cost script as systemd timer.

### Steps

1. Append to Nakama Docker Compose:
   - `prometheus`, `grafana`, `loki`, `promtail` containers.
   - `node_exporter` on both Nakama and Postgres boxes.
   - `postgres_exporter` sidecar.
   - Caddy config: reverse-proxy `grafana.snoringcat.games` →
     Grafana, behind basic auth (admin password in state).
2. DNS A record `grafana.snoringcat.games` → Nakama IP.
3. Prometheus scrape configs (Nakama metrics, Postgres exporter,
   both node exporters, Caddy metrics).
4. Grafana provisioning:
   - Datasources: Prometheus, Loki.
   - Dashboards: Nakama official, node_exporter full,
     postgres-exporter, Caddy.
5. Grafana Alerting:
   - Contact point: Discord webhook from credentials.
   - Rules per `platform-pivot-discussion.md` Operations →
     Alerts section (critical + warning tiers).
6. UptimeRobot via API:
   - `https://nakama.snoringcat.games/healthcheck` (HTTPS,
     5-min).
   - Webhook destination: Discord.
7. Daily cost script
   (`/opt/snoringcat/cost-monitor/cost-monitor.sh`):
   - Polls Hetzner Cloud + Edgegap APIs for MTD spend.
   - Writes daily Discord summary.
   - If grand total > `$EMERGENCY_CAP` (default $50), triggers
     emergency shutdown: Edgegap fleet → 0, optionally
     `hcloud server poweroff` on game-server boxes.
   - Systemd timer: daily at 09:00 UTC.
8. Trigger one alert manually (stop Nakama for 3 min) to confirm
   Discord notification arrives, then restart.

### Verification (autonomous)

- Grafana reachable at `https://grafana.snoringcat.games` (basic
  auth).
- All Prometheus targets show "UP".
- Test alert posted to Discord channel.
- UptimeRobot status: green.
- Cost script ran once successfully (test invocation).

---

## Phase C — Edgegap fleet + game-server image

**Estimated time:** ~3 hours.
**Manual gates:** one (~2 min in Edgegap UI).

### Goal

Edgegap app `hopnbop-server` configured. New slim game-server
Docker image pushed. Nakama runtime module for fleet allocation
deployed and tested.

### Steps

1. Build new game-server Docker image (`Dockerfile.edgegap`):
   - Base: Ubuntu 24.04.
   - Vanilla `webrtc-native` v1.0.9 GDExtension (no patch
     needed — Edgegap port-forwards directly).
   - **Removed:** GameLift Server SDK builder stage.
   - **Removed:** webrtc-builder patch stage.
   - **Removed:** nginx config (no port-remapping; Edgegap maps
     declared container ports directly).
   - **Removed:** `entrypoint.sh` Route 53 logic.
   - Copy Godot Linux server `.pck` (built via existing PS
     script with `-SkipExport` after manual export).
2. Use Godot CLI to export Linux server `.pck`:
   ```powershell
   godot --headless --export-pack "Linux Server" \
     build/linux/hopnbop_server.pck
   ```
3. `docker build` with the new Dockerfile.
4. Use Edgegap CLI/API:
   - Create app `hopnbop-server` if not exists.
   - Push image to Edgegap registry (tag matches
     `project.godot` `config/version`).
   - Create app version with port mappings:
     - 4433/UDP (ENet + WebRTC).
     - 4434/TCP (signaling, when WebRTC).
   - Set CPU/RAM: 1 vCPU / 1 GB initial.
5. Deploy a Go Nakama runtime module: `fleet_allocator.go`.
   - Implements `MatchmakerMatched` hook.
   - Calls Edgegap REST API to allocate a deployment.
   - Awaits `READY` state, returns connection info to clients
     via Nakama notification.
6. Nakama runtime module: `match_lifecycle.go`.
   - `register_server` RPC: game server checks in after boot.
   - `match_end` RPC: game server reports results, triggers
     leaderboard updates.
7. Restart Nakama container to load new runtime modules.
8. **Manual gate:** you click in Edgegap UI to confirm budget
   alerts at $20/$40/$80 thresholds. (~2 min.)
9. Test allocation:
   - Synthetic test: post matchmake ticket via Nakama RPC,
     trigger fake match, observe Edgegap allocates, server
     boots, registers via `register_server` RPC.

### Verification (autonomous)

- Image pushed to Edgegap registry.
- App version visible in Edgegap dashboard.
- Synthetic allocation completes within 30 sec.
- Game server registers via Nakama RPC.

### Manual gate before Phase D

You confirm via Discord (post a checkmark) once budget alerts
are configured.

---

## Phase D — Strip GameLift, swap client SDK to nakama-godot

**Estimated time:** ~4 hours.
**Manual gates:** one (~10 min editor smoke test).

### Goal

Game server: zero GameLift code. Vanilla webrtc-native v1.0.9.
No nginx. Boots cleanly under Edgegap.

Client: SDK seams in `src/core/` swap implementations to
nakama-godot. Method signatures stay; bodies talk to Nakama. Game
runs end-to-end against new stack in editor.

### Steps

**Server side:**

1. Add `addons/nakama` (nakama-godot SDK) — vendored or
   submoduled.
2. Update `addons/gamelift_session_manager` (currently submoduled
   from `SnoringCatGames/godot-gamelift-session-manager`):
   - Rename remote to `godot-platform-session-manager`.
   - Add `EdgegapPlatformProvider` class implementing the
     existing provider interface.
   - Mark `GameLiftPlatformProvider` deprecated; remove all
     production code paths that use it.
3. `Dockerfile.edgegap` already replaces `Dockerfile` — delete
   old `Dockerfile`.
4. Delete `gamelift-deploy/patch-webrtc-portrange.py` and the
   webrtc-builder Docker stage.
5. Delete nginx config files.
6. Delete `entrypoint.sh` Route 53 logic; replace with a thin
   "register with Nakama" startup hook.

**Client side:**

7. `src/core/auth_client.gd`: swap implementation to call
   `NakamaSession.authenticate_*`. Keep public method signatures
   identical.
8. `src/core/backend_api_client.gd`: same. Replace HTTPRequest
   calls with Nakama RPCs. Delete `warm_up_fleet()`,
   `is_fleet_ready()`, `is_fleet_warming_up()`,
   `get_fleet_estimated_remaining_sec()`.
9. `src/core/friends_api_client.gd`: route through Nakama
   friends API.
10. `src/core/party_api_client.gd`: route through Nakama
    groups/realtime party API.
11. `src/core/crash_reporter.gd`: route through Nakama RPC (or
    keep on direct HTTPS to a Nakama runtime endpoint).
12. UI cleanup:
    - `lobby_level.tscn` → remove `FleetWarmupLabel`.
    - `loading_screen.gd` → remove `LOADING.WARMING_UP_SERVER`
      phase + `is_fleet_warming_up()` branch.
    - `LocalSettings.setting_override_changed` → remove warmup
      retrigger path.

**Test:**

13. Run GUT unit + integration tests. Triage failures:
    - Tests that mock AWS API: re-mock against Nakama or
      delete.
    - Tests that exercise warmup UI: delete (the UI is gone).
14. Run GDScript formatter; fix any drift.

### Verification (autonomous)

- All GUT tests green.
- Server image builds cleanly.
- Linter clean.

### Manual gate before Phase E (CRITICAL)

You run the game in editor (Customize Run Instances: 1 server +
2 clients). Confirm:

- Anonymous login works.
- Lobby loads, friends list loads.
- Party invitation works.
- Matchmaking ticket created.
- Edgegap allocates server.
- Match starts, ends cleanly. Result reported to leaderboard.

If anything fails: post details to chat, I fix in a follow-up
session before Phase E.

---

## Phase E — Data migration

**Estimated time:** ~3 hours.
**Manual gates:** one (you approve before destructive cutover).

### Goal

Friends graph, leaderboards, settings, player records moved DDB →
Postgres + Nakama Storage. Source of truth flips to Nakama.

### Steps

1. Author `third_party/snoringcat-platform/scripts/migrate_ddb_to_nakama.py`:
   - Reads `aws ddb scan` paginated for each table:
     `hopnbop-players`, `hopnbop-friends`, `hopnbop-parties`,
     `hopnbop-leaderboards`, `hopnbop-settings`,
     `hopnbop-match-history`.
   - Writes to Nakama via Storage API + custom RPCs.
   - Idempotent: uses `if_not_exists` semantics.
   - Logs every record + outcome to a local JSONL file.
2. **Dry run** against staging Nakama (will be created during
   Phase G; for now, against prod Nakama in a sandboxed `staging-`
   namespace).
3. Sample 100 records of each type. Verify shape correctness in
   Nakama console.
4. Run reconciliation pass: read both DDB and Nakama, diff,
   surface anomalies.
5. **Manual gate (CRITICAL):** I post counts (e.g., "12,453
   players migrated, 0 mismatches"). You approve before
   destructive flip.
6. **Real run.** Stream all DDB content to Nakama (production
   namespace).
7. Set DDB tables to read-only via IAM policy. New writes flow
   to Nakama only. (Don't delete tables yet — Phase F does
   that.)
8. Spot-check: a player's leaderboard score, friends, settings
   match between DDB and Nakama.

### Verification (autonomous)

- Migration script ran to completion.
- Reconciliation pass: zero mismatches (or differences within
  tolerance for floating-point counters).
- DDB tables read-only.

---

## Phase F — DNS cutover + AWS decommission (GATED)

**Estimated time:** ~3 hours.
**Manual gates:** **explicit "approve decommission" message
required**.

### Goal

Production traffic on Nakama+Edgegap. AWS resources deleted.
`hopnbop.net` migrated to Cloudflare Pages (matching the host
already chosen for `snoringcat.games`). Net AWS cost drops to
$0/mo.

### Steps

1. Diff: I list **every AWS resource I'm about to delete**:
   - GameLift fleet `containerfleet-...`
   - Container group definition `hopnbop-server-group`
   - FlexMatch matchmaker `hopnbop-ffa-matchmaker`
   - Game session queue `hopnbop-game-queue`
   - FlexMatch ruleset `hopnbop-ffa-ruleset`
   - SAM stack `hopnbop-backend` (Lambdas + API Gateway + DDB)
   - ECR repo `hopnbop-server`
   - Secrets Manager `hopnbop/tls-wildcard-cert`,
     `hopnbop/server-api-key`
   - Route 53 records under `game.hopnbop.net` (per-server A
     records)
   - **Website hosting:** S3 bucket `hopnbop-website` and
     CloudFront `E3LT833LSVTW9R` &mdash; will be migrated to
     Cloudflare Pages first (steps 7-9 below), then deleted.
   - **Preserved:** Route 53 zone `hopnbop.net` (DNS records
     stay; only the apex / www records are repointed at
     Cloudflare).
2. **You approve in chat.** Without an explicit "yes proceed" or
   similar, I do not delete anything.
3. Switch DNS A record `api.hopnbop.net` &rarr; Nakama (already
   `nakama.snoringcat.games`, but keep `api.hopnbop.net`
   working as a CNAME during the transition).
4. Wait for propagation (poll DNS until both old and new
   resolve to Nakama; typically 5-30 min).
5. Verify production traffic now hits Nakama (UptimeRobot +
   Grafana).
6. Drain GameLift: set fleet DESIRED=0, wait for game-session
   count &rarr; 0 (in-flight matches finish naturally).

#### 7. Migrate `hopnbop.net` to Cloudflare Pages

Mirrors what we did for `snoringcat.games` in pre-flight:
add the domain as a Cloudflare zone, change nameservers at the
registrar, attach as a Pages custom domain. `hopnbop.net` is a
separate Cloudflare Pages project from `snoringcat-games`
because it serves the Godot 4 web export at root, which has
different headers and a different deploy pipeline.

   a. **Add a `web/_headers` file** to `hopnbop_private` with
      the Godot 4 web requirements:
      ```
      /*
        Cross-Origin-Opener-Policy: same-origin
        Cross-Origin-Embedder-Policy: require-corp
        Cross-Origin-Resource-Policy: same-origin
      ```
      Plus aggressive cache headers for the WASM/PCK blobs:
      ```
      /*.wasm
        Cache-Control: public, max-age=31536000, immutable
      /*.pck
        Cache-Control: public, max-age=604800
      ```
   b. **Create a Cloudflare Pages project** pointing at
      `SnoringCatGames/hopnbop_private`, branch `main`, build
      output directory `web`. (Cloudflare Pages can deploy
      from a private repo and a subdirectory.)
   c. **Update `scripts/deploy-website.ps1`**: replace the
      `aws s3 sync` + `aws cloudfront create-invalidation`
      steps with `wrangler pages deploy web/`. The Godot
      `--export-release "Web"` step stays as-is.
   d. **Verify** that `hopnbop-website.pages.dev` (or whatever
      Pages-assigned URL) loads the game cleanly &mdash;
      specifically test that `crossOriginIsolated === true` in
      the browser DevTools console (means COOP/COEP are
      correct and SharedArrayBuffer is available).
   e. **Add `hopnbop.net` as a Cloudflare zone:**
      - Cloudflare dashboard &rarr; Add Site &rarr; enter
        `hopnbop.net` &rarr; Free plan.
      - Cloudflare imports existing DNS records (currently
        served by AWS Route 53 hosted zone
        `Z05562172A1JF6AX39U2N`). Spot-check the import.
      - Cloudflare gives you two nameservers.
      - At the domain registrar (look up via WHOIS or check
        records you have), change nameservers to Cloudflare's.
      - Wait for Cloudflare to mark the zone active (5 min -
        24h).
   f. **Add `hopnbop.net` and `www.hopnbop.net` as Pages
      custom domains** on the new `hopnbop-website` Pages
      project. If you hit "domain already in use" errors,
      delete the conflicting A / CNAME records in Cloudflare
      DNS first (same procedure as during pre-flight for
      `snoringcat.games`).
   g. **Update the Pulumi Cloudflare DNS module** to manage
      the `hopnbop.net` zone too, including any per-server A
      records that survived the Edgegap cutover. Note that
      the legacy `s-{ip}.game.hopnbop.net` per-server pattern
      from the GameLift era is gone (Edgegap allocates with
      its own hostnames).
   h. **Verify in production:** game loads via
      `https://hopnbop.net/`, leaderboards/blog/legal pages
      all reachable.

#### 8. AWS teardown via Pulumi adopt-and-destroy

Create a new Pulumi stack `aws-decommission` (separate from
`snoringcat-platform`) that imports the existing AWS resources
by ARN, then destroys them in dependency order:

   - matchmaker, queue, ruleset
   - fleet, container group definition
   - ECR repo, Secrets Manager secrets
   - then `sam delete` for the SAM stack (DDB tables
     auto-deleted)
   - **then** S3 bucket `hopnbop-website` (now empty / not in
     use after step 7), CloudFront distribution
     `E3LT833LSVTW9R`
   - **then** Route 53 records under `game.hopnbop.net` and
     the entire Route 53 hosted zone for `hopnbop.net`
     (`Z05562172A1JF6AX39U2N`) &mdash; **only after** the
     Cloudflare zone for `hopnbop.net` is active and
     authoritative (verified by `whois hopnbop.net` showing
     Cloudflare nameservers and `dig +trace hopnbop.net NS`
     resolving via Cloudflare).

Pulumi gives a clean diff of what was destroyed and a
recoverable state if the teardown fails partway.

   **Preserved (NOT in the destroy stack):** none. All AWS
   resources are destroyed in this phase, including the Route
   53 zone for `hopnbop.net` (DNS now lives in Cloudflare).

9. Set CloudWatch budget alarm at $5/mo (catches anything we
   missed; should never trigger if teardown was clean).
10. Update `hopnbop_private/CLAUDE.md`: remove the GameLift /
    AWS resources section, replace with Nakama+Edgegap +
    Cloudflare-Pages architecture notes (or replace with a
    pointer to
    `third_party/snoringcat-platform/PLATFORM_ARCHITECTURE.md`).
11. After 30 days, you decide whether to fully close the AWS
    account (separate manual step, not in this phase).

### Verification (autonomous)

- AWS Cost Explorer: GameLift hours, S3 hopnbop-website,
  CloudFront = 0 going forward.
- UptimeRobot: all green.
- Test match plays end-to-end on prod.
- `https://hopnbop.net/` loads the Godot web export, browser
  reports `crossOriginIsolated === true`.
- `aws cloudformation describe-stacks --stack-name hopnbop-backend`
  returns `does not exist`.
- `aws s3 ls hopnbop-website` returns `NoSuchBucket`.

---

## Phase G — CI workflows + staging instance

**Estimated time:** ~2 hours.
**Manual gates:** one (push noop branch, confirm CI green).

### Goal

`pr-validate.yml`, `nightly-smoke.yml`, `release.yml` live.
Staging Nakama on a CX21 in Hillsboro for nightly smoke runs.
AWS-aware tests stripped or re-pointed.

### Steps

1. Provision `nakama-staging-1` (CX21 Hillsboro). Same Docker
   Compose stack as prod, separate Postgres container, separate
   DNS (`nakama-staging.snoringcat.games`).
2. Author `.github/workflows/pr-validate.yml`:
   - Runs on PR to `main`.
   - GDScript formatter check.
   - GUT unit + integration (per-file invocation).
   - `go test`, `go vet`, `staticcheck` for Nakama runtime
     modules.
   - Compliance suite from `third_party/snoringcat-platform`
     against ephemeral Nakama+Postgres in Docker Compose.
3. Author `.github/workflows/nightly-smoke.yml`:
   - Scheduled `cron: '0 3 * * *'`.
   - Runs against staging Nakama.
   - Anon auth → matchmake → Edgegap allocate → match → result
     reporting → leaderboard.
   - 10-ticket sustained-load test.
   - Headless Chromium for web-client variant.
   - Discord ping on failure.
4. Author `.github/workflows/release.yml`:
   - Trigger: tag matching `v*.*.*`.
   - Build Linux server image, push to Edgegap registry, bump
     fleet version.
   - Build Godot web export, deploy via
     `wrangler pages deploy web/` to the `hopnbop-website`
     Cloudflare Pages project (after Phase F migration; see
     `web/_headers` for COOP/COEP requirements). Pre-Phase-F
     this step still uses `aws s3 sync` + CloudFront
     invalidation.
   - Build native exports for Windows / Mac / Linux / Steam.
   - Roll Nakama runtime modules (Docker Compose pull + restart).
   - Post release notes to Discord.
5. Strip / re-target existing CI:
   - Delete AWS-specific tests (SAM build, moto-mocked DDB,
     GameLift integration).
   - Re-target compliance suite from AWS API → Nakama API.
6. Update `hopnbop_private/CLAUDE.md`:
   - Replace deploy sections with Edgegap deploy.
   - Replace SAM/CDK with Docker Compose / `runtime go build`
     (under `third_party/snoringcat-platform/runtime/`).
   - Update AWS Resources section.

### Verification (autonomous)

- Pushes a noop branch + draft PR; confirms `pr-validate.yml`
  runs green.
- Triggers `nightly-smoke.yml` manually via `workflow_dispatch`;
  confirms green.
- Staging Nakama healthcheck green.

### Manual gate after Phase G

You confirm CI is healthy by checking the GitHub Actions tab.

---

## Soak (passive, several days)

After Phase G, the migration is functionally complete. Then:

- Watch Discord alerts for the first 7 days.
- Daily cost-dashboard review.
- Triage WebRTC ICE failure rate, match-abandonment rate.
- Iteratively fix issues via the release pipeline.
- After 14 days clean, declare migration done. Update this doc
  with a "DONE" banner and archive `platform-pivot-discussion.md`
  to `docs/archive/`.

---

## Mid-migration manual interruptions (summary)

| Between | What you do | Time |
|---|---|---|
| Pre-flight start | Browser session: 12 accounts/tokens + Cloudflare Pages setup + DNS cutover for snoringcat.games | 90-120 min |
| Pre-flight DNS wait | Wait for `snoringcat.games` to flip to Cloudflare before doing OAuth steps 8-9 | 5-30 min (passive) |
| Phase A → B | (optional) hit healthcheck URL in browser | 30 sec |
| Phase B → C | none | — |
| Phase C → D | click budget-alert thresholds in Edgegap UI | 2 min |
| Phase D → E | smoke test in editor (1 server + 2 clients) | 5-10 min |
| Phase E → F | approve data-migration counts in chat | 1 min |
| Phase F start | **approve AWS decommission** in chat | 2 min |
| Phase F middle | hopnbop.net DNS cutover to Cloudflare Pages | 5-30 min (passive) |
| Phase G end | confirm CI green in GitHub UI | 2 min |
| Soak | be reachable for triage | passive |

Total active time on your end: ~110-140 min, all confined to
pre-flight + 6 short interruption checkpoints.

---

## Verification end-state

When all phases complete and soak is clean, the following must
be true:

- `https://nakama.snoringcat.games/healthcheck` returns 200.
- `https://grafana.snoringcat.games` reachable with basic auth,
  all Prometheus targets UP.
- UptimeRobot: all monitors green for ≥7 days.
- Hop 'n Bop production: anonymous + Google + Facebook auth
  works. Matchmaking → Edgegap allocation → match → result
  reporting → leaderboard update all functional.
- AWS Cost Explorer: GameLift, Lambda, DDB, API Gateway, S3,
  CloudFront = $0. (Website moved to Cloudflare Pages in
  Phase F.)
- GitHub Actions: `pr-validate` runs green on PRs.
  `nightly-smoke` runs green daily. `release.yml` triggers on
  tags.
- Discord: cost summary posts daily. No critical alerts firing.
- `platform-pivot-discussion.md` archived; this file (or a
  successor `OPERATIONS.md`) is the single source of truth for
  ongoing operations.

---

## Open decisions before kickoff

The following haven't been settled yet. Defaults assumed; flag if
you want to override.

1. **Single-AZ tolerance?** Hillsboro is one DC. If Hetzner has a
   regional outage, the game is offline. Default: accept it
   (indie scale). Alternatives: replicate Postgres to a second
   region (~$10/mo extra), or accept downtime SLA.
2. **Anonymous → permanent account upgrade UI.** In scope (per
   improvements list). Where in the game's settings flow?
   Default: a "Link account" row in the existing settings panel
   that opens Google/Facebook OAuth flow. Confirm.
3. **Account deletion UI.** In scope. Default: a "Delete my
   account" row in settings, with double-confirmation, that
   calls a Nakama RPC which schedules a deletion job (30-day
   grace period).

### Settled decisions (recorded for future reference)

- **Postgres backup destination:** Hetzner Storage Box ($3/mo,
  1 TB). Single-cloud simplicity wins; if it ever feels risky,
  add a second backup target later.
- **Cloudflare in front of Nakama:** no. Hetzner DNS + Caddy is
  sufficient at indie scale. Cloudflare *is* used for static
  hosting (Cloudflare Pages for `snoringcat.games` and
  `hopnbop.net`) but does not proxy Nakama. Revisit if DDoS
  becomes a concern.
- **Static-site host:** Cloudflare Pages free tier for both
  `snoringcat.games` (now) and `hopnbop.net` (Phase F migration
  off S3+CloudFront). Cost: $0/mo at any plausible scale (no
  bandwidth cap on Pages, only 500 builds/mo soft cap which we'll
  never hit).
- **Backend language:** Go for Nakama runtime modules. Rust would
  require forking Nakama; not worth the maintenance burden. See
  `STUDIO_ARCHITECTURE.md` &rarr; "Top-level architecture
  decisions" for context.
- **Credential storage:** age-encrypted in `claude-config`
  dotfiles repo (not 1Password &mdash; user keeps personal
  1Password account separate from studio work).
- **Pulumi scope:** partial. Hetzner Cloud + Hetzner DNS + AWS
  decommission only. Edgegap and Docker-Compose-on-a-box stay
  CLI/API driven.
- **OAuth providers (MVP):** Google + Facebook. Apple, Steam,
  Epic deferred until those distribution platforms are in scope.
- **Per-game protocol versioning:** in scope from day 1, even
  with one game today &mdash; cheap to add now, painful to
  retrofit later.

When you've reviewed: confirm any overrides on the still-open
items above, then kick off Phase A.
