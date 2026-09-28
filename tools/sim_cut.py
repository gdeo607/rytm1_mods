"""Bit-level model (v3: coefficients derived from a1 and g as coefs: does, the
fused both-on path, the silence skip) of 0008's hp_pass/lp_pass (same fixed-point steps as stub.s),
checked against ideal Butterworth responses and for stability. Needs numpy.

    python3 tools/sim_cut.py
"""
import math, re
from pathlib import Path
import numpy as np   # pip install numpy
FS=48000
txt=open(Path(__file__).resolve().parent.parent/'mods'/'0008-sample-cut'/'tables.inc').read()
rows=[tuple(int(x,16) for x in re.findall(r'0x([0-9a-f]{8})',l)) for l in txt.splitlines() if l.strip().startswith('.long')]
def _frac(a,b): return math.floor(a*b/2**31)
def derive(a1,g):   # exactly as coefs: in stub.s
    a2=(_frac(g,a1)<<3)&0xffffffff; a3=(_frac(g,a2)<<3)&0xffffffff
    return (a1,a2,a3)
co=[derive(a1,g) for a1,g in rows]
mant=[int(x) for l in txt.split('cut_mant:')[1].splitlines() if l.strip().startswith('.short') for x in l.split('.short')[1].split(',')]
hz=[mant[i%21]*10**(i//21)//10 for i in range(64)]
KQ=0x3504f334; SAT=0x07ffffff
def s32(x): x&=0xffffffff; return x-(1<<32) if x&0x80000000 else x
def frac(*pairs):  # sum of Q31 products, one truncation
    return s32(math.floor(sum(a*b for a,b in pairs)/2**31))
def unpack(w): return s32(w<<8)>>4
def pack(y):
    y=max(-SAT-1,min(SAT,y)); return ((y<<4)&0xffffffff)>>8
def run(words,coef,st,hp,raw_in=False,raw_out=False):
    a1,a2,a3=coef; ic1,ic2=st; out=[]
    for w in words:
        v0=w if raw_in else unpack(w)
        v3=s32(v0-ic2); v1=frac((a1,ic1),(a2,v3)); v2=s32(frac((a2,ic1),(a3,v3))+ic2)
        y=s32(v0-v2-v1-frac((KQ,v1))) if hp else v2
        ic1=s32(2*v1-ic1); ic2=s32(2*v2-ic2)
        out.append(y if raw_out else pack(y))
    return out,(ic1,ic2)
def to_words(x): return [((int(round(v*(2**23-1)))&0xffffff)) for v in x]
def from_words(ws): return np.array([ (w-(1<<24) if w&0x800000 else w)/(2**23) for w in ws])
def gain(step,f,hp,n=9600):
    t=np.arange(n)/FS; x=0.5*np.sin(2*math.pi*f*t)
    ws=to_words(x); st=(0,0); out=[]
    for i in range(0,n,32):
        o,st=run(ws[i:i+32],co[step],st,hp); out+=o
    y=from_words(out)[n//2:]; xs=x[n//2:]
    return 20*math.log10(np.sqrt(np.mean(y**2))/np.sqrt(np.mean(xs**2)))
def ideal(fc,f,hp):
    r=(f/fc)**4; return 10*math.log10((r if hp else 1)/(1+r))
worst=0
for step in (0,8,21,31,42,50,58,63):
    fc=hz[step]
    for hp in (True,False):
        for f in (fc/4,fc/2,fc,fc*2,fc*4):
            if not(15<f<22000): continue
            g=gain(step,f,hp); i=ideal(fc,f,hp)
            # bilinear warps near Nyquist, compare only where meaningful
            if fc/2<=f<=2*fc and fc<=2000: worst=max(worst,abs(g-i))
            print(f"{'HP' if hp else 'LP'} step {step:2d} fc {fc:6d} f {f:8.1f}: {g:7.2f} dB (ideal {i:7.2f})")
print('worst deviation from ideal within an octave of the cutoff, cutoffs up to 2 kHz (dB):',round(worst,3))
# stability: DC + full-scale square through HP at 20 Hz and LP at 20 kHz
for step,hp in ((0,True),(63,False),(0,False),(63,True)):
    x=np.sign(np.sin(2*math.pi*50*np.arange(48000)/FS))*0.999
    ws=to_words(x); st=(0,0); out=[]
    for i in range(0,48000,32):
        o,st=run(ws[i:i+32],co[step],st,hp); out+=o
    y=from_words(out); print('square', 'HP' if hp else 'LP', step, 'peak', round(float(np.max(np.abs(y))),3),'final state',st)

# ---- the silence skip (cut_process): a decaying hit, then silence.
# With the skip, a block whose 32 input words are all zero and whose states are all
# below 64 is left untouched and its states zeroed. Compare against always filtering.
def voice(ws,cfgs,skip):
    hp_st=(0,0); lp_st=(0,0); out=[]; ran=0
    for i in range(0,len(ws),32):
        blk=ws[i:i+32]
        if skip and not any(blk) and all(abs(v)<2048 for v in hp_st+lp_st):
            hp_st=lp_st=(0,0); out+=blk; continue
        ran+=1
        both=cfgs[0] is not None and cfgs[1] is not None
        if cfgs[0] is not None: blk,hp_st=run(blk,co[cfgs[0]],hp_st,True,raw_out=both)
        if cfgs[1] is not None: blk,lp_st=run(blk,co[cfgs[1]],lp_st,False,raw_in=both)
        out+=blk
    return out,ran
n=48000
t=np.arange(n)/FS
hit=np.where(t<0.3,0.9*np.sin(2*math.pi*180*t)*np.exp(-t/0.05),0.0)   # a 300 ms kick-like hit, then silence
ws=to_words(hit)
for cfgs in ((21,None),(None,42),(21,42),(0,63),(0,None),(None,0),(40,20)):
    a,ra=voice(ws,cfgs,False); b,rb=voice(ws,cfgs,True)
    d=np.max(np.abs(from_words(a)-from_words(b)))*2**23
    print(f"skip  hp step {cfgs[0]} lp step {cfgs[1]}: blocks filtered {rb}/{ra}, max difference {d:.0f} LSB ({20*math.log10(max(d,1)/2**23):.0f} dBFS)")

# ---- the fused path against two separate passes (both filters on)
x=to_words(0.7*np.sin(2*math.pi*300*np.arange(4800)/FS)+0.2*np.sin(2*math.pi*5000*np.arange(4800)/FS))
for hs,ls in ((21,42),(0,63),(30,35)):
    a=[];b=[];s1=s2=s3=s4=(0,0)
    for i in range(0,len(x),32):
        blk=x[i:i+32]
        t,s1=run(blk,co[hs],s1,True); t,s2=run(t,co[ls],s2,False); a+=t
        t,s3=run(blk,co[hs],s3,True,raw_out=True); t,s4=run(t,co[ls],s4,False,raw_in=True); b+=t
    d=np.max(np.abs(from_words(a)-from_words(b)))*2**23
    print(f"fused vs two passes, hp {hs} lp {ls}: max difference {d:.0f} LSB")
