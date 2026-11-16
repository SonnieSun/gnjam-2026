"""Test renders for "the cats sing in harmony in the climax" (the end of the pizza): the famous Can-Can tune
in fever, as the game plays it now, and the same with more cats singing WITH the tune in parallel harmony
(not the off-beat backing vocals of the harm lane: every note of the tune, at the same time, a third or a
sixth away), and with a choir of held meows on the chords.

  1_now                      what the game has in fever
  2_third_below              + one other cat a third below every note
  3_third_and_sixth          + two cats, a third and a sixth below (three-part, spread left and right)
  4_choir_pad                + three cats holding the chord (long 'aaao', half a bar each)
  5_three_part_and_choir     3 + 4
  6_three_part_only_cats     3 without the square and pluck (cats only on the tune)
  7_four_steps_three_part    the four steps down in three-part harmony + choir
(1-7 were the first round: cluttered, not full. The second round, A-F, is what the script renders now.)
  A_big_choir                + a low, loud choir of held meows (4 voices, each sung twice), one bar per chord
  B_octave_below             + the tune an octave lower by the same cat (body)
  C_harmony_on_long_notes    + a third below on the long notes only, by the lead's own cat
  D_choir_and_long_note_harmony   A + C
  E_all_cats_forward_no_pluck     A + B + C, cats louder, the pluck out and the square down
  F_four_steps_choir_and_harmony  the four steps down with the choir and the harmony

usage: python -I make_cat_harmony_tests.py <loops dir> <game audio dir (assets/audio)> <out dir>
"""
import contextlib
import io
import os
import sys

import numpy as np

LOOPS, GAME, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
sys.argv = [sys.argv[0], LOOPS, '__none__']
sys.path.insert(0, os.path.dirname(__file__))
with contextlib.redirect_stdout(io.StringIO()):
    import compose_classics as cc
from audio import BAR, SR, highpass, nm, pan, place, read_wav, reverb, t2n, write_wav  # noqa: E402

os.makedirs(OUT, exist_ok=True)
STEP = BAR / 16
BARS = 8
N = t2n(BARS * BAR)
CATS = [(c.mean(axis=1) if c.ndim == 2 else c, cc.native(c)) for c in cc.LONG + cc.ACCENT + cc.SHORT]
SCALES = {'can_can': (7, 9, 11, 0, 2, 4, 6), 'can_can_b': (2, 4, 6, 7, 9, 11, 1)}


def down(midi, degrees, scale):
    """The note `degrees` scale steps below midi (a note outside the scale is first moved down onto it)."""
    pcs = sorted(scale)
    ladder = [o * 12 + p for o in range(11) for p in pcs]
    i = max(k for k, v in enumerate(ladder) if v <= midi)
    return ladder[i - degrees]


def part(song_key, degrees, skip):
    """The tune `degrees` scale steps lower, bent onto the chord where the tune itself is on the chord (so a
    third below never makes a second against the harmony on a strong note). One cat per four-bar phrase,
    kichiku style, never one of the cats in `skip`. Returns (mono-ish stereo buffer, cats used)."""
    song = cc.SONGS[song_key]
    mel, chords, scale = song['melody'], song['chords'], SCALES[song_key]
    x = np.zeros((N, 2))
    used = []
    for ph in range(0, BARS, 4):
        idx = [i for i, (s, _, _) in enumerate(mel) if ph <= s // 16 < ph + 4]
        notes = []
        for i in idx:
            s, p, ln = mel[i]
            m = nm(p) + song['cat_octave']
            tones, _ = cc.chord(chords[min(s // 8, len(chords) - 1)])
            pcs = {t % 12 for t in tones}
            h = down(m, degrees, scale)
            if m % 12 in pcs and h % 12 not in pcs:          # tune on the chord: the harmony goes to the chord too
                h = max(v for v in range(m - 10, m - 2) if v % 12 in pcs and abs(v - h) <= 2)
            notes.append((s, h, ln))
        mid = float(np.median([h for _, h, _ in notes]))
        cat = next(c for c in sorted(range(len(CATS)), key=lambda c: abs(CATS[c][1] - mid)) if c not in skip and c not in used[-1:])
        used.append(cat)
        sample, own = CATS[cat]
        for s, h, ln in notes:
            v = cc.resonate(cc.hit(sample, own, h, ln * STEP * 0.95), h, even=True)
            place(x, cc.stereo(v), t2n(s * STEP), 1.0)
    x = reverb(cc.punch(highpass(x, 120)), 0.6, 0.2, mix=0.08)[:N]
    return cc.match_rms(x, 0.135), used


def choir(song_key):
    """Three cats hold the chord, half a bar each, legato: 'aaao' behind the tune."""
    song = cc.SONGS[song_key]
    x = np.zeros((N + t2n(1.0), 2))
    for h, sym in enumerate(song['chords']):
        tones, _ = cc.chord(sym)
        voiced = sorted(60 + (t - 60) % 12 for t in tones[:3])          # close position from C4 up
        for k, m in enumerate(voiced):
            v = cc.resonate(cc.miao(m, 8 * STEP, 'mix', flow=8 * STEP), cc.lift(m), 0.6)
            n = min(len(v), t2n(8 * STEP * 1.05))
            v = v[:n].copy()
            f = min(t2n(0.05), n // 3)
            v[:f] *= np.linspace(0, 1, f)
            v[-f:] *= np.linspace(1, 0, f)
            place(x, pan(v, (-0.6, 0.0, 0.6)[k]), t2n(h * 8 * STEP), 1.0)
    x = reverb(highpass(x, 200), 1.4, 0.4, mix=0.3)[:N]
    return cc.match_rms(x, 0.135)


def stem(tune, part_name):
    return read_wav(os.path.join(GAME, 'music', 'classics', tune, f'{tune}_{part_name}_8b.wav'))[:N]


GROOVE = read_wav(os.path.join(GAME, 'music', 'scene1', 'skeleton', 's1_L1_groove_4b.wav'))


def mix(name, tune, layers):
    """layers: [(buffer or stem name, dB, pan or None)], played twice (16 bars)."""
    one = np.zeros((N, 2))
    for i in range(2):
        place(one, GROOVE, t2n(i * 4 * BAR), 1.0)
    for what, db, side in layers:
        v = stem(tune, what) if isinstance(what, str) else what
        if side is not None and side != 'keep':
            m = v.mean(axis=1)
            v = pan(m, side) * 1.4
        one[:len(v)] += v[:N] * 10 ** (db / 20)
    x = np.concatenate([one, one, np.zeros((t2n(0.5), 2))])
    f = t2n(0.4)
    x[-f:] *= np.linspace(1, 0, f)[:, None]
    write_wav(os.path.join(OUT, name + '.wav'), x, peak=0.9)
    print(' ', name)



# --- second round (the first one was cluttered and thin): fullness comes from long notes, low-mid body and a
# slow harmonic rhythm, not from more cats on every fast note. So: harmony only on the long / strong notes,
# sung by the SAME cat as the tune (it blends), an octave below for body, and a real choir: low, whole bars,
# every voice double-tracked, loud.
def lead_cats(song_key):
    """The cat the kichiku lead uses in each four-bar phrase (the same rule as compose_classics.cat_leads)."""
    song = cc.SONGS[song_key]
    mel, prev, out = song['melody'], None, {}
    for ph in range(0, BARS, 4):
        idx = [i for i, (st, _, _) in enumerate(mel) if ph <= st // 16 < ph + 4]
        mid = float(np.median([nm(mel[i][1]) + song['cat_octave'] for i in idx]))
        prev = next(c for c in sorted(range(len(CATS)), key=lambda c: abs(CATS[c][1] - mid)) if c != prev)
        out[ph] = prev
    return out


def strong_part(song_key, degrees=None, octave=0, only_long=True):
    """Harmony on the long notes (a quarter note or more) and the phrase endings only, by the lead's own cat.
    degrees: scale steps below (2 = a third); None with octave=-12 = the tune an octave lower."""
    song = cc.SONGS[song_key]
    mel, chords, scale = song['melody'], song['chords'], SCALES[song_key]
    cats = lead_cats(song_key)
    x = np.zeros((N, 2))
    count = 0
    for st, p, ln in mel:
        if only_long and ln < 4:
            continue
        m = nm(p) + song['cat_octave']
        if degrees is None:
            h = m + octave
        else:
            tones, _ = cc.chord(chords[min(st // 8, len(chords) - 1)])
            pcs = {t % 12 for t in tones}
            h = down(m, degrees, scale)
            if h % 12 not in pcs:
                h = min((v for v in range(m - 10, m - 2) if v % 12 in pcs), key=lambda v: abs(v - h))
        sample, own = CATS[cats[(st // 64) * 4]]
        v = cc.resonate(cc.hit(sample, own, h, ln * STEP * 0.95), h, even=True)
        place(x, cc.stereo(v), t2n(st * STEP), 1.0)
        count += 1
    x = reverb(cc.punch(highpass(x, 100)), 0.8, 0.25, mix=0.12)[:N]
    return cc.match_rms(x, 0.135), count


def big_choir(song_key):
    """A choir of held meows: root, third, fifth from G3 up plus the root an octave above, one bar each (half
    a bar where the chord changes inside the bar), every voice sung twice by different cats a few cents and
    milliseconds apart."""
    song = cc.SONGS[song_key]
    ch = song['chords']
    x = np.zeros((N + t2n(2.0), 2))
    spans = []
    for b in range(BARS):
        if ch[2 * b] == ch[2 * b + 1]:
            spans.append((b * 16, 16, ch[2 * b]))
        else:
            spans += [(b * 16, 8, ch[2 * b]), (b * 16 + 8, 8, ch[2 * b + 1])]
    for st, ln, sym in spans:
        tones, _ = cc.chord(sym)
        low = sorted(55 + (t - 55) % 12 for t in tones[:3])              # close position from G3 up
        voiced = low + [low[0] + 12]
        for k, m in enumerate(voiced):
            for take, (style, cents, late, side) in enumerate((('mix', -6, 0.0, -1), ('pool', 7, 0.018, 1))):
                v = cc.resonate(cc.miao(m + cents / 100.0, ln * STEP, style, flow=ln * STEP), cc.lift(m), 0.5)
                n = min(len(v), t2n(ln * STEP * 1.04))
                v = v[:n].copy()
                f = min(t2n(0.06), n // 3)
                v[:f] *= np.linspace(0, 1, f)
                v[-f:] *= np.linspace(1, 0, f)
                width = (0.75, 0.3, 0.55, 0.15)[k] * side
                place(x, pan(v, width), t2n(st * STEP + late), (1.0, 0.9, 0.9, 0.6)[k])
    x = reverb(lowpass(highpass(x, 140), 7000), 1.6, 0.45, mix=0.3)[:N]
    return cc.match_rms(x, 0.135)


from audio import lowpass  # noqa: E402

for tune in ('can_can', 'can_can_b'):
    third, n3 = strong_part(tune, 2)
    low8, n8 = strong_part(tune, None, -12, only_long=False)
    pad = big_choir(tune)
    BACK = [('fb_L0_keys', 0, None), ('L2_bass', 0, None), ('fb_L4_peak', 0, None), ('C_drums', 0, None)]
    FEVER = BACK + [('L3_cat_kichiku', -6, None), ('L3_square', -2, None), ('L3_pluck', -2, None)]
    CATS_UP = BACK + [('L3_cat_kichiku', -2, None), ('L3_square', -5, None)]      # no pluck: fewer lines on the tune
    print(f'  {tune}: harmony on {n3} long notes of {len(cc.SONGS[tune]["melody"])}')
    if tune == 'can_can':
        mix('A_big_choir', tune, FEVER + [(pad, -4, 'keep')])
        mix('B_octave_below', tune, FEVER + [(low8, -6, 'keep')])
        mix('C_harmony_on_long_notes', tune, FEVER + [(third, -4, 'keep')])
        mix('D_choir_and_long_note_harmony', tune, FEVER + [(pad, -4, 'keep'), (third, -5, 'keep')])
        mix('E_all_cats_forward_no_pluck', tune, CATS_UP + [(pad, -3, 'keep'), (third, -4, 'keep'), (low8, -7, 'keep')])
    else:
        mix('F_four_steps_choir_and_harmony', tune, BACK[:3] + [('L3_cat_kichiku', 0, None), ('L3_square', -5, None), (pad, -3, 'keep'), (third, -3, 'keep')])
print('done ->', OUT)


# Measured: the choir of meows adds almost nothing at 200-800 Hz (a meow's energy sits at 800 Hz-3 kHz, its
# fundamental is weak), so on its own it cannot make the mix fuller, only busier up there. G / H put a soft
# 'aah' pad (saws through two vowel formants) on the choir's own notes, an octave lower too: the body the
# cats lack, with the cats as the colour on top of it.
def warm_pad(song_key):
    from audio import bandpass, mtof, osc_supersaw
    song = cc.SONGS[song_key]
    x = np.zeros((N + t2n(1.0), 2))
    for h, sym in enumerate(song['chords']):
        tones, _ = cc.chord(sym)
        low = sorted(55 + (t - 55) % 12 for t in tones[:3])
        n = t2n(8 * STEP)
        k = np.arange(n) / n
        v = sum(osc_supersaw(mtof(m + o), n, voices=5, detune=0.18) * g for m in low for o, g in ((0, 1.0), (-12, 0.7)))
        v = lowpass(v, 900) + bandpass(v, 600, 1100) * 0.8 + bandpass(v, 1000, 1500) * 0.4      # 'ah'
        env = np.clip(k / 0.08, 0, 1) * np.clip((1 - k) / 0.08, 0, 1)
        place(x, v * env[:, None], t2n(h * 8 * STEP), 1.0)
    return cc.match_rms(reverb(x, 1.6, 0.45, mix=0.25)[:N], 0.135)


tune = 'can_can'
third, _ = strong_part(tune, 2)
pad, warm = big_choir(tune), warm_pad(tune)
BACK = [('fb_L0_keys', 0, None), ('L2_bass', 0, None), ('fb_L4_peak', 0, None), ('C_drums', 0, None)]
FEVER = BACK + [('L3_cat_kichiku', -6, None), ('L3_square', -2, None), ('L3_pluck', -2, None)]
mix('G_choir_with_warm_pad', tune, FEVER + [(pad, -4, 'keep'), (warm, -5, 'keep')])
mix('H_choir_warm_pad_and_long_note_harmony', tune, FEVER + [(pad, -4, 'keep'), (warm, -5, 'keep'), (third, -5, 'keep')])


# --- third round: G was the right direction ("a choir"), F was cute. What makes a choir sound FULL is not more
# parts but the treatment: many singers on each note a little apart in pitch and time (ensemble), a hall, the
# lead doubled and widened, and everything glued and pumping with the kick like the rest of the eurobeat mix.
def ensemble_choir(song_key, singers=6):
    song = cc.SONGS[song_key]
    ch = song['chords']
    x = np.zeros((N + t2n(2.0), 2))
    spans = []
    for b in range(BARS):
        if ch[2 * b] == ch[2 * b + 1]:
            spans.append((b * 16, 16, ch[2 * b]))
        else:
            spans += [(b * 16, 8, ch[2 * b]), (b * 16 + 8, 8, ch[2 * b + 1])]
    r = np.random.default_rng(3)
    for st, ln, sym in spans:
        tones, _ = cc.chord(sym)
        low = sorted(55 + (t - 55) % 12 for t in tones[:3])
        for k, m in enumerate(low + [low[0] + 12]):
            for take in range(singers):
                cents, late = r.uniform(-16, 16), r.uniform(0, 0.035)
                v = cc.resonate(cc.miao(m + cents / 100.0, ln * STEP, ('mix', 'pool')[take % 2], flow=ln * STEP), cc.lift(m), 0.5)
                n = min(len(v), t2n(ln * STEP * 1.04))
                v = v[:n].copy()
                f = min(t2n(0.07), n // 3)
                v[:f] *= np.linspace(0, 1, f)
                v[-f:] *= np.linspace(1, 0, f)
                place(x, pan(v, r.uniform(-0.9, 0.9)), t2n(st * STEP + late), (1.0, 0.9, 0.9, 0.6)[k])
    return x[:N]


def hall(x, mix_amount=0.38):
    return reverb(lowpass(highpass(x, 140), 7500), 2.6, 0.5, mix=mix_amount)[:len(x)]


def chorus(x, base_ms=(14.0, 21.0), depth_ms=3.0, rate=(0.31, 0.43), wet=0.7):
    """Doubling: the left and right get a copy on a slowly moving delay (so it is a little off in pitch and
    time, differently on each side)."""
    m = x.mean(axis=1) if x.ndim == 2 else x
    t = np.arange(len(m))
    out = np.stack([m, m], 1) * 0.8
    for c in range(2):
        d = (base_ms[c] + depth_ms * np.sin(2 * np.pi * rate[c] * t / SR + c)) * SR / 1000.0
        out[:, c] += np.interp(t - d, t, m, left=0.0) * wet
    return out


def pump4(x, floor=0.4):
    """Duck on every kick of the four-on-the-floor beat, back up over most of the beat."""
    beat = t2n(BAR / 4)
    k = (np.arange(len(x)) % beat) / beat
    g = floor + (1 - floor) * np.clip(k / 0.6, 0, 1) ** 1.5
    return x * g[:, None]


def glue(x, drive=1.6):
    return np.tanh(x * drive / max(1e-9, np.abs(x).max())) * np.abs(x).max() / np.tanh(drive)


tune = 'can_can'
dry = ensemble_choir(tune)
ens = cc.match_rms(hall(dry), 0.135)
ens_small = cc.match_rms(reverb(dry, 1.0, 0.4, mix=0.15)[:N], 0.135)
lead = stem(tune, 'L3_cat_kichiku')
lead_wide = cc.match_rms(reverb(chorus(lead), 1.4, 0.4, mix=0.15)[:N], 0.135 * 1.0)
lead_wide *= np.sqrt((lead ** 2).mean()) / np.sqrt((lead_wide ** 2).mean())
REST = BACK + [('L3_square', -2, None), ('L3_pluck', -2, None)]
mix('G1_ensemble_24_cats_small_room', tune, REST + [('L3_cat_kichiku', -6, None), (ens_small, -3, 'keep'), (warm, -5, 'keep')])
mix('G2_ensemble_in_a_hall', tune, REST + [('L3_cat_kichiku', -6, None), (ens, -3, 'keep'), (warm, -5, 'keep')])
mix('G3_hall_and_lead_doubled_wide', tune, REST + [(lead_wide, -4, 'keep'), (ens, -3, 'keep'), (warm, -5, 'keep')])
cats_bus = glue(pump4(ens * 10 ** (-2 / 20) + warm * 10 ** (-4 / 20), 0.45) + lead_wide * 10 ** (-3 / 20))
mix('G4_G3_pumping_and_glued', tune, REST + [(cats_bus, 0, 'keep')])
cats_bus5 = glue(pump4(ens * 10 ** (-2 / 20) + warm * 10 ** (-4 / 20), 0.45) + lead_wide * 10 ** (-3 / 20) + third * 10 ** (-6 / 20))
mix('G5_G4_and_long_note_harmony', tune, REST + [(cats_bus5, 0, 'keep')])
mix('G6_G5_cats_forward_square_and_pluck_down', tune, BACK + [('L3_square', -7, None), ('L3_pluck', -8, None), (cats_bus5, 2, 'keep')])
