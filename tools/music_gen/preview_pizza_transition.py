"""Hear the pizza's transition into its fever in context, the way the game plays it: the four steps down (cats,
choir), the transition (tr_ccb_to_cc.wav), then the famous tune in fever with the hall.

A one-bar transition takes the place of the last bar of the descent's phrase; a longer one comes after the phrase.

usage: python -I preview_pizza_transition.py <tr_ccb_to_cc.wav> <game project dir> <out.wav> [dB the level plays it at, default 14]
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import BAR, place, read_wav, reverb, t2n, write_wav  # noqa: E402

TR, GAME, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
PLAY_DB = float(sys.argv[4]) if len(sys.argv) > 4 else 14.0
A = os.path.join(GAME, 'assets', 'audio')
M = os.path.join(A, 'music')
GROOVE = read_wav(os.path.join(M, 'scene1', 'skeleton', 's1_L1_groove_4b.wav'))
B = t2n(BAR)
BEAT = B // 4


def db(d):
    return 10 ** (d / 20)


def stem(tune, part):
    return read_wav(os.path.join(M, 'classics', tune, f'{tune}_{part}_8b.wav'))


tr = read_wav(TR)
n_tr = max(1, int(len(tr) / B))                      # whole bars (the file has a short tail after them)
before = 7 if n_tr == 1 else 8                       # bars of the descent that play before it
CCB = [('L3_cat_kichiku', 0), ('L3_square', -5), ('fb_L0_keys', 0), ('L2_bass', 0), ('fb_L4_peak', 0), ('C_choir', 1)]
CC = [('L3_cat_kichiku', 0), ('L3_square_dark', -3), ('L3_pluck', -2), ('fb_L0_keys', 0), ('L2_bass', 0), ('fb_L4_peak', 0), ('C_drums', 0)]
start = before + n_tr                                # the bar the famous tune starts on
total = start + 16
pre = np.zeros((total * B + t2n(3.0), 2))
post = np.zeros((total * B + t2n(3.0), 2))
for bar in range(total):                             # the level's drums never stop
    place(pre if bar < start else post, GROOVE[(bar % 4) * B:(bar % 4 + 1) * B], bar * B, 1.0)
for part, d in CCB:                                  # the descent; the game fades it out over the first beat of the transition
    w = stem('can_can_b', part)
    w = np.concatenate([w, w])[:before * B + BEAT].copy()
    w[before * B:] *= np.linspace(1, 0, BEAT)[:, None]
    place(pre, w, 0, db(d))
place(pre, tr, before * B, db(PLAY_DB))
place(post, read_wav(os.path.join(A, 'sfx', 'crash.wav')), start * B, db(-7))
for i in range(2):
    for part, d in CC:
        place(post, stem('can_can', part), (start + i * 8) * B, db(d))
post = post + reverb(post, 2.2, 0.45, mix=1.0)[:len(post)] * 0.35      # the fever's hall (the game's own reverb sounds different)
x = (pre + post)[:total * B + t2n(1.0)]
f = t2n(0.5)
x[-f:] *= np.linspace(1, 0, f)[:, None]
write_wav(OUT, x, peak=0.9)
print(f'{OUT}: {before} bars of the descent, {n_tr} bar(s) of transition, 16 bars of fever')
