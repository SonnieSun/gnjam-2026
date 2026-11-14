"""Pitch and length changes that keep a voice sounding like itself (TD-PSOLA).

Speeding a meow up to raise its pitch also squeezes its vowel up (a chipmunk), and cutting it to
fit a short note throws away the "ao" at the end, which is what makes it a "miao". Here the meow is
cut into one-pitch-period grains and laid down again at the new period: the pitch moves, the vowel
(formants) stays, and the whole m-i-a-o contour is fitted into any length.

  sing(meow, target_midi, seconds) -> mono array: the whole meow at that pitch, that long
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import SR  # noqa: E402

HOP = 220


def f0_track(m, win=1024, fmin=180.0, fmax=1600.0):
    frames = max(1, (len(m) - win) // HOP + 1)
    f0 = np.full(frames, np.nan)
    lo, hi = int(SR / fmax), int(SR / fmin)
    for i in range(frames):
        seg = m[i * HOP: i * HOP + win]
        seg = seg - seg.mean()
        if len(seg) < win or np.sqrt(np.mean(seg ** 2)) < 1e-3:
            continue
        ac = np.fft.irfft(np.abs(np.fft.rfft(seg, 2 * win)) ** 2)[:win]
        if ac[0] <= 0:
            continue
        k = lo + int(np.argmax(ac[lo:hi]))
        if ac[k] > 0.35 * ac[0]:
            f0[i] = SR / k
    return f0


def psola(audio, shift, out_len):
    """Shift by `shift` semitones (keeping the meow's own glide) and fit into out_len samples."""
    m = audio.mean(axis=1) if audio.ndim == 2 else audio
    n = len(m)
    f0 = f0_track(m)
    centers = np.arange(len(f0)) * HOP + 512
    ok = ~np.isnan(f0)
    ratio = 2 ** (shift / 12.0)
    if ok.sum() < 2:                                   # no clear pitch: plain resample
        idx = np.linspace(0, n - 1, out_len)
        return np.interp(idx, np.arange(n), m)
    period = SR / np.interp(np.arange(n), centers[ok], f0[ok])
    marks = []
    t = float(np.argmax(np.abs(m[: int(period[0]) + 1])))
    while t < n:
        marks.append(int(t))
        t += period[int(t)]
    marks = np.array(marks)
    pad = 4000
    out = np.zeros(out_len + 2 * pad)
    a = n / out_len
    s = 0.0
    while s < out_len:
        j = int(np.clip(np.searchsorted(marks, s * a), 0, len(marks) - 1))
        mk = marks[j]
        P = max(8, int(period[mk]))
        # pitching down spaces the grains further apart than one period: make each grain as long as
        # the new spacing so they still overlap (no gaps = no robotic buzz)
        Lh = int(P * max(1.0, 1.0 / ratio))
        g = np.zeros(2 * Lh)
        lo, hi = mk - Lh, mk + Lh
        src = m[max(0, lo): min(n, hi)]
        g[max(0, -lo): max(0, -lo) + len(src)] = src
        g *= np.hanning(2 * Lh)
        c = int(s) + pad
        out[c - Lh: c + Lh] += g / max(ratio, 1.0)
        s += P / ratio
    return out[pad: pad + out_len]


def sing(meow, target, seconds, fade_in=0.003, fade_out=0.025):
    """meow: dict with 'audio' and 'midi' (from the meow kit). Returns a mono array."""
    n = max(t2n_(seconds), 64)
    v = psola(meow['audio'], target - meow['midi'], n)
    fi, fo = min(int(fade_in * SR), n // 4), min(int(fade_out * SR), n // 2)
    v[:fi] *= np.linspace(0, 1, fi)
    v[-fo:] *= np.linspace(1, 0, fo)
    return v


def t2n_(seconds):
    return int(round(seconds * SR))


def midi_contour(m):
    """Per-sample MIDI pitch of a mono signal (octave slips folded back), or None."""
    f0 = f0_track(m)
    ok = ~np.isnan(f0)
    if ok.sum() < 3:
        return None
    centers = np.arange(len(f0)) * HOP + 512
    p = 69 + 12 * np.log2(f0[ok] / 440)
    med = np.median(p)
    p = np.where(p - med > 7, p - 12, np.where(med - p > 7, p + 12, p))
    p = np.convolve(np.pad(p, 2, mode='edge'), np.ones(5) / 5, mode='valid')
    return np.interp(np.arange(len(m)), centers[ok], p)


def sing_miao(audio, target, seconds, keep=0.4, attack_part=0.15, tail_part=0.3):
    """The 'Miiiiao' voice: the meow's main pitch lands on `target`, keeping `keep` of its own slide;
    when the note is longer than the meow, the 'M-i' and the 'ao' stay at natural speed and the 'iii'
    in between is stretched; when shorter, the whole meow is sped up (pitch kept). Mono out."""
    m = audio.mean(axis=1) if audio.ndim == 2 else audio
    n = len(m)
    N = max(64, int(round(seconds * SR)))
    pc = midi_contour(m)
    if pc is None:
        return sing({'audio': audio, 'midi': 60.0}, target, seconds)
    med = float(np.median(pc))
    period = SR / (440 * 2 ** ((pc - 69) / 12))
    marks = []
    t = 0.0
    while t < n:
        marks.append(int(t))
        t += period[int(t)]
    marks = np.array(marks)
    a, b = int(attack_part * n), int(tail_part * n)

    def src_pos(u):
        if N <= n:
            return u * n / N
        if u < a:
            return u
        if u >= N - b:
            return n - (N - u)
        return a + (u - a) * (n - a - b) / max(1, N - a - b)

    pad = 4000
    out = np.zeros(N + 2 * pad)
    s = 0.0
    while s < N:
        ti = src_pos(s)
        j = int(np.clip(np.searchsorted(marks, ti), 0, len(marks) - 1))
        mk = marks[j]
        P = max(8, int(period[mk]))
        want = target + keep * (pc[mk] - med)
        ratio = 2 ** ((want - pc[mk]) / 12)
        Lh = int(P * max(1.0, 1.0 / ratio))
        g = np.zeros(2 * Lh)
        lo = mk - Lh
        src = m[max(0, lo): min(n, mk + Lh)]
        g[max(0, -lo): max(0, -lo) + len(src)] = src
        g *= np.hanning(2 * Lh)
        c = int(s) + pad
        out[c - Lh: c + Lh] += g / max(ratio, 1.0)
        s += P / ratio
    v = out[pad: pad + N]
    fi, fo = min(int(0.003 * SR), N // 4), min(int(0.02 * SR), N // 2)
    v[:fi] *= np.linspace(0, 1, fi)
    v[-fo:] *= np.linspace(1, 0, fo)
    return v
