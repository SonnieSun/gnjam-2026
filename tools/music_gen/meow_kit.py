"""Turns a folder of cat recordings into a meow kit: every meow cut out, its pitch measured along
its length, and the clean ones (steady enough to tune, long enough to sing) written as one-shots
named by their note, so they can be played like an instrument.

usage: python -I meow_kit.py <out dir> <wav or folder> [...]
prints every meow found; writes <out dir>/meow_NN_<note>_<len>ms.wav and kit.txt
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import SR, read_wav, write_wav  # noqa: E402
from slicer import detect_midi, slices  # noqa: E402

NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']


def note_name(m):
    m = int(round(m))
    return f'{NAMES[m % 12]}{m // 12 - 1}'


def pitch_track(audio, win=0.06, hop=0.03):
    """Pitch (MIDI) every 30 ms through the meow, None where there is no clear note."""
    w, h = int(win * SR), int(hop * SR)
    out = []
    for a in range(0, len(audio) - w, h):
        seg = audio[a: a + w]
        # detect_midi looks at the middle of what it is given; give it a padded window
        m = detect_midi(np.concatenate([seg, seg, seg]), fmin=150, fmax=1500)
        out.append(m)
    return out


def describe(sl):
    track = [m for m in pitch_track(sl['audio']) if m is not None]
    voiced = len(track) / max(1, len(pitch_track(sl['audio'])))
    if not track:
        return None, 0.0, 99.0
    core = np.array(track[len(track) // 4: max(len(track) // 4 + 1, 3 * len(track) // 4)])
    return float(np.median(core)), voiced, float(np.std(core))


if __name__ == '__main__':
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    paths = []
    for p in sys.argv[2:]:
        paths += [os.path.join(p, f) for f in sorted(os.listdir(p)) if f.lower().endswith('.wav')] if os.path.isdir(p) else [p]
    rows = []
    for p in paths:
        x = read_wav(p)
        for sl in slices(x, min_len=0.2, max_len=1.2, gate_db=-28):
            midi, voiced, wobble = describe(sl)
            length = (sl['end'] - sl['start']) / SR
            rows.append(dict(src=os.path.basename(p), start=sl['start'] / SR, length=length, midi=midi,
                             voiced=voiced, wobble=wobble, audio=sl['audio'], level=sl['level']))
    # clean = mostly voiced, pitch steady within about a semitone and a half, 0.25-1.0 s long
    for r in rows:
        r['clean'] = r['midi'] is not None and r['voiced'] > 0.6 and r['wobble'] < 1.5 and 0.25 <= r['length'] <= 1.0
    keep = sorted([r for r in rows if r['clean']], key=lambda r: r['midi'])
    lines = []
    for k, r in enumerate(keep):
        a = r['audio'] / (np.max(np.abs(r['audio'])) + 1e-9) * 0.9
        name = f"meow_{k:02d}_{note_name(r['midi']).replace('#', 's')}_{int(r['length'] * 1000)}ms.wav"
        write_wav(os.path.join(out_dir, name), a, peak=0.9)
        lines.append(f"{name}\tmidi {r['midi']:.2f}\tfrom {r['src']} at {r['start']:.2f}s")
    with open(os.path.join(out_dir, 'kit.txt'), 'w', encoding='utf-8') as f:
        f.write('meow kit: one-shot, note measured at the steady middle (midi), source recording\n')
        f.write('all sources CC0 unless listed in ../CREDITS of their folder\n\n' + '\n'.join(lines) + '\n')
    sys.stdout.reconfigure(encoding='utf-8')
    for r in rows:
        m = f"{r['midi']:.1f} {note_name(r['midi']):4s}" if r['midi'] is not None else '   -     '
        print(f"{'KEEP' if r['clean'] else '    '}  {r['src'][8:48]:40s} {r['start']:6.2f}s  len {r['length']:.2f}  midi {m}  voiced {r['voiced']:.2f}  wobble {r['wobble']:.2f}")
    print(f'{len(keep)} clean meows of {len(rows)} -> {out_dir}')
