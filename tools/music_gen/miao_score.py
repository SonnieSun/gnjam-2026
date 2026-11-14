"""Finds the most 'Miiiiao' meows in a set of recordings: long ones whose pitch rises then falls and
whose vowel goes from a bright 'i' to a dark 'ao'. Prints a ranked list.

usage: python -I miao_score.py <wav or folder> [...]
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import SR, read_wav  # noqa: E402
from psola import f0_track  # noqa: E402
from slicer import slices  # noqa: E402

sys.stdout.reconfigure(encoding='utf-8')


def contour(x):
    f = f0_track(x)
    ok = ~np.isnan(f)
    if ok.sum() < 5:
        return None, 0.0
    m = 69 + 12 * np.log2(f[ok] / 440)
    med = np.median(m)
    m = np.where(m - med > 7, m - 12, np.where(med - m > 7, m + 12, m))      # undo octave slips
    m = np.convolve(m, np.ones(5) / 5, mode='same')
    return m, ok.mean()


def brightness(x, w=1323):
    out = []
    for a in range(0, len(x) - w, w // 2):
        s = np.abs(np.fft.rfft(x[a:a + w] * np.hanning(w)))
        f = np.fft.rfftfreq(w, 1 / SR)
        if (s ** 2).sum() > 1e-6:
            out.append((f * s).sum() / s.sum())
    return np.array(out)


def score(x):
    m, voiced = contour(x)
    if m is None or len(m) < 10:
        return None
    n = len(m)
    start, mid, end = m[: n // 6].mean(), m[n // 3: 2 * n // 3].max(), m[-n // 6:].mean()
    rise, fall = mid - start, mid - end
    c = brightness(x)
    vowel = c[len(c) // 5: len(c) // 2].mean() / max(1.0, c[-len(c) // 4:].mean()) if len(c) > 6 else 1.0
    length = len(x) / SR
    s = (min(rise, 8) + min(fall, 8)) * voiced + 3 * (vowel - 1) + 2 * min(length, 1.3)
    return dict(score=s, rise=rise, fall=fall, vowel=vowel, voiced=voiced, length=length, pitch=float(np.median(m)))


if __name__ == '__main__':
    paths = []
    for p in sys.argv[1:]:
        paths += [os.path.join(p, f) for f in sorted(os.listdir(p)) if f.lower().endswith('.wav')] if os.path.isdir(p) else [p]
    rows = []
    for p in paths:
        if '0926' in p:                       # a person imitating a cat
            continue
        for sl in slices(read_wav(p), min_len=0.6, max_len=2.0, gate_db=-30):
            r = score(sl['audio'].mean(axis=1))
            if r:
                rows.append((r, os.path.basename(p), sl['start'] / SR, sl['end'] / SR))
    for r, name, a, b in sorted(rows, key=lambda t: -t[0]['score'])[:14]:
        print(f"{r['score']:5.1f}  {name[:46]:46s} {a:5.2f}-{b:5.2f}s  len {r['length']:.2f}  rise {r['rise']:4.1f} fall {r['fall']:4.1f} st  "
              f"i->ao {r['vowel']:.2f}  voiced {r['voiced']:.2f}  pitch {r['pitch']:.1f}")
