"""What the harmony lane sounds like in the game, rendered offline: the tune's backing (drums, chords, bass),
the cat lead stem the level uses, and the harmony pattern played the way MeowPlayer plays it (the run-time
cat samples, one cat per four-bar phrase picked by pitch and never the same twice in a row, pitched by
playback speed, cut at 95 % of the note, the lane 5 dB down).

usage: python -I make_harmony_previews.py <game project dir> <out dir>
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import BAR, SR, pan, place, read_wav, resample, t2n, write_wav  # noqa: E402

PROJECT, OUT = sys.argv[1], sys.argv[2]
A = os.path.join(PROJECT, 'assets', 'audio')
os.makedirs(OUT, exist_ok=True)
STEP = BAR / 16
RT = os.path.join(A, 'meows', 'runtime')
CATS = {c['id']: (read_wav(os.path.join(RT, c['file'])), float(c['midi']))
        for c in json.load(open(os.path.join(RT, 'meows.json'), encoding='utf-8'))['cats']}
LANE_DB = -5.0


def harmony(pattern, bars_total):
    bars = int(pattern['bars'])
    x = np.zeros((t2n(bars_total * BAR) + t2n(1.0), 2))
    last = ''
    phrase_cat = {}
    for rep in range(bars_total // bars):
        for step, midi, ln in pattern['notes']:
            phrase = step // 64
            if phrase not in phrase_cat:
                pitches = sorted(m for s, m, _ in pattern['notes'] if s // 64 == phrase)
                mid = pitches[len(pitches) // 2]
                best = min((c for c in CATS if c != last or len(CATS) == 1), key=lambda c: abs(CATS[c][1] - mid))
                phrase_cat[phrase] = last = best
            s, own = CATS[pattern['cat']] if pattern.get('cat') in CATS else CATS[phrase_cat[phrase]]
            pitch = min(max(2 ** ((midi - own) / 12), 0.25), 4.0)   # the player's pitch_scale
            v = resample(s, 1.0 / pitch)                            # resample() takes the new length / old length
            n = min(len(v), t2n(ln * STEP * 0.95))
            v = v[:n].copy()
            f = min(t2n(0.005), n // 2)
            v[-f:] *= np.linspace(1, 0, f)[:, None] if v.ndim == 2 else np.linspace(1, 0, f)
            place(x, v, t2n((rep * bars * 16 + step) * STEP), 10 ** ((LANE_DB + float(pattern.get('gain_db', 0.0))) / 20))
    return x


def render(name, tune, lead, bars_total, stem_bars):
    folder = os.path.join(A, 'music', 'classics', tune)
    n = t2n(bars_total * BAR)
    base = np.zeros((n + t2n(1.0), 2))
    groove = read_wav(os.path.join(A, 'music', 'scene1', 'skeleton', 's1_L1_groove_4b.wav'))
    for i in range(bars_total // 4):
        place(base, groove, t2n(i * 4 * BAR), 1.0)
    for part in (f'fb_L0_keys_{stem_bars}b', f'L2_bass_{stem_bars}b', f'{lead}_{stem_bars}b'):
        w = read_wav(os.path.join(folder, f'{tune}_{part}.wav'))
        for i in range(bars_total // stem_bars):
            place(base, w, t2n(i * stem_bars * BAR), 1.0)
    pattern = json.load(open(os.path.join(PROJECT, 'levels', 'music', 'patterns', f'harm_{tune}.json'), encoding='utf-8'))
    h = harmony(pattern, bars_total)
    for label, x in (('with_harmony', base + h), ('harmony_and_backing_only', base * 0 + h + _backing(folder, tune, groove, bars_total, stem_bars))):
        x = x.copy()
        f = t2n(0.4)
        x[-f:] *= np.linspace(1, 0, f)[:, None]
        write_wav(os.path.join(OUT, f'{name}_{label}.wav'), x, peak=0.9)
    print(f'  {name}: {bars_total} bars, {len(pattern["notes"]) * (bars_total // int(pattern["bars"]))} harmony notes')


def _backing(folder, tune, groove, bars_total, stem_bars):
    x = np.zeros((t2n(bars_total * BAR) + t2n(1.0), 2))
    for i in range(bars_total // 4):
        place(x, groove, t2n(i * 4 * BAR), 1.0)
    for part in (f'fb_L0_keys_{stem_bars}b', f'L2_bass_{stem_bars}b'):
        w = read_wav(os.path.join(folder, f'{tune}_{part}.wav'))
        for i in range(bars_total // stem_bars):
            place(x, w, t2n(i * stem_bars * BAR), 1.0)
    return x


render('1_ode_to_joy_sky', 'ode_to_joy', 'L3_cat_flow', 16, 16)
render('2_your_best_friend_washer', 'your_best_friend', 'L3_cat_kichiku', 16, 8)
render('3_mountain_king_earth', 'mountain_king', 'L3_cat_kichiku', 8, 8)
render('4_can_can_earth_and_pizza', 'can_can', 'L3_cat_kichiku', 16, 8)
render('5_turkish_march_shooter', 'turkish_march', 'L3_cat_kichiku', 16, 16)
render('6_turkish_march_b_shooter_fever', 'turkish_march_b', 'L3_cat_kichiku', 16, 8)
render('7_entertainer_level_1', 'entertainer', 'L3_cat_kichiku', 16, 16)
render('8_can_can_opening_strain_pizza', 'can_can_a', 'L3_cat_kichiku', 16, 8)
print('done ->', OUT)
