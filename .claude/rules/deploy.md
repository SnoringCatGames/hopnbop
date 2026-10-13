---
paths:
  - "game.yaml"
  - ".github/workflows/**"
  - "scripts/deploy-*.ps1"
  - "scripts/sync-game-config.ps1"
  - "Dockerfile*"
  - "web/**"
  - "legal/**"
  - "export_presets.cfg"
---

# Deploy lore

Deployment, versioning-sync, and production-resource detail, moved
verbatim from CLAUDE.md by H34 (2026-10-13). The binding summary (deploy
targets, version table, commit policy) stays in CLAUDE.md; this file
holds the full procedures and the why.

## Game server deploy (Edgegap)

`game-server.yml` builds `Dockerfile.edgegap`, pushes to the
Edgegap registry as `v<N>`, and registers the app version
itself: a DELETE-then-POST against
`https://api.edgegap.com/v1/app/hopnbop-server/version` that
carries `docker_repository`, `docker_tag`, `req_cpu`,
`req_memory`, the 4433/UDP + 4434/TCP port pair, and the
injected `NAKAMA_HTTP_KEY`. DELETE-first makes a re-run with
the same version replace the old record; 404 is treated as
"no prior version". **No dashboard step is involved.** (This
section used to say registration happened "via the dashboard",
which predated the automation.)

Then bump `edgegap_app_version` in **`game.yaml`** to the new
`v<N>` and run `scripts/sync-game-config.ps1`. That file is the
source of truth: `fleet_allocator.go` prefers the per-game
config's value and only falls back to the host's
`EDGEGAP_APP_VERSION` env var when it is blank (bootstrap
deploys before any `game.yaml` has been synced). Bumping the
env var alone does nothing for hopnbop.

**`sync-game-config.ps1` pulls the new image onto the Nakama host
before it registers the config.** `allocator_mode: hybrid` sends
North American matches to the host's local Docker allocator, which
starts `local_image_ref` through the Docker Engine API. That API
never pulls, and a failed local allocation fails the match (no
Edgegap fallback), so a registered tag the host lacks would fail
every match routed local. A failed pull aborts the sync before
anything is registered. The pull needs the operator's SSH key
(`~/.hopnbop-migration/ssh/nakama`). CI has none, so `release.yml`
syncs with `-SkipImagePull` and warns; after a CI release, run
`docker pull <local_image_ref>` on the host by hand.

`game-server.yml` pushes the image tag but does NOT write
`edgegap_app_version` back. Bump `game.yaml` **before** running
the workflow: its first step fails the run if `game.yaml`'s
`edgegap_app_version` or `local_image_ref` tag doesn't match the
version being pushed. That guard is why a forgotten bump now
costs you a fast CI failure instead of an allocator silently
deploying the previous version forever.

**Edgegap version names are sequential (`v27`, `v28`, ...) and
are NOT the release tag.** `release.yml` reads
`edgegap_app_version` out of `game.yaml` (its
`resolve-edgegap-version` job) and passes that to this workflow,
so the tag-push and manual-dispatch paths agree.

It used to pass `github.ref_name` — the git tag (`v0.48.0`) on a
tag push, and the *branch* (`main`) on `workflow_dispatch`.
Neither is an Edgegap version name, so a release would have
registered an app version nothing allocates while reporting
success. It never fired: `release.yml` has never run.

**So: bumping `edgegap_app_version` + `local_image_ref` to the
next `v<N>` is part of preparing a release**, not an afterthought
— a release does not invent a new Edgegap version for you.

**Deactivate the superseded Edgegap version as part of each
release** (`PATCH /v1/app/hopnbop-server/version/<v>` with
`{"is_active": false}`): `game-server.yml` leaves the prior
version active, actives pile up, and check-prod step 10 flags
them (H36, 2026-10-12).

Required GH secrets: `EDGEGAP_TOKEN`, `EDGEGAP_REGISTRY_*`,
`EDGEGAP_REGISTRY_PROJECT`, `SUBMODULE_PAT`. The Harbor robot
credentials in `EDGEGAP_REGISTRY_USERNAME`/`PASSWORD` need
rotation when they expire (failure mode: HTTP 401 on docker
login).

## Web client deploy (Cloudflare Pages + R2)

`scripts/deploy-cf-pages.ps1` (local) or the `web-client` job
in `release.yml` (CI):

1. Godot exports `web/`.
2. Heavy assets (`.wasm` ~38 MB, `.pck`, `.audio.worklet.js`,
   `.audio.position.worklet.js`) upload to R2
   (`hopnbop-assets` bucket). Pages caps individual files at
   25 MiB, so the wasm doesn't fit on Pages.
3. `index.html`'s `GODOT_CONFIG` is patched in a staging copy
   to point at absolute R2 URLs.
4. Remaining files deploy to Cloudflare Pages
   (`hopnbop-website` project).

R2 bucket CORS is configured open for `GET`/`HEAD` from any
origin so the cross-origin wasm fetch works from the Pages
domain. The deploy script + the GHA both set CORS idempotently.

Required GH secrets: `CLOUDFLARE_API_TOKEN` (with Pages:Edit +
Workers R2 Storage:Edit + Account Settings:Read),
`CLOUDFLARE_ACCOUNT_ID`, plus `NAKAMA_HTTP_KEY` and
`GAME_ADMIN_KEY` for the job's game.yaml sync step
(`register_game` needs both; see "Synced locations").

### Web export gotcha

Godot `--export-release "Web"` returns non-zero on missing-
resource warnings. The CI step uses `|| true` plus a sanity
`test -s build/web/index.html` to distinguish a real failure
from a cosmetic one. If you export locally and the script
treats a non-zero exit as failure, do the export by hand,
verify the artifact landed, then run with `-SkipExport`.

### Website structure

- Root page loads the Godot web export directly (no landing
  page).
- Supporting pages: `/leaderboard/`, `/blog/`, `/privacy/`,
  `/terms/`, `/data-deletion/`.
- `/leaderboard/` (`web/leaderboard/index.html`) reads the
  platform runtime's public route, `GET
  https://nakama.snoringcat.games/snoringcat/leaderboard?game_id=hopnbop&leaderboard=ffa&limit=100`.
  No credential (the page must never carry one); it gets each
  listed player's rank, display name and best single-match score,
  refreshed at most once a minute. Guests, accounts queued for
  deletion, and probe accounts are never listed. Names are
  player-chosen, so the page builds rows with `textContent`, never
  `innerHTML`. Contract and privacy rules:
  `PLATFORM_ARCHITECTURE.md` → "Leaderboards". It replaced the AWS
  API Gateway URL, which died with Phase F.

  The in-game leaderboard (`src/ui/leaderboard_panel/`, through
  `BackendApiClient.fetch_leaderboard`) reads the same route, so the
  game and the site always list the same players with the same
  ranks; a signed-in player also sees their rank, from
  `get_player_stats`, and an anonymous one is told why they aren't
  listed. My Stats (`src/ui/screens/my_stats_screen.gd`) shows
  `get_player_stats`' best score and rank and `get_match_history`'s
  totals and latest matches. Before 2026-10-12 the panel listed raw
  Nakama records by username and My Stats read the account profile,
  so both showed nothing useful.
- Discord invite link: `https://discord.gg/QX939SF7nb`.
- Update `web/blog/index.html` with patch notes when making
  new releases.

## Legal documents

The game bundles plain-text copies of the legal docs for
offline access. When updating legal content, update **both**
locations:

1. **Web pages:** `web/terms/index.html`,
   `web/privacy/index.html`, `web/data-deletion/index.html`
2. **In-game text:** `legal/en/terms.txt`,
   `legal/en/privacy.txt`, `legal/en/data_deletion.txt`
   (and any translated variants in `legal/{locale}/`)

If the changes require users to re-consent, bump the legal
version in **both** places, in the same commit:

1. `game.yaml` → `legal.legal_version` (the authoritative value;
   the runtime surfaces it via `version_check`).
2. `src/core/legal_version.gd` → `const LEGAL_VERSION` (the
   offline / pre-fetch fallback).

They must match: `pr-validate.yml` fails the build if they
drift.

Sync the bump (`scripts/sync-game-config.ps1`) with the release
that ships the new text, never before. The runtime serves
`legal_version` to every client through `version_check`, so a
bump synced early makes clients that still bundle the old text
ask players to re-consent to that old text, and those players
are then never shown the new text. Every sync posts all of
`game.yaml`, so a sync for any other reason (a server-only
deploy, an `edgegap_app_version` bump) publishes a pending
legal bump too: hold such syncs until the client ships, or ship
them together.

## Prerequisites (all deploys)

- Docker Desktop running (Edgegap server-image build + local
  smoke).
- Godot CLI on PATH (server + web exports).
- For local Cloudflare deploys: `CLOUDFLARE_PAGES_TOKEN`,
  `NAKAMA_HTTP_KEY` and `GAME_ADMIN_KEY` in
  `~/.hopnbop-migration/credentials.env` (the last two for the
  closing game.yaml sync; the script stops before deploying
  anything if `GAME_ADMIN_KEY` is missing), and `npm`/`npx`
  available (the script invokes `npx wrangler@latest`).
- For Edgegap deploys: an Edgegap account with the
  `hopnbop-server` app registered. `game-server.yml` pushes the
  image and registers the app version over the API in the same
  run. What is left to you is bumping `edgegap_app_version` +
  `local_image_ref` in `game.yaml` (do it *before* the run; the
  workflow's first step fails if they disagree with the tag
  being pushed) and running `scripts/sync-game-config.ps1`.
  Do not bump the dashboard or the Nakama host's `runtime.env`
  for this.

## Synced locations (version values outside this repo)

- Edgegap registry image tag (set by `game-server.yml`'s
  workflow input).
- The platform's **per-game config row** (Postgres `games`
  table), field `display_version`. This is what `version_check`
  actually reports: `runtime/version.go` overrides the env-var
  value with the per-game config whenever the caller passes a
  `game_id`, and every real client does.

  **You don't hand-maintain this.** `game.yaml` deliberately does
  not define `display_version` or `protocol_version`;
  `scripts/sync-game-config.ps1` injects both from `project.godot`
  and POSTs the merged config to the `register_game` RPC. The web
  deploy runs it; run it standalone after a server-only deploy or
  any other `game.yaml` change. `pr-validate` fails the build if
  either field reappears in `game.yaml`.

  `game.yaml` used to carry `display_version`, annotated "cosmetic
  only; not CI-guarded" — it drifted to 0.39.0 while the shipped
  client reached 0.47.0, so the backend reported a version that
  hadn't existed for months. Deriving it removed the duplication
  instead of adding a second guard to police it.

  Note `register_game` **replaces the whole config blob**
  (matchmaker modes, `allocator_mode`, `edgegap_app_version`,
  legal paths). Never hand-POST it; a field missing from the
  payload is deleted from production. The script guards the
  load-bearing keys before it writes.

  `register_game` is operator-only: it needs the runtime's
  `GAME_ADMIN_KEY` (sent as `admin_key`) on top of
  `NAKAMA_HTTP_KEY`, and refuses every call while the runtime has
  no `GAME_ADMIN_KEY`. The HTTP key alone used to be enough, but it
  shipped in every client up to 0.47.0, so anyone could have
  replaced the live config. The script takes `-AdminKey`, default
  `$env:GAME_ADMIN_KEY` (`deploy-cf-pages.ps1` loads it from
  `credentials.env`; `release.yml` passes the `GAME_ADMIN_KEY`
  secret), falls back to the dev stack's fixed key for loopback
  hosts, and prints neither key. Model and key locations:
  `PLATFORM_ARCHITECTURE.md` → "Runtime keys and RPC auth".
- Nakama host's `runtime.env` `NAKAMA_GAME_VERSION` — **only the
  fallback** for `version_check` calls that pass no `game_id`.
  Bumping it does NOT change what clients see; fix
  `display_version` instead (above). It drifted to 0.39.0
  against a 0.47.0 client precisely because the old note here
  claimed it was the surfaced value.

  **It is currently unset in production, and that is fine.**
  Measured 2026-07-16: `version_check` with no `game_id` returns
  `game_version: ""`, `protocol_version: 0`, `is_compatible:
  false`. Every real client passes `game_id`
  (`backend_api_client.gd` — Stage 3.10), so the fallback is
  inert. Do **not** "fix" it by setting the env var: that
  re-creates the hand-maintained value with no guard that caused
  the 0.39.0 drift in the first place. The env knob is vestigial
  and should eventually be deleted from `main.go` /
  `docker-compose.yml` / `config.yml` rather than populated.
- Nakama host's `runtime.env` `EDGEGAP_APP_VERSION` — **only the
  bootstrap fallback**, for allocations before any `game.yaml`
  has been synced. Superseded per-game by the config's
  `edgegap_app_version`, which the runtime prefers and falls
  back to the env var only when blank. Do not bump this after a
  game-server deploy; bump `game.yaml` (see "Game server deploy
  (Edgegap)") and sync.
- `export_presets.cfg` `file_version`/`product_version`
  (optional, currently empty).

## Version check architecture

- `protocol_version` determines client/server compatibility.
  Only bump when the network protocol actually changes.
- `config/version` is for display only. Hotfix deploys can
  bump this without breaking existing clients.
- Client checks `protocol_version` at app startup through the
  runtime's unauthenticated `/snoringcat/version_check` route
  (`BackendApiClient.check_version`, URL from
  `Platform.get_version_check_url()`). It answers like the
  `version_check` RPC and needs no session or key. Also checked
  in the matchmaker ticket (the runtime aborts a mismatched
  match before allocating).

## Production resources

**Hetzner platform tier** (Pulumi-managed in
`third_party/snoringcat-platform/infra/pulumi/snoringcat-platform/`):
- **Project:** `snoringcat-platform`, stack `prod`, state in
  Cloudflare R2 bucket `hopnbop-pulumi-state-r2`. Pulumi
  authenticates via S3-compat keys in `R2_ACCESS_KEY_ID` /
  `R2_SECRET_ACCESS_KEY` / `R2_ENDPOINT` (sourced from
  `~/.hopnbop-migration/credentials.env`).
- **nakama-prod-1:** CPX21 (3 vCPU / 4 GB / 80 GB; upsized
  in-place from CPX11 on 2026-06-01) in Hillsboro, runs
  10 containers in a single docker compose stack: Postgres 16,
  Nakama, Caddy, signaling-proxy, geoip-sidecar (GeoIP lookups
  for the hybrid allocator), Prometheus, Grafana, node-exporter,
  postgres-exporter, and cadvisor (container metrics for
  Prometheus). cost-monitor + pg-backup + geoip-refresh +
  desktop-drain-watch systemd timers on the host. Loki + Promtail
  (log shipping) were intentionally left off in the Stage 7.11
  (2026-05-13) lightweight re-introduction; their configs remain
  in `infra/remote/nakama/` so they can be flipped on without
  reconstruction. Logs stay on `journalctl` / `docker logs`.
- **DNS:** Cloudflare-managed; `nakama.snoringcat.games`,
  `grafana.snoringcat.games`, and `signaling.snoringcat.games`
  all point at the Hetzner public IP (Caddy multiplexes by
  Host header).
- **Cost:** ~$14.59/mo, the CPX21 monthly cap at the pre-hike
  rate locked in on 2026-06-01 (September 2026 actual; this line
  said ~$8 until 2026-10-11, which was never right). cost-monitor
  MTD is authoritative. Plus cents of R2 backups.
- **Backups:** `pg-backup.timer` runs nightly at 03:11 UTC,
  `pg_dumpall` → `s3://hopnbop-pulumi-state-r2/pg-backups/
  postgres-YYYY-MM-DD.sql.gz`, 7-day retention. Restore —
  order matters, and because the dump is `pg_dumpall` output
  (it re-CREATEs the `nakama` DB and `\connect`s into it),
  psql must target the `postgres` maintenance DB, **not**
  `-d nakama`:
  1. `cd /opt/nakama && docker compose stop nakama` —
     Nakama must not migrate/write during the restore.
  2. `docker exec -e PGPASSWORD=<pw> postgres psql
     --no-password -h 127.0.0.1 -U nakama -d postgres -c
     'DROP DATABASE IF EXISTS nakama WITH (FORCE)'`
  3. `gunzip -c postgres-YYYY-MM-DD.sql.gz | docker exec -i
     -e PGPASSWORD=<pw> postgres psql --no-password -h
     127.0.0.1 -U nakama -d postgres` — role-exists errors
     are expected noise; verify afterwards with a table
     count on the restored `nakama` DB.
  4. `docker compose start nakama` (migrate-up is a no-op
     on a same-version restore).
  Full-host rebuild: `phase-a.ps1 -RestoreBackup` (in
  `third_party/snoringcat-platform/scripts/`) runs this
  automatically before Nakama first boots. Its HostKeys step
  re-pins the SSH host keys once you confirm the new ed25519
  fingerprint in the Hetzner console. It also renders the whole
  `/opt/nakama/.env` (Edgegap and local-allocator entries
  included) and pulls the local game-server image, so the rebuilt
  host matchmakes. RTO/RPO targets are in
  `PLATFORM_ARCHITECTURE.md` "Backups and disaster recovery".

**Edgegap game-server fleet:**
- **App:** `hopnbop-server` (registered in Edgegap dashboard).
- **Active version:** `game.yaml`'s `edgegap_app_version`,
  synced into the per-game config by
  `scripts/sync-game-config.ps1`. The host's `runtime.env`
  `EDGEGAP_APP_VERSION` is only the bootstrap fallback; see
  "Game server deploy (Edgegap)".
- **Allocation:** on demand by Nakama's matchmaker hook; no
  always-on fleet.

**Cloudflare:**
- **Pages project:** `hopnbop-website` (auto-deploy via
  `release.yml`).
- **R2 bucket:** `hopnbop-assets` (heavies > 25 MiB live here).
- **Cost-monitor thresholds:** R2 warn 8 GB / hard 9.5 GB, Pages
  builds warn 400 / hard 475 of the 500/mo free tier.

**Legacy AWS:** fully torn down. Phase F (2026-05-03) deleted the
hopnbop-* GameLift / Lambda / S3 / CloudFront / Route 53 surface;
the orphan `snoringcat-platform-backend` SAM stack and Pulumi-
state S3 bucket were cleaned up the next day. **Zero AWS
resources remain in the account.** Pulumi state migrated to
Cloudflare R2.

## Game-server allocation (Edgegap)

Allocation is on-demand: when Nakama's matchmaker matches
players, the runtime hook calls Edgegap's deployment API to
spin up a `hopnbop-server` container in a region close to the
matched players. There's no always-on fleet — cold start to
ready is typically a few seconds (Edgegap holds warm pools
internally). Once the match ends or the deploy idles, Edgegap
tears the container down automatically and we're billed only
for active session minutes.

The matchmaker hook lives in
`third_party/snoringcat-platform/runtime/fleet_allocator.go`
and reads `EDGEGAP_TOKEN`, `EDGEGAP_APP_NAME`, and
`EDGEGAP_APP_VERSION` from the Nakama runtime env (configured
in `infra/remote/nakama/config.yml`'s `runtime.env` block).

The previous AWS GameLift-based fleet (with cold-start warmup,
fleet state DynamoDB table, and Lambda idle-checker) was
decommissioned in Phase F. The historical detail is in
`docs/archive/MIGRATION_PLAN.md` if needed for archeology.

## Cost monitor (daily Discord MTD summary)

The Discord channel that receives this repo's morning-brief and
ci-failure pings also gets a **daily MTD spend summary** plus
threshold-crossing alerts. The source is in the snoringcat-platform
repo, deployed to the Hetzner host by Pulumi:

- Source files:
  `third_party/snoringcat-platform/infra/remote/cost-monitor/`
  (`cost-monitor.{sh, service, timer}`).
- Deployed path: `/opt/snoringcat/cost-monitor/` on the Nakama box.
- Trigger details, thresholds, emergency action, and inspection
  commands: see `PLATFORM_ARCHITECTURE.md` → "Cost monitor".
