"""The cats' backing-vocal part for each tune, as a run-time meow pattern (no WAV): short notes on the
off-beat eighths, the third and the fifth of the chord in turn, between C4 and B4 (under the tune). It rests
wherever the tune itself has a note on that eighth, so the two never land together. A tune that is busy all
the way gets a held note on each half bar instead.
(The idea is from Mewgenics, whose songs each carry a MIDI with a lead and a backing-vocal track; test set 5
of make_choir_tests.py, "ours + backing vocals", is what was picked.)

Writes <project>/levels/music/patterns/harm_<tune>.json. The game plays it on the "harm" lane
(tools/music_gen/make_music_sets.py), with the same per-cat samples as every other meow pattern.

usage: python -I make_harmony_patterns.py <loops dir> <game project dir>
"""
import contextlib
import io
import json
import os
import sys

LOOPS, PROJECT = sys.argv[1], sys.argv[2]
sys.argv = [sys.argv[0], LOOPS, '__none__']
sys.path.insert(0, os.path.dirname(__file__))
with contextlib.redirect_stdout(io.StringIO()):
    import compose_classics as cc

OUT = os.path.join(PROJECT, 'levels', 'music', 'patterns')
LOW, HIGH = 60, 71
# Per tune: which cat sings the backing vocals ('auto' = the player picks one per four-bar phrase, never the
# same twice running) and how loud. Ode to Joy: on 'auto' the second phrase went to a brighter cat that stuck
# out over the tune, so it keeps the soft low cat all the way and sits 3 dB lower.
CAT = {'ode_to_joy': '01'}
GAIN_DB = {'ode_to_joy': -3.0}
for key in ('ode_to_joy', 'your_best_friend', 'mountain_king', 'can_can', 'turkish_march', 'turkish_march_b'):
    song = cc.SONGS[key]
    if key in cc.SPEED:
        song = cc.slowed(song, cc.SPEED[key])
    bars = len(song['chords']) // 2                       # the chords are written two to a bar
    busy = {st for st, _, _ in song['melody']}
    notes = []
    for h, sym in enumerate(song['chords']):
        tones, _ = cc.chord(sym)
        for k, st in enumerate((2, 6)):
            step = h * 8 + st
            if step in busy:
                continue
            m = tones[(1, 2)[k] % len(tones)]
            while m < LOW:
                m += 12
            while m > HIGH:
                m -= 12
            notes.append([step, m, 2])
    if len(notes) < 2 * bars:
        # a busy tune (eighths all the way: Mountain King, Can-Can) leaves no room on the off-beats:
        # the backing vocals hold a note on each half bar instead, the third then the fifth
        notes = []
        for h, sym in enumerate(song['chords']):
            tones, _ = cc.chord(sym)
            m = tones[(1, 2)[h % 2] % len(tones)]
            while m < LOW:
                m += 12
            while m > HIGH:
                m -= 12
            notes.append([h * 8, m, 4])
    body = {'kind': 'melody', 'bars': bars, 'cat': CAT.get(key, 'auto'), 'gain_db': GAIN_DB.get(key, 0.0), 'notes': notes}
    path = os.path.join(OUT, f'harm_{key}.json')
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(body, f, indent='\t', ensure_ascii=False)
    print(f'  harm_{key}: {bars} bars, {len(notes)} notes')
