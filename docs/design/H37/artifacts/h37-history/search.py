"""Search human messages (and optionally assistant text) across transcripts.

Usage: python -I search.py <root> <regex> [--assistant] [--since YYYY-MM-DD]
       [--max N]

Human messages = `user` records that are not tool results and not meta, plus
`queue-operation` enqueue records (mid-turn messages). Subagent transcripts
are included (their "user" record is the agent prompt; marked [agent]).
"""
import json
import os
import re
import sys


def text_of(content):
    if isinstance(content, str):
        return content
    out = []
    if isinstance(content, list):
        for b in content:
            if isinstance(b, dict) and b.get("type") == "text":
                out.append(b.get("text", ""))
    return "\n".join(out)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    root, pat = sys.argv[1], re.compile(sys.argv[2], re.I)
    want_asst = "--assistant" in sys.argv
    since = ""
    mx = 400
    if "--since" in sys.argv:
        since = sys.argv[sys.argv.index("--since") + 1]
    if "--max" in sys.argv:
        mx = int(sys.argv[sys.argv.index("--max") + 1])
    excl = sys.argv[sys.argv.index("--exclude") + 1] if "--exclude" in sys.argv else ""
    hits = 0
    for dp, dn, fn in os.walk(root):
        for n in fn:
            if not n.endswith(".jsonl"):
                continue
            path = os.path.join(dp, n)
            is_agent = "subagents" in dp
            short = os.path.relpath(path, root)
            if excl and re.search(excl, short):
                continue
            try:
                f = open(path, encoding="utf-8")
            except Exception:
                continue
            with f:
                for line in f:
                    try:
                        o = json.loads(line)
                    except Exception:
                        continue
                    ts = o.get("timestamp", "")[:19]
                    if since and ts and ts < since:
                        continue
                    t = o.get("type")
                    txt, kind = None, None
                    if t == "queue-operation" and o.get("operation") == "enqueue":
                        txt, kind = text_of(o.get("content")), "queued"
                    elif t == "user" and not o.get("isMeta"):
                        c = (o.get("message") or {}).get("content")
                        if isinstance(c, list) and any(
                            isinstance(b, dict) and b.get("type") == "tool_result"
                            for b in c
                        ):
                            continue
                        txt = text_of(c)
                        kind = "agent-prompt" if is_agent else "user"
                        if txt.startswith("This session is being continued"):
                            kind = "summary"
                    elif t == "assistant" and want_asst:
                        txt = text_of((o.get("message") or {}).get("content"))
                        kind = "assistant"
                    if not txt or txt.startswith("<task-notification>"):
                        continue
                    m = pat.search(txt)
                    if not m:
                        continue
                    hits += 1
                    a = max(0, m.start() - mx // 2)
                    snip = txt[a:a + mx].replace("\n", " ")
                    print(f"[{kind}] {ts} {short}\n    ...{snip}...")
    print(f"hits={hits}")


if __name__ == "__main__":
    main()

