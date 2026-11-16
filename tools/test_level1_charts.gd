extends SceneTree
## Headless check of level 1's charts against the music: plays the level with the judge switched off, pushes the
## gauge over the dancing-cats line (60) and looks at the notes the section holds afterwards.
##   - in the room the chart follows the groove: up to the bar line the drums change on, every note is on a hit of
##     the half-time groove; from that bar line on, on a hit of the four-on-the-floor groove (the "room4" chart)
##   - no note is lost or doubled at the switch
##   godot --headless -s tools/test_level1_charts.gd       (about 15 seconds, real time)

var Conductor: Node
var Music: Node
var _fail := 0
var _switch := -1.0   # a member: a lambda only gets a copy of a local


func _initialize() -> void:
	call_deferred("_run")


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_fail += 1
	print("  %s  %s  %s" % ["ok" if ok else "NO", what, detail])


func _on_groove(notes: Array, groove: String, from: float, to: float) -> Array:
	var g: Dictionary = Music.events.groove(groove)
	var bad := []
	for n: NoteData in notes:
		if n.beat >= from - 0.001 and n.beat < to - 0.001:
			var step := fposmod(n.beat, 4.0) * 4.0
			if not (step in g.kick or step in g.clap or step in g.open_hat):   # the open hat is as loud as the clap
				bad.append(n.beat)
	return bad


func _run() -> void:
	Conductor = root.get_node("Conductor")
	Music = root.get_node("Music")
	var main_script = load("res://scripts/main.gd")
	main_script.in_run = false
	Levels.selected = 0
	change_scene_to_file(Levels.GAME_SCENE)
	await create_timer(0.6).timeout
	var game = current_scene
	game.start_from(0)
	game.judge.set_process(false)   # nobody is playing: no misses
	var section: Node = game._current
	while Conductor.song_beat < 5.3:
		await process_frame
	Music.lane_switched.connect(func(lane: String, clip: String) -> void:
		if lane == "beat" and clip == "groove" and _switch < 0.0:
			_switch = roundf(Conductor.song_beat))
	game.gauge.set_value(60)
	game.gauge.fire_passed_events()
	await process_frame
	var held: Array = section.notes.duplicate()
	while Conductor.song_beat < 14.0:
		await process_frame
	var switch_at := _switch
	_check("the drums changed to four on the floor on a bar line", switch_at > 0.0 and is_zero_approx(fposmod(switch_at, 4.0)), "beat %s" % switch_at)
	var beats: Array = held.map(func(n: NoteData) -> float: return n.beat)
	var sorted := beats.duplicate()
	sorted.sort()
	var doubled := 0
	for i in range(1, sorted.size()):
		if is_equal_approx(sorted[i], sorted[i - 1]):
			doubled += 1
	_check("notes are in order, none doubled", beats == sorted and doubled == 0, str(beats.slice(0, 14)))
	_check("before that bar line every note is on the half-time groove", _on_groove(held, "half", 0.0, switch_at).is_empty(), str(_on_groove(held, "half", 0.0, switch_at)))
	_check("from it on every note is on the four-on-the-floor groove (kick or open hat)", _on_groove(held, "four", switch_at, 1000.0).is_empty(), str(_on_groove(held, "four", switch_at, 1000.0)))
	var has_four := held.any(func(n: NoteData) -> bool: return n.beat >= switch_at and is_equal_approx(fposmod(n.beat, 4.0), 3.0))
	_check("the four-on-the-floor chart is the one playing (it has notes on beat 3)", has_four)
	var first_after := 1000.0
	for n: NoteData in held:
		if n.beat >= switch_at - 0.001:
			first_after = minf(first_after, n.beat)
	_check("no gap: a note on the bar line of the switch", is_equal_approx(first_after, switch_at), "first note from the switch on: %s" % first_after)
	# the room's climax is stretched: from the dancing cats (60) to the house opening (110) takes about 24 perfect
	# hits now (the gauge rises slower there), eight bars of the eight-bar chart
	_check("the gauge rises slower in the room's climax", is_equal_approx(game.gauge.gain_scale, section.room_climax_gain), "x%s" % game.gauge.gain_scale)
	game.gauge.set_value(60)
	var hits := 0
	while game.gauge.value < 109 and hits < 200:
		game.gauge.apply(NoteData.Result.PERFECT)
		hits += 1
	_check("60 -> 110 takes about 24 perfect hits, eight bars of the chart (it was 10)", hits >= 22 and hits <= 25, "%d hits" % hits)
	var loop: Array = held.filter(func(n: NoteData) -> bool: return n.beat >= switch_at and n.beat < switch_at + 8.0).map(func(n: NoteData) -> float: return n.beat - switch_at)
	_check("the climax chart builds (bar 1: two notes, bar 2: three)", loop == [0.0, 2.0, 4.0, 6.0, 7.0], str(loop))
	# the fever: when the music plans it, the chart becomes the fever chart on that bar line and the gauge slows down
	game.judge._generate()
	var at := ceilf(Conductor.song_beat / 4.0) * 4.0 + 4.0
	Music.change_planned.emit("fever", 0, at, at)
	await process_frame
	var fever: Array = section.notes.filter(func(n: NoteData) -> bool: return n.beat >= at - 0.001 and n.beat < at + 8.0).map(func(n: NoteData) -> float: return n.beat - at)
	_check("fever: its own chart from that bar line", fever == [0.0, 1.0, 2.5, 3.0, 4.0, 5.0, 6.5, 7.0], str(fever))
	var all_notes: Array = []
	for name: String in ["", "_room4", "_road", "_plaza", "_fever"]:
		for d: Dictionary in load("res://levels/charts/level_1_disco_0%s.tres" % name).notes:
			all_notes.append(fposmod(float(d.beat), 1.0))
	_check("no chart of level 1 has a note off the half-beat grid", all_notes.all(func(f: float) -> bool: return is_zero_approx(f) or is_equal_approx(f, 0.5)))
	_check("fever: the gauge rises slower", is_equal_approx(game.gauge.gain_scale, section.plaza_fever_gain), "x%s" % game.gauge.gain_scale)
	print("LEVEL1_CHARTS_%s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit()
