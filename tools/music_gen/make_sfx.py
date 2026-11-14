"""The small sounds: one-shots the beat manager and the transitions fire on top of the music.

  meow_*            the roster's meows as one-shots on the scene's chord tones (G, Bb, D, F)
  kitten_mi, seal_bark
  spin_meow_a/b     an OIIA-style spinning cat: 'o-i-i-a-i' built from our own meows (the meme's
                    own audio isn't ours to use; drop the original in as oiia_original.wav if the
                    team has the rights)
  catness_up        three cats rising Bb-D-F + a kitten on top: plays when a cat layer swaps in
  catness_down      one cat sliding down: a cat layer leaves / a miss streak
  miss_meow         a short sad meow for a MISS
  glitch_meow       'm-m-m-m-MIAO' stutter, bit-crushed: style switch / FRENZY
  orch_hit_Bb, laser_zap, rewind_1b, level_clear
  (kick, clap, crash, riser_1b are copied from scene 1)

usage: python -I make_sfx.py <samples dir> <loops dir> <out dir>
"""
import os
import shutil
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import (BAR, SR, bandpass, bitcrush, highpass, mtof, nm, noise, osc_saw, osc_sine,  # noqa: E402
                   osc_supersaw, pan, place, read_wav, resample, reverb, softclip, svf_lowpass, t2n, write_wav)
from psola import midi_contour, sing, sing_miao  # noqa: E402
from slicer import slices  # noqa: E402

S, LOOPS, OUT = sys.argv[1:4]
os.makedirs(OUT, exist_ok=True)
BEAT = BAR / 4
B = os.path.join(S, 'bigsoundbank_cats')
MIAUEN = os.path.join(S, 'commons_animals', 'Weibliche Britisch Kurzhaar will Futter C1277 MIAUEN.wav')


def cut(path, start, min_len=0.3):
    sl = min(slices(read_wav(path), min_len=min_len, max_len=2.0, gate_db=-30), key=lambda s: abs(s['start'] / SR - start))['audio']
    sl = highpass(sl, 100)
    # same trim as the song builder: no quiet lead-in (so it lands on time), no breathy tail
    m = np.abs(sl).mean(axis=1)
    w = int(0.01 * SR)
    env = np.sqrt(np.convolve(m ** 2, np.ones(w) / w, mode='same'))
    keep = np.nonzero(env > env.max() * 10 ** (-26 / 20))[0]
    loud = np.nonzero(env > env.max() * 10 ** (-18 / 20))[0]
    sl = sl[max(0, loud[0] - int(0.015 * SR)): min(len(sl), keep[-1] + int(0.03 * SR))].copy()
    sl[: int(0.005 * SR)] *= np.linspace(0, 1, int(0.005 * SR))[:, None]
    sl[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))[:, None]
    return sl / np.max(np.abs(sl))


CAT = {1: cut(MIAUEN, 11.45, 0.6), 3: cut(MIAUEN, 5.14, 0.6),
       4: cut(os.path.join(B, 'ANMLCat_Meow cat 4 (ID 1892)_BigSoundBank.com.wav'), 0.05, 0.6),
       5: cut(os.path.join(B, 'ANMLCat_Meow cat 5 (ID 1893)_BigSoundBank.com.wav'), 0.41, 0.6),
       6: cut(os.path.join(B, 'ANMLCat_Meow cat 13 (ID 1901)_BigSoundBank.com.wav'), 4.03, 0.6),
       10: cut(os.path.join(B, 'ANMLCat_Small mewing of a cat (ID 0098)_BigSoundBank.com.wav'), 1.09)}
KITTEN = cut(os.path.join(B, 'ANMLCat_Mewing kitten 3 weeks (ID 0390)_BigSoundBank.com.wav'), 2.46)
SEAL = cut(os.path.join(S, 'commons_animals', 'Arctocephalusgazellavocal.wav'), 1.01, 0.2)


def st(v, side=0.0):
    return pan(v, side)


def save(name, x, peak=0.9):
    x = np.array(x, dtype=float)
    f = min(t2n(0.03), len(x) // 4)                     # every one-shot ends in silence: no click
    x[-f:] *= np.linspace(1, 0, f)[:, None] if x.ndim == 2 else np.linspace(1, 0, f)
    write_wav(os.path.join(OUT, name + '.wav'), x, peak=peak)
    print(f'  {name}: {len(x) / SR:.2f} s')


# --- meows on the chord tones of scene 1 (Bb major / G minor), following loops/meow_roster.json ----
import json  # noqa: E402
ROSTER = json.load(open(os.path.join(LOOPS, 'meow_roster.json'), encoding='utf-8'))
TABLE = {i: (f, s, ml) for i, (f, s, ml) in {
    1: (MIAUEN, 11.45, 0.6), 2: (MIAUEN, 7.59, 0.6), 3: (MIAUEN, 5.14, 0.6),
    4: (os.path.join(B, 'ANMLCat_Meow cat 4 (ID 1892)_BigSoundBank.com.wav'), 0.05, 0.6),
    5: (os.path.join(B, 'ANMLCat_Meow cat 5 (ID 1893)_BigSoundBank.com.wav'), 0.41, 0.6),
    6: (os.path.join(B, 'ANMLCat_Meow cat 13 (ID 1901)_BigSoundBank.com.wav'), 4.03, 0.6),
    7: (os.path.join(B, 'ANMLCat_Meow cat 12 (ID 1900)_BigSoundBank.com.wav'), 0.02, 0.6),
    8: (os.path.join(B, 'ANMLCat_Meow cat 2 (ID 1890)_BigSoundBank.com.wav'), 0.08, 0.6),
    9: (os.path.join(B, 'ANMLCat_Meow cat 3 (ID 1891)_BigSoundBank.com.wav'), 0.05, 0.6),
    10: (os.path.join(B, 'ANMLCat_Small mewing of a cat (ID 0098)_BigSoundBank.com.wav'), 1.09, 0.3),
    11: (os.path.join(B, 'ANMLCat_Mewing kitten 3 weeks (ID 0390)_BigSoundBank.com.wav'), 2.46, 0.3),
    12: (os.path.join(B, 'ANMLCat_Little meow of a cat 8 (ID 1478)_BigSoundBank.com.wav'), 0.08, 0.3),
    13: (os.path.join(S, 'my_meows', 'user_meows.wav'), 0.05, 0.2),
    14: (os.path.join(S, 'my_meows', 'user_meows.wav'), 1.78, 0.2),
    15: (os.path.join(S, 'my_meows', 'user_meows_2.wav'), 0.80, 0.2)}.items()}
for i in ROSTER['long'] + ROSTER['accent'] + ROSTER['short']:
    if i not in CAT:
        CAT[i] = cut(*TABLE[i])


def own_pitch(audio):
    pc = midi_contour(audio.mean(axis=1) if audio.ndim == 2 else audio)
    return float(np.median(pc)) if pc is not None else 72.0


def near_cat(name, audio):
    """The chord tone `name` ('Bb', 'D') in the octave nearest the cat's own pitch: a meow pitched far
    down stops sounding like a cat, so each cat sings in its own register."""
    base = nm(name + '4')
    own = own_pitch(audio)
    octave = min(range(-2, 4), key=lambda k: abs(base + 12 * k - own - 1))
    m = base + 12 * octave
    return m, f'{name}{4 + octave}'


for i in ROSTER['accent']:
    for name in ('G', 'Bb', 'D'):
        m, note = near_cat(name, CAT[i])
        save(f'meow_long_{i:02d}_{note}', st(sing_miao(CAT[i], m, 0.8)))
for i in ROSTER['short']:
    for name in ('Bb', 'D', 'F'):
        m, note = near_cat(name, CAT[i])
        save(f'meow_short_{i:02d}_{note}', st(sing_miao(CAT[i], m, 0.3, keep=0.3)))
for i in ROSTER['long']:
    save(f'meow_natural_{i:02d}', st(CAT[i].mean(axis=1)))
save('kitten_mi', st(KITTEN.mean(axis=1)))
save('seal_bark', st(SEAL.mean(axis=1)[: t2n(0.4)] * np.linspace(1, 0, t2n(0.4)) ** 0.5))


# --- spin meow, OIIA style -----------------------------------------------------------------------
def spin(src, notes, seg=0.11, wobble=0.6):
    """'o-i-i-a-i...': each syllable is a slice of the meow (dark end for 'o'/'a', bright middle for
    'i'), sung on its note, with a fast pitch wobble like a cat being spun round."""
    m = src.mean(axis=1)
    n = len(m)
    part = {'o': m[int(0.7 * n):], 'i': m[int(0.3 * n): int(0.6 * n)], 'a': m[int(0.55 * n): int(0.9 * n)]}
    out = []
    for syl, note in notes:
        v = sing({'audio': np.stack([part[syl], part[syl]], 1), 'midi': float(np.median([nm('E5')]))}, note, seg)
        t = np.arange(len(v)) / SR
        rate = 2 ** (wobble * np.sin(2 * np.pi * 9 * t) / 12)
        idx = np.clip(np.cumsum(rate), 0, len(v) - 1)
        out.append(np.interp(idx, np.arange(len(v)), v))
    y = np.concatenate(out)
    f = t2n(0.004)
    for k in range(1, len(notes)):
        j = int(k * seg * SR)
        y[j - f: j + f] *= np.concatenate([np.linspace(1, 0.4, f), np.linspace(0.4, 1, f)])
    return st(softclip(y * 1.2, 1.2))


save('spin_meow_a', spin(CAT[6], [('o', nm('D5')), ('i', nm('A5')), ('i', nm('A5')), ('a', nm('F5')),
                                  ('i', nm('A5')), ('o', nm('D5')), ('i', nm('A5')), ('i', nm('A5')), ('a', nm('F5'))]))
save('spin_meow_b', spin(CAT[10], [('o', nm('Bb4')), ('i', nm('F5')), ('i', nm('F5')), ('a', nm('D5')), ('i', nm('F5'))], seg=0.09, wobble=0.9))

# --- stingers --------------------------------------------------------------------------------------
x = np.zeros((t2n(1.2), 2))
for k, (note, side) in enumerate((('Bb4', -0.4), ('D5', 0.0), ('F5', 0.4))):
    place(x, st(sing_miao(CAT[10], nm(note), 0.35, keep=0.3), side), t2n(k * BEAT / 2))
place(x, st(sing(dict(audio=KITTEN, midi=85.3), nm('Bb6'), 0.3), 0.0), t2n(1.5 * BEAT), 0.7)
save('catness_up', reverb(x, 0.6, 0.2, mix=0.08)[: len(x)])

v = sing_miao(CAT[6], nm('D5'), 0.9, keep=1.0)
t = np.arange(len(v)) / SR
idx = np.cumsum(2 ** (-7 * (t / t[-1]) ** 1.5 / 12))
save('catness_down', st(np.interp(np.clip(idx, 0, len(v) - 1), np.arange(len(v)), v) * np.linspace(1, 0.2, len(v))))
save('miss_meow', st(sing_miao(CAT[10], nm('E4'), 0.35, keep=0.8) * np.linspace(1, 0.5, t2n(0.35))))

g = sing_miao(CAT[10], nm('D5'), 0.06, keep=0.2)                # the 'm' grains, 1/32 apart
seq2 = np.zeros((t2n(0.9), 2))
for k in range(4):
    place(seq2, st(g * (0.6 + 0.1 * k)), t2n(k * BAR / 32))
place(seq2, st(sing_miao(CAT[6], nm('F5'), 0.5)), t2n(4 * BAR / 32))
seq2[: t2n(4 * BAR / 32)] = bitcrush(seq2[: t2n(4 * BAR / 32)], bits=5, hold=4)
save('glitch_meow', seq2)


def saw_chord(midis, n, detune=0.3):
    return sum(osc_supersaw(mtof(m), n, voices=5, detune=detune) for m in midis) / len(midis)


n = t2n(0.6)
tt = np.arange(n) / SR
chord = svf_lowpass(saw_chord([nm(q) for q in ('Bb3', 'D4', 'F4', 'Bb4')], n), 1800 + 7000 * np.exp(-tt / 0.06), q=0.9) * np.exp(-tt / 0.22)[:, None]
blast = st(bandpass(noise(n), 300, 4000) * np.exp(-tt / 0.035)) * 0.6
thump = st(osc_sine(70 * (1 + np.exp(-tt / 0.02)), n) * np.exp(-tt / 0.08)) * 0.5
save('orch_hit_Bb', chord + blast + thump)

n = t2n(0.35)
tt = np.arange(n) / SR
f = 2400 * np.exp(-tt / 0.07) + 120
save('laser_zap', st(softclip(osc_saw(f, n) * np.exp(-tt / 0.12) * 0.8, 1.5)))

n = t2n(BAR)
k = np.arange(n) / n
sweep = st(svf_lowpass(noise(n), 8000 - 7000 * k, q=1.4) * (1 - k) ** 0.5)[::-1] * 0.6
rv = st(sing_miao(CAT[1], nm('D5'), 0.9).copy()[::-1])
place(sweep, rv * 0.6, n - len(rv))
save('rewind_1b', sweep)

x = np.zeros((t2n(2.5), 2))
place(x, st(sing_miao(CAT[6], nm('Bb4'), 1.2), -0.3), 0, 0.7)
place(x, st(sing_miao(CAT[1], nm('D5'), 1.2), 0.0), 0, 0.6)
place(x, st(sing_miao(CAT[4], nm('F5'), 1.2), 0.3), 0, 0.6)
place(x, read_wav(os.path.join(LOOPS, 's1_disc', 's1_disc_crash.wav')), 0, 0.8)
n = t2n(0.6)
place(x, chord[:n] + blast[:n] + thump[:n], 0, 0.7)
save('level_clear', reverb(x, 1.2, 0.3, mix=0.12)[: len(x)])

for name in ('kick', 'clap', 'crash', 'riser_1b'):
    shutil.copy(os.path.join(LOOPS, 's1_disc', f's1_disc_{name}.wav'), os.path.join(OUT, f'{name}.wav'))
print('sfx done ->', OUT)
