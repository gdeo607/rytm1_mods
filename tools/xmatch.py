"""Match MKII addresses to their MK1 equivalents, and show both side by side.

Both MAIN OS images are the same code base, compiled separately. This normalises each
disassembly (absolute code/data and SRAM addresses masked), indexes the MK1 one by
k-grams of normalised instructions, and for an MKII address votes over the k-grams in
a window around it. The winning MK1 address is printed with its vote and, with
--side, both listings next to each other (* marks lines that differ once
normalised). A strong vote (~40+) with an identical listing is the usual evidence
recorded in re/symbols.toml; anything weaker is a lead, not a result.

Disassemble each MAIN OS the way `make disasm` does, then:

    python3 tools/xmatch.py MK2.dis MK1.dis 0x40120fae 0x40006ea8 --side
"""
import argparse
import bisect
import collections
import re

K = 6
RX = re.compile(r"^([0-9a-f]{8}):\t([0-9a-f ]+?)\s*\t(.*)$")


def load(path):
    addrs, norm, text = [], [], []
    for line in open(path):
        m = RX.match(line)
        if not m:
            continue
        ins = m.group(3)
        t = re.sub(r"0x4[0-7][0-9a-f]{6}", "A", ins)
        t = re.sub(r"0x80[0-9a-f]{6}", "R", t)
        t = re.sub(r"\b(10[0-9]{8}|11[0-9]{8}|21[0-9]{8})\b", "A", t)
        t = re.sub(r"-?21474[0-9]{5}", "R", t)
        addrs.append(int(m.group(1), 16))
        norm.append(t)
        text.append(ins)
    idx = collections.defaultdict(list)
    for i in range(len(norm) - K):
        idx["\0".join(norm[i:i + K])].append(i)
    return addrs, norm, text, idx


def find(m2, m1, addr, span=24):
    a2, n2, _, _ = m2
    a1, _, _, idx1 = m1
    i = bisect.bisect_left(a2, addr)
    if i >= len(a2) or a2[i] != addr:
        return []
    votes = collections.Counter()
    for s in range(max(0, i - span), min(len(n2) - K, i + span)):
        c = idx1.get("\0".join(n2[s:s + K]), [])
        if len(c) > 20:
            continue
        for j in c:
            votes[j - (s - i)] += 1 / len(c)
    return [(a1[j], round(v, 1)) for j, v in votes.most_common(3) if 0 <= j < len(a1)]


def side(m2, m1, addr, n=6):
    a2, n2, t2, _ = m2
    a1, n1, t1, _ = m1
    r = find(m2, m1, addr)
    if not r:
        print(f"{addr:#x}: no match")
        return
    i = bisect.bisect_left(a2, addr)
    j = bisect.bisect_left(a1, r[0][0])
    print(f"== {addr:#x} -> {r[0][0]:#x} ({r[0][1]})")
    for k in range(-n, n + 1):
        if not (0 <= i + k < len(a2) and 0 <= j + k < len(a1)):
            continue
        mark = " " if n2[i + k] == n1[j + k] else "*"
        left = f"{a2[i + k]:08x} {t2[i + k]}"
        print(f"{mark} {left:55.55} | {a1[j + k]:08x} {t1[j + k]}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("mk2_dis")
    ap.add_argument("mk1_dis")
    ap.add_argument("addrs", nargs="+", type=lambda x: int(x, 16))
    ap.add_argument("--side", action="store_true", help="print both listings")
    a = ap.parse_args()
    M2, M1 = load(a.mk2_dis), load(a.mk1_dis)
    for x in a.addrs:
        if a.side:
            side(M2, M1, x)
        else:
            print(f"{x:#x}", [(f"{y:#x}", v) for y, v in find(M2, M1, x)])
