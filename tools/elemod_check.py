"""Prove the .elemod export: elekloader builds exactly what build.py builds.

    python3 tools/elemod_check.py --elekloader PATH/TO/elekloader [--full]

For every subset of the exported mods:
- if the set is valid (requirements met, 0004 and 0008 not together),
  elekloader must accept it, and the MAIN OS it produces must be byte for
  byte the one tools/build.py produces for the same mods (build.py is the
  pipeline `make verify` checks);
- if it is not valid, elekloader must refuse it.

--full also writes each valid set's .syx with elekloader (its own packer and
container writer) and runs elekloader's verifier on it: the MAIN OS depacks
in place to the build.py image, the embedded bootstrap copy is stock, the
container is within the flash bound.
"""
import argparse
import itertools
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
IDS = ["0000-shared", "0002-euclid-accents", "0003-velocity-humanise", "0004-lfo-rnd",
       "0008-sample-cut"]
REQ = {"0003-velocity-humanise": {"0000-shared", "0002-euclid-accents"},
       "0004-lfo-rnd": {"0000-shared"}, "0008-sample-cut": {"0000-shared"}}


def valid(s):
    if not s:
        return False
    if "0004-lfo-rnd" in s and "0008-sample-cut" in s:
        return False
    return all(REQ.get(m, set()) <= s for m in s)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--elekloader", required=True, help="the elekloader checkout with rytm-mk1")
    ap.add_argument("--mods", default=str(BUILD / "elemod"))
    ap.add_argument("--full", action="store_true", help="also write and verify each .syx")
    a = ap.parse_args()
    sys.path.insert(0, a.elekloader)
    from elekloader import elemod, patch, syx  # noqa: E402

    stock_path = ROOT / "stock" / "Analog-Rytm_OS1.73.syx"
    stock = syx.Syx.load(stock_path)
    img0 = stock.section(3)
    files = {}
    for p in sorted(Path(a.mods).glob("*.elemod")):
        m = elemod.load_any(str(p))
        files[m.id] = (str(p), m)
    missing = set(IDS) - set(files)
    if missing:
        raise SystemExit(f"missing .elemod for {sorted(missing)}")

    ok = bad = 0
    for n in range(1, len(IDS) + 1):
        for combo in itertools.combinations(IDS, n):
            s = set(combo)
            mods = [files[i][1] for i in combo]
            try:
                img = elemod.apply(mods, img0)
                accepted, why = True, ""
            except elemod.ModError as e:
                accepted, why = False, str(e).split("\n")[1].strip() if "\n" in str(e) else str(e)
            label = "+".join(i[:4] for i in combo)
            if not valid(s):
                if accepted:
                    print(f"FAIL {label}: elekloader accepted an invalid set")
                    bad += 1
                else:
                    print(f"ok   {label}: refused ({why})")
                    ok += 1
                continue
            if not accepted:
                print(f"FAIL {label}: elekloader refused a valid set: {why}")
                bad += 1
                continue
            tag = "x_" + "_".join(i[:4] for i in combo)
            subprocess.run([sys.executable, "tools/build.py", "--mods", *combo, "--tag", tag],
                           cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
            ref = (BUILD / f"mainos_{tag}.bin").read_bytes()
            (BUILD / f"mainos_{tag}.bin").unlink()
            for f in BUILD.glob(f"*{tag}*"):
                f.unlink()
            if img != ref:
                diff = [i for i in range(len(ref)) if img[i] != ref[i]]
                print(f"FAIL {label}: MAIN OS differs from build.py at {len(diff)} bytes, "
                      f"first 0x{0x40000400 + diff[0]:08x}")
                bad += 1
                continue
            msg = "same MAIN OS as build.py"
            if a.full:
                out, man = patch.build(str(stock_path), [files[i][0] for i in combo],
                                       log=lambda *x: None)
                f = man["output"]
                if man["main_sha256"] != elemod.sha(ref):
                    print(f"FAIL {label}: the written .syx is not the build.py image")
                    bad += 1
                    continue
                msg += (f"; .syx {f['bytes']} B verified, version {man['version']}, in-place gap "
                        f"{f['main']['inplace_min_gap']}, flash ends {f['flash_end']}")
            print(f"ok   {label}: {msg}")
            ok += 1
    print(f"{ok} ok, {bad} failed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
