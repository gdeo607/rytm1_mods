        | Mod 0008 - SAMPLE CUT: a second FILTER page with a low cut and a high cut
        | for each track's digital layer (the sample and the digital noise), for
        | cleaning up a mix.
        |
        | Where it acts. On the Rytm everything after the sound source is analog -
        | the multimode filter, the amp, the mixer - so firmware cannot filter a
        | track's full output. What the ColdFire does produce is each voice's digital
        | layer: VOICE_OUT (0x4010795e) sums the sample engine's buffers and writes
        | one 24-bit word per voice per frame into the DAC ring, and from the DAC
        | that signal enters the voice's analog path, BEFORE the analog filter. This
        | mod filters those words in place, right after VOICE_OUT writes them.
        |
        | Settings: two per track, in the sound's free parameter word (sound index 0,
        | live sound +0x14 - the word the MKII project's LFO RND mod used, which is
        | why the two exclude each other):
        |
        |   bits 0..6   LOW CUT   0 = off, 1..127 = 20 Hz .. 20 kHz
        |   bits 8..14  127 - HIGH CUT, so 0 = off (a HIGH CUT of 127)
        |
        | A stored 0 is "both off", so every existing sound starts unfiltered.
        | Parameter ids 1 and 2 are dead Error records, renamed by registry patches.
        |
        | The filter: a trapezoidal (zero-delay) state-variable filter, Butterworth,
        | 12 dB/octave, one for the low cut (its high-pass output) and one for the
        | high cut (its low-pass output), per physical voice. Coefficients come from
        | tables.inc (tools/gen_cut_tables.py), 64 log-spaced steps from 20 Hz to
        | 20 kHz; a knob value v uses step v >> 1.
        |
        | Cost (v3): nothing for a voice with both filters off or with nothing
        | sounding; with both on, one fused pass instead of two full ones. The audio
        | side reads each track's settings straight from its live sound every block
        | (plain memory reads, no calls), so kit loads, sound changes and edits
        | reach it at once. P_DIAG = 1 builds a measuring version: FUNC + LCT's
        | popup shows the filter's peak share of the audio interrupt.

        .include "symbols.inc"
        .include "shared.inc"

        .equ    PAGE_FILT,      5
        .equ    PAGE_CUT,       11                | MK1 pages are 0..10
        .equ    ID_LC,          1
        .equ    ID_HC,          2
        .equ    OFF_PARAMS,     0x14              | live sound parameter array
        .equ    PROJ_TRACKSEL,  48
        .equ    TRACKS,         12
        .equ    VOICES,         8
        .equ    FRAMES,         32                | samples per voice per interrupt
        .equ    TX_STRIDE,      64                | bytes between frames in the DAC ring
        .equ    SAT_HI,         0x07ffffff        | the working scale's full scale
        .equ    KQ,             0x3504f334        | sqrt(2) - 1, Q31
        .equ    SETTLED,        2048              | silence threshold on the states
        .equ    DTCN0,          0xfc07000c        | DMA timer 0, free-running (stock reads it too)
        | The live sound of track t, as shared_sound_of finds it, in plain reads:
        | project (*project_instance) + 352 is the kit, kit + 60 + 352*t the track's
        | Sound, and Sound::get (vtable +0x28, 0x401737a2) is `return this->+16`.
        .equ    SOUND0,         352+60            | the kit's first Sound, from the project
        .equ    SOUND_STRIDE,   352
        .equ    SOUND_LIVE,     16

        .text

        | ------------------------------------------------------------------
        | page_info, answering PAGE_CUT.
        | Entered by a jmp at the entry: (%sp) return, 4(%sp) the page id.
        | ------------------------------------------------------------------
        .align  2
page_info_gate:
        moveq   #PAGE_CUT,%d0
        cmp.l   4(%sp),%d0
        bne.s   1f
        lea     page_cut,%a0
        move.l  %a0,%d0
        rts
1:      moveq   #10,%d1                           | displaced
        move.l  %sp@(4),%d0                       | displaced
        jmp     page_info_resume

        | ------------------------------------------------------------------
        | page_get_value for ids 1..2: the dials.
        | Entered by a jmp at the entry: (%sp) return, 4 view, 8 id, 12 lock.
        | Answers 8.8 on the 0..127 scale.
        | ------------------------------------------------------------------
        .align  2
get_gate:
        move.l  8(%sp),%d0
        subq.l  #ID_LC,%d0
        moveq   #1,%d1
        cmp.l   %d1,%d0
        bhi.s   9f
        jsr     word_sync
        move.l  8(%sp),%d1
        jsr     value_of
        lsl.l   #8,%d0
        rts
9:      lea     %sp@(-12),%sp                     | displaced
        moveml  %d2-%d3/%a2,%sp@                  | displaced
        jmp     page_get_value_body

        | ------------------------------------------------------------------
        | param_apply_delta for ids 1..2: the knobs.
        |
        | Reached by a jmp over `mvzb %d3,%d3; movel %a2@(116),%sp@-`, past the
        | prologue (and past 0003's gate, which rejoins here): %sp@(0..11) holds
        | d2/d3/a2, a2 is the view, %sp@(20) the id, %sp@(24) the delta in 8.8.
        | Handling the id and returning means stock never makes a p-lock for it.
        | The audio side reads the sound word itself, so writing it is enough.
        | ------------------------------------------------------------------
        .align  2
delta_gate:
        move.l  %sp@(20),%d0
        subq.l  #ID_LC,%d0
        moveq   #1,%d1
        cmp.l   %d1,%d0
        bhi.w   9f
        move.l  %sp@(24),%d2
        asr.l   #8,%d2                            | whole steps, sign preserved
        beq.s   7f
        jsr     word_sync                         | d0 word, a0 sound
        move.l  %a0,%d1
        beq.s   7f                                | no sound
        move.l  %d0,%d3                           | the old word
        move.l  %sp@(20),%d1
        jsr     value_of                          | d0 = shown value
        add.l   %d2,%d0
        bpl.s   1f
        clr.l   %d0
1:      moveq   #127,%d1
        cmp.l   %d1,%d0
        ble.s   2f
        move.l  %d1,%d0
2:      moveq   #ID_HC,%d1
        cmp.l   %sp@(20),%d1
        beq.s   3f
        and.l   #0x7f00,%d3                       | low cut: bits 0..6
        or.l    %d0,%d3
        bra.s   4f
3:      moveq   #127,%d1                          | high cut: 127 - v in bits 8..14
        sub.l   %d0,%d1
        lsl.l   #8,%d1
        and.l   #0x007f,%d3
        or.l    %d1,%d3
4:      move.w  %d3,OFF_PARAMS(%a0)
        move.l  %d3,-(%sp)                        | the new word
        move.l  %sp@(24),-(%sp)                   | the id
        jsr     shared_mark_changed               | so it is saved with the sound
        move.l  %a2,(%sp)                         | the view
        jsr     view_invalidate                   | redraw now
        addq.l  #8,%sp
7:      movem.l (%sp),%d2-%d3/%a2                 | param_apply_delta's epilogue
        lea     12(%sp),%sp
        rts
9:      mvzb    %d3,%d3                           | displaced
        move.l  %a2@(116),-(%sp)                  | displaced
        jmp     param_apply_delta_track

        | ------------------------------------------------------------------
        | param_value_text for ids 1..2: the popup, "OFF" or the cutoff.
        |
        | Reached by a jmp over `movel %sp@(32),%d2; movel %sp@(36),%d3`, past the
        | prologue (and past 0002's and 0003's text gates): %sp@(0..19) holds
        | d2-d4/a2-a3, d4 is the id, %sp@(36) the output buffer.
        | ------------------------------------------------------------------
        .align  2
text_gate:
        move.l  %d4,%d0
        subq.l  #ID_LC,%d0
        moveq   #1,%d1
        cmp.l   %d1,%d0
        bhi.w   9f
        .if     P_DIAG
        moveq   #ID_LC,%d0
        cmp.l   %d4,%d0
        bne.s   10f
        jsr     shared_func_held
        beq.s   10f
        move.l  %sp@(36),%a1
        jsr     diag_text
        bra.w   5f
10:
        .endif
        jsr     word_sync
        move.l  %d4,%d1
        jsr     value_of                          | d0 = 0..127
        move.l  %sp@(36),%a1
        moveq   #ID_HC,%d1
        cmp.l   %d4,%d1
        beq.s   1f
        tst.l   %d0                               | low cut 0 is off
        beq.w   6f
        bra.s   2f
1:      moveq   #127,%d1                          | high cut 127 is off
        cmp.l   %d1,%d0
        beq.w   6f
2:      jsr     fmt_hz
        bra.s   5f
6:      move.b  #0x4f,(%a1)+                      | OFF
        move.b  #0x46,(%a1)+
        move.b  #0x46,(%a1)+
5:      clr.b   (%a1)
        movem.l (%sp),%d2-%d4/%a2-%a3             | param_value_text's epilogue
        lea     20(%sp),%sp
        rts
9:      movel   %sp@(32),%d2                      | displaced
        movel   %sp@(36),%d3                      | displaced
        jmp     param_value_text_args

        | ------------------------------------------------------------------
        | voice_out_gate(txbase): both calls to VOICE_OUT in the audio interrupt
        | are repointed here. Runs VOICE_OUT, then filters what it wrote.
        | C convention: d0/d1/a0/a1 free, everything else kept.
        | ------------------------------------------------------------------
        .align  2
voice_out_gate:
        move.l  4(%sp),-(%sp)
        jsr     voice_out
        addq.l  #4,%sp
        | falls into cut_process with the same (return, txbase) frame

        | ------------------------------------------------------------------
        | cut_process(txbase): per physical voice, the owning track's cut filters
        | over its 32 words of this interrupt's slot. MACSR is 0x20 here
        | (fractional, no saturation) and is left so; acc0 is left clear.
        |
        | Frame: 0..43 saved registers, 44 voice, 48 settings word, 52 txbase
        | + 4*voice, 56 (P_DIAG) start time; the caller's txbase at 64. a4 is
        | the loops' mode.
        | ------------------------------------------------------------------
cut_process:
        lea     -60(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        .if     P_DIAG
        move.l  DTCN0,%d0
        move.l  %d0,56(%sp)
        .endif
        clr.l   44(%sp)
        lea     voice_owner,%a5
        lea     cut_state,%a6

1:      move.l  44(%sp),%d0
        lsl.l   #2,%d0
        add.l   64(%sp),%d0                       | txbase + 4*voice
        move.l  %d0,52(%sp)                       | this voice's first word
        mvzb    (%a5)+,%d0                        | the track playing on this voice
        moveq   #TRACKS-1,%d1
        cmp.l   %d1,%d0
        bhi.w   40f
        move.l  #SOUND_STRIDE,%d1
        mulu.l  %d1,%d0
        move.l  project_instance,%d1
        beq.w   40f                               | no project yet
        add.l   %d1,%d0
        move.l  %d0,%a0
        move.l  SOUND0+SOUND_LIVE(%a0),%d0        | the track's live sound
        beq.w   40f
        move.l  %d0,%a0
        mvzw    OFF_PARAMS(%a0),%d0               | the settings, live
        beq.w   40f                               | both off
        move.l  %d0,48(%sp)
        | A filter that is off keeps no state, so switching it on starts clean -
        | and a stale state cannot hold off the silence test below.
        moveq   #0x7f,%d1
        and.l   %d0,%d1
        bne.s   11f
        clr.l   (%a6)                             | low cut off
        clr.l   4(%a6)
11:     lsr.l   #8,%d0
        moveq   #0x7f,%d1
        and.l   %d0,%d1
        bne.s   12f
        clr.l   8(%a6)                            | high cut off
        clr.l   12(%a6)
12:     | Silence: when the voice's 32 words are all zero and every state is
        | below SETTLED (128 DAC steps, -96 dBFS), stop: zero the state and skip.
        | The threshold is that high because the filters' integer arithmetic
        | leaves them parked on a small DC value after a sound ends - up to about
        | 1300 at the lowest cutoffs, a few DAC steps of output.
        move.l  52(%sp),%a0
        moveq   #FRAMES,%d1
        clr.l   %d2
13:     or.l    (%a0),%d2
        lea     TX_STRIDE(%a0),%a0
        subq.l  #1,%d1
        bne.s   13b
        tst.l   %d2
        bne.s   2f                                | sounding
        move.l  %a6,%a1
        move.l  #SETTLED,%d6
        moveq   #4,%d3
18:     move.l  (%a1)+,%d0
        bpl.s   19f
        neg.l   %d0
19:     cmp.l   %d6,%d0
        bcc.s   2f                                | still ringing
        subq.l  #1,%d3
        bne.s   18b
40:     clr.l   (%a6)                             | off, or settled: nothing to do
        clr.l   4(%a6)
        clr.l   8(%a6)
        clr.l   12(%a6)
        bra.w   5f

2:      move.l  48(%sp),%d0
        moveq   #0x7f,%d7
        and.l   %d0,%d7                           | low cut
        lsr.l   #8,%d0
        moveq   #0x7f,%d1
        and.l   %d0,%d1                           | 127 - high cut
        beq.s   30f                               | low cut only
        tst.l   %d7
        beq.s   31f                               | high cut only
        | both: high-pass ring -> working scale in place, low-pass back to the ring
        move.l  %d7,%d0
        lsr.l   #1,%d0
        jsr     coefs
        move.l  52(%sp),%a0
        move.l  %a6,%a2
        move.l  %a6,%a4                           | fused (any non-zero)
        bsr.w   hp_loop
        move.l  48(%sp),%d0
        lsr.l   #8,%d0
        moveq   #0x7f,%d1
        and.l   %d1,%d0
        moveq   #127,%d1
        sub.l   %d0,%d1
        move.l  %d1,%d0
        lsr.l   #1,%d0
        jsr     coefs
        move.l  52(%sp),%a0
        lea     8(%a6),%a2
        move.l  %a6,%a4
        bsr.w   lp_loop
        bra.s   5f
30:     move.l  %d7,%d0                           | low cut only
        lsr.l   #1,%d0
        jsr     coefs
        move.l  52(%sp),%a0
        move.l  %a6,%a2
        sub.l   %a4,%a4
        bsr.w   hp_loop
        bra.s   5f
31:     moveq   #127,%d0                          | high cut only
        sub.l   %d1,%d0
        lsr.l   #1,%d0
        jsr     coefs
        move.l  52(%sp),%a0
        lea     8(%a6),%a2
        sub.l   %a4,%a4
        bsr.w   lp_loop

5:      lea     16(%a6),%a6
        addq.l  #1,44(%sp)
        moveq   #VOICES,%d0
        cmp.l   44(%sp),%d0
        bne.w   1b
        .if     P_DIAG
        | the share of the interval since the previous interrupt, in 0.1 %
        move.l  56(%sp),%d1                       | start
        move.l  DTCN0,%d0
        sub.l   %d1,%d0                           | our run
        move.l  diag_last,%d2
        move.l  %d1,diag_last
        sub.l   %d2,%d1                           | the interval
        beq.s   6f
        cmp.l   #0x00400000,%d0
        bcc.s   6f                                | a stall, not a measurement
        move.l  #1000,%d3
        mulu.l  %d3,%d0
        divu.l  %d1,%d0
        cmp.l   diag_peak,%d0
        bls.s   6f
        move.l  %d0,diag_peak
6:
        .endif
        movem.l (%sp),%d2-%d7/%a2-%a6
        lea     60(%sp),%sp
        rts

        | ------------------------------------------------------------------
        | The two loops, over a voice's 32 words (a0, stride 64), with the
        | coefficients in d4-d6 and the state {ic1, ic2} at a2. a4 = 0: ring in,
        | ring out. a4 != 0 is the fused path when both filters are on: hp_loop
        | leaves the high-pass on the working scale in place and lp_loop takes it
        | from there - one clamp, pack and unpack per sample fewer. The words hold
        | working-scale values only between the two loops, inside this interrupt,
        | before DMA reaches the slot.
        |
        | Per sample, with v0 the input on a scale of 2^27 = full scale:
        |   v3 = v0 - ic2
        |   v1 = a1*ic1 + a2*v3
        |   v2 = ic2 + a2*ic1 + a3*v3
        |   ic1 = 2*v1 - ic1,  ic2 = 2*v2 - ic2
        |   low-pass = v2,  high-pass = v0 - k*v1 - v2   (k = sqrt 2 = 1 + KQ)
        | The ring's words are 24-bit two's complement in bits 0..23 (VOICE_OUT
        | stores its Q31 sum >> 8, logical): << 8 recovers Q31, >> 4 gives the
        | working scale and 3 bits of headroom. Clobbers d0-d3/d7/a0-a3; a4 is the mode.
        | ------------------------------------------------------------------
        .macro  UNPACK
        move.l  (%a0),%d0
        lsl.l   #8,%d0
        asr.l   #4,%d0                            | v0
        .endm

        .macro  PACK
        move.l  #SAT_HI,%d1                       | clamp to full scale
        cmp.l   %d1,%d0
        ble.s   2f
        move.l  %d1,%d0
        bra.s   3f
2:      not.l   %d1                               | -2^27
        cmp.l   %d1,%d0
        bge.s   3f
        move.l  %d1,%d0
3:      lsl.l   #4,%d0                            | back the way VOICE_OUT stores it
        lsr.l   #8,%d0
        .endm

        | HP core: d0 = v0 in, d0 = high-pass out; keeps d2/d3 (ic1, ic2)
        .macro  HP
        move.l  %d0,%d1
        sub.l   %d3,%d1                           | v3
        mac.l   %d4,%d2,%acc0
        mac.l   %d5,%d1,%acc0
        movclr.l %acc0,%a1                        | v1
        mac.l   %d5,%d2,%acc0
        mac.l   %d6,%d1,%acc0
        movclr.l %acc0,%d1
        add.l   %d3,%d1                           | v2
        mac.l   %a3,%a1,%acc0
        movclr.l %acc0,%a2                        | KQ * v1
        sub.l   %d1,%d0
        sub.l   %a1,%d0
        sub.l   %a2,%d0                           | high-pass
        move.l  %a1,%a2
        adda.l  %a1,%a2
        suba.l  %d2,%a2
        move.l  %a2,%d2                           | ic1
        move.l  %d1,%a2
        adda.l  %d1,%a2
        suba.l  %d3,%a2
        move.l  %a2,%d3                           | ic2
        .endm

        | LP core: d0 = v0 in, d0 = low-pass out
        .macro  LP
        sub.l   %d3,%d0                           | v3
        mac.l   %d4,%d2,%acc0
        mac.l   %d5,%d0,%acc0
        movclr.l %acc0,%a1                        | v1
        mac.l   %d5,%d2,%acc0
        mac.l   %d6,%d0,%acc0
        movclr.l %acc0,%d1
        add.l   %d3,%d1                           | v2 = low-pass
        move.l  %a1,%a2
        adda.l  %a1,%a2
        suba.l  %d2,%a2
        move.l  %a2,%d2                           | ic1
        move.l  %d1,%a2
        adda.l  %d1,%a2
        suba.l  %d3,%a2
        move.l  %a2,%d3                           | ic2
        move.l  %d1,%d0
        .endm

        .macro  LOOP_IN
        move.l  %a2,-(%sp)
        movem.l (%a2),%d2-%d3                     | ic1, ic2
        move.l  #KQ,%a3
        moveq   #FRAMES,%d7
        .endm

        .macro  LOOP_OUT
        move.l  %d0,(%a0)
        lea     TX_STRIDE(%a0),%a0
        subq.l  #1,%d7
        bne.w   1b
        move.l  (%sp)+,%a2
        movem.l %d2-%d3,(%a2)
        rts
        .endm

        .align  2
hp_loop:
        LOOP_IN
1:      UNPACK
        HP
        cmpa.l  #0,%a4
        bne.s   4f                                | fused: leave it on the working scale
        PACK
4:      LOOP_OUT

        .align  2
lp_loop:
        LOOP_IN
1:      cmpa.l  #0,%a4
        bne.s   5f
        UNPACK
        bra.s   6f
5:      move.l  (%a0),%d0                         | fused: already on the working scale
6:      LP
        PACK
        LOOP_OUT

        .if     P_DIAG
        | diag_text(a1 = out): "12.3%" - the filters' peak share of the audio
        | interrupt interval since the last reading, in tenths of a percent - then
        | starts a new peak. Clobbers d0/d1, advances a1.
        .align  2
diag_text:
        move.l  diag_peak,%d0
        clr.l   diag_peak
        cmp.l   #9999,%d0
        bls.s   1f
        move.l  #9999,%d0
1:      divu.w  #10,%d0                           | low whole percent, high tenths
        move.l  %d0,-(%sp)
        and.l   #0xffff,%d0
        jsr     put_u3
        move.b  #0x2e,(%a1)+
        move.l  (%sp)+,%d0
        swap    %d0
        and.l   #0xffff,%d0
        add.l   #0x30,%d0
        move.b  %d0,(%a1)+
        move.b  #0x25,(%a1)+                      | %
        rts
        .endif

        | ------------------------------------------------------------------
        | Data
        | ------------------------------------------------------------------
        .align  2
cut_pages:                                        | the FILTER view's pages
        .long   PAGE_FILT, PAGE_CUT

page_cut:                                         | {name, top row, bottom row}
        .long   str_page
        .long   ID_LC, ID_HC, 0, 0
        .long   0, 0, 0, 0

        | One label, two uses: the page's name and the parameters' group name.
str_page:
str_group:      .asciz  "SMP CUT"
str_lc_l:       .asciz  "Low Cut"
str_hc_l:       .asciz  "High Cut"
str_lc:         .asciz  "LCT"
str_hc:         .asciz  "HCT"

        | ------------------------------------------------------------------
        | In cave3 (section .tab): the cutoff tables, and what is written at run
        | time - the filter state and the measuring build's counters.
        | ------------------------------------------------------------------
        .section .tab,"awx"
        .include "mods/0008-sample-cut/tables.inc"

        .align  2
cut_state:      .space  VOICES*16                 | per voice: hp {ic1, ic2}, lp {ic1, ic2}
        .if     P_DIAG
diag_last:      .long   0
diag_peak:      .long   0
        .endif

        | ------------------------------------------------------------------
        | Helpers, also in cave3 (called with jsr: cave3 is out of bsr range).
        | ------------------------------------------------------------------
        | ------------------------------------------------------------------
        | word_sync() -> d0 = the selected track's settings word (0 without a
        | sound), a0 = its live sound or 0. Clobbers d0/d1/a0/a1.
        | ------------------------------------------------------------------
        .align  2
word_sync:
        jsr     project_singleton
        move.l  %d0,%a0
        pea     PROJ_TRACKSEL(%a0)
        jsr     track_index_of
        addq.l  #4,%sp
        jsr     shared_sound_of                   | d0 = a0 = the live sound
        beq.s   8f
        mvzw    OFF_PARAMS(%a0),%d0
        rts
8:      clr.l   %d0
        sub.l   %a0,%a0
        rts

        | ------------------------------------------------------------------
        | value_of(d0 = word, d1 = id) -> d0 = what the knob shows, 0..127
        | Clobbers d0/d1.
        | ------------------------------------------------------------------
        .align  2
value_of:
        cmp.l   #ID_HC,%d1
        beq.s   1f
        moveq   #0x7f,%d1
        and.l   %d1,%d0
        rts
1:      lsr.l   #8,%d0
        moveq   #0x7f,%d1
        and.l   %d1,%d0
        moveq   #127,%d1
        sub.l   %d0,%d1
        move.l  %d1,%d0
        rts

        | put_u3(d0 = 0..999, a1 = out) - decimal, no leading zeros. Clobbers d0/d1.
        .align  2
put_u3:
        move.l  %d2,-(%sp)
        moveq   #0,%d2                            | a digit has been printed
        divu.w  #100,%d0
        mvzw    %d0,%d1                           | hundreds
        beq.s   1f
        add.l   #0x30,%d1
        move.b  %d1,(%a1)+
        moveq   #1,%d2
1:      clr.w   %d0
        swap    %d0
        divu.w  #10,%d0
        mvzw    %d0,%d1                           | tens
        tst.l   %d2
        bne.s   2f
        tst.l   %d1
        beq.s   3f
2:      add.l   #0x30,%d1
        move.b  %d1,(%a1)+
3:      swap    %d0
        mvzw    %d0,%d1                           | units
        add.l   #0x30,%d1
        move.b  %d1,(%a1)+
        move.l  (%sp)+,%d2
        rts


        | ------------------------------------------------------------------
        | fmt_hz(d0 = knob value 0..127, a1 = out): the cutoff as text, "120",
        | "1.2k", "12k". Step s = v >> 1 is 20 Hz * 10^(s/21):
        | Hz = cut_mant[s % 21] * 10^(s / 21) / 10. Clobbers d0/d1/a0, advances a1.
        | ------------------------------------------------------------------
        .align  2
fmt_hz:
        lsr.l   #1,%d0                            | step
        divu.w  #21,%d0                           | low word the decade, high the rest
        move.l  %d0,%d1
        swap    %d1
        and.l   #0xffff,%d1
        add.l   %d1,%d1
        lea     cut_mant,%a0
        mvzw    %a0@(0,%d1:l),%d1                 | tenths of a Hz
        and.l   #0xffff,%d0                       | decade 0..3
        beq.s   21f
        subq.l  #1,%d0
        beq.s   23f                               | x10 / 10: as is
        mulu.w  #10,%d1
        subq.l  #1,%d0
        beq.s   23f
        mulu.w  #10,%d1
        bra.s   23f
21:     divu.w  #10,%d1
        and.l   #0xffff,%d1
23:     move.l  %d1,%d0                           | Hz
        cmp.l   #1000,%d0
        bcc.s   3f
        jmp     put_u3                            | 20 .. 999
3:      divu.w  #1000,%d0                         | low word kHz, high word rest
        mvzw    %d0,%d1                           | kHz
        cmp.l   #10,%d1
        bcc.s   4f
        add.l   #0x30,%d1                         | 1.0k .. 9.9k
        move.b  %d1,(%a1)+
        move.b  #0x2e,(%a1)+
        clr.w   %d0
        swap    %d0
        divu.w  #100,%d0
        mvzw    %d0,%d1
        add.l   #0x30,%d1
        move.b  %d1,(%a1)+
        bra.s   41f
4:      and.l   #0xffff,%d0                       | 10k .. 20k
        jsr     put_u3
41:     move.b  #0x6b,(%a1)+                      | k
        rts

        | ------------------------------------------------------------------
        | coefs(d0 = step 0..63) -> d4 = a1, d5 = a2, d6 = a3 (Q31)
        | From the table's a1 (Q31) and g (Q28): a2 = g*a1, a3 = g*a2, each a
        | Q28 result shifted to Q31. Clobbers d0/d1/a1.
        | ------------------------------------------------------------------
        .align  2
coefs:
        lsl.l   #3,%d0
        lea     cut_coef,%a1
        adda.l  %d0,%a1
        move.l  (%a1)+,%d4                        | a1
        move.l  (%a1),%d1                         | g
        mac.l   %d1,%d4,%acc0
        movclr.l %acc0,%d5
        lsl.l   #3,%d5                            | a2
        mac.l   %d1,%d5,%acc0
        movclr.l %acc0,%d6
        lsl.l   #3,%d6                            | a3
        rts

