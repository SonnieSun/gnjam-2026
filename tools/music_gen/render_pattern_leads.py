"""A cat melody pattern (levels/music/patterns/<name>.json in the game, e.g. made by midi_to_pattern.py
from a MIDI file) -> the pre-rendered cat leads, sung the way the classics are:

  <loops>/custom/<name>_L3_cat_flow_<N>b.wav      every meow rings out and overlaps the next
  <loops>/custom/<name>_L3_cat_<N>b.wav           cut to the note
  <loops>/custom/<name>_L3_cat_kichiku_<N>b.wav   kichiku (one cat per 4 bars, pitch by speed, hard cuts)

These are the high-quality versions (held 'iii', formants kept); the game can also play the same pattern
directly at run time, which is rougher but needs no render.

usage: python -I render_pattern_leads.py <pattern.json> <loops dir>      (CAT_BPM=120 for 120 BPM)
"""
import contextlib
import io
import json
import os
import sys

import numpy as np

PATTERN, LOOPS = sys.argv[1], sys.argv[2]
sys.argv = [sys.argv[0], LOOPS, '__none__']          # compose_classics: load the cats, render no song
sys.path.insert(0, os.path.dirname(__file__))
with contextlib.redirect_stdout(io.StringIO()):
    import compose_classics as cc
from audio import write_wav  # noqa: E402

NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
p = json.load(open(PATTERN, encoding='utf-8'))
assert p.get('kind') == 'melody', 'only melody patterns can be rendered'
bars = int(p['bars'])
melody = [(int(s), f'{NAMES[int(m) % 12]}{int(m) // 12 - 1}', int(ln)) for s, m, ln in sorted(p['notes'])]
song = {'melody': melody, 'cat_octave': 0}
last = {max(i for i, (s, _, _) in enumerate(melody) if s // 16 == b)
        for b in range(3, bars, 4) if any(s // 16 == b for s, _, _ in melody)}
leads = cc.cat_leads(song, bars, last)
name = os.path.splitext(os.path.basename(PATTERN))[0]
out = os.path.join(LOOPS, 'custom')
os.makedirs(out, exist_ok=True)
for key in ('L3_cat_flow', 'L3_cat', 'L3_cat_kichiku'):
    x = leads[key]
    path = os.path.join(out, f'{name}_{key}_{bars}b.wav')
    write_wav(path, x * (1.0 / max(1.0, np.max(np.abs(x)) / 0.98)), peak=None)
    print(path)
