#!/usr/bin/env python3
"""Analyze a song for the level tool: tempo, beat-0 offset and onsets.

    pip install numpy soundfile        (soundfile only needed for ogg/mp3/flac)
    python3 tools/analyze_song.py songs/my_song.ogg [--bpm 128]

Writes songs/my_song.analysis.json next to the audio:
    { "bpm": 128.0, "offset": 0.412, "duration": 93.1,
      "beats": [sec...], "onsets": [{"t": sec, "s": strength 0..1}...] }

The editor reads it when the song is picked: BPM and offset are filled in,
and "Gen chart" with "from song" builds the chart from the onsets.

Plain numpy on purpose (spectral flux + autocorrelation): no librosa/numba,
so it installs everywhere in a jam. If you KNOW the bpm, pass --bpm and only
the offset is searched. Always check the offset by ear (Metro on): any
beat tracker can be half a beat off.
"""
import argparse
import json
import wave
from pathlib import Path

import numpy as np

HOP = 512  # set per song in analyze(): ~11.6 ms per frame
FRAME = 2048


def load_mono(path: Path) -> tuple[np.ndarray, int]:
    try:
        import soundfile as sf
        y, sr = sf.read(str(path), always_2d=True, dtype="float32")
        return y.mean(axis=1), sr
    except ImportError:
        if path.suffix.lower() != ".wav":
            raise SystemExit("pip install soundfile  (needed for %s)" % path.suffix)
    with wave.open(str(path)) as w:
        sr, ch, width = w.getframerate(), w.getnchannels(), w.getsampwidth()
        raw = w.readframes(w.getnframes())
    dtype = {1: np.uint8, 2: np.int16, 4: np.int32}[width]
    y = np.frombuffer(raw, dtype=dtype).astype(np.float32)
    if width == 1:
        y = (y - 128.0) / 128.0
    else:
        y /= float(np.iinfo(dtype).max)
    return y.reshape(-1, ch).mean(axis=1), sr


def onset_envelope(y: np.ndarray) -> np.ndarray:
    """Spectral flux: how much louder each frequency got since last frame.
    Frame i is centred on sample i * HOP, so frame times line up with audio."""
    n = 1 + len(y) // HOP
    idx = np.arange(FRAME)[None, :] + HOP * np.arange(n)[:, None]
    frames = np.pad(y, (FRAME // 2, FRAME))[idx] * np.hanning(FRAME)[None, :]
    mag = np.log1p(10.0 * np.abs(np.fft.rfft(frames, axis=1)))
    flux = np.maximum(0.0, np.diff(mag, axis=0)).sum(axis=1)
    flux = np.concatenate([[0.0], flux])
    flux -= np.convolve(flux, np.ones(16) / 16, mode="same")  # remove slow loudness drift
    return np.maximum(flux, 0.0)


def pick_onsets(env: np.ndarray, fps: float) -> list[int]:
    w = max(1, int(0.05 * fps))
    avg = np.convolve(env, np.ones(2 * int(0.1 * fps) + 1) / (2 * int(0.1 * fps) + 1), mode="same")
    thresh = avg + 0.08 * env.max()
    out, last = [], -10**9
    for i in range(len(env)):
        lo, hi = max(0, i - w), min(len(env), i + w + 1)
        if env[i] >= thresh[i] and env[i] == env[lo:hi].max() and i - last > w:
            out.append(i)
            last = i
    return out


def estimate_bpm(env: np.ndarray, fps: float) -> float:
    """Autocorrelation of the envelope, weighted towards ~120 bpm."""
    e = env - env.mean()
    ac = np.correlate(e, e, mode="full")[len(e) - 1:]
    bpms = np.arange(60.0, 200.0, 0.05)
    lags = 60.0 * fps / bpms
    score = np.interp(lags, np.arange(len(ac)), ac)
    # Also reward the double lag (a real tempo repeats at 2 beats too).
    score += 0.5 * np.interp(lags * 2, np.arange(len(ac)), ac)
    score *= np.exp(-0.5 * (np.log2(bpms / 120.0) / 0.9) ** 2)
    return float(bpms[int(np.argmax(score))])


def comb_fit(env: np.ndarray, fps: float, bpms: np.ndarray) -> tuple[float, float]:
    """The (bpm, offset) whose beat grid lands on the most onset energy over
    the whole song. Long songs make this precise to a few hundredths of a bpm."""
    t = np.arange(len(env)) / fps
    best = (-1.0, float(bpms[0]), 0.0)
    for bpm in bpms:
        spb = 60.0 / bpm
        for p in np.arange(0.0, spb, 0.5 / fps):
            score = np.interp(np.arange(p, t[-1], spb), t, env).mean()
            if score > best[0]:
                best = (score, float(bpm), float(p))
    return best[1], best[2]


def analyze(path: Path, bpm: float | None = None) -> dict:
    global HOP, FRAME
    y, sr = load_mono(path)
    HOP = 512 if sr >= 32000 else 256
    FRAME = 4 * HOP
    fps = sr / HOP
    env = onset_envelope(y)
    if bpm is None:
        coarse = estimate_bpm(env, fps)
        bpm, offset = comb_fit(env, fps, np.arange(coarse - 1.5, coarse + 1.5, 0.02))
    else:
        bpm, offset = comb_fit(env, fps, np.array([bpm]))
    duration = len(y) / sr
    beats = np.arange(offset, duration, 60.0 / bpm)
    peak = float(env.max()) or 1.0
    onsets = [{"t": round(i / fps, 4), "s": round(float(env[i]) / peak, 3)} for i in pick_onsets(env, fps)]
    return {
        "bpm": round(bpm, 2),
        "offset": round(offset, 4),
        "duration": round(duration, 3),
        "beats": [round(float(b), 4) for b in beats],
        "onsets": onsets,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("songs", nargs="+", type=Path)
    ap.add_argument("--bpm", type=float, help="known tempo: skip tempo detection")
    a = ap.parse_args()
    for song in a.songs:
        data = analyze(song, a.bpm)
        out = song.with_suffix(".analysis.json")
        out.write_text(json.dumps(data, indent=1))
        print(f"{out}: {data['bpm']} bpm, offset {data['offset']} s, {len(data['onsets'])} onsets")


if __name__ == "__main__":
    main()
