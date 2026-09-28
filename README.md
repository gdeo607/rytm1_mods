# rytm1_mods

Firmware modifications for the Analog Rytm MK1, OS 1.73 - a port of the MKII
project `rytm-mods` (kept unchanged next to this folder as `rytm-mods_MKII_peer`),
with the same conventions: every build starts from the pinned stock image and
rebuilds from source; the patch sources, the symbol map and the allocation registry
are the project, the `.syx` is an artifact.

Unofficial. Not affiliated with or endorsed by the manufacturer. Flashing modified
firmware is at your own risk; keep the stock `.syx` for recovery (docs/FLASHING.md).

## Layout

| path | what |
|---|---|
| `stock/` | the stock MK1 1.73 `.syx` and its checksum. Never written to. |
| `re/symbols.toml` | the MK1 symbol map: every address, the MKII address it ports, and the evidence |
| `registry/allocations.toml` | cave pools and every claim on them, detour and patch sites (MK1 addresses) |
| `mods/NNNN-slug/` | one modification: manifest, stub source, design notes |
| `tools/` | build, layout check, verify, symbol generation; `xmatch.py` (MKII -> MK1 address matcher); `gen_cut_tables.py` (0008's filter tables); `eft-ele2-align4.patch` |
| `vendor/` | elektron-firmware-tool, fetched and patched by `make setup` |
| `docs/` | MANUAL (what the mods do), FLASHING, HAZARDS (read it) |
| `PORTING.md` | what is ported, how, what differs from MKII, what is left, the loader question |
| `build/` | artifacts |

## Build

Prerequisites: Python 3.11+, git, make, a C compiler, and m68k binutils
(`brew install m68k-elf-binutils` on macOS, `apt install binutils-m68k-linux-gnu`
on Debian/Ubuntu - either prefix is found automatically).

    make setup     # clone the container tool at its pinned commit, apply the MK1 patch, build it
    make verify    # the SMP CUT build: 0000 + 0002 + 0003 + 0008, and assert the result
    make random    # the RANDOM build: 0000 + 0002 + 0003 + 0004, and assert the result
    make control   # the pipeline test: no mods, stock code repacked

`make verify` produces `build/AR1_OS1.73_0000_0002_0003_0008.syx`, `make random`
`build/AR1_OS1.73_0000_0002_0003_0004.syx`. There are two builds because 0004 and
0008 keep their settings in the same free word of the sound - the only one the stock
OS saves, loads, copies and undoes by itself - so they can never share an image.

A subset, for bisecting on hardware:

    python3 tools/build.py --mods 0000-shared 0002-euclid-accents

## The MK1 container

One section, not five:

| id | name | size | load base | we touch it |
|---|---|---|---|---|
| 3 | MAIN OS | 2,824,228 | 0x40000400 | yes - but never 0x4028c708..0x402a1b24, the embedded bootstrap |

## Mods

| id | title | MK1 status |
|---|---|---|
| 0000 | The shared runtime other mods call into | built |
| 0002 | Euclidean generator places accents instead of trigs | built |
| 0003 | Per-track random velocity offset | built |
| 0004 | LFO RND: two per-sound random modifiers on a second LFO page | built (RANDOM build; excludes 0008) |
| 0006 | Compressor gain-reduction preview | not ported (disabled, not wanted) |
| 0008 | SMP CUT: low cut / high cut per track on a second FILTER page (new, MK1 only) | built (default build; excludes 0004) |

Status ladder: `re-only` -> `built` -> `hardware-verified`, plus `retracted`. Only
`hardware-verified` counts, and MKII results do not transfer automatically.
