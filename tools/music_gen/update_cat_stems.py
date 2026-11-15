"""Copies only the re-rendered cat stems (flow leads, cat chords, cat bass) from loops/ into deliver/
and into the Godot project, over the files that are already there. Unlike package_for_godot.py it
deletes nothing and leaves every .import file alone, so it is safe to run on a project in use.

Each file gets what package_for_godot.py gives it: a 'smpl' chunk looping the whole file and the
-4 dB trim on the cat bass. A file whose length differs from the one in the project is refused (the
game plays the stems in sync, so a length change would break it).

usage: python -I update_cat_stems.py <loops dir> <deliver dir> <godot project dir>
"""
import glob
import os
import shutil
import struct
import sys
import wave

import numpy as np

L, D, G = sys.argv[1], sys.argv[2], sys.argv[3]
M = os.path.join(G, 'assets', 'audio', 'music')
PARTS = ('_L3_cat_flow_', '_C_stabs_', '_C_bass_')
TRIM_DB = {'_C_bass_': -4.0}                                   # as in package_for_godot.py


def add_loop(src, dst):
    """Copy a 16-bit PCM WAV, trimmed if it is a bass, adding a 'smpl' chunk that loops the whole file."""
    data = open(src, 'rb').read()
    assert data[:4] == b'RIFF' and data[8:12] == b'WAVE', src
    pos, chunks = 12, []
    channels = bits = None
    while pos + 8 <= len(data):
        cid, size = data[pos:pos + 4], struct.unpack('<I', data[pos + 4:pos + 8])[0]
        body = data[pos + 8: pos + 8 + size]
        if cid == b'fmt ':
            channels, bits = struct.unpack('<H', body[2:4])[0], struct.unpack('<H', body[14:16])[0]
        if cid == b'data':
            assert bits == 16, src
            db = sum(v for k, v in TRIM_DB.items() if k in os.path.basename(src))
            if db:
                pcm = np.frombuffer(body, dtype='<i2').astype(np.float64) * 10 ** (db / 20)
                body = np.clip(np.round(pcm), -32768, 32767).astype('<i2').tobytes()
        if cid != b'smpl':
            chunks.append((cid, body))
        pos += 8 + size + (size & 1)
    frames = len(dict(chunks)[b'data']) // (channels * bits // 8)
    rate = struct.unpack('<I', dict(chunks)[b'fmt '][4:8])[0]
    smpl = struct.pack('<9I', 0, 0, int(1e9 / rate), 60, 0, 0, 0, 1, 0) + struct.pack('<6I', 0, 0, 0, frames, 0, 0)
    chunks.append((b'smpl', smpl))
    out = b''.join(c + struct.pack('<I', len(b)) + b + (b'\0' if len(b) & 1 else b'') for c, b in chunks)
    open(dst, 'wb').write(b'RIFF' + struct.pack('<I', 4 + len(out)) + b'WAVE' + out)


def frames(path):
    with wave.open(path) as w:
        return w.getnframes(), w.getframerate()


jobs = []                                                      # (loops file, deliver file, project file)
for f in sorted(glob.glob(os.path.join(L, 'classics', '*b.wav'))):
    name = os.path.basename(f)
    if any(p in name for p in PARTS):
        song = name[: name.index(next(p for p in PARTS if p in name))]
        jobs.append((f, os.path.join(D, 'classics', song, name), os.path.join(M, 'classics', song, name)))
for part in ('C_lead_flow', 'C_stabs', 'C_bass'):
    f = os.path.join(L, 's1_disc', f's1_disc_{part}_4b.wav')
    name = f's1_{part}_4b.wav'
    jobs.append((f, os.path.join(D, 'scene1', 'cat_band', name), os.path.join(M, 'scene1', 'cat_band', name)))

for src, _, dst in jobs:                                       # check everything before writing anything
    assert os.path.exists(dst), f'not in the project: {dst}'
    assert frames(src) == frames(dst), f'length changed: {src} {frames(src)} vs {dst} {frames(dst)}'
for src, deliver, dst in jobs:
    if os.path.isdir(os.path.dirname(deliver)):
        shutil.copy(src, deliver)
    add_loop(src, dst)
    print(os.path.relpath(dst, G).replace('\\', '/'), frames(dst)[0])
print(len(jobs), 'stems ->', G)
