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
  <sfx>/tr_disco_to_ent.wav  the disco theme (G minor) -> The Entertainer (C major), inside level 1 (a section's
                           "tier_enter"): the rag's own introduction, the run down D E C A B G, and its pick-up D D#,
                           the cats joining for the second half, over G7 (G is the disco's key note and C's dominant).
  <sfx>/tr_ccb_to_cc.wav   Can-Can's four steps down (D major) -> its famous tune (G major), the pizza going into
                           fever (a section's "fever_enter"): the famous tune's own lead-in, "G D A B, MIAO! MIAO!",
                           cut from the famous tune's stems (the fever's band, one bar early).
  <sfx>/tr_tm_to_cc.wav    Turkish March's second section (A major) -> Can-Can's opening strain (D major): the
                           galop's own lead-in, the vamp on the dominant.

Also the ENDINGS, one per key: the last chord when a level clears (a section's "exit"):
  <sfx>/end_g_minor.wav, end_c_major.wav, end_g_major.wav

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
ENTER_DB = -1.0          # scripts/music/music.gd plays a written transition this much down
CAT = cc.LONG[0]
CAT = CAT.mean(axis=1) if CAT.ndim == 2 else CAT
CAT_MIDI = cc.native(cc.LONG[0])
SFX_SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'deliver', 'sfx')
if not os.path.exists(os.path.join(SFX_SRC, 'orch_hit_Bb.wav')):      # run from the game repo (tools/music_gen)
    SFX_SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'assets', 'audio', 'sfx')


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


def snare(gain):
    """A synth snare for the announcing roll (a short noise burst over a 190 Hz knock)."""
    n = t2n(0.16)
    k = np.arange(n) / SR
    body = np.sin(2 * np.pi * 190 * k * (1 + 0.5 * np.exp(-k / 0.01))) * np.exp(-k / 0.035)
    v = highpass(np.stack([noise(n), noise(n)], 1), 1800) * np.exp(-k / 0.05)[:, None] * 0.9 + body[:, None] * 0.6
    return v * gain


ORCH = None


def render(name, lead, bass, chords, last_slide=0.0, roll=False, accents=()):
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
    if roll:
        # the drums announce the change: two calls, then a roll that tightens (eighths, sixteenths, thirty-seconds)
        # and grows into the bar line. The one exception to "no drums in a transition": a roll is a fill on top of
        # the level's own groove, not a second groove.
        hits = [0, 4, 8, 10, 12, 13, 14, 14.5, 15, 15.5]
        for j, st in enumerate(hits):
            place(x, snare(0.35 + 0.5 * (st / 16) ** 1.5), t2n(st * STEP), 1.0)
    for step, sym, shout in accents:
        # a full-band accent: orchestra hit (the sample is a Bb chord, moved to this chord's root), crash, snare,
        # the chord on the saws, a low octave, and the cats shouting the note in two octaves
        global ORCH
        if ORCH is None:
            from audio import read_wav
            ORCH = read_wav(os.path.join(SFX_SRC, 'orch_hit_Bb.wav'))
        at = t2n(step * STEP)
        notes, root = cc.chord(sym)
        place(x, ORCH, at, 0.8, semitones=(root - nm('A#1')) % 12 if (root - nm('A#1')) % 12 <= 6 else (root - nm('A#1')) % 12 - 12)
        place(x, cc.CRASH, at, 0.45)
        place(x, snare(0.9), at, 1.0)
        n = t2n(3 * STEP)
        k = np.arange(n) / SR
        v = sum(osc_supersaw(mtof(m + o), n, voices=7, detune=0.3) for m in notes for o in (0, 12)) / (2 * len(notes))
        place(x, lowpass(v, 6500) * (np.clip(k / 0.004, 0, 1) * np.exp(-k / 0.16))[:, None], at, 0.7)
        place(x, pan(cc.bass_note(mtof(root + 12), n), 0.0), at, 0.6)
        m = nm(shout)
        place(x, pan(sung(m, 3), 0.15), at, 1.1)
        place(x, pan(sung(m - 12, 3), -0.15), at, 0.7)
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

# Turkish March's second section (A major) -> Can-Can. The pizza starts on the galop's opening strain in D,
# so this is the galop's own lead-in: the vamp on the dominant (A: the note the march ends on) with its little
# grace-note leaps (bars 12-13 of the galop in the MIDI the user supplied, moved to our key), over A7.
render('tr_tm_to_cc',
       lead=[(0, 'A4', 3, 'b'), (3, 'B5', 1, 'i'), (4, 'A5', 3, 'b'), (7, 'B4', 1, 'i'),
             (8, 'A4', 3, 'b'), (11, 'B5', 1, 'i'), (12, 'A5', 2, 'b'), (14, 'C#6', 1, 'i'), (15, 'E6', 1, 'i')],
       bass=[(0, 'A1', 2), (4, 'A1', 2), (8, 'A1', 2), (12, 'A1', 2), (14, 'A1', 2)],
       chords=[(0, 'A7', 4, 'stab'), (8, 'A7', 8, 'swell')], last_slide=7.0)

# The disco theme (G minor) -> The Entertainer (C major), when the house opens in level 1. The rag's own
# introduction (D E C A B G, the top octave of its three) in the game's eighths, then the pick-up the first
# strain starts with (D D#, which lands on the tune's first E on the next bar line). The instrument plays it
# all, the cats come in on the second half, and a snare roll announces the change: the house opening is a
# little climax and The Entertainer comes in at full strength, sung by the cats, on the next bar line.
render('tr_disco_to_ent',
       lead=[(0, 'D6', 2, 'i'), (2, 'E6', 2, 'i'), (4, 'C6', 2, 'i'), (6, 'A5', 2, 'i'),
             (8, 'B5', 2, 'b'), (10, 'G5', 2, 'b'), (12, 'D5', 2, 'b'), (14, 'D#5', 2, 'b')],
       bass=[(0, 'G1', 6), (8, 'G1', 4), (12, 'G1', 4)],
       chords=[(0, 'G', 4, 'stab'), (4, 'G7', 12, 'swell')], roll=True)

# Can-Can: the four steps down (D major) -> the famous tune (G major), the pizza going into its fever.
# What everybody hears in their head before the famous tune is its own lead-in: the end of the galop's phrase,
# "G D A B | MIAO! MIAO!", two accents (G, then D) and the tune starts. So this bar is THE FEVER'S OWN BAND
# arriving one bar early with exactly that: the famous tune is rendered again by the code that makes its stems
# (compose_classics.build: same cats, square lead, pluck, chords, bass, peak layer, cat drums), with its last bar
# rewritten to the phrase ending (bar 28 of the piano MIDI the user supplied), that bar is cut out of every stem
# and mixed at the levels the fever plays them at. On the two accents the cats shout in two more octaves with a
# crash and a big snare; under the run before them a snare fill; a thirty-second roll into the bar line.
# Tried before and dropped: a separate little arrangement (pluck + one cat + orchestra hits: "another sound cut
# in"), and the descent's own band with its last bar varied (the same sound, but not the lead-in people know).
def from_stems(name, base, bar, row, chords, levels, accents=(), play_db=14.0):
    song = dict(cc.SONGS[base])
    lo, hi = bar * 16, bar * 16 + 16
    song['melody'] = sorted([n for n in song['melody'] if not lo <= n[0] < hi] + [(lo + st, p, ln) for st, p, ln in row])
    song['chords'] = list(song['chords'])
    song['chords'][2 * bar:2 * bar + 2] = chords
    with contextlib.redirect_stdout(io.StringIO()):
        L = cc.build(song)
    L['L3_square_dark'] = lowpass(L['L3_square'], 2200)       # the square lead as the fever plays it (make_choir_stems.py)
    x = np.zeros((BAR_N + t2n(0.4), 2))
    for layer, db in levels:
        x[:BAR_N] += L[layer][bar * BAR_N:(bar + 1) * BAR_N] * 10 ** (db / 20)
    f = t2n(0.02)
    x[:f] *= np.linspace(0, 1, f)[:, None]
    for st in (0, 2, 4, 5, 6, 7):                                   # the fill under the run
        place(x, snare(0.35 + 0.03 * st), t2n(st * STEP), 1.0)
    for st, note in accents:                                        # MIAO! MIAO!
        at, m = t2n(st * STEP), nm(note)
        place(x, snare(1.0), at, 1.0)
        place(x, cc.CRASH, at, 0.4)
        place(x, pan(sung(m + 12, 3), 0.25), at, 1.0)
        place(x, pan(sung(m, 3), -0.25), at, 0.9)
    for i in range(4):                                              # the roll into the bar line
        place(x, snare(0.45 + 0.12 * i), t2n((14 + i / 2) * STEP), 1.0)
    f = t2n(0.006)
    x[BAR_N - f:BAR_N] *= np.linspace(1, 0.5, f)[:, None]
    x[BAR_N:] *= np.linspace(0.5, 0, len(x) - BAR_N)[:, None] ** 2      # only the crash and snare tails ring over
    # A full band at the stems' own levels peaks far above 1.0 (in the game the stems are summed as floats), so
    # the file is written play_db lower and the level plays it that much up (the section's "fever_enter_db").
    x = x * 10 ** (-play_db / 20)
    assert np.abs(x).max() < 1.0, np.abs(x).max()
    write_wav(os.path.join(SFX, name + '.wav'), x, peak=None)
    for d in COPIES:
        shutil.copy(os.path.join(SFX, name + '.wav'), os.path.join(d, name + '.wav'))
    print(f'  {name}: {len(x) / SR:.2f} s, peak {np.abs(x).max():.2f}, cut from the stems of {base}')


from_stems('tr_ccb_to_cc', 'can_can', 7,
           row=[(0, 'G4', 2), (2, 'D5', 2), (4, 'A4', 2), (6, 'B4', 2), (8, 'G4', 4), (12, 'D4', 4)],
           chords=['G', 'D7'],
           accents=[(8, 'G4'), (12, 'D4')],
           # the levels of the pizza's fever (levels/music/level_3_spaceship.json: the square on the fx lane -3 dB,
           # the pluck on the kiai lane -2 dB; bass stems are trimmed 4 dB when they are packaged for the game)
           levels=[('L3_cat_kichiku', 0.0), ('L3_square_dark', -3.0), ('L3_pluck', -2.0), ('fb_L0_keys', 0.0),
                   ('L2_bass', -4.0), ('fb_L4_peak', 0.0), ('C_drums', 0.0)])


def ending(name, sym, tonic):
    """The last chord of a level, in the tune's key: played the moment the level clears (the music stops there),
    so it is the downbeat the tune was heading for. A big tonic chord with a kick and a crash, the cats' MIAO on
    the tonic, two little 'mi' after it (fifth, third) and a MIAO an octave up. These have drums: nothing else
    is playing."""
    n = t2n(3.2)
    x = np.zeros((n + t2n(1.5), 2))
    k = np.arange(n) / SR
    notes, root = cc.chord(sym)
    v = sum(osc_supersaw(mtof(m + o), n, voices=7, detune=0.3) * g for m in notes for o, g in ((0, 1.0), (12, 0.6))) / len(notes)
    place(x, lowpass(v, 6000) * (np.clip(k / 0.008, 0, 1) * np.exp(-k / 1.1))[:, None], 0, 0.5)
    place(x, pan(cc.bass_note(mtof(root + 12), t2n(1.6)), 0.0), 0, 0.6)
    place(x, cc.KICK, 0, 0.9)
    place(x, cc.CRASH, 0, 0.5)
    m = nm(tonic)
    third = notes[1] + (12 if notes[1] < m else 0)
    fifth = notes[2] + (12 if notes[2] < m else 0)
    place(x, pan(sung(m, 7), 0.0), 0, 1.0)
    place(x, pan(sung(m - 12, 7), -0.2), 0, 0.5)
    place(x, pan(cc.resonate(cc.mi(fifth, 0.09), cc.lift(fifth), 1.0), 0.25), t2n(8 * STEP), 0.8)
    place(x, pan(cc.resonate(cc.mi(third, 0.09), cc.lift(third), 1.0), -0.25), t2n(10 * STEP), 0.8)
    place(x, pan(sung(m + 12, 6), 0.0), t2n(12 * STEP), 0.9)
    x = reverb(x, 1.8, 0.45, mix=0.2)
    f = t2n(0.2)
    x[-f:] *= np.linspace(1, 0, f)[:, None]
    write_wav(os.path.join(SFX, name + '.wav'), x, peak=0.9)
    for d in COPIES:
        shutil.copy(os.path.join(SFX, name + '.wav'), os.path.join(d, name + '.wav'))
    print(f'  {name}: {len(x) / SR:.2f} s')


ending('end_g_minor', 'Gm', 'G4')      # the disco theme (level 1)
ending('end_c_major', 'C', 'C5')       # Ode to Joy (the sky level)
ending('end_g_major', 'G', 'G4')       # Can-Can (the end of level 2 and of level 3)
print('transitions done ->', SFX)
