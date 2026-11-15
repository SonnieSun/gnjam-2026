"""The meows the game plays note by note at run time (the meow patterns edited in the game: meow drums
and the kichiku cat melody). One file per roster cat: its meow at its own pitch, starting right on the
sound, at a standard loudness, with the pitch FX (the tuned resonance) baked in, so that when the game
plays it faster or slower to reach a note the resonance moves with it and stays in tune.

  <out>/meow_<id>.wav     the cat's meow
  <out>/tick_<id>.wav     only its first 70 ms (the 'mi'): for hat-like ticks
  <out>/meows.json        {"cats": [{"id", "file", "tick", "midi" (own pitch), "seconds", "roles"}]}

usage: python -I make_runtime_meows.py <loops dir> <out dir>
"""
import contextlib
import io
import json
import os
import sys

import numpy as np

LOOPS, OUT = sys.argv[1], sys.argv[2]
sys.argv = [sys.argv[0], LOOPS, '__none__']          # compose_classics: load the cats, render no song
sys.path.insert(0, os.path.dirname(__file__))
with contextlib.redirect_stdout(io.StringIO()):
    import compose_classics as cc
from audio import SR, t2n, write_wav  # noqa: E402

os.makedirs(OUT, exist_ok=True)
cats = []
seen = {}
for role in ('long', 'accent', 'short'):
    for i in cc.ROSTER[role]:
        if i in seen:
            seen[i]['roles'].append(role)
            continue
        s = cc.cat_sample(i)
        m = s.mean(axis=1) if s.ndim == 2 else s
        own = cc.native(s)
        v = cc.resonate(m, own, even=True)                      # same loudness for every cat + pitch FX
        v = cc.punch(np.stack([v, v], 1))
        v *= 0.5 / np.max(np.abs(v))
        f = t2n(0.03)
        v[-f:] *= np.linspace(1, 0, f)[:, None]
        write_wav(os.path.join(OUT, f'meow_{i:02d}.wav'), v, peak=None)
        tick = v[: t2n(0.07)].copy()
        g = t2n(0.015)
        tick[-g:] *= np.linspace(1, 0, g)[:, None]
        write_wav(os.path.join(OUT, f'tick_{i:02d}.wav'), tick, peak=None)
        seen[i] = {'id': f'{i:02d}', 'file': f'meow_{i:02d}.wav', 'tick': f'tick_{i:02d}.wav',
                   'midi': round(own, 2), 'seconds': round(len(v) / SR, 3), 'roles': [role]}
        cats.append(seen[i])
        print(f"  cat {i:02d}: own pitch {own:.1f}, {len(v) / SR:.2f} s, {role}")
with open(os.path.join(OUT, 'meows.json'), 'w', encoding='utf-8', newline='\n') as fh:
    json.dump({'cats': cats}, fh, indent=1)
print(len(cats), 'cats ->', OUT)
