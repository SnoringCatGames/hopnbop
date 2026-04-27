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

**State file:** `~/.hopnbop-migration/state.json`. See
[State file format](#state-file-format) below.

**Credentials:** `~/.hopnbop-migration/credentials.env`. **Never
commit.** Add `~/.hopnbop-migration/` to your global gitignore.

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

Do these in order. Each step ends with a value to drop into
`~/.hopnbop-migration/credentials.env`.

```bash
mkdir -p ~/.hopnbop-migration/ssh
touch ~/.hopnbop-migration/credentials.env
chmod 600 ~/.hopnbop-migration/credentials.env
```

Then add `~/.hopnbop-migration/` to your global gitignore.

### 1. Hetzner Cloud account

1. https://www.hetzner.com/cloud → Sign up (use `admin@snoringcat.games`).
2. Confirm email link. Add credit card or PayPal.
3. Create project: **`snoringcat-platform`**.
4. Project → Security → API Tokens → Generate. Name: `migration`.
   Permissions: **Read & Write**.
5. Save: `HCLOUD_TOKEN=...`

### 2. Hetzner DNS (free, separate from Cloud)

1. https://dns.hetzner.com → sign in (same account).
2. Add zone for `snoringcat.games`.
3. **Update your domain registrar's nameservers** to:
   `hydrogen.ns.hetzner.com`, `oxygen.ns.hetzner.com`,
   `helium.ns.hetzner.de`. Propagation 1-24h. **Do this now** so
   it's done by the time Phase A runs.
4. Hetzner DNS → API tokens → Create.
5. Save: `HETZNER_DNS_TOKEN=...`

### 3. Edgegap account

1. https://app.edgegap.com → Sign up.
2. Confirm email. (Account may be held for review — message
   support if so: "Godot indie dev migrating from GameLift".
   Approval typically <24h.)
3. Add payment method.
4. User → API Tokens → Create.
5. Save: `EDGEGAP_TOKEN=...`
6. Save: `EDGEGAP_ORG=...` (your org slug, visible in account
   settings).

### 4. GitHub Personal Access Token

1. https://github.com/settings/tokens → Generate new (classic).
2. Scopes: `repo`, `workflow`, `admin:org` (if pushing to
   SnoringCatGames org).
3. Save: `GITHUB_TOKEN=...`

### 5. Discord webhook

Already in `~/.claude/jobs/discord-config.json`? Confirm and copy:
- Save: `DISCORD_WEBHOOK_URL=...`

If not: Discord server → channel → Integrations → Webhooks → New.

### 6. UptimeRobot (free)

1. https://uptimerobot.com → Sign up.
2. My Settings → API Settings → Main API Key.
3. Save: `UPTIMEROBOT_API_KEY=...`

### 7. Google OAuth (for Google sign-in)

1. https://console.cloud.google.com → create or pick project
   (e.g. "Snoring Cat Games").
2. APIs & Services → OAuth consent screen → Configure.
   - User type: **External**.
   - App name: `Snoring Cat Games`. Support email + dev contact:
     yours.
   - Scopes: `email`, `profile`, `openid` (default).
   - Test users: add your email until you publish.
3. APIs & Services → Credentials → Create Credentials →
   OAuth client ID → **Web application**.
4. Authorized redirect URIs:
   `https://nakama.snoringcat.games/v2/account/authenticate/google`.
5. Copy Client ID and Client Secret.
6. Save: `GOOGLE_OAUTH_CLIENT_ID=...`,
   `GOOGLE_OAUTH_CLIENT_SECRET=...`

### 8. Facebook OAuth (for Facebook sign-in)

1. https://developers.facebook.com → Log in (Facebook account).
2. My Apps → Create App.
   - Use case: **Authenticate and request data from users with
     Facebook Login**.
   - App type: **Consumer**.
   - App name: `Snoring Cat Games`.
3. Add product: **Facebook Login** → Web.
4. Settings → Basic:
   - App Domains: `snoringcat.games`.
   - Privacy Policy URL: `https://hopnbop.net/privacy/`.
   - Terms URL: `https://hopnbop.net/terms/`.
   - User data deletion URL:
     `https://hopnbop.net/data-deletion/`.
   - Save changes.
5. Facebook Login → Settings:
   - Valid OAuth Redirect URIs:
     `https://nakama.snoringcat.games/v2/account/authenticate/facebook`.
6. Settings → Basic → copy App ID and App Secret.
7. Save: `FACEBOOK_APP_ID=...`, `FACEBOOK_APP_SECRET=...`
8. **App Review:** when you go beyond test users, submit for
   review (Facebook requires this for production). Reviews take
   1-7 days. **Do this in parallel with the migration**, not
   blocking.

### 9. Verify AWS access still works

```bash
aws sso login --profile hopnbop
aws sts get-caller-identity --profile hopnbop
```
Should print account `270469481989`. If expired, the SSO login
re-prompts in a browser.

### 10. Generate SSH keypairs

```bash
ssh-keygen -t ed25519 -f ~/.hopnbop-migration/ssh/nakama -N "" -C "nakama"
ssh-keygen -t ed25519 -f ~/.hopnbop-migration/ssh/postgres -N "" -C "postgres"
```

Public keys get added to Hetzner servers in Phase A.

### 11. Confirm `credentials.env` is complete

```
HCLOUD_TOKEN=...
HETZNER_DNS_TOKEN=...
EDGEGAP_TOKEN=...
EDGEGAP_ORG=...
GITHUB_TOKEN=...
DISCORD_WEBHOOK_URL=...
UPTIMEROBOT_API_KEY=...
GOOGLE_OAUTH_CLIENT_ID=...
GOOGLE_OAUTH_CLIENT_SECRET=...
FACEBOOK_APP_ID=...
FACEBOOK_APP_SECRET=...
```

When all 11 lines have values, you're done with pre-flight. Kick
off Phase A.

---

## State file format

`~/.hopnbop-migration/state.json`:

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
    "nakama_console_password": null,
    "nakama_version": null,
    "postgres_password": null,
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

1. Read `credentials.env`, validate all 11 vars present.
2. Initialize state file if missing.
3. **Pulumi project setup** (one-time, idempotent):
   - Create directory `infra/pulumi/snoringcat-platform/`.
   - `pulumi new hetzner-go --name snoringcat-platform`.
   - State backend: S3 bucket `hopnbop-pulumi-state` (create if
     not exists, in `us-west-2`, versioning + encryption on).
   - `pulumi config set hetzner:token $HCLOUD_TOKEN --secret`.
4. **Declare Hetzner infra in Pulumi** (Go code under
   `infra/pulumi/snoringcat-platform/`):
   - SSH keys (`nakama`, `postgres`) loaded from
     `~/.hopnbop-migration/ssh/`.
   - Private network `snoringcat-internal` (10.0.0.0/16).
   - Server `nakama-prod-1` (CAX11, Hillsboro, Ubuntu 24.04,
     attach to private network).
   - Server `postgres-prod-1` (CAX11, Hillsboro, Ubuntu 24.04,
     attach to private network).
   - Hetzner Cloud Firewall rules:
     - Nakama: 22/tcp from your IP, 80+443/tcp from world.
     - Postgres: 22/tcp from your IP, 5432/tcp from Nakama
       private IP only.
   - Hetzner DNS A record `nakama.snoringcat.games` → Nakama
     public IP, TTL 60.
   - Pulumi outputs: server IDs, public IPs, private IPs.
5. `pulumi up`. State persists to S3. Outputs written to state
   file.
6. SSH in to both boxes (poll until reachable):
   - `apt update && apt upgrade -y`
   - Install Docker + Docker Compose (`get.docker.com` script).
   - Install fail2ban, ufw (configure to match cloud firewall).
7. **Postgres box** (`/opt/postgres/docker-compose.yml`):
   - Postgres 16, persistent volume `/var/lib/postgresql/data`.
   - Generated strong password (write to state file).
   - `pg_hba.conf` restricts to private network CIDR.
   - Bring up; verify `psql` connection from Nakama box over
     private network.
8. **Nakama box** (`/opt/nakama/docker-compose.yml`):
   - Nakama latest stable.
   - Caddy with automatic Let's Encrypt for
     `nakama.snoringcat.games`.
   - Nakama config:
     - `database.address` → Postgres private IP.
     - Console password from state file.
     - Server-key set (random, written to state).
     - Google + Facebook OAuth credentials from
       `credentials.env`.
     - Session encryption key (random).
   - Bring up Caddy first; verify TLS issuance (poll Caddy logs
     until `certificate obtained successfully`).
   - Bring up Nakama; verify container healthy.
9. Hit `https://nakama.snoringcat.games/healthcheck` (poll up to
   60s, expect 200).
10. SSH-tunnel to console port `:7351`, log in with admin
    password, verify console loads.
11. Smoke test: `curl -X POST` Nakama anonymous-auth endpoint
    with a test device ID, verify session token returned.
12. Update state: phase A `completed`, populate infrastructure
    fields.
13. Post Discord summary: "Phase A complete. Nakama healthy at
    {url}. Console password in state file."

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

1. Author `scripts/migrate_ddb_to_nakama.py`:
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

**Estimated time:** ~2 hours.
**Manual gates:** **explicit "approve decommission" message
required**.

### Goal

Production traffic on Nakama+Edgegap. AWS resources deleted. Cost
drops to ~$0/mo (website hosting only).

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
   - **Preserved:** S3 bucket `hopnbop-website`, CloudFront
     `E3LT833LSVTW9R`, Route 53 zone `hopnbop.net` (website
     hosting stays on AWS).
2. **You approve in chat.** Without an explicit "yes proceed" or
   similar, I do not delete anything.
3. Switch DNS A record `api.hopnbop.net` → Nakama (already
   `nakama.snoringcat.games`, but keep `api.hopnbop.net` working
   as a CNAME during the transition).
4. Wait for propagation (poll DNS until both old and new resolve
   to Nakama; typically 5-30 min).
5. Verify production traffic now hits Nakama (UptimeRobot +
   Grafana).
6. Drain GameLift: set fleet DESIRED=0, wait for game-session
   count → 0 (in-flight matches finish naturally).
7. **AWS teardown via Pulumi adopt-and-destroy.** Create a new
   Pulumi stack `aws-decommission` (separate from
   `snoringcat-platform`) that imports the existing AWS
   resources by ARN, then destroys them in dependency order:
   matchmaker, queue, ruleset, fleet, container group
   definition, ECR, Secrets Manager, then `sam delete` for the
   SAM stack (DDB tables auto-deleted), and finally Route 53
   records under `game.hopnbop.net`. Pulumi gives us a clean
   diff of what was destroyed and a recoverable state if the
   teardown fails partway. **Preserved (NOT in the destroy
   stack):** S3 bucket `hopnbop-website`, CloudFront
   distribution, Route 53 zone `hopnbop.net`.
8. Set CloudWatch budget alarm at $5/mo.
9. Update `hopnbop_private/CLAUDE.md`: remove the GameLift /
   AWS resources section, replace with new Nakama+Edgegap
   architecture notes (or replace with a pointer to
   `third_party/snoringcat-platform/PLATFORM_ARCHITECTURE.md`).
10. After 30 days, you decide whether to fully close the AWS
    account (separate manual step, not in this phase).

### Verification (autonomous)

- AWS Cost Explorer: GameLift hours = 0 going forward.
- UptimeRobot: all green.
- Test match plays end-to-end on prod.
- `aws cloudformation describe-stacks --stack-name hopnbop-backend`
  returns `does not exist`.

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
   - Build Godot web export, sync `web/` to S3, invalidate
     CloudFront.
   - Build native exports for Windows / Mac / Linux / Steam.
   - Roll Nakama runtime modules (Docker Compose pull + restart).
   - Post release notes to Discord.
5. Strip / re-target existing CI:
   - Delete AWS-specific tests (SAM build, moto-mocked DDB,
     GameLift integration).
   - Re-target compliance suite from AWS API → Nakama API.
6. Update `hopnbop_private/CLAUDE.md`:
   - Replace deploy sections with Edgegap deploy.
   - Replace SAM/CDK with Docker Compose / `nakama-runtime go
     build`.
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
| Pre-flight start | Browser session: 11 accounts/tokens | 60-90 min |
| Phase A → B | (optional) hit healthcheck URL in browser | 30 sec |
| Phase B → C | none | — |
| Phase C → D | click budget-alert thresholds in Edgegap UI | 2 min |
| Phase D → E | smoke test in editor (1 server + 2 clients) | 5-10 min |
| Phase E → F | approve data-migration counts in chat | 1 min |
| Phase F start | **approve AWS decommission** in chat | 2 min |
| Phase G end | confirm CI green in GitHub UI | 2 min |
| Soak | be reachable for triage | passive |

Total active time on your end: ~80-110 min, all confined to
pre-flight + 5 short interruption checkpoints.

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
- AWS Cost Explorer: GameLift, Lambda, DDB, API Gateway = $0.
  Only S3 + CloudFront for website.
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

1. **Postgres backup destination.** Default: Hetzner Storage Box
   ($3/mo, 1 TB). Alternatives: S3, Backblaze B2.
2. **Cloudflare in front?** Default: no (Hetzner DNS + Caddy
   sufficient at this scale). Add later if DDoS becomes a
   concern.
3. **Single-AZ tolerance?** Hillsboro is one DC. If Hetzner has a
   regional outage, the game is offline. Default: accept it
   (indie scale). Alternatives: replicate Postgres to a second
   region (~$10/mo extra), or accept downtime SLA.
4. **Anonymous → permanent account upgrade UI.** In scope (per
   improvements list). Where in the game's settings flow?
   Default: a "Link account" row in the existing settings panel
   that opens Google/Facebook OAuth flow. Confirm.
5. **Account deletion UI.** In scope. Default: a "Delete my
   account" row in settings, with double-confirmation, that
   calls a Nakama RPC which schedules a deletion job (30-day
   grace period).

When you've reviewed: confirm any overrides, then kick off Phase
A.
