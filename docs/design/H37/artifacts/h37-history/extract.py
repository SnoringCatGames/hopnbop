"""Extract readable text from a Claude Code session transcript (JSONL).

Usage: python extract.py <transcript.jsonl> <out_prefix>

Writes:
  <out_prefix>.users.txt      user prompts (not tool results), with UTC time
  <out_prefix>.assistant.txt  assistant text blocks, with UTC time
  <out_prefix>.agents.txt     Agent/Task tool_use calls (description + prompt)
  <out_prefix>.all.txt        users + assistant interleaved
"""
import json
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
    path, prefix = sys.argv[1], sys.argv[2]
    users, assistant, agents, alll = [], [], [], []
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                o = json.loads(line)
            except Exception:
                continue
            t = o.get("type")
            ts = o.get("timestamp", "")[:19]
            msg = o.get("message") or {}
            content = msg.get("content")
            if t == "queue-operation" and o.get("operation") == "enqueue":
                c = o.get("content")
                if isinstance(c, list):
                    c = text_of(c)
                c = (c or "").strip()
                if c and not c.startswith("<task-notification>"):
                    entry = f"===== USER {ts} [queued mid-turn]\n{c}\n"
                    users.append(entry)
                    alll.append(entry)
                continue
            if t == "user":
                if isinstance(content, list) and any(
                    isinstance(b, dict) and b.get("type") == "tool_result"
                    for b in content
                ):
                    continue
                txt = text_of(content).strip()
                if not txt:
                    continue
                meta = " [meta]" if o.get("isMeta") else ""
                entry = f"===== USER {ts}{meta}\n{txt}\n"
                users.append(entry)
                alll.append(entry)
            elif t == "assistant":
                txt = text_of(content).strip()
                if txt:
                    entry = f"----- ASSISTANT {ts}\n{txt}\n"
                    assistant.append(entry)
                    alll.append(entry)
                if isinstance(content, list):
                    for b in content:
                        if (
                            isinstance(b, dict)
                            and b.get("type") == "tool_use"
                            and b.get("name") in ("Agent", "Task", "SendMessage")
                        ):
                            inp = b.get("input", {})
                            agents.append(
                                f"##### {b.get('name')} {ts} id={b.get('id')}\n"
                                + json.dumps(inp, indent=1, ensure_ascii=False)
                                + "\n"
                            )
    for suffix, data in (
        ("users", users),
        ("assistant", assistant),
        ("agents", agents),
        ("all", alll),
    ):
        with open(f"{prefix}.{suffix}.txt", "w", encoding="utf-8") as g:
            g.write("\n".join(data))
    print(
        f"users={len(users)} assistant={len(assistant)} agents={len(agents)}"
    )


if __name__ == "__main__":
    main()

