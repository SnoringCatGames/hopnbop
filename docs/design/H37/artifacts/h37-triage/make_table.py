import csv, sys
d = sys.argv[1]
dates = {}
with open(d + "/line_dates.csv", newline="", encoding="utf-8") as f:
    for row in csv.reader(f):
        if row and row[0].isdigit():
            dates[int(row[0])] = row[1]
out = ["| ID | Lines | Added | Note | Area | Verdict and evidence | Size | Pri | LH | Owner |",
       "|---|---|---|---|---|---|---|---|---|---|"]
for line in open(d + "/items.txt", encoding="utf-8"):
    line = line.rstrip("\n")
    if not line:
        continue
    f = line.split("~")
    tid, a, b = f[0], int(f[1]), int(f[2])
    ds = sorted({dates[i][5:] for i in range(a, b + 1) if i in dates})
    added = ds[0] if len(ds) == 1 else (ds[0] + ".." + ds[-1] if ds else "?")
    lines = str(a) if a == b else "%d-%d" % (a, b)
    out.append("| " + " | ".join([tid, lines, added] + f[3:]) + " |")
open(d + "/items_table.md", "w", encoding="utf-8").write("\n".join(out) + "\n")
print(len(out) - 2)
