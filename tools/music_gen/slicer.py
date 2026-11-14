"""Cut a recording into one-shots: find where each sound starts, estimate its pitch, and keep
slices you can pitch to any note. Used for vocal chops now and for meows / seal barks later.

  slices(x, min_len, max_len)  -> list of dicts: start, end (samples), audio, midi (or None), level
  detect_midi(audio)           -> estimated MIDI note of the steady part (autocorrelation), or None

As a script: python -I slicer.py <wav>   prints the slices it finds.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import SR, read_wav  # noqa: E402


def envelope(mono, ms=10):
    w = max(1, int(SR * ms / 1000))
    return np.sqrt(np.convolve(mono ** 2, np.ones(w) / w, mode='same'))


def detect_midi(audio, fmin=70.0, fmax=1500.0):
    m = audio.mean(axis=1) if audio.ndim == 2 else audio
    n = len(m)
    seg = m[n // 5: n // 5 + min(n // 2, int(0.12 * SR))]       # the steady middle, not the attack
    if len(seg) < int(SR / fmin) * 2:
        return None
    seg = seg - seg.mean()
    ac = np.correlate(seg, seg, mode='full')[len(seg) - 1:]
    lo, hi = int(SR / fmax), int(SR / fmin)
    if hi >= len(ac):
        return None
    lag = lo + int(np.argmax(ac[lo:hi]))
    if ac[lag] < 0.3 * ac[0]:                                     # no clear period: noise, not a note
        return None
    f = SR / lag
    return 69 + 12 * np.log2(f / 440.0)


def slices(x, min_len=0.08, max_len=0.6, gate_db=-30):
    """Sounds separated by dips of at least `gate_db` below the loudest part."""
    mono = x.mean(axis=1)
    env = envelope(mono)
    thr = np.max(env) * 10 ** (gate_db / 20)
    on = env > thr
    out = []
    i = 0
    n = len(on)
    while i < n:
        if on[i]:
            j = i
            while j < n and on[j]:
                j += 1
            a = max(0, i - int(0.005 * SR))
            b = min(n, j + int(0.03 * SR), a + int(max_len * SR))
            if (b - a) / SR >= min_len:
                audio = x[a:b].copy()
                f = int(0.01 * SR)
                audio[-f:] *= np.linspace(1, 0, f)[:, None]
                out.append(dict(start=a, end=b, audio=audio, midi=detect_midi(audio), level=float(np.max(env[i:j]))))
            i = j
        else:
            i += 1
    return out


if __name__ == '__main__':
    x = read_wav(sys.argv[1])
    print(f'{len(x) / SR:.2f} s')
    for k, s in enumerate(slices(x)):
        midi = f"{s['midi']:.1f}" if s['midi'] is not None else '  - '
        print(f"  {k:2d}  {s['start'] / SR:6.2f}-{s['end'] / SR:6.2f}s  len {(s['end'] - s['start']) / SR:.2f}  midi {midi}  level {s['level']:.3f}")
