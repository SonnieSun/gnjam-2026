"""Level 1's note charts, written from the music: every note sits on a drum hit of the groove that is playing
there (kick or clap), on a beat or half a beat, in patterns that repeat, so the next one can be predicted.
No triplets: neither the disco theme nor The Entertainer (as the game plays it) has any.

What was there: one chart of 9 notes (levels/charts/level_1_disco_0.tres) played by EVERY phase, because the road
and the plaza had no chart of their own (their "bars" fallback is ignored when the section has a chart). Four of
its notes were on half beats that no drum plays (0.5, 14.5, 15.5 ...), under four different grooves.

The grooves (tools/music_gen/compose_disc.py RHYTHMS; beats of a 4/4 bar, 0 = the downbeat):
    half    kick 0, 2.5         clap 2          the room before 14 %
    four    kick 0, 1, 2, 3                     the room from 14 %
    club    kick 0, 0.75, 1.5, 2.5, 3, 3.5      clap 1, 3      from the house opening (The Entertainer)
    break   kick 0, 1.75, 2.5   clap 1, 3       the fever on the plaza

The files are ChartPattern resources (scripts/chart/chart_pattern.gd), the format both chart editors read and
write. Kisa's beat editor (scenes/tools/kisa/beat_editor.tscn) opens them per phase (room / road / plaza) by
these file names; its finest snap is a quarter beat and every note here is on that grid. A chart loops; a phase's
beat 0 is where the level starts it (the room: the level's first note; the road: the bar after The Entertainer's
count-in bar; the plaza: the bar the music's build comes in).

usage: python -I make_level1_charts.py <game project dir>
"""
import os
import sys

GAME = sys.argv[1]
K, S = 0, 1          # NoteData.Sound: kick, snare


def bars(*rows):
    """rows: one list of (beat in the bar, sound) per bar -> [(beat, sound)] and the length in beats."""
    notes = [(b * 4 + beat, sound) for b, row in enumerate(rows) for beat, sound in row]
    return notes, len(rows) * 4.0


def write(name, notes, length):
    path = os.path.join(GAME, 'levels', 'charts', name + '.tres')
    body = ', '.join('{\n"beat": %s,\n"sound": %d\n}' % (repr(float(b)), s) for b, s in sorted(notes))
    text = ('[gd_resource type="Resource" script_class="ChartPattern" format=3]\n\n'
            '[ext_resource type="Script" path="res://scripts/chart/chart_pattern.gd" id="1_erph5"]\n\n'
            '[resource]\nscript = ExtResource("1_erph5")\nlength_beats = %s\nnotes = Array[Dictionary]([%s])\n' % (repr(float(length)), body))
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print(f'  {name}.tres: {len(notes)} notes in {int(length / 4)} bars')


# THE ROOM (the disco theme; half-time drums, then four on the floor). Beats 0 and 2 are a drum in both (kick /
# clap, kick / kick), 1 and 3 are the four-on-the-floor kicks. Four bars, the second and fourth a little fuller.
write('level_1_disco_0', *bars(
    [(0, K), (2, S)],
    [(0, K), (2, S), (3, K)],
    [(0, K), (2, S)],
    [(0, K), (1, K), (2, S), (3, K)]))

# THE ROAD. Nothing to play in the music's two transition bars, nor in The Entertainer's first bar: that bar is the
# band's count-in, four big drum hits (the level's "预备" beat), and the road's chart starts on the bar after it:
# its beat 0 is the first fruit. (A version with notes in the transition bars was tried first; the count-in bar
# is the design.) The Entertainer over the club beat, getting denser the way the old road was meant to (every note
# a kick, beat 3 a kick and a clap):
#   4 bars   0, 3            4 bars   0, 1.5, 3            8 bars   0, 1.5, 2.5, 3
#   then two bars in turn:   0, 1.5, 2.5, 3   /   0, 1.5, 2.5, 3, 3.5
A = [(0, K), (3, S)]
B = [(0, K), (1.5, K), (3, S)]
C = [(0, K), (1.5, K), (2.5, K), (3, S)]
D = [(0, K), (1.5, K), (2.5, K), (3, S), (3.5, K)]
write('level_1_disco_0_road', *bars(*([A] * 4 + [B] * 4 + [C] * 8 + [C, D] * 24)))

# THE PLAZA (the build on the club beat, then the fever on the break beat). 0 and 2.5 are a kick in both, 1 and 3
# the clap in both.
P = [(0, K), (1, S), (2.5, K), (3, S)]
write('level_1_disco_0_plaza', *bars(P, [(0, K), (1, S), (2.5, K)], P, P))
