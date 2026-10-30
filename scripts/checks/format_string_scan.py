#!/usr/bin/env python3
"""Broken format-string scan (H66, from the H37 audit's V17).

GDScript's `%` (format) binds tighter than `+`, so in

    "Client %d rejected:" + " limit reached" % peer_id

only the last fragment is formatted: the `%d` never substitutes and
the format call errors at runtime ("not all arguments converted").
The fix is one literal, or parentheses around the concatenation.

This scan flags every `"..." + ... % args` chain whose last fragment
does not consume exactly the given arguments. It understands `%%`
(literal), `%.*f` (consumes precision + value), triple-quoted
strings, and leaves non-literal left sides (`tr("KEY") % n`) and
plain modulo alone.

Run from the repo root: python3 scripts/checks/format_string_scan.py
Exits 1 and names each violation.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCAN_DIRS = [
    "src",
    "test",
    "scripts",
    "addons/rollback_netcode/core",
    "addons/rollback_netcode/state",
    "addons/rollback_netcode/utils",
    "addons/rollback_netcode/debug",
]

_PLACEHOLDER = re.compile(
    r"%(?:[-+ 0#]*(?:\d+|\*)?(?:\.(?:\d+|\*))?[sdifeExXobc]|%)")


def placeholders(text):
    """(count, arg_consumption) for a literal's placeholders."""
    count = 0
    consumed = 0
    for match in _PLACEHOLDER.finditer(text):
        token = match.group(0)
        if token == "%%":
            # A literal percent consumes no argument.
            continue
        count += 1
        consumed += 1 + token.count("*")
    return count, consumed


def depth_of(text):
    return (sum(text.count(c) for c in "([{")
            - sum(text.count(c) for c in ")]}"))


def tokens(stmt):
    """Yield (kind, text): STR, PCT, PLUS, or OTHER runs."""
    i, n = 0, len(stmt)
    while i < n:
        c = stmt[i]
        if c == '"':
            if stmt.startswith('"""', i):
                end = stmt.find('"""', i + 3)
                end = n if end < 0 else end + 3
                yield ("STR", stmt[i + 3:end - 3])
                i = end
                continue
            j = i + 1
            while j < n:
                if stmt[j] == "\\":
                    j += 2
                    continue
                if stmt[j] == '"':
                    break
                j += 1
            yield ("STR", stmt[i + 1:j])
            i = j + 1
        elif c == "%":
            yield ("PCT", c)
            i += 1
        elif c == "+":
            yield ("PLUS", c)
            i += 1
        else:
            j = i
            while j < n and stmt[j] not in '"%+':
                j += 1
            yield ("OTHER", stmt[i:j])
            i = j


def bracket_argc(stmt, pos):
    """Elements in the [...] starting at pos in stmt."""
    depth, instr, commas, i = 0, False, 0, pos
    while i < len(stmt):
        c = stmt[i]
        if instr:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                instr = False
            i += 1
            continue
        if c == '"':
            instr = True
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                break
        elif c == "," and depth == 1:
            commas += 1
        i += 1
    inner = stmt[pos + 1:i].strip().rstrip(",").strip()
    if not inner:
        return 0
    count, depth2, instr2, j = 1, 0, False, 0
    while j < len(inner):
        c = inner[j]
        if instr2:
            if c == "\\":
                j += 2
                continue
            if c == '"':
                instr2 = False
            j += 1
            continue
        if c == '"':
            instr2 = True
        elif c in "([{":
            depth2 += 1
        elif c in ")]}":
            depth2 -= 1
        elif c == "," and depth2 == 0:
            count += 1
        j += 1
    return count


def statement_violations(stmt):
    toks = list(tokens(stmt))
    for index, (kind, _text) in enumerate(toks):
        if kind != "PCT":
            continue
        chain = []
        k = index - 1
        while k >= 0:
            tkind, ttext = toks[k]
            if tkind == "STR":
                chain.append(ttext)
            elif tkind == "PLUS":
                pass
            elif tkind == "OTHER" and ttext.strip() == "":
                pass
            else:
                break
            k -= 1
        if not chain:
            continue
        _ph, consumed = placeholders(chain[0])
        following = "".join(t for _k, t in toks[index + 1:index + 3])
        if following.strip().startswith("["):
            pos = stmt.find("[", stmt.find("%"))
            # Find the '[' that belongs to this %: the first '[' after
            # the (index-th) percent sign outside strings.
            argc = _argc_for(stmt, toks, index)
        else:
            argc = 1
        if consumed != argc:
            yield " + ".join(reversed(chain))


def _argc_for(stmt, toks, pct_index):
    # Count PCT tokens up to pct_index to find this one in the raw text.
    ordinal = sum(1 for kind, _t in toks[:pct_index + 1] if kind == "PCT") - 1
    seen, instr, i = -1, False, 0
    pos = -1
    while i < len(stmt):
        c = stmt[i]
        if instr:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                instr = False
            i += 1
            continue
        if c == '"':
            instr = True
        elif c == "%":
            seen += 1
            if seen == ordinal:
                pos = i
                break
        i += 1
    if pos < 0:
        return 1
    bracket = stmt.find("[", pos)
    if bracket < 0 or stmt[pos:bracket].strip() != "%":
        return 1
    return bracket_argc(stmt, bracket)


def scan_file(path):
    lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
    i = 0
    while i < len(lines):
        start = i
        logical = lines[i]
        depth = depth_of(logical)
        while (logical.rstrip().endswith("\\") or depth > 0) and i + 1 < len(lines):
            i += 1
            logical += "\n" + lines[i]
            depth += depth_of(lines[i])
        i += 1
        if "%" not in logical or '"' not in logical:
            continue
        for chain in statement_violations(logical):
            yield start + 1, chain


def main():
    violations = []
    for rel in SCAN_DIRS:
        base = ROOT / rel
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.gd")):
            for line, chain in scan_file(path):
                violations.append((path.relative_to(ROOT), line, chain))
    for path, line, chain in violations:
        print(f"{path}:{line}: broken format chain: {chain[:120]}")
    if violations:
        print(f"\n{len(violations)} broken format string(s). Parenthesize "
              "the concatenation or merge it into one literal.")
        return 1
    print("format strings ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
