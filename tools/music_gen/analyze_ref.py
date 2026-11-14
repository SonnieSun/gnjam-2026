"""Reads a reference song and prints what a producer would want to know, without listening:
tempo and beat grid, key, chord per bar, the average drum pattern per 16th step, how loud each
band is section by section (the arrangement), and spectrogram PNGs of chosen bars.

usage: python -I analyze_ref.py <png dir> <wav>
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from audio import SR, read_wav  # noqa: E402

sys.stdout.reconfigure(encoding='utf-8')
NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
HOP = 512


def stft(m, win=2048, hop=HOP):
    frames = 1 + (len(m) - win) // hop
    idx = np.arange(win)[None, :] + hop * np.arange(frames)[:, None]
    return np.abs(np.fft.rfft(m[idx] * np.hanning(win), axis=1)), np.fft.rfftfreq(win, 1 / SR)


def band_flux(S, f, lo, hi):
    e = np.log1p(S[:, (f >= lo) & (f < hi)] * 10)
    d = np.maximum(np.diff(e, axis=0), 0).sum(axis=1)
    return np.concatenate([[0], d])


def tempo(onset):
    o = onset - onset.mean()
    ac = np.correlate(o, o, 'full')[len(o) - 1:]
    fps = SR / HOP
    best, bpm = -1, 0
    for b10 in range(1200, 2000):                       # 120.0 - 199.9 BPM
        lag = fps * 60 / (b10 / 10)
        v = np.interp(lag, np.arange(len(ac)), ac) + 0.5 * np.interp(lag * 2, np.arange(len(ac)), ac)
        if v > best:
            best, bpm = v, b10 / 10
    return bpm


def phase(onset, bpm):
    fps = SR / HOP
    period = fps * 60 / bpm
    best, ph = -1, 0
    for p in np.linspace(0, period, 64, endpoint=False):
        t = np.arange(p, len(onset) - 1, period)
        v = onset[t.astype(int)].sum()
        if v > best:
            best, ph = v, p
    return ph / fps                                      # seconds of the first beat


def chroma(S, f, lo=80, hi=2500):
    sel = (f >= lo) & (f < hi)
    midi = np.round(69 + 12 * np.log2(f[sel] / 440)).astype(int) % 12
    C = np.zeros((S.shape[0], 12))
    for k in range(12):
        C[:, k] = (S[:, sel][:, midi == k] ** 2).sum(axis=1)
    return C


MAJ = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
MIN = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])


def key_of(c):
    best = (-9, '')
    for k in range(12):
        for prof, q in ((MAJ, 'major'), (MIN, 'minor')):
            r = np.corrcoef(np.roll(prof, k), c)[0, 1]
            best = max(best, (r, f'{NAMES[k]} {q}'))
    return best[1]


TEMPL = {'': [0, 4, 7], 'm': [0, 3, 7], '7': [0, 4, 7, 10], 'maj7': [0, 4, 7, 11], 'm7': [0, 3, 7, 10]}


def chord_of(c, bass):
    best = (-9, '')
    for r in range(12):
        for q, iv in TEMPL.items():
            t = np.zeros(12)
            t[[(r + i) % 12 for i in iv]] = 1
            score = np.dot(t / np.linalg.norm(t), c / (np.linalg.norm(c) + 1e-9)) + (0.15 if bass == r else 0)
            best = max(best, (score, NAMES[r] + q))
    return best[1]


def spectro_png(m, path, height=200):
    S, f = stft(m)
    edges = np.geomspace(40, 16000, height + 1)
    rows = [S[:, (f >= edges[k]) & (f < edges[k + 1])].mean(axis=1) if np.any((f >= edges[k]) & (f < edges[k + 1])) else np.zeros(S.shape[0]) for k in range(height)]
    img = 20 * np.log10(np.array(rows[::-1]) + 1e-6)
    img = np.clip((img - (img.max() - 70)) / 70, 0, 1)
    rgb = (np.stack([img ** 0.7, img ** 1.6, img ** 3 * 0.6 + img * 0.4], -1) * 255).astype(np.uint8)
    Image.fromarray(rgb).resize((min(1200, rgb.shape[1]), height)).save(path)


if __name__ == '__main__':
    png_dir, path = sys.argv[1], sys.argv[2]
    os.makedirs(png_dir, exist_ok=True)
    x = read_wav(path)
    m = x.mean(axis=1)
    S, f = stft(m)
    on = band_flux(S, f, 30, 8000)
    bpm = tempo(on)
    t0 = phase(band_flux(S, f, 30, 150), bpm)
    beat = 60 / bpm
    nbars = int((len(m) / SR - t0) / (4 * beat))
    print(f'{os.path.basename(path)}: {len(m) / SR:.1f}s  tempo {bpm} BPM  first downbeat~{t0:.2f}s  {nbars} bars')
    C = chroma(S, f)
    print('key:', key_of(C.sum(axis=0)))
    fps = SR / HOP
    # per-bar: chord, energy in bands
    Sb = chroma(S, f, 30, 200)
    bands = [(30, 120), (120, 400), (400, 2000), (2000, 6000), (6000, 16000)]
    print('bar  chord   bass  | energy dB  sub   low   mid   hi    air  | rough instrument guess')
    E_all = []
    lines = []
    for b in range(nbars):
        a, z = int((t0 + b * 4 * beat) * fps), int((t0 + (b + 1) * 4 * beat) * fps)
        if z > len(S):
            break
        bass = int(np.argmax(Sb[a:z].sum(axis=0)))
        ch = chord_of(C[a:z].sum(axis=0), bass)
        E = [10 * np.log10((S[a:z][:, (f >= lo) & (f < hi)] ** 2).sum() + 1e-9) for lo, hi in bands]
        E_all.append(E)
        lines.append((b + 1, ch, NAMES[bass], E))
    E_all = np.array(E_all)
    ref = E_all.max(axis=0)
    for b, ch, bass, E in lines:
        print(f'{b:3d}  {ch:7s} {bass:4s}  | ' + ' '.join(f'{e - r:5.0f}' for e, r in zip(E, ref)))
    # average drum pattern per 16th over bars with drums
    kick = band_flux(S, f, 30, 120)
    snare = band_flux(S, f, 1500, 5000)
    hat = band_flux(S, f, 8000, 16000)
    def pattern(o):
        acc = np.zeros(16)
        cnt = 0
        for b in range(nbars):
            for s in range(16):
                k = int((t0 + b * 4 * beat + s * beat / 4) * fps)
                if k + 2 < len(o):
                    acc[s] += o[max(0, k - 1): k + 2].max()
            cnt += 1
        acc /= max(cnt, 1)
        return acc / (acc.max() + 1e-9)
    print('average drum pattern per 16th (0-9):')
    for name, o in (('kick ', kick), ('snare', snare), ('hat  ', hat)):
        p = pattern(o)
        print('  ' + name + ' ' + ' '.join(''.join(str(min(9, int(v * 9.99))) for v in p[i:i + 4]) for i in range(0, 16, 4)))
    # spectrograms of a few 8-bar stretches
    for start in sorted(set([1, nbars // 4, nbars // 2, 3 * nbars // 4])):
        a = int((t0 + (start - 1) * 4 * beat) * SR)
        z = int((t0 + (start + 7) * 4 * beat) * SR)
        spectro_png(m[a:z], os.path.join(png_dir, f'{os.path.splitext(os.path.basename(path))[0]}_bars{start:03d}.png'))
