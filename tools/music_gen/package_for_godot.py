"""Copies the finished audio into the Godot project, laid out for the music manager:

  assets/audio/music/scene1/<group>/*.wav     scene 1 loops (skeleton, styles, cat band, ...)
  assets/audio/music/classics/<song>/*.wav    each classic's stems
  assets/audio/sfx/*.wav                      one-shots
  assets/audio/meows/*.wav                    the roster's meows (one-shot use)
  (assets/audio/README.md, what every file is, is kept by hand in the project)

Every music loop gets a RIFF 'smpl' chunk with one forward loop over the whole file, so Godot's
WAV importer (loop mode "Detect From WAV", the default) imports it already looping. One-shots
get none. Listening previews and alternates nobody uses are left out to keep the repo light.

A 120 BPM render of scene 1 (CAT_BPM=120 python -I compose_disc.py <samples> <loops_120>) can be given as
a third argument: the stems listed in STEMS_120 go to assets/audio/music/scene1_120/ as s120_*.wav.

usage: python -I package_for_godot.py <deliver dir> <godot project dir> [<120 BPM loops dir>/s1_disc]
"""
import glob
import os
import shutil
import struct
import sys

D, G = sys.argv[1], sys.argv[2]
A = os.path.join(G, 'assets', 'audio')
SKIP = ('_L3_square_', '_L3_cat_classic_', 'ent_A_L3_lead')       # alternates not shipped
# Level trims applied while copying (dB by file name part). The bass stems were rendered about 14 dB
# above the chords, which is bass-heavy when every stem plays at full level in the game.
TRIM_DB = {'_L2_bass_': -4.0, '_C_bass_': -4.0}
# the 120 BPM stems the game uses (Kisa's disco level): the disco and future bass styles, the club and
# half-time rhythms, the cat band and two event tracks
STEMS_120 = ('L1_groove', 'L2_bass', 'B_L0_keys', 'B_L3_hook', 'B_L4_peak', 'fb_L0_keys', 'fb_L3_hook', 'fb_L4_peak',
             'Rclub_L1_groove', 'Rclub_L2_bass', 'Rhalf_L1_groove', 'C_drums', 'C_stabs', 'C_bass', 'C_lead',
             'X_meow', 'X_seal')


def add_loop(src, dst):
    """Copy a PCM WAV, adding a 'smpl' chunk that loops the whole file."""
    data = open(src, 'rb').read()
    assert data[:4] == b'RIFF' and data[8:12] == b'WAVE', src
    pos, chunks = 12, []
    channels = bits = None
    while pos + 8 <= len(data):
        cid, size = data[pos:pos + 4], struct.unpack('<I', data[pos + 4:pos + 8])[0]
        body = data[pos + 8: pos + 8 + size]
        if cid == b'fmt ':
            channels, bits = struct.unpack('<H', body[2:4])[0], struct.unpack('<H', body[14:16])[0]
        if cid == b'data' and bits == 16:
            db = sum(v for k, v in TRIM_DB.items() if k in os.path.basename(src))
            if db:
                import numpy as np
                pcm = np.frombuffer(body, dtype='<i2').astype(np.float64) * 10 ** (db / 20)
                body = np.clip(np.round(pcm), -32768, 32767).astype('<i2').tobytes()
        if cid != b'smpl':
            chunks.append((cid, body))
        pos += 8 + size + (size & 1)
    frames = len(dict(chunks)[b'data']) // (channels * bits // 8)
    rate = struct.unpack('<I', dict(chunks)[b'fmt '][4:8])[0]
    smpl = struct.pack('<9I', 0, 0, int(1e9 / rate), 60, 0, 0, 0, 1, 0) + struct.pack('<6I', 0, 0, 0, frames, 0, 0)   # Godot reads the end as exclusive: the whole file
    chunks.append((b'smpl', smpl))
    out = b''.join(c + struct.pack('<I', len(b)) + b + (b'\0' if len(b) & 1 else b'') for c, b in chunks)
    open(dst, 'wb').write(b'RIFF' + struct.pack('<I', 4 + len(out)) + b'WAVE' + out)


def copy_tree(src_dir, dst_dir, loop):
    n = 0
    os.makedirs(dst_dir, exist_ok=True)
    for f in sorted(glob.glob(os.path.join(src_dir, '*.wav'))):
        if any(s in os.path.basename(f) for s in SKIP):
            continue
        dst = os.path.join(dst_dir, os.path.basename(f))
        add_loop(f, dst) if loop else shutil.copy(f, dst)
        n += 1
    return n


if os.path.isdir(A):
    for sub in ('music', 'sfx', 'meows'):
        p = os.path.join(A, sub)
        if os.path.isdir(p):
            for f in glob.glob(os.path.join(p, '**', '*.wav'), recursive=True):
                os.remove(f)                      # stale renders out; their .import files go too
                if os.path.exists(f + '.import'):
                    os.remove(f + '.import')
n = 0
for group in sorted(os.listdir(os.path.join(D, 'scene1'))):
    n += copy_tree(os.path.join(D, 'scene1', group), os.path.join(A, 'music', 'scene1', group), loop=True)
for song in sorted(os.listdir(os.path.join(D, 'classics'))):
    n += copy_tree(os.path.join(D, 'classics', song), os.path.join(A, 'music', 'classics', song), loop=True)
if len(sys.argv) > 3:
    os.makedirs(os.path.join(A, 'music', 'scene1_120'), exist_ok=True)
    for k in STEMS_120:
        add_loop(os.path.join(sys.argv[3], f's1_disc_{k}_4b.wav'), os.path.join(A, 'music', 'scene1_120', f's120_{k}_4b.wav'))
        n += 1
n += copy_tree(os.path.join(D, 'sfx'), os.path.join(A, 'sfx'), loop=False)
n += copy_tree(os.path.join(D, 'meows'), os.path.join(A, 'meows'), loop=False)
size = sum(os.path.getsize(f) for f in glob.glob(os.path.join(A, '**', '*.wav'), recursive=True))
print(f'{n} files, {size / 1e6:.0f} MB -> {A}')
