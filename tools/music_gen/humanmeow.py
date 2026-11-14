"""Clean up a human doing a meow and make it sound more like a cat.

  1 denoise     spectral gate: the quiet parts of the recording are the noise print; every STFT bin
                that is not clearly above it is turned down
  2 trim        quiet start and tail off, so the meow lands on its beat
  3 tone        high-pass 150 Hz (room rumble, mic handling), low-pass 11 kHz (hiss)
  4 cat-ify     shift the formants up (default 4 semitones) without moving the pitch: a human throat
                is longer than a cat's, so the vowel colour sits lower; lifting it is most of what
                makes a person's 'miao' read as a cat. (resample up by k, then TD-PSOLA the pitch back
                down and the length back out, which keeps the raised formants)
  5 level       peak-normalise with a little soft saturation

usage: python -I humanmeow.py <out dir> <recording.wav> <start s> [<start s> ...] [--formant 4]
       writes <out dir>/<recording>_<n>.wav, one per meow, plus a _raw version for comparison
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import SR, highpass, lowpass, read_wav, resample, softclip, write_wav  # noqa: E402
from psola import psola  # noqa: E402
from slicer import slices  # noqa: E402


def denoise(m, n_fft=1024, hop=256, strength=2.0):
    win = np.hanning(n_fft)
    frames = 1 + (len(m) - n_fft) // hop
    idx = np.arange(n_fft)[None, :] + hop * np.arange(frames)[:, None]
    S = np.fft.rfft(m[idx] * win, axis=1)
    mag = np.abs(S)
    energy = (mag ** 2).sum(axis=1)
    quiet = energy <= np.percentile(energy, 30)                 # the quietest 30% of frames = noise
    noise = mag[quiet].mean(axis=0) if quiet.any() else mag.min(axis=0)
    gain = np.clip((mag - strength * noise) / np.maximum(mag, 1e-9), 0.05, 1.0)
    gain = np.apply_along_axis(lambda g: np.convolve(g, np.ones(3) / 3, 'same'), 1, gain)   # no 'musical noise'
    out = np.zeros(len(m))
    norm = np.zeros(len(m))
    y = np.fft.irfft(S * gain, axis=1)
    for i in range(frames):
        out[i * hop: i * hop + n_fft] += y[i] * win
        norm[i * hop: i * hop + n_fft] += win ** 2
    return out / np.maximum(norm, 1e-6)


def trim(m, floor_db=-26, head_db=-18):
    w = int(0.01 * SR)
    env = np.sqrt(np.convolve(m ** 2, np.ones(w) / w, mode='same'))
    keep = np.nonzero(env > env.max() * 10 ** (floor_db / 20))[0]
    loud = np.nonzero(env > env.max() * 10 ** (head_db / 20))[0]
    a = max(0, loud[0] - int(0.015 * SR))
    b = min(len(m), keep[-1] + int(0.03 * SR))
    y = m[a:b].copy()
    y[: int(0.005 * SR)] *= np.linspace(0, 1, int(0.005 * SR))
    y[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))
    return y


def formant_up(m, semitones):
    if semitones == 0:
        return m
    k = 2 ** (semitones / 12)
    up = resample(np.stack([m, m], 1), 1 / k).mean(axis=1)     # pitch and formants up by k, shorter
    return psola(up, -semitones, len(m))                        # pitch back down, length back out


def process(meow, formant=4.0):
    m = denoise(meow)
    m = trim(m)
    m = lowpass(highpass(m[:, None], 150), 11000)[:, 0]
    m = formant_up(m, formant)
    m = m / (np.max(np.abs(m)) + 1e-9)
    return softclip(m * 1.3, 1.2) * 0.9


def centroid(m):
    S = np.abs(np.fft.rfft(m * np.hanning(len(m))))
    f = np.fft.rfftfreq(len(m), 1 / SR)
    return float((f * S).sum() / S.sum())


if __name__ == '__main__':
    args = sys.argv[1:]
    formant = 4.0
    if '--formant' in args:
        i = args.index('--formant')
        formant = float(args[i + 1])
        del args[i: i + 2]
    out_dir, path, starts = args[0], args[1], [float(s) for s in args[2:]]
    os.makedirs(out_dir, exist_ok=True)
    x = read_wav(path).mean(axis=1)
    full = denoise(x)
    base = os.path.splitext(os.path.basename(path))[0]
    for n, start in enumerate(starts, 1):
        sl = min(slices(np.stack([full, full], 1), min_len=0.15, max_len=2.0, gate_db=-26), key=lambda s: abs(s['start'] / SR - start))
        raw = x[sl['start']: sl['end']]
        clean = process(raw, formant)
        write_wav(os.path.join(out_dir, f'{base}_{n}.wav'), np.stack([clean, clean], 1), peak=0.9)
        write_wav(os.path.join(out_dir, f'{base}_{n}_raw.wav'), np.stack([raw, raw], 1), peak=0.9)
        noise_before = 20 * np.log10(np.percentile(np.abs(raw), 20) / np.max(np.abs(raw)) + 1e-9)
        noise_after = 20 * np.log10(np.percentile(np.abs(clean), 20) / np.max(np.abs(clean)) + 1e-9)
        print(f'{base}_{n}: {len(raw) / SR:.2f}s -> {len(clean) / SR:.2f}s  quiet-part level {noise_before:.0f} -> {noise_after:.0f} dB  '
              f'brightness {centroid(raw):.0f} -> {centroid(clean):.0f} Hz')
