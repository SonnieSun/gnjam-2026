"""Note charts that play a tune's own rhythm: one note on every note of the melody, read from the small JSON files
the game also uses for its music signals (levels/music/events/<tune>.json, written by export_music_events.py).
The chart is as long as the tune's loop, and the level starts it on the beat the tune starts on, so the player
taps the melody.

  level_2_sky_0_ode    the sky level from the moment it turns bright: Ode to Joy, 16 bars, 62 notes
                               (quarters, the dotted figure at the end of each line, two bars with a pair of eighths)

The files are ChartPattern resources (scripts/chart/chart_pattern.gd), the format both chart editors read and write.
Kick on beats 1 and 3 of the bar, snare on everything else (only the sound of the player's hit; the judge does not care).

usage: python -I make_tune_charts.py <game project dir>
"""
import json
import os
import sys

GAME = sys.argv[1]
K, S = 0, 1          # NoteData.Sound: kick, snare

# chart file name (levels/charts/<name>.tres) -> tune (levels/music/events/<tune>.json)
CHARTS = {'level_2_sky_0_ode': 'ode_to_joy'}


def write(name, notes, length):
    path = os.path.join(GAME, 'levels', 'charts', name + '.tres')
    body = ', '.join('{\n"beat": %s,\n"sound": %d\n}' % (repr(float(b)), s) for b, s in sorted(notes))
    text = ('[gd_resource type="Resource" script_class="ChartPattern" format=3]\n\n'
            '[ext_resource type="Script" path="res://scripts/chart/chart_pattern.gd" id="1_erph5"]\n\n'
            '[resource]\nscript = ExtResource("1_erph5")\nlength_beats = %s\nnotes = Array[Dictionary]([%s])\n' % (repr(float(length)), body))
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print(f'  {name}.tres: {len(notes)} notes in {int(length / 4)} bars')


for name, tune in CHARTS.items():
    song = json.load(open(os.path.join(GAME, 'levels', 'music', 'events', tune + '.json'), encoding='utf-8'))
    notes = []
    for step, _midi, _length in song['notes']:
        beat = step / 4.0
        notes.append((beat, K if beat % 4 in (0.0, 2.0) else S))
    write(name, notes, song['bars'] * 4)
