# Next Steps

Captured 2026-05-02; addenda 2026-05-03 + 2026-05-04 +
2026-05-05. The platform migration is functionally complete:
AWS GameLift is out and torn down, Edgegap + Nakama (Hetzner)
are running production matches, the platform-shared infra and
runtime live in `snoringcat-platform/`, and Pulumi state lives
on Cloudflare R2.

## 2026-05-05 addendum: web boot cascade fixed + WSS hostname

Two distinct issues, both shipped end-to-end on the code side
but the second still needs operator deploy steps before web
cross-play actually works.

### Boot cascade (fixed end-to-end)

Web build was crashing at every page load with
`Cannot get class ''` → `Could not resolve external class
member 'settings'` → spawn-time RuntimeError. Root cause was
`var settings: Settings = preload("res://settings.tres")` in
`src/core/global.gd` running at parse time, before all
class_name registrations finished. settings.tres references
class_name'd resource scripts, those lookups returned empty,
and Settings.* became unresolvable across the project.

Fix (commit `834fdcc`): switched to `load()` (CLAUDE.md
"approach #1"). Type annotation stays Settings — no
intellisense loss. Also excluded `addons/webrtc/*` from the
Web preset and deleted 11 orphan `.gd.uid` files for files
that were removed in earlier refactors.

CLAUDE.md "Web Build Cyclic-Reference Parser Failures"
section was rewritten — the previous "cyclic reference"
framing was a misdiagnosis that led to .get() rewrites that
destroy intellisense without fixing the root cause. The new
section directs investigation top-down through the boot log.

### WSS hostname mismatch (code shipped, deploy pending)

After the boot fix, matchmaking joined and matched, but the
post-allocation WSS handshake failed: the runtime sent
Edgegap's `*.pr.edgegap.net` FQDN to the client, the wildcard
cert is for `*.game.hopnbop.net`, browser rejected the
handshake on cert mismatch.

Code shipped:

| Repo | Commit | What |
|---|---|---|
| `snoringcat-platform` | `cbd64ee` | runtime computes `s-<ip>.<SERVER_DNS_BASE>` from PublicIP, sends as `server_fqdn`. New `infra/remote/dns-watchdog/` systemd timer. `scripts/phase-b.ps1` grows a Step-DnsWatchdog. |
| `hopnbop_private` | `7fd3dcb` | `infra/game-server/entrypoint.sh` POSTs the matching A record to Cloudflare on startup, deletes on EXIT/TERM/INT. Submodule pointer bumped. |

**Operator steps — done 2026-05-05:**

| Step | What | When |
|---|---|---|
| 1. CF env vars | `CLOUDFLARE_DNS_ZONE_ID` GH secret added (`0d5df9dd7cfdf0b3e46f9f37c83488a7` = hopnbop.net zone). `CLOUDFLARE_DNS_TOKEN` already existed (same token cert-rotate uses). Plumbed into `game-server.yml`'s Edgegap envs (commits `569cfed`, `042f0cc`). | 22:48-23:00 UTC |
| 2. game-server.yml v10 | `gh workflow run game-server.yml -f version=v10`. First run failed on an apostrophe inside the jq comment block; fixed in `042f0cc` and re-ran successfully. | 22:55, 23:01 UTC |
| 3. cert-rotate v10 | `gh workflow run cert-rotate.yml -f force_renew=true` — added TLS_FULLCHAIN/TLS_PRIVKEY/TLS_ISSUED_AT to v10. | 23:08 UTC |
| 4. Hetzner runtime.env bump | sed `EDGEGAP_APP_VERSION=v9` → `v10` on `/opt/nakama/config.yml`, `docker compose restart nakama`. | 23:08 UTC |
| 5. nakama-runtime.yml | `gh workflow run nakama-runtime.yml` — built + scp'd `snoringcat.so` (build_id `569cfed79b...`). Runtime healthy, all 10 RPCs registered, matchmaker_matched hook present. | 22:55 UTC |
| 6. dns-watchdog deploy | `phase-b.ps1 -StartAt DnsWatchdog -StopAt DnsWatchdog`. Systemd timer enabled on the Nakama host; first test run scanned 0 records (expected, no live deploys at the time). Next fire 23:17 UTC. | 22:57 UTC |

v10 envs verified via `GET /v1/app/hopnbop-server/version/v10`:
NAKAMA_HTTP_KEY, CLOUDFLARE_DNS_TOKEN (secret), CLOUDFLARE_DNS_ZONE_ID,
TLS_FULLCHAIN (secret), TLS_PRIVKEY (secret), TLS_ISSUED_AT.

**Step 7 — smoke test (user, pending):**

Open hopnbop.net in two browsers, both join matchmaking with
`platform=web`, verify they see each other in the lobby. The
runtime hook should publish `s-<ip>.game.hopnbop.net` -> the
deploy IP just before sending match_ready, the wildcard cert
will match, WSS handshake completes. Watch
`journalctl -u dns-watchdog.service` on the Nakama box to
confirm the hourly sweep also fires.

### 2026-05-06 follow-up: ICE port regression — patch restored

Once DNS pre-warm landed and the WSS handshake started reaching
the container, both native and web clients still failed with
the same fingerprint as the actual matchmaking attempt: WS
opens, offer is sent, no answer, 10 s timeout, 5 retries, give
up. The new `scripts/edgegap-logs.ps1` (see below) pulled
container stdout via `GET /v1/deployment/<id>/container-logs`
and the actual cause was visible immediately:

```
[ICE init] ICE port=4433
[ICE candidate] candidate:1 1 UDP ... 10.4.11.30 38645 typ host
WARNING: rtc::impl::IceTransport::LogCallback@390:
  juice: Send failed, errno=101
WARNING: rtc::impl::IceTransport::LogCallback@390:
  juice: STUN message send failed
```

The GDExtension binary ignored `portRangeBegin/End` and bound
ICE to ephemeral port 38645 instead of the declared 4433.
Edgegap doesn't forward arbitrary ports → STUN sends fail
with ENETUNREACH (errno 101) → ICE never completes.

This is the exact same regression NOTES_FOR_BLOG_POSTS.md
"ICE port nightmare on GameLift container fleets" documents
from March/April 2026. The pre-AWS-migration setup had a
multi-stage Dockerfile that compiled a patched webrtc-native
v1.0.9 from source (`patch-webrtc-portrange.py` adds 6 lines
to `_initialize()` parsing portRangeBegin/End/enableIceUdpMux
into libdatachannel's rtc::Configuration). The migration to
`Dockerfile.edgegap` (commit `70d3e6d`) dropped that stage
under the assumption "Edgegap port-forwards declared
container ports directly, so no patches needed." The
container logs disagree.

`5a70367` recovers `infra/game-server/patch-webrtc-portrange.py`
from `70d3e6d^` and adds the matching builder stage back to
`Dockerfile.edgegap`. v12 builds in CI now (slower than usual
because the webrtc-native compile takes 5-10 min). Once v12
is registered + Hetzner's `EDGEGAP_APP_VERSION` is bumped,
the next match should ICE successfully.

Also added permanent log-collection tooling:
`scripts/edgegap-logs.ps1 [-RequestId X] [-Latest]` wraps
`GET /v1/deployment/<id>/container-logs`. Without it we had
no way to see container stdout from outside the dashboard.
This is keeper tooling, not temp instrumentation.

### 2026-05-05 follow-up: DNS pre-warm moved into the runtime

First end-to-end test surfaced an issue with the original
plan. After the runtime started sending the right
`s-<ip>.game.hopnbop.net` hostname, the WSS handshake still
failed because the *DNS A record itself wasn't created*.
Manually adding the record made the handshake work (HTTP 101
Switching Protocols) — so the cert / nginx / runtime hostname
were all fine; the entrypoint pre-warm was just silently
failing.

I tried to debug from the container side: dumped the v11
image's entrypoint via a workflow probe (it had the latest
code), confirmed CF env vars were on the version (`is_secret:
true`, value lengths matched), confirmed CF API was reachable
from Hetzner. But Edgegap doesn't expose container stdout via
API and the deploy never reached register_server (which would
imply the entrypoint ran past DNS), so something between
"container start" and "DNS POST" was failing without a way
to see what.

Pivoted: moved DNS pre-warm into the runtime
(`fleet_allocator.go preWarmDNS`). Same logic, same TTL +
comment shape, but it runs on Hetzner where logs are visible
and the CF creds come from `runtime.env` instead of having to
go through Edgegap's env-var injection. Container `entrypoint.sh`
is now back to its pre-pivot shape (no DNS code).

Code shipped:
- `snoringcat-platform 82135ea / 279472c` — `preWarmDNS()` +
  doc sync.
- `hopnbop_private 0371c98 / 0429761` — entrypoint revert,
  game-server.yml cleanup, submodule pointer bump.

Live:
- Hetzner `runtime.env`: `CLOUDFLARE_DNS_TOKEN` +
  `CLOUDFLARE_DNS_ZONE_ID` added (token same as cert-rotate).
- New runtime plugin deployed via `nakama-runtime.yml`
  (build_id `0371c98...`). Hooks + RPCs registered.
- dns-watchdog systemd timer unchanged (cleanup mechanism is
  the same regardless of who creates the record).

## 2026-05-04 addendum: WebRTC cross-play deploy + web debug

A long session that took the WebRTC cross-play work from "code
shipped, not deployed" all the way through to live production
v0.34.0 + new runtime + cert + nginx + auto-rotation, then
debugged why the web build was hanging at "Resuming session…"
and shipped the real fix.

### What's live in production now

| Layer | Version | How shipped |
|---|---|---|
| Game-server image (Edgegap registry) | `v9` (2026-05-04T04:44Z) | `gh workflow run game-server.yml -f version=v9` |
| Edgegap app version registered | v8 + v9 both active | auto-registered by `game-server.yml` |
| Nakama runtime plugin | build `d8ecedb` (2026-05-04T~05:00Z) | `gh workflow run nakama-runtime.yml` |
| Hetzner Nakama runtime.env | `EDGEGAP_APP_VERSION=v9`, `NAKAMA_GAME_VERSION=0.34.0`, `NAKAMA_PROTOCOL_VERSION=2` | SSH hot-fix to `/opt/nakama/config.yml` + `docker compose restart nakama` |
| Cloudflare Pages (hopnbop.net) | 0.34.0 | `scripts/deploy-cf-pages.ps1` (3 deploys this session) |
| R2 wasm/pck Cache-Control | `no-cache, must-revalidate` | re-uploaded 2026-05-04T08:43Z |
| TLS cert for `*.game.hopnbop.net` | ECDSA-P-256, expires 2026-08-02 | issued via certbot DNS-01; cert-rotate workflow renews automatically |
| Edgegap version env vars (TLS_FULLCHAIN/TLS_PRIVKEY/TLS_ISSUED_AT) | populated on v8 + v9 | `gh workflow run cert-rotate.yml -f force_renew=true` (after fixing 4 workflow bugs along the way) |
| `project.godot` `config/version` | 0.34.0 | commit `74b065e` |

### Major work shipped this session

**Compliance test suite (44 tests / 20 files now)** — rewritten
top-to-bottom for the Nakama backend; previous suite targeted
the deleted AWS REST API:

- HTTP-side suite: version, auth_anon, auth_link, account,
  account_delete, friends, party, settings, presence,
  player_stats, data_export, token_refresh, matchmaking,
  match_loopback, api_surface, transport_selection.
- Realtime-socket rig (`compliance_socket_helper.gd`) + 4
  socket tests (auth, matchmaker, presence, chat).
- Helper bug found + fixed: RPC bodies need `?unwrap=true` to
  avoid Nakama's JSON-string-double-encoding requirement.
- Run-isolated, all four key files green:
  `test_version` 3/3, `test_transport_selection` 5/5,
  `test_match_loopback` 3/3, `test_api_surface` 2/2.

**Plan doc** (`docs/test-architecture-plan.md`) — single
source of truth for the WebRTC fix plan, socket rig design,
and (placeholder) distributed-test architecture.

**Protocol-version drift** — fixed `config.yml` to pass
`NAKAMA_PROTOCOL_VERSION` through to the runtime, set the env
var to `2` on Hetzner so `version_check` returns
`is_compatible: true` for real clients.

**WebRTC cross-play, all 8 plan-doc items**:

1-5. transport_type plumbing through runtime → match_ready →
   client → server.
6. rollback_netcode `signaling_port` escape hatch (kept as
   future flexibility; nginx makes it inert today).
7. nginx `ssl_preread` re-introduced for WSS termination on
   4434/TCP; new `infra/game-server/nginx.conf` + entrypoint
   updated to write `TLS_*` env vars to disk + start nginx
   before the Godot server.
8. `transport_select` runtime RPC + Layer 1 compliance test
   (5 cases — native-only, mixed, all-web, empty strings,
   empty list).

**Cert + auto-rotation**:

- One-shot ECDSA wildcard cert via certbot dns-cloudflare.
- New GitHub secret `CLOUDFLARE_DNS_TOKEN` (Zone:DNS:Edit on
  snoringcat.games — separate from the broader
  `CLOUDFLARE_API_TOKEN` used for Pages/R2).
- `.github/workflows/cert-rotate.yml`: weekly cron, renews at
  60-day mark via certbot DNS-01, PATCHes every active
  Edgegap app version's env vars (`is_secret: true` on the
  cert/key, plain `TLS_ISSUED_AT` for the freshness check).

**Web debug saga (the actual prod-fixing portion)**:

- Symptom: web build stuck at "Sign in / resuming session…".
- Red herring (~1h): suspected service worker (no), suspected
  R2 cache (partially true — fixed by adding
  `Cache-Control: no-cache, must-revalidate` to wrangler
  uploads in both `scripts/deploy-cf-pages.ps1` and
  `release.yml`).
- Real cause: `addons/gamelift/` directory survived Phase F.
  It's the GameLift Server SDK GDExtension binaries (separate
  from `addons/gamelift_session_manager/` which WAS removed).
  No `web.wasm32` library in the `.gdextension` config →
  Godot's web export errored on load → cascade triggered the
  Godot 4.7-beta1 cyclic-reference parser bug at
  `src/core/auth_client.gd:466`
  (`G.settings.oauth_callback_url`) → auth_client.gd failed
  to compile → `refresh_token()` was a no-op → "Resuming
  session…" never resolved.
- Fix (`275a416`): deleted `gamelift.gdextension` config + 7
  of 9 native binaries (2 Windows DLLs locked by running
  Godot editor); applied `Object.get()` rewrite at
  auth_client.gd:466 per CLAUDE.md's documented surgical fix
  pattern; removed dead `gamelift_session_manager/plugin.cfg`
  reference from `project.godot`.

### Open — immediate next steps

1. **Verify the web build works end-to-end.** Browser cache
   cleared (or Incognito) → load hopnbop.net → confirm
   sign-in flow completes → reach lobby. Should "just work"
   now; if "Resuming session…" persists, the new build still
   has a parse cascade and we need fresh logs to diagnose.
2. **Verify a real cross-play match** (web + native client in
   same lobby). The transport_type now propagates end-to-end,
   nginx terminates wss for the web client, ICE handshake
   should complete. This is the first time the full path has
   been deployed; Layer 1 covers the runtime selection logic
   but not the actual handshake.
3. **Two locked Windows DLLs** in `addons/gamelift/bin/`
   (`libcrypto-3-x64.dll`, `libssl-3-x64.dll`) couldn't be
   deleted because the Godot 4.7-beta1 editor process was
   running. Close the editor and `Remove-Item -Recurse -Force
   addons/gamelift` to nuke the directory entirely. ~6MB of
   dead weight in the export pck until then.
4. **Optional cert hygiene**: cert A (issued in cert-rotate
   run `25301578756`) was briefly stored as `is_secret: false`
   for ~3 minutes before being superseded by cert C. Theoretical
   leak — anyone with `EDGEGAP_TOKEN` could read it during the
   window. Cert is no longer in use; revoke at Let's Encrypt
   for hygiene if paranoid.

### Open — lower priority

- **Layer 2 e2e cross-play test** (multi-process). Plan-doc §2
  Shape B + §3 #8's deferred "real ICE handshake" verification.
  Burns Edgegap quota per run; defer to integration tier.
- **Distributed test architecture research** (plan-doc §4).
  An open-web research agent was launched in the background
  during this session and may have completed; check
  `claude/projects/.../tasks/aee46b61e97dcb98f.output` if
  the new session wants to fold it in.
- **Compliance suite rate limit**: running all 44 tests
  back-to-back hits Nakama's auth rate limit (429s on `~17`
  tests). Need per-test pacing or backoff before the suite
  can be a regular CI gate.
- **Cyclic-ref preventative `.get()` rewrites** for
  `splash.gd`, `fish.gd`, `confirm_overlay.gd`,
  `networked_level.gd` — only apply if web exports flag them.
  `auth_client.gd:466` was promoted from "preventative" to
  "fixed" today after seeing the actual cascade.
- **Doc sweep** in CLAUDE.md (per plan-doc §3's "Doc sweep
  after the fix lands"): "Web Build Cross-Play",
  "Transport Architecture" → "Transport selection flow",
  and "End-to-End Matchmaking Flow" still describe the
  pre-Phase-F intermediate state with `is_web` (the actual
  property name is `platform`). PLATFORM_ARCHITECTURE.md in
  the platform repo also has stale GameLift transport refs.
- **Retire `MIGRATION_PLAN.md`** to `docs/archive/` once the
  post-migration system has been stable for a while.

### Pointers

- Plan doc: `docs/test-architecture-plan.md` (the deeper
  detail behind the WebRTC + tests work).
- Compliance suite: `third_party/snoringcat-platform/addons/snoringcat_platform_client/test/compliance/`
  (canonical source) + the `addons/snoringcat_platform_client/`
  copy in this repo refreshed by
  `scripts/setup-platform-addon.ps1` (re-run after every
  submodule bump).
- Platform-runtime build + deploy: `gh workflow run nakama-runtime.yml`.
- Game-server build + Edgegap registry push: `gh workflow run game-server.yml -f version=vN`.
- Cert rotation manual trigger: `gh workflow run cert-rotate.yml -f force_renew=true`.
- Web client deploy: `scripts/deploy-cf-pages.ps1` (local) or
  the `web-client` job in `release.yml` (CI).
- Hetzner Nakama config: `/opt/nakama/config.yml` (env vars
  in `runtime.env` block); restart with
  `cd /opt/nakama && docker compose restart nakama`.

### Key commits this session

```
275a416 gamelift: remove dead addon + fix web auth cyclic-ref parse error
2230f6e web deploy: force revalidation on R2 wasm/pck heavies
5d55f35 bump snoringcat-platform: transport_select RPC + Layer 1 regression test
9eae649 ci: add cert-rotate workflow for WebRTC signaling TLS
9dd5a18 webrtc cross-play: re-introduce nginx for WSS termination (#7)
e9b19d7 webrtc: read SIGNALING_PORT env on game-server boot (#6)
140143f webrtc cross-play: plumb transport_type through match_ready (#1-5)
0e84a15 bump snoringcat-platform: realtime-socket test rig + 4 tests
20b4ad8 bump snoringcat-platform: pass NAKAMA_PROTOCOL_VERSION
9737cf5 docs: test architecture plan
da8a389 bump snoringcat-platform: 5 more compliance tests
43db749 bump snoringcat-platform: rewrite compliance test suite
74b065e bump version: 0.33.0 -> 0.34.0
```

Submodule (`snoringcat-platform`) commits: `88d1603` (HEAD;
helper unwrap + party assert), `d8ecedb` (transport_select),
`b935514` (socket rig), `c023b82` (5 more tests), `ffd2c56`
(suite rewrite), `553825b` (drop SIGNALING_PORT), `cfe3499`,
`95ea183`, `2461026`. The runtime plugin currently live on
Hetzner is built from `d8ecedb`; the parent submodule pointer
is at `88d1603` (one commit ahead — only the helper/test
changes that don't touch runtime code).



## 2026-05-03 addendum: status sweep + new findings

**Resolved since 2026-05-02:**

- Phase F AWS teardown — done (commit `4f8cfe3`); zero AWS
  resources remain.
- Pulumi state migrated to Cloudflare R2 (`hopnbop-pulumi-state-r2`).
- `runtime_status` static RPC list — done (commit `63affdd`);
  list is now built from a `&registered` slice.
- `NAKAMA_GAME_VERSION` on Hetzner host — already at `0.33.0`
  (probed via `version_check` RPC).
- Edgegap stale image cleanup — already complete; only `v8`
  exists in the registry.
- Compliance test suite — rewritten + expanded for the
  Nakama-backed platform: 33 tests across 14 files (commits
  `43db749`, `da8a389`).
- `addons/gamelift_session_manager` global-class registry leak
  — wiped + rebuilt the local `.godot/global_script_class_cache.cfg`;
  cascading parse errors gone.
- `CLAUDE.md` symlink claim + `src/networking/` path — corrected
  to reflect that the addon is a copy via
  `scripts/setup-platform-addon.ps1`, and that networking lives
  in `addons/rollback_netcode/core/`.

**New findings (2026-05-03):**

- **Protocol version drift.** Client sends `protocol_version=2`
  (`project.godot`); Nakama runtime env has `NAKAMA_PROTOCOL_VERSION`
  unset → server reports `0`. The `version_check` RPC computes
  `is_compatible = client==0 || client==server`, so real
  clients (sending 2) get back `is_compatible=false`. Production
  is still functioning, suggesting the client UI doesn't gate
  on this signal — but it should. Either bump the runtime env
  to 2 or relax the compat rule. Verify which path the client
  takes on `is_compatible=false` before deciding.
- **WebRTC cross-play silently broken** during the Edgegap
  migration. Full audit + fix path in `docs/test-architecture-plan.md`
  §3. Short version: `fleet_allocator.go` never reads `platform`
  from matchmaker properties and never sets `transport_type` in
  the match-ready payload.

**Still open (lower-priority):**

- Cyclic-ref `.get()` rewrites for 4 files
  (`src/objects/splash/splash.gd`, `src/objects/fish/fish.gd`,
  `src/ui/confirm_overlay/confirm_overlay.gd`,
  `src/level/networked_level.gd`). Preventative-only —
  apply only if web build emits "Could not resolve external
  class member ... Cyclic reference" parse errors.
- `MIGRATION_PLAN.md` is now archeology; consider moving to
  `docs/archive/` like `platform-pivot-discussion.md`.

## Status snapshot (what works now)

| Layer | Status |
|---|---|
| Nakama runtime (build `local-pending-172017-dirty`) | ✅ |
| Edgegap server image v8 (active) | ✅ |
| Matchmaker → Edgegap allocation → match_ready → ENet handshake | ✅ |
| Per-player session_id allocation by runtime; server validates | ✅ |
| 3-4 player matches (was hardcoded =2 before today) | ✅ |
| Pre-auth `version_check` via HTTP key | ✅ |
| `match_end` RPC writes leaderboard + match_history | ✅ |
| Runtime hardening: match_end ↔ server_registrations, winner validation, score clamping, register_server idempotency, bulk_import gated behind env var | ✅ |
| Cloudflare Pages web client at v0.33.0 | ✅ |
| Pulumi stack parameterized (zone / location / serverType / image as config keys) | ✅ |
| `perf_tracker` reports realistic packet loss (state_send_interval-aware) | ✅ |

## Live state (don't lose track)

- **Latest commit on `main`:** `3eb8389` (fix Nakama RPC body shape).
- **Nakama runtime plugin:** build_id `local-pending-172017-dirty`,
  built from platform commit `ae914c6` (runtime hardening). Live
  on Hetzner.
- **Edgegap registry:** `v8` is the live tag (active deploy
  source). Older tags `v2`-`v7` should be cleaned up via dashboard
  or the Edgegap API — they're now obsolete.
- **Nakama `runtime.env`:** `EDGEGAP_APP_VERSION=v8`,
  `NAKAMA_GAME_VERSION=0.32.0`. (Game version drifted from the
  current `0.33.0` — see follow-ups.)
- **`addons/gamelift_session_manager/` + `addons/gamelift/` +
  `gamelift-deploy/` + `gamelift-gdextension/`:** all deleted.
  `class_name SessionProvider`, `PreviewSessionProvider`,
  `LocalOnlySessionProvider` moved to `src/core/`.
- **AWS Phase F:** queued. Dry-run clean. Real run blocked on
  `aws sso login --profile hopnbop` token refresh.
- **Cloudflare Pages:** redeployed at v0.33.0. Heavies (.wasm,
  .pck) on R2; rest on Pages.

## Open follow-ups

### Phase F (AWS teardown) — finish

`scripts/phase-f-destroy.ps1` errored at the first delete with
exit 255 because the `hopnbop` SSO session expired. Re-auth
and re-run:

```powershell
aws sso login --profile hopnbop
.\scripts\phase-f-destroy.ps1 -Confirm
```

Targets (from the dry-run): matchmaker, queue, 2 rulesets,
container group def, ECR repo, 5 Secrets Manager entries
(forced delete), CloudFront distribution, S3 website bucket.
**Skips Route 53 zone** (no `-IncludeRoute53Zone` flag) — that
zone exists but Cloudflare is authoritative for hopnbop.net,
so it's harmless to leave for now.

The script also creates a CloudWatch billing alarm at the end —
useful tripwire if any AWS resource creeps back in.

### Bump `NAKAMA_GAME_VERSION` to 0.33.0

Currently `0.32.0` in Nakama config; client is at `0.33.0` after
today's gamelift-removal version bump. Mismatch is informational
only (compat check uses `protocol_version`, which both sides
have at `2`), but worth keeping in sync.

```bash
ssh root@5.78.137.83 \
  "sed -i 's/NAKAMA_GAME_VERSION=0.32.0/NAKAMA_GAME_VERSION=0.33.0/' \
   /opt/nakama/config.yml && \
   cd /opt/nakama && docker compose restart nakama"
```

### Clean up stale Edgegap image tags

Registry has `v2` through `v8`. Only `v8` is referenced. Delete
the obsolete tags via the Edgegap dashboard or:

```bash
EDGEGAP_TOKEN=...  # in /opt/nakama/.env on Hetzner
for v in v2 v3 v4 v5 v6 v7; do
  curl -X DELETE -H "Authorization: token $EDGEGAP_TOKEN" \
    "https://api.edgegap.com/v1/app/hopnbop-server/version/$v"
done
```

### Fix `runtime_status.go` static RPC list

`registered_rpcs` in the status response is hardcoded — still
lists `bulk_import` even when the env-gate skips its
registration. Cosmetic but confusing for an operator probe.
Either build the list dynamically from the initializer state
or pass a `bulkImportRegistered` flag through
`runtimeStatusConfig` like the matchmaker hook does. Triggers a
runtime rebuild when fixed.

### Cyclic-ref preventative `.get()` rewrites (NEXT_STEPS #11)

Still skipped from May 1:
`src/objects/splash/splash.gd`, `src/objects/fish/fish.gd`,
`src/ui/confirm_overlay/confirm_overlay.gd`,
`src/level/networked_level.gd`. Apply only if web build starts
emitting "Could not resolve external class member ... Cyclic
reference" parse errors again.

### Post-Phase-F CLAUDE.md cleanup

Once Phase F runs clean, the CLAUDE.md "AWS Resources" section,
the "Deployment > GameLift Server" section, and the entire
"GameLift Architecture Notes" section are all describing
demolished infra. Replace with a brief "Production deployment"
section that points at:

- `gh workflow run game-server.yml -f version=vN` for image
  builds,
- `nakama-runtime.yml` workflow (or its successor in the
  platform repo) for runtime rolls,
- `scripts/deploy-cf-pages.ps1` for web client.

### Documentation: update PLATFORM_ARCHITECTURE.md

Several sections in the snoringcat-platform repo still describe
the planned/transitional state ("post-migration target",
"snoringcat-platform/backend/runtime/*.go" — runtime is at
`snoringcat-platform/runtime/` now). Worth a sweep once the
above docs cleanup happens in hopnbop.

### Move `phase-f-destroy.ps1` out (eventually)

After Phase F runs and stays clean for a while, this script
becomes dead weight in `hopnbop_private/scripts/`. Either delete
or move to a generic `scripts/decommission/aws/` directory in
case another game ever needs to do the same migration.

---

## Already shipped this session (2026-05-02)

Many commits across three repos. Highlights, in roughly the
order they landed:

**hopnbop_private:**
- `68ef668` edgegap: real session validation, env-driven
  expected count (P0 trio: EXPECTED_PLAYER_COUNT,
  EdgegapServerProvider, runtime-issued session_ids; P1.5
  notification poller fix; P1.6 silent-exit diagnostics).
- `59396d2` game_panel: defer match-end cleanup to next idle
  tick (silent C1/C2 exit bug, root cause was multiplayer-
  peer teardown from inside the peer-disconnected callback).
- `55e02dc` Move platform-shared infra to snoringcat-platform
  submodule (cost-monitor, runtime, Pulumi, remote configs,
  scripts).
- `0611b42` deps: bump rollback_netcode (perf-loss fix) +
  platform (pulumi parameterization).
- `4aecd49` cleanup: route version_check + match_end through
  Nakama, drop gamelift from Edgegap export.
- `cf0942c` fix: restore gamelift addon binaries on Edgegap
  container; debug check_version transport (the
  `extension_list.cfg` regression).
- `4163c2a` fix: revert Linux Server export-filter — gamelift
  addon hosts SessionProvider base class (the
  parse-time-undefined-class bug).
- `0b9b059` gamelift: remove the addon, the build env, the
  deploy scripts, the tests (~28k-line deletion).
- `3eb8389` fix: Nakama RPC body shape — bare JSON, not
  JSON-encoded string (the silent-pass version_check bug).

**snoringcat-platform (submodule):**
- `0731de1` Migrate platform-shared infra in from
  hopnbop_private.
- `790b75b` pulumi: extract zone/location/server-type into
  stack config.
- `4b8b2f7` cost-monitor: track CF Pages builds, simplify
  daily summary (parallel work stream).
- `ae914c6` runtime: harden write RPCs against forged calls
  from client builds (match_end ↔ registrations dedup,
  winner validation, stat clamping, register_server
  idempotency, bulk_import env gate).

**rollback_netcode (submodule):**
- `6065de3` perf_tracker: compensate for state_send_interval
  in loss metric.

Live state changes (not in git): GitHub repo secrets
`NAKAMA_HOST` + `NAKAMA_SSH_KEY` populated; Edgegap registry
`v1` deleted, `v2` through `v8` still present (`v8` live);
Nakama runtime plugin scp'd + restarted multiple times during
the day; Hetzner runtime config bumped through `v3 → v4 → v5
→ v6 → v7 → v8`.

---

## Useful diagnostic commands (preserve)

Decrypt Nakama SSH key (one-shot, cleans up at end):

```powershell
$keyDir = "$env:TEMP\nakama-deploy"
New-Item -ItemType Directory $keyDir -Force | Out-Null
age -d -i $HOME\.config\age\key.txt -o $keyDir\id_ed25519 `
    $HOME\Repositories\claude-config\secrets\hopnbop-migration-nakama-ssh.age
icacls $keyDir\id_ed25519 /inheritance:r /grant:r "${env:USERNAME}:(R)" | Out-Null
# ... use it ...
icacls $keyDir\id_ed25519 /grant "${env:USERNAME}:(F)" | Out-Null
Remove-Item -Recurse -Force $keyDir
```

Probe Nakama runtime status:

```powershell
$line = & ssh -i $keyDir\id_ed25519 root@5.78.137.83 "grep '^NAKAMA_HTTP_KEY=' /opt/nakama/.env"
$HTTP_KEY = $line.Split('=', 2)[1]
curl.exe -sS -X POST "https://nakama.snoringcat.games/v2/rpc/runtime_status?http_key=$HTTP_KEY&unwrap=true" `
  -H "Content-Type: application/json" -d '""' | python -m json.tool
```

Verify runtime hardening (match_end with fake request_id should
return HTTP 404 "unknown request_id"):

```bash
HTTP_KEY=...
curl -sS -X POST \
  "https://nakama.snoringcat.games/v2/rpc/match_end?http_key=$HTTP_KEY&unwrap=true" \
  -H "Content-Type: application/json" \
  -d '{"request_id":"fake","winner_id":"x","players":[{"user_id":"x","score":1,"kills":0,"bumps":0}]}'
```

Check Edgegap deployment status (`REQ_ID` from `match_ready`):

```powershell
$EDGEGAP_TOKEN = ...  # /opt/nakama/.env on Hetzner
curl.exe -sS -H "Authorization: token $EDGEGAP_TOKEN" `
  "https://api.edgegap.com/v1/status/REQ_ID" | python -m json.tool
```

Trigger game-server build + watch:

```powershell
gh workflow run game-server.yml -f version=v9
gh run watch (gh run list --workflow=game-server.yml --limit 1 --json databaseId -q '.[0].databaseId')
```

Rebuild Nakama runtime plugin and deploy:

```bash
cd third_party/snoringcat-platform/runtime
BUILD_ID="local-$(git rev-parse --short HEAD)-dirty"
BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LDFLAGS="-X main.BuildID=${BUILD_ID} -X main.BuildTime=${BUILD_TIME}"
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd):/backend" -w /backend \
  heroiclabs/nakama-pluginbuilder:3.25.0 build -buildmode=plugin -trimpath \
  -ldflags "${LDFLAGS}" -o ./build/snoringcat.so .
# then scp + restart via the SSH key flow above
```
