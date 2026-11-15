# Judgement artwork

The approved no-white-backing glitter design is packaged as four transparent PNG wordmarks in `assets/ui/judgements`. These are display artwork, not an installable font. The HUD uses `ui/judgement_widget.tscn`, centered at the existing top judgment position.

PERFECT / GREAT / GOOD / MISS have respective width limits of 280 / 232 / 196 / 160 pixels at the 960×720 base viewport. Pink / orange / yellow / warning red and the approved decoration hierarchy are retained. Existing score/combo components and scoring rules are untouched.

Each result scales from 74% to 108% over 0.10 seconds, settling to 100% over another 0.14 seconds. The pivot is the wordmark center. A local, decaying 1.8-pixel vibration lasts 0.20 seconds; the camera and EARLY/LATE text stay stable. There is no flashing or animated glitter. After 0.7 seconds the result disappears by a hard visibility change. A newer result cancels the previous animation and restarts from a clean transform and timer. Reset and diagnostic LOOK text cancel the animation and clear the art.

The transparent source was generated from the approved black-sheet design, then sliced and padded for integration. No runtime black rectangle is used. Textures have antialiased transparent edges.

Run `godot --headless --path <project> --script res://tools/test_judgement_widget.gd` for mapping, lifetime, replacement and reset tests. A graphics run also writes actual game screenshots into `docs/judgements`.
