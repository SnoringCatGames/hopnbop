#!/usr/bin/env bash
# Copies the platform SDK out of the snoringcat-platform submodule into
# addons/snoringcat_platform_client/, where Godot finds it. Linux CI
# counterpart of scripts/setup-platform-addon.ps1. Run from the repo root.
#
# Then checks that project.godot's Platform autoload, which names the
# script only by UID, resolves to the copied core/platform.gd. The SDK
# has tracked its .uid files since snoringcat-platform b2eecad. Before
# that, a Linux checkout minted different UIDs than a Windows one, so
# the autoload silently failed to load and global.gd failed to compile,
# which showed up only as failing tests or a broken export. A mismatch
# now fails here, naming the cause.
set -euo pipefail

src=third_party/snoringcat-platform/addons/snoringcat_platform_client
dst=addons/snoringcat_platform_client

if [ ! -d "$src" ]; then
  echo "::error::$src is missing. Check out with submodules: recursive."
  exit 1
fi
rm -rf "$dst"
mkdir -p "$(dirname "$dst")"
cp -r "$src" "$dst"

want=$(sed -nE 's|^Platform="\*(uid://[a-z0-9]+)"$|\1|p' project.godot)
have=$(tr -d '[:space:]' 2>/dev/null < "$dst/core/platform.gd.uid" || true)
if [ -z "$want" ]; then
  echo "::error file=project.godot::no Platform=\"*uid://...\" autoload found"
  exit 1
fi
if [ "$want" != "$have" ]; then
  echo "::error file=project.godot::Platform autoload is $want, but $dst/core/platform.gd.uid is '${have:-missing}'. Commit the SDK's .uid files in snoringcat-platform."
  exit 1
fi
echo "Platform autoload $want resolves to $dst/core/platform.gd"
