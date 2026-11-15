# Static S/A/B/C settlement

The upright approved red S / pink A / orange B / yellow C artwork is sliced into transparent PNGs under `assets/ui/result_grades`. `ui/result_widget.tscn` displays the final letter beside score, max combo, four judgment counts and signed mean timing offset. Restart and menu keyboard shortcuts remain R / Esc. No animated effects were added.

Accuracy = score / (100 × number of actually judged notes). This matches the 100/80/50/0 point system and includes misses. Since stages loop until their gauges fill, this denominator uses counts accumulated during this run, not the chart's initial fixed note list or a previous run's best score. Thresholds are S ≥ 95%, A ≥ 85%, B ≥ 70%, otherwise C. An empty run is C at 0%. Integer comparisons determine ranks at exact boundaries.

The result view clears transient judgment and combo milestone artwork. HUD reset hides the settlement; reopening it always replaces its grade and statistics. Gameplay scoring is unchanged.

Validation: run `godot --headless --path <project> --script res://tools/test_result_widget.gd`. A graphics run writes S/A/B/C actual game screenshots under `docs/result_grades`.
