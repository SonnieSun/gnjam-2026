# SCORE / COMBO HUD components

Only the top-left score and top-right live combo use `ui/score_combo_widget.tscn` and `scripts/ui/score_combo_widget.gd`. Judgment, result text, combo milestone pop-up, menu and other UI keep their existing rendering.

Current artwork uses the latest approved jelly faces and layered dark/color rims. Assets live in `assets/ui/score_combo/jelly/`; `jelly_palette.gdshader` preserves smooth baked highlights, shades and dark rims while selecting the six colors. No glitter shader is attached to the widgets. The previous glitter assets remain unused.

The tightly joined source digit specimen is deskewed for extraction and restored to its original italic angle. Shared rims are rebuilt into complete antialiased glyphs so arbitrary values do not show clipped neighboring digits. The bitmap font uses proportional advances with 9 source pixels of rim overlap, matching the compact specimen instead of padded monospace cells; 1 is narrower than 0. Both SCORE and COMBO now use size 84 digits above their titles. SCORE has a wider 340-pixel layout box so normal five-digit scores match the combo digit size. Very long numeric values shrink only as needed to remain within their widget. The corner star remains attached to the combo number's right edge. Values have no zero padding. SCORE starts at 0 in pale yellow; COMBO is shown from 1 and hidden at 0. Color selection recalculates from the current value on restart and combo breaks.

| Stage | Score | Combo |
| --- | --- | --- |
| Pale yellow | 0–1999 | 1–9 |
| Yellow | 2000–3999 | 10–19 |
| Orange | 4000–5999 | 20–29 |
| Pink | 6000–7999 | 30–39 |
| Red | 8000–9999 | 40–49 |
| Rainbow | >=10000 | >=50 |

`HUD.set_stats` updates the numeric text and palette synchronously from the existing Judge `stats_changed` signal. On a rise to a higher color stage only, the component's Visual wrapper scales to 1.38 and moves up 10 logical pixels in 0.09 seconds, then elastically returns in 0.32 seconds. Numeric values and palettes do not tween or wait for that feedback. Ordinary within-stage updates and increases beyond the rainbow cap do not retrigger the jump. Resetting to zero or dropping a stage cancels feedback and restores the wrapper immediately. A rapid new stage rise restarts one clean jump. Each component owns its feedback and material independently. Left/right pivots keep the screen edges stable. Existing unrelated game effects are not changed.

Validation: `godot --headless --path <project> --script res://tools/test_score_combo_widget.gd`. Tests every requested score/combination value, threshold edges, independent palettes, very large values, palette reset and actual Judge-to-HUD signal updates. Run with a graphics backend to write six scene screenshots to `docs/score_combo/`.
