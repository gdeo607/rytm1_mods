# Hazards - Analog Rytm MK1

Read before flashing. The MKII project's hazards (3_Claude_work/rytm-mods_MKII_peer/
docs/HAZARDS.md) all apply; this file says what is different on the MK1, and the
first item is new and the most important.

## The bootstrap lives INSIDE MAIN OS - never write into it

On the MKII the bootstrap (the STARTUP menu and the DIN-MIDI OS UPGRADE that survive
a bad OS) is a separate section of the `.syx`, which the project simply never
rebuilds. **The MK1 `.syx` has only one section, MAIN OS, and the bootstrap image is
carried inside it:**

- `0x4028c708` holds the embedded bootstrap's version words, `0x4028c710..0x402a1b24`
  its image (87,068 B, ending in its USB descriptors).
- At every boot, the startup code (`0x400005aa`) compares that version with the one
  in flash at `0x1fff8`. If the embedded one is newer, `0x4011a738` shows BOOTSTRAP
  UPGRADE, erases the bootstrap sectors and writes the embedded image into them.

So a mod byte anywhere in that range could one day be written into the recovery
path itself - by this build, or by a later one whose version word is newer. The
rules that follow from it:

- No pool may overlap `0x4028c708..0x402a1b24`. The nearest pool, `cave`, starts
  12 bytes past its end and is unused.
- `tools/build.py` refuses to write a build whose embedded image differs from stock,
  and `tools/verify.py` checks it again on the `.syx` it reads back
  ("embedded bootstrap image unchanged"). Keep both checks.
- Do not power off during the first boot after flashing. If your unit was on an OS
  older than 1.73, that boot may be a genuine bootstrap upgrade (with our builds it
  is the manufacturer's own, unmodified image that gets written).

## The recovery route still exists

Hold FUNC while powering on for the STARTUP menu, TRIG 4 for OS UPGRADE, then send
the stock `1_official_firmware/Analog-Rytm_OS1.73.syx` from the Transfer app's
LEGACY OS UPGRADE mode over DIN MIDI. That menu is drawn by the bootstrap in flash,
not by MAIN OS, which is why the rule above matters.

## The container writer needed one fix for MK1

The vendored elektron-firmware-tool pads ELE2 containers to 2 bytes; the stock MK1
file pads to 4, so a "no change" rebuild came out 2 bytes shorter than stock. The
content was identical, but the null-repack self-check failed. `tools/eft-ele2-align4.patch`
(applied by `make setup`) pads to 4, and the untouched stock file now rebuilds byte
for byte. Every MK1 build uses the patched tool.

## Assembler target: ColdFire V4, EMAC, NO FPU

`-mcpu=5475 -mno-float` (from re/symbols.toml [meta]). The MK1 image uses mvz/mvs,
sats, mov3q and the EMAC unit, and no floating point in code. With -mno-float an FPU
instruction in a stub is an assembly error instead of a crash on the unit.

## Different geometry, same code

The MK1 and MKII firmware are one code base, and most routines are byte-identical
- but not all data is. Found while porting, and each would have been a silent bug:

- The parameter info record is 88 bytes on MK1, 84 on MKII (`PARAM_INFO_STRIDE`).
- The Bool Operator glyphs are 13 x 11 on MK1, 17 x 12 on MKII.
- The MK1 screen is smaller: the firmware centres text on a 122-pixel-wide display
  (MKII: 128 x 64). Anything that draws its own pixels (0004's knob art, all of
  0006) has to be redesigned, not re-addressed.
- RAM layout differs throughout: every 0x41xxxxxx / 0x8000xxxx address in a stub
  has to be found again.

## Verify before flashing, every time

`make verify` asserts on MK1:

- stock `.syx` rebuilds byte-identically (null repack)
- MAIN OS is unchanged in size and round-trips out of our `.syx`
- the embedded bootstrap image is stock, and the `.syx` carries MAIN OS only
- every byte that differs from stock lies inside a registry claim
- every detour jumps to its resolved entry, inside its own cave, and rejoins stock
  past exactly what it displaced
- no stub's movem overruns its stack frame

## Status means what it says

`built` means the image assembled. Only `hardware-verified` counts, and only for the
exact image flashed. MKII hardware results are evidence for the MK1 port, not proof.
