# Porting the MKII mods to the Analog Rytm MK1

Source: the peer project `3_Claude_work/rytm-mods_MKII_peer` (Analog Rytm MKII,
OS 1.73). Target: Analog Rytm MK1, OS 1.73 (`1_official_firmware/Analog-Rytm_OS1.73.syx`,
sha256 9115c388...157c).

## Status

| mod | MK1 status | notes |
|---|---|---|
| 0000 shared runtime | **built, verified in software** | 6 symbols, all found and checked |
| 0002 euclid accents | **built, verified in software** | 31 symbols + 10 detours + 11 patches, all found; glyph code rewritten for the MK1's 13 x 11 icons |
| 0003 velocity humanise | **built, verified in software** | 4 detours + 1 patch, all found |
| 0004 LFO RND | **built, verified in software** | RANDOM build (excludes 0008); see below |
| 0006 compressor preview | not ported, disabled | not wanted |
| 0008 SMP CUT (new) | **built, verified in software** | written for MK1; see below |

"Verified in software" = `make verify` PASS, and every address checked against what
the MKII notes say the code does (evidence per symbol in `re/symbols.toml`). Nothing
has run on an MK1 yet.

## Why the port works

The MK1 and MKII 1.73 images are the same C++ code base, compiled separately. Code
that contains no absolute address is byte-identical, shifted by a delta that is
constant over long runs:

| region (MKII) | delta to MK1 | anchored by |
|---|---|---|
| pattern load/save 0x40008xxx | -0x120 | 0002's two persistence detours (unique byte matches) |
| param_apply_delta 0x400378xx | -0x1d2 | three detours |
| trig_fire 0x4009xxxx | -0x1fec | four detours |
| param text / get-set-by-id 0x400a8xxx | -0x2ce8 / -0x2cea | five detours, three jsr operands |
| euclid block 0x400c0xxx..0x400c3xxx | -0x2f6c | three detours |
| param_info / Bool Op glyphs 0x400ffxxx | -0x6e3e | the format and draw routines |

Everything else - RAM addresses, string and table pointers, routines far from any
anchor - was found by what references it (e.g. the icon set via its bitmap_set_make
call, EUCLID_CHANGE_INFO from the stock setter) and checked against the MKII
description. The per-symbol evidence is in `re/symbols.toml`.

### Differences found (each would have been a silent bug)

- MK1 container: one section. The bootstrap is embedded in MAIN OS and self-flashed
  (docs/HAZARDS.md). The build and verify tools now guard that range.
- Parameter info record: 88 B on MK1, 84 on MKII. Only 0002's (disabled) range probe
  used the stride; it now reads PARAM_INFO_STRIDE.
- Bool Operator glyphs: 13 x 11 on MK1, 17 x 12 on MKII. 0002 no longer carries its
  own 17 x 12 pixel art; it builds the accent glyphs at run time from the MK1's own
  (copy + 2 x 2 dot), so no stock artwork is carried in the mod.
- Cave layout: MKII cave1 (1760 B) held 0002 + 0000. On MK1 the matching gap is only
  1232 B and sits right after the embedded bootstrap, while MK1 cave2 is 2176 B. All
  three mods now live in cave2 (2140 B used, 36 B spare).

## 0008 SMP CUT - how it was placed

A new mod, not a port, built on what the MKII project's LFO RND (0004) proved:
a second page in a view's page list, dead parameter ids 1..2 renamed, and the
sound's free word (index 0) for storage.

v3 (optimised): no trig_fire hook any more. The audio side reads each voice's
owning track's settings straight from its live sound every block, without calls:
`*project_instance + 352 + 60 + 352*t` is the track's Sound, and Sound::get
(vtable +0x28, 0x401737a2) is just `return this->+16` - read fresh each block,
because Sound's setter can repoint it (e.g. on a kit load). The table is a1 + g
per step (a2, a3 derived per block on the EMAC), the popup's frequencies are 21
mantissas, both-on runs as one fused pass, and `diag = 1` builds a measuring
version (DMA timer 0; FUNC + LCT shows the peak share of the interrupt).

The audio side hooks the voice mixer `voice_out` (0x4010795e), which writes each
physical voice's digital layer into the DAC ring: 8 words per frame, 32 frames per
interrupt, slot `0x80000000 + (slot << 11)`, words 24-bit in bits 0..23. Both calls
in the audio interrupt (0x401189e8, 0x40119d8a) are repointed through
`voice_out_gate`, which runs the mixer and then filters those words in place, per
voice, with the settings of the track in `voice_owner` (0x40254e2c).

The filter math is modelled bit for bit in Python (fixed-point, the same Q31
truncation as the EMAC) and matches an ideal Butterworth to within 0.3 dB for an octave
either side of the cutoff, for cutoffs up to 2 kHz. Higher up, the slope beyond
the cutoff gets steeper than the analog ideal (about 2 dB more at an octave past a
5 kHz cutoff) - the usual digital (bilinear) cramping toward 24 kHz: more
attenuation, never less. The -3 dB point is exact at every step. Full-scale square waves at both extremes stay
bounded. The model is `tools/sim_cut.py` (needs numpy); the build itself checks that
the table file is current (`tools/gen_cut_tables.py --check`).

Space: code in `cave` (993 of 1232 B; the measuring build 1165), tables, state and
helpers in `cave3` (982 of 1024 B). Both pools were promoted to "probably-verified" for this, on the static
case in registry/allocations.toml; the first flash is their MK1 hardware run.

Silence skip: a voice whose 32 input words are all zero and whose filter state is
below 2048 is skipped and its state zeroed; in the model a 300 ms hit per second is
filtered in about a third of the blocks, and the difference from filtering every
block stays under -96 dBFS. The threshold is high because the integer filters park
on a small DC value (up to ~1300) after a sound ends.

To check on hardware: the page and knobs, that the sound changes as expected on a
sample track, that the settings survive save + power cycle, and whether the UI
stays responsive with many filters on.

## 0004 LFO RND - how it was ported

Done with the MKII stock image (`Analog-Rytm_MKII_OS1.73.syx`, sha256 8ad67108...,
MAIN OS 28d9ef40...). Both MAIN OS images were disassembled, and `tools/xmatch.py`
matched every MKII address the mod uses to its MK1 twin by voting over normalised
instruction windows; each result was then read side by side, and an independent
review pass re-checked every site, expect string, frame offset and RAM address.

- 13 detours (MKII had 14 - see the title hook below), 24 patches, 22 symbols;
  all in `re/symbols.toml` with the MKII address and the evidence.
- The 469 ROM parameter records are identical on both (kind, container index,
  range, modflags, names), so the sixteen destinations and ids 1..4 carry over.
- RAM: the trig flags are at 0x8000a9e8 (MKII 0x8000e508) and the effective
  parameter array at 0x800062c0 (MKII 0x8000f7a8); stride 0x54 on both.

Differences from MKII:

- **No title hook.** MKII's page view pushes a header title on activate, and the
  mod re-pushed it after the page key's cycle. MK1's page_view_activate
  (0x400376ae) pushes none, so that detour is dropped.
- **param_knob_draw** saves one more register on MK1 and reads two more argument
  slots; x/y/h are where MKII has them, so only the re-emitted prologue changes.
- **Page 11**, not 12, and page_info's displaced compare is `moveq #10`.
- **Space**: code in `cave` (1092 of 1232 B), data, strings and state in `cave3`
  (221 of 1024 B) - the two pools 0008 uses, free because the two exclude each other.
- **The destination list** is 73 px wide at x = 49 on MK1; the mod moves it to x = 0.

**Why two builds.** 0004 and 0008 both keep their settings in sound index 0, the
one 16-bit word per sound that the stock OS saves, loads, copies and undoes by
itself (MKII project, `re/subsystems/lfo.md` Q8/Q9), and each needs all 16 bits.
The other spare storage (slots 42..47) is zeroed by every stock save and has no
place in the live sound. So the default build keeps SMP CUT and `make random`
builds LFO RND instead.

To check on hardware: as MKII's design.md, plus that the list sits on the left
of the MK1 screen and that "LFO RND" fits where the MK1 prints page names.

## What 0006 still needs

**0006 compressor preview**: the hardest by far. 3.8 KB, a model calibrated against
the MKII's analog compressor path and USB audio, SRAM audio-engine addresses, and a
128-column scrolling trace drawn for a 128 x 64 screen. On the MK1 (122-pixel-wide
screen, different analog board) the drawing must be redesigned and the model
re-calibrated with the MK1's own USB/Overbridge captures. Treat as a new mod that
reuses the MKII design, not a port.

**Porting more MKII work.** 0002/0003 were located from the MKII project's notes and
detour bytes alone; 0004 with the MKII stock `.syx` (the manufacturer's free
download) and `tools/xmatch.py`, which matches the two images function by function.
Use the latter for anything further - it is much faster and leaves evidence.

## Would a loader be feasible? Yes - two stages

1. **Now:** this project's `tools/build.py --mods ...` already is a command-line
   loader - pick mods, it checks conflicts and builds a verified `.syx`. A
   double-click launcher (like the Digitakt's elekloader.app) around it is small work.
2. **Properly: add the Rytm MK1 to elekloader** (the loader the Digitakt mods use).
   Its DEVICES.md lists what a new device needs; for the MK1:
   - device profile: sysex id 0x07, MAIN OS = section 3 at 0x40000400, ColdFire
     (the ISA decoder already exists), no trailer - all known now;
   - an ELE2 container writer (elekloader writes ELE3 today) - the format is simple
     and the null-repack test above already pins what stock looks like;
   - `stage` / `flash_at` / `flash_limit`: read out of the embedded bootstrap, which
     is right here in MAIN OS;
   - free RAM areas for mod code (DDR above .bss end 0x427a6310 and below the stack
     at 0x48000000 is the place to look);
   - a Rytm **core** mod: the hook bus (tick, draw, key, encoder, SETTINGS, audio
     render). The Rytm runs the same framework as the Digitakt, so the
     sites are findable; this is the largest piece;
   - the mods rewritten as linkable `.elemod`s.

   The payoff on the MK1 is bigger than on the Digitakt: the loader copies mod code
   into free DDR at boot, so the cave shortage that blocks 0006 disappears,
   and mods combine with the Digitakt-style tooling you already use.
