"""Ask / answer leads for scene 1: an instrument plays the first half of the riff (bars 1-2 of the 4-bar
loop) and the cats answer with the second half (bars 3-4). Cut from the stems that already exist, so the
cats' first entrance in a song is a reply instead of a takeover.

  <loops>/s1_disc/s1_disc_QA_<style>_4b.wav     style = B (disco), fb (future bass), A (eurobeat), chip

usage: python -I make_ask_answer.py <loops dir>          (run it on the 160 and on the 120 loops dir)
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import SR, read_wav, write_wav  # noqa: E402

DISC = os.path.join(sys.argv[1], 's1_disc')
cats = read_wav(os.path.join(DISC, 's1_disc_C_lead_flow_4b.wav'))
half = len(cats) // 2
fade = int(0.006 * SR)
for style in ('B', 'fb', 'A', 'chip'):
    hook = read_wav(os.path.join(DISC, f's1_disc_{style}_L3_hook_4b.wav'))
    out = np.zeros_like(cats)
    out[:half] = hook[:half]
    out[half - fade: half] *= np.linspace(1, 0, fade)[:, None]          # the instrument stops for the answer
    out[half:] = cats[half:]
    out[half: half + fade] *= np.linspace(0, 1, fade)[:, None]
    out[-fade:] *= np.linspace(1, 0, fade)[:, None]                     # and the cats for the next question
    out[:fade] *= np.linspace(0, 1, fade)[:, None]
    path = os.path.join(DISC, f's1_disc_QA_{style}_4b.wav')
    write_wav(path, out, peak=None)
    print(path)
