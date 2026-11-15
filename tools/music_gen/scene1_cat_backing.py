"""Scene 1's cat chords and cat bass (s1_disc_C_stabs_4b / s1_disc_C_bass_4b), thin enough to sit under
a cat lead. compose_disc.py uses these two functions; run this file to re-render only these two stems
without rendering the rest of scene 1.

What changed from the first version (which was muddy under a lead):
  stabs  two cats per hit (were three), 0.08 s (was 0.11), high-pass 280 Hz (was 140), half the room
  bass   notes of 1.25 16ths (were 1.6), the cat 0.13 s (was 0.17) and high-passed, 200-500 Hz down 3 dB

usage: python -I scene1_cat_backing.py <loops dir>      (needs loops/meow_kit and loops/s1_disc)
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import (BAR, adsr, bandpass, highpass, mtof, nm, osc_sine, pan, place, reverb, softclip,  # noqa: E402
                   t2n, wrap)
from psola import sing  # noqa: E402

BARS = 4
LOOP = t2n(BARS * BAR)
STEP = BAR / 16
# Level of each stem against the part it replaces (the eurobeat keys, the bass). The notes are shorter
# than they were, so the same RMS would make every hit louder: these keep a hit about as loud as before.
STABS_LEVEL = 0.8
BASS_LEVEL = 0.87


def _finish(x, target_rms):
    y = wrap(x, LOOP)
    return y * (target_rms / (np.sqrt(np.mean(y ** 2)) + 1e-9))


def cat_stabs(voices, chords, keys_rms):
    """voices: meow-kit entries (dicts with 'audio', 'midi'); chords: [(note names, root name)] per bar."""
    x = np.zeros((LOOP + t2n(2.0), 2))
    for bar, (notes, _) in enumerate(chords):
        top2 = [nm(q) + 12 for q in notes[-2:]]
        for s in [2, 6, 10, 14] + ([15] if bar % 2 else []):
            for i, (m, side) in enumerate(zip(top2, (-0.35, 0.35))):
                v = sing(voices[(i + s) % len(voices)], m, 0.08 if s != 15 else 0.06, fade_out=0.015)
                place(x, pan(v, side), t2n(bar * BAR + s * STEP), 0.6)
    x = highpass(x, 280)
    return _finish(reverb(softclip(x * 1.15, 1.1), 0.5, 0.15, mix=0.03), keys_rms * STABS_LEVEL)


def cat_bass(singers, chords, bass_note, bass_rms):
    """The real bass on the beat, a cat (near its own pitch) with a sine under it on the off-beat octave."""
    x = np.zeros((LOOP + t2n(2.0), 2))
    k = 0
    for bar, (_, root) in enumerate(chords):
        f = mtof(nm(root) + 12)
        r = nm(root) + 36                                          # Eb4-G4: where these cats sing
        for e in range(8):
            at = t2n(bar * BAR + e * 2 * STEP)
            n = t2n(STEP * 1.25)
            if e % 2 == 0:
                place(x, pan(bass_note(f, n), 0.0), at)
            else:
                v = highpass(sing(singers[k % len(singers)], r, 0.13), 250)
                place(x, np.stack([v, v], axis=1), at, 0.9)
                place(x, pan(osc_sine(f, n) * adsr(n, 0.003, 0.05, 0.7, 0.03) * 0.6, 0.0), at)
                k += 1
    x = softclip(x * 1.2, 1.2)
    return _finish(x - 0.3 * bandpass(x, 200, 500), bass_rms * BASS_LEVEL)


CHORDS = [                                   # compose_disc.py CHORDS
    (['G3', 'Bb3', 'D4', 'Eb4'], 'Eb1'),
    (['A3', 'C4', 'Eb4', 'F4'], 'F1'),
    (['A3', 'C4', 'D4', 'F4'], 'D1'),
    (['Bb3', 'D4', 'F4', 'G4'], 'G1'),
]

if __name__ == '__main__':
    import contextlib
    import io

    LOOPS = sys.argv[1]
    S1 = os.path.join(LOOPS, 's1_disc')
    sys.argv = [sys.argv[0], LOOPS, '__none__']          # compose_classics: load everything, render no song
    with contextlib.redirect_stdout(io.StringIO()):
        import compose_classics as cc
    from audio import read_wav, write_wav

    def rms(name):
        return float(np.sqrt(np.mean(read_wav(os.path.join(S1, f's1_disc_{name}_4b.wav')) ** 2)))

    voices = [k for k in cc.KIT if 'ID 0903' in k['src']]
    out = {'C_stabs': cat_stabs(voices, CHORDS, rms('A_L0_keys')),
           'C_bass': cat_bass(voices, CHORDS, cc.bass_note, rms('L2_bass'))}
    for name, x in out.items():
        path = os.path.join(S1, f's1_disc_{name}_4b.wav')
        write_wav(path, x * (1.0 / max(1.0, np.max(np.abs(x)) / 0.98)), peak=None)
        print(path, f'rms {np.sqrt(np.mean(x ** 2)):.3f}  peak {np.max(np.abs(x)):.2f}')
