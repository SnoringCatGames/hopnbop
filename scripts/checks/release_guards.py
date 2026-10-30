#!/usr/bin/env python3
"""Release-checklist guards (H99, from TODO-scratch T48).

Two checks from the manual release checklist, automated:

1. RPC channels: every @rpc annotation in src/ and the rollback
   netcode submodule must name its channel explicitly (the fourth
   argument), so the choice is made on purpose instead of falling
   back to channel 0 by accident. No baseline: fix violations.

2. Logging: bare print/printerr/push_warning/push_error calls in
   src/ outside the logging utilities must not grow. The known
   ones are listed in release_guards_baseline.txt (path:line is
   too brittle, so entries are path + call kind, counted). Fixing
   a baselined call is welcome: shrink the baseline with it.

Run from the repo root: python3 scripts/checks/release_guards.py
Exits 1 and names each new violation.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASELINE = Path(__file__).with_name("release_guards_baseline.txt")

LOG_CALLS = ("print(", "printerr(", "push_warning(", "push_error(")
# The utilities every other call should route through.
LOG_UTILITY_FILES = {
    "src/scaffolder/scaffolder_log.gd",
}


def gd_files(base):
    return sorted(base.rglob("*.gd")) if base.exists() else []


def rpc_violations():
    out = []
    for base in (ROOT / "src", ROOT / "addons/rollback_netcode"):
        for path in gd_files(base):
            text = path.read_text(encoding="utf-8", errors="replace")
            for match in re.finditer(r"@rpc\((.*?)\)\s*\n\s*func ", text, re.S):
                args = match.group(1)
                parts = [a.strip() for a in args.split(",") if a.strip()]
                if len(parts) < 4:
                    line = text[: match.start()].count("\n") + 1
                    rel = path.relative_to(ROOT).as_posix()
                    out.append(f"{rel}:{line}: @rpc without explicit channel")
    return out


def log_violations():
    out = []
    for path in gd_files(ROOT / "src"):
        rel = path.relative_to(ROOT).as_posix()
        if rel in LOG_UTILITY_FILES:
            continue
        for number, line in enumerate(
            path.read_text(encoding="utf-8", errors="replace").splitlines(), 1
        ):
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            for call in LOG_CALLS:
                if stripped.startswith(call):
                    out.append(f"{rel}: {call}")
                    break
    return out


def main():
    failures = []
    for violation in rpc_violations():
        failures.append(violation)

    baseline = []
    if BASELINE.exists():
        baseline = [
            line.strip()
            for line in BASELINE.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.startswith("#")
        ]
    remaining = list(baseline)
    for violation in log_violations():
        if violation in remaining:
            remaining.remove(violation)
        else:
            failures.append(f"new bare log call: {violation}")

    if failures:
        print("release guards failed:")
        for failure in failures:
            print(f"  {failure}")
        return 1
    print("release guards ok (RPC channels explicit, no new bare log calls)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
