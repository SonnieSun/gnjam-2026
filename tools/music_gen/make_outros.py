"""OUTROS: the written ending of a level, a few bars long. The music manager plays one from the next bar line
after the level calls Music.outro() (the moment the player loses control: the notes stop and the ending shot
begins). Every lane except the drums stops, this one-shot is the music until the level clears, and the level's
"exit" chord (make_transitions.py) lands on top of its tail. A section's "outro" in levels/music/<level>.json.
NO drums in these (the level's drum loop keeps going under them).

How long the ending shot is differs by up to a bar (the outro starts on a bar line, the shot does not), so each
one is: the written bars, which always fit, then a tail that rises and fades and can be covered at any point.

  <sfx>/out_ufo_takes_the_cat.wav   level 1 (The Entertainer, C major) -> the sky. 26 beats of ending shot.
        bars 1-2  the rag's own closing phrase, cats and instrument together: the tune says goodbye
        bars 3-4  the tractor beam: the head of that phrase climbs a whole-tone ladder (E, F#, G#, A#), over
                  augmented chords: the key dissolves, the cat leaves the ground
        bars 5-6+ a theremin slides up an octave, a cat's long meow slides up with it, everything fades upward
  <sfx>/out_into_the_ufo.wav        the sky (Ode to Joy, C major) -> level 2. 12 beats of ending shot.
        bars 1-2  the Ode's last phrase (C C D E | D. C C), the cats singing it with the instrument
        bar 3+    the last C opens into a rising arpeggio that fades (the hatch closing behind the cat)

usage: python -I make_outros.py <loops dir> <sfx dir> [<more sfx dirs to copy into>...]
"""
import contextlib
import io
import os
import shutil
import sys

import numpy as np

LOOPS, SFX, COPIES = sys.argv[1], sys.argv[2], sys.argv[3:]
sys.argv = [sys.argv[0], LOOPS, '__none__']
sys.path.insert(0, os.path.dirname(__file__))
with contextlib.redirect_stdout(io.StringIO()):
    import compose_classics as cc
from audio import BAR, SR, highpass, lowpass, mtof, nm, noise, osc_supersaw, pan, place, reverb, t2n, write_wav  # noqa: E402

STEP = BAR / 16
rng = np.random.default_rng(11)
CAT = cc.LONG[0].mean(axis=1) if cc.LONG[0].ndim == 2 else cc.LONG[0]
CAT_MIDI = cc.native(cc.LONG[0])


def sung(midi, steps):
    """A kichiku note from one cat (hard cut), brought into the cat's own range by octaves."""
    while midi - CAT_MIDI > 9:
        midi -= 12
    while CAT_MIDI - midi > 7:
        midi += 12
    return cc.resonate(cc.hit(CAT, CAT_MIDI, midi, steps * STEP * 0.95), midi)


def pad(x, notes, start, steps, peak=0.4, swell=False):
    n = t2n(steps * STEP)
    k = np.arange(n) / n
    v = sum(osc_supersaw(mtof(m), n, voices=5, detune=0.25) for m in notes) / len(notes)
    env = k ** 1.5 if swell else np.clip(k / 0.02, 0, 1) * np.exp(-k * 2.2)
    place(x, lowpass(v, 4800) * env[:, None], t2n(start * STEP), peak)


def lead(x, events):
    """[(step, note, steps, 'i' instrument / 'c' cat / 'b' both)]"""
    for step, note, steps, who in events:
        m = nm(note)
        if who in 'ib':
            place(x, cc.pluck(m, steps * STEP), t2n(step * STEP), 0.75)
        if who in 'cb':
            place(x, pan(sung(m, steps), 0.1), t2n(step * STEP), 0.85)


def bass(x, events):
    for step, note, steps in events:
        place(x, pan(cc.bass_note(mtof(nm(note)), t2n(steps * STEP)), 0.0), t2n(step * STEP), 0.5)


def theremin(x, start, steps, m0, m1, gain=0.3):
    """A sine sliding from m0 to m1 with a vibrato that widens: the flying saucer's own instrument."""
    n = t2n(steps * STEP)
    k = np.arange(n) / n
    midi = m0 + (m1 - m0) * k ** 1.3 + 0.35 * (0.3 + k) * np.sin(2 * np.pi * 6.2 * np.arange(n) / SR)
    ph = 2 * np.pi * np.cumsum(440.0 * 2 ** ((midi - 69) / 12)) / SR
    v = (np.sin(ph) + 0.25 * np.sin(2 * ph)) * np.clip(k / 0.08, 0, 1) * np.clip((1 - k) / 0.45, 0, 1)
    place(x, pan(v, -0.15), t2n(start * STEP), gain)


def cat_slide(x, start, steps, from_midi, semitones, gain=0.6):
    """One long meow whose pitch slides up, looped inside the sample so it lasts."""
    n = t2n(steps * STEP)
    k = np.arange(n) / n
    rate = 2 ** ((from_midi - CAT_MIDI) / 12) * 2 ** (semitones * k ** 1.2 / 12)
    pos = np.mod(np.cumsum(rate), len(CAT) * 0.7) + len(CAT) * 0.05
    v = np.interp(pos, np.arange(len(CAT)), CAT) * np.clip(k / 0.05, 0, 1) * np.clip((1 - k) / 0.5, 0, 1)
    place(x, pan(v, 0.2), t2n(start * STEP), gain)


def air(x, start, steps, gain=0.2):
    n = t2n(steps * STEP)
    k = np.arange(n) / n
    v = highpass(np.stack([noise(n), noise(n)], 1), 3000) * (np.sin(np.pi * k) ** 2)[:, None]
    place(x, v, t2n(start * STEP), gain)


def finish(name, x, tail_from_step, tail_steps):
    """Fade the tail out, a little room, write and copy."""
    x = reverb(x, 1.6, 0.45, mix=0.2)
    a, n = t2n(tail_from_step * STEP), t2n(tail_steps * STEP)
    x = x[:a + n]
    x[a:] *= np.linspace(1, 0, len(x) - a)[:, None] ** 1.5
    write_wav(os.path.join(SFX, name + '.wav'), x, peak=0.85)
    for d in COPIES:
        shutil.copy(os.path.join(SFX, name + '.wav'), os.path.join(d, name + '.wav'))
    print(f'  {name}: {len(x) / SR:.2f} s = {len(x) / SR / BAR:.2f} bars')


# --- level 1: the UFO takes the cat (The Entertainer, C major) ------------------------------------------------
x = np.zeros((t2n(10 * BAR), 2))
# bars 1-2: the closing phrase of the first strain (ENT_B in compose_classics, at the game's speed)
lead(x, [(0, 'E6', 2, 'b'), (2, 'C6', 2, 'b'), (4, 'D6', 2, 'b'), (6, 'E6', 4, 'b'), (10, 'B5', 2, 'b'), (12, 'D6', 4, 'b'),
         (16, 'C6', 10, 'b'), (28, 'D6', 2, 'i'), (30, 'D#6', 2, 'i')])
bass(x, [(0, 'C2', 6), (8, 'G1', 6), (16, 'C2', 10)])
pad(x, cc.chord('C')[0], 0, 8)
pad(x, cc.chord('G7')[0], 8, 8)
pad(x, cc.chord('C')[0], 16, 16)
# bars 3-4: the same four notes up a whole-tone ladder, the cats joining on the first note of every rung
for r, top in enumerate(('E6', 'F#6', 'G#6', 'A#6')):
    s0, m = 32 + r * 8, nm(top)
    for j, d in enumerate((0, -4, -2, 0)):
        place(x, cc.pluck(m + d, 2 * STEP), t2n((s0 + 2 * j) * STEP), 0.7 + 0.05 * r)
    place(x, pan(sung(m, 2), 0.1), t2n(s0 * STEP), 0.85)
    place(x, pan(sung(m, 2), -0.2), t2n((s0 + 6) * STEP), 0.7)
    aug = [60 + 2 * (r % 2) + i for i in (0, 4, 8)]               # C augmented / D augmented: the whole-tone scale
    pad(x, aug, s0, 8, peak=0.3 + 0.04 * r, swell=True)
bass(x, [(32, 'C2', 8), (40, 'D2', 8), (48, 'E2', 8), (56, 'F#2', 8)])
air(x, 32, 64, 0.22)
# bars 5-6 and on: up and away
theremin(x, 60, 68, nm('C6'), nm('C7'), 0.3)
cat_slide(x, 64, 56, nm('C5'), 14.0, 0.6)
pad(x, [60, 64, 68, 72], 64, 48, peak=0.3)
finish('out_ufo_takes_the_cat', x, 80, 48)

# --- the sky: into the UFO (Ode to Joy, C major) --------------------------------------------------------------
x = np.zeros((t2n(7 * BAR), 2))
lead(x, [(0, 'C5', 4, 'b'), (4, 'C5', 4, 'b'), (8, 'D5', 4, 'b'), (12, 'E5', 4, 'b'),
         (16, 'D5', 6, 'b'), (22, 'C5', 2, 'b'), (24, 'C5', 8, 'b')])
bass(x, [(0, 'C2', 8), (8, 'G1', 8), (16, 'G1', 8), (24, 'C2', 16)])
pad(x, cc.chord('C')[0], 0, 8)
pad(x, cc.chord('G')[0], 8, 16)
pad(x, cc.chord('C')[0], 24, 40, peak=0.45)
for j, note in enumerate(('C5', 'E5', 'G5', 'C6', 'E6', 'G6', 'C7', 'E7')):          # the hatch closes: up and out
    place(x, cc.pluck(nm(note), 4 * STEP), t2n((32 + 2 * j) * STEP), 0.6 * (1 - j / 10))
place(x, pan(sung(nm('C5'), 8), 0.0), t2n(32 * STEP), 0.8)
air(x, 24, 40, 0.18)
finish('out_into_the_ufo', x, 40, 32)
print('outros done ->', SFX)
