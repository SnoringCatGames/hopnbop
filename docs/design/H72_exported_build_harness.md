# H72: exported-build runs for the harness

## Problem

`scripts/agent/run-game.ps1` runs the game from source in
the editor binary. It cannot catch what only an exported
build does: export-time script stripping, the web boot
parse cascade (`docs/web-parse-errors.md`), or a Linux
server behaving differently from the editor. H38's
release check waits on this. The repo's presets ship no
custom template (`export_presets.cfg` has empty
`custom_template/*`), and CI's export-smoke job already
exports Web and Linux server builds per push, but nothing
runs one under the harness's scripted steps.

## Options

1. **Build the export in the harness run.** Add a mode
   that exports (Linux server + one client platform) into
   the run directory, then points the existing process
   launcher at the exported binaries. Cost: export adds
   minutes per run and needs the 4.7.2 templates installed
   wherever it runs; the launcher change is small (it
   already starts processes and reads their logs).
2. **Download CI's export artifact.** export-smoke
   uploads nothing today; make it upload the Linux server
   and Web builds, and let the harness run a downloaded
   build locally. Cost: CI minutes and artifact storage,
   plus a version-skew question (the artifact is from the
   push being tested only if the run starts after CI).
3. **Custom template.** Only needed if a build must differ
   from stock 4.7.2 (it does not today); building and
   pinning a template is a separate project. Not
   recommended as part of this item.

## Recommendation

Option 1 for the Linux server (it is the build that runs
production matches and exports fastest), reusing the
export-smoke job's preset invocation so local and CI
build the same artifact. The Web client stays verified
by export-smoke's artifact check plus the boot-log read
in `docs/web-parse-errors.md`; running a browser build
under the harness is a follow-up, not this item. CI
cost: export-smoke already pays the export minutes; the
harness mode is local/agent-run, so no new CI time
unless Levi wants it gated. An exported server reaches
Levi as a run directory artifact (binary + logs +
screenshots) from an agent run, the same shape as today's
source runs.

## How it would be tested

- `run-game.ps1 -Exported` (working name) on
  `match-2-clients`: the exported Linux server hosts,
  two editor clients join, AGENT_RESULT passes, and the
  run directory records the export preset and template
  version.
- A deliberate export-only break (a script reference
  that resolves in the editor but not in export) fails
  the exported run while the source run passes, proving
  the mode exercises the export.
- export-smoke stays green unchanged.
