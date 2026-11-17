"""The written ending of level 3 (TV WALL -> the earth slap) into level 4 (the spaceship): Mountain King (A minor)
turns into the Turkish March (A minor, the game plays it in half time) while the camera follows the cat off the
earth. A section "outro" (levels/music/level_3_tv_wall.json, the last section): the music manager plays it from
the bar line of the final POWER SLAP (EarthSlapSection calls Music.outro() a bar before), every lane stops,
the drums too ("outro_drums": false), so this one has its own drums. 4 bars, one per shot of the ending
(stages/earth_slap/earth_slap_stage.gd, _update_rocket, counts the same beats), then a tail the curtain covers.

  bar 1  IMPACT, Mountain King ENDS     the slap: orchestra hit on A, crash, a sub drop, the cats shout MIAO; then
                                         the tune's own ending: its head (A B C D E C E) once more, and a cadence,
                                         D# E over an E7 stab, A over an A minor stab; a ticking that slows down
                                         under it (the earth's spin running out while the camera pushes in).
  bar 2  THE CAT BURSTS OUT              on E7, the dominant both tunes share: a pop on the downbeat, the Turkish
                                         March's turn (B A G# A) high and bright, the cats sing C, and the turn
                                         again an octave down as the pick-up; a half-time march comes in, a riser.
  bar 3  INTO ORBIT                      the Turkish March's head at the game's half time (C . D C B C), cats and
                                         instrument, over a wide A minor pad, sparkles for the stars. (The BONK
                                         when the cat's head hits a UFO on beat 3 is its own sfx, ufo_bonk.wav,
                                         played by the stage: make_ufo_bonk.py.)
  bar 4  THE DASH                        E . F E on E7, then the tune's next run in sixteenths, twice as fast
                                         (B A G# A B A G# A): the cat accelerates; a snare roll tightens, a meow
                                         slides up an octave, four on the floor.
  tail   the run's last A rings with a crash and air rising: the curtain falls on it, the level clears.

usage: python -I make_earth_to_space.py <loops dir> <sfx dir> [<more sfx dirs to copy into>...]
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
from audio import (BAR, SR, bandpass, highpass, lowpass, mtof, nm, noise, osc_sine, osc_supersaw, pan, place,  # noqa: E402
                   read_wav, reverb, t2n, write_wav)

STEP = BAR / 16
NAME = 'out_earth_to_space'
CAT = cc.LONG[0].mean(axis=1) if cc.LONG[0].ndim == 2 else cc.LONG[0]
CAT_MIDI = cc.native(cc.LONG[0])
ORCH = read_wav(os.path.join(SFX, 'orch_hit_Bb.wav'))
KICK = cc.KICK
rng = np.random.default_rng(31)


def at(step):
    return t2n(step * STEP)


def sung(midi, steps):
    """A kichiku note from one cat (hard cut), brought into the cat's own range by octaves."""
    while midi - CAT_MIDI > 9:
        midi -= 12
    while CAT_MIDI - midi > 7:
        midi += 12
    return cc.resonate(cc.hit(CAT, CAT_MIDI, midi, steps * STEP * 0.95), midi)


def lead(x, events, gain=0.75):
    """[(step, note, steps, 'i' instrument / 'c' cat / 'b' both)]"""
    for step, note, steps, who in events:
        m = nm(note)
        if who in 'ib':
            place(x, cc.pluck(m, steps * STEP), at(step), gain)
        if who in 'cb':
            place(x, pan(sung(m, steps), 0.1), at(step), 0.85)


def bass(x, events, gain=0.5):
    for step, note, steps in events:
        place(x, pan(cc.bass_note(mtof(nm(note)), t2n(steps * STEP)), 0.0), at(step), gain)


def pad(x, sym, step, steps, peak=0.35, swell=False, octave=0, cutoff=4800):
    notes, _ = cc.chord(sym)
    n = t2n(steps * STEP)
    k = np.arange(n) / n
    v = sum(osc_supersaw(mtof(m + octave), n, voices=5, detune=0.25) for m in notes) / len(notes)
    env = (k ** 1.5) * np.clip((1 - k) / 0.15, 0, 1) if swell else np.clip(k / 0.02, 0, 1) * np.exp(-k * 2.2)
    place(x, lowpass(v, cutoff) * env[:, None], at(step), peak)


def snare(gain):
    n = t2n(0.16)
    k = np.arange(n) / SR
    body = np.sin(2 * np.pi * 190 * k * (1 + 0.5 * np.exp(-k / 0.01))) * np.exp(-k / 0.035)
    v = highpass(np.stack([noise(n), noise(n)], 1), 1800) * np.exp(-k / 0.05)[:, None] * 0.9 + body[:, None] * 0.6
    return v * gain


def shaker(gain):
    n = t2n(0.05)
    k = np.arange(n) / SR
    return highpass(np.stack([noise(n), noise(n)], 1), 6000) * np.exp(-k / 0.012)[:, None] * gain


def tick(pitch_hz, gain):
    """A woodblock click: the earth's spin ticking past."""
    n = t2n(0.07)
    k = np.arange(n) / SR
    v = np.sin(2 * np.pi * pitch_hz * k) * np.exp(-k / 0.012)
    v += bandpass(noise(n), 1500, 5000) * np.exp(-k / 0.004) * 0.5
    return pan(v, 0.25 * np.sin(pitch_hz)) * gain


def sub_drop(steps, f0=70.0, f1=32.0, gain=0.9):
    n = t2n(steps * STEP)
    k = np.arange(n) / n
    f = f1 + (f0 - f1) * np.exp(-k * 5.0)
    v = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-k * 3.0) * np.clip(k / 0.01, 0, 1)
    return pan(v, 0.0) * gain


def accent(x, step, sym, shout, big=1.0):
    """orchestra hit (a Bb chord moved to this chord's root), crash, kick, snare, the chord on saws, the cats shout"""
    notes, root = cc.chord(sym)
    shift = (root - nm('A#1')) % 12
    place(x, ORCH, at(step), 0.8 * big, semitones=shift if shift <= 6 else shift - 12)
    place(x, cc.CRASH, at(step), 0.5 * big)
    place(x, KICK, at(step), 0.9)
    place(x, snare(0.8 * big), at(step), 1.0)
    n = t2n(3 * STEP)
    k = np.arange(n) / SR
    v = sum(osc_supersaw(mtof(m + o), n, voices=7, detune=0.3) for m in notes for o in (0, 12)) / (2 * len(notes))
    place(x, lowpass(v, 6500) * (np.clip(k / 0.004, 0, 1) * np.exp(-k / 0.16))[:, None], at(step), 0.6 * big)
    m = nm(shout)
    place(x, pan(sung(m, 3), 0.15), at(step), 1.0 * big)
    place(x, pan(sung(m - 12, 3), -0.15), at(step), 0.65 * big)


def cat_slide(x, step, steps, from_midi, semitones, gain=0.55):
    n = t2n(steps * STEP)
    k = np.arange(n) / n
    rate = 2 ** ((from_midi - CAT_MIDI) / 12) * 2 ** (semitones * k ** 1.4 / 12)
    pos = np.mod(np.cumsum(rate), len(CAT) * 0.7) + len(CAT) * 0.05
    v = np.interp(pos, np.arange(len(CAT)), CAT) * np.clip(k / 0.05, 0, 1) * np.clip((1 - k) / 0.3, 0, 1)
    place(x, pan(v, 0.2), at(step), gain)


def air(x, step, steps, gain=0.2, rise=False):
    n = t2n(steps * STEP)
    k = np.arange(n) / n
    env = k ** 2.5 if rise else np.sin(np.pi * k) ** 2
    v = highpass(np.stack([noise(n), noise(n)], 1), 2500 if rise else 3500) * env[:, None]
    place(x, v, at(step), gain)


TAIL = 24
x = np.zeros((at(64 + TAIL), 2))

# --- bar 1: the slap, then Mountain King ends: its head once more and a cadence into A minor ---------------
accent(x, 0, 'Am', 'A5', big=1.15)
place(x, sub_drop(12), 0, 1.0)
pad(x, 'Am', 2, 10, peak=0.22)
lead(x, [(2, 'A4', 1, 'i'), (3, 'B4', 1, 'i'), (4, 'C5', 1, 'i'), (5, 'D5', 1, 'i'),
         (6, 'E5', 2, 'b'), (8, 'C5', 2, 'i'), (10, 'E5', 2, 'b'),
         (12, 'D#5', 1, 'i'), (13, 'E5', 1, 'i'), (14, 'A4', 2, 'b')])
bass(x, [(0, 'A1', 8), (8, 'A1', 4), (12, 'E2', 2), (14, 'A1', 2)], 0.5)
pad(x, 'E7', 12, 2, peak=0.4)                                             # the cadence: E7 ...
pad(x, 'Am', 14, 2, peak=0.45)                                            # ... A minor
for st, g in ((12, 0.6), (14, 0.8)):
    place(x, KICK, at(st), 0.8)
    place(x, snare(g), at(st), 1.0)
for j, st in enumerate((1, 2, 3, 4, 5, 6, 7.5, 9, 11, 13.5)):            # the spin ticking past, slower and slower
    place(x, tick(1900 - 90 * j, 0.4 * (1 - j / 14)), at(st), 1.0)
place(x, tick(700, 0.45), at(15.5), 1.0)                                  # ... and it stops

# --- bar 2: the cat bursts out of the earth, on E7 -----------------------------------------------------------
place(x, KICK, at(16), 1.0)
place(x, snare(0.7), at(16), 1.0)
place(x, cc.CRASH, at(16), 0.35)
place(x, pan(cc.mi(nm('E6'), 0.12), -0.2), at(16), 0.7)                   # a kitten's 'mi' on the pop
pad(x, 'E7', 16, 16, peak=0.32)
bass(x, [(16, 'E2', 8), (24, 'E2', 4), (28, 'B1', 4)])
lead(x, [(20, 'B5', 1, 'i'), (21, 'A5', 1, 'i'), (22, 'G#5', 1, 'i'), (23, 'A5', 1, 'i'),
         (24, 'C6', 4, 'c'),
         (28, 'B4', 1, 'b'), (29, 'A4', 1, 'b'), (30, 'G#4', 1, 'b'), (31, 'A4', 1, 'b')])
for st in (16, 24):
    place(x, KICK, at(st), 0.85)
for st in (20, 28):
    place(x, snare(0.6), at(st), 1.0)
place(x, cc.RISER, at(16), 0.35)
cat_slide(x, 17, 6, nm('E5'), 5.0, 0.4)

# --- bar 3: off the earth, into space: the Turkish March's head at half time ---------------------------------
lead(x, [(32, 'C5', 4, 'b'), (40, 'D5', 2, 'b'), (42, 'C5', 2, 'b'), (44, 'B4', 2, 'b'), (46, 'C5', 2, 'b')])
pad(x, 'Am', 32, 16, peak=0.38, swell=True, cutoff=6500)
pad(x, 'Am', 32, 16, peak=0.16, swell=True, octave=12, cutoff=9000)
bass(x, [(32, 'A2', 8), (40, 'E2', 8)])
for st in (32, 40):
    place(x, KICK, at(st), 0.8)
for st in (36, 44):
    place(x, snare(0.5), at(st), 1.0)
for st in range(32, 48, 2):
    place(x, shaker(0.35 if st % 4 else 0.2), at(st), 1.0)
for j, note in enumerate(('A6', 'E6', 'C7', 'A6', 'E7', 'C7', 'A6', 'E6')):      # stars going past
    place(x, cc.pluck(nm(note), 2 * STEP) * np.array([1.0 - 0.5 * (j % 2), 0.5 + 0.5 * (j % 2)]), at(33 + 2 * j), 0.28)
air(x, 32, 16, 0.12)

# --- bar 4: the dash -------------------------------------------------------------------------------------------
lead(x, [(48, 'E5', 4, 'b'), (52, 'F5', 2, 'b'), (54, 'E5', 2, 'b')])
lead(x, [(56, 'B5', 1, 'b'), (57, 'A5', 1, 'i'), (58, 'G#5', 1, 'i'), (59, 'A5', 1, 'i'),
         (60, 'B5', 1, 'b'), (61, 'A5', 1, 'i'), (62, 'G#5', 1, 'i'), (63, 'A5', 1, 'i')], gain=0.85)
pad(x, 'E7', 48, 16, peak=0.4, swell=True, cutoff=7000)
bass(x, [(48, 'E2', 8)] + [(56 + 2 * j, 'E2' if j % 2 else 'E3', 2) for j in range(4)])
for st in (48, 52, 56, 60):
    place(x, KICK, at(st), 0.9)
for st in (50, 54, 56, 58, 60, 61, 62, 62.5, 63, 63.5):                 # the roll tightens into the bar line
    place(x, snare(0.3 + 0.6 * ((st - 48) / 16) ** 1.5), at(st), 1.0)
place(x, cc.RISER, at(48), 0.5)
cat_slide(x, 52, 12, nm('E5'), 12.0, 0.55)
air(x, 48, 16, 0.25, rise=True)

# --- tail: the run's A rings out with a crash while the curtain falls ---------------------------------------
place(x, cc.CRASH, at(64), 0.5)
place(x, pan(sung(nm('A5'), 6), 0.0), at(64), 0.8)
place(x, cc.pluck(nm('A5'), 8 * STEP), at(64), 0.6)
pad(x, 'Am', 64, TAIL, peak=0.3)
bass(x, [(64, 'A1', 12)], 0.45)
air(x, 64, TAIL, 0.15)

x = reverb(x, 1.6, 0.45, mix=0.18)
a = at(64 + 4)
x[a:] *= np.linspace(1, 0, len(x) - a)[:, None] ** 1.5
write_wav(os.path.join(SFX, NAME + '.wav'), x, peak=0.85)
for d in COPIES:
    shutil.copy(os.path.join(SFX, NAME + '.wav'), os.path.join(d, NAME + '.wav'))
print(f'  {NAME}: {len(x) / SR:.2f} s = {len(x) / SR / BAR:.2f} bars')
