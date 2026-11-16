"""Test sets for "how should the cats sing": the same 8 bars of a tune over its backing, sung five ways.
Made after looking at how Mewgenics does it (one vocal MIDI per song with a lead and a backing-vocal track;
one ordinary meow per cat, pitched to each note by changing the playback speed).

  1_ours_now          what the game has: the kichiku lead stem (hard cut, one cat per phrase, resonance)
  2_plain_one_cat     Mewgenics style, lead only: ONE cat, ONE meow, speed-pitched, left to ring, no FX
  3_plain_lead_bgv    2 + a backing-vocal part: a second cat on short off-beat chord notes
  4_choir             three cats sing the lead together (each a little off in time and tune) + two on backing
  5_ours_plus_bgv     1 + the backing-vocal part with our resonance: the "add a harmony lane" candidate

usage: python -I make_choir_tests.py <loops dir> <game audio dir (assets/audio)> <out dir>
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
from audio import BAR, SR, nm, pan, place, read_wav, resample, reverb, t2n, write_wav  # noqa: E402

os.makedirs(OUT, exist_ok=True)
STEP = BAR / 16
BARS = 8
N = t2n(BARS * BAR)
rng = np.random.default_rng(7)


def mono(s):
    return s.mean(axis=1) if s.ndim == 2 else s


CATS = [(mono(s), cc.native(s)) for s in cc.LONG + cc.SHORT]      # (sample, its own pitch)


def nearest_cats(midi, k=1, skip=()):
    order = sorted((i for i in range(len(CATS)) if i not in skip), key=lambda i: abs(CATS[i][1] - midi))
    return order[:k]


def fold(midi, own):
    """Bring a note into the cat's range by octaves (a meow far from its own pitch stops being a cat)."""
    while midi - own > 8:
        midi -= 12
    while own - midi > 6:
        midi += 12
    return midi


def plain(cat, midi, room, cents=0.0):
    """Mewgenics style: the whole meow, played faster or slower to reach the note. It rings until the next
    note of the same part starts (room, seconds), with a short fade there."""
    s, own = CATS[cat]
    v = resample(s, 2 ** ((own - fold(midi, own) - cents / 100.0) / 12))
    n = min(len(v), t2n(room))
    v = v[:n].copy()
    f = min(t2n(0.03), n // 2)
    v[-f:] *= np.linspace(1, 0, f)
    return v


def ours(cat, midi, steps):
    s, own = CATS[cat]
    m = fold(midi, own)
    return cc.resonate(cc.hit(s, own, m, steps * STEP * 0.95), m)


def level(x, target):
    return x * target / (np.sqrt(np.mean(x ** 2)) + 1e-9)


def bgv_notes(song):
    """The backing-vocal part: short notes on the off-beat eighths, the third and the fifth of the chord in
    turn, between C4 and B4 (under the tune). Left out where the tune itself has a note on that eighth."""
    busy = {st for st, _, _ in song['melody']}
    out = []
    for h, sym in enumerate(song['chords'][: BARS * 2]):
        tones, _ = cc.chord(sym)
        third, fifth = tones[1 % len(tones)], tones[2 % len(tones)]
        for k, st in enumerate((2, 6)):
            step = h * 8 + st
            if step in busy:
                continue
            m = (third, fifth)[k]
            while m < 60:
                m += 12
            while m > 71:
                m -= 12
            out.append((step, m, 2))
    return out


def render(name, key):
    song = cc.SONGS[key]
    folder = os.path.join(GAME, 'music', 'classics', key)
    back = np.zeros((N + t2n(1.0), 2))
    groove = read_wav(os.path.join(GAME, 'music', 'scene1', 'skeleton', 's1_L1_groove_4b.wav'))
    for i in range(BARS // 4):
        place(back, groove, t2n(i * 4 * BAR), 0.8)
    place(back, read_wav(os.path.join(folder, f'{key}_fb_L0_keys_8b.wav')), 0, 0.8)
    place(back, read_wav(os.path.join(folder, f'{key}_L2_bass_8b.wav')), 0, 0.8)
    stem = read_wav(os.path.join(folder, f'{key}_L3_cat_kichiku_8b.wav'))
    target = float(np.sqrt(np.mean(stem ** 2)))
    lead = [(st, nm(p), ln) for st, p, ln in song['melody'] if st < BARS * 16]
    bgv = bgv_notes(song)
    mid = float(np.median([m for _, m, _ in lead]))
    lead_cats = nearest_cats(mid, 3)
    bgv_cats = nearest_cats(66, 2, skip=lead_cats)

    def part(notes, fn, cats, side=0.0, jitter=0.0, detune=0.0):
        x = np.zeros((N + t2n(1.0), 2))
        for c_i, cat in enumerate(cats):
            for i, (st, m, ln) in enumerate(notes):
                nxt = notes[i + 1][0] if i + 1 < len(notes) else BARS * 16
                at = st * STEP + (rng.uniform(-jitter, jitter) if jitter else 0.0)
                v = fn(cat, m, ln, (nxt - st) * STEP, rng.uniform(-detune, detune) if detune else 0.0)
                place(x, pan(v, side + (c_i - (len(cats) - 1) / 2) * 0.5), max(t2n(at), 0), 1.0)
        return x

    def plain_fn(cat, m, ln, room, cents):
        return plain(cat, m, room, cents)

    def ours_fn(cat, m, ln, room, cents):
        return ours(cat, m, ln)

    sets = {
        '1_ours_now': [stem[: len(back)] if len(stem) >= len(back) else np.pad(stem, ((0, len(back) - len(stem)), (0, 0)))],
        '2_plain_one_cat': [level(part(lead, plain_fn, lead_cats[:1]), target)],
        '3_plain_lead_bgv': [level(part(lead, plain_fn, lead_cats[:1]), target),
                             level(part(bgv, plain_fn, bgv_cats[:1], side=0.3), target * 0.6)],
        '4_choir': [level(part(lead, plain_fn, lead_cats, jitter=0.018, detune=18.0), target),
                    level(part(bgv, plain_fn, bgv_cats, side=0.2, jitter=0.012, detune=12.0), target * 0.6)],
        '5_ours_plus_bgv': [None, level(part(bgv, ours_fn, bgv_cats[:1], side=0.3), target * 0.55)],
    }
    sets['5_ours_plus_bgv'][0] = sets['1_ours_now'][0]
    for label, parts in sets.items():
        once = back + sum(parts)
        once = reverb(once, 0.8, 0.3, mix=0.06)
        x = np.zeros((2 * N + t2n(1.0), 2))                 # twice through, so the loop point is heard too
        place(x, once, 0, 1.0)
        place(x, once, N, 1.0)
        f = t2n(0.4)
        x[-f:] *= np.linspace(1, 0, f)[:, None]
        path = os.path.join(OUT, f'{name}_{label}.wav')
        write_wav(path, x, peak=0.9)
        print(f'  {os.path.basename(path)}  lead cats {lead_cats} bgv cats {bgv_cats}  bgv notes {len(bgv)}')


render('ode', 'ode_to_joy')
render('cancan', 'can_can')
print('done ->', OUT)
