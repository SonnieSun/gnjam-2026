"""Prints numbers that describe each drum one-shot, to pick sounds without listening:
length, how fast it dies away, where its energy sits, how hard it hits.

usage: python -I inspect_kit.py <folder> [<folder> ...]
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import SR, read_wav  # noqa: E402


def describe(path):
    x = read_wav(path).mean(axis=1)
    # A 5 ms moving RMS, so a zero crossing is not mistaken for the sound dying away.
    w = int(0.005 * SR)
    env = np.sqrt(np.convolve(x ** 2, np.ones(w) / w, mode='same'))
    peak = np.max(env) + 1e-9
    env = env / peak
    # time to fall 20 dB / 40 dB below the peak, from the peak
    p = int(np.argmax(env))
    after = env[p:]
    t20 = np.argmax(after < 0.1) / SR if np.any(after < 0.1) else len(after) / SR
    t40 = np.argmax(after < 0.01) / SR if np.any(after < 0.01) else len(after) / SR
    spec = np.abs(np.fft.rfft(x[: min(len(x), SR)]))
    f = np.fft.rfftfreq(min(len(x), SR), 1 / SR)
    centroid = float(np.sum(f * spec) / (np.sum(spec) + 1e-9))
    low = float(np.sum(spec[f < 120]) / (np.sum(spec) + 1e-9))
    pk = float(f[np.argmax(spec * (f < 400))]) if np.any(f < 400) else 0.0
    lead = p / SR  # silence or slow attack before the peak
    return dict(len=len(x) / SR, attack=lead, t20=t20, t40=t40, centroid=centroid, low=low, lowpeak=pk, peak=peak)


for folder in sys.argv[1:]:
    print('==', os.path.basename(folder.rstrip('/')))
    for name in sorted(os.listdir(folder)):
        if not name.lower().endswith('.wav'):
            continue
        d = describe(os.path.join(folder, name))
        print(f"{name[-22:]:>22}  len {d['len']:.2f}s  atk {d['attack'] * 1000:5.1f}ms  -20dB {d['t20'] * 1000:6.0f}ms  "
              f"-40dB {d['t40'] * 1000:6.0f}ms  centroid {d['centroid']:6.0f}Hz  low<120 {d['low']:.2f}  lowpeak {d['lowpeak']:4.0f}Hz")
