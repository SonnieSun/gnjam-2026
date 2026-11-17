extends SceneTree
## Headless check of the sky level (level 2) against its music, the judge switched off:
##   - when the level turns bright (the gauge passes 50 %: Ode to Joy starts on the next bar line) the chart becomes
##     the tune: every note from that bar line on is a note of the melody, counted from the tune's own bar 1
##   - the notes before the run into it are still there, the bar before it is a run of eighths, nothing is doubled
##   - space comes in on the tune's bar 9 and the fever on bar 13 (phrase lines), with the fever picture
##   - the last gauge line does not end the level before the tune has been sung through once (16 bars)
##   - the cat in the beam bounces with the music
##   godot --headless -s tools/test_sky_level.gd       (about 40 seconds, real time)

var Conductor: Node
var Music: Node
var _fail := 0
var _commit := -1.0
var _space_at := -1.0


func _initialize() -> void:
	call_deferred("_run")


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_fail += 1
	print("  %s  %s  %s" % ["ok" if ok else "NO", what, detail])


func _run() -> void:
	Conductor = root.get_node("Conductor")
	Music = root.get_node("Music")
	var main_script = load("res://scripts/main.gd")
	main_script.in_run = false
	Levels.selected = 1  # 第 2 大关：天空（原来是第 1 关后面的插曲关）
	Levels.interlude = ""
	change_scene_to_file(Levels.GAME_SCENE)
	await create_timer(0.6).timeout
	var game = current_scene
	game.start_from(0)
	game.judge.set_process(false)   # nobody is playing: no misses
	var section: Node = game._current
	_check("this is the sky level", section.get_script().resource_path.ends_with("sky_section.gd"))
	Music.change_planned.connect(func(kind: String, id: int, _fill: float, commit: float) -> void:
		if kind == "tier" and id == 2:
			_commit = commit)
	while Conductor.song_beat < 5.3:
		await process_frame
	var bounce: Node = section.get_node("CatBounce")
	_check("cat bounce found the cat in the beam", is_instance_valid(bounce._joint))
	var before: Array = section.notes.map(func(n: NoteData) -> float: return n.beat)
	game.gauge.set_value(240)       # 50 %
	await process_frame
	_check("the music planned the bright stage on a bar line", _commit > 0.0 and is_zero_approx(fposmod(_commit, 4.0)), "beat %s" % _commit)
	while Conductor.song_beat < _commit + 6.0:
		await process_frame
	var origin: float = Music.tune_origin("ode")
	_check("Ode to Joy starts on that bar line", is_equal_approx(origin, _commit), "tune origin %s" % origin)
	var song: Dictionary = Music.events.song("ode_to_joy")
	var written: Array = (song.notes as Array).map(func(n: Array) -> int: return int(n[0]))
	var beats: Array = section.notes.map(func(n: NoteData) -> float: return n.beat)
	var off := []
	var after := []
	for b: float in beats:
		if b >= _commit - 0.001:
			after.append(b)
			if not (int(round((b - origin) * 4.0)) % (int(song.bars) * 16)) in written:
				off.append(b)
	_check("from that bar line on every note is a note of the melody", off.is_empty() and after.size() >= 8, "%d notes, not in the tune: %s" % [after.size(), str(off)])
	var want := written.filter(func(s: int) -> bool: return s < 32).map(func(s: int) -> float: return _commit + s / 4.0)
	_check("the first two bars are the tune's first two bars, note for note", after.slice(0, want.size()) == want, str(after.slice(0, want.size())))
	var run_from: float = _commit - (section.ode_run_notes - 1) * 0.5
	var kept := before.filter(func(b: float) -> bool: return b < run_from - 0.001 and b > 5.3)
	var still := beats.filter(func(b: float) -> bool: return b < run_from - 0.001 and b > 5.3)
	var run := beats.filter(func(b: float) -> bool: return b >= run_from - 0.001 and b < _commit - 0.001)
	var want_run := []
	for i in section.ode_run_notes - 1:
		want_run.append(run_from + i * 0.5)
	var sorted := beats.duplicate()
	sorted.sort()
	_check("the notes before the run are still there, in order", kept == still and beats == sorted, str(still))
	_check("the bar before the tune is a run of eighths", run == want_run, str(run))
	# the note on the beat Ode to Joy comes in is the rainbow one, and only that one
	var accents: Node = section.get_node("NoteAccents")
	var rainbow := []
	for n: NoteData in section.notes:
		if accents.look(n, Color.WHITE).rainbow:
			rainbow.append(n.beat)
	_check("the note on the beat Ode to Joy comes in is the rainbow one, and only it", rainbow == [_commit], "rainbow: %s" % str(rainbow))
	var first: NoteData = section.notes.filter(func(n: NoteData) -> bool: return is_equal_approx(n.beat, _commit))[0]
	_check("that note is still to be played (the white flash skips the ones after it)", not first.judged)
	var fx: Node = section.get_node("FeverFx")
	_check("no fever picture yet", not fx._on)
	var lines: PackedFloat32Array = Music.tier_lines(Music.section)
	Music.tier_changed.connect(func(t: int, _up: bool) -> void:
		if t == 3 and _space_at < 0.0:
			_space_at = Conductor.song_beat)
	# a perfect run (the fastest the gauge can go) crosses the space line in the tune's bar 7 and the fever line in bar 11
	while Conductor.song_beat < origin + 24.5:
		await process_frame
	game.gauge.set_value(int(ceil(float(lines[2]) * game.gauge.max_value)))   # space: waits for the phrase line
	while _space_at < 0.0 and Conductor.song_beat < _commit + 40.0:
		await process_frame
	_check("space comes in on the tune's bar 9 (the B phrase)", is_equal_approx(roundf(_space_at - origin), 32.0), "beat %s" % _space_at)
	while Conductor.song_beat < origin + 40.5:
		await process_frame
	game.gauge.set_value(int(ceil(float(lines[3]) * game.gauge.max_value)))   # fever
	while not Music.fever and Conductor.song_beat < _commit + 70.0:
		await process_frame
	var fever_at: float = Conductor.song_beat
	await create_timer(0.4).timeout
	_check("the fever comes in on the tune's bar 13 (the last A)", is_equal_approx(roundf(fever_at - origin), 48.0), "beat %s" % fever_at)
	_check("fever: the colour filter is on", Music.fever and fx._on and fx._rect.visible)
	# the last line, crossed early (in bar 13; a perfect run crosses it in bar 15): the finale still waits for the end of bar 16, and the gauge stops filling
	var last: int = game.gauge.events[game.gauge.events.size() - 1]
	game.gauge.set_value(last - 1)
	game.gauge.apply(NoteData.Result.PERFECT)
	await process_frame
	_check("the finale waits for the tune to be sung through once", is_equal_approx(section._finale_at, origin + 64.0), "finale at %s, tune from %s" % [section._finale_at, origin])
	var v: int = game.gauge.value
	for i in 10:
		game.gauge.apply(NoteData.Result.PERFECT)
	_check("while it waits the gauge does not fill up", game.gauge.value == v and not game.gauge.full, "%d -> %d" % [v, game.gauge.value])
	print("SKY_LEVEL_%s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit()
