"""Checks rendered audio without listening:
  - loop seam: the jump between a loop's last and first sample, against its typical step
  - level: peak, RMS, clipped samples
  - where the energy sits: share below 150 Hz, 150 Hz-2 kHz, 2-6 kHz, above 6 kHz
and draws a spectrogram PNG of each file, with bar lines, for looking at.

usage: python -I check_audio.py <png dir> <wav> [<wav> ...]
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
from audio import BAR, SR, read_wav  # noqa: E402

png_dir = sys.argv[1]
os.makedirs(png_dir, exist_ok=True)


def bands(x):
    spec = np.abs(np.fft.rfft(x.mean(axis=1))) ** 2
    f = np.fft.rfftfreq(len(x), 1 / SR)
    tot = spec.sum() + 1e-12
    return [spec[(f >= lo) & (f < hi)].sum() / tot for lo, hi in ((0, 150), (150, 2000), (2000, 6000), (6000, SR))]


def spectrogram(x, path, height=256):
    m = x.mean(axis=1)
    win = 2048
    hop = 512
    frames = 1 + (len(m) - win) // hop
    w = np.hanning(win)
    cols = []
    for i in range(frames):
        seg = m[i * hop: i * hop + win] * w
        cols.append(np.abs(np.fft.rfft(seg)))
    S = np.array(cols).T  # freq x time
    f = np.fft.rfftfreq(win, 1 / SR)
    # log frequency axis 40 Hz - 16 kHz
    edges = np.geomspace(40, 16000, height + 1)
    rows = []
    for k in range(height):
        sel = (f >= edges[k]) & (f < edges[k + 1])
        rows.append(S[sel].mean(axis=0) if np.any(sel) else np.zeros(S.shape[1]))
    img = 20 * np.log10(np.array(rows[::-1]) + 1e-6)
    img = np.clip((img - (img.max() - 70)) / 70, 0, 1)
    rgb = (np.stack([img ** 0.7, img ** 1.6, img ** 3.0 * 0.6 + img * 0.4], axis=-1) * 255).astype(np.uint8)
    pic = Image.fromarray(rgb)
    width = min(pic.width, 1600)
    pic = pic.resize((width, height))
    d = ImageDraw.Draw(pic)
    bar_px = BAR * SR / hop * width / S.shape[1]
    b = 0
    while b * bar_px < width:
        d.line([(b * bar_px, 0), (b * bar_px, 10)], fill=(255, 255, 255))
        d.text((b * bar_px + 2, 10), str(b + 1), fill=(255, 255, 255))
        b += 1
    pic.save(path)


for p in sys.argv[2:]:
    x = read_wav(p)
    name = os.path.basename(p)
    step = np.median(np.abs(np.diff(x, axis=0)))
    seam = np.max(np.abs(x[0] - x[-1]))
    clipped = int(np.sum(np.abs(x) > 0.999))
    lo, mid, hi, air = bands(x)
    print(f'{name:34s} {len(x) / SR:6.2f}s  peak {np.max(np.abs(x)):.2f}  rms {np.sqrt(np.mean(x ** 2)):.3f}  '
          f'clipped {clipped:4d}  seam {seam:.3f} (typical step {step:.4f})  '
          f'<150 {lo:.2f}  150-2k {mid:.2f}  2-6k {hi:.2f}  >6k {air:.2f}')
    spectrogram(x, os.path.join(png_dir, os.path.splitext(name)[0] + '.png'))
