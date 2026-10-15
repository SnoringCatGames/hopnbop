"""List tool_use calls in a transcript time window (UTC prefix compare).

Usage: python tools.py <transcript.jsonl> <from_ts> <to_ts> [maxlen]
"""
import json
import sys


def main():
    path, t0, t1 = sys.argv[1], sys.argv[2], sys.argv[3]
    maxlen = int(sys.argv[4]) if len(sys.argv) > 4 else 300
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                o = json.loads(line)
            except Exception:
                continue
            if o.get("type") != "assistant":
                continue
            ts = o.get("timestamp", "")[:19]
            if not (t0 <= ts <= t1):
                continue
            content = (o.get("message") or {}).get("content")
            if not isinstance(content, list):
                continue
            for b in content:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    inp = b.get("input", {})
                    s = json.dumps(inp, ensure_ascii=False)
                    print(f"{ts} {b.get('name')}: {s[:maxlen]}")


if __name__ == "__main__":
    main()
