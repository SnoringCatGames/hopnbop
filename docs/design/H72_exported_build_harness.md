# H72: exported-build runs for the harness

## Problem

`scripts/agent/run-game.ps1` runs the game from source in
the editor binary. It cannot catch what only an exported
build does. Scripts are tokenized
(`script_export_mode=2`), the server preset strips visual
resources (`dedicated_server=true`), the web boot parse
cascade (`docs/web-parse-errors.md`) only shows in a Web
build, and release only settings and missing files in a
client pack only show in a packed client. H38's release
check waits on this. The repo's presets ship no custom
template (`export_presets.cfg` has empty
`custom_template/*`), and CI's export-smoke job already
exports Web and Linux server builds per push, but nothing
runs one under the harness's scripted steps.

The stock path cannot drive an exported binary (verified
on 4.7.2). The official 4.7.2 templates, debug and
release, abort on `--path` and `--main-pack` with
"compiled without support for path overrides" (exit 1).
They silently ignore `-s <script>`. A debug export ran its
own main scene instead. `scripts/.gdignore` (tracked)
keeps the bootstrap and the driver out of every pack. The
harness launcher passes exactly those arguments
(`--path`, then `-s res://scripts/agent/agent_bootstrap.gd`).
An exported binary under the existing launcher therefore
runs its own main scene, with no scripted steps, no
snapshots and no `AGENT_RESULT`. The harness also runs
Windows binaries and sandboxes each process through
`APPDATA`. A Linux process ignores `APPDATA` and uses XDG
paths for `user://` (inferred), so the exported Linux
server cannot run on the harness host without Docker or
WSL. Without the driver an exported process has no
sandbox. The URL blackhole and the `-Backend` override
live in the driver. Without it an export boots against
the production URLs, so the harness guarantee that a run
can never reach production would silently not hold.

## Options

1. **Path-override template (the main option).** Build a
   4.7.2 template with `disable_path_overrides=no`, then
   run it with `run-game.ps1 -Godot <its console exe>` on
   the source tree under the full driver sandbox. This
   changes nothing shipped. Build two targets. The debug
   target is enough for the pause question. The release
   target is what shows crashes. The engine build lives
   outside the repo on each machine, next to the stock
   Godot install, and is rebuilt once per Godot upgrade.
   The path is passed with `-Godot`, as today. This is
   the only option that keeps the sandbox, because the
   driver still runs.
2. **Web boot check on every push (the web half).**
   `scripts/web-boot-check.mjs` already boots a Web build
   in headless Chromium and fails on the cascade's
   signatures. It already takes `WEB_CLIENT_URL`. Today it
   runs only nightly, against the deployed site, so a
   cascade is caught after a deploy. The artifact check in
   export-smoke catches less. It only catches an empty
   artifact or script errors printed during the export.
   The `docs/web-parse-errors.md` read is manual. Serve
   export-smoke's fresh `build/web/` locally and run the
   existing check against it on every push. The web preset
   has `thread_support=false`, so a plain local static
   server should do (inferred). Cost: the nightly's
   Playwright install (an 8 minute bound) plus about 30 s
   of boot. Flake risk: on 2026-08-19 the nightly's
   Chromium install wedged and the boot check hung to the
   job timeout, so keep a step timeout.
3. **Exported Linux server as the Docker image (a later
   step).** The image already exports and packages the
   real server. The dev stack does not start servers. It
   runs with mock deploy and synthesizes deploy responses.
   For the server half, `docker run` the game-server image
   on the mock-deploy port. That tests the shipped image,
   not just a binary. It runs on a Docker internal network.
   Its environment holds no production URL or key.

Building the export in the harness run, or downloading
CI's export artifact, cannot be driven with stock
templates, for the reasons in Problem. They are not
recommended.

## Recommendation

Do option 1 first, then option 2. Option 3 is a separate,
later step.

Name the binaries per goal. H38 needs Windows
release-template clients, built from the option 1
template. That is what shows the release only crash (4 of
6 cells crash on release, against 0 of 6 on debug and 1
of 6 in the editor, verified). The exported Linux server
does not show it. The two editor clients in the old plan
do not show it either. The same template also covers
missing files in a client pack and release only settings
(pause, debug toggles). H77's held verify scenarios wait
on the same template.

Every exported run must carry the driver, or run on a
network with no route out (a Docker internal network).
The server's environment must hold no production URL or
key. The option 1 template runs the source tree, so it
keeps the sandbox by construction.

Nothing here ships to players. The fix touches tooling
and CI only, so the released clients are unaffected.

## How it would be tested

An "exported run" covers two different things, so name a
fixture per half.

- For the engine half, H37's minimal 4.7.2 repro. A
  synchronous peer change in `peer_disconnected` crashes
  on release and not in the editor. Run it under the
  option 1 release template on the source tree. It fails
  without the mode and passes with the peer change
  deferred. This is the test that proves the mode
  exercises the release engine.
- For the pack half, a runtime `load()` of a file
  outside `include_filter` (the H40 class). The source run
  passes. The packed run fails. Export-smoke's pack greps
  cover part of this already.
- `run-game.ps1 -Godot <template console exe>` on the
  source tree. The driver still applies its sandbox, the
  scenario's steps run, and the run directory records the
  template version. Debug covers pause. Release covers
  crashes.
- Serve export-smoke's fresh `build/web/` locally and run
  `scripts/web-boot-check.mjs` against it, with a step
  timeout. A deliberate cascade fails it before a deploy.
- Later, `docker run` the game-server image on the
  mock-deploy port. The server hosts, clients join, and
  `AGENT_RESULT` passes.
- export-smoke stays green unchanged. It passes either
  way, so it is not the proof.

Size: M.

Build and keep a 4.7.2 template with path overrides (an
engine build per Godot upgrade) so the harness can run
release builds?

Run the web boot check on every push (about 2 to 3 CI
minutes per push)?
