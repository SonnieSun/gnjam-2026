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
	# --- the change note is added when the chart has no note on the beat the new part comes in ---
	accents.notes = section.own_notes()
	game.judge._generate()   # the judge is switched off in this test: lay the notes out as far as it would have
	var free_beat := ceilf(Conductor.song_beat) + 3.0
	while section.notes.any(func(n: NoteData) -> bool: return absf(n.beat - free_beat) < 0.5):
		free_beat += 1.0
	var count_before: int = game.judge.notes.size()
	Music.change_planned.emit("fever", 0, free_beat, free_beat)
	for i in 4:
		await process_frame
	var added: Array = section.notes.filter(func(n: NoteData) -> bool: return is_equal_approx(n.beat, free_beat))
	_check("no note on the change beat: one is added there", added.size() == 1 and game.judge.notes.has(added[0]), "beat %s" % free_beat)
	var order: Array = game.judge.notes.map(func(n: NoteData) -> float: return n.beat)
	var order_sorted := order.duplicate()
	order_sorted.sort()
	_check("the judge's notes are still in order", order == order_sorted)
	_check("the added note is the rainbow change note", added.size() == 1 and accents.look(added[0], Color.WHITE).rainbow)
	# hitting it plays its own sound; hitting any other note does not
	var other: NoteData = section.notes.filter(func(n: NoteData) -> bool: return n.beat > free_beat + 0.6)[0]
	game.judge.note_judged.emit(other, NoteData.Result.PERFECT, 0.0)
	_check("an ordinary note has no change-note sound", not accents._sfx.playing)
	game.judge.note_judged.emit(added[0], NoteData.Result.PERFECT, 0.0)
	_check("hitting the change note plays its own sound", accents._sfx.playing and accents._sfx.stream.resource_path.ends_with("fever_note.wav"))
	# a change on a beat that has a note: nothing is added
	var taken: float = section.notes.filter(func(n: NoteData) -> bool: return n.beat > free_beat + 1.0)[0].beat
	var size_now: int = game.judge.notes.size()
	Music.change_planned.emit("fever", 0, taken, taken)
	for i in 4:
		await process_frame
	var on_taken: Array = game.judge.notes.filter(func(n: NoteData) -> bool: return is_equal_approx(n.beat, taken))
	_check("a note already on the change beat: nothing added, it is the change note", on_taken.size() == 1 and accents.look(on_taken[0], Color.WHITE).rainbow, "beat %s" % taken)
	Music.fever_ended.emit()

	# --- fever: the colour filter comes up, the corner cannons fire, a clap fires a small pair, then it all goes ---
	var fx: Node = section.get_node("FeverFx")
	Music.events.set_process(false)   # only the claps this test sends: the music's own would fire cannons too
	Music.fever_started.emit()
	await create_timer(0.4).timeout
	_check("fever: the level-up sound plays as it starts", fx._sfx.playing and fx._sfx.stream.resource_path.ends_with("fever_enter.wav"))
	_check("fever: filter on, both big cannons and the rain going", fx._rect.visible and fx._level > 0.9
			and fx._big[0].emitting and fx._big[1].emitting and fx._rain[0].emitting and fx._rain[1].emitting)
	Music.drum_clap.emit(Conductor.song_beat)
	await process_frame
	_check("fever: a clap fires one small cannon on each side", fx._small[0].emitting and fx._small[1].emitting and not fx._small[2].emitting)
	Music.fever_ended.emit()
	await create_timer(0.9).timeout
	_check("fever over: filter gone, rain stopped", not fx._rect.visible and not fx._rain[0].emitting)
	Music.drum_clap.emit(Conductor.song_beat)
	await process_frame
	_check("no fever: a clap fires nothing", not fx._small[2].emitting)
	print("LEVEL1_MUSIC_FX_%s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit()
