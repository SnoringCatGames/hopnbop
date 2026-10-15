import sys
p = sys.argv[1] + "/items.txt"
q = {
 "T13": "Quick: labels exist (`src/level/lobby_level.gd:97,100`, `src/ui/screens/loading_screen.gd:130`), runtime `runtime_status.go`; the 15 and 45 min timing checks are the owner's",
 "T20": "Quick: presence code and tests exist in the SDK and runtime",
 "T21": "Quick: device (anonymous) auth implemented with tests",
 "T22": "Quick: party code and tests exist",
 "T26": "Quick: leaderboard screen exists; see T30",
 "T31": "Quick: the note has no details (L108 is an empty bullet)",
 "T32": "Quick: not checked here",
 "T34": "Quick: removal in `_server_on_peer_disconnected`; wins-by-default text exists (`src/ui/celebration/match_end_celebration.gd:230,234`)",
 "T35": "Quick: Google sign-in has no automated coverage (CLAUDE.md)",
 "T36": "Quick: party code and tests exist; who-gets-control is the owner's",
 "T65": "Owner: test review",
 "T66": "Owner: CI status",
 "T103": "Owner: test status",
}
out = []
for line in open(p, encoding="utf-8"):
    f = line.rstrip("\n").split("~")
    if f and f[0] in q:
        f[5] = q[f[0]]
    out.append("~".join(f))
open(p, "w", encoding="utf-8").write("\n".join(out) + "\n")
print(sum(1 for l in out if "Owner domain agent" in l))
