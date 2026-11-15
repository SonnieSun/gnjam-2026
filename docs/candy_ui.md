# Candy Gem UI integration

## Current menu style

The ten disc Title/Sub nodes render the original CandyGem color bitmap font: pink/purple texture, gold edging and baked highlights. The inflated lettering script is detached from these nodes. Enlarged title/stage sizes and chart-driven names/counts are retained. The balloon assets remain available as an unused experiment.

## Previous inflated lettering experiment (inactive)

`scripts/balloon_lettering.gd` was used for the inflated experiment. Its editable Label3D text/font/size fields provide layout metadata and the flat text is hidden while attached. Reusable meshes in `assets/fonts/candy_gem/balloon` follow the extracted font silhouettes and have domed fronts and closed side/counter walls. A wider, nearly flat dark-purple mesh under each letter provides the recessed mounting edge; the record itself is not boolean-cut.

`assets/menu/balloon_foil.gdshader` keeps pink/purple as the base, adds view/normal-dependent spectral edging and broad foil reflections. Hologram strength and base colors are material parameters. Reflections are stylized shader reflections, so the lettering remains readable under the menu's very low lighting. Only the record's names and stage-count lettering use this material; PLAY remains the color bitmap font.

Open `scenes/menu.tscn` in Godot and press F6. Select with Left/Right or the neon arrow buttons; enter with Space, Enter, or PLAY. Gameplay Esc returns to the menu.

The record labels use `assets/fonts/candy_gem/CandyGem.fnt` and its transparent color atlas. The five chart titles are DISCO, SPACESHIP, ORBIT CAT, TV WALL, WASHING MACHINE; counts currently read 1, 1, 3, 1, 1 STAGE(S). Runtime labels read the chart resources directly. Longer titles are sized to fit a common sector width.

Font changes apply only to the menu. Gameplay judgment, timing hints, score, combo and milestone fonts retain their original settings. Menu title size is 190 (long names fit within 1100 font-layout units), stage count size is 100 (previously 40). Adjust these on Menu/Disc3D via title_font_size, stage_font_size and title_max_width. The stage subtitle is offset farther below the title to avoid overlap.

The color font has A–Z, a–z, 0–9 and space only. Lowercase c was reconstructed from C because the supplied lowercase sheet has x in its place. `CandyGem-Mono.ttf` is included as an optional scalable single-color alternative.

Validation: `godot --headless --path <project> --script res://tools/test_candy_menu.gd`. Checks required glyphs, all five titles/counts, selection, PLAY, original gameplay fonts, and return to menu. Running with a graphics backend also writes `docs/menu_candy_preview.png`.
