# H37 exec-b: harness and end-to-end probes

Started 2026-10-14 09:34:16 -07:00. Repos at: hopnbop 44f0093e,
platform 8e85e8a, netcode 7d6ebd9.

Question answered here: can Claude run the real game end to end, start a
match, and open and use the settings menu? Answered with runs, not code
reading. Run dirs, scenarios and logs: `.claude/probes/H37/h37-exec-b/`.

## 1. Settings menu, driven by player inputs (probe a): works

**Verified.** Scenario `h37-exec-b/scenarios/h37-settings-menu.json`, run
`h37-exec-b/runs/20261014-094233-h37-settings-menu`: PASS, 77/77 steps,
0 errors, first try.

- From the lobby, `W` joins a bunny. Holding `A` walks it into the
  hidden cave (x about -166), and the SettingsBook opens the side panel.
  That is the player's route: no `call` step, no `_show_settings_ui`
  shortcut (the committed `export-data-offline` scenario uses one).
- In the main menu, `S` x4 focuses "Settings" and `D` (Right) opens it.
  `S` x2 then focuses Gore, and `Space` turns it on. `S` x10 more
  focuses Music, and `Space` unmutes it. `S` focuses SFX, and `Space`
  unmutes it.
- The change takes effect. `G.settings` flips, and so does the engine
  state: audio bus 2 (SFX) goes from muted to unmuted, read via
  `Engine.get_singleton('AudioServer').is_bus_mute(2)`.
- `A` pops back to the main menu, and `A` again closes the panel.
  Closing saves (`side_panel_manager.gd` `close_all`). The sandbox's
  `local_settings.cfg` then holds `is_gore_enabled=true`,
  `mute_music=false` and `mute_sfx=false`.
- Every step is checked by an `assert` on the focused row's
  `_setting_key` or label, so a moved row fails loudly. The labels read
  from the panel were Account, Friends, Party, Settings, Levels,
  Leaderboard, My Stats, Info, Quit.
- Screenshots `01-joined` .. `05-closed` show the panel. `04-toggled`
  shows Gore, Music and SFX checked.

**Survives a restart: Verified, but only by working around the harness.**
`h37-exec-b/relaunch.ps1` relaunched Godot with run-game.ps1's arguments
(run-game.ps1:386-419) and the first run's sandbox as `APPDATA`.
Scenario `h37-settings-after-restart.json`, output
`runs/20261014-094233-h37-settings-menu/client1-restart`: AGENT_RESULT
ok, 27/27 steps.
- After the restart, gore is on and music and SFX are unmuted, with the
  SFX bus unmuted. The reopened panel's toggle rows show the persisted
  values.
- This holds even though the driver forces `mute_music` and `mute_sfx`
  to true in memory. `configure()` runs before `G._ready`
  (agent_driver.gd:186-213), and `G._ready` then loads and applies
  `user://local_settings.cfg` (global.gd:341-343), so the stored value
  wins.
- **Harness gap:** run-game.ps1 always makes a fresh
  `<run>/<proc>/appdata` (run-game.ps1:377-379). It has no flag to reuse
  a sandbox and no restart step, so persistence across restarts can't be
  tested without hand-rolling the launch. The fix is a `-ReuseSandbox
  <run dir>` flag, or a scenario-level `restart` step that relaunches the
  process with the same `APPDATA`.

**There is no volume control in the game.**
- Verified, on screen: the settings panel's rows are Language, Gore,
  Critters, Cheats (6 sub-rows), Full Screen, Music, SFX and Offline
  Mode (`settings_panel` eval).
- Believed, from code: Music and SFX are mute toggles
  (`settings_panel.gd:115-123`), and `LocalSettings.OVERRIDABLE_KEYS`
  has no volume key (`local_settings.gd:40-54`). `audio_main.gd` sets
  fixed `volume_db` values.
- So "change a volume" was done as the Music and SFX mute toggles.

**Minor (Believed, code only).** `LocalSettings.set_override` compares
the new value with the live `G.settings`, which it has just mutated
itself (`local_settings.gd:136-149`). Toggling a setting back to its
resource default therefore stores the default as an override instead of
clearing it. The file is not kept minimal, contrary to the class doc, and
a user who ever toggled a setting keeps that value even if a release
changes the default.

## 2. Committed scenarios without a backend

Run through `h37-exec-b/run-scenarios.ps1`, which wraps run-game.ps1
and re-runs a failure once. Raw lines: `h37-exec-b/results.md`; run dirs:
`h37-exec-b/runs/20261014-<time>-<name>`. Other audit agents were
running GUT and imports at the same time, so timings are under load.

| Scenario | AGENT_RESULT | Run time |
|---|---|---|
| lobby | ok, 8/8 | 093902 |
| offline-move-jump | ok, 20/20 | 093916 |
| sign-out-lobby | ok, 13/13 | 093930 |
| sign-out-local-match | **fail twice**, 8/17 | 093940, 094033 |
| sign-out-play-again | **fail twice**, 5/13 | 094126, 094217 |
| session-kept-offline | ok, 11/11 | 094308 |
| session-refresh-before-match | ok, 19/19 | 094326 |
| export-data-offline | ok, 16/16 | 094346 |
| consent-kept-after-sign-out | ok, 21/21 | 094406 |
| i18n-party-strings | ok, 83/83 | 094415 |
| log-out-sign-in-cycles | ok, 33/33 | 094432 |

`match-2-clients` (starts a server) and `leaderboard-local-backend`
(needs `-Backend`) are in section 3.

**Two deterministic failures. Root cause Verified: the committed match
is now 180 s.**
- Both fail the same way: `wait_until: timed out after 40.0s waiting
  for screen() == 'GAME_OVER'`, on both attempts. So they are broken,
  not flaky.
- `88e3089b` ("Update settings", 2026-10-14 00:27) changed the
  committed `settings.tres`: `match_duration_sec` 10.0 to 180.0, and
  `level_override_for_preview` 0 to 4.
- The harness always starts from `HEAD:settings.tres`. These two
  scenarios set no match length, so they relied on the 10 s match that
  `scripts/agent/README.md:37-38` still promises ("the committed match
  is 10 s"). That README line is now false.
- Test: copies that differ only by `"settings": {"match_duration_sec":
  10}` (`h37-exec-b/scenarios/sign-out-*-10s.json`) PASS on the first
  try: 17/17 and 13/13, about 21 s each (runs `094420`, `094448`).
- Fix: every scenario that needs a match to end sets
  `match_duration_sec` itself, and the README line goes. Reverting
  settings.tres would only hide the coupling until the next tune.

**ERROR lines on passing runs: known noise, not failures.** Every
local-mode run logs `RPC '_server_rpc_ping' on yourself is not allowed
by selected mode` (6 to 19 times, growing with run length) and one
`_rpc_init`. offline-move-jump adds `_rpc_server_update_critter_stats`.
README:107-109 already says local mode logs known RPC errors.

## 3. Local backend stack, match-2-clients, leaderboard

Taken under `net.lock` from 09:51. Raw lines: `h37-exec-b/results-net.md`.
Its "exit=1 0s NO SUMMARY" line is a bug in my wrapper script (it passed
`-Backend` as one string), not a harness failure.

**A local Nakama stack without `--import`: works (Verified).**
- `h37-exec-b/stack.ps1 -Action Up` follows `infra/dev/README.md`
  "Manual usage" (66-104). It builds the runtime plugin with
  `heroiclabs/nakama-pluginbuilder:3.25.0` and brings up
  `infra/dev/docker-compose.dev.yml` as compose project `h37execb` on
  three free loopback ports. Then it waits for `/healthcheck` and
  registers `game.yaml` with `sync-game-config.ps1 -NakamaHost
  http://127.0.0.1:<port>`.
- Up in 31 s. Sync exit 0, protocol_version 2, display_version 0.54.0.
  Teardown: `stack.ps1 -Action Down` (compose `down -v`).
- **Harness gap.** The harness README points at
  `scripts/local-smoke-test.ps1 -KeepStack` for a stack
  (README:95-97). That script re-copies the addon (309) and runs
  `--import` (411) before anything else, then runs the whole
  compliance suite. No committed script brings up only the stack.
  `stack.ps1` is about 90 lines and would make a `scripts/dev-stack.ps1`.
- **Care point (Believed, code).** `sync-game-config.ps1` defaults
  `-NakamaHost` to production (50) and its keys to `$env:NAKAMA_HTTP_KEY`
  and `$env:GAME_ADMIN_KEY` (51, 55). Registering a local stack must
  always name the loopback host. A shell that has production keys in
  its environment would otherwise re-register production from the
  working tree.

**`match-2-clients`: PASS** (run `095201`, 28 s): server 5/5, client1
8/8, client2 ok. It is a direct ENet preview match on a free port and
never touches Nakama (section 4).
- **LEDGER H26 is the normal path, not a hot-reload edge case.** The
  server spawns `level_4`, then logs "Hot-reloading settings and level
  for preview mode" and respawns it. `_server_preview_hot_reload`
  (`game_panel.gd:1904-1911`) runs before every preview countdown. The
  respawned level gets an auto-generated name: the server logs
  `Unable to auto-spawn node with reserved name: @Node2D@39` (3x). Then
  client1 logs 39 errors and client2 36: `Node not found:
  .../Levels/@Node2D@40/Objects/Snail_0`, `Invalid packet received`,
  `Parameter "spawner" is null`. H26 says this happens "after a preview
  server hot-reload". In fact it hits every 2-client harness match.
  The log is Verified; the cause chain is Believed.

**`leaderboard-local-backend`: FAIL twice** (runs `095246`, `095255`),
with `-Backend http://127.0.0.1:<stack port>`.
- The backend path works (Verified): the screen loaded the stack's
  public leaderboard route and rendered "No scores yet".
- The two failed asserts are step 10 (`%StatusLabel` hidden) and step
  11 (`%ContentContainer` has rows). Both expect recorded scores. A
  fresh stack has none, and the harness has no step that seeds them.
  The scenario's own comment says it needs a stack that
  `local-smoke-test.ps1 -KeepStack` left up, so only the compliance
  suite's leftovers can make it pass. A `seed` step, or a fixture RPC
  call in the scenario, would make it self-contained.
- **`ui_labels()` returns translation keys** for auto-translated
  labels: "LEADERBOARD.PLAYER", "LEADERBOARD.BEST_SCORE" and
  "SETTINGS.BACK", while `client1/leaderboard.png` shows "Player" and
  "Back" (Verified). An assert on visible text has to compare with
  `tr(...)`, as step 12 does.

## 4. Matchmaking end to end against the local stack (probe b)

**Answer: yes, for one full online match that the player starts by
walking into the rabbit hole, through the real Nakama matchmaker, the
allocator (mock deploy) and connect. Play again re-matchmakes and
reconnects. Two things break: the second match on the same preview
server shows no bunnies, and a server that leaves mid-match, in the
first match or the second, by quitting or by a hard kill, crashes both
clients (signal 11, 4 of 4 runs, 8 of 8 clients).**

**Recipe (Verified by the runs below).** `run-game.ps1 -Scenario <match
mode, 2 clients> -Port 14433 -Backend http://127.0.0.1:<stack port>
-AllowNetwork`, with client process settings
`preview_connect_to_remote_server: true` and, to start in the lobby,
`start_in_game: false`. Why each piece:
- `-Port 14433`: the dev stack runs `EDGEGAP_MOCK_DEPLOY=true`
  (`infra/dev/docker-compose.dev.yml:13`), so every allocation answers
  `127.0.0.1:14433`, and the harness's preview server must listen there.
  One such match per machine at a time.
- `preview_connect_to_remote_server: true` makes the session provider
  `res://src/core/nakama_matchmaker_client.gd` (eval `provider`) instead
  of the direct preview connection.
- `-AllowNetwork`: the driver refuses that setting without it
  (`agent_driver.gd:669-674`), even when `-Backend` is loopback. The
  wrapper then warns "this run may talk to production", although
  `-Backend` blackholes the other backend URLs (`agent_driver.gd:199-204,
  575-594`). Every connection in the logs went to the stack or
  127.0.0.1; that nothing else was reached is Believed, from code. Fix:
  accept the setting without `-AllowNetwork` when `-Backend` is loopback.

**Run 2, the player's route** (`runs/20261014-100556-h37-mm-e2e-lobby`,
scenario `h37-mm-e2e-lobby.json`; times are client1's seconds since
launch):
- 0.6 LOBBY. 4.3 `W` joins a bunny. `D` held with three `Space` jumps:
  at 6.2 the bunny drops into the rabbit hole. The lobby despawns, LOBBY
  to LOADING, toast "Playing online. Change in Settings.", `Joining
  matchmaker query=+properties.game_mode:ffa min=2 max=4`, ticket.
  Asserted on both clients.
- The stack logs `matchmaker matched 2 players, allocating game-server`
  and `EDGEGAP_MOCK_DEPLOY=true: synthesized request_id=mock-...` once
  client2's ticket is in.
- 48.4 `match_ready 127.0.0.1:14433`, `Connected to server`, level_4
  spawned, LOADING to GAME. At 51.5 both clients see players 1 and 2;
  `local_player() != null` and `match_state.players_by_id.size() == 2`
  pass.
- 66.5 the 10 s match ends: GAME to GAME_OVER. The preview server then
  drops both clients and resets ("All clients disconnected", "Resetting
  server for new match").
- 68.1 Play again, by `eval G.game_panel.client_play_again()` (not by
  keys on the Game Over screen): GAME_OVER to LOADING, toast, a new
  ticket. 78.4 second `match_ready` (10 s later), connected, level
  spawned.
- **Second match: neither client gets a bunny (Verified, both
  clients).** The server has both players (state `second_ended`: players
  1 and 2). It logs `Unable to auto-spawn node with reserved name:
  @CharacterBody2D@339` (and @341, @342) for every player it spawns,
  plus `@Node2D@334` and `@Node2D@340` for the level. The clients never
  log `Received assigned player IDs` or `Session established` this time
  (they did at 48.5). They log `Node not found:
  .../Levels/Level4/Players/@CharacterBody2D@34x/StateFromServer` and
  about 400 `Ignoring sync data from non-authority or for missing node`
  each (server: 818). The match still runs its 10 s and ends on
  GAME_OVER at 96.4.
- AGENT_RESULT: server ok 12/12. Both clients fail step 36
  (`player_count() == 2`); all 41 steps ran. My snapshot was at the
  second match's frame 1, but the logs show the bunnies never arrived.
- Cause (Believed, code): LEDGER H26 reaching the players. On a preview
  server a round's setup runs more than once: the server logs `Spawning 1
  player(s) for peer X` two to four times per peer, and `Hot-reloading
  settings and level for preview mode` (`game_panel.gd:1904-1911`). A
  node added while the old `Level4` or `Player_1` is still in the tree
  gets an `@Type@N` name, and MultiplayerSpawner refuses to replicate
  it. In the first round only the extra copies got such names; in the
  second, every player did. Only preview servers take this path
  (`_server_on_preview_peer_connected`, `game_panel.gd:1993-2003`).
  A production server never hosts a second match (Believed, code): with
  no clients left it logs "Production mode: Exiting server", waits 12 s
  and quits (`game_session_manager.gd:554-569`). So this blocks preview
  and harness play-again tests, not players.

**Client crash when the server leaves mid-match (Verified, 4 of 4
runs, 8 of 8 clients).** Scenario `h37-mm-e2e.json` (runs 1 and 3,
`20261014-100142-h37-mm-e2e`, `20261014-101123-h37-mm-e2e`): the
preview auto-start sends the clients straight to matchmaking; the
server's steps end at the second round's first connect, and the driver
then quits it. Scenario `h37-mm-drop.json` (run 4): the server quits 3 s
into the first match. In all three runs both clients exit -1073741819
(0xC0000005) with `CrashHandlerException: Program crashed with signal
11` and no AGENT_RESULT.
- Run 3: `Unexpected disconnect: CONNECTION_LOST`, then `Mid-match
  disconnect; starting reconnect loop` (`game_panel.gd:532-538`), then
  `Server disconnected in preview mode` (`network_connector.gd:369`),
  then the crash, all within 1 ms.
- Run 1: the client was still loading, so `_on_connection_lost` took
  `client_exit_match()` (`game_panel.gd:556`): LOBBY, "Restoring 1
  player(s) from previous match" (`lobby_level.gd:508`), 4x `No
  multiplayer peer is assigned` from `player_input_from_client.gd:86-134`
  via `lobby_level.gd:269`, `Server disconnected in preview mode`, crash.
- Run 4 (`20261014-101410-h37-mm-drop`, 59.3 s; server PASS 4/4): the
  server quits 3 s into the FIRST match. Both clients, at frame 362:
  `Unexpected disconnect: CONNECTION_LOST`, `Mid-match disconnect;
  starting reconnect loop`, `Reconnect attempt 1 (elapsed=0.0s)`,
  `Server disconnected in preview mode`, signal 11. So the crash does
  not need the broken second-match state: any mid-match server loss
  that arrives as a disconnect takes the clients down.
- Run 6 (`20261014-102135-h37-mm-kill`, scenario `h37-mm-kill.json`,
  driver `kill-run.ps1`): the server process is killed
  (`Stop-Process -Force`) 3 s into the first match, so no disconnect
  packet is sent, as in a server crash, a container stop or a network
  drop. Both clients log `CONNECTION_LOST`, `Mid-match disconnect;
  starting reconnect loop`, `Reconnect attempt 1 (elapsed=0.0s)`, then
  signal 11, exit -1073741819; the wrapper saw both exits within 10 s
  of the kill.
- Players are likely affected (Believed, code): nothing on this path is
  preview-only. `_on_connection_lost` has no preview check
  (`game_panel.gd:491-556`), `can_attempt_reconnect()` needs only the
  server's ip and port (`reconnect_handler.gd:118-121`), and the
  preview branch at `network_connector.gd:365-371` is a log line. So the
  reconnect loop, which exists for network blips, would crash a release
  client on its first attempt. Not checked in an exported build.
- Common factor (Believed, code): both paths handle the disconnect
  synchronously inside the engine's `peer_disconnected` callback
  (`disconnected.emit`, rollback_netcode `core/network_connector.gd:363`)
  and tear down or replace the multiplayer peer there. In the reconnect
  path, `reconnect_handler.start()` calls `_attempt_reconnect()` at once
  (`src/core/reconnect_handler.gd:137`), which calls
  `client_connect_to_server` (`:193`), which assigns a new
  `multiplayer.multiplayer_peer` (`network_connector.gd:293`) while the
  old peer is still dispatching its event; the log line at
  `network_connector.gd:369` prints after the reconnect attempt, and the
  crash follows as the callback returns. Deferring that handling
  (`call_deferred`) is the likely fix. LEDGER H25 (signal 11 on quit
  during the reconnect loop) may be this same crash.
- The expected disconnect at the end of match 1
  (`_client_transition_to_game_over`) never crashed.

**Harness gaps on this path.**
- Client2 starts 30 s late in every matchmaker run. The wrapper waits up
  to 30 s for client1's `Connected to server` before starting client2
  (`run-game.ps1:441-462`), which can't happen until client2 has joined
  the matchmaker. Run 2: client1 ran 98 s, client2 66 s.
- At most 2 clients, and only in match mode (`run-game.ps1:315`); lobby
  mode runs one. A 3- or 4-player match (`game.yaml` max 4) can't be
  tested.
- The dev stack has no geoip sidecar: each allocation logs two `geoip
  sidecar lookup ... failed` lines (about 250 ms each) before falling
  back. Harmless.
- WebRTC (cross-play) can't be tested: the dev stack has no signaling
  proxy, and the payload's `signaling_url` points at `wss://dev.invalid/`
  (Verified in the client log).
- A real allocation instead of the mock would need the local allocator
  path (docker socket, `LOCAL_*` env, a current game-server image). Not
  tried.
- Screenshots taken during the 0.7 s ScreenTransition are black (run 1
  `03-game-over.png`): wait 1 to 1.5 s after a screen change.

**Parties: a harness client can't form one (Verified, run 5).** Run
`20261014-101718-h37-party-guest` (scenario `h37-party-guest.json`,
lobby mode, `-Backend` the stack, PASS 7/7): the token store holds no
session (`is_anonymous` false, `is_token_valid()` false,
`build_session_from_store()` null). `G.party_manager.create_party()`
then does nothing visible: 4 s later `is_in_party()` is false, with no
log line or toast. Why (Believed, code): `create_party` needs a stored
session (snoringcat-platform
`addons/snoringcat_platform_client/core/party_api_client.gd:61`,
`_ensure_session` at 603-606, which emits "Not authenticated"). The
client has two sign-ins: `login_with_provider` (`auth_api_client.gd:258`,
OAuth in a browser, blackholed in the harness) and `login_anonymous`
(`:300`), a local identity that gets no JWT until matchmaking. Joining
also needs the 6-character invite code the runtime generates
(`party.go:2129-2229`, `join_party_by_code`, `party_manager.gd:544`) or
the other player's id, and each process knows only its own: the harness
has no cross-process channel. What it would take: (1) a dev-only,
loopback-only sign-in that stores a real session from the local stack;
(2) a step pair such as `publish` (write an expression's value to the
run dir) and `wait_shared` (read it), so client1 creates the party and
publishes the code and client2 joins with it. Run 2's layout (match
mode, 2 clients, `start_in_game: false`) already gives two lobby
clients, so the party-matchmaking path (`pending_party_match_context`)
would follow from there.

## 5. Networked pause in a match (coordinator's extra check)

**Broken, as h37-triage believed: any player's Escape freezes the
match for everyone (Verified, on the harness's debug path), and a
release export should behave the same (Believed, code).**

Run `20261014-102607-h37-pause` (scenario `h37-pause.json`: a copy of
`match-2-clients` with pause steps; server and 2 clients, direct
preview connection, no backend). PASS: server 12/12, client1 18/18,
client2 15/15. Times are seconds after each process's match start.
- Client1's eval `c1_gates`: `is_server_pause_enabled` true,
  `max_pauses_per_client` 1, `max_pause_duration_sec` 60,
  `Netcode.is_debug` true, `OS.has_feature("editor")` true,
  `OS.is_debug_build()` true, `G.is_networked_level_active` true.
- About 2 s: client1 taps Escape at frame 300 (`Requesting server
  PAUSE`). The server logs `Server paused at frame 303 by peer
  <client1>`. Both clients switch GAME to PAUSE and log `Client
  synchronized pause at frame 303`. The server's eval shows paused,
  frame 303, `pauses_used_by_peer` {client1: 1}. Client2's frame index
  stays at 303 across 2 s of evals, so the match is frozen for everyone.
  Screenshots: `client1/c1-paused.png`, `client2/c2-paused.png`.
- About 5.5 s: client2 taps Escape. The server refuses: `Client
  <client2> requested unpause, but only initiator (peer <client1>) can
  unpause` (rollback_netcode `core/frame_driver.gd:510-518`). The match
  stays paused.
- About 9 s: client1 taps Escape and the match resumes (server frame
  412 by 11.5 s).
- About 11 s: client1's second pause is refused by the game validator,
  which allows one pause per player (`game_panel.gd:1847-1860`).
- Not observed: the 60 s auto-unpause (`max_pause_duration_sec`,
  `frame_driver.gd:664-671`). Believed, from code.

So in a public match each player can freeze everyone once, for up to
60 s, and only that player can end it early: up to four freezes in a
4-player match. The match clock counts frames, so a pause also
lengthens the match (Believed).

**The harness runs the debug path.** It runs the editor binary, so
`OS.has_feature("editor")` is true (eval above), and
`apply_release_overrides()` returns before `_apply_release_values()`
(`settings.gd:358-361`). Runs use `HEAD:settings.tres` as committed
(`scripts/agent/README.md:43-44`).

**An `--export-release` build should pause the same way (Believed,
code).**
- `_apply_release_values()` (`settings.gd:385-389`) sets only
  `match_duration_sec`, `show_hud`, `show_player_overhead_labels` and
  `skip_splash`.
- `is_server_pause_enabled = true` comes from `settings.tres:154` in
  every build. Its default is false (`network_settings.gd:99`).
- The Escape branch (`input_handler.gd:126-138`) has no
  `Netcode.is_debug` check. The five debug hotkeys before it all have
  one (lines 11-13, 76-78, 87-89, 98-100, 111-113).
- The server's validator checks only match end and the per-player
  limit (`game_panel.gd:1838-1866`).
- `settings.tres:155` also sets `pause_request_cooldown_sec = 0.5`
  (default 30).

Not run in an export: building one needs an import and an export,
which this audit leaves to h37-exec-a.

**Two small bugs seen on the way (Verified, server log).**
- **Refused pause logs an ERROR.** A limit refusal logs `ERROR: String
  formatting error: not all arguments converted during string
  formatting` from `game_panel.gd:1854`, then prints `Client %d pause
  rejected: limit reached (%d/%d)` unformatted.
  - Cause (Believed): `%` binds tighter than `+`, so only the second
    string is formatted (`"Client %d pause rejected:" + " limit reached
    (%d/%d)" % [...]`).
  - The same pattern is at 1840-1842 ("match has ended").
- **Pause stats are always 0.** After a 7 s pause the server logs
  `Server unpaused at frame 303 (paused for 0 frames, cumulative: 0)`.
  The frame index doesn't advance while paused, so the pause-duration
  stats (`frame_driver.gd:711-712`) are always 0.

## 6. Capability table (probe c)

| Capability | Verdict | Evidence |
|---|---|---|
| Launch the real game (server + clients) | Yes | every run; `run-game.ps1` sandboxes each process |
| Drive a player by keys (move, jump, menus) | Yes, keyboard only | offline-move-jump 20/20; run 2 walks a bunny into the rabbit hole; the driver sends `InputEventKey` only (`agent_driver.gd:979-984`) |
| Open and use the settings menu | Yes | h37-settings-menu 77/77 (section 1) |
| Settings persist across a restart | Partly | h37-settings-after-restart 27/27, but by a hand-rolled relaunch on the same sandbox; no restart step |
| Read UI and game state | Yes, one gap | `state`, `eval`, `screen()`; `ui_labels` returns translation keys, not shown text |
| Screenshots | Yes | windowed runs; black during the 0.7 s screen transition |
| Start a match (direct preview) | Yes | match-2-clients PASS, h37-pause PASS |
| Matchmaking end to end, local Nakama | Yes, first match | runs 2 to 6 (section 4 recipe); `-AllowNetwork` needed even for loopback; second preview match has no bunnies (H26) |
| Play again / second match | Runs, broken | run 2: no bunnies; runs 1 and 3: crash |
| Server loss mid-match | Runs, clients crash | runs 1, 3, 4, 6 |
| Networked pause | Yes | run 7, section 5 |
| Local backend | Partly | works through my `h37-exec-b/stack.ps1` (docker compose on `infra/dev/`); no committed up-only script (`local-smoke-test.ps1` builds, tests and tears down) |
| Seeded backend data (leaderboard) | No | leaderboard-local-backend FAIL x2: no scores, no seed step |
| Parties | No | run 5: no session; no cross-process channel |
| 3 or 4 players, or 2+ lobby clients | No | match mode caps at 2 clients (`run-game.ps1:315`), lobby mode runs 1; `start_in_game: false` gives 2 lobby clients in match mode |
| Gamepad input | No | `agent_driver.gd:979-984` |
| Web build, WebRTC cross-play | No | no web harness; dev stack has no signaling proxy (`wss://dev.invalid/`) |
| Real game-server allocation | Not tried | mock deploy only (`EDGEGAP_MOCK_DEPLOY=true`) |

## 7. AGENT_RESULT, probe runs (sections 1 to 3 hold the rest)

| Run | Scenario | Result |
|---|---|---|
| 1 `100142` | h37-mm-e2e | FAIL: server PASS 9/9; both clients signal 11 entering match 2 |
| 2 `100556` | h37-mm-e2e-lobby | FAIL: server ok 12/12; clients ran 41/41, step 36 failed (no bunnies in match 2) |
| 3 `101123` | h37-mm-e2e | FAIL: server PASS 9/9; both clients signal 11 in match 2 |
| 4 `101410` | h37-mm-drop | FAIL: server PASS 4/4; both clients signal 11 in match 1 |
| 5 `101718` | h37-party-guest | PASS 7/7 (finding: no session, no party) |
| 6 `102135` | h37-mm-kill | FAIL: server killed by design; both clients signal 11 |
| 7 `102607` | h37-pause | PASS: 12/12, 18/18, 15/15 |


Teardown: stack `h37execb` down with its volumes, no Godot process of mine left, ports 56191, 14433 and 14435 free, `net.lock` deleted.

Done 2026-10-14 10:29:30 -07:00
