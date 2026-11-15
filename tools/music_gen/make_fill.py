"""The transition fill: one bar of "something is about to change", the same in every bar of a 4-bar loop,
so the game can switch its lane on for exactly one bar at any bar line (it plays in sync with the song).

  <loops>/s1_disc/s1_disc_X_fill_4b.wav

Each bar: claps on the 8ths of the first half and on the 16ths of the second, getting louder; a kitten
'mi-mi-mi-mi' climbing in pitch over the last beat; a noise riser under it all. No chords and no bass, so it
fits any song in any key.

usage: python -I make_fill.py <loops dir> <deliver sfx dir>          (CAT_BPM=120 for the 120 BPM set)
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import BAR, SR, highpass, noise, pan, place, read_wav, resample, softclip, t2n, write_wav  # noqa: E402

LOOPS, SFX = sys.argv[1], sys.argv[2]
DISC = os.path.join(LOOPS, 's1_disc')
clap = read_wav(os.path.join(DISC, 's1_disc_clap.wav'))
mi = read_wav(os.path.join(SFX, 'kitten_mi.wav'))
n = t2n(BAR)
step = BAR / 16
bar = np.zeros((n + t2n(0.5), 2))
# claps: 8ths, then 16ths, louder and louder
hits = [0, 2, 4, 6] + list(range(8, 16))
for k, s in enumerate(hits):
    place(bar, clap, t2n(s * step), 0.25 + 0.6 * k / (len(hits) - 1))
# the kitten climbs over the last beat
for k in range(4):
    place(bar, mi[: t2n(0.09)], t2n((12 + k) * step), 0.7, semitones=2.0 * k)
# a noise riser: filtered noise swelling to the bar line
t = np.arange(n) / n
swell = highpass(pan(noise(n) * t ** 2.5, 0.0), 2500) * 0.25
bar[:n] += swell
bar = bar[:n]
f = t2n(0.004)
bar[-f:] *= np.linspace(1, 0, f)[:, None]
loop = softclip(np.tile(bar, (4, 1)), 1.2)
loop *= 0.11 / np.sqrt(np.mean(loop ** 2))
path = os.path.join(DISC, 's1_disc_X_fill_4b.wav')
write_wav(path, loop * (1.0 / max(1.0, np.max(np.abs(loop)) / 0.98)), peak=None)
print(path, f'{len(loop) / SR:.1f} s, rms {np.sqrt(np.mean(loop ** 2)):.3f}, peak {np.max(np.abs(loop)):.2f}')
