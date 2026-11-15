"""Designed transitions between two tunes: one bar each, a little variation on the tune that is leaving
that walks into the key of the tune that is coming. The music manager plays one on the bar where a level
changes tune (a section's "enter" in levels/music/<level>.json): the drums keep going underneath, the old
tune's chords and bass stop, this one-shot fills the bar, and the new tune starts on the next bar line.
There are NO drums in these (the level's own drum loop is playing; a one-shot can start a few ms late and
two sets of drums would flam).

  <sfx>/tr_ybf_to_mk.wav   Your Best Friend (Ab major) -> Mountain King (A minor): "the smile cracks".
                           The friendly head once on the instrument, then again a semitone up sung by a cat,
                           hard-cut, landing on E (the dominant of A minor) over an E7 swell.
  <sfx>/tr_mk_to_cc.wav    Mountain King (A minor) -> Can-Can (G major): "the hall bursts open". The creeping
                           head in sixteenths, running on up the scale and chromatically up to a high D over D7.
  <sfx>/tr_tm_to_cc.wav    Turkish March (A minor) -> Can-Can (G major): the march's turn figure, three times,
                           each a step higher, then a D7 arpeggio up.

usage: python -I make_transitions.py <loops dir> <sfx dir> [<more sfx dirs to copy into>...]
"""
import contextlib
import io
import os
import shutil
import sys

import numpy as np

LOOPS, SFX, COPIES = sys.argv[1], sys.argv[2], sys.argv[3:]
sys.argv = [sys.argv[0], LOOPS, '__none__']          # compose_classics: load the cats, render no song
sys.path.insert(0, os.path.dirname(__file__))
with contextlib.redirect_stdout(io.StringIO()):
    import compose_classics as cc
from audio import BAR, SR, highpass, lowpass, mtof, nm, noise, osc_supersaw, pan, place, reverb, t2n, write_wav  # noqa: E402

STEP = BAR / 16
BAR_N = t2n(BAR)
CAT = cc.LONG[0]
CAT = CAT.mean(axis=1) if CAT.ndim == 2 else CAT
CAT_MIDI = cc.native(cc.LONG[0])


def sung(midi, steps):
    """A kichiku note from one cat (hard cut), brought into the cat's own range by octaves."""
    while midi - CAT_MIDI > 9:
        midi -= 12
    while CAT_MIDI - midi > 7:
        midi += 12
    return cc.resonate(cc.hit(CAT, CAT_MIDI, midi, steps * STEP * 0.95), midi)


def swell(sym, start_step, steps, peak=0.5):
    """A chord that swells into the bar line."""
    n = t2n(steps * STEP)
    k = np.arange(n) / n
    notes, _ = cc.chord(sym)
    v = sum(osc_supersaw(mtof(m), n, voices=5, detune=0.25) for m in notes) / len(notes)
    v = lowpass(v, 5000) * (k ** 1.6)[:, None] * peak
    return v, t2n(start_step * STEP)


def render(name, lead, bass, chords, last_slide=0.0):
    """lead: [(step, note, steps, 'i' instrument / 'c' cat / 'b' both)]; bass: [(step, note, steps)];
    chords: [(step, symbol, steps, 'stab' or 'swell')]. One bar, plus a short tail."""
    x = np.zeros((BAR_N + t2n(0.5), 2))
    for step, note, steps, who in lead:
        at = t2n(step * STEP)
        m = nm(note)
        if who in 'ib':
            place(x, cc.pluck(m, steps * STEP), at, 0.75)
        if who in 'cb':
            place(x, pan(sung(m, steps), 0.1), at, 0.85)
    for step, note, steps in bass:
        n = t2n(steps * STEP)
        place(x, pan(cc.bass_note(mtof(nm(note)), n), 0.0), t2n(step * STEP), 0.5)
    for step, sym, steps, kind in chords:
        if kind == 'swell':
            v, at = swell(sym, step, steps)
            place(x, v, at, 1.0)
        else:
            notes, _ = cc.chord(sym)
            n = t2n(steps * STEP)
            k = np.arange(n) / SR
            v = sum(osc_supersaw(mtof(m), n, voices=5, detune=0.25) for m in notes) / len(notes)
            place(x, lowpass(v, 4200) * np.exp(-k / 0.22)[:, None], t2n(step * STEP), 0.45)
    # air rushing into the bar line
    k = np.arange(BAR_N) / BAR_N
    air = highpass(np.stack([noise(BAR_N), noise(BAR_N)], 1), 2500) * (k ** 3)[:, None] * 0.22
    x[:BAR_N] += air
    if last_slide:
        # the last sung note slides up into the bar line
        n = t2n(4 * STEP)
        kk = np.arange(n) / n
        rate = 2 ** ((nm('D5') - CAT_MIDI) / 12) * 2 ** (last_slide * kk / 12)
        pos = np.mod(np.cumsum(rate), len(CAT) * 0.7) + len(CAT) * 0.05
        v = np.interp(pos, np.arange(len(CAT)), CAT) * np.clip(kk / 0.05, 0, 1) * np.clip((1 - kk) / 0.06, 0, 1)
        place(x, pan(v, -0.1), BAR_N - n, 0.6)
    x = reverb(x, 0.9, 0.35, mix=0.12)
    f = t2n(0.03)
    x[-f:] *= np.linspace(1, 0, f)[:, None]
    write_wav(os.path.join(SFX, name + '.wav'), x, peak=0.85)
    for d in COPIES:
        shutil.copy(os.path.join(SFX, name + '.wav'), os.path.join(d, name + '.wav'))
    print(f'  {name}: {len(x) / SR:.2f} s')


# Your Best Friend (Ab) -> Mountain King (Am): the head, then the head a semitone up, landing on E
render('tr_ybf_to_mk',
       lead=[(0, 'C5', 2, 'i'), (2, 'C5', 1, 'i'), (3, 'C#5', 1, 'i'), (4, 'D#5', 3, 'i'),
             (8, 'C#5', 2, 'b'), (10, 'C#5', 1, 'c'), (11, 'D5', 1, 'c'), (12, 'E5', 4, 'b')],
       bass=[(0, 'G#1', 7), (8, 'E1', 8)],
       chords=[(0, 'Ab', 6, 'stab'), (8, 'E7', 8, 'swell')])

# Mountain King (Am) -> Can-Can (G): the creeping head in sixteenths, then on up to a high D over D7
render('tr_mk_to_cc',
       lead=[(0, 'A4', 1, 'b'), (1, 'B4', 1, 'b'), (2, 'C5', 1, 'b'), (3, 'D5', 1, 'b'),
             (4, 'E5', 1, 'b'), (5, 'C5', 1, 'b'), (6, 'E5', 1, 'b'), (7, 'F#5', 1, 'b'),
             (8, 'G5', 1, 'i'), (9, 'A5', 1, 'i'), (10, 'B5', 1, 'i'), (11, 'C6', 1, 'i'),
             (12, 'C#6', 1, 'i'), (13, 'D6', 3, 'i')],
       bass=[(0, 'A1', 4), (4, 'A1', 4), (8, 'D2', 4), (12, 'D2', 4)],
       chords=[(0, 'Am', 4, 'stab'), (8, 'D7', 8, 'swell')], last_slide=12.0)

# Turkish March (Am) -> Can-Can (G): the turn figure three times, a step higher each time, then D7 up
render('tr_tm_to_cc',
       lead=[(0, 'B4', 1, 'b'), (1, 'A4', 1, 'b'), (2, 'G#4', 1, 'b'), (3, 'A4', 1, 'b'),
             (4, 'C5', 1, 'b'), (5, 'B4', 1, 'b'), (6, 'A#4', 1, 'b'), (7, 'B4', 1, 'b'),
             (8, 'D5', 1, 'b'), (9, 'C5', 1, 'b'), (10, 'B4', 1, 'b'), (11, 'C5', 1, 'b'),
             (12, 'D5', 1, 'i'), (13, 'F#5', 1, 'i'), (14, 'A5', 1, 'i'), (15, 'C6', 1, 'i')],
       bass=[(0, 'A1', 4), (4, 'A1', 4), (8, 'D2', 8)],
       chords=[(0, 'Am', 4, 'stab'), (8, 'D7', 8, 'swell')], last_slide=7.0)
print('transitions done ->', SFX)
