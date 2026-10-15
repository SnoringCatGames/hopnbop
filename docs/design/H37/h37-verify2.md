# H37 phase 2b: h37-verify2

Started 2026-10-14 11:01. Repos at: hopnbop 59a12b67, platform 8e85e8a,
netcode 7d6ebd9. Brief: `docs/design/H37_audit_brief.md` "Phase 2b",
h37-verify2's list. Scratch: `.claude/probes/H37/h37-verify2/`.

Verdicts: Verified (a run I did, or a cited test that covers the case),
Believed (code reading), Suspect, Broken.

Probe paths below are relative to `.claude/probes/H37/h37-verify2/`.
The Go probes run in copies: `runtime-copy/` (platform `runtime/` at
8e85e8a plus `h37v2_hook_test.go`) and `nakama-src/` (a shallow clone of
heroiclabs/nakama v3.25.0 plus `server/h37v2_matchmaker_stall_test.go`).
User ids in the probes are made up.

## 1. G1.2 guessable session ids (11:13)

**Broken, Verified** (Go and GUT probes; h37-matchmaking had Believed).
Any member of a matched set can compute every other member's session id
and claim it on the game server before its owner does.

- Minting: `plat:runtime/fleet_allocator.go:722-727` builds
  `<nakama user id>_<i>` for each i below the entry's `player_count`
  string property. The list reaches the server as `EXPECTED_SESSION_IDS`
  (914-915, and the local allocator's container env), and the server's
  allowlist is an exact-match set of that list
  (`game:src/core/edgegap_server_provider.gd:301-317`, checks 230-258).
- What a fellow player holds: Nakama 3.25.0 sends every member the
  MatchmakerMatched envelope with every member's user id, session id,
  username and string properties, `player_count` included
  (`nakama-src/server/matchmaker.go:497-503`). The runtime's match_ready
  gives each user only their own ids, which hides nothing.
- Go probe, `TestH37v2SessionIDsDerivableFromEnvelope`
  (`runtime-copy/h37v2_hook_test.go`, log `go-test-hook.log`): the real
  `OnMatchmakerMatched` (local mode, Docker faked in memory) on a set of
  A (2 local players) and B (1) put `[A_0 A_1 B_0]` in the container's
  `EXPECTED_SESSION_IDS`; the ids computed from the envelope's fields
  alone are identical. match_ready to A carried only A_0 and A_1.
- GUT probe, `test_h37v2_guessable_sids.gd` (log
  `gut-guessable-sids.log`: 3 tests, 3 passing, 14 asserts), allowlist
  loaded through `_load_allowlist_from_env()`:
  - peer 5 (A) declares B's computed id with B's account id: accepted,
    claimed, and the slot recorded as B's account (H17). B (peer 6) then
    declares its own id and is the peer rejected ("already claimed").
    Today the connector ignores that rejection, gives B the same player
    id and moves the slot to peer 6 (G1.3: the last declarer wins).
  - one peer claims all three slots in one declare (3 ids is within
    `max_local_player_count` = 4, `net:core/network_settings.gd:156`);
    B is rejected.
  - control: `B_1`, which the runtime did not mint, is rejected.
- When: match_ready is sent inside the hook (`fleet_allocator.go:
  1218-1238`) and the envelope right after the hook returns
  (`matchmaker.go:486-531`), so a member has B's id before anyone's
  transport is up (Believed, source order). A user id learned earlier
  (party, friends, a previous match) works too. A stranger also needs the
  server's address and port, which only match_ready carries. The public
  leaderboard route shows no user ids (`plat:runtime/
  leaderboard_public.go:116-120`); which other Nakama APIs show user ids
  to strangers I did not check.
- What it changes for the fixes:
  - G1.1 must not ship alone. Enforcing the rejection (disconnect the
    rejected peer) with guessable ids kicks the owner and keeps the
    thief; today's last-declarer-wins (G1.3) at least limits it to a race.
  - Make the ids unguessable first: the runtime mints a random 128-bit
    token per slot, sends each user only theirs, and gives the server a
    token-to-user-id map instead of a list, so the server derives the
    backend id itself (this also closes H17).
  - Then G1.3: a second claim of a token is a reconnect only from the
    same account and only after the earlier peer has dropped (or the
    server drops it first); otherwise reject and disconnect the new peer.
    Keep the tokens out of anything the server replicates.

## 2. No match forms while an allocation runs; one timeout cancels the set (11:13)

**Finding 3 (stall): Broken, Verified** (h37-matchmaking had Believed).

- Nakama half, `nakama-src/server/h37v2_matchmaker_stall_test.go` (log
  `go-test-nakama-stall.log`, PASS): Nakama 3.25.0's real matchmaker
  (prod and dev run `heroiclabs/nakama:3.25.0`,
  `plat:infra/remote/nakama/docker-compose.yml:49`; the test's
  interval_sec 1 matches prod `config.yml:27`), the MatchmakerMatched hook
  replaced by a sleep for pair (a1,a2). An unrelated pair (b1,b2, other
  mode) queues 0.2 s after a1/a2's hook starts.
  - hold 0 s: b's hook ran 0.79 s after b queued (the next tick).
  - hold 6 s: b's hook ran at +7 s, the moment a's hook returned (b
    waited 5.79 s), and both pairs' envelopes went out at +7 s.
- Runtime half, `TestH37v2HookBlocksForWholeAllocation` (log
  `go-test-hook.log`): the real `OnMatchmakerMatched`, local mode, with a
  container that registers after 3 s, returned after 3 s and sent
  match_ready at +3 s. The hook allocates synchronously.
- So every queued player on the Nakama node, any game or mode, waits out
  the slowest allocation in flight: container boot plus registration
  for local (the 30 s register timeout caps a bad one), up to 3 Edgegap
  attempts for Edgegap (h37-matchmaking's estimate of about 6 min worst
  case is Believed; I did not re-measure it).

**Finding 4 (one player's 120 s timeout cancels the whole set): Broken,
Verified** (each link by a run, and the links meet; h37-matchmaking had
the composite Believed).

- SDK link: the 120 s timer starts at ticket creation
  (`plat:addons/snoringcat_platform_client/core/matchmaker_api_client.gd:49`,
  841) and, since the client learns of the match only from the envelope
  after the hook, keeps running through the allocation. On expiry it
  sends `cancel_matchmaking_allocation` with `{}` over the socket (249-250):
  h37-matchmaking's `test_timeout_sends_allocation_cancel` (passed,
  `h37-matchmaking/gut-ghost-ticket.log`; their run, not mine).
- Runtime link, `TestH37v2OneUserCancelAbortsMatchedSet` (log
  `go-test-hook.log`): with an allocation in flight, A calls the RPC
  (game id from session vars, as `plat:runtime/auth.go:79` reads it) at
  +0.7 s and gets `{"cancelled":true,"ok":true}`; the hook returns at
  0.7 s; A and B, who did not cancel, both get `match_failed` reason
  `cancelled` with "Match cancelled by another player." (the canceller
  gets that text too); the container is stopped (create, start, inspect,
  stop).
- Together: a player whose ticket is near 120 s old when its set is
  matched (a long queue, or a queue behind a slow allocation, finding 3)
  fails the whole set, and one slow Edgegap allocation can push many
  queued players past 120 s at once.
- Fix direction: allocate outside the hook (the hook records the set and
  returns; a goroutine allocates and sends match_ready), tell the client
  at hook entry that its set is allocating so the SDK stops the timer,
  and send `cancel_matchmaking_allocation` only on an explicit Cancel,
  never on the timer.

## 3. AN-1 guest upgrade signs in instead of linking; DEL-2 (11:19)

**AN-1: Broken, Verified** (GUT probe; h37-account had "Broken by code").

- Flow: Settings sends a guest to the "Keep Your Progress" panel, whose
  Google row calls `login_with_provider` when `is_anonymous`
  (`game:src/ui/settings_panel/link_account_row.gd:74-79`; a signed-in
  player gets `link_provider`, 80-85). `login_with_provider` opens the
  browser without setting `_is_linking` (`plat:addons/
  snoringcat_platform_client/core/auth_api_client.gd:258-272`), so the
  callback picks `/auth/login` (641-643; web 795-797) and dispatches to
  `_do_provider_auth` (863-864), which calls
  `authenticate_google_async(id_token, null, true, vars)` (1056-1057):
  Nakama's sign-in, create=true. Nothing in the game, SDK or runtime
  calls `link_device_async` (grep), and no RPC moves anything.
- Probe `test_h37v2_guest_upgrade.gd` (log `gut-guest-upgrade.log`: 2
  tests, 2 passing, 19 asserts). Real `LinkAccountRow` and
  `PlatformAuthApiClient`, a fake Nakama client that records every call;
  only the browser step and Google's code exchange are stubbed.
  - A guest who played online (`login_anonymous`, then `get_guest_jwt`
    -> `authenticate_device`) presses the row: the browser opens for a
    sign-in (`is_link` false), the dispatch line reads
    `Nakama auth dispatch: /auth/login`, and the whole call list is
    `authenticate_device, authenticate_google (create=true),
    get_account`: no `link_google`, no `link_device`, no RPC.
  - Afterwards the store holds the Google identity's account id, not the
    guest's, with `is_anonymous` false. The device id stays on disk until
    sign-out, whose `clear_tokens()` (`game:src/core/sign_out_router.gd:77`,
    `auth_token_store.gd:161`) erases it; nothing on the device names the
    guest account after that.
  - Control: `link_provider` from the same guest session calls
    `link_google` on the guest's own session and keeps its account id.
    So the fix is to route guests with a device session through the link
    path. Residual for that fix: after the link the store still says
    `is_anonymous` true and `provider` anonymous (link mode updates only
    the profile, `auth_api_client.gd:1265-1270`).
- Survival, by part:
  - Account: survives on the server, untouched and unreachable; no job
    purges such accounts (no anonymous, device or inactive handling in
    `plat:runtime/account_cron.go`, grep). Believed.
  - Stats: match results go to `LeaderboardRecordWrite` under each
    player's user id (`plat:runtime/match_lifecycle.go:523-530`), so a
    guest's results stay on the device account and the Google account
    starts empty. Believed (runtime code), the account switch Verified.
  - Friends: the client gives guests none (the friends poller, party
    manager and leaderboard panel skip anonymous players:
    `friends_notification_poller.gd:466`, `party_manager.gd:567`,
    `leaderboard_panel.gd:78`), but the game server reports nobody as
    anonymous (`edgegap_server_provider.gd:285-289`), so others can send
    a guest friend requests, which are stranded with the account.
    Believed.
- Not covered: the Google identity already owning an account (the link
  fails with "already in use"; today's merge path is dead,
  `auth_api_client.gd` `_MERGE_ENDPOINT` branch, h37-account LK-2/LK-4),
  and web's popup flow beyond the shared endpoint choice.

**DEL-2: Broken, Verified** (my re-run of h37-account's
`test_del2_failed_delete_is_reported_as_auth_failure`, log
`gut-del2-rerun.log`: 1 test, 1 passing, 6 asserts).

- Why: `_send_delete_request` clears `_is_deleting` before calling
  `_emit_failure` (`auth_api_client.gd:888-899`), so `_emit_failure`
  skips its `delete_completed` branch (1368-1370) and emits
  `auth_completed(false)`.
- Effects (Believed, code): the confirm panel listens only to
  `delete_completed` (`game:src/ui/settings_panel/
  delete_account_confirm_panel.gd:140-142`), so it stays busy with the
  confirm row disabled and its failure toast (160-170) never shows; the
  notification socket stops on any `auth_completed(false)`
  (`notification_socket_client.gd:321-326`, H23) while the player stays
  signed in.
- Fix: drop the two early `_is_deleting = false` lines so
  `_emit_failure` routes to `delete_completed`.

**DEL-2 UI half: Broken, Verified (11:26)**, upgrading "Effects" above.
Probe `test_h37v2_del2_panel.gd` (log `gut-del2-panel.log`: 1 test, 1
passing, 9 asserts) drives the real `DeleteAccountConfirmPanel` handlers
(state as after `build_ui()` with the verify word typed) and the real auth
client, whose delete RPC fails with a 503. After Confirm: the RPC was sent,
`delete_completed` never fired, `auth_completed(false)` did, and the panel
is still busy with its confirm row disabled. Retyping the word leaves it
disabled, and a second press sends nothing (`_on_confirm_pressed` returns
on `_is_busy`, `delete_account_confirm_panel.gd:129-130`). The player sees
no error and cannot retry until the panel is closed. The toast and the
socket stop are still Believed (code).

AN-1 fix note (11:29): Nakama 3.25.0 `LinkGoogle` refuses a Google id
that another account holds, `codes.AlreadyExists` "Google ID is already
in use." (`nakama-src/server/core_link.go:361-375`). So a fix that links
from the guest session must also handle a returning player whose Google
identity already has an account (merge, or tell the player).

## 4. LG-1 on every export preset (11:29, export results below when net.lock frees)

Static (Believed): all four presets (`Web`, `Windows Desktop`,
`Linux Server`, `Android`) have `export_filter="all_resources"` and
`include_filter=""` (`game:export_presets.cfg:9-10, 55-56, 123-124,
166-167`); `legal/en/{terms,privacy,data_deletion}.txt` are plain text,
not resources, and `legal_doc_screen.gd:152-154` reads them with
`FileAccess` from `res://legal/`.

Windows Desktop, from an existing artifact (Verified): h37-verify's
`--export-release "Windows Desktop"` of today 10:43 (Godot 4.7.2, this
HEAD; `h37-verify/export/hopnbop.pck`) listed with my `list_pack.py`
(it reads the PCK directory; header PCK v4, Godot 4.7.2): 1978 entries,
no `legal/` entry and no `.txt` entry at all, while the reader is in
(`src/ui/screens/legal_doc_screen.gdc`, its `.tscn.remap` and exported
scene).

**Every preset: Broken, Verified (11:44).** `net.lock` came free early;
I held it 11:42:20 to 11:43:58. `export.ps1` ran
`--headless --path . --export-pack "<preset>" export/<slug>.zip` with
Godot 4.7.2 (console exe, throwaway APPDATA) for each preset; no export
templates are needed for a pack. Every export exited 0 (20-33 s; the
only ERROR in the logs is the usual "15 resources still in use at
exit"), and `git status --porcelain` was the same before and after.
`list_pack.py` on the zips (`export-run.log`):

| Preset | Entries | `legal/` | any `.txt` | reader (`legal_doc_screen.gdc`) |
|---|---|---|---|---|
| Web | 1975 | none | none | in |
| Windows Desktop | 1978 | none | none | in |
| Linux Server | 1835 | none | none | in |
| Android | 1978 | none | none | in |

The Windows pack-only zip has the same 1978 entries as h37-verify's full
release `.pck` above, so a pack export selects files the way a full
export does. So on every preset the Terms, Privacy and Data Deletion
screens have no file to read and show nothing (the reader's
`FileAccess.file_exists` checks fail; that part is Believed, code). The
Linux Server pack only matters if a server ever shows the screen. Fix
(not tested): add `legal/*` (or `*.txt` under `legal/`) to
`include_filter` on every client preset, and a CI check that lists an
exported pack for `legal/en/terms.txt`. The exports (about 27 MB each)
are in `export/`; delete them when the audit closes.

## 5. On the stack: 4a to 4e (11:44)

Nothing left for me. When `net.lock` came free (11:42) `h37-verify.md`
had sections 4a, 4b, 4c, 4d and 4e (and 4f and its ranked summary), so
h37-verify reached all five; I ran no stack.

Done 11:45
