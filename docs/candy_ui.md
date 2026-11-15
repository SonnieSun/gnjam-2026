# Candy Gem menu typography

The menu uses `assets/fonts/candy_gem/CandyGem.fnt` and its transparent atlas: pink/purple faces, gold edging and baked highlights. Only the active bitmap font is included; unused balloon meshes and foil experiments are excluded.

Open `scenes/menu.tscn` in Godot and press F6. Select with Left/Right or the neon arrows; start with Space, Enter or PLAY. Esc returns from gameplay.

Record labels read titles and section counts from the current chart resources. The current three main charts retain upstream ordering and section flow. Title size is 190, stage count size is 100, and long names fit within 1100 font-layout units. These are editable on Menu/Disc3D. The subtitle is offset below the title to avoid overlap.

The color font contains A–Z, a–z, 0–9 and space. Lowercase c was reconstructed from C because the supplied lowercase sheet has x in its place.

Validation: `godot --headless --path <project> --script res://tools/test_candy_menu.gd`. The merged chart flow is covered by `tools/test_merged_level_flow.gd`.
