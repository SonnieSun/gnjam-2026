"""star_ding: the 'ding' of the cartoon cross-star that flashes where the cat breaks out of the atmosphere
(the earth slap's ending, bar 2, beat 1: stages/earth_slap/earth_slap_stage.gd, rocket_star_sfx).

With a recording: InspectorJ, "Bike Bell Ding, Single, 01-01.wav" (freesound.org/s/484344, CC BY 4.0; credited in
assets/audio/README.md), trimmed to start on the strike, a short fade on the ring, a quick glint on the front.
Without one: a synthetic bell on E6 (bar 2 is on E7) with its inharmonic partials.

usage: python -I make_star_ding.py <sfx dir> [<bell recording .wav>]
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import SR, highpass, mtof, nm, noise, pan, read_wav, reverb, t2n, write_wav  # noqa: E402

LENGTH = 1.3   # seconds kept


def glint():
    g = t2n(0.09)
    kg = np.arange(g) / g
    v = np.sin(2 * np.pi * np.cumsum(mtof(nm('E6')) * 2 ** ((7 * kg) / 12)) / SR) * np.sin(np.pi * kg) * 0.25
    return pan(v, 0.15)


if len(sys.argv) > 2:
    rec = read_wav(sys.argv[2])
    rec = rec if rec.ndim == 2 else np.stack([rec, rec], 1)
    level = np.abs(rec).max(axis=1)
    start = max(int(np.argmax(level > level.max() * 0.05)) - t2n(0.003), 0)
    x = rec[start:start + t2n(LENGTH)].copy()
    x[-t2n(0.5):] *= np.linspace(1, 0, t2n(0.5))[:, None] ** 2
    g = glint()
    x[:len(g)] += g * 0.6
else:
    n = t2n(LENGTH)
    k = np.arange(n) / SR
    f = mtof(nm('E6'))
    bell = sum(gain * np.sin(2 * np.pi * f * r * k) * np.exp(-k / d)
               for r, gain, d in ((1.0, 1.0, 0.45), (2.0, 0.35, 0.25), (2.76, 0.3, 0.16), (5.4, 0.18, 0.07)))
    x = pan(bell * np.clip(k / 0.002, 0, 1) * 0.8, 0.0)
    g = glint()
    x[:len(g)] += g
    x[:t2n(0.05)] += highpass(np.stack([noise(t2n(0.05))] * 2, 1), 7000) * np.exp(-np.arange(t2n(0.05)) / SR / 0.01)[:, None] * 0.15
    x = reverb(x, 1.2, 0.4, mix=0.25)
write_wav(os.path.join(sys.argv[1], 'star_ding.wav'), x, peak=0.8)
print(f'  star_ding: {len(x) / SR:.2f} s' + (' (from the recording)' if len(sys.argv) > 2 else ' (synthetic)'))
