# MIDI of every tune (for chart writing)

Made by `tools/music_gen/export_midi.py`; see `docs/music_chart_handoff.md`.
All 160 BPM, 4/4, one file = one loop. Not used by the game.

| File | Used in | Bars | Lead notes | Harmony notes | Chords (one per half bar) |
|---|---|---|---|---|---|
| ode_to_joy.mid | the sky level | 16 | 62 | 59 | C C G G Am Am Em Em F F C C Dm7 Dm7 G C G G G C G G Am G C C G G F C G C |
| your_best_friend.mid | level 2, the washer | 8 | 34 | 26 | Ab Ab Eb Eb Ab Ab Db Eb7 Ab Ab Bbm Eb Db Eb Ab Ab |
| mountain_king.mid | level 2, the earth | 8 | 50 | 16 | Am Am B7 Bb Am Am C G E E E E E E E E |
| can_can.mid | level 2 (last part of the earth) and level 3 (the pizza) | 8 | 48 | 16 | D7 G C D7 D7 G D7 G D7 G C D7 D7 G D7 G |
| turkish_march.mid | level 3, the shooter | 16 | 76 | 43 | Am Am Am Am E E Am Am Em Em Em Em B7 B7 Em Em Am Am Am Am E E Am Am E E Dm Dm E7 E7 Am Am |
| turkish_march_b.mid | level 3, the shooter in fever | 8 | 29 | 32 | A A A A D D E E A A A A E E A A |
| scene1_theme.mid | level 1 (the disco theme) | 4 | hook A 25, hook B 36 | - | Ebmaj7 F7 Dm7 Gm7, one per bar |

Kick steps of the four grooves (a step is a sixteenth, 0 = the first beat of the bar):

| Groove | Kick | Clap | Used |
|---|---|---|---|
| four | 0 4 8 12 | - | most of the game |
| half | 0 10 | 8 | quiet openings |
| break | 0 7 10 | 4 12 | level 1 fever |
| club | 0 3 6 10 12 14 | 4 12 | level 1 after the house opens |
