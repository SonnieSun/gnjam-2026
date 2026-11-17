"""The hit sound of an ENDING change note (the rainbow note a part ends on, before a transition).

Not a riser like the fever note (fever_note.wav): this one settles. A timpani-like thud whose pitch drops and
stays, a short dry snap on top and one small high "ting" (inharmonic, so it does not fight the key of the tune).

usage: python -I make_end_note.py <out.wav>
"""
import sys
import wave

import numpy as np

SR = 44100
OUT = sys.argv[1]
n = int(SR * 0.9)
t = np.arange(n) / SR
rng = np.random.default_rng(7)

# the drum: starts a fourth up and settles within 60 ms, then rings about half a second
f = 82.0 + 60.0 * np.exp(-t / 0.02)
phase = 2 * np.pi * np.cumsum(f) / SR
drum = np.sin(phase) * np.exp(-t / 0.22) + 0.35 * np.sin(2.0 * phase) * np.exp(-t / 0.12)
# the stick: a few ms of filtered noise
snap = rng.standard_normal(n) * np.exp(-t / 0.006)
snap = np.convolve(snap, np.ones(6) / 6.0, mode='same')
# the ting: three inharmonic partials, quick decay
ting = sum(a * np.sin(2 * np.pi * fr * t) * np.exp(-t / d)
           for fr, a, d in ((2217.0, 1.0, 0.16), (3534.0, 0.5, 0.10), (5310.0, 0.25, 0.06)))
x = 0.9 * drum + 0.5 * snap + 0.16 * ting
x *= np.minimum(1.0, (n - np.arange(n)) / (SR * 0.05))  # fade the tail
x = np.tanh(x * 1.3)
x = x / np.max(np.abs(x)) * 0.89
w = wave.open(OUT, 'wb')
w.setnchannels(1)
w.setsampwidth(2)
w.setframerate(SR)
w.writeframes((x * 32767).astype('<i2').tobytes())
w.close()
print('wrote', OUT)
