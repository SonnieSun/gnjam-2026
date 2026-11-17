extends SceneTree
## Headless check of level 2 (the washer, then the three parts of the earth), the judge's own clock switched off:
##   - the washer: every hold starts on the same beat of the bar; a hold whose head was hit completes at its tail
##     without the key being held (no tail judgement)
##   - the earth: a part waits for the tune's phrase line before the next part's music comes in; a mash that ends
##     without enough presses gives no verdict, the press that reaches the count is still a Perfect; part 3's chart
##     sits on the break groove
##   godot --headless -s tools/test_level2.gd       (about 40 seconds, real time)

var Conductor: Node
var Music: Node
var _fail := 0
var _judged: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_fail += 1
	print("  %s  %s  %s" % ["ok" if ok else "NO", what, detail])


func _until(beat: float) -> void:
	while Conductor.song_beat < beat:
		await process_frame


func _run() -> void:
	Conductor = root.get_node("Conductor")
	Music = root.get_node("Music")
	var main_script = load("res://scripts/main.gd")
	main_script.in_run = false
	Levels.selected = 1
	change_scene_to_file(Levels.GAME_SCENE)
	await create_timer(0.6).timeout
	var game = current_scene
	game.judge.note_judged.connect(func(_n: NoteData, r: int, _d: float) -> void: _judged.append(r))

	# ---- the washer ----
	game.start_from(0)
	game.judge.set_process(false)
	var washer: Node = game._current
	await _until(10.2)
	game.judge._generate()   # the judge's clock is off in this test: lay the notes out as far as it would have
	washer._parse_holds()
	var holds: Array = washer.notes.filter(func(n: NoteData) -> bool: return washer.hold_beats(n) > 0.0)
	var places := {}
	for n: NoteData in holds:
		places[fposmod(n.beat, 4.0)] = true
	_check("the washer's holds all start on the same beat of the bar", holds.size() >= 2 and places.size() == 1, "beat %s of the bar, %d holds laid out" % [str(places.keys()), holds.size()])
	var hold: NoteData = holds[0]
	await _until(hold.beat)
	var before: float = washer._stage.progress()
	hold.judged = true
	washer._on_note_judged(hold, NoteData.Result.PERFECT)      # the head is hit; nobody holds the key
	_check("a hold begins when its head is hit", washer._holding == hold)
	await _until(hold.beat + washer.hold_beats(hold) + 0.3)
	_check("it completes at its tail without the key held (no tail judgement)", washer._holding == null and not washer._failed.has(hold)
			and washer._stage.progress() > before, "washer progress %.2f -> %.2f" % [before, washer._stage.progress()])

	# ---- the earth, part 1: waits for the phrase line ----
	game.start_from(1)
	game.judge.set_process(false)
	while Music.tune_origin("mka") < 0.0:
		await process_frame
	var origin: float = Music.tune_origin("mka")
	# fill the gauge in the first bar of a four-bar phrase: without the wait the switch would be one bar later
	while fposmod(Conductor.song_beat - origin, 16.0) > 2.5 or Conductor.song_beat < origin + 0.5:
		await process_frame
	var filled_at: float = Conductor.song_beat
	while not game.gauge.full:
		game.gauge.apply(NoteData.Result.PERFECT)
	var switch_at: float = game._switch_at
	# the next part's music comes in one bar after the switch (it has no fill): that bar line must end a phrase
	_check("part 1 switches so that its tune ends on a four-bar phrase line", is_zero_approx(fposmod(switch_at + 4.0 - origin, 16.0)) and switch_at > filled_at,
			"gauge full at beat %.1f, switch at %.0f, the tune started on %.0f" % [filled_at, switch_at, origin])
	_check("it waited (the next bar line would have cut the phrase)", switch_at - filled_at > 4.0, "%.1f beats" % (switch_at - filled_at))
	# the notes join up: part 2's notes are already laid out from the switch on, behind part 1's, with no bar of rest
	var joined: Array = game._current.notes.map(func(n: NoteData) -> float: return n.beat)
	var gap := 0.0
	for i in range(1, joined.size()):
		if joined[i] <= switch_at + 8.0:
			gap = maxf(gap, joined[i] - joined[i - 1])
	_check("notes run through the switch with no gap", joined.has(switch_at) and joined.has(switch_at + 1.0) and gap <= 2.01, "largest gap %.1f beats; around the switch: %s" % [gap,
			str(joined.filter(func(b: float) -> bool: return b >= switch_at - 4.0 and b <= switch_at + 4.0))])
	var on_line: NoteData = game._current.notes.filter(func(n: NoteData) -> bool: return is_equal_approx(n.beat, switch_at))[0]
	await _until(switch_at + 6.5)   # the old tune fades for a beat before it stops
	_check("the notes laid out before the switch are the ones played after it", game.judge.notes.has(on_line) and game._current.notes.has(on_line)
			and game._current.notes[0] == on_line, "first note of part 2 on beat %s" % game._current.notes[0].beat)
	_check("part 2 is on, and its tune starts where part 1's phrase ended", game._index == 2 and is_equal_approx(Music.tune_origin("mk"), switch_at + 4.0)
			and Music.tune_origin("mka") < 0.0, "mk starts on %s" % Music.tune_origin("mk"))

	# ---- the earth, part 3: the chart and the mash ----
	game.start_from(3)
	game.judge.set_process(false)
	var earth: Node = game._current
	await _until(4.5)
	var groove: Dictionary = Music.events.groove(Music.events.groove_of(Music.playing_clip("beat")))
	var off := []
	var mash := 0
	for n: NoteData in earth.notes:
		if n.sound == NoteData.Sound.HAT:
			mash += 1
			continue
		var step := fposmod(n.beat, 4.0) * 4.0
		if not (step in groove.kick or step in groove.clap):
			off.append(n.beat)
	_check("part 3: every tap and slap is on a kick or clap of the break groove", Music.playing_clip("beat") == "break" and off.is_empty() and mash > 0, "off: %s" % str(off))
	_check("part 3: one mash per bar, the slap on beat 4", earth._zones.size() == 1 and is_equal_approx(earth._strike_beat, 3.0), "zones %d, slap on beat %s" % [earth._zones.size(), earth._strike_beat])
	# a whole mash goes by with no press: no verdict
	_judged.clear()
	game.judge._generate()
	var zone: Dictionary = earth._zone_now()
	await _until(float(zone.end) + 0.3)
	_check("a mash nobody pressed gives no verdict (no tail judgement)", _judged.is_empty(), str(_judged))
	# the next one: enough presses -> a Perfect on the press that reaches the count
	zone = earth._zone_now()
	await _until(float(zone.start) + 0.1)
	await process_frame
	for i in int(zone.need):
		earth._on_empty_hit()
	_check("the press that reaches the count is a Perfect", _judged == [NoteData.Result.PERFECT], str(_judged))
	print("LEVEL2_%s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit()
