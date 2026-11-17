extends SceneTree
## Headless check of level 3's shooter chart against the music, and of the note marks / fever picture that every
## section of levels 2 and 3 now carries.
##   - the shooter: the chart is as long as the tune (16 bars), every note is on a kick of the plain groove and on a
##     note of the Turkish March (the chart starts a bar into the tune), and the opening bars are on the half-time
##     groove's own hits
##   - each section scene has its NoteAccents and FeverFx, the fever sounds are the ones in that tune's key, and a
##     bar-line note gets its mark colour through SpinSection.sound_color()
##   godot --headless -s tools/test_level3.gd       (about 25 seconds, real time)

var Conductor: Node
var Music: Node
var _fail := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_fail += 1
	print("  %s  %s  %s" % ["ok" if ok else "NO", what, detail])


func _open(level: int, section: int) -> Node:
	Levels.selected = level
	change_scene_to_file(Levels.GAME_SCENE)
	await create_timer(0.6).timeout
	var game = current_scene
	game.start_from(section)
	game.judge.set_process(false)
	await create_timer(0.4).timeout
	return game


func _run() -> void:
	Conductor = root.get_node("Conductor")
	Music = root.get_node("Music")
	var main_script = load("res://scripts/main.gd")
	main_script.in_run = false

	# ---- the shooter's chart ----
	# (no class names of the game here: naming one would compile it before the autoloads exist)
	var chart: Resource = load("res://levels/charts/level_4_spaceship_0.tres")
	var beats: Array = chart.notes.map(func(d: Dictionary) -> float: return float(d.beat))
	beats.sort()
	var tune: Dictionary = Music.events.song("turkish_march")
	var written: Array = (tune.notes as Array).map(func(n: Array) -> int: return int(n[0]))
	var four: Dictionary = Music.events.groove("four")
	var half: Dictionary = Music.events.groove("half")
	_check("the shooter's chart is as long as the tune", is_equal_approx(chart.length_beats, float(tune.bars) * 4.0), "%s beats" % chart.length_beats)
	var off_drum := beats.filter(func(b: float) -> bool: return not (fposmod(b, 4.0) * 4.0) in four.kick)
	var off_tune := beats.filter(func(b: float) -> bool: return not (int(round((b + 4.0) * 4.0)) % (int(tune.bars) * 16)) in written)
	_check("every note is on a kick of the plain groove", off_drum.is_empty(), str(off_drum))
	_check("every note is on a note of the Turkish March (the chart starts on its bar 2)", off_tune.is_empty(), str(off_tune))
	var opening := beats.filter(func(b: float) -> bool: return b < 16.0)
	_check("the first four bars are on the half-time groove's kick and clap", opening.all(func(b: float) -> bool:
		return (fposmod(b, 4.0) * 4.0) in half.kick or (fposmod(b, 4.0) * 4.0) in half.clap), str(opening))

	# ---- the sections of levels 2 and 3 ----
	for spot: Array in [[1, 0, "fever_enter_ab", "the washer"], [1, 3, "fever_enter", "the earth"], [2, 0, "fever_enter_a", "the shooter"], [2, 1, "fever_enter_g", "the pizza"]]:
		var game = await _open(spot[0], spot[1])
		var section: Node = game._current
		var fx: Node = section.get_node_or_null("FeverFx")
		var accents: Node = section.get_node_or_null("NoteAccents")
		var ok: bool = fx != null and accents != null and section.note_accents == accents
		var sound := ""
		if ok:
			Music.fever_started.emit()
			await process_frame
			sound = fx._sfx.stream.resource_path.get_file().get_basename() if fx._sfx.stream else ""
			Music.fever_ended.emit()
			ok = fx._sfx.playing and sound == spot[2]
		_check("%s: note marks and the fever picture are in, the fever sound is in its key" % spot[3], ok, sound)
		if spot[3] == "the shooter":
			# a note on a bar line is tinted through the one place sections get a note's colour
			var n := NoteData.new()
			n.beat = 400.0
			var plain := Color(1.0, 0.85, 0.2)   # SpinSection.SOUND_COLORS[0], the kick's colour
			_check("a bar-line note gets its mark colour in sound_color()", not section.sound_color(n).is_equal_approx(plain), str(section.sound_color(n)))
			section.note_accents.enabled = false
			section.note_accents._forget()
			_check("with the marks switched off it is the plain colour", section.sound_color(n).is_equal_approx(plain))
	print("LEVEL3_%s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit()
