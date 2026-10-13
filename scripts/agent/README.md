# Agent harness reference

Full reference for `scripts/agent/run-game.ps1`, moved verbatim from
CLAUDE.md by H34 (2026-10-13). CLAUDE.md keeps the summary; this file
holds every flag, step, and expression.

`scripts/agent/run-game.ps1` runs the game for an agent (or you): it
launches one or more Godot processes, drives them with scripted key
presses, and collects logs, screenshots, state snapshots, and a
pass/fail verdict in one run directory. Use it to see a change
working instead of hand-rolling `-s` bootstraps.

```powershell
scripts/agent/run-game.ps1 -Scenario offline-move-jump  # scenarios/*.json
scripts/agent/run-game.ps1 -Mode lobby                  # default steps
scripts/agent/run-game.ps1 -Mode level -Level level_2 -Headless
scripts/agent/run-game.ps1 -Scenario match-2-clients    # server + 2 clients
```

Flags: `-Headless` (no windows, so no screenshots), `-Visible`
(windows on the primary screen; the default is off-screen at
x=20000, which still renders), `-Steps '<json array>'`, `-TimeoutSec`,
`-Seed <int|none>`, `-UseWorkingSettings`, `-OutDir` (default
`$env:TEMP\hopnbop-agent-runs`), `-Import` (re-import first), `-Json`
(print only the summary), `-AllowNetwork`, `-Backend <url>` (see
"Prod safety").

**Modes.** `offline`: one local-mode process (`--client=1`, running
client and server logic). `level`: offline with a required `level`.
`lobby`: the lobby screen, nobody joined. `match`: a headless preview
server plus 1-2 clients on a free UDP port (2 is the cap, from
`preview_client_count`). `headless` combines with any mode.

**Scenario JSON.** Top level: `name`, `mode`, `level` (id such as
`level_4` or an index; omit it for the committed override), `seed`,
`clients`, `timeout_sec` (per process, default 60),
`headless`, `settings` (in-memory `Settings` overrides such as
`{"match_duration_sec": 120}`; the committed match is 10 s), `steps`
(run by every client), and `processes.<server|client|clientN>` with
its own `steps`, `settings`, `headless`, `timeout_sec`. A process
with no steps waits until ready, then screenshots and snapshots.

**Reproducibility.** Runs start from the committed settings.tres (the
wrapper extracts `HEAD:settings.tres` with git), so an operator's
local edits never change a result; `-UseWorkingSettings` opts out,
and `settings_reset` in the summary lists what was ignored. `seed`
(default 1; `null` or `-Seed none` keeps the game random) fixes the
global RNG, which spawn points, bunny names, and critters draw from.
Each process seeds with `seed` plus its `--client` number (server 0)
at boot, again right after main.tscn's `randomize()`, and again
whenever a level enters the tree, so level setup and the spawns it
makes replay identically. In a match the wrapper starts each client
after the previous one connects, so client N is always player N.
Anything that happens later depends on how many frames ran, which is
wall-clock time.

**Steps** are `{"do": ...}` objects. A failing step stops the process
unless it is an `assert` or sets `"fatal": false`.
- `wait` (`sec` or physics `frames`), `wait_until` (`expr`,
  `timeout_sec`), `wait_ready` (level loaded with the local bunny,
  the lobby screen, or on the server every player in),
  `wait_match_start` (countdown over).
- `press`, `release`, `tap` (`hold_sec` or `hold_frames`) take `key`
  or `keys`. Movement names (`move_left` or `left`, `jump`, ...) map
  to keyboard partition `player` 1-4 (WASD+Space, IJKL+Shift,
  arrows+Enter, numpad); anything else is a Godot key name such as
  `Escape`. Held keys are re-sent if the OS releases them.
- `screenshot` (`name`, `target`: `window` or `game`), `state`
  (`name`: players, match, HUD labels, screen, level, frame).
- `eval` (`expr`, `name`), `call` (`node`, `method`, `args`),
  `assert` (`expr`, `message`), `log`, `quit`.

Expressions are Godot `Expression`s with `G`, `Netcode`, `Platform`,
`level`, `match_state`, `snapshots`, `driver`, `OS`, `Engine`,
`Input`, and `Time` in scope, plus the driver's helpers: `players()`,
`player(id)`, `local_player(i)`, `player_count()`, `peer_count()`,
`screen()`, `level_id()`, `snap(name)`, `ui_labels(path)`. For
example:
`"snap('after').players[0].x > snap('before').players[0].x + 20"`.

**Output.** `<run>/scenario.json`, `<run>/summary.json`, and per
process `<run>/<name>/`: `process.log` (stdout and stderr merged in
order), `result.json`, `<shot>.png`, `state-<name>.json`, and
`appdata/` (the sandbox, holding `user://logs/godot.log`). The wrapper
prints one PASS/FAIL line per process and exits 0 or 1.

**Prod safety.** Every process gets a throwaway `APPDATA`, and the
driver refuses to run (exit 3) unless `user://` is inside it and no
`auth*.cfg` is visible. It initializes `Platform` before `G` does,
with every backend URL at `127.0.0.1:9`, forces
`preview_connect_to_remote_server=false`, mutes audio, and never
writes settings.tres. `-AllowNetwork` lifts only the network block;
the wrapper deletes any `auth*.cfg` a run wrote.

`-Backend http://127.0.0.1:<port>` points Nakama, and only Nakama,
at a local stack, such as one `scripts/local-smoke-test.ps1
-KeepStack` left up (`-BackendServerKey`, default the dev stack's
`defaultkey`). The host must be loopback; anything else is refused
(exit 3), with or without `-AllowNetwork`, so a run can never reach
production. OAuth and the token broker stay blackholed.
`scenarios/leaderboard-local-backend.json` opens the in-game
leaderboard against such a stack and needs recorded scores in it.

**Pass/fail and exit codes.** Judge by the `AGENT_RESULT {...}` line,
as the wrapper does. A process fails on a missing result line, a
failed step or assert, a `CrashHandlerException`, or a `SCRIPT ERROR`.
`ERROR:` lines are counted (`top_errors`, plus `teardown_errors` after
the result) but do not fail a run, because local mode and preview
matches log known RPC and replication errors today. About half of all
lobby runs also end with an `AudioStreamWAV` (`pause_menu.wav`) leak
warning at exit; that is known teardown noise.
Exit codes are real: 0 pass, 1 fail, 2 bad scenario, 3 refused. Every
preview process, harness or not, used to exit 0xC0000005 because
rollback_netcode's `PerfTracker` never removed its lambda-backed
`Performance` custom monitors. Since rollback_netcode 1.0.2 it removes
them in `_exit_tree`, so the harness no longer works around it.

**Files.** `scripts/agent/agent_bootstrap.gd` is the `-s` main loop.
It must not name an autoload (a `-s` script compiles before the
autoload globals exist), so it loads `agent_driver.gd`, which does
the work. `scripts/` has a `.gdignore`, so neither ships.
