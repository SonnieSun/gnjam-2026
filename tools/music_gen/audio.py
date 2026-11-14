"""Small audio toolkit for making the game's loops with nothing but numpy.

Everything is float64 stereo arrays of shape (n, 2) at 44.1 kHz.
  read_wav / write_wav      any PCM or float WAV in; 16-bit WAV out
  osc_*                     band-limited oscillators (PolyBLEP), FM, noise
  adsr                      envelopes
  lowpass / highpass / ...  FFT filters for static EQ, svf() for sweeps
  reverb / delay            room and echoes
  place                     drop a sound into a track at a time, optionally pitched
"""
import struct
import wave

import numpy as np

SR = 44100
rng = np.random.default_rng(160)


# --- files -------------------------------------------------------------------

def read_wav(path):
    """Any WAV (8/16/24/32-bit PCM or 32/64-bit float, mono or stereo) -> (n, 2) at SR."""
    with open(path, 'rb') as f:
        data = f.read()
    assert data[:4] == b'RIFF' and data[8:12] == b'WAVE', path
    pos, fmt, raw = 12, None, None
    while pos + 8 <= len(data):
        cid, size = data[pos:pos + 4], struct.unpack('<I', data[pos + 4:pos + 8])[0]
        body = data[pos + 8:pos + 8 + size]
        if cid == b'fmt ':
            tag, ch, rate, _, _, bits = struct.unpack('<HHIIHH', body[:16])
            if tag == 0xFFFE:  # extensible: the real format is in the sub-format GUID
                tag = struct.unpack('<H', body[24:26])[0]
            fmt = (tag, ch, rate, bits)
        elif cid == b'data':
            raw = body
        pos += 8 + size + (size & 1)
    tag, ch, rate, bits = fmt
    if tag == 3:
        x = np.frombuffer(raw[: len(raw) // (bits // 8) * (bits // 8)], dtype='<f4' if bits == 32 else '<f8').astype(np.float64)
    elif bits == 8:
        x = (np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128) / 128
    elif bits == 16:
        x = np.frombuffer(raw[: len(raw) // 2 * 2], dtype='<i2') / 32768.0
    elif bits == 24:
        b = np.frombuffer(raw[: len(raw) // 3 * 3], dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        v = np.where(v >= 1 << 23, v - (1 << 24), v)
        x = v / float(1 << 23)
    elif bits == 32:
        x = np.frombuffer(raw[: len(raw) // 4 * 4], dtype='<i4') / 2147483648.0
    else:
        raise ValueError(f'{path}: {bits}-bit')
    x = x[: len(x) // ch * ch].reshape(-1, ch)
    x = np.repeat(x, 2, axis=1) if ch == 1 else x[:, :2]
    if rate != SR:
        x = resample(x, SR / rate)
    return x


def write_wav(path, x, peak=None):
    """(n, 2) float -> 16-bit stereo WAV. `peak` normalises to that level first."""
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1:
        x = np.stack([x, x], axis=1)
    if peak is not None:
        x = x * (peak / max(np.max(np.abs(x)), 1e-9))
    pcm = (np.clip(x, -1, 1) * 32767).astype('<i2')
    with wave.open(path, 'wb') as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(pcm.tobytes())


def resample(x, ratio):
    """Stretch by `ratio` (2 = twice as long, an octave down when played at SR)."""
    n = len(x)
    m = max(1, int(round(n * ratio)))
    src = np.arange(m) / ratio
    i = np.clip(src.astype(int), 0, n - 1)
    j = np.clip(i + 1, 0, n - 1)
    f = (src - i)[:, None] if x.ndim == 2 else (src - i)
    return x[i] * (1 - f) + x[j] * f


# --- time --------------------------------------------------------------------

BPM = 160.0
BEAT = 60.0 / BPM
BAR = 4 * BEAT


def t2n(seconds):
    return int(round(seconds * SR))


def beats(b):
    """Beats -> samples."""
    return t2n(b * BEAT)


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


NOTE = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def nm(s):
    """'Bb4' -> MIDI number."""
    i, acc = 1, 0
    while s[i] in '#b':
        acc += 1 if s[i] == '#' else -1
        i += 1
    return 12 * (int(s[i:]) + 1) + NOTE[s[0]] + acc


# --- oscillators -------------------------------------------------------------

def _phase(freq, n):
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    return np.cumsum(f / SR) % 1.0, f / SR


def _blep(t, dt):
    """PolyBLEP correction for a jump at phase 0 (removes most aliasing)."""
    y = np.zeros_like(t)
    a = t < dt
    x = t[a] / dt[a]
    y[a] = x + x - x * x - 1.0
    b = t > 1.0 - dt
    x = (t[b] - 1.0) / dt[b]
    y[b] = x * x + x + x + 1.0
    return y


def osc_saw(freq, n, phase0=0.0):
    t, dt = _phase(freq, n)
    t = (t + phase0) % 1.0
    return 2.0 * t - 1.0 - _blep(t, dt)


def osc_pulse(freq, n, width=0.5, phase0=0.0):
    t, dt = _phase(freq, n)
    t = (t + phase0) % 1.0
    w = np.broadcast_to(np.asarray(width, dtype=np.float64), (n,))
    y = np.where(t < w, 1.0, -1.0)
    y += _blep(t, dt)
    y -= _blep((t - w) % 1.0, dt)
    # A pulse that is not 50/50 sits off zero (12.5% width averages -0.75): take that
    # offset out, or every note thumps in the sub-bass.
    return y - (2.0 * w - 1.0)


def osc_sine(freq, n, phase0=0.0):
    t, _ = _phase(freq, n)
    return np.sin(2 * np.pi * (t + phase0))


def osc_supersaw(freq, n, voices=7, detune=0.18, stereo=0.8):
    """Detuned saw stack, spread across the stereo field. Returns (n, 2)."""
    out = np.zeros((n, 2))
    offs = np.linspace(-1, 1, voices)
    for k, o in enumerate(offs):
        cents = o * detune * 50
        f = np.asarray(freq) * 2 ** (cents / 1200)
        v = osc_saw(f, n, phase0=rng.uniform(0, 1))
        pan = 0.5 + 0.5 * o * stereo
        gain = 1.0 if k == voices // 2 else 0.6
        out[:, 0] += v * gain * np.cos(pan * np.pi / 2)
        out[:, 1] += v * gain * np.sin(pan * np.pi / 2)
    return out / voices * 2.2


def osc_fm(freq, n, ratio=2.0, index=2.0, index_decay=6.0):
    """Two-operator FM: a bell / electric-piano tone whose brightness decays."""
    t = np.arange(n) / SR
    idx = index * np.exp(-t * index_decay)
    mod = np.sin(2 * np.pi * freq * ratio * t) * idx
    return np.sin(2 * np.pi * freq * t + mod)


def noise(n):
    return rng.standard_normal(n)


# --- envelopes -----------------------------------------------------------------

def adsr(n, a=0.005, d=0.1, s=0.7, r=0.08, gate=None):
    """Attack/decay/sustain/release over n samples; the note is held for `gate` seconds."""
    t = np.arange(n) / SR
    gate = n / SR - r if gate is None else gate
    env = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    rel = np.where(t > gate, np.exp(-(t - gate) / max(r / 4, 1e-6)), 1.0)
    return env * rel


def perc(n, decay):
    t = np.arange(n) / SR
    return np.exp(-t / decay)


# --- filters (FFT, for fixed EQ) --------------------------------------------------

def _fft_gain(x, g_of_f):
    mono = x.ndim == 1
    x2 = x[:, None] if mono else x
    n = len(x2)
    F = np.fft.rfft(x2, axis=0)
    f = np.fft.rfftfreq(n, 1 / SR)
    y = np.fft.irfft(F * g_of_f(f)[:, None], n, axis=0)
    return y[:, 0] if mono else y


def lowpass(x, fc, order=2):
    return _fft_gain(x, lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order)))


def highpass(x, fc, order=2):
    return _fft_gain(x, lambda f: 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))


def bandpass(x, lo, hi, order=2):
    return highpass(lowpass(x, hi, order), lo, order)


def svf_lowpass(x, cutoff, q=0.8):
    """State-variable low-pass whose cutoff (Hz, scalar or per sample) can move."""
    n = len(x)
    mono = x.ndim == 1
    x2 = x[:, None] if mono else x
    c = np.broadcast_to(np.asarray(cutoff, dtype=np.float64), (n,))
    g = np.tan(np.pi * np.clip(c, 20, SR * 0.45) / SR)
    k = 1.0 / q
    a1 = 1 / (1 + g * (g + k))
    out = np.zeros_like(x2)
    for ch in range(x2.shape[1]):
        ic1 = ic2 = 0.0
        col = x2[:, ch]
        res = out[:, ch]
        for i in range(n):
            gi = g[i]
            v3 = col[i] - ic2
            v1 = a1[i] * ic1 + gi * a1[i] * v3
            v2 = ic2 + gi * v1
            ic1 = 2 * v1 - ic1
            ic2 = 2 * v2 - ic2
            res[i] = v2
    return out[:, 0] if mono else out


# --- effects -------------------------------------------------------------------

def reverb(x, seconds=1.6, decay=0.45, mix=0.25, lo=250, hi=7000, seed=7):
    """Convolution with a noise tail. Wraps nothing: caller decides about tails."""
    r = np.random.default_rng(seed)
    n = len(x)
    m = int(seconds * SR)
    t = np.arange(m) / SR
    out = np.zeros((n + m, 2))
    for ch in range(2):
        ir = r.standard_normal(m) * np.exp(-t / decay)
        ir[: int(0.01 * SR)] = 0
        ir = bandpass(ir, lo, hi)
        ir /= np.sqrt(np.sum(ir ** 2))
        size = 1 << (n + m - 1).bit_length()
        y = np.fft.irfft(np.fft.rfft(x[:, ch], size) * np.fft.rfft(ir, size), size)[: n + m]
        out[:, ch] = y
    dry = np.zeros((n + m, 2))
    dry[:n] = x
    return dry + out * mix


def delay(x, seconds, feedback=0.35, mix=0.3, repeats=6, pingpong=True):
    d = t2n(seconds)
    out = np.zeros((len(x) + d * repeats, 2))
    out[: len(x)] += x
    g = mix
    for k in range(1, repeats + 1):
        seg = x * g
        if pingpong:
            seg = seg[:, ::-1] if k % 2 else seg
        out[k * d: k * d + len(x)] += seg
        g *= feedback
    return out


def bitcrush(x, bits=6, hold=4):
    """Fewer bits and a lower sample rate: the broken-computer sound."""
    y = x[::hold].repeat(hold, axis=0)[: len(x)]
    q = 2 ** (bits - 1)
    return np.round(y * q) / q


def softclip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def pan(mono, p):
    """Mono -> stereo, p in -1..1."""
    a = (p + 1) * np.pi / 4
    return np.stack([mono * np.cos(a), mono * np.sin(a)], axis=1)


# --- placing sounds -------------------------------------------------------------

def place(track, sound, at_sample, gain=1.0, semitones=0.0):
    """Mix `sound` into `track` starting at `at_sample`, optionally pitched (by resampling)."""
    if semitones:
        sound = resample(sound, 2 ** (-semitones / 12.0))
    if sound.ndim == 1:
        sound = np.stack([sound, sound], axis=1)
    i = int(at_sample)
    j = min(len(track), i + len(sound))
    if j > i >= 0:
        track[i:j] += sound[: j - i] * gain


def wrap(x, length):
    """Fold everything past `length` back onto the start, so a loop's tail rings into its own
    beginning and the seam is seamless."""
    out = x[:length].copy()
    k = length
    while k < len(x):
        seg = x[k: k + length]
        out[: len(seg)] += seg
        k += length
    return out


def rms(x):
    return float(np.sqrt(np.mean(x ** 2)))
