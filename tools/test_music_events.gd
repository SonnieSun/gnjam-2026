extends SceneTree
## Headless check of Music.drum_kick / drum_clap / lead_note in level 1: plays the level's music, walks the gauge
## through its stages and prints, bar by bar, which sixteenths the signals fired on, next to what should be there
## (the groove's pattern, the tune's notes counted from the tune's own bar 1), and how late each one was emitted.
##   godot --headless -s tools/test_music_events.gd            (about a minute: it runs in real time)

## [from bar, gauge progress 0-1]
const WALK := [[0, 0.0], [2, 0.10], [4, 0.15], [8, 0.26], [18, 0.40], [22, 0.60], [30, 0.66], [34, 0.82]]
const BARS := 38
const PATTERN := {"half": [[0, 10], [8]], "groove": [[0, 4, 8, 12], []], "club": [[0, 3, 6, 10, 12, 14], [4, 12]],
		"break": [[0, 7, 10], [4, 12]], "": [[], []]}

var _rows := {}     # bar -> {"kick": [], "clap": [], "note": [], "tune": [], "beat_clip", "lead_clip", "count"}
var _late := 0.0
var _bad := 0
var _count_bar := {}
# a -s script is compiled before the autoloads exist: fetched from the tree in _run()
var Conductor: Node
var Music: Node


func _initialize() -> void:
	call_deferred("_run")


func _row(bar: int) -> Dictionary:
	if not _rows.has(bar):
		_rows[bar] = {"kick": [], "clap": [], "note": [], "tune": []}
	return _rows[bar]


func _seen(kind: String, beat: float) -> void:
	_late = maxf(_late, Conductor.song_beat - beat)
	_row(floori(beat / 4.0))[kind].append(int(round(fposmod(beat, 4.0) * 4.0)))


func _run() -> void:
	Conductor = root.get_node("Conductor")
	Music = root.get_node("Music")
	Levels.selected = 0
	var chart: SongChart = Levels.build_chart()
	chart.stream = Music.build(Music.read(Music.path_for(0)))
	chart.bpm = Music.bpm()
	chart.first_beat_offset_sec = 0.0
	Conductor.load_chart(chart)
	Music.set_section(0)
	Music.drum_kick.connect(func(b: float) -> void: _seen("kick", b))
	Music.drum_clap.connect(func(b: float) -> void: _seen("clap", b))
	Music.count_in_started.connect(func(b: float) -> void: _count_bar[int(b / 4.0)] = true)
	Music.lead_note.connect(func(b: float, _m: int, _l: float) -> void:
		_seen("note", b)
		# the same note counted from the tune's own bar 1 (sixteenths into its loop)
		var clip: String = Music.playing_clip("lead")
		var tune: String = Music._tune_of("lead", clip)
		var s: Dictionary = Music.events.song(Music.events.song_of(clip))
		_row(floori(b / 4.0)).tune.append(int(round((b - Music.tune_origin(tune)) * 4.0)) % (int(s.bars) * 16)))
	Conductor.bar.connect(func(i: int) -> void:
		for step: Array in WALK:
			if int(step[0]) == i:
				Music.set_progress(step[1])
		# what is playing in this bar is settled once the music has handled the bar line: read it a moment later
		create_timer(0.2).timeout.connect(func() -> void:
			var r := _row(i)
			r.beat_clip = Music.playing_clip("beat")
			r.lead_clip = Music.playing_clip("lead")))
	Conductor.play(0.0)
	while Conductor.song_beat < BARS * 4.0 + 0.5:
		await process_frame
	Conductor.stop()
	print("bar  beat lane  kick                clap     ok | lead lane   notes (sixteenths of the bar)           in the tune's loop          ok")
	for bar in BARS:
		var r := _row(bar)
		var clip := str(r.get("beat_clip", "?"))
		var want: Array = PATTERN.get(clip, [[], []])
		if _count_bar.has(bar):       # the count-in bar: the level's drums step aside, no drum signals
			want = [[], []]
		var drums_ok: bool = r.kick == want[0] and r.clap == want[1]
		var lead := str(r.get("lead_clip", "?"))
		var s: Dictionary = Music.events.song(Music.events.song_of(lead)) if lead != "" else {}
		var notes_ok := true
		if s.is_empty():
			notes_ok = (r.note as Array).is_empty()
		else:
			# every fired note must be a written note of the tune, and the bar must hold all the notes of that tune bar
			var written: Array = (s.notes as Array).map(func(n: Array) -> int: return int(n[0]))
			for t: int in r.tune:
				notes_ok = notes_ok and t in written
			if not (r.tune as Array).is_empty():
				var tune_bar: int = int(r.tune[0]) / 16
				var in_bar: Array = written.filter(func(t: int) -> bool: return t / 16 == tune_bar)
				notes_ok = notes_ok and in_bar == r.tune
		if not drums_ok or not notes_ok:
			_bad += 1
		print("%3d  %-9s  %-18s  %-7s  %s | %-10s  %-38s  %-26s  %s" % [bar + 1, clip + ("*" if _count_bar.has(bar) else ""),
				str(r.kick), str(r.clap), "ok" if drums_ok else "NO", lead, str(r.note), str(r.tune), "ok" if notes_ok else "NO"])
	print("(* = count-in bar)   latest emit: %.3f beats = %.0f ms after the hit" % [_late, _late * 60000.0 / Music.bpm()])
	print("MUSIC_EVENTS_%s: %d bars checked, %d wrong" % ["PASS" if _bad == 0 else "FAIL", BARS, _bad])
	quit()
