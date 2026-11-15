"""The cozy opening of level 1: for a moment the game pretends to be a sweet little pet-the-cat game.

  <loops>/sky/cozy_intro_8b.wav    8 bars: a music box tune in C major over soft chords, with a purr under it

It loops until the player presses the button; then the game cuts it dead (a glitch meow and a tape rewind,
which are existing one-shots) and the real level starts.

usage: python -I make_cozy.py <loops dir>
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import BAR, SR, bandpass, lowpass, mtof, nm, noise, osc_fm, osc_sine, pan, place, reverb, t2n, wrap, write_wav  # noqa: E402

OUT = os.path.join(sys.argv[1], 'sky')
os.makedirs(OUT, exist_ok=True)
BARS = 8
N = t2n(BARS * BAR)
BEAT = BAR / 4
x = np.zeros((N + t2n(3.0), 2))
# the music box: one note a beat, a lullaby shape (up the chord and back), a little higher the second time
TUNE = ['E5 G5 C6 G5', 'F5 A5 C6 A5', 'E5 G5 C6 E6', 'D6 B5 G5 B5',
        'E5 G5 C6 G5', 'F5 A5 D6 C6', 'B5 D6 G5 B5', 'C6 G5 E5 C5']
for bar, row in enumerate(TUNE):
    for i, name in enumerate(row.split()):
        n = t2n(1.6)
        k = np.arange(n) / SR
        bell = osc_fm(mtof(nm(name)), n, ratio=3.5, index=1.1, index_decay=9.0) * np.exp(-k / 0.45)
        place(x, pan(bell, 0.25 if i % 2 else -0.25), t2n(bar * BAR + i * BEAT), 0.5)
        if i == 0:                                     # an octave below on the first beat, like a second comb
            low = osc_fm(mtof(nm(name) - 12), n, ratio=3.5, index=0.8, index_decay=9.0) * np.exp(-k / 0.6)
            place(x, pan(low, 0.0), t2n(bar * BAR), 0.35)
# soft chords underneath: C F C G | C F G C
for bar, chord in enumerate([(48, 52, 55), (53, 57, 60), (48, 52, 55), (55, 59, 62), (48, 52, 55), (53, 57, 60), (55, 59, 62), (48, 52, 55)]):
    n = t2n(BAR * 1.05)
    k = np.arange(n) / SR
    env = np.clip(k / 0.25, 0, 1) * np.clip((n / SR - k) / 0.3, 0, 1)
    pad = sum(osc_sine(mtof(m), n) + 0.3 * osc_sine(mtof(m + 12), n) for m in chord) / 3 * env
    place(x, pan(pad, 0.0), t2n(bar * BAR), 0.28)
# a purr: low noise that flutters about 25 times a second, breathing in and out every two bars
t = np.arange(N) / SR
purr = lowpass(np.stack([noise(N), noise(N)], 1), 220) * (0.5 + 0.5 * np.sin(2 * np.pi * 25 * t))[:, None]
purr *= (0.55 + 0.45 * np.sin(2 * np.pi * t / (2 * BAR) - 1.5))[:, None]
x[:N] += purr * 0.9
x = reverb(x, 1.8, 0.45, mix=0.22)
x = wrap(x, N)
x *= 0.075 / np.sqrt(np.mean(x ** 2))
x *= 1.0 / max(1.0, np.max(np.abs(x)) / 0.98)
path = os.path.join(OUT, 'cozy_intro_8b.wav')
write_wav(path, x, peak=None)
print(path, f'rms {np.sqrt(np.mean(x ** 2)):.3f} peak {np.max(np.abs(x)):.2f}')
