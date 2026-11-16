"""The cats' CHOIR stem for a slow tune section: held meows on the chords plus a harmony on the tune's long
notes. Picked by ear on 2026-11-16 (make_cat_harmony_tests.py, file F): it works where the tune moves in
quarter notes or slower, because a meow needs that long to settle on its pitch, so several of them lock into
a chord. On a fast tune (eighths at 160 BPM: Can-Can's famous strain) the same treatment is only clutter, with
any amount of ensemble / hall / glue; do not use it there.

  <loops>/classics/<tune>_C_choir_<bars>b.wav
     the choir   root, third, fifth from G3 up + the root an octave above, a bar per chord (half a bar where
                 the chord changes inside the bar), every voice sung twice by different cats a few cents and
                 milliseconds apart, left and right, in a room
     the harmony a third below the tune (bent onto the chord) on the notes a quarter note or longer, sung
                 kichiku style by the same cat as the lead in that phrase, so it blends with it
The stem loops (its tail is folded onto its start) and is meant for the 'harm' lane (-5 dB) in place of the
run-time backing vocals.

usage: python -I make_choir_stems.py <loops dir> [tune ...]      (default: can_can_b)
"""
import contextlib
import io
import os
import sys

import numpy as np

LOOPS, TUNES = sys.argv[1], sys.argv[2:] or ['can_can_b']
sys.argv = [sys.argv[0], LOOPS, '__none__']
sys.path.insert(0, os.path.dirname(__file__))
with contextlib.redirect_stdout(io.StringIO()):
    import compose_classics as cc
from audio import BAR, highpass, lowpass, nm, pan, place, reverb, t2n, write_wav  # noqa: E402

STEP = BAR / 16
CATS = [(c.mean(axis=1) if c.ndim == 2 else c, cc.native(c)) for c in cc.LONG + cc.ACCENT + cc.SHORT]
SCALES = {'can_can_b': (2, 4, 6, 7, 9, 11, 1)}          # the notes of the tune's key (D major)
STEM_DB = -4.0     # the level the stem is written at (peaks ~0.75). In the level its clip has gain_db +6 on the
                   # -5 dB harm lane: choir and harmony each end up 3 dB under the lead, as in the test render


def down(midi, degrees, scale):
    ladder = [o * 12 + p for o in range(11) for p in sorted(scale)]
    i = max(k for k, v in enumerate(ladder) if v <= midi)
    return ladder[i - degrees]


def lead_cats(song, bars):
    """The cat the kichiku lead uses in each four-bar phrase (the rule of compose_classics.cat_leads)."""
    mel, prev, out = song['melody'], None, {}
    for ph in range(0, bars, 4):
        idx = [i for i, (st, _, _) in enumerate(mel) if ph <= st // 16 < ph + 4]
        mid = float(np.median([nm(mel[i][1]) + song['cat_octave'] for i in idx]))
        prev = next(c for c in sorted(range(len(CATS)), key=lambda c: abs(CATS[c][1] - mid)) if c != prev)
        out[ph] = prev
    return out


def harmony(song, bars, scale):
    n_all = t2n(bars * BAR)
    x = np.zeros((n_all + cc.TAIL, 2))
    cats = lead_cats(song, bars)
    for st, p, ln in song['melody']:
        if ln < 4:
            continue
        m = nm(p) + song['cat_octave']
        tones, _ = cc.chord(song['chords'][min(st // 8, len(song['chords']) - 1)])
        pcs = {t % 12 for t in tones}
        h = down(m, 2, scale)
        if h % 12 not in pcs:
            h = min((v for v in range(m - 10, m - 2) if v % 12 in pcs), key=lambda v: abs(v - h))
        sample, own = CATS[cats[(st // 64) * 4]]
        place(x, cc.stereo(cc.resonate(cc.hit(sample, own, h, ln * STEP * 0.95), h, even=True)), t2n(st * STEP), 1.0)
    y = reverb(cc.punch(highpass(x, 100)), 0.8, 0.25, mix=0.12)
    return cc.match_rms(cc.finish(y, bars), 0.135)


def choir(song, bars):
    ch = song['chords']
    n_all = t2n(bars * BAR)
    x = np.zeros((n_all + cc.TAIL, 2))
    spans = []
    for b in range(bars):
        if ch[2 * b] == ch[2 * b + 1]:
            spans.append((b * 16, 16, ch[2 * b]))
        else:
            spans += [(b * 16, 8, ch[2 * b]), (b * 16 + 8, 8, ch[2 * b + 1])]
    for st, ln, sym in spans:
        tones, _ = cc.chord(sym)
        low = sorted(55 + (t - 55) % 12 for t in tones[:3])
        for k, m in enumerate(low + [low[0] + 12]):
            for style, cents, late, side in (('mix', -6, 0.0, -1), ('pool', 7, 0.018, 1)):
                v = cc.resonate(cc.miao(m + cents / 100.0, ln * STEP, style, flow=ln * STEP), cc.lift(m), 0.5)
                n = min(len(v), t2n(ln * STEP * 1.04))
                v = v[:n].copy()
                f = min(t2n(0.06), n // 3)
                v[:f] *= np.linspace(0, 1, f)
                v[-f:] *= np.linspace(1, 0, f)
                place(x, pan(v, (0.75, 0.3, 0.55, 0.15)[k] * side), t2n(st * STEP + late), (1.0, 0.9, 0.9, 0.6)[k])
    y = reverb(lowpass(highpass(x, 140), 7000), 1.6, 0.45, mix=0.3)
    return cc.match_rms(cc.finish(y, bars), 0.135)


for tune in TUNES:
    song = cc.SONGS[tune]
    bars = len(song['chords']) // 2
    x = (choir(song, bars) + harmony(song, bars, SCALES[tune])) * 10 ** (STEM_DB / 20)
    path = os.path.join(LOOPS, 'classics', f'{tune}_C_choir_{bars}b.wav')
    assert np.abs(x).max() < 0.98, np.abs(x).max()
    write_wav(path, x, peak=None)
    print(f'  {os.path.basename(path)}: peak {np.abs(x).max():.2f}, rms {np.sqrt((x ** 2).mean()):.3f}')


# The square lead for where it doubles the cats on a fast tune (the pizza's fever, Can-Can's famous strain):
# the same stem without its top (low-pass 2.2 kHz), so the 2-5 kHz where a meow reads belongs to the cats.
# Picked by ear on 2026-11-16 (file 2 of deliver/previews/pizza_fever_cats_forward); the level plays it 3 dB down.
from audio import read_wav  # noqa: E402

for tune, bars in (('can_can', 8),):
    src = os.path.join(LOOPS, 'classics', f'{tune}_L3_square_{bars}b.wav')
    x = read_wav(src)
    n = len(x)
    y = lowpass(np.concatenate([x, x, x]), 2200)[n:2 * n]          # filtered as a loop: no click at the seam
    write_wav(os.path.join(LOOPS, 'classics', f'{tune}_L3_square_dark_{bars}b.wav'), y, peak=None)
    print(f'  {tune}_L3_square_dark_{bars}b.wav: peak {np.abs(y).max():.2f}')
