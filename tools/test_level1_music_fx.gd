extends SceneTree
## Headless check of level 1's music-driven sample effects (scenes/sections/kisa/disco.tscn):
##   CatBounce       the cat squashes on the groove's kick without any input
##   NoteAccents     which mark each kind of note gets
##   CountInDisplay  READY 3 2 1 on the four hits of a count-in
##   godot --headless -s tools/test_level1_music_fx.gd       (about 15 seconds, real time)

var Conductor: Node
var Music: Node
var _fail := 0


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
	change_scene_to_file(Levels.GAME_SCENE)
	await create_timer(0.6).timeout
	var game = current_scene
	game.start_from(0)
	game.judge.set_process(false)   # nobody is playing: no misses
	var section: Node = game._current
	var bounce: Node = section.get_node("CatBounce")
	var accents: Node = section.get_node("NoteAccents")
	var count: Node = section.get_node("CountInDisplay")

	# --- the cat: deepest squash after each kick of the half-time groove (kick on steps 0 and 10) ---
	var kicks: Array = []
	var deepest := {}
	Music.drum_kick.connect(func(b: float) -> void: kicks.append(b))
	while Conductor.song_beat < 8.6:
		await process_frame
		if not kicks.is_empty() and is_instance_valid(bounce._joint):
			var k: float = kicks[-1]
			deepest[k] = minf(deepest.get(k, 1.0), bounce._joint.scale.y)
	_check("cat bounce found the cat", is_instance_valid(bounce._joint))
	_check("kicks of the half-time groove", kicks == [0.0, 2.5, 4.0, 6.5, 8.0], str(kicks))
	var squashed := 0
	for k: float in deepest:
		if deepest[k] < 0.93:
			squashed += 1
	_check("cat squashed after every kick", squashed == deepest.size() and squashed >= 4, "lowest height per kick: " + str(deepest.values().map(func(v: float) -> String: return "%.2f" % v)))
	bounce.enabled = false
	await process_frame
	await process_frame
	_check("flag off: cat back to normal", bounce._joint.scale.is_equal_approx(Vector3.ONE))
	bounce.enabled = true

	# --- note marks, on the half-time groove (clap on step 8 = beat 2 of the bar) ---
	# NoteAccents.Kind by number (naming the class here would compile it before the autoloads exist)
	var K := {"NONE": 0, "DOWNBEAT": 1, "SYNCOPATED": 2, "ACCENT": 3, "LEAD_IN": 4, "FEVER": 5}
	# a made-up bar: 12 (bar line), 13 (plain), 14 (on the clap), then three off-beats in a row 16.5 17.5 18.5, and 20
	var made: Array[NoteData] = []
	for b: float in [12.0, 13.0, 14.0, 16.5, 17.5, 18.5, 20.0, 24.0, 25.0]:
		var n := NoteData.new()
		n.beat = b
		made.append(n)
	accents.notes = made
	var want := [K.DOWNBEAT, K.NONE, K.ACCENT, K.SYNCOPATED, K.NONE, K.NONE, K.DOWNBEAT]
	var got: Array = []
	for i in want.size():
		got.append(accents.kind_of(made[i]))
	_check("bar line / plain / clap / only the first of three off-beats / bar line", got == want, str(got))
	# a change gets planned while a note is on its way: the note keeps its mark
	Music._plan = {"kind": "tier", "id": 3, "fill_beat": 16.0, "commit_beat": 16.0}
	_check("a marked note does not change on the way", accents.kind_of(made[2]) == K.ACCENT)
	Music._plan = {}
	# entering fever on beat 24: only the note on that bar line is the rainbow one
	Music.change_planned.emit("fever", 0, 24.0, 24.0)
	_check("the note that enters fever is the rainbow one", accents.kind_of(made[7]) == K.FEVER and accents.look(made[7], Color.WHITE).rainbow)
	_check("the note after it is not", accents.kind_of(made[8]) == K.NONE and accents.kind_of(made[6]) == K.DOWNBEAT)
	Music.fever = true
	_check("nor are the other notes in fever", accents.kind_of(made[8]) == K.NONE)
	Music.fever = false
	Music.fever_ended.emit()
	accents.notes = section.own_notes()
	# let the rings draw for a while (a script error in the drawing code would show here)
	await create_timer(1.0).timeout

	# --- the count-in: called on a bar line, as the music does ---
	while fposmod(Conductor.song_beat, 4.0) > 0.1:
		await process_frame
	Music.count_in()
	var from := roundf(Conductor.song_beat / 4.0) * 4.0
	var seen := {}
	while Conductor.song_beat < from + 4.6:
		await process_frame
		var label: Label = count._label
		if label.visible:
			var i := floori(Conductor.song_beat - from)
			seen[i] = label.text
	_check("count-in shows a word on each of the four beats", seen == {0: "READY", 1: "3", 2: "2", 3: "1"}, str(seen))
	_check("count-in is gone after the bar", not count._label.visible)
	print("LEVEL1_MUSIC_FX_%s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit()
