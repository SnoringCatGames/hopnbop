# Flags GDScript string concatenations where `%` (which binds tighter
# than `+`) formats only the last fragment while an earlier fragment
# holds a placeholder: `"a %d" + " b" % x` formats " b" alone.
import os, re, sys

BS = chr(92)
PH = re.compile(r'(?<!%)%[-+ 0#]*\*?\d*(?:\.\d+)?[sdcfoxXv]')
STR = re.compile('"(?:[^"' + BS + BS + chr(10) + ']|' + BS + BS + '.)*"')

def scan(path):
    text = open(path, encoding='utf-8', errors='replace').read()
    lits = [(m.start(), m.end(), m.group(0)) for m in STR.finditer(text)]
    hits = []
    for i, (s, e, lit) in enumerate(lits):
        after = text[e:e + 40]
        if not re.match(r'\s*%\s*[\[\(\w"]', after):
            continue
        j, chain = i, []
        while j > 0:
            before = text[lits[j - 1][1]:lits[j][0]]
            if re.fullmatch(r'\s*\+\s*', before):
                chain.append(lits[j - 1][2]); j -= 1
            else:
                break
        if any(PH.search(c) for c in chain):
            line = text.count(chr(10), 0, s) + 1
            hits.append((line, (''.join(reversed(chain)) + lit)[:100]))
    return hits

total = 0
for root in sys.argv[1:]:
    for d, _, files in os.walk(root):
        if '.godot' in d:
            continue
        for f in files:
            if f.endswith('.gd'):
                p = os.path.join(d, f)
                for line, frag in scan(p):
                    total += 1
                    print(f'{p}:{line}: {frag}')
print(f'TOTAL {total}')
