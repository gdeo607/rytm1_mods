# User manual - Analog Rytm MK1

What each mod in the MK1 build does on the device and how to use it. For building
see `README.md`, for installing `docs/FLASHING.md`, and read `docs/HAZARDS.md`
before flashing.

The build is `AR1_OS1.73_0000_0002_0003_0008.syx`: stock MK1 OS 1.73 with the mods
below; everything not mentioned behaves as stock. The unit still reports OS 1.73.

| mod | where | what |
|---|---|---|
| 0002 | TRIG > euclidean page, OP | euclid sets accents on your trigs instead of placing trigs |
| 0003 | TRIG page, FUNC + VEL | per-track random velocity |
| 0008 | FILTER key, pressed twice | SMP CUT page: low cut and high cut per track |

0000 is the shared code the others call into. It has no controls.

Status on MK1: **built and verified in software, not yet run on an MK1.** 0002 and
0003 were confirmed on an MKII by the author of the original project; 0008 is new; the
MK1 port has been checked address by address against the MK1 image (PORTING.md),
but only hardware can confirm it. The MKII mods 0004 (LFO RND) and 0006 (compressor
preview) are not in this build yet - see PORTING.md.

MK1-specific: the MK1 draws the Bool Operator glyphs smaller (13 x 11 pixels
instead of 17 x 12), and the accent versions are made from the MK1's own glyphs
with a 2 x 2 dot in the top-right corner.

## 0002 - Euclidean accents

Normally the euclidean generator decides which steps play. With this mod it can
instead leave the pattern's trigs alone and mark some of them with ACCENT: the
grid says when, euclid says which hits are accented.

**Use.** On the euclidean page, the Bool Operator (OP) now has eight values instead
of four:

| value | icon | behaviour |
|---|---|---|
| OR, XOR, AND, SUB | stock gate glyph | stock euclidean |
| OR\*, XOR\*, AND\*, SUB\* | the same glyph with a small dot, top right | accent mode, same operator |

In accent mode:

- Only steps with a trig in the grid play. Euclid adds nothing.
- A trig on a step where the euclidean pattern has a hit plays accented.
- Accents you set by hand stay; euclid only ever adds accent.
- Turning euclid off with FUNC held bakes the result: the accents are written
  into the pattern. Turning it off without FUNC leaves the pattern as it was,
  as stock does.

The setting is per track and survives save, power cycle and reload.

**On stock firmware** a pattern saved with an accent-mode track loads with euclid
off on that track.

## 0003 - Velocity humanise

Adds a random offset to the velocity of every trig on a track.

**Use.** On the TRIG page, hold FUNC and turn the VEL knob. While FUNC is held
the label reads RND and the knob selects the amount N:

    0, 1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 24, 32, 40, 48, 64

The sixteen settings sit on evenly spaced positions of the knob. Each trig then
plays at its velocity plus a random amount between -N and +N, kept within
1..127. Release FUNC and VEL behaves as stock. N = 0 is off.

The amount is per track and stored with the pattern. It needs 0002, which saves
it; the two are always built together.

**Limitations**

- Editing the amount may not mark the project as modified, so the device may
  not prompt you to save. Save explicitly.

## 0008 - SMP CUT (low cut / high cut)

A second FILTER page for cleaning up a mix: a low cut and a high cut on each
track's **sample**.

**Use.** Press FILTER, then FILTER again: the page is SMP CUT. Press FILTER again to
go back.

| knob | label | what |
|---|---|---|
| A | LCT | low cut (removes lows): OFF at 0, then 20 Hz .. 20 kHz |
| B | HCT | high cut (removes highs): 20 Hz .. 20 kHz, OFF at 127 |

Turning a knob shows the cutoff in the popup ("120", "1.2k", "OFF"). Both are
12 dB/octave (Butterworth). The range is 64 steps, about 2 semitones each, spread
evenly in pitch. Set LCT above HCT and you get a band-pass.

The settings are per track, stored in the track's sound, and take effect as you
turn the knob.

**What it filters, and what it cannot.** On the Rytm the filter, amp and mixer are
analog. What the firmware can reach is each voice's *digital* layer - the sample,
and the digital noise some machines add - which it sends through a DAC into the
voice's analog path, before the analog filter. SMP CUT filters that. The analog
synthesis part of a machine is not affected. On a sample-only track (machine off,
or its level at 0) it acts on the whole sound.

**Things to know**

- A full-scale sample with a strong low cut can clip slightly: the filter's
  overshoot is clamped at full scale.
- Tracks that share a voice (RS/CP, MT/HT, CH/OH, CY/CB) use the settings of whichever
  track played last on that voice.
- Settings follow the sound instantly: a kit or project load, a sound from the
  pool, copy/paste - the audio side reads each track's sound every block.
- A filter only costs processor time while its voice is actually sounding (plus a
  short tail): a silent voice is detected and skipped. With both filters on, the
  two run as one fused pass. While sounding, each filter costs roughly 1% of the
  audio interrupt's time by instruction count. To MEASURE it, flash the measuring
  build (2_builds/..._diag.syx): hold FUNC and turn LCT - the popup shows the
  filters' peak share of the audio interrupt since you last looked (e.g. "2.4%").
  In that build the LCT/HCT popups otherwise work as normal.
- **Not yet verified: that the settings survive saving the kit and a power cycle.**
  They live in the sound's one unused parameter slot; whether the MK1 saves that
  slot has to be tested on the unit.
- Parameter locks are not supported for LCT/HCT.
- It cannot be in the same build as the MKII project's LFO RND mod (0004): both use
  that same slot.
