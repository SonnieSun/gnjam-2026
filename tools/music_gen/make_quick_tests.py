"""Test renders of the Turkish March kichiku lead with different meows on its fast notes (CAT_QUICK of
compose_classics.py): the first 8 bars over the backing, one file per choice.

usage: python -I make_quick_tests.py <loops dir> <game audio dir> <out dir>
"""
import os
import shutil
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import BAR, place, read_wav, t2n, write_wav  # noqa: E402

LOOPS, GAME, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(OUT, exist_ok=True)
stem = os.path.join(LOOPS, 'classics', 'turkish_march_L3_cat_kichiku_16b.wav')
keep = stem + '.keep'
shutil.copy(stem, keep)
CHOICES = [('1_mi_cat', 'S2@0', "the short 'mi' meow from its start"),
           ('2_low_cat', 'S3@0', 'the low short cat from its start (pitched far up)'),
           ('3_kitten_from_the_bright_part', 'S1@0.22', 'the kitten, starting 0.22 s into its meow'),
           ('4_first_long_cat', 'L0@0', 'the first long cat from its start'),
           ('5_own_cat_plus_mi', 'own+mi', "the phrase's own cat, with a kitten 'mi' layered on each fast note"),
           ('6_own_cat_plus_mi_on_every_note', 'own+mi_all', "the same, and a 'mi' on the long notes too")]
if len(sys.argv) > 4:
    CHOICES = [c for c in CHOICES if c[0][0] in sys.argv[4]]
try:
    for name, quick, what in CHOICES:
        subprocess.run([sys.executable, '-I', os.path.join(os.path.dirname(__file__), 'compose_classics.py'), LOOPS, 'turkish_march'],
                       env=dict(os.environ, CAT_QUICK=quick), check=True, stdout=subprocess.DEVNULL)
        n = t2n(8 * BAR)
        x = np.zeros((n + t2n(0.5), 2))
        groove = read_wav(os.path.join(GAME, 'music', 'scene1', 'skeleton', 's1_L1_groove_4b.wav'))
        for i in range(2):
            place(x, groove, t2n(i * 4 * BAR), 1.0)
        folder = os.path.join(GAME, 'music', 'classics', 'turkish_march')
        for part in ('fb_L0_keys_16b', 'L2_bass_16b'):
            place(x, read_wav(os.path.join(folder, f'turkish_march_{part}.wav'))[:n], 0, 1.0)
        place(x, read_wav(stem)[:n], 0, 1.0)
        f = t2n(0.3)
        x[-f:] *= np.linspace(1, 0, f)[:, None]
        write_wav(os.path.join(OUT, f'turkish_fast_notes_{name}.wav'), x, peak=0.9)
        solo = read_wav(stem)[:n].copy()
        solo[-f:] *= np.linspace(1, 0, f)[:, None]
        write_wav(os.path.join(OUT, f'turkish_fast_notes_{name}_cats_only.wav'), solo, peak=0.9)
        print(f'  {name}: {what}')
finally:
    shutil.move(keep, stem)
