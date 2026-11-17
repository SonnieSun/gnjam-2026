"""ufo_bonk: the cat's head hits a UFO as it lifts off the earth (the earth slap's ending, rocket_ufo_hit, beat 8:
stages/earth_slap/earth_slap_stage.gd, rocket_ufo_sfx). A dry, dull wooden knock with a low thump
under it and only a touch of short ring, low-passed; no room, nothing after it (the saucer spins off silently). No samples needed.

usage: python -I make_ufo_bonk.py <sfx dir>
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import SR, highpass, lowpass, noise, pan, t2n, write_wav  # noqa: E402

x = np.zeros((t2n(0.3), 2))
n = t2n(0.25)
k = np.arange(n) / SR
knock = np.sin(2 * np.pi * 320 * k * (1 + 0.6 * np.exp(-k / 0.008))) * np.exp(-k / 0.04)
body = np.sin(2 * np.pi * np.cumsum(90 + 80 * np.exp(-k / 0.02)) / SR) * np.exp(-k / 0.05)   # low thump: weight
clang = sum(g * np.sin(2 * np.pi * 980 * r * k) * np.exp(-k / d) for r, g, d in ((1.0, 0.5, 0.05), (2.76, 0.3, 0.03), (5.4, 0.2, 0.015)))
click = highpass(noise(n), 2500) * np.exp(-k / 0.004) * 0.12
# dry and solid: no room, the ring cut short, a dull knock with some weight under it, filtered down
x[:n] += pan(lowpass(lowpass(knock * 0.75 + body * 0.6 + clang * 0.15 + click, 2000), 2000), 0.1)
x[-t2n(0.03):] *= np.linspace(1, 0, t2n(0.03))[:, None]
write_wav(os.path.join(sys.argv[1], 'ufo_bonk.wav'), x, peak=0.6)
print(f'  ufo_bonk: {len(x) / SR:.2f} s')
