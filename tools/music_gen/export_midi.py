"""A MIDI file for every tune and rhythm in the game: what is played on which sixteenth, for whoever writes the
charts. Not used by the game; open them in any DAW / MIDI editor next to the level's chart.

  <out>/<tune>.mid          one per classic tune, the length of its loop, 160 BPM, 4/4. Tracks:
                              Lead      the tune (what the cats / the instrument sing)
                              Harmony   the cats' backing vocals (levels/music/patterns/harm_<tune>.json), if any
                              Chords    the chord on every half bar (a block chord)
                              Bass      the bass root, on the eighths as the bass stem plays it
                              Drums     the groove under it (channel 10): kick on the four beats, hat on the off-beats
  <out>/scene1_theme.mid    the game's own theme (level 1), 4 bars: Chords (stabs on 1, the "a" of 2 and 4: steps 0 6 12),
                            Hook A (eurobeat), Hook B (disco, 2 bars twice), Bass roots, and one drum track per groove
                            (four / half / break / club): kick, clap, hats
  <out>/README.md           the same list with bar counts and the note counts

Sources: tools/compose_classics.py (SONGS: melody + chords), tools/compose_disc.py (CHORDS, RIFF_A, RIFF_B, RHYTHMS)
and the harmony patterns. A step is a sixteenth; a tune marked half-time (SPEED) is written out as it sounds.

usage: python -I export_midi.py <loops dir> <game project dir> <out dir>
"""
import ast
import contextlib
import io
import json
import os
import struct
import sys

LOOPS, PROJECT, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
sys.argv = [sys.argv[0], LOOPS, '__none__']
sys.path.insert(0, os.path.dirname(__file__))
with contextlib.redirect_stdout(io.StringIO()):
    import compose_classics as cc
from audio import nm  # noqa: E402

os.makedirs(OUT, exist_ok=True)
PPQ = 480
STEP = PPQ // 4
BPM = 160
KICK, CLAP, HAT, OPEN_HAT = 36, 39, 42, 46


def vlq(n):
    out = [n & 0x7f]
    n >>= 7
    while n:
        out.append((n & 0x7f) | 0x80)
        n >>= 7
    return bytes(reversed(out))


def track(name, notes, channel=0):
    """notes: (step, midi, length in steps, velocity)."""
    ev = [(0, 0, b'\xff\x03' + vlq(len(name)) + name.encode('ascii'))]
    for step, midi, ln, vel in notes:
        ev.append((step * STEP, 1, bytes([0x90 | channel, midi, vel])))
        ev.append((step * STEP + max(int(ln * STEP) - 10, 20), 0, bytes([0x80 | channel, midi, 0])))
    ev.sort(key=lambda e: (e[0], e[1]))
    body, at = b'', 0
    for t, _, data in ev:
        body += vlq(t - at) + data
        at = t
    body += b'\x00\xff\x2f\x00'
    return b'MTrk' + struct.pack('>I', len(body)) + body


def write(path, bars, tracks):
    tempo = b'\x00\xff\x51\x03' + (60000000 // BPM).to_bytes(3, 'big') + b'\x00\xff\x58\x04\x04\x02\x18\x08'
    tempo += vlq(bars * 16 * STEP) + b'\xff\x2f\x00'
    data = b'MThd' + struct.pack('>IHHH', 6, 1, len(tracks) + 1, PPQ) + b'MTrk' + struct.pack('>I', len(tempo)) + tempo
    for t in tracks:
        data += t
    open(path, 'wb').write(data)


def drums(bars, kick, clap=(), hats=(), open_=()):
    notes = []
    for b in range(bars):
        notes += [(b * 16 + s, KICK, 1, 110) for s in kick] + [(b * 16 + s, CLAP, 1, 100) for s in clap]
        notes += [(b * 16 + s, HAT, 1, 70) for s in hats] + [(b * 16 + s, OPEN_HAT, 1, 80) for s in open_]
    return notes


FOUR = dict(kick=[0, 4, 8, 12], clap=[], hats=[], open_=[2, 6, 10, 14])
rows = []
USED = {'ode_to_joy': 'the sky level', 'your_best_friend': 'level 2, the washer', 'mountain_king': 'level 2, the earth',
        'can_can': 'level 2 (last part of the earth) and level 3 (the pizza)', 'turkish_march': 'level 3, the shooter',
        'turkish_march_b': 'level 3, the shooter in fever', 'can_can_a': 'level 3, the first half of the pizza',
        'entertainer': 'level 1, from the house opening on'}
for key, where in USED.items():
    song = cc.SONGS[key]
    if key in cc.SPEED:
        song = cc.slowed(song, cc.SPEED[key])
    bars = len(song['chords']) // 2
    lead = [(s, nm(p) + song.get('cat_octave', 0), ln, 100) for s, p, ln in song['melody']]
    chords, bass = [], []
    for h, sym in enumerate(song['chords']):
        tones, root = cc.chord(sym)
        chords += [(h * 8, m, 8, 70) for m in tones]
        bass += [(h * 8 + e * 2, root + 12 + (12 if e % 2 else 0), 2, 90) for e in range(4)]
    tr = [track('Lead', lead), track('Chords', chords, 1), track('Bass', bass, 2)]
    hp = os.path.join(PROJECT, 'levels', 'music', 'patterns', f'harm_{key}.json')
    n_h = 0
    if os.path.exists(hp):
        h = json.load(open(hp, encoding='utf-8'))
        harm = [(s, m, ln, 80) for s, m, ln in h['notes']]
        n_h = len(harm)
        tr.insert(1, track('Harmony', harm, 3))
    tr.append(track('Drums', drums(bars, **FOUR), 9))
    write(os.path.join(OUT, key + '.mid'), bars, tr)
    rows.append((key + '.mid', where, bars, len(lead), n_h, ' '.join(song['chords'])))
    print(f'  {key}: {bars} bars, {len(lead)} lead notes, {n_h} harmony notes')

# --- the game's own theme, read out of compose_disc.py without running it ---------------------------
tree = ast.parse(open(os.path.join(os.path.dirname(__file__), 'compose_disc.py'), encoding='utf-8').read())
const = {}
for node in tree.body:
    if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name) \
            and node.targets[0].id in ('CHORDS', 'STABS', 'RIFF_A', 'RIFF_B', 'RHYTHMS'):
        # plain data, written with dict(...) / list(range(...)): evaluated with only those names available
        const[node.targets[0].id] = eval(compile(ast.Expression(node.value), 'compose_disc', 'eval'),
                                         {'__builtins__': {}, 'dict': dict, 'list': list, 'range': range})
bars = 4
chords = [(b * 16 + s, nm(n), 2, 80) for b, (notes, _) in enumerate(const['CHORDS']) for s in const['STABS'] for n in notes]
bass = [(b * 16 + e * 2, nm(root) + 12 + (12 if e % 2 else 0), 2, 90) for b, (_, root) in enumerate(const['CHORDS']) for e in range(8)]
hook_a = [(b * 16 + s, nm(p), ln, 100) for b, row in enumerate(const['RIFF_A']) for s, p, ln in row]
hook_b = [((b + 2 * r) * 16 + s, nm(p), ln, 100) for r in range(2) for b, row in enumerate(const['RIFF_B']) for s, p, ln in row]
tr = [track('Chords (stabs)', chords, 1), track('Hook A (eurobeat)', hook_a), track('Hook B (disco)', hook_b, 4),
      track('Bass', bass, 2), track('Drums four', drums(bars, **FOUR), 9)]
for name in ('half', 'break', 'club'):
    r = const['RHYTHMS'][name]
    tr.append(track('Drums ' + name, drums(bars, r['kick'], r['clap'], r['hats'], r['open_']), 9))
write(os.path.join(OUT, 'scene1_theme.mid'), bars, tr)
print(f'  scene1_theme: {bars} bars, hook A {len(hook_a)} notes, hook B {len(hook_b)} notes')

with open(os.path.join(OUT, 'README.md'), 'w', encoding='utf-8', newline='\n') as f:
    f.write('# MIDI of every tune (for chart writing)\n\nMade by `tools/music_gen/export_midi.py`; see `docs/music_chart_handoff.md`.\n'
            'All 160 BPM, 4/4, one file = one loop. Not used by the game.\n\n'
            '| File | Used in | Bars | Lead notes | Harmony notes | Chords (one per half bar) |\n|---|---|---|---|---|---|\n')
    for r in rows:
        f.write('| %s | %s | %d | %d | %d | %s |\n' % r)
    f.write('| scene1_theme.mid | level 1 (the disco theme) | 4 | hook A %d, hook B %d | - | Ebmaj7 F7 Dm7 Gm7, one per bar |\n' % (len(hook_a), len(hook_b)))
    f.write('\nKick steps of the four grooves (a step is a sixteenth, 0 = the first beat of the bar):\n\n'
            '| Groove | Kick | Clap | Used |\n|---|---|---|---|\n'
            '| four | 0 4 8 12 | - | most of the game |\n')
    for name, used in (('half', 'quiet openings'), ('break', 'level 1 fever'), ('club', 'level 1 after the house opens')):
        r = const['RHYTHMS'][name]
        f.write('| %s | %s | %s | %s |\n' % (name, ' '.join(map(str, r['kick'])), ' '.join(map(str, r['clap'])) or '-', used))
print('midi done ->', OUT)
