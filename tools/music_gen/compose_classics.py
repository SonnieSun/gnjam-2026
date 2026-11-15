"""Public-domain classics as dynamic cat / future-bass tracks.

Only the tune is borrowed. Each song is written down here as its lead (16th steps in 4/4 at
160 BPM) and its chords (one per half bar); the builder turns that into the same set of
swappable layers as scene 1, so a song plays like any other scene:

  fb_L0_keys   future-bass supersaw chords pumping on every beat        (bed)
  L1_groove    the shared four-on-the-floor groove (keyless, reused)     (groove)
  L2_bass      octave saw bass on the chord roots                        (bass)
  L3_pluck     the tune on the kawaii pluck   |  L3_square  on the square lead
  L3_cat       the tune sung by cats (whole meows, pitch-shifted keeping their voice)
  fb_L4_peak   gated chord chops + white-noise sweeps                    (peak)
  C_drums      meow drums tuned to the song's key   C_stabs  cats singing the off-beat chords
  C_bass       real bass on the beat, a cat on the off-beat octave

and a 20-bar preview that starts future bass and gets more and more cat:
  1-4 bed + groove | 5-8 + bass + meow drums | 9-12 + pluck tune | 13-16 tune -> cats ('mix'), + peak,
  bed -> cat stabs | 17-19 bass -> cat bass, the cats change ('pool') | 20 transition

usage: python -I compose_classics.py <loops dir> [song ...]   (needs loops/meow_kit and loops/s1_disc)
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import (BAR, SR, adsr, bandpass, highpass, lowpass, mtof, nm, noise, osc_fm, osc_pulse,  # noqa: E402
                   osc_saw, osc_sine, osc_supersaw, pan, place, read_wav, resample, reverb, softclip, svf_lowpass,
                   t2n, write_wav)
from psola import midi_contour, sing, sing_miao  # noqa: E402
from slicer import slices  # noqa: E402

loops = sys.argv[1]
DISC = os.path.join(loops, 's1_disc')
OUT = os.path.join(loops, 'classics')
os.makedirs(OUT, exist_ok=True)
STEP = BAR / 16
BEAT = BAR / 4
BAR_N = t2n(BAR)
TAIL = t2n(2.0)

GROOVE = read_wav(os.path.join(DISC, 's1_disc_L1_groove_4b.wav'))
KICK = read_wav(os.path.join(DISC, 's1_disc_kick.wav'))
CRASH = read_wav(os.path.join(DISC, 's1_disc_crash.wav'))
RISER = read_wav(os.path.join(DISC, 's1_disc_riser_1b.wav'))


def load_kit(folder):
    out = []
    for line in open(os.path.join(folder, 'kit.txt'), encoding='utf-8'):
        if line.startswith('meow_'):
            name, midi, src = line.rstrip('\n').split('\t')
            out.append(dict(audio=read_wav(os.path.join(folder, name)), midi=float(midi.split()[1]), src=src))
    return out


KIT = load_kit(os.path.join(loops, 'meow_kit'))
SINGERS = [k for k in KIT if 'ID 0390' not in k['src'] and k['midi'] < 80]     # grown cats
KITTENS = [k for k in KIT if 'ID 0390' in k['src']]
_turn = [0]


def nearest(pool, target, choices=2):
    """One of the `choices` meows whose own note is closest to target (taking turns between them),
    so a meow is never pushed far from its own pitch."""
    ranked = sorted(pool, key=lambda k: abs(k['midi'] - target))[:choices]
    _turn[0] += 1
    return ranked[_turn[0] % len(ranked)]


def stereo(v, side=0.0):
    return pan(v, side)


# --- the cats: who sings what is read from loops/meow_roster.json (saved on the 喵选秀 page) -------
#   long    take turns on long notes (a quarter note or longer)
#   accent  the low long notes (at or below E5, so they are never pushed up into a squeal) and the
#           'MIAO' that ends each phrase
#   short   take turns on short notes, the meow drums, the cat chords and the 'mi-mi-mi' stutter
# Within a role, each note goes only to the cats whose own pitch is near it (see turn()).
# Numbers are the 喵选秀 candidates (the miao_score.py ranking); #1-3 are CC BY 4.0, the rest CC0.
SAMPLES = os.path.join(os.path.dirname(loops), 'samples')
_B = os.path.join(SAMPLES, 'bigsoundbank_cats')
_M = os.path.join(SAMPLES, 'commons_animals', 'Weibliche Britisch Kurzhaar will Futter C1277 MIAUEN.wav')
CANDIDATES = {
    1: (_M, 11.45, 0.6), 2: (_M, 7.59, 0.6), 3: (_M, 5.14, 0.6),
    4: (os.path.join(_B, 'ANMLCat_Meow cat 4 (ID 1892)_BigSoundBank.com.wav'), 0.05, 0.6),
    5: (os.path.join(_B, 'ANMLCat_Meow cat 5 (ID 1893)_BigSoundBank.com.wav'), 0.41, 0.6),
    6: (os.path.join(_B, 'ANMLCat_Meow cat 13 (ID 1901)_BigSoundBank.com.wav'), 4.03, 0.6),
    7: (os.path.join(_B, 'ANMLCat_Meow cat 12 (ID 1900)_BigSoundBank.com.wav'), 0.02, 0.6),
    8: (os.path.join(_B, 'ANMLCat_Meow cat 2 (ID 1890)_BigSoundBank.com.wav'), 0.08, 0.6),
    9: (os.path.join(_B, 'ANMLCat_Meow cat 3 (ID 1891)_BigSoundBank.com.wav'), 0.05, 0.6),
    10: (os.path.join(_B, 'ANMLCat_Small mewing of a cat (ID 0098)_BigSoundBank.com.wav'), 1.09, 0.3),
    11: (os.path.join(_B, 'ANMLCat_Mewing kitten 3 weeks (ID 0390)_BigSoundBank.com.wav'), 2.46, 0.3),
    12: (os.path.join(_B, 'ANMLCat_Little meow of a cat 8 (ID 1478)_BigSoundBank.com.wav'), 0.08, 0.3),
    # recorded by the team, used as recorded (humanmeow.py exists if a cleanup is ever wanted)
    13: (os.path.join(SAMPLES, 'my_meows', 'user_meows.wav'), 0.05, 0.2),
    14: (os.path.join(SAMPLES, 'my_meows', 'user_meows.wav'), 1.78, 0.2),
    15: (os.path.join(SAMPLES, 'my_meows', 'user_meows_2.wav'), 0.80, 0.2),
}
_roster_path = os.path.join(loops, 'meow_roster.json')
ROSTER = json.load(open(_roster_path, encoding='utf-8')) if os.path.exists(_roster_path) else {'long': [1, 3, 4, 5], 'accent': [6], 'short': [10]}


def trim_tail(sl, floor_db=-26):
    """Drop the quiet tail after a meow (breath, room noise): keep up to the last 10 ms that is within
    `floor_db` of the loudest, plus 30 ms, faded out. Also trims a quiet start."""
    m = np.abs(sl).mean(axis=1) if sl.ndim == 2 else np.abs(sl)
    w = int(0.01 * SR)
    env = np.sqrt(np.convolve(m ** 2, np.ones(w) / w, mode='same'))
    keep = np.nonzero(env > env.max() * 10 ** (floor_db / 20))[0]
    end = min(len(sl), keep[-1] + int(0.03 * SR)) if len(keep) else len(sl)
    # and a quiet start (a hummed 'm', a murmur, a breath) would land the meow late on its beat:
    # start 5 ms before it reaches -12 dB of its peak (#8 murmurs for 0.8 s before its meow)
    loud = np.nonzero(env > env.max() * 10 ** (-12 / 20))[0]
    start = max(0, loud[0] - int(0.005 * SR)) if len(loud) else 0
    out = sl[start:end].copy()
    g = min(int(0.005 * SR), len(out) // 4)
    out[:g] *= (np.linspace(0, 1, g)[:, None] if out.ndim == 2 else np.linspace(0, 1, g))
    f = min(int(0.02 * SR), len(out) // 4)
    out[-f:] *= (np.linspace(1, 0, f)[:, None] if out.ndim == 2 else np.linspace(1, 0, f))
    return out


def _slice_at(path, start, min_len=0.3):
    x = read_wav(path)
    return trim_tail(min(slices(x, min_len=min_len, max_len=2.0, gate_db=-30), key=lambda s: abs(s['start'] / SR - start))['audio'])


_cache = {}


def cat_sample(i):
    if i not in _cache:
        x = _slice_at(*CANDIDATES[i])
        _cache[i] = highpass(x, 100) / np.max(np.abs(x))
    return _cache[i]


LONG = [cat_sample(i) for i in ROSTER['long']]
ACCENT = [cat_sample(i) for i in ROSTER['accent']] or LONG
SHORT = [cat_sample(i) for i in ROSTER['short']]
_kdir = os.path.join(loops, 'meow_kit_kichiku')
os.makedirs(_kdir, exist_ok=True)
for _f in os.listdir(_kdir):
    if _f.startswith('miao_') and _f != 'miao_audition.wav':
        os.remove(os.path.join(_kdir, _f))
for _role in ('long', 'accent', 'short'):
    for _i in ROSTER[_role]:
        write_wav(os.path.join(_kdir, f'miao_{_role}_{_i:02d}.wav'), cat_sample(_i), peak=0.9)
FX = 0.35            # how much pitch FX the regular cat leads get (the kichiku lead gets 1.0)
_turns = {}
# each cat's own pitch (the median of its meow), so a note goes to a cat that is already near it
_native = {}


def native(sample):
    if id(sample) not in _native:
        pc = midi_contour(sample.mean(axis=1) if sample.ndim == 2 else sample)
        _native[id(sample)] = float(np.median(pc)) if pc is not None else 72.0
    return _native[id(sample)]


# A meow pitched far down stops sounding like a cat (a high kitten sung 20 semitones lower is a
# growl), so a cat only sings notes from DOWN semitones below its own pitch to UP above it.
DOWN, UP = 5, 7


def lift(midi):
    """A note lower than every cat can sing goes up an octave (the tune stays, the meow stays a meow)."""
    lowest = min(native(x) for x in LONG + ACCENT + SHORT) - DOWN
    while midi < lowest:
        midi += 12
    return midi


def turn(pool, key, midi=None):
    """The next cat of a pool, taking turns; with a note, only among the cats near that note. None
    near: a cat from the other roles that is near (a short note borrows a long cat, sped up), else
    the one that needs the smallest shift, a shift down counting double."""
    if midi is not None:
        def near(cats):
            return [s for s in cats if -DOWN <= midi - native(s) <= UP]
        everyone = LONG + ACCENT + SHORT
        pool = near(pool) or near(everyone) or [min(everyone, key=lambda s: 2 * (native(s) - midi) if midi < native(s) else midi - native(s))]
    _turns[key] = _turns.get(key, -1) + 1
    return pool[_turns[key] % len(pool)]


def miao(midi, seconds, style='mix', flow=False):
    """One note of the kichiku cat. Short notes: the short cats take turns, sped up. Long notes:
      'mix'      the accent cats wherever the note is at or below E5; the long cats above that
      'pool'     the long cats taking turns
      'classic'  the first long cat alone
    All keep part of their own slide and hold the 'iii' on long notes.
    flow: the meow keeps at least 80% of its own length even on a short note, so it rings on past the
    next note (the caller fades that tail) instead of being squeezed and cut."""
    def fit(sample, sec):
        return max(sec, 0.8 * len(sample) / SR) if flow else sec
    midi = lift(midi)
    if seconds < 0.33:                 # an 8th or shorter; a quarter note already gets a whole 'Miiiiao'
        s = turn(SHORT, 'short', midi)
        return sing_miao(s, midi, fit(s, max(seconds * 0.95, 0.12)), keep=0.3)
    if style == 'mix' and midi <= nm('E5'):
        s = turn(ACCENT, 'accent', midi)
    elif style == 'classic':
        s = LONG[0]
    else:
        s = turn(LONG, 'long', midi)
    return sing_miao(s, midi, fit(s, seconds * 0.97), keep=0.4)


def tail_under(v, note_n):
    """After the next note starts, the meow drops to 60% for 0.35 s, then fades out over 0.15 s: it
    overlaps the next meow instead of being cut, without piling up into mush."""
    g = np.ones(len(v))
    if len(v) > note_n:
        k = np.arange(len(v) - note_n) / SR
        g[note_n:] = np.where(k < 0.35, 1 - 0.4 * np.clip(k / 0.01, 0, 1), np.clip(0.6 * (1 - (k - 0.35) / 0.15), 0, None))
    return v * g


def shout(midi, seconds, key='shout'):
    """The 'MIAO' that ends a phrase, at the written pitch (it used to drop an octave above C5, which
    made the top note of a tune its lowest), sung by an accent or long cat whose own pitch is near."""
    midi = lift(midi)
    return sing_miao(turn(ACCENT + LONG, key, midi), midi, max(seconds, 0.3), keep=0.4)


def resonate(v, midi, amount=1.0, even=False, g=0.93):
    """Pitch FX: a feedback comb tuned to the note, so every harmonic of the note rings and the pitch
    of a meow reads. `amount` 1 = clearly electric, 0.35 = just a little. Short notes get a little more
    than long ones, low notes a little less. even: first bring the meow to a standard loudness."""
    if even:
        v = v * 0.1 / (np.sqrt(np.mean(v ** 2)) + 1e-9)
    wet = amount * float(np.interp(len(v) / SR, [0.12, 1.0], [0.6, 0.48])) * (0.85 if midi < 69 else 1.0)
    n = len(v) + t2n(0.25)
    w = 2 * np.pi * np.fft.rfftfreq(n)
    y = np.fft.irfft(np.fft.rfft(v, n) / (1 - g * np.exp(-1j * w * SR / mtof(midi))), n)
    y = highpass(np.stack([y, y], 1), 450)[:, 0]
    y *= np.sqrt(np.mean(v ** 2)) / (np.sqrt(np.mean(y[: len(v)] ** 2)) + 1e-9)
    out = np.zeros(n)
    out[: len(v)] = v * (1 - wet * 0.5)
    out += y * wet
    f = t2n(0.1)
    out[-f:] *= np.linspace(1, 0, f)
    return out


def punch(x):
    """A little more bite for a cat lead: +3 dB or so of presence (2-5 kHz) and a touch of saturation."""
    return softclip((x + 0.4 * bandpass(x, 2000, 5000)) * 1.15, 1.15)


def hit(sample, own, midi, seconds):
    """Kichiku note: the sample from its start, played faster / slower to reach the pitch (so high notes
    are sharper and shorter), cut hard at the end of the note."""
    v = resample(sample, 2 ** ((own - midi) / 12))
    n = max(t2n(0.05), min(len(v), t2n(seconds)))
    v = v[:n].copy()
    f = min(t2n(0.008), n // 3)
    v[-f:] *= np.linspace(1, 0, f)
    return v


def mi(midi, seconds=0.05):
    """Just the 'mi' at the front of a short cat's meow: for stutters and off-beat ticks."""
    midi = lift(midi)
    v = sing_miao(turn(SHORT, 'mi', midi), midi, 0.3, keep=0.2)
    n = int(seconds * SR)
    v = v[:n].copy()
    v[-int(0.008 * SR):] *= np.linspace(1, 0, int(0.008 * SR))
    return v


# --- chords ---------------------------------------------------------------------------------
PC = {'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4, 'F': 5, 'F#': 6, 'Gb': 6, 'G': 7,
      'G#': 8, 'Ab': 8, 'A': 9, 'A#': 10, 'Bb': 10, 'B': 11}
QUAL = {'': [0, 4, 7], 'm': [0, 3, 7], '7': [0, 4, 7, 10], 'm7': [0, 3, 7, 10], 'maj7': [0, 4, 7, 11]}


def chord(sym):
    """'Am', 'E7', 'Fmaj7' -> (voicing midis between G3 and G4+, bass root midi in octave 1-2)."""
    root = sym[:2] if len(sym) > 1 and sym[1] in '#b' else sym[:1]
    q = sym[len(root):]
    r = PC[root]
    notes = sorted(55 + ((r + i - 55) % 12) for i in QUAL[q])        # each tone in G3..F#4
    return notes, 24 + (r - 24) % 12 + (12 if r < 4 else 0)


# --- instruments ----------------------------------------------------------------------------
def saw_stack(freq, n, voices=7, detune=0.35):
    return highpass(osc_supersaw(freq, n, voices=voices, detune=detune), max(60.0, float(np.min(freq)) * 0.7))


def filtered(x, start, end, tau, q=1.0):
    t = np.arange(len(x)) / SR
    return svf_lowpass(x, end + (start - end) * np.exp(-t / tau), q=q)


def attack(n, ms=1.5):
    return np.clip(np.arange(n) / (ms / 1000 * SR), 0, 1)


def pluck(midi, seconds):
    n = t2n(seconds + 0.15)
    t = np.arange(n) / SR
    v = filtered(saw_stack(mtof(midi), n, voices=3, detune=0.15), 9000, 900, 0.06, q=1.1)
    bell = pan(osc_fm(mtof(midi + 12), n, ratio=2.0, index=1.5, index_decay=10) * np.exp(-t / 0.2) * 0.25, 0.0)
    return (v + bell) * (np.exp(-t / 0.18) * attack(n, 1))[:, None] * 0.5


def square(midi, seconds):
    gate = seconds * (0.8 if seconds < 0.2 else 0.92)
    n = t2n(gate + 0.03)
    v = lowpass(osc_pulse(mtof(midi), n, 0.5)[:, None], 6000, order=1)[:, 0] * adsr(n, 0.001, 0.015, 0.77, 0.02, gate=gate)
    return pan(v * 0.45, 0.0)


def cat(midi, seconds):
    return stereo(sing(nearest(SINGERS, midi), midi, max(seconds * 0.95, 0.12)))


def bass_note(freq, n):
    t = np.arange(n) / SR
    tone = osc_supersaw(freq, n, voices=3, detune=0.08).mean(axis=1) * 0.7 + osc_pulse(freq, n, 0.5) * 0.3
    tone = svf_lowpass(tone, 450 + 3200 * np.exp(-t / 0.045), q=1.3)
    sub = osc_sine(freq, n) * 0.8 if freq < 120 else osc_sine(freq / 2, n) * 0.45
    return (tone + sub) * adsr(n, a=0.002, d=0.08, s=0.55, r=0.02, gate=n / SR - 0.02)


def pump(n):
    g = np.ones(n)
    t = np.arange(t2n(BEAT)) / SR
    shape = 1 - np.exp(-t / 0.06)
    for b in range(0, n, t2n(BEAT)):
        j = min(n, b + len(shape))
        g[b:j] = shape[: j - b]
    k = t2n(0.004)
    return np.convolve(np.concatenate([np.zeros(k), g]), np.ones(k) / k, mode='valid')[:n]


# --- the builder ----------------------------------------------------------------------------
def blank(bars):
    return np.zeros((t2n(bars * BAR) + TAIL, 2))


def finish(x, bars):
    n = t2n(bars * BAR)
    y = x[:n].copy()
    y[:TAIL] += x[n:n + TAIL]
    return y


def match_rms(x, target):
    return x * (target / (np.sqrt(np.mean(x ** 2)) + 1e-9))


def halves(song):
    """[(start step, chord notes, root)] one per half bar."""
    return [(i * 8, *chord(c)) for i, c in enumerate(song['chords'])]


def cat_leads(song, bars, last_in_phrase):
    """The cat versions of a tune: {'L3_cat', 'L3_cat_flow', 'L3_cat_pool', 'L3_cat_classic',
    'L3_cat_kichiku'}. song needs 'melody' [(16th step, note name, length in 16ths)] and 'cat_octave'."""
    L = {}
    # three cat leads, so the game can vary the cats between rounds (same notes, other cats). Each has
    # a little pitch FX and bite so the tune reads; the phrase-ending MIAO is the loudest note, with a
    # second meow an octave below under it.
    mel = song['melody']
    for name, style, flow in (('L3_cat', 'mix', False), ('L3_cat_flow', 'mix', True),
                              ('L3_cat_pool', 'pool', False), ('L3_cat_classic', 'classic', False)):
        x = blank(bars)
        for i, (s, p, ln) in enumerate(song['melody']):
            m = nm(p) + song['cat_octave']
            if i in last_in_phrase and ln >= 2:              # mi-mi-mi-MIAO, #6 shouting the end
                for k in range(3):
                    place(x, stereo(resonate(mi(m), lift(m), FX)), t2n(s * STEP + k * STEP / 2), 0.9)
                sec, at = max(0.12, ln * STEP - 1.5 * STEP), t2n(s * STEP + 1.5 * STEP)
                place(x, stereo(resonate(shout(m, sec), lift(m), FX)), at, 1.25)
                place(x, stereo(resonate(shout(m - 12, sec, 'shout_lo'), lift(m - 12), FX)), at, 0.55)
            elif flow:
                nxt = mel[i + 1][0] if i + 1 < len(mel) else mel[0][0] + bars * 16
                v = miao(m, ln * STEP, style, flow=True)
                place(x, stereo(resonate(tail_under(v, t2n((nxt - s) * STEP)), lift(m), FX)), t2n(s * STEP))
            else:
                place(x, stereo(resonate(miao(m, ln * STEP, style), lift(m), FX)), t2n(s * STEP))
        L[name] = match_rms(finish(reverb(punch(highpass(x, 120)), 0.6, 0.2, mix=0.06)[: len(x)], bars), 0.135)
    # the kichiku cat lead: one cat sings a whole 4-bar phrase (the one whose own pitch is nearest the
    # phrase, never the same cat two phrases running), every note restarts its meow from the start,
    # pitched by playing it faster / slower, and is cut hard at the end of the note. Full pitch FX.
    everyone = [(c.mean(axis=1) if c.ndim == 2 else c, native(c)) for c in LONG + ACCENT + SHORT]
    x = blank(bars)
    prev = None
    for ph in range(0, bars, 4):
        idx = [i for i, (s, _, _) in enumerate(mel) if ph <= s // 16 < ph + 4]
        if not idx:
            continue
        mid = float(np.median([nm(mel[i][1]) + song['cat_octave'] for i in idx]))
        prev = next(c for c in sorted(range(len(everyone)), key=lambda c: abs(everyone[c][1] - mid)) if c != prev)
        sample, own = everyone[prev]
        for i in idx:
            s, p, ln = mel[i]
            m = nm(p) + song['cat_octave']
            end = i in last_in_phrase and ln >= 2
            place(x, stereo(resonate(hit(sample, own, m, ln * STEP * 0.95), m, even=True)), t2n(s * STEP), 1.3 if end else 1.0)
            if end:
                place(x, stereo(resonate(hit(sample, own, m - 12, ln * STEP * 0.95), m - 12, even=True)), t2n(s * STEP), 0.6)
    L['L3_cat_kichiku'] = match_rms(finish(reverb(punch(highpass(x, 120)), 0.6, 0.2, mix=0.06)[: len(x)], bars), 0.135)
    return L


def build(song):
    bars = len(song['chords']) // 2
    H = halves(song)
    L = {}
    # bed: pumping supersaw chords
    x = blank(bars)
    for s, notes, _ in H:
        n = t2n(2 * BEAT)
        c = lowpass(sum(saw_stack(mtof(m + 12), n, voices=7, detune=0.4) for m in notes) / len(notes), 5000)
        c[-t2n(0.01):] *= np.linspace(1, 0, t2n(0.01))[:, None]
        place(x, c * 0.6, t2n(s * STEP))
    x = x * pump(len(x))[:, None]
    L['fb_L0_keys'] = match_rms(finish(reverb(highpass(x, 180), 1.0, 0.3, mix=0.12)[: len(x)], bars), 0.079)
    # bass: octave 8ths
    x = blank(bars)
    for s, _, root in H:
        f = mtof(root + 12)
        for e in range(4):
            place(x, pan(bass_note(f * (2 if e % 2 else 1), t2n(STEP * 1.6)), 0.0), t2n((s + e * 2) * STEP))
    L['L2_bass'] = match_rms(finish(softclip(x * 1.8, 2.2), bars), 0.386)
    # leads
    last_in_phrase = {max(i for i, (s, _, _) in enumerate(song['melody']) if s // 16 == b)
                      for b in range(3, bars, 4) if any(s // 16 == b for s, _, _ in song['melody'])}
    for name, voice in (('L3_pluck', pluck), ('L3_square', square)):
        x = blank(bars)
        for s, p, ln in song['melody']:
            place(x, voice(nm(p), ln * STEP), t2n(s * STEP))
        L[name] = match_rms(finish(reverb(highpass(x, 200), 0.6, 0.2, mix=0.06)[: len(x)], bars), 0.123)
    L.update(cat_leads(song, bars, last_in_phrase))
    # peak: gated chord chops and sweeps
    x = blank(bars)
    for s, notes, _ in H:
        for o, ln in ((0, 2), (3, 2), (6, 2)):
            n = t2n(ln * STEP * 0.85 + 0.02)
            c = filtered(sum(saw_stack(mtof(m + 24), n, voices=5, detune=0.3) for m in notes[1:]) / max(1, len(notes) - 1), 8000, 3000, 0.05)
            place(x, c * adsr(n, 0.002, 0.04, 0.7, 0.015, gate=n / SR - 0.015)[:, None] * 0.4, t2n((s + o) * STEP))
    for b in range(1, bars, 2):
        n = t2n(BAR)
        k = np.arange(n) / n
        sw = pan(svf_lowpass(noise(n), 500 + 9000 * k ** 2, q=1.2) * k * 0.25, 0.0)
        sw[-t2n(0.008):] *= np.linspace(1, 0, t2n(0.008))[:, None]
        place(x, sw, t2n(b * BAR))
    L['fb_L4_peak'] = match_rms(finish(reverb(highpass(x, 150), 0.9, 0.3, mix=0.1)[: len(x)], bars), 0.060)
    # cat drums: "meow" on every beat, low on 1 and 3, high on 2 and 4, a short "mi" on the off-beats
    lo, hi = song['drum_notes']
    x = blank(bars)
    for b in range(bars):
        for beat in range(4):
            target = lo if beat % 2 == 0 else hi
            place(x, stereo(sing_miao(turn(SHORT, 'drum', target), target, 0.26, keep=0.3)), t2n(b * BAR + beat * BEAT))
            # the off-beat "mi" a fourth above the high drum (it was an octave up: a shrill kitten)
            place(x, stereo(lowpass(mi(hi + 5, 0.045), 5000), 0.3 if beat % 2 else -0.3), t2n(b * BAR + beat * BEAT + 2 * STEP), 0.35)
    L['C_drums'] = match_rms(finish(highpass(x, 120), bars), 0.10)
    # cat stabs: three cats on the off-beat 8ths, the chord of that half bar
    x = blank(bars)
    for s, notes, _ in H:
        top3 = [m + 12 for m in notes[-3:]]
        for o in (2, 6):
            for m, side in zip(top3, (-0.5, 0.0, 0.5)):
                place(x, stereo(sing_miao(turn(SHORT, 'stab'), m, 0.12, keep=0.2), side), t2n((s + o) * STEP), 0.6)
    L['C_stabs'] = match_rms(finish(reverb(highpass(x, 140), 0.5, 0.15, mix=0.06)[: len(x)], bars), 0.079)
    # cat bass: real bass on the beat, a cat on the off-beat octave (near its own pitch)
    x = blank(bars)
    for s, _, root in H:
        f = mtof(root + 12)
        for e in range(4):
            at = t2n((s + e * 2) * STEP)
            n = t2n(STEP * 1.6)
            if e % 2 == 0:
                place(x, pan(bass_note(f, n), 0.0), at)
            else:
                m = root + 36
                place(x, stereo(sing_miao(turn(SHORT, 'bass'), m, 0.18, keep=0.3)), at, 0.9)
                place(x, pan(osc_sine(f, n) * adsr(n, 0.003, 0.05, 0.7, 0.03) * 0.6, 0.0), at)
    L['C_bass'] = match_rms(finish(softclip(x * 1.2, 1.2), bars), 0.386)
    L['L1_groove'] = GROOVE
    return L


def render(path, layers, bars=20):
    music = np.zeros((t2n(bars * BAR + 1.5), 2))
    for loop, a, b, g in layers:
        nb = len(loop) // BAR_N
        for bar in range(a, b + 1):
            off = ((bar - a) % nb) * BAR_N
            seg = loop[off: off + BAR_N].copy()
            if bar == a:
                f = t2n(0.01)
                seg[:f] *= np.linspace(0, 1, f)[:, None]
            music[(bar - 1) * BAR_N: bar * BAR_N] += seg * g
    place(music, RISER, (bars - 1) * BAR_N, 0.7)
    drums = np.zeros_like(music)
    kicks = [b * BAR_N + s * t2n(BEAT) for b in range(bars) for s in range(4)] + [bars * BAR_N]
    for k in kicks:
        place(drums, KICK, k, 0.95)
    place(drums, CRASH, bars * BAR_N, 0.7)
    gain = np.ones(len(music))
    t_rel = np.arange(t2n(0.3)) / SR
    dip = 1 - 0.45 * np.exp(-t_rel / 0.09) * np.clip(t_rel / 0.003, 0, 1)
    for k in kicks:
        j = min(len(gain), k + len(dip))
        gain[k:j] = np.minimum(gain[k:j], dip[: j - k])
    write_wav(path, softclip((music * gain[:, None] + drums) * 0.9, 1.4), peak=0.89)


def more_and_more_cat(L):
    """1-4 bed + groove | 5-8 + bass, meow drums, the tune on the pluck | 9-16 the cats take the tune
    ('mix', meows overlapping), bed -> cat stabs, + peak from 13 | 17-19 the same cats cut to the
    note, bass -> cat bass |
    20 transition. Every loop enters at its own bar 1."""
    return [(L['fb_L0_keys'], 1, 8, 0.6), (L['C_stabs'], 9, 20, 0.6),
            (L['L1_groove'], 1, 19, 0.85),
            (L['L2_bass'], 5, 16, 0.72), (L['C_bass'], 17, 19, 0.72),
            (L['C_drums'], 5, 19, 0.8),
            (L['L3_pluck'], 5, 8, 0.78), (L['L3_cat_flow'], 9, 16, 1.0), (L['L3_cat'], 17, 20, 1.1),
            (L['fb_L4_peak'], 13, 19, 0.62)]


# --- the songs (all public domain; the arrangements are our own) ------------------------------
def tune(rows):
    """rows: one list per bar of (step, note, length in 16ths) -> absolute steps."""
    return [(b * 16 + s, p, ln) for b, row in enumerate(rows) for s, p, ln in row]


SONGS = {
    # Beethoven, Bagatelle "Fur Elise" (1810). Its 3/8 bars become half bars of 4/4: the 16th run
    # keeps its notes, each arpeggio bar is stretched by holding its last note. A minor.
    'fur_elise': dict(
        chords=['Am', 'Am', 'E', 'Am', 'F', 'Am', 'E', 'Am'],
        melody=tune([
            [(0, 'E6', 1), (1, 'D#6', 1), (2, 'E6', 1), (3, 'D#6', 1), (4, 'E6', 1), (5, 'B5', 1), (6, 'D6', 1), (7, 'C6', 1),
             (8, 'A5', 2), (11, 'C5', 1), (12, 'E5', 1), (13, 'A5', 3)],
            [(0, 'B5', 2), (3, 'E5', 1), (4, 'G#5', 1), (5, 'B5', 3),
             (8, 'C6', 2), (11, 'E5', 1), (12, 'E6', 1), (13, 'D#6', 1), (14, 'E6', 1), (15, 'D#6', 1)],
            [(0, 'E6', 1), (1, 'B5', 1), (2, 'D6', 1), (3, 'C6', 3),
             (8, 'A5', 2), (11, 'C5', 1), (12, 'E5', 1), (13, 'A5', 3)],
            [(0, 'B5', 2), (3, 'E5', 1), (4, 'C6', 1), (5, 'B5', 3),
             (8, 'A5', 8)],
        ]),
        cat_octave=-12, drum_notes=(nm('E4'), nm('A4'))),
    # Grieg, "In the Hall of the Mountain King" (1875), the march theme in 8ths. A minor.
    'mountain_king': dict(
        chords=['Am', 'Am', 'B7', 'Bb', 'Am', 'Am', 'C', 'G'],
        melody=tune([
            [(0, 'A4', 2), (2, 'B4', 2), (4, 'C5', 2), (6, 'D5', 2), (8, 'E5', 2), (10, 'C5', 2), (12, 'E5', 4)],
            [(0, 'D#5', 2), (2, 'B4', 2), (4, 'D#5', 4), (8, 'D5', 2), (10, 'Bb4', 2), (12, 'D5', 4)],
            [(0, 'A4', 2), (2, 'B4', 2), (4, 'C5', 2), (6, 'D5', 2), (8, 'E5', 2), (10, 'C5', 2), (12, 'E5', 2), (14, 'A5', 2)],
            [(0, 'G5', 2), (2, 'E5', 2), (4, 'C5', 2), (6, 'E5', 2), (8, 'G5', 8)],
        ]),
        cat_octave=0, drum_notes=(nm('E4'), nm('A4'))),
    # Beethoven, Symphony No. 9, "Ode to Joy" (1824), on royal-road chords. C major, quarters.
    'ode_to_joy': dict(
        chords=['C', 'C', 'G', 'G', 'Am', 'Am', 'Em', 'Em', 'F', 'F', 'C', 'C', 'Dm7', 'Dm7', 'G', 'C'],
        melody=tune([
            [(0, 'E5', 4), (4, 'E5', 4), (8, 'F5', 4), (12, 'G5', 4)],
            [(0, 'G5', 4), (4, 'F5', 4), (8, 'E5', 4), (12, 'D5', 4)],
            [(0, 'C5', 4), (4, 'C5', 4), (8, 'D5', 4), (12, 'E5', 4)],
            [(0, 'E5', 6), (6, 'D5', 2), (8, 'D5', 8)],
            [(0, 'E5', 4), (4, 'E5', 4), (8, 'F5', 4), (12, 'G5', 4)],
            [(0, 'G5', 4), (4, 'F5', 4), (8, 'E5', 4), (12, 'D5', 4)],
            [(0, 'C5', 4), (4, 'C5', 4), (8, 'D5', 4), (12, 'E5', 4)],
            [(0, 'D5', 6), (6, 'C5', 2), (8, 'C5', 8)],
        ]),
        cat_octave=0, drum_notes=(nm('E4'), nm('G4'))),
    # Offenbach, "Galop infernal" from Orphee aux enfers (1858): the can-can theme. G major, at
    # its own galop speed (16th = our 16th, quarter = 160). Notes checked against flutetunes.com's
    # MIDI of the galop.
    'can_can': dict(
        chords=['D7', 'G', 'C', 'D7', 'D7', 'G', 'D7', 'G'] * 2,
        melody=tune([
            [(0, 'A4', 2), (2, 'C5', 2), (4, 'B4', 2), (6, 'A4', 2), (8, 'D5', 4), (12, 'D5', 4)],
            [(0, 'D5', 2), (2, 'E5', 2), (4, 'B4', 2), (6, 'C5', 2), (8, 'A4', 4), (12, 'A4', 4)],
            [(0, 'A4', 2), (2, 'C5', 2), (4, 'B4', 2), (6, 'A4', 2), (8, 'G4', 2), (10, 'G5', 2), (12, 'F#5', 2), (14, 'E5', 2)],
            [(0, 'D5', 2), (2, 'C5', 2), (4, 'B4', 2), (6, 'A4', 2), (8, 'G4', 8)],
            [(0, 'A4', 2), (2, 'C5', 2), (4, 'B4', 2), (6, 'A4', 2), (8, 'D5', 4), (12, 'D5', 4)],
            [(0, 'D5', 2), (2, 'E5', 2), (4, 'B4', 2), (6, 'C5', 2), (8, 'A4', 4), (12, 'A4', 4)],
            [(0, 'A4', 2), (2, 'C5', 2), (4, 'B4', 2), (6, 'A4', 2), (8, 'G4', 2), (10, 'D5', 2), (12, 'A4', 2), (14, 'B4', 2)],
            [(0, 'G4', 4), (4, 'D4', 4), (8, 'G4', 8)],
        ]),
        cat_octave=0, drum_notes=(nm('D4'), nm('G4'))),
    # Mozart, Sonata K. 331, "Rondo alla turca" (1783), the A-minor theme, notes from the Mutopia
    # Project edition (public domain). Mozart's 16th = our 16th, so each 2/4 bar is half of ours.
    'turkish_march': dict(
        chords=['Am', 'Am', 'E', 'Am', 'Em', 'Em', 'B7', 'Em', 'Am', 'Am', 'E', 'Am', 'E', 'Dm', 'E7', 'Am'],
        melody=tune([
            [(0, 'C5', 2), (4, 'D5', 1), (5, 'C5', 1), (6, 'B4', 1), (7, 'C5', 1),
             (8, 'E5', 2), (12, 'F5', 1), (13, 'E5', 1), (14, 'D#5', 1), (15, 'E5', 1)],
            [(0, 'B5', 1), (1, 'A5', 1), (2, 'G#5', 1), (3, 'A5', 1), (4, 'B5', 1), (5, 'A5', 1), (6, 'G#5', 1), (7, 'A5', 1),
             (8, 'C6', 4), (12, 'A5', 2), (14, 'C6', 2)],
            [(0, 'B5', 2), (2, 'A5', 2), (4, 'G5', 2), (6, 'A5', 2), (8, 'B5', 2), (10, 'A5', 2), (12, 'G5', 2), (14, 'A5', 2)],
            [(0, 'B5', 2), (2, 'A5', 2), (4, 'G5', 2), (6, 'F#5', 2), (8, 'E5', 4),
             (12, 'B4', 1), (13, 'A4', 1), (14, 'G#4', 1), (15, 'A4', 1)],
            [(0, 'C5', 2), (4, 'D5', 1), (5, 'C5', 1), (6, 'B4', 1), (7, 'C5', 1),
             (8, 'E5', 2), (12, 'F5', 1), (13, 'E5', 1), (14, 'D#5', 1), (15, 'E5', 1)],
            [(0, 'B5', 1), (1, 'A5', 1), (2, 'G#5', 1), (3, 'A5', 1), (4, 'B5', 1), (5, 'A5', 1), (6, 'G#5', 1), (7, 'A5', 1),
             (8, 'C6', 4), (12, 'A5', 2), (14, 'B5', 2)],
            [(0, 'C6', 2), (2, 'B5', 2), (4, 'A5', 2), (6, 'G#5', 2), (8, 'A5', 2), (10, 'E5', 2), (12, 'F5', 2), (14, 'D5', 2)],
            [(0, 'C5', 4), (4, 'B4', 2), (6, 'A4', 1), (7, 'B4', 1), (8, 'A4', 4),
             (12, 'B4', 1), (13, 'A4', 1), (14, 'G#4', 1), (15, 'A4', 1)],
        ]),
        cat_octave=0, drum_notes=(nm('E4'), nm('A4'))),
}

# Toby Fox, "Your Best Friend" (Undertale, 2015). NOT public domain: for the team's internal playtest
# only. The tune comes from a piano MIDI (tools/music_gen/midi_to_pattern.py, right hand); the chords are
# read off its left hand. Ab major, the first 8 bars. The original is at 120 BPM.
SONGS['your_best_friend'] = dict(
    chords=['Ab', 'Ab', 'Eb', 'Eb', 'Ab', 'Ab', 'Db', 'Eb7', 'Ab', 'Ab', 'Bbm', 'Eb', 'Db', 'Eb', 'Ab', 'Ab'],
    melody=tune([
            [(0, 'C5', 2), (4, 'C5', 1), (6, 'C#5', 1), (8, 'D#5', 2), (12, 'C5', 2)],
            [(0, 'C#5', 2), (4, 'C#5', 1), (6, 'D#5', 1), (8, 'A#4', 2)],
            [(0, 'C5', 2), (4, 'C5', 1), (6, 'C#5', 1), (8, 'D#5', 2), (12, 'G#5', 2)],
            [(0, 'F5', 6), (8, 'D#5', 1), (12, 'D#6', 4)],
            [(0, 'C5', 2), (4, 'C5', 1), (6, 'C#5', 1), (8, 'D#5', 2), (12, 'C5', 2)],
            [(0, 'C#5', 2), (4, 'C#5', 1), (6, 'D#5', 1), (8, 'A#4', 2), (12, 'G4', 1)],
            [(0, 'C5', 2), (4, 'C5', 1), (6, 'C#5', 1), (8, 'A#4', 2), (12, 'G4', 2)],
            [(0, 'G#4', 6), (8, 'G#5', 1)],
    ]),
    cat_octave=0, drum_notes=(nm('D#4'), nm('G#4')))

# Speed per song, over the same 160 BPM beat. Half time (2) plays the tune at half speed (an 8th
# becomes a quarter, chords one per bar, loop twice as long): the Turkish March, all 16ths, needs it
# and sounded best that way. The rest stay at their own speed: the 'flow' lead lets each meow ring
# on into the next, so they are long enough without slowing the tune down.
HALF_TIME = 2
SPEED = {'turkish_march': HALF_TIME}
# Placeholder, not used yet: everything is rendered at 160 BPM. Songs listed here suit 120 better and
# get their own 120 render later (it also needs 120 BPM drums and bass; the game already takes the
# tempo from each level's music file, levels/music/level_N.json "bpm").
TEMPO = {'fur_elise': 120}


def slowed(song, k=HALF_TIME):
    return dict(song, melody=[(s * k, p, ln * k) for s, p, ln in song['melody']],
                chords=[c for c in song['chords'] for _ in range(k)])


only = sys.argv[2:]                          # song names to render; none = all
for name, song in SONGS.items():
    if only and name not in only:
        continue
    song = slowed(song, SPEED.get(name, 1))
    L = build(song)
    for k, x in L.items():
        if k != 'L1_groove':
            write_wav(os.path.join(OUT, f'{name}_{k}_{len(x) // BAR_N}b.wav'), x * (1.0 / max(1.0, np.max(np.abs(x)) / 0.98)), peak=None)
    render(os.path.join(OUT, f'{name}_preview_20b.wav'), more_and_more_cat(L))
    print(name, 'done')
