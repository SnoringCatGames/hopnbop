# H37 verify (phase 2)
Started 2026-10-14 10:37 PDT. Repos at: hopnbop e03f8861, platform 8e85e8a, netcode 7d6ebd9.
Holds `.claude/probes/H37/net.lock` for the whole run. Scratch: `h37-verify/`.

## 0. How close production is to the local port-pool leak

Sent to the coordinator at 10:40. Local records only; nothing touched production.

- **Leak confirmed in code (Verified by reading plus h37-matchmaking's probe):** `plat:runtime/local_allocator.go:323-346` `Stop` never calls `l.ports.release` (its own comment at 328-335 says "we leak them until the runtime restarts"). `release` runs only on Allocate's error paths (242, 248, 313). The file hasn't changed since 2026-06-02 (`9d55335`), so every deployed build since then has the leak.
- **Production runs hybrid (Observed):** `game:game.yaml:73` `allocator_mode: hybrid`. Pool ranges: `plat:scripts/lib/nakama-env.ps1:89-90` (30000-30099 UDP, 30100-30199 TCP, so 100 pairs). The synthetic probe reports `kind=local` 6 days a week and `kind=edgegap` on Wednesdays.
- **Last Nakama restart (Observed):** the runtime loaded at 2026-10-13T00:02:20Z (build `c4c7413`). That's the line `prod-health-check` takes from `docker logs nakama | grep 'runtime loaded' | tail -1` (`claude-config:jobs/scripts/prod-health-check.ps1:90`), last read 2026-10-14T12:51Z. The newest `nakama-runtime.yml` run is 2026-10-12 21:43Z (`gh run list`), so there has been no deploy since.
- **Local allocations since that restart:** 1 synthetic probe (2026-10-13T07:53Z, `kind=local`); today's (10-14) was Edgegap. Player NA matches are unknown: no local record counts matches (player-metrics-daily has only DAU 3 on 10-13 and DAU 1 on 10-14, with active_now 0; edgegap-deploy-success-rate sees only Edgegap). **Estimate: 1-3 of 100 pairs used.** Confidence: high for the restart time and the probe count, medium for player matches.
- **Historical bound (Observed):** runtime deploys on 2026-07-18 05:11Z (`c4e5f78`) and 2026-10-11 18:07Z (`9679db4`), with nothing between them, so prod went 85 days without a Nakama restart. In that stretch the synthetic probe made 70 successful local allocations (77 entries: 70 local ok, 5 red `auth` before allocation, 2 Edgegap) and never failed to allocate. So player NA matches in those 85 days were at most about 30, and the pool reached at least 70% used.
- **Time to exhaustion with no players:** 100 pairs at 6 probe allocations a week is about 16-17 weeks after a restart. Each player NA match brings it closer. Detection: the synthetic probe would go red with `allocation_failed` on its next local day, and players see LOADING.ALLOCATION_FAILED (`game:src/core/game_panel.gd:746-751`). Only a Nakama restart (any runtime deploy) clears it.
- **Verdict: Broken, latent.** Not close today (a restart 2 days ago). It goes off only after about 4 months without a runtime deploy, or sooner with real NA traffic. Frequent runtime deploys mask it, and the 85-day stretch shows deploys can stop for that long.


## 1. Client crash (signal 11) when the server goes away mid-match

### Sizing: does production quit with clients still connected? (Believed, code)
- No, not in the normal end-of-match flow. At match end a production
  server calls `server_close_multiplayer_session()` (`src/core/game_panel.gd:1628-1644`;
  rollback_netcode `core/network_connector.gd:441-453`: refuse new
  connections, `disconnect_peer` each peer). It quits only after the last
  peer is gone: `_server_on_client_disconnected` -> remaining peers 0 ->
  `_server_on_all_clients_disconnected` -> "Production mode: Exiting
  server", 12 s timer, `get_tree().quit()` (`src/core/game_session_manager.gd:521-569`).
- That disconnect reaches the client while `G.match_state.is_match_ended`
  is set, so `_client_on_server_disconnected` marks it expected
  (`game_session_manager.gd:489-518`) and `_on_connection_lost` takes
  `_client_transition_to_game_over()` (`game_panel.gd:491-556`), whose
  cleanup is `call_deferred` precisely because of this crash
  (`game_panel.gd:1443-1464`). Run below checks it.
- The crash needs an UNEXPECTED disconnect. Two synchronous paths, both
  inside the engine's `peer_disconnected` dispatch (`network_connector.gd:363`
  `disconnected.emit`):
  - mid-match: `_on_connection_lost` -> `reconnect_handler.start()` ->
    `_attempt_reconnect()` at once (`src/core/reconnect_handler.gd:137`) ->
    `client_connect_to_server` (`:193`) -> new `multiplayer.multiplayer_peer`
    (`network_connector.gd:293`). exec-b runs 3, 4, 6.
  - not mid-match (loading, lobby): `client_exit_match()` (`game_panel.gd:556`)
    -> `_client_cleanup_after_match` -> `client_disconnect()` and
    `multiplayer.multiplayer_peer = null` synchronously (`game_panel.gd:1250-1284`,
    `:1414-1433`). exec-b run 1.
- Production triggers for an unexpected disconnect (Believed): an ENet
  timeout or network drop, a server crash, a container stop (Edgegap
  stop, cost-monitor or leak sweep), `_server_abort_not_enough_players`
  (`game_session_manager.gd:600+`, notify + close while clients load),
  the grace timeout with at most one peer (`src/core/edgegap_server_provider.gd:418-494`).
  A SERVER_SHUTDOWN notice before the close sets the reason, but
  `is_expected` is only MATCH_FINISHED or `is_match_ended`, so a pre-match
  abort still takes the synchronous `client_exit_match()` path.
- Consequence (Believed, from exec-b's 8 of 8 crashed clients): the
  reconnect loop can never succeed on ENet; it crashes on attempt 1.

### Run 1: production end-of-match flow, editor binary (Verified, 1 run, 2 clients)
- Scenario `h37-verify/scenarios/h37v-prod-quit.json`, run
  `h37-verify/runs/20261014-104816-h37v-prod-quit`. A 10 s match, 2 clients;
  every process evals `Netcode.set('is_preview', false)` 1 s into the match,
  so the server takes the production branches at match end.
- Client 1 (client 2 the same): `Match ended, starting client-side
  game-over timer (5.0s)` at 21.7 s; at 26.687 `Disconnected from server:
  CONNECTION_LOST`, `Match ended, showing results` (the expected path),
  `Switching screens: GAME => GAME_OVER`. Still on GAME_OVER 18 s later,
  after the server had quit. Both clients exit 0, 9/9 steps.
- Server: `Client disconnected` x2, `All clients disconnected`,
  `Production mode: Exiting server` at 32.6 s, then the process quit at
  44.6 s (12 s, as coded); the harness flags only "the game quit before
  the scenario finished", which is the point of the run.
- So the normal production end of match does not crash the clients.
  The disconnect still arrives as CONNECTION_LOST (no reason is sent by
  `server_close_multiplayer_session`); the client is saved only by
  `is_match_ended` already being true.

### Run 2: one client quits during the match, production server (Verified, 1 run)
- Scenario `h37v-prematch-abort.json`, run `20261014-105120-h37v-prematch-abort`.
  Meant to hit the pre-match abort; it could not: the harness's preview
  server sets `is_game_active` and `is_match_active` together (server
  eval at game start: match active, 2 peers), so there is no loading
  window. What it did show: client 2 quits mid-match, client 1 keeps
  playing (exit 0), and the server quits 12 s after client 1 leaves.
- Pre-match abort -> synchronous `client_exit_match()` -> crash stays
  Believed (code above, plus exec-b run 1, which crashed on that path).

### Exported release clients: not run (sandbox not reproducible)
- Exported OK: `--export-release "Windows Desktop"` into
  `h37-verify/export/` (exit 0, 12 s; pck 30.9 MB; `export.log`).
- The harness cannot drive it. `scripts/.gdignore` exists, so Godot's
  filesystem skips `scripts/` and no `res://scripts/` file is in the pck
  (export.log lists none). Every harness process starts with
  `-s res://scripts/agent/agent_bootstrap.gd` (`scripts/agent/run-game.ps1:387`
  area), and the bootstrap loads the driver from res://
  (`agent_bootstrap.gd:17`). The URL blackhole lives in the driver
  (`agent_driver.gd:16-21`), so an exported client without it boots
  against the production backend URLs. A throwaway APPDATA alone is not
  the sandbox, so per the brief it was not run.
- The release template against the source tree is no substitute
  either: a non-editor binary is never preview
  (`network_orchestrator.gd:185-195`), so its clients take the
  sign-in and matchmaking path, which the driver does not navigate.
- Release behaviour stays Believed: the crash path has no preview or
  debug branch except a log line (`network_connector.gd:365-371`).
- Harness gap worth a ledger item: no way to run an exported build
  (agent scripts excluded from exports by `scripts/.gdignore`).
- A harder blocker, found at 10:56: the 4.7.2 release template refuses
  `--path` outright ("this Godot binary was compiled without support for
  path overrides. Aborting.", exit 1; the message says it takes a build with
  `disable_path_overrides=no`). So a release binary cannot run
  the source tree or the harness bootstrap at all; only an exported pck
  runs on it. See 4f for the debug-template question.

### H25 comparison
- LEDGER H25: "Quitting during the mid-match reconnect loop crashes with
  signal 11. The game's own exit paths avoid it". exec-b runs 4 and 6
  show nobody has to quit: the first reconnect attempt crashes, within
  1 ms of the disconnect. H25 is the same crash, mis-described; its
  scope is every unexpected server loss mid-match (and pre-match, via
  `client_exit_match()`), and the fix is to defer the handling
  (`call_deferred`), as `_client_transition_to_game_over` already does.
- Verdict: Broken (Verified in editor builds, 8 of 8 clients in exec-b;
  release builds: Verified at engine level by the repro below, not run
  with the shipped game binary).

### Minimal engine repro: editor vs exported release (Verified, 4.7.2)
`h37-verify/repro/` is a three-file project on loopback ENet. The server
optionally spawns one node through a MultiplayerSpawner when the client
connects, then quits 1 s later. The client's `peer_disconnected` handler
does one of three things: `replace` assigns a new ENet client peer (what
reconnect attempt 1 does, `network_connector.gd:293`); `null` closes the
peer and sets `multiplayer_peer = null` (what `client_exit_match()` does,
`game_panel.gd:1275-1281`); `deferred` does the replace through
`call_deferred`. `repro/run.ps1` runs the editor binary with `--path`;
`repro/run-export.ps1` runs the project exported with the 4.7.2 release
template (`repro/export/`, no `--path`). Throwaway APPDATA, logs in
`repro/logs/`. Client exit codes, runs 10:58-11:02 (-1073741819 is
0xC0000005, an access violation; two runs with a mangled variant
argument are discarded):

| handler  | editor, no node | editor, 1 node | release, no node | release, 1 node |
|----------|-----------------|----------------|------------------|-----------------|
| replace  | 0, 0            | crash, crash   | crash            | crash, crash    |
| null     | 0, 0            | 0, 0           | crash            | crash, crash    |
| deferred | 0, 0            | 0, 0           | 0                | 0               |

- Every crash came after the handler printed "handler returned": the
  engine fails after the script swaps the peer during the dispatch.
- The release template crashes on ANY synchronous peer change inside
  `peer_disconnected`, replicated nodes or not. The editor binary is
  more tolerant (only replace with a spawned node crashed), so editor
  runs understate what players get. Deferring avoids it in both.
- Correction to the exec-b reading in the H25 comparison above: a
  release build needs no extra factor. Both mid-match paths crash there:
  reconnect attempt 1 (replace) and, when reconnect is not feasible or
  has failed, `client_exit_match()` (close + null), both synchronous
  inside the dispatch (`game_panel.gd:527-556`).
- The expected end-of-match path defers its cleanup and its level free
  (`game_panel.gd:1453-1464`), which is the `deferred` variant: Believed
  safe in release (Run 1 Verified it in the editor only).
- Pre-match "not enough players" (`game_session_manager.gd:600-613`):
  the client gets the shutdown RPC first and closes its own peer
  deferred (`network_connector.gd:782-806`), so whether a
  `peer_disconnected` then fires inside a dispatch was not determined.
  Not run: the harness cannot hold a match before its start.
- Only ENet was tested; WebRTC peers (cross-play) and the web build
  were not.
- Verdict: H25 is Broken in release builds. Verified at engine level
  with the same 4.7.2 release template and the same peer operations;
  not run with the shipped game binary (sandbox, above). Scope: every
  unexpected server loss mid-match (game-server crash, container
  eviction, an ENet timeout), not "quitting during the reconnect loop".

## 2. Networked pause in a release build (not run; Believed, code)
- Not run: it needs exported release clients, which cannot be sandboxed
  (section 1 "Exported release clients", and 4f).
- Code: `toggle_pause` is Escape (`project.godot`, physical keycode
  4194305) plus two gamepad buttons. Its branch in `_input`
  (`input_handler.gd:126-138`) has no `Netcode.is_debug` gate, unlike
  its neighbours (`input_handler.gd:12, 77, 88, 99, 112`); it requires
  only `G.settings.is_server_pause_enabled` (true in the shipped
  `settings.tres:154`) and an active networked level. The release
  overrides (`settings.gd:358-389`, applied whenever the binary is not
  the editor) do not touch it. The server's handler checks only the
  same setting and a 0.5 s cooldown (`frame_driver.gd:449-471`).
  exec-b Verified this path pauses everyone in an editor run.
- Verdict: Believed: in a release build, any client's Escape mid-match
  pauses the server and every other client.
## 3. Party invite is a forced join (Verified, local stack)
Run `h37-verify/item3.ps1` at 10:53 against this agent's own stack
(loopback, device auth, users A, B, C); raw responses, tokens redacted,
in `h37-verify/item3/raw.txt`.
- Step 1. A creates a closed party (`POST /v2/group`, max 4) and calls
  `party_invite` for B, who is not a friend and accepted nothing:
  `{"ok":true}`. B's own `GET /v2/user/<B>/group` immediately lists A's
  party with `state: 2` (member, not 3 = invited); A's member list shows
  B at state 2 and `edge_count: 2`. B is sent a persistent code -4
  "You've been added to group party-..." (Nakama's add notice) and a
  transient `party_state_changed` `{"event":"invited",...}` on the socket.
- Step 2. B blocks C (`POST /v2/friend/block`; B's friend list shows C at
  state 3). C creates a party and calls `party_invite` for B:
  `{"ok":true}`. B is now a state 2 member of BOTH parties, and gets a
  second persistent "added to group" notice with C as `sender_id`. The
  block is not consulted.
- Step 3. A calls `party_start_matchmaking` (`game_mode` empty):
  `{"ok":true, "game_mode":"ffa", "member_ids":[A,B], "rt_party_id":""}`.
  B's socket gets one transient notification, code 100, subject
  `party_matchmaking_start`, with the party id, leader id and matchmaker
  properties. Nothing asks B first; there is no consent or ready field.
  It is not stored (B's notification list still has only the two
  group-add notices). Per h37-social F11 (Believed, code), B's client
  then runs `client_load_game()` from wherever it is.
- Verdict: Broken. Any user can put any user id into a party, past a
  block and into two parties at once, and then pull that user into a
  match load. Confirms h37-social findings 1 and 2 at runtime.

## 4a. Can a party's creator leave, and can anything disband a party? (Verified, local stack)
Run `h37-verify/item4a.ps1` at 11:08 (users A, B, C, device auth, this
agent's stack). Raw: `h37-verify/item4a/raw.txt`. The SDK's leave and
kick are Nakama's own REST calls
(`snoringcat-platform:addons/snoringcat_platform_client/core/party_api_client.gd:124`
`leave_group_async`, `:340` `kick_group_users_async`), which is what the
script called.
- A creates a closed party; B joins by code (A superadmin, B member).
- A leaves: HTTP 400 `{"code":3,"message":"Cannot leave group when you
  are the last superadmin."}`. Members unchanged.
- A calls `party_transfer_leadership` to B: `ok`, `leader_id` B. Nakama
  roles after: A superadmin, B admin (the promotion stops at admin).
- A leaves again: the same 400. The transfer does not free the creator.
- B, now the leader, kicks A: `{}` (success), and A is still superadmin.
  The SDK emits `party_kicked` on that empty success
  (`party_api_client.gd:340-348`), so B's client is told the kick
  worked (Believed, code).
- C joins by code; A kicks C (`{}`, C gone); C rejoins with the same code
  and is a member again. A kick keeps no one out (h37-social finding 11,
  now Verified).
- B (admin) `DELETE /v2/group/{id}`: 400 "Group not found or you're not
  allowed to delete." A (creator) `DELETE`: `{}`; B's group list is then
  empty. No SDK call or client code wraps a delete (code search:
  no `delete_group` in the SDK or `src/`), and the runtime registers no
  after-hook for DeleteGroup (`snoringcat-platform:runtime/party.go:1187-1202`
  hooks AddGroupUsers, JoinGroup, LeaveGroup and KickGroupUsers only).
  The one server-side disband is account deletion:
  `runtime/account.go:408-451` deletes the creator's parties and their
  settings rows.
- Verdict: Broken. h37-social finding 3 is now Verified at runtime
  level: the creator cannot leave while anyone else is in the party, a
  transfer does not change that, a transferred leader cannot remove the
  creator (a silent no-op the client reports as success), and nothing in
  the product disbands a party short of deleting the account. The raw
  error toast on the failed leave is Believed (h37-social F8), not run.

## 4b. Over 50 stored notifications: does the client's poll ever see a newer one? (Verified, local stack)
Run `h37-verify/item4b.ps1` at 11:08. Raw: `h37-verify/item4b/raw.txt`.
- Fill: A runs 55 `party_invite` + B-leaves cycles against B in 1 s.
  Each leaves B a persistent code -4 "You've been added to group" row.
  Nothing rate-limits `party_invite` (no limit in `runtime/party.go`).
- C sends B a friend request (`POST /v2/friend`): B has 56 rows, the
  newest a code -2.
- The client's poll, `GET /v2/notification?limit=50` with no cursor (as
  `src/core/friends_notification_poller.gd:149-153` and the SDK's
  `friends_api_client.gd:252` send it), returns 50 rows, all code -4,
  the oldest 50 (18:08:45 to 18:08:46 UTC). No friend request. A second
  poll returns the same 50.
- The same call with the `cacheable_cursor` the first poll returned
  gives the 6 newer rows, the friend request among them.
- Nothing deletes notifications: no `delete_notifications` in the SDK or
  `src/`, no `NotificationsDelete` in the runtime (code search; Believed).
- Verdict: Broken. h37-social finding 4 (its F6) is Verified at runtime
  level: once a player has 50 stored notifications, the client's poll
  never returns a newer one, so friend requests that arrive while the
  player is offline stop toasting. New: any user can push any other user
  past 50 in about a second with `party_invite`, so this is a cheap
  griefing vector as well as slow drift (SP14 adds a row per match).
  Fix shape: page with `cacheable_cursor` and keep it, and delete rows
  once consumed.

## 4c. A member whose client is gone: does party_start_matchmaking wait, fail or go ahead? (Verified, local stack; client screens Believed)
Run `h37-verify/item4c.ps1` at 11:10. Raw: `h37-verify/item4c/raw.txt`.
- A, B and C in a party, all three `party_set_ready true`: three ready
  rows `{"ready": true}`.
- B's socket closes (B quits). A's member list shows B `online=False`;
  B's ready row is unchanged, still `ready: true`.
- A creates the realtime party over its socket, as the leader client
  does (`src/core/nakama_matchmaker_client.gd:196-255`), and calls
  `party_start_matchmaking`: `ok`, `member_ids` [A, B, C], `game_mode`
  ffa. It goes ahead at once; `runtime/party.go` has no presence check.
- A's socket receives nothing. C's gets the transient code 100
  `party_matchmaking_start` with the rt party id; C joins the rt party
  and A gets C's `party_presence_event`. B gets nothing, and nothing is
  stored for B (code 100 is transient).
- A sends `party_abort_matchmaking` with `members_never_joined`, which
  the leader client sends after `_PARTY_JOIN_TIMEOUT_SEC = 20.0`
  (`nakama_matchmaker_client.gd:47`, `:239-249`): `ok`. C gets the
  transient code 102 `party_matchmaking_abort` with that reason.
- B comes back: only the persistent group-add notice, and the ready row
  still says `ready: true`. A's second start goes ahead the same way,
  B still in `member_ids`.
- The client's Start gate counts non-invited members and their `ready`
  flags only (`src/core/party_manager.gd:437-449`,
  `src/ui/party/party_lobby_panel.gd:365-377`), so with B's stale
  `ready: true` Start stays enabled (Believed, code).
- Verdict: Broken. The runtime goes ahead with an absent member, the
  absent member's ready row outlives the session, and every attempt
  stalls 20 s and aborts. Other members see matchmaking start, then
  abort with `members_never_joined` (the on-screen part is Believed,
  client code). Refines h37-social finding 5: when the absent member had
  marked ready, Start does not stay disabled; it stays enabled and fails
  every time. Only a kick clears it, and a kick fails against the
  creator (4a).

## 4d. H15 end to end: after log-out, does the realtime socket stay open and keep receiving? (Verified, harness + local stack, 2 runs)
Run `h37-verify/item4d.ps1` at 11:20 and 11:22: the harness
(`run-game.ps1 -Backend http://127.0.0.1:<port> -Headless`, scenario
`h37-verify/scenarios/h37v-h15-logout.json`, editor binary) plays the
client; the script plays user A over REST. A probe-only recorder,
`h37-verify/d4/rec.gd`, is connected to the matchmaking socket's
signals and prints one line per event. Raw: `h37-verify/item4d/raw.txt`
(run 2) and `raw-run1.txt`; client logs under
`h37-verify/runs/20261014-1120*` and `-1122*`. Both runs gave the same
results.
- Player 1 signs in as a guest (`Platform.auth.login_anonymous()`) and
  calls `Platform.matchmaking.ensure_socket()`, what Quick Match and a
  party start do first. The SDK gets a guest JWT from the local stack and
  connects the matchmaking socket (user X).
- Phase 1, control: A `party_invite`s X. The socket receives 2
  notifications (code -4 group add, code 101 `party_state_changed`).
- Player 1 logs out (`G.screens.sign_out_router.log_out()`) and the
  CONSENT screen opens. Then: the JWT is empty and the notification
  socket is stopped (`notif_socket_wants=false`), but
  `Platform.matchmaking._socket` is the same object and
  `is_connected_to_host()` is true.
- Phase 2, after log-out: A invites X into a second party and calls
  `party_start_matchmaking` on it. The logged-out client's socket
  receives all 3: code -4, code 101 and the transient code 100
  `party_matchmaking_start`.
- The next player consents, signs in as a new guest (new device id) and
  calls `ensure_socket()`. It returns at once on the old socket (same
  object, still connected) and the new guest never gets a JWT of its own
  (`new_jwt_empty=true`). Phase 3: A invites X again; the socket, now
  serving player 2, receives X's code -4 and code 101.
- Phase 4 (run 2): player 2 calls `Platform.matchmaking.create_rt_party(4)`.
  A joins that realtime party; Nakama reports its leader and only other
  presence as user X, player 1's account. So player 2's party operations
  go out as player 1; tickets use the same socket (Believed, same code
  path).
- Presence in the status sense does not leak: A's member list shows X
  `online=False` before and after the log-out, because the SDK connects
  with `appear_online` false (`addons/nakama/socket/NakamaSocket.gd:317-318`
  sends `status=false`). It leaks through realtime parties instead:
  anyone who joins the party player 2 creates sees X as its leader
  (phase 4).
- Cause, code: `clear_session_state()` stops the poller and the
  notification socket (`src/core/sign_out_router.gd:94-121`, socket stop
  at 110) and never closes the matchmaking socket.
  `NakamaMatchmakerClient.cleanup()` (`src/core/nakama_matchmaker_client.gd:159-163`),
  which would call the SDK's `cleanup()` (`matchmaker_api_client.gd:262-271`,
  closes `_socket`), has no caller in `src/` (code search), and
  `ensure_socket()` reuses any connected socket without checking whose
  it is (`matchmaker_api_client.gd:287-289`).
- Verdict: Broken. H15 is Verified end to end: after log-out the
  matchmaking socket stays open as the old account, keeps receiving its
  notifications (persistent and transient), and the next player's
  realtime party is created as the old account. h37-account SO-1 (unit
  level) and AN-1b's mechanism are now Verified in a running client; the
  sign-in-over-a-guest path without a log-out (AN-1b proper) was not run
  and stays Believed. Fix shape: call the SDK's `cleanup()` from
  `clear_session_state()` and on every account change, and have
  `ensure_socket()` reconnect when the stored session's user differs
  from the socket's.

## 4e. Every client drops, the server quits 12 s later: does the runtime get match_end or a cancel, and what does the match row keep? (Verified in two halves, harness + local stack; the Edgegap restart path Believed)

**Broken, low-medium. The runtime gets neither. The match's rows stay
until something else deletes them, which on the local allocator is
never, and two of the rows are listable by any signed-in player.**

Server half (Verified, harness run `h37-verify/runs/20261014-104816-h37v-prod-quit`,
server `process.log`):
- The scenario flips the preview server to production 1 s into the
  match (eval `s_flip` = `[null,false,true,false]`), then both clients
  leave mid-match. At 32.62 s the server logs both disconnects, "All
  clients disconnected" and "Production mode: Exiting server" (log lines
  199-218), with `is_match_ended` false (eval `s_no_peers` =
  `[false,0,false]`). The process quits at 44.65 s, 12.0 s later: the
  following 25 s wait step fails with "the game quit".
- `MatchResultReporter` logs even when it has no key ("No
  NAKAMA_HTTP_KEY env var on this server. Skipping match_end RPC.",
  "Skipping match_cancel RPC: ...", `match_result_reporter.gd:52-59,
  101-110`). Neither line is in the log, so neither `report` nor
  `cancel` was called: `_server_on_all_clients_disconnected`
  (`game_session_manager.gd:541-569`) goes straight to the 12 s await
  and `get_tree().quit()`. Its comment says the wait lets "the match_end
  HTTP request" finish, but nothing sends one, and the reporter's own
  doc names "mid-match all-clients-dropped" as a `cancel` case
  (`match_result_reporter.gd:88-90`). The code and its docs disagree.
- The 12 s quit also cuts the 30 s per-player reconnect grace
  (`match_state_synchronizer.gd:24, 249-258`) short: a player whose
  connection blipped can't come back once the last peer is gone
  (Believed, code).
- Caveat: the harness server runs the preview provider, not
  `edgegap_server_provider.gd`, so its idle (`:66, 402-435`) and
  late-joiner grace (`:30, 353, 438-509`) timers didn't run. Neither
  sends anything on this path (Believed, code).

Runtime half (Verified, local stack: `h37-verify/item4e.ps1`, raw
`item4e/raw.txt`; `item4e-reg.ps1`, raw `item4e/raw-reg.txt`):
- Two device users queue with the client's ticket (`+properties.game_mode:ffa`,
  min 2, max 4, the string properties of `nakama_matchmaker_client.gd:360-391`).
  Matched in 10 s; each gets `match_ready`, code 100, persistent.
- Nobody reports. The database then holds one `match_metadata` row,
  keyed by the request id, value `{game_id, user_ids: [both players],
  allocated_at, allocator_kind: "edgegap"}`, read permission 2. It is
  unchanged 45 s later. Each player's persistent `match_ready`
  notification stays too (RT2; and 4b: those rows fill the oldest-50
  poll).
- A booting Edgegap server also writes `server_registrations` (request
  id, IP, port, FQDN). Reproduced with a server-key `register_server`
  call: `{"ok":true}`, one row, read permission 2.
- Only `match_end` and `match_cancel` delete these rows
  (`match_lifecycle.go:593-610, 726-749`; RT1, no sweeper). So the
  all-dropped match keeps both rows and the `match_ready` rows forever on
  the local Docker allocator (the container is auto-removed and nothing
  restarts it, `local_allocator.go:219`, Believed), and on Edgegap until
  a restarted container's 60 s idle timer sends `match_cancel`
  "idle_timeout" (h37-matchmaking F12). Whether Edgegap restarts an
  exited container can't be checked here: Believed.
- New: `match_cancel` for a match with no `server_registrations` row
  answers `{"noop":true,"ok":true}` and leaves `match_metadata` in place
  (Verified with the dev stack's server key; `match_lifecycle.go:694-711`).
  A server that dies before it registers, or whose registration failed,
  can't clean up its metadata even when it cancels.
- New: both collections are listable by any signed-in player. An
  unrelated device user listed `GET /v2/storage/match_metadata?user_id=<system user>`
  and got the row with both players' user ids; another listed
  `server_registrations` and got the server's IP, port, FQDN and request
  id. The writes set PermissionRead 2 (`fleet_allocator.go:1149, 1174`,
  `match_lifecycle.go:177`), and no client code reads either collection
  (only `match_result_reporter.gd` comments and two compliance-test
  comments mention them). In production this would let a guest
  enumerate live game servers and the co-play history (who matched
  whom, when) of every live or leaked match. Production was not
  checked.
- Fix shape: call `G.match_result_reporter.cancel(request_id,
  "all_clients_dropped")` before the quit, and quit after the reconnect
  grace rather than 12 s; have `match_cancel` delete `match_metadata`
  even without a registration; add RT1's sweep; write the three
  collections with PermissionRead 0.

## 4f. Item 2 without an exported release client: what blocks the sandbox, and is a debug export a fair stand-in for the pause question? (blockers Verified; pause not run)

**Answer: no exported binary can be sandboxed with the shipped 4.7.2
templates, debug or release, so the pause run was not done. A debug
build would be a fair stand-in for the pause logic, but not for crash
behaviour: it hides the H25 crash completely.**

What blocks it (Verified unless marked; scripts and output in
`h37-verify/f4/` and `h37-verify/reltpl/`):
- The official templates, debug and release alike, are built without
  path overrides. `--path` and `--main-pack` abort with exit 1 ("this
  Godot binary was compiled without support for path overrides", from
  `main/main.cpp:1782` and `:1892`; it takes a build with
  `disable_path_overrides=no`). A `project.godot` in the working
  directory is refused with a blocking error dialog: the headless run
  hung until killed. `-s <script>` is silently ignored: a debug export
  given `-s f4/hello.gd` ran its own main scene and never printed the
  script's line (`f4/dbg-export-s.out.txt`). So there is no command-line
  way to put `agent_bootstrap.gd` into an exported process.
- `scripts/.gdignore` keeps the bootstrap and the driver out of every
  pck (section 1, export.log).
- The sandbox lives in the driver (URL blackhole and `-Backend`
  override, `agent_driver.gd:16-21, 199-204, 575-594`). Without it an
  export boots against the production URLs. The shipped client reads no
  environment variable that could point it at loopback: the only
  `OS.get_environment` reads in `src/` and the SDK addon are server-side
  (`NAKAMA_URL`, `NAKAMA_HTTP_KEY`, `ARBITRIUM_*`,
  `EXPECTED_SESSION_IDS`) or match prefs (Believed, grep). A throwaway
  APPDATA alone is not a sandbox, so per the brief nothing was run.
- Even with the driver in place, a non-editor binary is never preview
  (`network_orchestrator.gd:184-196`). Its clients take the real
  sign-in and matchmaking path, and every headless process becomes a
  server (`is_server = is_headless or args.has("server")`), so the
  harness's preview `match` mode can't be reused. A run needs windowed
  clients, the local stack's matchmaker and a server on
  `127.0.0.1:14433` (exec-b's section 4 recipe).

Is a debug export a fair stand-in?
- For the pause logic, yes (Believed, code). The `toggle_pause` branch
  has no `Netcode.is_debug` gate (`input_handler.gd:126-140`; the gated
  neighbours return only inside their own branches). The release
  overrides skip only the editor (`settings.gd:359`), so they apply in a
  debug template too. The server checks only the setting and a cooldown
  (`frame_driver.gd:449-471`). The one thing `OS.is_debug_build()`
  changes is `Netcode.is_debug` (`network_orchestrator.gd:188`), which
  the pause path doesn't read.
- For crash behaviour, no (Verified). Item 1's engine repro on the debug
  template (`repro/run-dbg-export.ps1`, logs `repro/logs/dbgexport-*`):
  0 crashes in 6 cells (replace, null, deferred, each with no node and
  with a replicated node; one run each). On the release template 4 of
  the 6 cells crash, and in the editor 1. A debug export would show H25
  as fixed when it is not. Of the three binaries, only release crashes
  on every synchronous peer change.

Ways to unblock, for whoever picks it up:
- Build a 4.7.2 template with `disable_path_overrides=no` (the debug
  target is enough for pause; release for crashes), then run
  `run-game.ps1 -Godot <its console exe>` on the source tree under the
  full driver sandbox. This changes nothing shipped.
- Add a published-mode recipe to the harness (windowed clients, the
  local stack's matchmaker, a server on the mock-deploy port), which any
  non-editor run needs anyway.
- An "agent" export preset carrying the harness would need the driver
  outside the `.gdignore`d directory and the blackhole compiled in. It
  touches shipped code, so it is the least attractive.

## Minor notes (Believed, code)
- `snoringcat-platform:addons/snoringcat_platform_client/test/compliance/test_party_invite_flow.gd:136-140`
  passes when the invitee lands at state 2, a member who agreed to
  nothing, so the compliance suite accepts item 3's forced join instead
  of catching it.
- `test_party_to_matchmaking.gd:65-67` and `test_friends_block.gd:77-79`
  (same directory) say hard-deleting the test users cleans up their
  `match_metadata` and `synthetic_matches` rows. Those rows belong to the
  system user, and nothing in `runtime/account*.go` touches the three
  match collections (grep), so a test match that allocates leaves its
  rows behind (4e).

## Summary, ranked
1. H25 (items 1 and 4f). Broken. A release client crashes on any
   synchronous peer change inside `peer_disconnected`, which both
   unexpected-disconnect paths make (reconnect attempt 1 mid-match,
   `client_exit_match()` otherwise). Verified at engine level with the
   4.7.2 release template (4 of 6 cells crash; editor 1, debug template
   0); not run with the shipped game binary. Fix: defer both.
2. 4e. Broken. `match_metadata` (both players' user ids) and
   `server_registrations` (server IP, port, FQDN) are listable by any
   signed-in player. Verified on the local stack; production not checked.
3. 4d (H15). Broken. After log-out the matchmaking socket stays open as
   the old account and keeps receiving its notifications, and the next
   player's realtime party is created as the old account. Verified end
   to end (harness + local stack, 2 runs).
4. Item 2. Believed (code): in a release build any client's Escape
   pauses the server and every other client. Not run: exports can't be
   sandboxed (4f).
5. Item 3. Broken, Verified: a party invite is a forced join, past a
   block and into two parties at once, and the leader can then start
   matchmaking for the invitee without asking (the invitee's load is
   Believed).
6. 4b. Broken, Verified: the client's notification poll returns the
   oldest 50 rows forever, and `party_invite` (no rate limit) fills them
   in about a second.
7. 4c. Broken, Verified at runtime: party matchmaking starts with an
   absent member, whose ready row outlives the session. The leader
   client then waits 20 s and aborts, and the stale ready row keeps
   Start enabled (both Believed, code).
8. 4a. Broken, Verified at runtime: the creator cannot leave while
   anyone else is in the party, a transfer doesn't help, kicking the
   creator is a silent no-op reported as success, nothing in the product
   disbands a party short of deleting the account, and a kicked member
   rejoins with the same code.
9. 4e. Broken (low-medium), Verified in two halves: when every client
   drops, the production server quits 12 s later without `match_end` or
   `match_cancel`, so the match rows stay; `match_cancel` without a
   registration is a no-op. The Edgegap restart path is Believed.
10. Item 0. Broken, latent: the local allocator's port pool leaks; about
    4 months without a runtime deploy exhausts it.

Done 11:46