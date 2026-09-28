"""Export the mods as elekloader .elemod files (format 1, site-only).

    python3 tools/mkelemod.py [--out DIR]

Each mod becomes one .elemod that elekloader (with its Analog Rytm mk1
profile) can combine with the others on the user's own stock .syx:

- the mod's code and data: one "data" site per cave claim, holding the
  assembled bytes at their fixed cave address (the stock bytes there are
  zeros);
- its detours: one "code" site per detour, covering every instruction the
  jmp displaces (the registry's `expect` span), so elekloader's
  whole-instruction check holds. The jmp is 6 bytes; the rest of the span is
  the stock tail, which is never executed;
- its patches: one site each, "code" when the bytes are whole instructions,
  else "data";
- requires / conflicts, and named resources (the sound's free word, the
  parameter ids, the page slot) so elekloader reports clashes by name;
- regions: the cave claims, inside the device profile's cave areas.

The bytes come from the two verified builds (make verify, make random), so
this runs them first. Because every claim sits at a fixed address, a mod's
bytes do not depend on which other mods are in the build;
tools/elemod_check.py proves that for every valid combination by comparing
elekloader's main OS with build.py's.

Stock bytes are never shipped, except the tail of a detour's span (at most
4 bytes of the instruction the jmp cuts into), and only hashes of the stock
bytes each site replaces.
"""
import argparse
import hashlib
import json
import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
BASE = 0x40000400

# The two builds, and which mods each one provides the bytes for.
SETS = {
    "0000_0002_0003_0008": ["0000-shared", "0002-euclid-accents", "0003-velocity-humanise",
                            "0008-sample-cut"],
    "0000_0002_0003_0004": ["0004-lfo-rnd"],
}

META = {
    "0000-shared": dict(
        version="1.0", title="Shared runtime", category="Library",
        requires=[], conflicts=[], names=[],
        blurb="The shared code the other mods call into: the amount table, the decimal "
              "formatter, the random draw and the sound plumbing. No controls of its own."),
    "0002-euclid-accents": dict(
        version="1.0", title="Euclid accents", category="Sequencer",
        requires=[], conflicts=[], names=["euclid-enable-byte"],
        blurb="Euclidean page, OP: four more values, OR* XOR* AND* SUB*. They keep your own "
              "trigs and ACCENT the ones on euclidean hits. FUNC + euclid off bakes the "
              "accents in. Saved with the pattern."),
    "0003-velocity-humanise": dict(
        version="1.0", title="Velocity humanise", category="Sequencer",
        requires=["0000-shared", "0002-euclid-accents"], conflicts=[], names=[],
        blurb="TRIG page, FUNC + VEL: RND amount 0..64. Every trig on the track plays at "
              "its velocity plus a random -N..+N. Needs Euclid accents, which saves the "
              "amount with the pattern."),
    "0004-lfo-rnd": dict(
        version="1.0", title="LFO RND (random modifiers)", category="Sound",
        requires=["0000-shared"], conflicts=["0008-sample-cut"],
        names=["sound-word:0", "param-id:1", "param-id:2", "param-id:3", "param-id:4",
               "page:11"],
        blurb="Press LFO twice: two random modifiers per sound. DS1/DS2 pick a destination "
              "(the 8 machine parameters, FIN, STA, FRQ, RES, DEC, PAN, DEL, REV), DP1/DP2 a "
              "depth 0..64. Every note adds a random -N..+N to it. Voice tracks only. Cannot "
              "be combined with SMP CUT: both keep their settings in the sound's one free word."),
    "0008-sample-cut": dict(
        version="3.0", title="SMP CUT (low / high cut)", category="Sound",
        requires=["0000-shared"], conflicts=["0004-lfo-rnd"],
        names=["sound-word:0", "param-id:1", "param-id:2", "page:11"],
        blurb="Press FILTER twice: LCT (low cut) and HCT (high cut) per track, 12 dB/oct, "
              "20 Hz..20 kHz, on the sample layer (the analog part of a machine cannot be "
              "filtered from firmware). Cannot be combined with LFO RND: both keep their "
              "settings in the sound's one free word."),
}
AUTHOR = {
    "0008-sample-cut": "rytm1_mods",
}
DEFAULT_AUTHOR = "rytm-mods (MKII), ported to the MK1 by rytm1_mods"


def sha(b):
    return hashlib.sha256(b).hexdigest()


def run(cmd):
    subprocess.run(cmd, check=True, cwd=ROOT, stdout=subprocess.DEVNULL)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default=str(BUILD / "elemod"))
    ap.add_argument("--no-build", action="store_true", help="use the builds already in build/")
    a = ap.parse_args()

    if not a.no_build:
        run(["make", "verify"])
        run(["make", "random"])
    sym = tomllib.load(open(ROOT / "re" / "symbols.toml", "rb"))["meta"]
    reg = tomllib.load(open(ROOT / "registry" / "allocations.toml", "rb"))
    stock_syx = (ROOT / "stock" / "Analog-Rytm_OS1.73.syx").read_bytes()
    stock = (BUILD / "stock_mainos.bin").read_bytes()
    target = {"device": "rytm-mk1", "product": "Analog Rytm mk1", "os": "1.73",
              "syx_sha256": sha(stock_syx), "section3_sha256": sha(stock),
              "section3_len": len(stock)}
    if target["section3_sha256"] != sym["mainos_sha256"]:
        raise SystemExit("build/stock_mainos.bin is not the stock MAIN OS")
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                            capture_output=True, text=True).stdout.strip() or "?"
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)

    pools = {p["name"]: (p["start"], p["end"]) for p in reg["pool"]}

    def pool_of(lo, hi):
        for n, (s, e) in pools.items():
            if s <= lo and hi <= e:
                return n
        raise SystemExit(f"claim 0x{lo:08x} is in no pool")

    written = []
    for tag, owners in SETS.items():
        img = (BUILD / f"mainos_{tag}.bin").read_bytes()
        if len(img) != len(stock):
            raise SystemExit(f"mainos_{tag}.bin has the wrong size")

        def at(buf, addr, n):
            o = addr - BASE
            return buf[o:o + n]

        for owner in owners:
            mt = tomllib.load(open(ROOT / "mods" / owner / "mod.toml", "rb"))["mod"]
            m = META[owner]
            sites, regions = [], []
            for c in reg.get("cave", []):
                if c["owner"] != owner:
                    continue
                new, old = at(img, c["addr"], c["size"]), at(stock, c["addr"], c["size"])
                if new == old:
                    continue                       # gated out in this build
                sites.append({"addr": f"0x{c['addr']:08x}", "len": c["size"], "kind": "data",
                              "stock_sha256": sha(old), "new": new.hex(),
                              "note": f"{c.get('section', '.text')} in {pool_of(c['addr'], c['addr'] + c['size'])}"})
                regions.append({"name": f"{pool_of(c['addr'], c['addr'] + c['size'])} "
                                        f"{c.get('section', '.text')}",
                                "lo": f"0x{c['addr']:08x}", "hi": f"0x{c['addr'] + c['size']:08x}"})
            for d in reg.get("detour", []):
                if d["owner"] != owner:
                    continue
                n = len(bytes.fromhex(d["expect"]))
                new, old = at(img, d["addr"], n), at(stock, d["addr"], n)
                if new == old:
                    continue
                if old != bytes.fromhex(d["expect"]) or new[:2] != b"\x4e\xf9" or new[6:] != old[6:]:
                    raise SystemExit(f"{owner}: detour 0x{d['addr']:08x} is not jmp + stock tail")
                sites.append({"addr": f"0x{d['addr']:08x}", "len": n, "kind": "code",
                              "stock_sha256": sha(old), "new": new.hex(),
                              "note": f"detour -> {d['entry']}"})
            for p in reg.get("patch", []):
                if p["owner"] != owner:
                    continue
                new, old = at(img, p["addr"], p["size"]), at(stock, p["addr"], p["size"])
                if new == old:
                    continue
                kind = "code" if len(new) == 2 else "data"   # the 2-byte patches are moveq/bra
                sites.append({"addr": f"0x{p['addr']:08x}", "len": p["size"], "kind": kind,
                              "stock_sha256": sha(old), "new": new.hex(),
                              "note": "patch" + (f" -> {p['from_symbol']}" if "from_symbol" in p else "")})
            sites.sort(key=lambda s: int(s["addr"], 16))
            doc = {
                "elemod": 1,
                "id": owner,
                "version": m["version"],
                "title": m["title"],
                "description": m["blurb"],
                "category": m["category"],
                "author": AUTHOR.get(owner, DEFAULT_AUTHOR),
                "target": target,
                "requires": m["requires"],
                "conflicts": m["conflicts"],
                "resources": {"regions": regions, "names": m["names"]},
                "sites": sites,
                "build": {"tool": "rytm1_mods tools/mkelemod.py", "commit": commit,
                          "from_build": f"mainos_{tag}.bin", "mod_title": mt["title"]},
                "signature": None,
            }
            path = out / f"{owner}-{m['version']}.elemod"
            path.write_text(json.dumps(doc, indent=1) + "\n")
            written.append(path)
            print(f"{path.name}: {len(sites)} sites, "
                  f"{sum(s['len'] for s in sites)} B, regions {[r['name'] for r in regions]}")
    return written


if __name__ == "__main__":
    main()
