"""Audition of the most 'Miiiiao' meows: for each candidate, the meow as recorded, then the same
meow singing G4-B4-D5-G5 (half a second each, 'iii' held, slide kept), then a gap.

usage: python -I miao_audition.py <samples dir> <out wav>
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import SR, nm, read_wav, write_wav  # noqa: E402
from psola import sing_miao  # noqa: E402
from slicer import slices  # noqa: E402

S = sys.argv[1]
CANDIDATES = [   # (file, start s) - the top of tools/miao_score.py
    ('commons_animals/Weibliche Britisch Kurzhaar will Futter C1277 MIAUEN.wav', 11.45),
    ('commons_animals/Weibliche Britisch Kurzhaar will Futter C1277 MIAUEN.wav', 7.59),
    ('bigsoundbank_cats/ANMLCat_Meow cat 4 (ID 1892)_BigSoundBank.com.wav', 0.05),
    ('bigsoundbank_cats/ANMLCat_Meow cat 13 (ID 1901)_BigSoundBank.com.wav', 4.03),
    ('bigsoundbank_cats/ANMLCat_Small mewing of a cat (ID 0098)_BigSoundBank.com.wav', 1.09),
    ('bigsoundbank_cats/ANMLCat_Mewing kitten 3 weeks (ID 0390)_BigSoundBank.com.wav', 2.46),
]
parts = []
for f, start in CANDIDATES:
    x = read_wav(os.path.join(S, f))
    sl = min(slices(x, min_len=0.3, max_len=2.0, gate_db=-30), key=lambda s: abs(s['start'] / SR - start))['audio']
    sl = sl / np.max(np.abs(sl))
    parts += [sl.mean(axis=1) * 0.8, np.zeros(int(0.25 * SR))]
    for m in ('G4', 'B4', 'D5', 'G5'):
        parts.append(sing_miao(sl, nm(m), 0.5) * 0.8)
    parts.append(np.zeros(int(0.8 * SR)))
write_wav(sys.argv[2], np.concatenate(parts), peak=0.89)
print('written', sys.argv[2])
