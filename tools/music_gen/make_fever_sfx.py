"""Two one-shot sounds for fever, synthesized from scratch (numpy only, no samples needed):

  assets/audio/sfx/fever_enter.wav   the "level up" as fever starts: a fast arpeggio running up three octaves in
                                     sixteenths (at 160 BPM), landing on a ringing chord with a shimmer, a noise sweep
                                     rising under it. Starts on the bar line fever starts on (scripts/fx/fever_fx.gd).
  assets/audio/sfx/fever_note.wav    the change note's own hit sound (the rainbow note, scripts/fx/note_accents.gd):
                                     a glassy four-note chime going up, a little sparkle, a soft thump under it.

Both are written in a major key, ROOT below (C: The Entertainer in level 1 and Ode to Joy in the sky level, the two
places fever is wired up, are both in C major). For a level in another key change ROOT and write to another name.

usage: python -I make_fever_sfx.py <game project dir>
"""
import os
import sys
import wave

import numpy as np

SR = 44100
BPM = 160.0
STEP = 60.0 / BPM / 4.0        # a sixteenth
ROOT = 60                      # MIDI note of the key (60 = C4)
OUT = os.path.join(sys.argv[1], 'assets', 'audio', 'sfx')
rng = np.random.default_rng(7)


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def blank(seconds):
    return np.zeros((int(seconds * SR), 2))


def place(x, v, at, gain=1.0, pan=0.0):
    """Mix the mono sound v into the stereo buffer x at `at` seconds. pan: -1 left ... 1 right."""
    i = int(at * SR)
    v = v[:max(len(x) - i, 0)]
    x[i:i + len(v), 0] += v * gain * (1.0 - max(pan, 0.0) * 0.7)
    x[i:i + len(v), 1] += v * gain * (1.0 + min(pan, 0.0) * 0.7)


def bell(midi, seconds, bright=1.0):
    """A glassy bell: the note, its octave, and the inharmonic partials of a struck bar, each decaying faster the higher."""
    t = np.arange(int(seconds * SR)) / SR
    f = hz(midi)
    v = np.zeros_like(t)
    for ratio, amp, decay in ((1.0, 1.0, 0.45), (2.0, 0.5, 0.3), (2.76, 0.35 * bright, 0.16), (5.4, 0.2 * bright, 0.08), (8.93, 0.1 * bright, 0.04)):
        if f * ratio < SR * 0.45:
            v += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / (decay * seconds / 0.9))
    return v * np.minimum(t / 0.002, 1.0)


def pluck(midi, seconds):
    """A bright synth pluck: a few saw harmonics, the upper ones dying first."""
    t = np.arange(int(seconds * SR)) / SR
    f = hz(midi)
    v = np.zeros_like(t)
    for k in range(1, 9):
        if f * k < SR * 0.45:
            v += np.sin(2 * np.pi * f * k * t) / k * np.exp(-t * (6.0 + 5.0 * k))
    return v * np.minimum(t / 0.002, 1.0)


def hiss(seconds, rise=False):
    """High noise: a short sparkle (falling) or a sweep (rising)."""
    n = int(seconds * SR)
    v = rng.standard_normal(n)
    v = np.diff(v, prepend=0.0)                 # a crude high-pass
    v = np.diff(v, prepend=0.0)
    t = np.arange(n) / n
    return v / np.max(np.abs(v)) * (t ** 2 if rise else np.exp(-t * 6.0))


def write(name, x, peak):
    x = np.tanh(x * 1.2)
    x = x / np.max(np.abs(x)) * peak
    fade = int(0.03 * SR)
    x[-fade:] *= np.linspace(1.0, 0.0, fade)[:, None]
    path = os.path.join(OUT, name + '.wav')
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype('<i2').tobytes())
    print('  %s.wav  %.2f s  peak %.2f  rms %.3f' % (name, len(x) / SR, np.max(np.abs(x)), np.sqrt(np.mean(x ** 2))))


# --- fever_enter: up the chord in sixteenths, three octaves, then the chord rings ---------------------
x = blank(2.2)
steps = [0, 4, 7, 12, 16, 19, 24, 28, 31]             # root, third, fifth, three times over
for i, s in enumerate(steps):
    at = i * STEP
    k = i / (len(steps) - 1)
    place(x, pluck(ROOT + 12 + s, 0.35), at, 0.55 + 0.25 * k, pan=(k - 0.5) * 0.8)
    place(x, bell(ROOT + 24 + s, 0.5, bright=0.7), at, 0.22 + 0.2 * k, pan=(0.5 - k) * 0.8)
land = len(steps) * STEP                               # the chord: two beats and a bit after the bar line
for s, pan in ((36, 0.0), (40, -0.5), (43, 0.5), (48, 0.0)):
    place(x, bell(ROOT + 12 + s, 1.3), land, 0.5, pan)
    place(x, pluck(ROOT + s, 0.9), land, 0.35, pan)
place(x, hiss(land, rise=True), 0.0, 0.12)
for i in range(10):                                    # the shimmer after the chord: little high bells, scattered
    place(x, bell(ROOT + 48 + int(rng.choice([0, 4, 7, 12, 16])), 0.25, bright=0.5), land + 0.05 + i * 0.06, 0.12 * (1 - i / 12), pan=float(rng.uniform(-1, 1)))
write('fever_enter', x, 0.8)

# --- fever_note: a quick chime up the chord, a sparkle, a thump ----------------------------------------
x = blank(1.0)
for i, s in enumerate((0, 4, 7, 12)):
    place(x, bell(ROOT + 36 + s, 0.7), i * 0.028, 0.5 + 0.12 * i, pan=(i - 1.5) * 0.3)
place(x, hiss(0.25), 0.0, 0.18)
t = np.arange(int(0.18 * SR)) / SR
place(x, np.sin(2 * np.pi * (hz(ROOT - 12) * (1.0 + 0.8 * np.exp(-t / 0.02))) * t) * np.exp(-t / 0.05), 0.0, 0.5)
write('fever_note', x, 0.75)
