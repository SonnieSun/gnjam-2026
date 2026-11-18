"""ufo_break: a very short game-style explosion / smash for the UFO the cat knocks away (the earth slap's ending,
rocket_ufo_hit, beat 8: stages/earth_slap/earth_slap_stage.gd, rocket_break_sfx). Played together with ufo_bonk.
Retro: a console-style noise channel whose pitch drops from bright fizz to crunchy rumble, a square wave
sweeping down under it, a light kick for weight, stepped volume and ~5-bit grit. About 0.4 s, no room. No samples needed.

usage: python -I make_ufo_break.py <sfx dir>
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import SR, highpass, lowpass, noise, pan, t2n, write_wav  # noqa: E402

rng = np.random.default_rng(7)
x = np.zeros((t2n(0.4), 2))
n = t2n(0.38)
k = np.arange(n) / SR

# chip noise: random values held for a while (sample-and-hold), the hold getting longer as it decays, so the
# noise "pitch" drops from a bright fizz to a crunchy rumble, like an old console's noise channel
rate = 9000 * np.exp(-k / 0.09) + 700
phase = np.cumsum(rate / SR)
steps = np.floor(phase).astype(int)
chip = rng.uniform(-1, 1, steps[-1] + 2)[steps]
# square sweep: a square wave diving 700 -> 90 Hz under it (the "pew-boom" body)
sq = np.sign(np.sin(2 * np.pi * np.cumsum(90 + 610 * np.exp(-k / 0.04)) / SR))
# a soft kick for some weight, much lighter than the punchy version
kick = np.sin(2 * np.pi * np.cumsum(55 + 110 * np.exp(-k / 0.02)) / SR) * np.exp(-k / 0.05)
# stepped volume: the envelope only takes 16 levels, like a sound chip's 4-bit volume register
env = np.floor(np.exp(-k / 0.11) * 15) / 15
env_sq = np.floor(np.exp(-k / 0.05) * 15) / 15

mix = chip * env * 0.85 + sq * env_sq * 0.3 + kick * 0.45
mix = np.round(mix * 24) / 24        # ~5-bit: the retro grit
mix = lowpass(mix, 9000)             # take the harshest aliasing edge off, keep the fizz
x[:n] += pan(mix, -0.05)
x[-t2n(0.03):] *= np.linspace(1, 0, t2n(0.03))[:, None]
write_wav(os.path.join(sys.argv[1], 'ufo_break.wav'), x, peak=0.7)
print(f'  ufo_break: {len(x) / SR:.2f} s')
