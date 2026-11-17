"""The sky level's dark half, take 2 (2026-11-17, the user's reference: a Deftones record, "this kind of heavy
metal"; the storm should be DOOM metal; the clouds build up into it; and the cats shout rock-style on
quarter-note triplets). Everything at 160 BPM in C minor; the light (the Ode to Joy, C major) comes after.

CLOUDS, quiet and dreamy (Deftones' quiet side: a clean guitar with chorus, maj7 / add9 chords):
  <loops>/sky/sky_dream_gtr_8b.wav    clean chorus guitar picking the chords in 8ths, with a dotted-8th echo.
                                      Chords, two bars each: Cm(add9)  Abmaj7  Ebmaj7/Bb  Fm(add9) -> G7sus
THE BUILD, from about half way through the clouds (Deftones' loud side, the wall of guitars):
  <loops>/sky/sky_fuzz_wall_8b.wav    the same chords as a shoegaze wall: fuzz guitars strummed in 8ths, wide,
                                      each chord swelling in, big reverb
  <loops>/sky/sky_drive_drums_8b.wav  driving drums under the wall: kick, snare on 2 and 4, open 8th hats,
                                      tom fills at the end of every 4 bars, a crash on each 4-bar line
  <sfx>/tr_sky_into_doom.wav          the one bar before the storm (the tier change's written fill): the wall
                                      chokes, a snare roll swells for two beats, then three cat SHOUTS on the
                                      quarter-note triplets of beats 3-4 with the band hitting each one
STORM = DOOM (clip ids start with 'doom_': in the game they are one tune and start from their own bar 1 together
with the doom horns of make_sky.py, whose roots C C Ab G every two bars this follows):
  <loops>/sky/sky_doom_riff_8b.wav    drop-C fuzz guitars, slow and huge, half-time: C | C .. Gb (the tritone,
                                      bent down) | C | C Db (phrygian) | Ab | Ab .. G | G | G chugging 8ths -> 16ths
  <loops>/sky/sky_doom_bass_8b.wav    a fuzz bass an octave under the riff
  <loops>/sky/sky_doom_drums_8b.wav   half-time: kick on 1, a huge roomy snare on 3, crash-ride; the band hits on
                                      the shouts' triplets; the last bar double kick in 16ths
  <loops>/sky/sky_doom_shouts_8b.wav  the cats: a low monster growl on bars 1 and 5; bar 4 beats 3-4: three
                                      shouts on the quarter-note triplets (G); bar 8: six shouts climbing on
                                      quarter-note triplets over the whole bar, into the light

usage: python -I make_sky_metal.py <loops dir> <deliver sfx dir>
"""
import contextlib
import io
import os
import sys

import numpy as np

LOOPS, SFX = sys.argv[1], sys.argv[2]
sys.argv = [sys.argv[0], LOOPS, '__none__']          # compose_classics: load the cats, render no song
sys.path.insert(0, os.path.dirname(__file__))
with contextlib.redirect_stdout(io.StringIO()):
    import compose_classics as cc
from audio import (BAR, SR, bandpass, highpass, lowpass, mtof, noise, osc_saw, osc_sine, pan,  # noqa: E402
                   place, read_wav, reverb, delay, softclip, t2n, wrap, write_wav, resample)

OUT = os.path.join(LOOPS, 'sky')
os.makedirs(OUT, exist_ok=True)
DISC = os.path.join(LOOPS, 's1_disc')
rng = np.random.default_rng(7)
BARS = 8
N = t2n(BARS * BAR)
BAR_N = BAR * SR
BEAT_N = BAR_N / 4
STEP_N = BAR_N / 16


def at(bar, beat=0.0):
    return int(round(bar * BAR_N + beat * BEAT_N))


def level(x, target):
    return x * target / (np.sqrt(np.mean(x ** 2)) + 1e-9)


def save_loop(name, x, target, bars=BARS):
    x = level(wrap(x, t2n(bars * BAR)), target)
    x *= 1.0 / max(1.0, np.max(np.abs(x)) / 0.98)
    write_wav(os.path.join(OUT, f'{name}_{bars}b.wav'), x, peak=None)
    print(f'  {name}_{bars}b: rms {np.sqrt(np.mean(x ** 2)):.3f} peak {np.max(np.abs(x)):.2f}')


def save_sfx(name, x, peak=0.9):
    f = t2n(0.03)
    x[-f:] *= np.linspace(1, 0, f)[:, None]
    write_wav(os.path.join(SFX, name + '.wav'), x, peak=peak)
    print(f'  {name}: {len(x) / SR:.2f} s')


def st_noise(n):
    return np.stack([noise(n), noise(n)], 1)


# --- instruments ---------------------------------------------------------------------------------------

def ks_pluck(midi, seconds, bright=0.5, decay=0.996):
    """A plucked string (Karplus-Strong), computed one period at a time."""
    n = t2n(seconds)
    p = max(2, int(round(SR / mtof(midi))))
    y = np.zeros(n + p)
    burst = noise(p) * 0.8
    burst = lowpass(np.stack([burst, burst], 1), 1500 + 6000 * bright)[:, 0]
    y[:p] = burst
    i = p
    while i < n + p:
        j = min(i + p, n + p)
        seg = y[i - p: j - p]
        prev = y[i - p - 1: j - p - 1] if i - p - 1 >= 0 else np.concatenate([[0.0], y[i - p: j - p - 1]])
        y[i:j] = decay * 0.5 * (seg + prev[: len(seg)])
        i = j
    out = y[p: p + n]
    f = min(t2n(0.02), n // 4)
    out[-f:] *= np.linspace(1, 0, f)
    return out


def chorus(x, depth_ms=3.0, rate=0.6):
    """Two slowly wobbling delayed copies, one per side: the clean guitar's chorus pedal."""
    n = len(x)
    t = np.arange(n) / SR
    out = np.zeros((n, 2))
    mono = x if x.ndim == 1 else x.mean(axis=1)
    for ch, ph in ((0, 0.0), (1, np.pi / 2)):
        d = (7.0 + depth_ms * (1 + np.sin(2 * np.pi * rate * t + ph))) / 1000 * SR
        out[:, ch] = 0.6 * mono + 0.55 * np.interp(np.arange(n) - d, np.arange(n), mono, left=0.0)
    return out


def cab(x):
    """A 4x12 cabinet, roughly: no fizz above 5 kHz, no mud below 80 Hz, a bump in the low mids."""
    return lowpass(highpass(x, 80), 5000) + bandpass(x, 180, 500) * 0.35 + bandpass(x, 1200, 2600) * 0.25


def fuzz_chord(notes, seconds, drive=7.0, mute=0.0, cents=(-7, 6), sides=(-0.9, 0.9), vib=0.0):
    """A distorted chord, two takes panned left and right (slightly different tuning). mute > 0: palm-muted
    (decays in that many seconds). vib: a slow pitch wobble (doom bends and vibrato), in semitones."""
    n = t2n(seconds)
    k = np.arange(n) / SR
    x = np.zeros((n, 2))
    for side, c in zip(sides, cents):
        f = 2 ** (c / 1200)
        v = np.zeros(n)
        for m, g in notes:
            fr = mtof(m) * f * 2 ** (vib * np.sin(2 * np.pi * 5.2 * k) * np.clip(k / 0.6, 0, 1) / 12) if vib else mtof(m) * f
            ph = 2 * np.pi * np.cumsum(np.broadcast_to(fr, (n,))) / SR
            v += g * (2 * ((ph / (2 * np.pi)) % 1.0) - 1)
        env = np.exp(-k / mute) if mute else np.clip((seconds - k) / 0.04, 0, 1)
        v = np.tanh(v * drive) * env * np.clip(k / 0.003, 0, 1)
        x += pan(v, side)
    return x


def bend(midi_from, midi_to, seconds, start=0.3, length=0.8):
    """A pitch curve (in MIDI) for a bend: holds midi_from, then slides to midi_to."""
    k = np.arange(t2n(seconds)) / SR
    s = np.clip((k - start) / length, 0, 1)
    return midi_from + (midi_to - midi_from) * (s * s * (3 - 2 * s))


def fuzz_bent(root_curve, seconds, fifth=True, drive=8.0):
    """A power chord whose root follows a MIDI curve (for the tritone bend)."""
    n = t2n(seconds)
    k = np.arange(n) / SR
    x = np.zeros((n, 2))
    for side, c in ((-0.9, -7), (0.9, 6)):
        v = np.zeros(n)
        for off, g in ((0, 1.0), (7, 0.8), (12, 0.6)) if fifth else ((0, 1.0), (12, 0.6)):
            fr = 440 * 2 ** ((root_curve + off - 69) / 12) * 2 ** (c / 1200)
            ph = np.cumsum(fr) / SR
            v += g * (2 * (ph % 1.0) - 1)
        v = np.tanh(v * drive) * np.clip(k / 0.003, 0, 1) * np.clip((seconds - k) / 0.05, 0, 1)
        x += pan(v, side)
    return x


def power(root, octave=True):
    return [(root, 1.0), (root + 7, 0.85)] + ([(root + 12, 0.6)] if octave else [])


KICK = read_wav(os.path.join(DISC, 's1_disc_kick.wav'))
CLAP = read_wav(os.path.join(DISC, 's1_disc_clap.wav'))
CRASH = read_wav(os.path.join(DISC, 's1_disc_crash.wav'))


def snare(gain=1.0, room=0.0, seconds=0.45):
    """A rock snare: a body (two damped sines), the wires (noise), and the clap layered for crack."""
    n = t2n(seconds)
    k = np.arange(n) / SR
    body = (osc_sine(185, n) * 0.7 + osc_sine(330, n) * 0.35) * np.exp(-k / 0.07)
    wires = bandpass(np.stack([noise(n)] * 2, 1), 1800, 9000)[:, 0] * np.exp(-k / (0.12 + room * 0.25))
    s = pan(body + wires * 0.8, 0.0)
    s[: len(CLAP)] += CLAP[:n] * 0.6
    if room:
        s = reverb(s, 1.6 + room, 0.5, mix=0.25 + 0.3 * room)
    return s * gain


def tom(midi, gain=1.0):
    n = t2n(0.5)
    k = np.arange(n) / SR
    f = mtof(midi) * (1 + 0.5 * np.exp(-k / 0.03))
    v = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-k / 0.22) + lowpass(np.stack([noise(n)] * 2, 1), 2000)[:, 0] * np.exp(-k / 0.02) * 0.3
    return pan(v, 0.0) * gain


def hat(open_=False, gain=1.0):
    n = t2n(0.35 if open_ else 0.06)
    k = np.arange(n) / SR
    v = highpass(st_noise(n), 7000) * np.exp(-k / (0.12 if open_ else 0.018))[:, None]
    return v * gain


# --- the cats ------------------------------------------------------------------------------------------

# The shouts take turns among the cats (each layer from its own pool), so a set of triplets is three different
# voices: the user prefers that. The shout put on the front of a long low meow does NOT take a turn: it is always
# the set the very first triplet shout has (lead and double #13, ours, about G4; the top #6 an octave up; the 'mi'
# of #8), at G4. (Taking turns at C5 it once got a top layer at C6: an odd high meow.)
SHOUT_LEAD, SHOUT_TOP, SHOUT_MI = cc.cat_sample(13), cc.cat_sample(6), cc.cat_sample(8)


def cat_shout(midi, seconds, gang=True, fixed=False):
    """A rock shout: the cats' phrase-ending MIAO at the note, doubled, pitch-FX ringing, a little distortion
    so it sits on top of fuzz guitars, and a short kitten 'mi' on the front so it bites."""
    m = cc.lift(midi)
    if fixed:
        lead = cc.resonate(cc.sing_miao(SHOUT_LEAD, m, max(seconds, 0.3), keep=0.4), m, 0.8)
        low = lead
        hi = cc.sing_miao(SHOUT_TOP, m + 12, max(seconds * 0.8, 0.3), keep=0.4)
        tick = cc.sing_miao(SHOUT_MI, m + 12, 0.3, keep=0.2)[: t2n(0.06)].copy()
        tick[-t2n(0.008):] *= np.linspace(1, 0, t2n(0.008))
    else:
        lead = cc.resonate(cc.shout(midi, seconds, key='rock'), m, 0.8)
        low = cc.resonate(cc.shout(midi - 12, seconds, key='rock_low'), cc.lift(midi - 12), 0.8)
        hi = cc.shout(midi + 12, seconds * 0.8, key='rock_hi')
        tick = cc.mi(midi + 12, 0.06)
    x = cc.stereo(lead)
    if gang:
        x[: len(low)] += cc.stereo(low, -0.4)[: len(x)] * 0.7
        x[: len(hi)] += cc.stereo(hi, 0.4)[: len(x)] * 0.4
    x[: len(tick)] += cc.stereo(tick)[: len(x)] * 0.6
    x = (x + 0.5 * bandpass(x, 1800, 4500)) * 1.4
    return softclip(x, 1.6)


# Take 4, dropped (the user: too shrill, the take-3 shouts are better; kept here for reference, unused):
# candidate #7 (BigSoundBank 'Meow cat 12', 1.5 s, its own pitch about F5). Each shout is the whole meow at its
# natural length, only moved to the note (sung an octave up from the written note, G5-B5, near its own pitch so it
# stays a cat), saturated, with a little room. Shouts closer together than 1.5 s ring over each other.
LONGEST = cc.cat_sample(7)


def long_shout(midi):
    m = midi + 12
    v = cc.sing_miao(LONGEST, m, len(LONGEST) / SR, keep=0.5)
    v = v * 0.25 / (np.sqrt(np.mean(v ** 2)) + 1e-9)
    x = cc.stereo(v)
    x = (x + 0.6 * bandpass(x, 1500, 4500)) * 2.2
    x = np.tanh(x) * 0.7
    return reverb(x, 0.9, 0.35, mix=0.18)


def growl(seconds):
    """The monster: a long cat meow played much slower (its formants drop with it), doubled, distorted."""
    src = cc.LONG[0]
    src = src.mean(axis=1) if src.ndim == 2 else src
    v = resample(src, 2 ** (-14 / 12))[: t2n(seconds)]
    v2 = resample(src, 2 ** (-19 / 12))[: t2n(seconds)]
    v = v[: min(len(v), len(v2))] + 0.7 * v2[: min(len(v), len(v2))]
    v = np.tanh(v * 4.0 / (np.max(np.abs(v)) + 1e-9))
    k = np.arange(len(v)) / SR
    v *= np.clip(k / 0.02, 0, 1) * np.clip((len(v) / SR - k) / 0.3, 0, 1)
    return reverb(cc.stereo(lowpass(np.stack([v, v], 1), 3500)[:, 0]), 1.5, 0.45, mix=0.25)


TRIP = 2.0 / 3.0                                          # a quarter-note triplet, in beats

# ======================================================================================================
print('the clouds')
CLOUD_CHORDS = [  # (bass, voicing), two bars each
    (36, [48, 55, 62, 63, 67]),          # Cm(add9)
    (32, [44, 51, 55, 60, 63]),          # Abmaj7
    (34, [46, 51, 55, 58, 62]),          # Ebmaj7/Bb
    (29, [41, 48, 53, 56, 62]),          # Fm(add9), the second bar G7sus
]
G7SUS = (31, [43, 50, 55, 60, 65])

# --- the clean chorus guitar: 8ths up and down the chord, a dotted-8th echo -----------------------------
x = np.zeros((N + t2n(3.0), 2))
ORDER = [0, 2, 3, 4, 3, 2, 1, 2]                          # which chord tone on each 8th
for bar in range(BARS):
    bass, voice = CLOUD_CHORDS[bar // 2] if not (bar == 7) else G7SUS
    for e in range(8):
        m = voice[ORDER[e]]
        if e == 0:
            place(x, pan(ks_pluck(bass + 12, 1.4, 0.3, 0.997), 0.0), at(bar), 0.5)
        v = ks_pluck(m, 0.9, 0.45, 0.995)
        place(x, pan(v, 0.0), at(bar, e * 0.5), 0.55 if e % 2 == 0 else 0.42)
x = chorus(x[:, 0])
x = delay(x, 0.75 * BAR / 4 * 1.0, feedback=0.35, mix=0.28)
x = reverb(x, 2.4, 0.5, mix=0.3)
save_loop('sky_dream_gtr', x, 0.075)

# --- the wall: the same chords, fuzz strummed in 8ths, swelling in ------------------------------------
x = np.zeros((N + t2n(3.0), 2))
for bar in range(BARS):
    bass, voice = CLOUD_CHORDS[bar // 2] if bar != 7 else G7SUS
    notes = [(bass + 12, 1.0), (bass + 19, 0.7)] + [(m, 0.45) for m in voice[1:]]
    for e in range(8):
        dur = BAR / 8 * 1.05
        ch = fuzz_chord(notes, dur, drive=4.0, cents=(-9, 8))
        g = (0.8 if e % 2 == 0 else 0.6) * (0.55 + 0.45 * ((bar % 2) * 8 + e) / 15)   # each two-bar chord swells
        place(x, ch, at(bar, e * 0.5), g)
x = cab(x)
x = reverb(x, 3.0, 0.6, mix=0.35)
save_loop('sky_fuzz_wall', x, 0.13)

# --- the driving drums ---------------------------------------------------------------------------------
x = np.zeros((N + t2n(2.0), 2))
SN = snare(1.0, 0.3)
for bar in range(BARS):
    fill = bar % 4 == 3
    for b in range(4):
        if not (fill and b == 3):
            place(x, KICK, at(bar, b), 0.9 if b in (0, 2) else 0.0)
    place(x, KICK, at(bar, 1.5), 0.65)
    for b in (1, 3) if not fill else (1,):
        place(x, SN, at(bar, b), 0.9)
    for e in range(8):
        if fill and e >= 6:
            continue
        place(x, hat(open_=e % 2 == 1), at(bar, e * 0.5), 0.35 if e % 2 else 0.25)
    if fill:                                              # tom fill on the last beat: high, mid, floor, floor
        for i, m in enumerate((50, 45, 40, 38)):
            place(x, tom(m), at(bar, 3 + i * 0.25), 0.8)
    if bar % 4 == 0:
        place(x, CRASH, at(bar), 0.55)
save_loop('sky_drive_drums', x, 0.095)

# --- the bar before the storm (written fill) ---------------------------------------------------------
print('into the storm')
x = np.zeros((int(BAR_N) + t2n(2.5), 2))
roll_n = 16
for i in range(roll_n):                                   # beats 1-2: 16ths then 32nds, swelling
    b = i * 0.125
    place(x, snare(1.0, 0.0, 0.2), at(0, b), 0.25 + 0.6 * (i / roll_n) ** 1.5)
sw = t2n(BAR / 2)
k = np.arange(sw) / SR
riser = highpass(st_noise(sw), 2500) * ((k / k[-1]) ** 2)[:, None] * 0.35
place(x, riser, 0)
for j in range(3):                                        # beats 3-4: MIAO! MIAO! MIAO! on the triplets
    pos = at(0, 2 + j * TRIP)
    place(x, cat_shout(67, BAR / 4 * TRIP * 0.95), pos, 0.9)
    place(x, cab(fuzz_chord(power(31), BAR / 4 * TRIP * 0.9, drive=8.0, mute=0.25)), pos, 0.55)
    place(x, CRASH, pos, 0.4)
    place(x, KICK, pos, 0.9)
    place(x, snare(1.0, 0.2), pos, 0.6)
save_sfx('tr_sky_into_doom', x, peak=0.9)

# ======================================================================================================
print('the doom')
# Take 2 (the user: not heavy enough; the climax wants 8th-note drums; try harsh screaming cats on 3-3-2 or
# syncopated 8ths). Bars 1-4: the crushing half-time doom. Bars 5-8: the climax: kick on every 8th, the riff
# chugs in 8ths with ringing accents in 3-3-2 (8ths 1, 4, 7: beats 1, 2.5, 4), the cats scream on the accents.
# The doom horns' roots, two bars each: C C Ab G.
KICK_CLICK = KICK.copy()
_k = np.arange(t2n(0.012)) / SR
KICK_CLICK[: len(_k)] += pan(highpass(np.stack([noise(len(_k))] * 2, 1), 2500)[:, 0] * np.exp(-_k / 0.003), 0.0) * 0.5
A332 = (0.0, 1.5, 3.0)                                    # 3-3-2 in 8ths (the tresillo)
# The climax's accents per bar (bars 5-8), and how long each shout is held (in beats). SKY_ACCENTS=333 renders the
# other version (files end in _333): groups of three 8ths running over the bar line, 3-3-3-3-4 across bars 5-6,
# then a tresillo in bar 7.
VARIANT = os.environ.get('SKY_ACCENTS', '332')
SUFFIX = '' if VARIANT == '332' else '_' + VARIANT
# Take 9 (the user: the climax isn't good, where is the metal shout?): stop-time. In bars 6 and 7 the band only
# hits the accents (a chord choked short, kick, crash, snare; a quiet hi-hat keeps time in the gaps) and the cats
# shout short and together on every hit, the last one held. SKY_CLIMAX=hold renders take 3's held shouts over the
# running band (files end in _hold).
CLIMAX = os.environ.get('SKY_CLIMAX', 'stop')
STOP_BARS = (5,) if CLIMAX == 'stop' else ()            # take 11: only the first of the two stops; bar 7 runs, 3-3-2
SUFFIX += '' if CLIMAX == 'stop' else '_' + CLIMAX
if VARIANT == '333':
    ACC = {4: (0.0, 1.5, 3.0), 5: (0.5, 2.0), 6: A332, 7: (0.0, 1.5)}
    SHOUTS = {4: ((0.0, 1.5, 68), (1.5, 1.5, 68), (3.0, 1.5, 67)), 5: ((0.5, 1.5, 68), (2.0, 2.0, 67)),
              6: ((0.0, 1.5, 67), (1.5, 1.5, 67), (3.0, 1.0, 70))}
else:
    ACC = {4: A332, 5: A332, 6: A332, 7: (0.0, 1.5)}
    SHOUTS = {5: ((0.0, 1.5, 68), (1.5, 1.5, 68), (3.0, 1.0, 67)), 6: ((0.0, 1.5, 67), (1.5, 1.5, 67), (3.0, 1.0, 70))}
SYNC = (0.5, 1.5, 2.5, 3.0)                               # syncopated 8ths: pushed off-beats, landing on 4

HALF = [  # bars 1-4, per bar: (beat, length in beats, root, how)
    [(0, 4, 36, 'ring')],
    [(0, 2, 36, 'ring'), (2, 2, 42, 'bend')],             # C .. Gb, bent down a semitone
    [(0, 4, 36, 'ring')],
    [(0, 1, 36, 'ring'), (1, 1, 37, 'ring'), (2, TRIP, 31, 'hit'), (2 + TRIP, TRIP, 31, 'hit'), (2 + 2 * TRIP, TRIP, 31, 'hit')],
]
CLIMAX_ROOTS = (32, 32, 31, 31)                           # bars 5-8: Ab Ab G G (the last bar chugs into 16ths)


def climax_bar(root, last, acc, stop=False):
    if stop:
        nxt = list(acc[1:]) + [4.0]                       # take 12: each hit rings almost to the next (fuller)
        return [(b, (b2 - b) * 0.9, root, 'stab') for b, b2 in zip(acc, nxt)]
    if last:                                              # take 10: the bar into the Ode is straight 8ths (the chart's 8th run)
        return [(e * 0.5, 0.5, root, 'drive') for e in range(8)]
    out = []
    for e in range(8):
        b = e * 0.5
        ring = min([a for a in acc if a > b] + [4.0]) - b
        out.append((b, ring if b in acc else 0.5, root + (1 if (e == 7 and not last) else 0), 'ring' if b in acc else 'chug'))
    return out


RIFF = HALF + [climax_bar(r, i == 3, ACC[4 + i], (4 + i) in STOP_BARS) for i, r in enumerate(CLIMAX_ROOTS)]
DRIVE = 13.0                                              # more gain than take 1


def heavy(notes, sec, mute=0.0, vib=0.0):
    """Four takes (two each side, different tuning) and a sub octave: a wall, not one guitar."""
    a = fuzz_chord(notes, sec, drive=DRIVE, mute=mute, cents=(-8, 7), vib=vib)
    b = fuzz_chord(notes, sec, drive=DRIVE, mute=mute, cents=(4, -11), sides=(-0.6, 0.6), vib=vib)
    sub = fuzz_chord([(notes[0][0] - 12, 1.0)], sec, drive=6.0, mute=mute, sides=(-0.2, 0.2))
    return a + b * 0.8 + sub * 0.5


# --- the riff ------------------------------------------------------------------------------------------
x = np.zeros((N + t2n(3.0), 2))
for bar, notes in enumerate(RIFF):
    for beat, length, root, how in notes:
        sec = length * BAR / 4
        if how == 'bend':
            ch = fuzz_bent(bend(root, root - 1, sec * 1.02, 0.25, 0.9), sec * 1.02, drive=DRIVE) * 1.6
        elif how == 'chug':
            ch = heavy(power(root, False), sec * 0.85, mute=0.06)
        elif how == 'hit':
            ch = heavy(power(root), sec * 0.92, mute=0.2)
        elif how == 'drive':                              # the 8ths into the Ode: fuller chugs, getting louder
            ch = heavy(power(root), sec * 0.9, mute=0.12) * (0.8 + 0.35 * beat / 3.5)
        elif how == 'stab':
            ch = heavy(power(root), sec * 0.85) * 1.15     # rings for an 8th, then choked
        else:
            ch = heavy(power(root), sec * 1.02, vib=0.04)
        place(x, ch, at(bar, beat), 0.75 if how == 'chug' else 1.0)
x = lowpass(highpass(x, 70), 5200) + bandpass(x, 90, 250) * 0.5 + bandpass(x, 1500, 3000) * 0.3 - bandpass(x, 400, 800) * 0.3
x = reverb(x, 1.6, 0.45, mix=0.14)
save_loop('sky_doom_riff' + SUFFIX, x, 0.15)

# --- the bass ------------------------------------------------------------------------------------------
x = np.zeros((N + t2n(2.0), 2))
for bar, notes in enumerate(RIFF):
    for beat, length, root, how in notes:
        sec = length * BAR / 4
        n = t2n(sec * (0.9 if how in ('chug', 'hit') else 1.0))
        k = np.arange(n) / SR
        m = bend(root - 12, root - 13, sec, 0.25, 0.9)[:n] if how == 'bend' else np.full(n, float(root - 12))
        ph = np.cumsum(440 * 2 ** ((m - 69) / 12)) / SR
        v = np.sin(2 * np.pi * ph) * 0.8 + np.tanh((2 * (ph % 1.0) - 1) * 4.0) * 0.5
        v *= np.clip(k / 0.004, 0, 1) * np.clip((n / SR - k) / 0.03, 0, 1) * (np.exp(-k / 0.09) if how == 'chug' else 1.0)
        place(x, pan(v, 0.0), at(bar, beat), 1.0)
x = lowpass(x, 1000)
save_loop('sky_doom_bass' + SUFFIX, x, 0.13)

# --- the drums ------------------------------------------------------------------------------------------
x = np.zeros((N + t2n(3.0), 2))
BIG = snare(1.3, 1.0, 0.8)
TIGHT = snare(1.2, 0.35, 0.4)
RIDE = highpass(st_noise(t2n(0.6)), 4000) * np.exp(-np.arange(t2n(0.6)) / SR / 0.25)[:, None]
for bar in range(BARS):
    if bar < 4:                                           # half-time doom
        if bar == 3:
            place(x, KICK_CLICK, at(bar), 1.0)
            place(x, BIG, at(bar, 1), 0.7)
            for j in range(3):                            # the band hits the triplet shouts
                place(x, KICK_CLICK, at(bar, 2 + j * TRIP), 1.0)
                place(x, CRASH, at(bar, 2 + j * TRIP), 0.45)
                place(x, TIGHT, at(bar, 2 + j * TRIP), 0.6)
            continue
        place(x, KICK_CLICK, at(bar), 1.0)
        place(x, KICK_CLICK, at(bar, 1.5), 0.75)
        place(x, BIG, at(bar, 2), 1.0)
        for b in range(4):
            place(x, RIDE, at(bar, b), 0.22)
        if bar % 2 == 0:
            place(x, CRASH, at(bar), 0.6)
        if bar == 1:
            place(x, tom(38), at(bar, 3), 0.7)
            place(x, tom(36), at(bar, 3.5), 0.8)
        continue
    if bar in STOP_BARS:                                  # stop-time: only the hits, a quiet hi-hat in the gaps
        nxt = list(ACC[bar][1:]) + [4.0 + (ACC[bar + 1][0] if bar + 1 in STOP_BARS else 0.0)]
        for b, b2 in zip(ACC[bar], nxt):
            place(x, KICK_CLICK, at(bar, b), 1.0)
            place(x, CRASH, at(bar, b), 0.75)
            place(x, CRASH, at(bar, b + 0.02), 0.35, semitones=-3.0)   # a second, darker crash: the hit rings on
            place(x, TIGHT, at(bar, b), 0.9)
            gap = t2n((b2 - b) * BAR / 4)                 # take 10: a reversed cymbal swells into the next hit
            rev = CRASH[: gap][::-1] * np.linspace(0, 1, min(gap, len(CRASH)))[:, None] ** 2
            place(x, rev, at(bar, b2) - len(rev), 0.45)
        for e in range(8):
            if e * 0.5 not in ACC[bar]:
                place(x, hat(), at(bar, e * 0.5), 0.18)
        continue
    last = bar == 7                                       # the climax: kick on every 8th, snare on 2 and 4
    if last:                                              # take 10: straight 8ths into the Ode, kick and snare, building
        place(x, CRASH, at(bar), 0.6)
        for e in range(8):
            g = 0.75 + 0.3 * e / 7
            place(x, KICK_CLICK, at(bar, e * 0.5), g)
            place(x, TIGHT, at(bar, e * 0.5), g * 0.9)
            place(x, hat(), at(bar, e * 0.5), 0.2)
        continue
    for e in range(8 if not last else 4):
        place(x, KICK_CLICK, at(bar, e * 0.5), 1.0 if e * 0.5 in ACC[bar] else 0.8)
        place(x, RIDE, at(bar, e * 0.5), 0.3 if e % 2 == 0 else 0.2)
    for b in (1, 3) if not last else (1,):
        place(x, TIGHT, at(bar, b), 1.0)
    for b in ACC[bar]:                                    # the accents get a crash
        if not (last and b >= 2):
            place(x, CRASH, at(bar, b), 0.35)
    if bar == 4:
        place(x, CRASH, at(bar), 0.7)
save_loop('sky_doom_drums' + SUFFIX, x, 0.10)


# --- the cats ------------------------------------------------------------------------------------------
def cat_scream(midi, seconds):
    """A metal scream: the rock shout, plus the same meow played slower (formants down: the chest of it),
    a rasp of noise that follows the voice, and a lot of distortion."""
    shout = cat_shout(midi, seconds)
    src = cc.shout(midi, seconds, key='scream')
    chest = resample(src, 2 ** (-7 / 12))[: len(src)]
    n = max(len(shout), len(chest))
    x = np.zeros((n, 2))
    x[: len(shout)] += shout
    x[: len(chest)] += cc.stereo(chest) * 0.8
    follow = lowpass(np.abs(x), 30)
    x += bandpass(st_noise(n), 1500, 6000) * follow * 0.8
    k = np.arange(n) / SR
    x *= (np.clip(k / 0.008, 0, 1) * np.clip((seconds - k) / 0.05, 0, 1))[:, None]
    x = np.tanh(x * 3.0 / (np.max(np.abs(x)) + 1e-9)) * 0.6
    return lowpass(highpass(x, 200), 7000)


# Take 5 (the user: right after the quarter-note triplets, a long held meow; cat #1 is the best low one):
# #1 (the British Shorthair 'will Futter', its own pitch about E4) sings a C4 held for almost a bar, its 'iii'
# stretched, a touch of pitch FX so the note reads, a little saturation and room.
LOW_CAT_ID = int(os.environ.get('SKY_LOW_CAT', 1))       # SKY_LOW_CAT=2 / 3 to try the other low cats
LOW_CAT = cc.cat_sample(LOW_CAT_ID)


# How soft the long meow is (the user: #1 is the one, but a little too sharp). SKY_LOW_SOFT 0 = take 5 as it was;
# 1 = highs off above 5 kHz, no saturation; 2 = off above 3.2 kHz, less pitch FX, 2 dB down; 3 = off above 2.2 kHz,
# no pitch FX, 3 dB down. (lowpass cutoff, pitch FX amount, saturation on, gain)
LOW_SOFT = int(os.environ.get('SKY_LOW_SOFT', 1))         # the user picked 1
_SOFT = {0: (None, 0.5, True, 1.0), 1: (5000, 0.5, False, 1.0), 2: (3200, 0.2, False, 0.8), 3: (2200, 0.0, False, 0.7)}[LOW_SOFT]


def warp(v, semis):
    """Bend a mono sound by a pitch curve (semitones per output sample; the sound gets a little shorter or longer)."""
    pos = np.cumsum(2 ** (semis / 12))
    pos = pos[pos < len(v) - 1]
    return np.interp(pos, np.arange(len(v)), v)


def long_low(midi, seconds, shape=''):
    """shape: '' held; 'fall' falls off at the end (down a minor third over the last third, like the guitar's bend);
    'scoop' comes up into the note from a semitone below, then a slow vibrato."""
    cut, fx, sat, gain = _SOFT
    v = cc.sing_miao(LOW_CAT, midi, seconds, keep=0.3)
    if fx:
        v = cc.resonate(v, midi, fx)
    k = np.arange(len(v) + t2n(0.5)) / SR
    if shape == 'fall':
        u = np.clip((k - seconds * 0.62) / (seconds * 0.38), 0, 1)
        v = warp(v, -3.0 * u * u)
    elif shape == 'scoop':
        v = warp(v, -1.0 * np.clip(1 - k / 0.22, 0, 1) ** 2 + 0.3 * np.sin(2 * np.pi * 5.5 * k) * np.clip((k - 0.35) / 0.4, 0, 1))
    v = v * 0.22 / (np.sqrt(np.mean(v ** 2)) + 1e-9)
    x = cc.stereo(v) * 1.6
    x = softclip(x, 1.3) if sat else x * 0.75
    if cut:
        x = lowpass(x, cut, order=4)
    return reverb(x * gain, 1.4, 0.45, mix=0.22)


def cats(name):
    """Take 3 (the user: too many messy meows; keep the quarter-note-triplet shouts, do 3-3-2 with that feel).
    Only the clean rock shout, few and in phrases: bar 4 and bar 8 three shouts on the quarter-note triplets of
    beats 3-4 (the same as the bar before the storm), bars 5 and 7 three long shouts in 3-3-2 (each held until
    the next: 3, 3 and 2 eighths), bar 6 left to the guitars."""
    x = np.zeros((N + t2n(3.0), 2))
    for j in range(3):                                    # bar 4: three triplet shouts, G
        place(x, cat_shout(67, BAR / 4 * TRIP * 0.95), at(3, 2 + j * TRIP), 0.9)
    # take 5: each set of triplets runs straight into a long low meow on the next downbeat (bar 1 answers the
    # triplets of the bar before the storm, and the ones of bar 8 when the loop comes round; bar 5 answers bar 4)
    for bar in (0, 4):
        place(x, long_low(60, BAR * 0.95), at(bar), 0.9)
        place(x, cat_shout(67, BAR / 4 * TRIP * 0.95, fixed=True), at(bar), 0.9)   # take 6: a shout on its front (G4, fixed cats)
    # take 7: the long meow once more on the second eight-count (storm bar 3), on its own. (Bar 7, the second
    # eight-count after the bar-5 one, has the 3-3-2 shouts, so it gets none.)
    # take 8 (the user: a little variation on the repeat): SKY_LOW_AGAIN = third (sings Eb4), fall, scoop; '' = the same
    again = os.environ.get('SKY_LOW_AGAIN', 'scoop')       # the user picked the scoop
    place(x, long_low(63 if again == 'third' else 60, BAR * 0.95, again if again in ('fall', 'scoop') else ''), at(2), 0.9)
    if STOP_BARS:                                         # take 9: short shouts with the band's hits
        for bar, m in zip(STOP_BARS, (60, 62)):            # take 10: under them, the soft long meow (C4 on Ab, D4 on G)
            place(x, long_low(m, BAR * 0.95, 'scoop'), at(bar), 0.55)
        for bar, shouts in SHOUTS.items():
            for i, (b, length, m) in enumerate(shouts):
                held = bar == max(SHOUTS) and i == len(shouts) - 1
                if bar in STOP_BARS:                      # take 12: the stop's shouts are held through their gap
                    sec = length * BAR / 4 * 0.85
                else:
                    sec = BAR / 4 * (0.9 if held else TRIP * 0.95)
                place(x, cat_shout(m, sec), at(bar, b), 0.95)
    else:
        for bar, shouts in SHOUTS.items():                 # the long shouts on the climax's accents
            for b, length, m in shouts:
                place(x, cat_shout(m, length * BAR / 4 * 0.92), at(bar, b), 0.9)
    for j, m in enumerate((67, 68, 71)):                  # bar 8: the triplets again, climbing G Ab B into the C of the light
        place(x, cat_shout(m, BAR / 4 * TRIP * 0.95), at(7, 2 + j * TRIP), 0.9 + 0.05 * j)
    save_loop(name, x, 0.075)


cats('sky_doom_shouts' + SUFFIX + ''.join('_' + k.lower() + os.environ[k] for k in ('SKY_LOW_CAT', 'SKY_LOW_SOFT', 'SKY_LOW_AGAIN') if k in os.environ))
print('sky metal done ->', OUT)
