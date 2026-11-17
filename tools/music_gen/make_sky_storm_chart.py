"""The sky level's storm charts, written to follow the doom music of make_sky_metal.py (2026-11-17):

  levels/charts/level_2_sky_0_storm.tres   one chart, swapped in once on the bar line the written fill starts on:
    the fill bar (tr_sky_into_doom): the snare roll's first two beats, then the cats' three shouts on the
    quarter-note triplets of beats 3-4;
    then the 8 bars of the doom loop, written out STORM_LOOPS times (the music loops them; a chart loop would
    replay the fill bar, so the chart is just long enough never to loop):
    bar 1  C            the doom chord, the half-time snare on 3
    bar 2  C .. Gb      the chord, the bend on 3
    bar 3  C            as bar 1
    bar 4  C Db, G G G  the chord, the step up, and the three triplet shouts
    bar 5  Ab           the 3-3-2 accents (beats 1, 2.5, 4) under the long meow
    bar 6  Ab           stop-time: the three hits
    bar 7  G            3-3-2 again, the band running
    bar 8  G            straight 8ths into the Ode (the chart's own 8th run lands here too)
Sounds: 0 kick, 1 snare. scripts/sections/sky_section.gd swaps it in (_on_change_planned, tier 1).

usage: python -I make_sky_storm_chart.py <godot project dir>
"""
import os
import sys

G = sys.argv[1]
T = 2.0 / 3.0          # a quarter-note triplet, in beats

INTO = [(0, 0), (1, 1), (2, 1), (2 + T, 1), (2 + 2 * T, 1)]
STORM = [
    (0, 0), (2, 1),
    (4, 0), (6, 1),
    (8, 0), (10, 1),
    (12, 0), (13, 0), (14, 1), (14 + T, 1), (14 + 2 * T, 1),
    (16, 0), (17.5, 0), (19, 1),
    (20, 0), (21.5, 0), (23, 1),
    (24, 0), (25.5, 0), (27, 1),
] + [(28 + e * 0.5, e % 2) for e in range(8)]


def write(name, length, notes):
    body = ', '.join('{\n"beat": %s,\n"sound": %d\n}' % (repr(round(float(b), 6)), s) for b, s in notes)
    text = ('[gd_resource type="Resource" script_class="ChartPattern" format=3]\n\n'
            '[ext_resource type="Script" path="res://scripts/chart/chart_pattern.gd" id="1_erph5"]\n\n'
            '[resource]\nscript = ExtResource("1_erph5")\n'
            f'length_beats = {float(length)}\n'
            f'notes = Array[Dictionary]([{body}])\n')
    path = os.path.join(G, 'levels', 'charts', name + '.tres')
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('wrote', path, len(notes), 'notes')


STORM_LOOPS = 6
write('level_2_sky_0_storm', 4 + 32 * STORM_LOOPS, INTO + [(4 + 32 * k + b, s) for k in range(STORM_LOOPS) for b, s in STORM])
