extends SceneTree
## Headless check of the sky level (level 2) against its music, the judge switched off:
##   - the storm: its written fill starts at least 4 beats after the gauge line, on a bar line; the doom music starts
##     from its own bar 1 one bar later; the chart from the fill's bar line on is the storm chart, note for note
##   - the light waits for the end of the doom loop (its 8-bar line), so its last bar always leads into the Ode
##   - when the level turns bright (the gauge passes 50 %: Ode to Joy starts on the next bar line) the chart becomes
##     the tune: every note from that bar line on is a note of the melody, counted from the tune's own bar 1
##   - the notes before the run into it are still there, the bar before it is a run of eighths, nothing is doubled
##   - space comes in on the tune's bar 9 and the fever on bar 13 (phrase lines), with the fever picture
##   - the last gauge line does not end the level before the tune has been sung through once (16 bars)
##   - the cat in the beam bounces with the music
##   godot --headless -s tools/test_sky_level.gd       (about a minute, real time)

var Conductor: Node
var Music: Node
var _fail := 0
var _commit := -1.0
var _storm_fill := -1.0
var _storm_commit := -1.0
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
	process_frame.connect(func() -> void: game.judge._generate())   # ... but the notes still get made, a few beats ahead
	var section: Node = game._current
	_check("this is the sky level", section.get_script().resource_path.ends_with("sky_section.gd"))
	Music.change_planned.connect(func(kind: String, id: int, fill: float, commit: float) -> void:
		if kind == "tier" and id == 2:
			_commit = commit
		if kind == "tier" and id == 1:
			_storm_fill = fill
			_storm_commit = commit)
	while Conductor.song_beat < 5.3:
		await process_frame
	var bounce: Node = section.get_node("CatBounce")
	_check("cat bounce found the cat in the beam", is_instance_valid(bounce._joint))
	# --- the storm ---
	var lines: PackedFloat32Array = Music.tier_lines(Music.section)
	var crossed: float = Conductor.song_beat
	game.gauge.set_value(int(ceil(float(lines[0]) * game.gauge.max_value)))
	await process_frame
	_check("the storm's fill is planned on a bar line, at least 4 beats on", _storm_fill >= crossed + 3.99 and is_zero_approx(fposmod(_storm_fill, 4.0)) 			and is_equal_approx(_storm_commit, _storm_fill + 4.0), "crossed %.2f, fill %s, storm %s" % [crossed, _storm_fill, _storm_commit])
	while Conductor.song_beat < _storm_commit + 1.0:
		await process_frame
	var doom: float = Music.tune_origin("doom")
	_check("the doom music starts from its own bar 1 after the fill", is_equal_approx(doom, _storm_commit), "doom from %s" % doom)
	var pattern: ChartPattern = load("res://levels/charts/level_2_sky_0_storm.tres")
	var want_storm: Array = pattern.notes.map(func(d: Dictionary) -> float: return snappedf(_storm_fill + float(d.beat), 0.001)).filter(
			func(b: float) -> bool: return b < _storm_fill + 36.0)
	# (the judge is switched off, so only the notes made when the chart was swapped in are there: they must be the chart's first notes)
	var got_storm: Array = section.notes.map(func(n: NoteData) -> float: return snappedf(n.beat, 0.001)).filter(
			func(b: float) -> bool: return b >= _storm_fill - 0.001 and b < _storm_fill + 36.0)
	_check("from the fill on the chart is the storm chart, note for note", got_storm.size() >= 8 and got_storm == want_storm.slice(0, got_storm.size()),
			"%d notes: %s" % [got_storm.size(), str(got_storm)])
	# --- the light ---
	game.gauge.set_value(int(ceil(float(lines[1]) * game.gauge.max_value)))
	await process_frame
	_check("the music planned the bright stage on a bar line", _commit > 0.0 and is_zero_approx(fposmod(_commit, 4.0)), "beat %s" % _commit)
	_check("... at the end of the doom loop (its 8-bar line)", is_zero_approx(fposmod(_commit - doom, 32.0)), "beat %s, doom from %s" % [_commit, doom])
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
	var kept := want_storm.filter(func(b: float) -> bool: return b < run_from - 0.001)   # the whole storm chart up to the run
	var still := beats.filter(func(b: float) -> bool: return b < run_from - 0.001 and b > _storm_fill - 0.001).map(func(b: float) -> float: return snappedf(b, 0.001))
	var run := beats.filter(func(b: float) -> bool: return b >= run_from - 0.001 and b < _commit - 0.001)
	var want_run := []
	for i in section.ode_run_notes - 1:
		want_run.append(run_from + i * 0.5)
	var sorted := beats.duplicate()
	sorted.sort()
	_check("every storm note before the run is there (none lost to the wait), in order", kept == still and beats == sorted, str(still))
	_check("the bar before the tune is a run of eighths", run == want_run, str(run))
	# the note on the beat Ode to Joy comes in is the rainbow one, and only that one
	var accents: Node = section.get_node("NoteAccents")
	var rainbow := []
	for n: NoteData in section.notes:
		if accents.look(n, Color.WHITE).rainbow:
			rainbow.append(n.beat)
	_check("the note on the beat Ode to Joy comes in is the rainbow one, and only it", rainbow == [_commit], "rainbow: %s" % str(rainbow))
	var firsts: Array = section.notes.filter(func(n: NoteData) -> bool: return is_equal_approx(n.beat, _commit))
	_check("that note is still to be played (the white flash skips the ones after it)", firsts.size() == 1 and not firsts[0].judged)
	var fx: Node = section.get_node("FeverFx")
	_check("no fever picture yet", not fx._on)
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
