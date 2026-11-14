"""Renders small clips of the meow candidates for the picker page: the meow as recorded, the meow
singing four long notes (G4 B4 D5 G5, 'iii' held), and eight quick notes (the short-note use).
Mono 22 kHz to keep the page light. Writes <out>/clips/*.wav and <out>/candidates.json.

usage: python -I miao_picker.py <samples dir> <out dir>
"""
import json
import os
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio import SR, nm, read_wav  # noqa: E402
from psola import sing_miao  # noqa: E402
from slicer import slices  # noqa: E402

S, OUT = sys.argv[1], sys.argv[2]
C = [  # (label, file, start s, licence)
    ('英短讨饭 A', 'commons_animals/Weibliche Britisch Kurzhaar will Futter C1277 MIAUEN.wav', 11.45, 'CC BY 4.0'),
    ('英短讨饭 B', 'commons_animals/Weibliche Britisch Kurzhaar will Futter C1277 MIAUEN.wav', 7.59, 'CC BY 4.0'),
    ('英短讨饭 C', 'commons_animals/Weibliche Britisch Kurzhaar will Futter C1277 MIAUEN.wav', 5.14, 'CC BY 4.0'),
    ('Meow cat 4', 'bigsoundbank_cats/ANMLCat_Meow cat 4 (ID 1892)_BigSoundBank.com.wav', 0.05, 'CC0'),
    ('Meow cat 5', 'bigsoundbank_cats/ANMLCat_Meow cat 5 (ID 1893)_BigSoundBank.com.wav', 0.41, 'CC0'),
    ('Meow cat 13', 'bigsoundbank_cats/ANMLCat_Meow cat 13 (ID 1901)_BigSoundBank.com.wav', 4.03, 'CC0'),
    ('Meow cat 12', 'bigsoundbank_cats/ANMLCat_Meow cat 12 (ID 1900)_BigSoundBank.com.wav', 0.02, 'CC0'),
    ('Meow cat 2', 'bigsoundbank_cats/ANMLCat_Meow cat 2 (ID 1890)_BigSoundBank.com.wav', 0.08, 'CC0'),
    ('Meow cat 3', 'bigsoundbank_cats/ANMLCat_Meow cat 3 (ID 1891)_BigSoundBank.com.wav', 0.05, 'CC0'),
    ('小喵 Small mewing', 'bigsoundbank_cats/ANMLCat_Small mewing of a cat (ID 0098)_BigSoundBank.com.wav', 1.09, 'CC0'),
    ('3 周小奶猫', 'bigsoundbank_cats/ANMLCat_Mewing kitten 3 weeks (ID 0390)_BigSoundBank.com.wav', 2.46, 'CC0'),
    ('Little meow 8', 'bigsoundbank_cats/ANMLCat_Little meow of a cat 8 (ID 1478)_BigSoundBank.com.wav', 0.08, 'CC0'),
    ('自己录的 A', 'my_meows/user_meows.wav', 0.05, '自己录'),
    ('自己录的 B', 'my_meows/user_meows.wav', 1.78, '自己录'),
    ('自己录的 C', 'my_meows/user_meows_2.wav', 0.80, '自己录'),
]


def trim_tail(sl, floor_db=-26):
    """Drop the quiet tail after a meow (breath, room noise): keep up to the last 10 ms that is within
    `floor_db` of the loudest, plus 30 ms, faded out. Also trims a quiet start."""
    m = np.abs(sl).mean(axis=1) if sl.ndim == 2 else np.abs(sl)
    w = int(0.01 * SR)
    env = np.sqrt(np.convolve(m ** 2, np.ones(w) / w, mode='same'))
    keep = np.nonzero(env > env.max() * 10 ** (floor_db / 20))[0]
    end = min(len(sl), keep[-1] + int(0.03 * SR)) if len(keep) else len(sl)
    # and a quiet start (a hummed 'm', a breath) would land the meow late on its beat: start 15 ms
    # before it reaches -18 dB of its peak
    loud = np.nonzero(env > env.max() * 10 ** (-18 / 20))[0]
    start = max(0, loud[0] - int(0.015 * SR)) if len(loud) else 0
    out = sl[start:end].copy()
    g = min(int(0.005 * SR), len(out) // 4)
    out[:g] *= (np.linspace(0, 1, g)[:, None] if out.ndim == 2 else np.linspace(0, 1, g))
    f = min(int(0.02 * SR), len(out) // 4)
    out[-f:] *= (np.linspace(1, 0, f)[:, None] if out.ndim == 2 else np.linspace(1, 0, f))
    return out


def save(path, mono):
    y = mono[::2]                                            # 44.1 -> 22.05 kHz (meows sit below 10 kHz)
    y = y / (np.max(np.abs(y)) + 1e-9) * 0.89
    with wave.open(path, 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR // 2)
        f.writeframes((np.clip(y, -1, 1) * 32767).astype('<i2').tobytes())


meta = []
for i, (label, f, start, lic) in enumerate(C, 1):
    x = read_wav(os.path.join(S, f))
    sl = min(slices(x, min_len=0.12, max_len=2.0, gate_db=-30), key=lambda s: abs(s['start'] / SR - start))['audio']
    sl = trim_tail(sl)
    sl = sl / np.max(np.abs(sl))
    from audio import highpass
    sl = highpass(sl, 100)
    save(os.path.join(OUT, 'clips', f'm{i:02d}_orig.wav'), sl.mean(axis=1))
    long_ = np.concatenate([np.concatenate([sing_miao(sl, nm(m), 0.5), np.zeros(int(0.03 * SR))]) for m in ('G4', 'B4', 'D5', 'G5')])
    save(os.path.join(OUT, 'clips', f'm{i:02d}_long.wav'), long_)
    quick = np.concatenate([np.concatenate([sing_miao(sl, nm(m), 0.15, keep=0.3), np.zeros(int(0.04 * SR))])
                            for m in ('G4', 'A4', 'B4', 'D5', 'B4', 'D5', 'E5', 'G5')])
    save(os.path.join(OUT, 'clips', f'm{i:02d}_quick.wav'), quick)
    meta.append(dict(id=i, label=label, source=os.path.basename(f), start=start, licence=lic, length=round(len(sl) / SR, 2)))
    print(i, label, 'ok')
json.dump(meta, open(os.path.join(OUT, 'candidates.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
