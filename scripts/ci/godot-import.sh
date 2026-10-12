#!/usr/bin/env bash
# Imports the project in a fresh CI checkout, which has no .godot/ cache.
# Run from the repo root, after scripts/ci/bridge-platform-addon.sh.
#
# --import exits non-zero on harmless warnings, so a non-zero exit alone
# means nothing. A crash does. On 2026-10-11 the importer segfaulted
# partway through translations/adjectives/*.csv, the step only warned,
# and 40 GUT files then failed against a half-imported project. So retry
# when the importer dies on a signal (exit 128 and up), then check that
# class_names registered at all.
set -uo pipefail

attempts=3
for attempt in $(seq 1 "$attempts"); do
  godot --headless --import
  rc=$?
  if [ "$rc" -lt 128 ]; then
    break
  fi
  echo "::warning::godot --import died with exit $rc (attempt $attempt of $attempts)"
  if [ "$attempt" -eq "$attempts" ]; then
    echo "::error::godot --import crashed $attempts times in a row"
    exit 1
  fi
done

cache=.godot/global_script_class_cache.cfg
if ! grep -q '"GutTest"' "$cache" 2>/dev/null; then
  echo "::error::--import did not register class_names (GutTest missing from $cache)"
  exit 1
fi
echo "import ok: exit $rc on attempt $attempt"
