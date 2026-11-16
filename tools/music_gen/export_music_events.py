"""What is played on which sixteenth, as small JSON files the game reads (GDScript has no MIDI reader).
The `Music` autoload emits `drum_kick` / `drum_clap` / `drum_hat` / `lead_note` from them, in time with
what is playing (scripts/music/music_events.gd; docs/music_manager.md, "画面跟着音乐的信号").

  <project>/levels/music/events/grooves.json     the drum patterns of the `beat` lane, one bar each:
                                                 {"four": {"kick": [0, 4, 8, 12], "clap": [], "hat": [], "open_hat": [...]}, ...}
  <project>/levels/music/events/<tune>.json      one per classic tune (the folder name under assets/audio/music/classics/):
                                                 {"bars": 16, "cat_octave": 0, "notes": [[step, midi, length], ...]}

A step is a sixteenth of a 4/4 bar. A tune marked half-time (SPEED) is written out as it sounds, like the MIDI in
docs/music_midi/. `midi` is the pitch the instrument plays; the cats sing it `cat_octave` semitones away.

Needs only Python (no samples, no numpy): the data is read out of compose_classics.py (SONGS, SPEED) and
compose_disc.py (RHYTHMS) without running them.

usage: python -I export_music_events.py <game project dir>
"""
import ast
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = sys.argv[1]
OUT = os.path.join(PROJECT, 'levels', 'music', 'events')
os.makedirs(OUT, exist_ok=True)

PC = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def nm(name):
    """'C4' -> 60, 'F#5' -> 78, 'Bb3' -> 58 (the same as audio.nm)."""
    m = re.fullmatch(r'([A-G])([#b]?)(-?\d+)', name)
    return PC[m.group(1)] + {'#': 1, 'b': -1, '': 0}[m.group(2)] + 12 * (int(m.group(3)) + 1)


def dump(path, obj):
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(obj, f, separators=(',', ':'))
        f.write('\n')


# --- the grooves: compose_disc.py's RHYTHMS, plus the plain four-on-the-floor one --------------------
tree = ast.parse(open(os.path.join(HERE, 'compose_disc.py'), encoding='utf-8').read())
rhythms = {}
for node in tree.body:
    if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name) \
            and node.targets[0].id == 'RHYTHMS':
        rhythms = eval(compile(ast.Expression(node.value), 'compose_disc', 'eval'),
                       {'__builtins__': {}, 'dict': dict, 'list': list, 'range': range})
# layer_groove(): the kick is the player's, the loop itself has an open hat on every off-beat
grooves = {'four': dict(kick=[0, 4, 8, 12], clap=[], hat=[], open_hat=[2, 6, 10, 14])}
for name, r in rhythms.items():
    grooves[name] = dict(kick=r['kick'], clap=r['clap'], hat=r['hats'], open_hat=r['open_'])
dump(os.path.join(OUT, 'grooves.json'), grooves)
print('grooves:', ', '.join(grooves))

# --- the tunes: compose_classics.py's SONGS, read without importing it (it loads the samples) --------
tree = ast.parse(open(os.path.join(HERE, 'compose_classics.py'), encoding='utf-8').read())
ns = {'nm': nm}
started = False
for node in tree.body:
    if isinstance(node, ast.FunctionDef) and node.name in ('tune', 'slowed'):
        started = True
    elif not (started and isinstance(node, ast.Assign) and len(node.targets) == 1):
        continue
    else:
        t = node.targets[0]
        name = t.id if isinstance(t, ast.Name) else (t.value.id if isinstance(t, ast.Subscript) and isinstance(t.value, ast.Name) else '')
        if not re.fullmatch(r'_?[A-Z][A-Z0-9_]*', name):
            continue
    try:
        exec(compile(ast.Module([node], []), 'compose_classics', 'exec'), ns)
    except Exception as e:  # a constant that needs the samples: not one the songs are written with
        print('  skipped line %d (%s)' % (node.lineno, e))

for key, song in ns['SONGS'].items():
    if 'melody' not in song or 'chords' not in song:
        continue
    k = ns.get('SPEED', {}).get(key, 1)
    if k != 1:
        song = ns['slowed'](song, k)
    bars = len(song['chords']) // 2
    notes = sorted([int(s), nm(p), int(ln)] for s, p, ln in song['melody'])
    if notes and notes[-1][0] >= bars * 16:
        print('  %s: a note starts after the loop ends, left as written' % key)
    dump(os.path.join(OUT, key + '.json'), {'bars': bars, 'cat_octave': int(song.get('cat_octave', 0)), 'notes': notes})
    print('  %s: %d bars, %d notes' % (key, bars, len(notes)))
print('events done ->', OUT)
