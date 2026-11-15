"""Before / after numbers for the cat-stem clean-up (flow leads cut at the next note, thinner cat chords
and cat bass), and optional listening previews.

  per stem (the files in the Godot project, old ones from the backup):
    frames old/new (must be equal), RMS old -> new, hit level old -> new (95th percentile of 20 ms RMS)
  per flow lead (from the renderer, old script from the backup vs the current one):
    ring  share of the meows' energy that sounds later than 50 ms after the next note has started
    2+    share of the loop during which two or more notes sound at once (above -30 dB of the loudest)
    3+    the same for three or more

usage: python -I check_cat_cleanup.py <loops dir> <backup dir> <godot project dir> [<previews dir>]
"""
import contextlib
import glob
import importlib.util
import io
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
LOOPS, BACKUP, G = sys.argv[1], sys.argv[2], sys.argv[3]
PREVIEWS = sys.argv[4] if len(sys.argv) > 4 else None
M = os.path.join(G, 'assets', 'audio', 'music')
sys.path.insert(0, HERE)
from audio import BAR, SR, place, read_wav, softclip, t2n, write_wav  # noqa: E402


def load(path, name):
    sys.argv = [path, LOOPS, '__none__']                 # compose_classics: load everything, render no song
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    with contextlib.redirect_stdout(io.StringIO()):
        spec.loader.exec_module(mod)
    return mod


def stats(path):
    x = read_wav(path)
    m, w = x.mean(axis=1), t2n(0.02)
    e = np.sqrt(np.mean(m[: len(m) // w * w].reshape(-1, w) ** 2, axis=1))
    return len(x), float(np.sqrt(np.mean(x ** 2))), float(np.percentile(e, 95))


def db(a, b):
    return 20 * np.log10(max(b, 1e-9) / max(a, 1e-9))


# --- 1. every re-rendered stem: length and level ----------------------------------------------
print('stem                                              frames old / new      RMS old -> new (dB)      hit old -> new (dB)')
bad = 0
olds = sorted(glob.glob(os.path.join(BACKUP, 'game', '*.wav')))
for old in olds:
    name = os.path.basename(old)
    new = (glob.glob(os.path.join(M, 'classics', '*', name)) + glob.glob(os.path.join(M, 'scene1', 'cat_band', name)))[0]
    (n0, r0, h0), (n1, r1, h1) = stats(old), stats(new)
    same = open(old, 'rb').read() == open(new, 'rb').read()
    bad += n0 != n1 or same
    print(f'{name:48s} {n0:8d} / {n1:8d} {"ok " if n0 == n1 else "DIFFERENT"}  {r0:.3f} -> {r1:.3f} ({db(r0, r1):+.1f})'
          f'    {h0:.3f} -> {h1:.3f} ({db(h0, h1):+.1f}){"   NOT RE-RENDERED" if same else ""}')
print(f'{len(olds)} stems, {bad} problems\n')

# --- 2. the flow leads: how much the meows overlap --------------------------------------------
RIFF_A = [                                               # scene 1's riff (make_scene1_cat_leads.py)
    [(0, 'Bb5', 1), (2, 'Bb5', 1), (6, 'G5', 1), (8, 'Bb5', 1), (10, 'C6', 1), (12, 'D6', 3)],
    [(0, 'C6', 3), (4, 'A5', 1), (6, 'F5', 1), (8, 'A5', 1), (10, 'Bb5', 1), (12, 'C6', 3)],
    [(0, 'A5', 1), (2, 'A5', 1), (6, 'F5', 1), (8, 'D5', 1), (10, 'F5', 1), (12, 'A5', 3)],
    [(0, 'Bb5', 1), (2, 'A5', 1), (4, 'G5', 3), (8, 'D5', 1), (10, 'G5', 1), (12, 'A5', 1), (14, 'Bb5', 1)],
]


def overlap(cc, song, bars, last):
    cc.VOICES.clear()
    cc._turns.clear()
    cc.cat_leads(song, bars, last)
    mel, step, n = song['melody'], cc.STEP, t2n(bars * BAR)
    w = t2n(0.01)
    env = np.zeros((len(mel), n // w + 1))
    late = total = 0.0
    for i, at, v in cc.VOICES['L3_cat_flow']:
        nxt = t2n((mel[i + 1][0] if i + 1 < len(mel) else mel[0][0] + bars * 16) * step) + t2n(0.05)
        total += float(np.sum(v ** 2))
        late += float(np.sum(v[max(0, nxt - at):] ** 2))
        for k in range(0, len(v), w):                    # 10 ms energy of each note, wrapped round the loop
            env[i, ((at + k) % n) // w] += float(np.sum(v[k:k + w] ** 2))
    on = env > env.max() * 10 ** (-30 / 10)
    count = on.sum(axis=0)
    return late / total, float(np.mean(count >= 2)), float(np.mean(count >= 3))


old_cc = load(os.path.join(BACKUP, 'tools', 'compose_classics.py'), 'cc_old')
new_cc = load(os.path.join(HERE, 'compose_classics.py'), 'cc_new')
print('flow lead           ring old -> new      2+ notes old -> new     3+ notes old -> new')
for name, song in list(new_cc.SONGS.items()) + [('scene1', None)]:
    row = []
    for cc in (old_cc, new_cc):
        if song is None:
            s = {'melody': [(b * 16 + st, p, ln) for b, r in enumerate(RIFF_A) for st, p, ln in r], 'cat_octave': -12}
            bars, last = 4, set()
        else:
            s = cc.slowed(cc.SONGS[name], cc.SPEED.get(name, 1))
            bars = len(s['chords']) // 2
            last = {max(i for i, (st, _, _) in enumerate(s['melody']) if st // 16 == b)
                    for b in range(3, bars, 4) if any(st // 16 == b for st, _, _ in s['melody'])}
        row.append(overlap(cc, s, bars, last))
    (a, b, c), (d, e, f) = row
    print(f'{name:18s} {a:6.1%} -> {d:5.1%}      {b:6.1%} -> {e:5.1%}        {c:6.1%} -> {f:5.1%}')

# --- 3. listening previews: 8 bars, before / after ----------------------------------------------
if PREVIEWS:
    os.makedirs(PREVIEWS, exist_ok=True)
    BAR_N = t2n(BAR)

    def mix(path, stems):
        out = np.zeros((8 * BAR_N, 2))
        for f, g in stems:
            x = read_wav(f)
            for k in range(0, len(out), len(x)):
                place(out, x, k, g)
        write_wav(path, softclip(out * 0.9, 1.3), peak=0.89)

    S1 = os.path.join(M, 'scene1')
    groove = os.path.join(S1, 'skeleton', 's1_L1_groove_4b.wav')

    def stem(folder, name, which):                       # which: 'before' reads the backup when it has the file
        b = os.path.join(BACKUP, 'game', name)
        return b if which == 'before' and os.path.exists(b) else os.path.join(folder, name)

    for which in ('before', 'after'):
        for song, nb in (('can_can', 8), ('mountain_king', 4)):
            d = os.path.join(M, 'classics', song)
            lead = stem(d, f'{song}_L3_cat_flow_{nb}b.wav', which)
            mix(os.path.join(PREVIEWS, f'catfix_{song}_lead_{which}.wav'),
                [(lead, 1.0), (os.path.join(d, f'{song}_fb_L0_keys_{nb}b.wav'), 0.8), (os.path.join(d, f'{song}_L2_bass_{nb}b.wav'), 0.8), (groove, 0.85)])
            mix(os.path.join(PREVIEWS, f'catfix_{song}_catband_{which}.wav'),
                [(lead, 1.0), (stem(d, f'{song}_C_stabs_{nb}b.wav', which), 0.8), (stem(d, f'{song}_C_bass_{nb}b.wav', which), 0.8),
                 (os.path.join(d, f'{song}_C_drums_{nb}b.wav'), 0.8), (groove, 0.85)])
        d = os.path.join(S1, 'cat_band')
        lead = stem(d, 's1_C_lead_flow_4b.wav', which)
        mix(os.path.join(PREVIEWS, f'catfix_scene1_lead_{which}.wav'),
            [(lead, 1.0), (os.path.join(S1, 'style_disco', 's1_B_L0_keys_4b.wav'), 0.8), (os.path.join(S1, 'skeleton', 's1_L2_bass_4b.wav'), 0.8), (groove, 0.85)])
        mix(os.path.join(PREVIEWS, f'catfix_scene1_catband_{which}.wav'),
            [(lead, 1.0), (stem(d, 's1_C_stabs_4b.wav', which), 0.8), (stem(d, 's1_C_bass_4b.wav', which), 0.8),
             (os.path.join(d, 's1_C_drums_4b.wav'), 0.8), (groove, 0.85)])
    print('\npreviews ->', PREVIEWS)
    for f in sorted(glob.glob(os.path.join(PREVIEWS, 'catfix_*.wav'))):
        print(' ', os.path.basename(f))
