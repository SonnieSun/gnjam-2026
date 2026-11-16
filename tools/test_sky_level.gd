extends SceneTree
## Headless check of the sky level (the interlude after level 1) against its music, the judge switched off:
##   - when the level turns bright (the gauge passes 50 %: Ode to Joy starts on the next bar line) the chart becomes
##     the tune: every note from that bar line on is a note of the melody, counted from the tune's own bar 1
##   - the notes before that bar line are still there, nothing is doubled
##   - the cat in the beam bounces with the music, the fever picture comes on at 85 %
##   godot --headless -s tools/test_sky_level.gd       (about 25 seconds, real time)

var Conductor: Node
var Music: Node
var _fail := 0
var _commit := -1.0


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
	Levels.selected = 0
	Levels.interlude = "res://levels/interludes/after_level_1_disco.tres"
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
	var kept := before.filter(func(b: float) -> bool: return b < _commit - 0.001 and b > 5.3)
	var still := beats.filter(func(b: float) -> bool: return b < _commit - 0.001 and b > 5.3)
	var sorted := beats.duplicate()
	sorted.sort()
	_check("the notes before it are still there, in order", kept == still and beats == sorted, str(still))
	var fx: Node = section.get_node("FeverFx")
	_check("no fever picture yet", not fx._on)
	game.gauge.set_value(420)       # 87.5 %
	while not Music.fever and Conductor.song_beat < _commit + 40.0:
		await process_frame
	await create_timer(0.4).timeout
	_check("fever at 85 %: the colour filter is on", Music.fever and fx._on and fx._rect.visible)
	print("SKY_LEVEL_%s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	Levels.interlude = ""
	quit()
