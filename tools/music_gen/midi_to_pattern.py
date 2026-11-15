"""A MIDI file -> a cat melody pattern the game plays (levels/music/patterns/<name>.json, kind "melody").

Write the tune in any MIDI editor, export a .mid, run this, and the pattern shows up on the Tab panel's
Meow page, ready to add to a lane. Needs nothing but Python (no samples, no numpy).

What it does with the file:
  - takes one track (the one with the most notes, or --track N),
  - with --min-pitch N, drops every note below MIDI pitch N first (a piano file has the left hand in
    the same track: 60 = middle C usually separates it from the tune),
  - keeps one note at a time: where several start together, the highest,
  - snaps every note to the 16th-note grid (the game's step),
  - moves the tune by whole octaves so it sits in the cats' range (A3-E6); single notes still outside
    are folded in by an octave,
  - a note lasts until its note-off or the next note, whichever comes first.

usage: python midi_to_pattern.py <file.mid> [--name NAME] [--track N] [--min-pitch N]
                                 [--transpose SEMITONES] [--bars N] [--cat ID|auto] [--out DIR]
"""
import argparse
import json
import math
import os
import struct

LOW, HIGH = 57, 88          # the piano roll's range in the game (meow_grid.gd)


def read_midi(path):
    """-> (ticks per quarter note, [track: [(tick, midi, length in ticks)]])"""
    data = open(path, 'rb').read()
    assert data[:4] == b'MThd', 'not a MIDI file'
    _, ntracks, division = struct.unpack('>HHH', data[8:14])
    assert not division & 0x8000, 'SMPTE time division is not supported'
    pos, tracks = 14, []
    for _ in range(ntracks):
        assert data[pos:pos + 4] == b'MTrk'
        size = struct.unpack('>I', data[pos + 4:pos + 8])[0]
        body, pos = data[pos + 8:pos + 8 + size], pos + 8 + size
        i, tick, status, on, notes = 0, 0, 0, {}, []

        def vlq():
            nonlocal i
            v = 0
            while True:
                b = body[i]
                i += 1
                v = (v << 7) | (b & 0x7F)
                if not b & 0x80:
                    return v
        while i < len(body):
            tick += vlq()
            b = body[i]
            if b & 0x80:
                status = b
                i += 1
            kind = status & 0xF0
            if status == 0xFF:                      # meta event
                i += 1
                size = vlq()                        # (not i += vlq(): vlq moves i itself)
                i += size
            elif status in (0xF0, 0xF7):            # sysex
                size = vlq()
                i += size
            elif kind in (0x80, 0x90):
                key, vel = body[i], body[i + 1]
                i += 2
                if kind == 0x90 and vel > 0:
                    on[key] = tick
                elif key in on:
                    start = on.pop(key)
                    notes.append((start, key, max(1, tick - start)))
            elif kind in (0xC0, 0xD0):
                i += 1
            else:
                i += 2
        tracks.append(sorted(notes))
    return division, tracks


def to_melody(notes, division, transpose=0, min_pitch=0):
    step = division / 4.0
    by_step = {}
    for tick, key, length in notes:
        if key < min_pitch:
            continue
        s = int(round(tick / step))
        if s not in by_step or key > by_step[s][0]:
            by_step[s] = (key, max(1, int(round(length / step))))
    starts = sorted(by_step)
    if not starts:
        return []
    first = starts[0] - starts[0] % 16               # keep the tune's place in its first bar
    keys = sorted(k for k, _ in by_step.values())
    shift = transpose
    middle = keys[len(keys) // 2] + shift
    while middle > 78:
        shift -= 12
        middle -= 12
    while middle < 66:
        shift += 12
        middle += 12
    out = []
    for n, s in enumerate(starts):
        key, length = by_step[s]
        key += shift
        while key > HIGH:
            key -= 12
        while key < LOW:
            key += 12
        if n + 1 < len(starts):
            length = min(length, starts[n + 1] - s)
        out.append([s - first, key, max(1, length)])
    return out


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('midi')
    ap.add_argument('--name')
    ap.add_argument('--track', type=int)
    ap.add_argument('--transpose', type=int, default=0)
    ap.add_argument('--min-pitch', type=int, default=0, help='drop notes below this MIDI pitch (the left hand)')
    ap.add_argument('--bars', type=int, help='keep only the first N bars')
    ap.add_argument('--cat', default='auto')
    ap.add_argument('--out', default=os.path.join(os.path.dirname(__file__), '..', '..', 'levels', 'music', 'patterns'))
    a = ap.parse_args()
    division, tracks = read_midi(a.midi)
    for i, t in enumerate(tracks):
        print(f'track {i}: {len(t)} notes')
    k = a.track if a.track is not None else max(range(len(tracks)), key=lambda i: len(tracks[i]))
    notes = to_melody(tracks[k], division, a.transpose, a.min_pitch)
    assert notes, f'track {k} has no notes'
    bars = int(math.ceil((notes[-1][0] + notes[-1][2]) / 16))
    if a.bars:
        bars = a.bars
        notes = [[s, m, min(ln, bars * 16 - s)] for s, m, ln in notes if s < bars * 16]
    name = a.name or os.path.splitext(os.path.basename(a.midi))[0].lower().replace(' ', '_')
    os.makedirs(a.out, exist_ok=True)
    path = os.path.join(a.out, name + '.json')
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump({'kind': 'melody', 'bars': bars, 'cat': a.cat, 'gain_db': 0.0, 'notes': notes}, f, indent='\t')
    print(f'track {k} -> {os.path.normpath(path)}: {len(notes)} notes, {bars} bars, '
          f'{min(n[1] for n in notes)}-{max(n[1] for n in notes)}')
