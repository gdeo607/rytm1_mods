# Flashing - Analog Rytm MK1

The MK1 takes one format, a `.syx`, sent like any OS update. Back up your projects
first (Transfer can back up the +Drive), and keep the stock file at hand:
`1_official_firmware/Analog-Rytm_OS1.73.syx`.

## Normal route (Transfer app, USB)

1. Connect over USB, power on.
2. Transfer > CONNECTION: set MIDI IN and OUT to the Analog Rytm.
3. Transfer > DROP: drag the `.syx` on.
4. Press `[YES]` on the device to confirm.

The unit restarts by itself. This path runs inside MAIN OS, so it needs a MAIN OS
that still boots. **Do not power off during the first boot afterwards** (see
HAZARDS.md: the MK1's bootstrap upgrade runs from inside MAIN OS).

## Recovery route (STARTUP menu, DIN MIDI only)

1. Hold `[FUNC]` while powering on.
2. `[TRIG 4]` enters OS UPGRADE.
3. Transfer > CONNECTION: "LEGACY OS UPGRADE mode", select the stock `.syx`, UPGRADE.

Served by the bootstrap in flash, not by MAIN OS, so it still comes up after a MAIN
OS that does not boot. It needs the DIN MIDI port (a USB-MIDI interface into the
Rytm's MIDI IN), not USB.

## Order for a first MK1 session

1. `2_builds/AR1_OS1.73_control.syx` - optional, 2 minutes. Stock code, only
   repacked by our tool. If it boots and plays, the packer is proven on your unit,
   so any later problem is a mod, not the file format.
2. `0_Latest_Custom_OS/AR1_OS1.73_0000_0002_0003.syx` - the mods. Then run through
   the test list in 0_Latest_Custom_OS/README.txt.

## Downgrades

The device does not support going back to an older OS ("Downgrade not possible").
Both builds carry version 1.73, the same as stock 1.73, so returning to stock is a
same-version reinstall - the manufacturer allows reinstalling the current OS, but that has
not been tried with these builds yet. The STARTUP-menu route above is the fallback
either way.
