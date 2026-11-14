"""Scene 1's riff sung the way the classics are: by the roster's cats (loops/meow_roster.json), each
meow ringing out and overlapping the next instead of being chopped to the note, with a little pitch FX.

  <loops>/s1_disc/s1_disc_C_lead_flow_4b.wav      the meows overlap ('flow'), the usual cat lead
  <loops>/s1_disc/s1_disc_C_lead_kichiku_4b.wav   kichiku: one cat for the phrase, pitch by speed, hard cuts

The older s1_disc_C_lead_4b.wav (compose_disc.py) cuts every 16th note to 0.13 s and uses the first
sample kit; these two replace it where the tune should read as "Miiiiao".

usage: python -I make_scene1_cat_leads.py <loops dir>          (CAT_BPM=120 for the 120 BPM set)
"""
import contextlib
import io
import os
import sys

import numpy as np

LOOPS = sys.argv[1]
sys.argv = [sys.argv[0], LOOPS, '__none__']          # compose_classics: load everything, render no song
sys.path.insert(0, os.path.dirname(__file__))
with contextlib.redirect_stdout(io.StringIO()):
    import compose_classics as cc
from audio import write_wav  # noqa: E402

# the scene 1 riff (compose_disc.py RIFF_A), one row per bar: (16th step, note, length in 16ths)
RIFF_A = [
    [(0, 'Bb5', 1), (2, 'Bb5', 1), (6, 'G5', 1), (8, 'Bb5', 1), (10, 'C6', 1), (12, 'D6', 3)],
    [(0, 'C6', 3), (4, 'A5', 1), (6, 'F5', 1), (8, 'A5', 1), (10, 'Bb5', 1), (12, 'C6', 3)],
    [(0, 'A5', 1), (2, 'A5', 1), (6, 'F5', 1), (8, 'D5', 1), (10, 'F5', 1), (12, 'A5', 3)],
    [(0, 'Bb5', 1), (2, 'A5', 1), (4, 'G5', 3), (8, 'D5', 1), (10, 'G5', 1), (12, 'A5', 1), (14, 'Bb5', 1)],
]
song = {'melody': [(bar * 16 + s, p, ln) for bar, row in enumerate(RIFF_A) for s, p, ln in row], 'cat_octave': -12}
leads = cc.cat_leads(song, len(RIFF_A), set())
for key, name in (('L3_cat_flow', 'C_lead_flow'), ('L3_cat_kichiku', 'C_lead_kichiku')):
    x = leads[key]
    path = os.path.join(LOOPS, 's1_disc', f's1_disc_{name}_4b.wav')
    write_wav(path, x * (1.0 / max(1.0, np.max(np.abs(x)) / 0.98)), peak=None)
    print(path, f'rms {np.sqrt(np.mean(x ** 2)):.3f}')
