"""Print the last N assistant text blocks of a transcript.

Usage: python lastreply.py <transcript.jsonl> [n] [maxchars]
"""
import json
import sys


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    path = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    maxchars = int(sys.argv[3]) if len(sys.argv) > 3 else 12000
    texts = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                o = json.loads(line)
            except Exception:
                continue
            if o.get("type") != "assistant":
                continue
            content = (o.get("message") or {}).get("content")
            if not isinstance(content, list):
                continue
            t = "\n".join(
                b.get("text", "")
                for b in content
                if isinstance(b, dict) and b.get("type") == "text"
            ).strip()
            if t:
                texts.append((o.get("timestamp", "")[:19], t))
    for ts, t in texts[-n:]:
        print(f"----- {ts}")
        print(t[:maxchars])


if __name__ == "__main__":
    main()
