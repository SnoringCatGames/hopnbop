# Ledger done

Done items moved out of `LEDGER.md` by the ledger diet
(`scripts/ledger_diet.mjs` in knotmaze, K353; applied 2026-10-15), verbatim,
under their ID: every entry resolved before 2026-10-12 or undated, and the
full text of the newer ones, which the ledger keeps as a one-line entry. New
entries go at the bottom.

## H11 (Done 2026-10-14)

- **H11** · CI never ran on push to main. Fixed: `push:
  branches: [main]` triggers on pr-validate and
  compliance-matrix (2026-10-14).

## H67 (Done, undated)

- **H67** · Settings reverted two launches later. Fixed in
  `678af560`: pristine-defaults comparison in LocalSettings,
  sync-at advanced on successful save, echo regression test
  promoted into test/unit/platform (1/1, sync suite 16/16).

## H70 (Done, undated)

- **H70** · Signed signaling URL was logged verbatim. Fixed:
  the log line strips the query (token) in
  `game_session_manager.gd`.

## H69 (Done 2026-10-14)

- **H69** · `sign-out-local-match` and `sign-out-play-again`
  scenarios timed out at the 180 s match length. Fixed: both
  pin `match_duration_sec: 10`; harness-verified PASS
  (2026-10-14).

## H38 (Done, undated)

- **H38** · Clients crashed (signal 11) when the server went
  away mid-match. Fixed: the reconnect start, the first
  reconnect attempt, and both exit-match calls on the
  disconnect paths are now deferred out of the
  peer_disconnected dispatch, mirroring the normal match-end
  cleanup. Editor-path verified (connector GUT 3/3, harness
  offline-move-jump PASS); the release-template check still
  waits on H72, since the editor hides this crash family.

## H39 (Done 2026-10-14)

- **H39** · Networked pause shipped enabled. Decided by Levi
  2026-10-14 (off in release): `_apply_release_values` now sets
  `is_server_pause_enabled` from
  `RELEASE_IS_SERVER_PAUSE_ENABLED = false`; editor and harness
  keep the settings.tres value. Covered by
  `test_settings_release_values.gd` (2/2).

## H40 (Done 2026-10-14)

- **H40** · Legal texts missing from every export (LG-1, ops C7).
  Fixed: `include_filter="legal/*"` on all four presets, plus a
  pr-validate export-smoke step that fails if either pack lacks
  `legal/en/{terms,privacy,data_deletion}.txt`. Verified locally: web
  export pack contains all three (2026-10-14).

## H37 (Done 2026-10-14)

- **H37** · Systems audit, test run, history recap and TODO-scratch.md
  triage (Levi, 2026-10-14). Report `docs/design/H37_systems_audit.md`,
  appendices and reusable probes in `docs/design/H37/`. Its items are
  filed: H38-H100 here, SP26-SP71, RN6-RN8 and CC51-CC57. Done in
  6910dce4 (2026-10-14).

## H25 (Done, undated)

- **H25** · Quitting during the mid-match reconnect loop crashes with
  signal 11. The game's own exit paths avoid it, and so does the
  harness. (Agent a9dc5b3c.) Dropped: superseded by H38, which has the
  full trigger set and the fix (H37).

## H34 (Done 2026-10-13)

- **H34** · CLAUDE.md slimmed to the context budget: 2,333 lines /
  ~24k tokens → 400 lines / ~4.8k, the same split knotmaze used for
  K45. Binding rules stay; lore moved verbatim to path-scoped
  `.claude/rules/` (deploy, transport, testing, gdscript-style, ui,
  crash-reporting), the harness reference to
  `scripts/agent/README.md`, playbooks and the netcode explainer to
  `docs/`, history to `docs/history.md`. Done in 34971411
  (2026-10-13); Measure-ContextBudget now lists hopnbop within
  budget.

## H36 (Done 2026-10-12)

- **H36** · Edgegap v27 and v28 deactivated 2026-10-12 (API PATCH
  `is_active=false`); only v29 is active. Edgegap-side state, no commit.
  `game-server.yml` still leaves the prior version active after every
  release, so deactivate the superseded one as part of each release;
  check-prod step 10 flags actives piling up again.

## H16 (Done 2026-10-12)

- **H16** · Checked 2026-10-12 against the real 0.54.0 web export:
  mounted `index.pck` with `ProjectSettings.load_resource_pack` and
  probed `FileAccess.file_exists` on the exact paths
  `localized_name_config.gd` reads. All `translations/names/*` and
  `translations/adjectives/*` CSVs ship, so localized bunny names and
  adjectives work in exports. The suspicion (sources stripped by the
  translation importer) was wrong; nothing to fix.

## H14 (Done 2026-10-12)

- **H14** · Runtime HTTP key rotated 2026-10-12, right after H4
  shipped (leak plan step 3, closing the key committed here from
  12a93325 until 15498835). Rotated in `credentials.env` (blob
  re-encrypted, claude-config 6279e62), `/opt/nakama/.env` + nakama
  recreate (healthy; new key 200, old key 401), the Edgegap v29 env
  (PATCH), and a hopnbop repo-level `NAKAMA_HTTP_KEY` Actions secret.
  Caddy `access.log` truncated (no rotated files existed). Verified:
  synthetic matches green on both allocator paths (servers
  authenticated with the new key) and nightly-smoke green from CI
  (run 38325468725). Residue: the desktop re-decrypts (CC31), and gh
  here lacks admin:org, so if an org-level `NAKAMA_HTTP_KEY` exists it
  still holds the dead old key; hopnbop's repo secret shadows it.

## H4 (Done 2026-10-12)

- **H4** · Release 0.54.0 shipped and verified 2026-10-12 (laptop
  session). Levi confirmed the shipping values; exported builds now
  enforce them in code (180 s matches, HUD and overhead labels on,
  splash plays: `Settings.apply_release_overrides()` from
  `G._enter_tree`, GUT `test_settings_release_values.gd`) in 8ca156e7,
  boot page in 2abf477c. Game server v29 built and registered (run
  38313778919); web 0.54.0 on Pages + R2; `register_game` serves
  0.54.0 / v29 / legal 1.2. Verified: live hopnbop.net boot check
  (overrides applied, splash plays, no script errors), version_check,
  the check-prod checks all green, synthetic-match-probe green on both
  allocator paths with clean Edgegap teardown. No `v*` tag pushed.

## H1 (Done 2026-10-11)

- **H1** · Crash reporting was dead (no client session lookup, and the
  runtime never had a `crash_report` RPC). Done in hopnbop 6b0dc6d7 and
  platform 6081b82 (2026-10-11), live on prod; design review in
  `docs/design/crash_report_review.md`.

## H2 (Done 2026-10-11)

- **H2** · Local GUT runs loaded the real token store and refreshed that
  session against PRODUCTION Nakama on the first frame; a rejected
  refresh also signed the developer out. Done in the commit that moved
  this item here (2026-10-11): under GUT, in editor builds only, G hands
  Platform `user://test_auth.cfg`, deleted at boot, so every run starts
  signed out. Guarded by `test/unit/core/test_auth_file_isolation.gd`.

## H12 (Done 2026-10-11)

- **H12** · `upgrade_levels.tscn` failed to parse (dead ld58 content
  that broke exports). Done in b998107d (2026-10-11).

## H13 (Done 2026-10-11)

- **H13** · Nothing surfaced crash reports. Done in claude-config
  ad8c6ca (2026-10-11): prod-health-check's `crashes:` line (24 h count,
  new signatures, top 5) and step 9 of the hopnbop-check-prod skill.
