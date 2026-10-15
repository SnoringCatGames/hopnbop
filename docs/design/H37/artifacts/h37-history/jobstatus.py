"""Print status entries for jobs matching a regex since a date.

Usage: python -I jobstatus.py <status.jsonl> <job_regex> <since>
"""
import json
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")
path, pat, since = sys.argv[1], re.compile(sys.argv[2], re.I), sys.argv[3]
keys = None
for line in open(path, encoding="utf-8"):
    try:
        o = json.loads(line)
    except Exception:
        continue
    if keys is None:
        keys = list(o.keys())
        print("keys:", keys)
    j = str(o.get("source") or o.get("job") or o.get("id") or o.get("name") or o.get("service") or "")
    if not pat.search(j):
        continue
    ts = str(o.get("ts") or o.get("time") or o.get("timestamp") or o.get("at") or "")
    if ts < since:
        continue
    st = str(o.get("status") or o.get("state") or o.get("result") or o.get("level") or "")
    msg = str(o.get("summary") or o.get("message") or o.get("detail") or o.get("text") or "")
    print(ts[:16], j, st, "|", msg[:160].replace("\n", " "))

