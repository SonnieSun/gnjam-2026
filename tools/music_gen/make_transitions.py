"""Designed transitions between two tunes: one bar each, a little variation on the tune that is leaving
that walks into the key of the tune that is coming. The music manager plays one on the bar where a level
changes tune (a section's "enter" in levels/music/<level>.json): the drums keep going underneath, the old
tune's chords and bass stop, this one-shot fills the bar, and the new tune starts on the next bar line.
There are NO drums in these (the level's own drum loop is playing; a one-shot can start a few ms late and
two sets of drums would flam).

  <sfx>/tr_ybf_to_mk.wav   Your Best Friend (Ab major) -> Mountain King (A minor), two bars: the washer's band ends
                           its tune, then the metronome counts a bar in over E7 with the tune's pick-up.
  <sfx>/tr_mk_to_cc.wav    Mountain King (A minor) -> Can-Can (G major): "the hall bursts open". The creeping
                           head in sixteenths, running on up the scale and chromatically up to a high D over D7.
  <sfx>/tr_disco_to_ent.wav  the disco theme (G minor) -> The Entertainer (C major), inside level 1: two bars cut
                           from The Entertainer's own stems, the rag's introduction, an accent and its pick-up.
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

# Can-Can: the four steps down (D major) -> the famous tune (G major), the pizza going into its fever.
# What everybody hears in their head before the famous tune is the two accents its phrase starts with:
# "MIAO! MIAO! da-da-da-da DUM DUM" (G, D, then A C B A | D D: bar 21 of the piano MIDI the user supplied; our loop
# starts on the A C B A, so the two accents are the second half of the bar before it). So this bar is THE FEVER'S
# OWN BAND arriving one bar early for exactly that: the famous tune is rendered again by the code that makes its
# stems (compose_classics.build: same cats, square lead, pluck, chords, bass, peak layer, cat drums) with its
# last two bars rewritten, and those bars are cut out of every stem and mixed at the fever's levels.
# Tried before and dropped: a separate little arrangement (pluck + one cat + orchestra hits: "another sound cut
# in"), and the descent's own band with its last bar varied (the same sound, but not the lead-in people know).
def tom(hz, gain):
    """A synth tom for the fill: a sine that drops a fifth, with a little skin noise."""
    n = t2n(0.2)
    k = np.arange(n) / SR
    ph = 2 * np.pi * np.cumsum(hz * (0.67 + 0.33 * np.exp(-k / 0.05))) / SR
    v = np.sin(ph) * np.exp(-k / 0.07)
    skin = lowpass(noise(n), 3000) * np.exp(-k / 0.012) * 0.3
    return np.stack([v + skin, v + skin], 1) * gain


def tick(hz, gain):
    n = t2n(0.09)
    k = np.arange(n) / SR
    tone = (np.sin(2 * np.pi * hz * k) + 0.5 * np.sin(2 * np.pi * hz * 2.76 * k) * np.exp(-k / 0.008)) * np.exp(-k / 0.022)
    click = highpass(np.stack([noise(n), noise(n)], 1), 2500) * np.exp(-k / 0.0025)[:, None] * 0.5
    return (np.stack([tone, tone], 1) + click) * gain * np.clip(k / 0.0005, 0, 1)[:, None]


def game_clips(level, ids, bar):
    """One bar of clips of a level's music file as the level plays them: [(samples of that bar, dB)] for the clip
    ids, read from the game's own files with the lane's and the clip's gain."""
    import json
    from audio import read_wav
    game = os.environ.get('GAME_DIR', 'C:/Users/40389/Desktop/gnjam-2026')
    d = json.load(open(os.path.join(game, 'levels', 'music', level + '.json'), encoding='utf-8'))
    out = []
    for lane in d['lanes']:
        for c in lane['clips']:
            if c['id'] in ids and 'file' in c:
                w = read_wav(os.path.join(game, c['file'].replace('res://', '')))
                out.append((w[bar * BAR_N:(bar + 1) * BAR_N], lane.get('gain_db', 0.0) + c.get('gain_db', 0.0)))
    assert len(out) == len(ids), (ids, len(out))
    return out


def from_stems(name, tune, first_bar, rows, chords, levels, accents, accent_chords, play_db=16.0, accent_gain=1.0, head=None, band_db=0.0,
               extras=('double', 'fill', 'air', 'swell', 'windup'), clicks=False):
    """A transition made by THE BAND THAT IS ABOUT TO PLAY: `tune` is rendered again by the code that makes its
    stems (compose_classics.build) with len(rows) bars from `first_bar` rewritten (rows: one list of
    (step, note, steps) per bar; chords: two per bar), those bars are cut out of every stem and mixed at
    `levels`. Drums and the accents ([(step from the start, note)]) are added on top.
    extras: what is piled on, each can be left out when the result is cluttered: 'double' the notes doubled an
    octave up on the pluck, 'fill' the accelerating snare and toms, 'air' the rising noise, 'swell' the low
    swell, 'windup' the snare over the head bar. clicks: the metronome's four ticks over the last bar."""
    n_bars = len(rows)
    song = dict(cc.SONGS[tune])
    if tune in cc.SPEED:                                           # a tune the game plays at half speed
        song = cc.slowed(song, cc.SPEED[tune])
    if first_bar is None:                                          # the last bars of the tune
        first_bar = len(song['chords']) // 2 - n_bars
    lo, hi = first_bar * 16, (first_bar + n_bars) * 16
    new_notes = [(lo + j * 16 + st, p, ln) for j, row in enumerate(rows) for st, p, ln in row]
    song['melody'] = sorted([n for n in song['melody'] if not lo <= n[0] < hi] + new_notes)
    song['chords'] = list(song['chords'])
    song['chords'][2 * first_bar:2 * (first_bar + n_bars)] = chords
    with contextlib.redirect_stdout(io.StringIO()):
        L = cc.build(song)
    L['L3_square_dark'] = lowpass(L['L3_square'], 2200)       # the square lead as the fever plays it (make_choir_stems.py)
    N = n_bars * BAR_N
    x = np.zeros((N + t2n(0.4), 2))
    for layer, db in levels:
        x[:N] += L[layer][first_bar * BAR_N:first_bar * BAR_N + N] * 10 ** (db / 20)
    f = t2n(0.015)
    x[:f] *= np.linspace(0, 1, f)[:, None]
    first_accent = min([st for st, _ in accents] + [n_bars * 16])
    # the hammered notes doubled an octave up on the pluck, and from the second bar in sixteenths
    for st, pch, ln in new_notes if 'double' in extras else []:
        st -= lo
        if st >= first_accent:
            continue
        reps = 2 if st >= 16 else 1
        for rep in range(reps):
            place(x, cc.pluck(nm(pch) + 12, STEP * (0.9 if reps == 2 else 1.6)), t2n((st + rep) * STEP), 0.4 + 0.5 * st / first_accent)
    # drums: an accelerando into the accents. Before the last half bar the snare goes with the tune (eighths), toms
    # answering at the ends of the half bars. The last half bar before the accents is split in two: its first
    # half in sixteenths, its second half in thirty-seconds (twice as fast again), toms running down the kit
    # under the snare; the very last thirty-second is left empty so the first accent lands in a hole.
    grow = lambda st: st / first_accent
    f0 = first_accent - 8
    do_fill = 'fill' in extras and bool(accents)
    for st, _, _ in [n for row_i, row in enumerate(rows) for n in [(row_i * 16 + q[0], 0, 0) for q in row]]:
        if st < f0 and do_fill:
            place(x, snare(0.4 + 0.3 * grow(st)), t2n(st * STEP), 1.0)
    for st, hz in ((6, 185), (7, 147), (14, 147), (15, 110)):
        if st < f0 and do_fill:
            place(x, tom(hz, 0.5 + 0.2 * grow(st)), t2n(st * STEP), 1.0)
    fast = [f0 + i for i in range(4)] + [f0 + 4 + i / 2 for i in range(7)]      # 4 sixteenths, then 7 thirty-seconds
    for i, st in enumerate(fast if do_fill else []):
        place(x, snare(0.3 + 0.025 * i), t2n(st * STEP), 1.0)
        place(x, tom((220, 220, 185, 185, 165, 165, 147, 147, 123, 110, 98)[i], 0.32 + 0.02 * i), t2n(st * STEP), 1.0)
    # THE TWO ACCENTS. Measured on the version before this one: the kick was the loudest thing in the attack (the
    # pitched part 6 dB under it), the note was gone after a sixteenth (the beat's second half quieter than the
    # fill before it), and G4 / D4 hard-cut meows open dull ("mm") and sit BELOW the hammered D5. So: no kick
    # (the level's own is there), the drums get out of the way (one snare and a crash on each, nothing between
    # them), and the note itself is big and lasts the whole beat: the cats' phrase-ending MIAO (the long shout,
    # not a cut meow) an octave up and at pitch, a kitten 'mi' on its front for the bright attack, and the band
    # hitting the chord with it: saws over three octaves, pluck and square on top.
    band, x = x, np.zeros_like(x)                                   # the accents on their own, so they can be scaled
    for (st, note), sym in zip(accents, accent_chords):
        at, m = t2n(st * STEP), nm(note)
        dur = 4 * STEP * 0.92
        if do_fill:
            place(x, snare(0.7), at, 1.0)
            place(x, cc.CRASH, at, 0.85)                            # the cymbal is meant to be heard on both
        for mm, g in ((m + 12, 2.6), (m, 1.7)):
            place(x, cc.stereo(cc.resonate(cc.shout(mm, dur), cc.lift(mm), 1.0)), at, g)
        place(x, cc.stereo(cc.resonate(cc.mi(m + 12, 0.08), cc.lift(m + 12), 1.0)), at, 1.0)
        # and a kitten's short high 'mi' two octaves up on the very front: what makes it a MIAO and not a chord
        place(x, cc.stereo(cc.resonate(cc.mi(m + 24, 0.09), cc.lift(m + 24), 1.0)), at, 1.6)
        notes, root = cc.chord(sym)
        n = t2n(dur)
        k = np.arange(n) / SR
        v = sum(osc_supersaw(mtof(q + o), n, voices=7, detune=0.3) * g for q in notes for o, g in ((0, 1.0), (12, 0.8), (24, 0.4))) / len(notes)
        place(x, lowpass(v, 7000) * (np.clip(k / 0.004, 0, 1) * np.exp(-k / 1.5) * np.clip((dur - k) / 0.02, 0, 1))[:, None], at, 0.65)
        place(x, pan(cc.bass_note(mtof(root + 12), n), 0.0), at, 0.5)
        place(x, cc.pluck(m + 24, dur), at, 0.8)                    # (the synths were half as loud again: the accents
        place(x, cc.square(m + 12, dur), at, 0.7)                   # outweighed the loop they lead into)
        place(x, cc.square(m, dur), at, 0.45)
    x = band + x * accent_gain
    last = max([st for st, _ in accents] + [0])
    for i in range(2 if do_fill else 0):                            # a short roll into the bar line, after the note
        place(x, snare(0.4 + 0.15 * i), t2n((last + 3 + i / 2) * STEP), 1.0)
    # air rising through the whole thing
    k = np.arange(N) / N
    if 'air' in extras:
        x[:N] += highpass(np.stack([noise(N), noise(N)], 1), 2500) * (k ** 2.5)[:, None] * 0.2
    # and under it the dominant's root an octave down, swelling: weight that the downbeat of the tune releases
    n_sw = t2n(first_accent * STEP)
    kk = np.arange(n_sw) / n_sw
    sw = osc_supersaw(mtof(cc.chord(chords[-2])[1]), n_sw, voices=7, detune=0.3)
    if 'swell' in extras:
        x[:n_sw] += lowpass(sw, 900) * (kk ** 2)[:, None] * 0.5
    if clicks:                                                      # the metronome over the last bar (see count_in below)
        for i in range(4):
            place(x, tick(2100 if i == 0 else 1575, 1.0 if i == 0 else 0.85) * clicks, N - BAR_N + t2n(i * 4 * STEP), 1.0)
    f = t2n(0.006)
    x[N - f:N] *= np.linspace(1, 0.5, f)[:, None]
    x[N:] *= np.linspace(0.5, 0, len(x) - N)[:, None] ** 2          # only the crash and drum tails ring over
    x = x * 10 ** (band_db / 20)                                    # the new band's bars against the level's own (see head)
    if head:
        # One bar in front, played by THE BAND THAT WAS PLAYING: the last bar of its loop, taken from the level's
        # own files at the level's own gains, so the tune that was playing finishes its phrase inside the
        # transition instead of being cut off by it. It fades in over the first beat (in the game those stems
        # fade out over that beat: the two add up to the one band). On top of it the wind-up begins: the snare
        # in quarters, then eighths (the bars after it go on to sixteenths and thirty-seconds), and air rising.
        h = np.zeros((BAR_N, 2))
        for w, db in head:
            h += w * 10 ** (db / 20)
        beat = BAR_N // 4
        h[:beat] *= np.linspace(0, 1, beat)[:, None]
        for i, st in enumerate((0, 4, 8, 10, 12, 14) if 'windup' in extras else ()):
            place(h, snare(0.3 + 0.04 * i), t2n(st * STEP), 1.0)
        k = np.arange(BAR_N) / BAR_N
        h += (0.0 if 'windup' not in extras else 1.0) * highpass(np.stack([noise(BAR_N), noise(BAR_N)], 1), 2500) * (k ** 2)[:, None] * 0.12
        x = np.concatenate([h, x])
        n_bars += 1
    # A full band at the stems' own levels peaks far above 1.0 (in the game the stems are summed as floats), so
    # the file is written play_db lower and the level plays it that much up (the section's "fever_enter_db").
    x = x * 10 ** (-play_db / 20)
    assert np.abs(x).max() < 1.0, np.abs(x).max()
    write_wav(os.path.join(SFX, name + '.wav'), x, peak=None)
    for d in COPIES:
        shutil.copy(os.path.join(SFX, name + '.wav'), os.path.join(d, name + '.wav'))
    print(f'  {name}: {len(x) / SR:.2f} s = {n_bars} bars, peak {np.abs(x).max():.2f}, from the stems of {tune}')


# ================================================================================================================
# THE PIZZA'S TRANSITION INTO ITS FEVER. Edit here, then render (see "to try your own" below).
#
# Now: the melody THE USER WROTE for it (reference/midi_from_user/pizza_transition/user_transition.mid, bars 2-3;
# its bar 1 is the descent itself and its bar 4 the famous tune), arranged for the fever's band. TWO bars, the
# first of them in place of the last bar of the descent's phrase ("fever_enter_replaces": 1 in the level):
#   bar 1            G# A B C# | D A D A      the run up and the galop's vamp on the dominant
#   bar 2, 1st half  D A D A                  the vamp goes on, the pluck above it now in sixteenths, a tom fill
#   bar 2, 2nd half  MIAO! MIAO!              the two accents, both on G
#
# To try your own:
#   rows           one list per bar of the transition; each note is (step, 'note name', length). A bar has 16
#                  steps (sixteenths): step 0 = beat 1, 4 = beat 2, 8 = beat 3, 12 = beat 4. Length 2 = an eighth,
#                  4 = a quarter. Two lists = a two-bar transition.
#   chords         two per bar (one per half bar): 'D', 'D7', 'A7', 'G', 'Em', ...
#   accents        [(step counted from the start of the transition, 'note')]: the big hits (cats shouting, band
#                  chord, snare, crash). accent_chords: the chord under each.
#   levels         which stems of the famous tune play and how loud (dB); leave as is to sound like the fever.
#   Then, from the cat_sound folder:
#       python -I tools/make_transitions.py loops <a folder for the result>
#   and copy <that folder>/tr_ccb_to_cc.wav to gnjam-2026/assets/audio/sfx/ (the game picks it up on the next run).
#   If you change the NUMBER of bars, also set "bars" in levels/music/level_4_spaceship.json (section SPACE
#   PIZZA, "changes" -> "fever") to it, and 'fever_enter_bars' in tools/music_gen/make_music_sets.py so it
#   survives a regenerate. "replaces" there = how many bars at the end of the descent's phrase the transition takes the
#   place of (now 1: the transition's first bar is played instead of the phrase's last; 0 = the phrase is
#   played to its end and the transition comes after it).
#
# The two-bar version with the hammered dominant (bars 18-21 of the piano MIDI the user supplied), for reference:
#   rows=[[(0, 'D5', 2), (2, 'D5', 2), (4, 'D5', 2), (8, 'D5', 2), (10, 'D5', 2), (12, 'D5', 2)],
#         [(0, 'D5', 2), (2, 'D5', 2), (4, 'D5', 2), (6, 'D5', 2), (8, 'G4', 4), (12, 'D4', 4)]],
#   chords=['D', 'D', 'D7', 'G'], accents=[(24, 'G4'), (28, 'D4')]
# ================================================================================================================
from_stems('tr_ccb_to_cc', 'can_can', None,
           rows=[[(0, 'G#4', 2), (2, 'A4', 2), (4, 'B4', 2), (6, 'C#5', 2), (8, 'D5', 2), (10, 'A4', 2), (12, 'D5', 2), (14, 'A4', 2)],
                 [(0, 'D5', 2), (2, 'A4', 2), (4, 'D5', 2), (6, 'A4', 2), (8, 'G4', 4), (12, 'G4', 4)]],
           chords=['A7', 'D', 'D7', 'G'],
           levels=[('L3_cat_kichiku', 0.0), ('L3_square_dark', -3.0), ('L3_pluck', -2.0), ('fb_L0_keys', 0.0),
                   ('L2_bass', -4.0), ('fb_L4_peak', 0.0), ('C_drums', 0.0)],
           accents=[(24, 'G4'), (28, 'G4')], accent_chords=['G', 'G'])

# ================================================================================================================
# LEVEL 1: THE DISCO THEME (G minor) -> THE ENTERTAINER (C major), when the house opens.
# Made the way the pizza's was found to work (the first version here was the kind that did not: a pluck and one
# cat, one bar, a plain snare roll):
#   - THE BAND THAT IS ABOUT TO PLAY, cut from The Entertainer's own stems at the levels the level plays them at
#     (cats in front, the square under them, chords, bass, peak layer, cat drums), arriving two bars early
#   - a tune people know as "it is about to start": the rag's own introduction
#   - drums that accelerate into the accent (eighths with the tune, then sixteenths, then thirty-seconds, toms
#     running down the kit), one thirty-second of nothing before it
#   - one big accent the cats shout (long MIAO, an octave up too, a kitten's high 'mi' on the front, a crash), and
#     then the two notes of the tune's own pick-up as the "MIAO! MIAO!" that throws it onto the first beat
#   bar 1            the disco theme's own band plays the LAST BAR OF ITS LOOP (from the level's files): the tune that
#                    was playing ends its phrase here, with the snare winding up over it. (The version before this
#                    one was The Entertainer's band for both bars: better sounds, but "the front did not connect",
#                    the disco loop was simply cut.) The level waits for the disco loop's 4-bar line for this.
#   bar 2, 1st half  D E C A                  The Entertainer's band: the rag's introduction, the pluck above it in
#                                             sixteenths, the fill (sixteenths, then thirty-seconds)
#   bar 2, beat 3    MIAO!                    the accent on G, the dominant
#   bar 2, beat 4    D  D#                    the pick-up (the first strain starts with these two notes) -> E on the bar line
# Notes are written in the tune's own octave (the cats sing The Entertainer an octave below it).
# In levels/music/level_1_disco.json ("changes" -> "tier" -> "5"): "bars": 2, "replaces": 1 (bar 1 takes the place
# of the disco loop's last bar), "on_bars": 4 (wait for that loop's phrase line), "db": 14.
from_stems('tr_disco_to_ent', 'entertainer', None,
           rows=[[(0, 'D5', 2), (2, 'E5', 2), (4, 'C5', 2), (6, 'A4', 2), (8, 'G5', 4), (12, 'D5', 2), (14, 'D#5', 2)]],
           chords=['G7', 'G7'],
           # level 1 from the house opening: the cats lead, the square 7 dB under them on the fx lane, bass stems
           # are trimmed 4 dB when they are packaged for the game
           levels=[('L3_cat_kichiku', 0.0), ('L3_square', -7.0), ('fb_L0_keys', 0.0), ('L2_bass', -4.0),
                   ('fb_L4_peak', 0.0), ('C_drums', 0.0)],
           accents=[(8, 'G4')], accent_chords=['G7'],
           # measured in context at the pizza's settings the accent was 5.7 dB over the loop it leads into and the
           # whole transition louder than it (there is no fever layer here to catch it: this is 25 % into level 1),
           # so: the accent at 0.6 and The Entertainer's bar 2 dB down (band_db); the disco bar in front is at the level's
           # own level exactly (the file is written 14 dB down and the level plays it at +14)
           accent_gain=0.6, play_db=14.0, band_db=-2.0,
           # what level 1 plays just before the house opens (its stage from 18.6 %), without the drum loop (that
           # one keeps playing in the game): bar 4 of the 4-bar disco loop
           head=game_clips('level_1_disco', ('dt_bass', 'dt_keys', 'dt_cats', 'dt_peak', 'dt_cat_drums'), 3))


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


# ================================================================================================================
# LEVEL 2: THE WASHER -> THE EARTH, Your Best Friend (Ab major) -> In the Hall of the Mountain King (A minor).
# Two bars, which is exactly how long the notes rest when the level changes section there, so the Mountain King's
# first beat is the earth's first note:
#   bar 1   the washer's own band plays the LAST BAR of Your Best Friend, plain (the level's stems at the level's
#           gains: cats, chords, bass, cat drums)
#   bar 2   the metronome's four ticks (the count-in) over the earth's bass and chords on E7, the dominant of
#           A minor (Ab, the key just left, is its third), and on the last beat the pluck's pick-up E G#, whose G#
#           leads into the tune's first A
# Three versions before it were dropped by ear: the old kind (a pluck and one cat, one bar: a 4.6 dB hole in the
# middle of the level), the full treatment of level 1 and the pizza (wind-up, doubled run, tom fill, accent, crash:
# "cluttered", and wrong for a tune that tiptoes in), and a lean one with a small accent.
# In levels/music/level_3_tv_wall.json: "changes" -> "enter" of SLAP / WARM UP, "bars": 2, "db": 14.
from_stems('tr_ybf_to_mk', 'mountain_king', None,
           rows=[[(12, 'E4', 2), (14, 'G#4', 2)]], chords=['E7', 'E7'],
           levels=[('L3_pluck', 0.0), ('fb_L0_keys', -4.0), ('L2_bass', -4.0)],
           accents=[], accent_chords=[], play_db=14.0, band_db=-2.0, extras=(), clicks=1.6,
           head=game_clips('level_3_tv_wall', ('ybf_bass', 'ybf_keys', 'ybf_cats', 'ybf_cat_drums'), 7))


# THE COUNT-IN: one bar of four clicks on the beats, A METRONOME (the first one higher, the way a metronome marks
# the bar). A component of the music manager (scripts/music/music.gd count_in(); a change's "count_in" plays it
# on the first bar of the new part, or on the last bar of its transition): the level leaves that bar empty and
# puts its first note on the next bar line, so the player gets a bar to find the beat. For that bar the manager
# takes the level's own drums and cat drums out (20 dB down) and turns the rest down 7 dB.
# Two versions before this one were drums ("da da da da"): a snare and toms under the full band, which measured
# 0.1-0.4 dB over the band's own claps (inaudible), and sticks + rimshot with the drums ducked. A metronome reads
# as "counting" at once and is not mistaken for part of the groove: a short wooden tick, most of it at 1.5-4 kHz.
def count_in(name):
    x = np.zeros((BAR_N + t2n(0.3), 2))
    for i in range(4):
        place(x, tick(2100 if i == 0 else 1575, 1.0 if i == 0 else 0.85), t2n(i * 4 * STEP), 1.0)
    x = reverb(x, 0.25, 0.2, mix=0.04)[:len(x)]
    write_wav(os.path.join(SFX, name + '.wav'), x, peak=0.95)
    for d in COPIES:
        shutil.copy(os.path.join(SFX, name + '.wav'), os.path.join(d, name + '.wav'))
    print(f'  {name}: {len(x) / SR:.2f} s')


count_in('count_in_4')
