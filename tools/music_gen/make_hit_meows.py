"""The hit feedback meows: the team's own recorded meows, short and punchy, played when a hit lands.

  hit_meow_perfect_<cat>_<shift>.wav   a whole 'miao' squeezed to 0.24 s (pitch kept), at its own
                                       pitch and a little higher: bright, for a Perfect
  hit_meow_good_<cat>_<shift>.wav      a shorter, lower 0.16 s 'mi(ao)': for a Good

<cat> is which recorded meow: a = recording 1 long, b = recording 1 short, c = recording 2 long.
Every file has the same loudness (RMS), so a randomizer can pick any of them. In Godot they are
grouped into two AudioStreamRandomizer resources (assets/audio/sfx/hit_meow_perfect.tres and
hit_meow_good.tres) that also add a little random pitch and volume, never the same file twice in a row.

usage: python -I make_hit_meows.py <samples dir> <out dir>
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import SR, highpass, write_wav  # noqa: E402
from audio import read_wav  # noqa: E402
from psola import sing_miao  # noqa: E402
from slicer import slices  # noqa: E402

S, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
REC = os.path.join(S, 'my_meows')
# the three real meows in the two recordings (the rest is breath and room noise)
SOURCES = {'a': ('user_meows.wav', 0.05), 'b': ('user_meows.wav', 1.78), 'c': ('user_meows_2.wav', 0.64)}


def cut(path, start):
    """The meow nearest `start`, without its quiet lead-in (so it lands on the hit) or breathy tail."""
    sl = min(slices(read_wav(path), min_len=0.1, max_len=2.0, gate_db=-30), key=lambda s: abs(s['start'] / SR - start))['audio']
    sl = highpass(sl, 120)
    m = np.abs(sl).mean(axis=1)
    w = int(0.01 * SR)
    env = np.sqrt(np.convolve(m ** 2, np.ones(w) / w, mode='same'))
    keep = np.nonzero(env > env.max() * 10 ** (-26 / 20))[0]
    loud = np.nonzero(env > env.max() * 10 ** (-12 / 20))[0]
    a = max(0, loud[0] - int(0.005 * SR))
    b = min(len(sl), keep[-1] + int(0.02 * SR))
    return sl[a:b].mean(axis=1)


def own_pitch(m):
    from psola import midi_contour
    pc = midi_contour(m)
    return float(np.median(pc)) if pc is not None else 72.0


def tight(v, db=-10, pre=0.002):
    """Start 2 ms before the sound reaches -10 dB of its peak: a soft 'm' at the front would make the
    meow feel late on the hit."""
    m = np.abs(v)
    w = int(0.005 * SR)
    env = np.sqrt(np.convolve(m ** 2, np.ones(w) / w, mode='full')[: len(m)])
    i = np.nonzero(env >= env.max() * 10 ** (db / 20))[0]
    return v[max(0, i[0] - w - int(pre * SR)):] if len(i) else v


def finish(v, rms=0.12):
    """Starts right on the sound, same loudness for every file, a 2 ms fade in, a 25 ms fade out,
    and a peak cap."""
    v = tight(v)
    v = v * rms / (np.sqrt(np.mean(v ** 2)) + 1e-9)
    g = int(0.002 * SR)
    v[:g] *= np.linspace(0, 1, g)
    f = min(int(0.025 * SR), len(v) // 3)
    v[-f:] *= np.linspace(1, 0, f)
    peak = np.max(np.abs(v))
    return v * (0.95 / peak) if peak > 0.95 else v


def save(name, v):
    write_wav(os.path.join(OUT, name + '.wav'), np.stack([v, v], 1), peak=None)
    print(f'  {name}: {len(v) / SR:.2f} s')


for key, (f, start) in SOURCES.items():
    m = cut(os.path.join(REC, f), start)
    p = own_pitch(m)
    print(f'meow {key}: {len(m) / SR:.2f} s, own pitch {p:.1f}')
    for shift in (0, 3, 5):
        save(f'hit_meow_perfect_{key}_{shift:+d}', finish(sing_miao(m, p + shift, 0.24, keep=0.7)))
    for shift in (-2, 0):
        save(f'hit_meow_good_{key}_{shift:+d}', finish(sing_miao(m, p + shift, 0.16, keep=0.5), rms=0.09))
print('hit meows done ->', OUT)
