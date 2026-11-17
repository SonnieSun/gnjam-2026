extends SceneTree
## Headless check of the beat editor (scenes/tools/kisa/beat_editor.tscn): opens every level in its list (the
## interlude levels too), every section and every play phase, plays each for a moment, and looks at what the
## timeline is given to draw. A script error anywhere shows in the output.
##   godot --headless -s tools/test_beat_editor.gd       (about 20 seconds)

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
	change_scene_to_file("res://scenes/tools/kisa/beat_editor.tscn")
	await create_timer(0.5).timeout
	var ed = current_scene
	var names := []
	for i in ed._level_pick.item_count:
		names.append(ed._level_pick.get_item_text(i).strip_edges())
	_check("the level list has the sky level", ed._paths.has("res://levels/level_2_sky.tres"), str(names))
	var opened := 0
	for level in ed._paths.size():
		ed._open_level(level)
		for section in ed._song.sections.size():
			ed._open_section(section)
			for ph: Dictionary in ed._phases:
				ed._open_phase(ph.id)
				ed._marks()
				ed._toggle_play()
				await create_timer(0.25).timeout
				ed._toggle_play()
				opened += 1
				print("     %s / %s / %s: %d notes in %d bars, groove '%s', tune '%s'" % [
						ed._paths[level].get_file().get_basename(), ed._song.sections[section].title, ph.name,
						ed.pattern.notes.size(), int(ed.pattern.length_beats / 4.0),
						Music.events.groove_of(Music.playing_clip("beat")), Music.events.song_of(Music.playing_clip("lead"))])
	_check("every level, section and phase opens and plays", opened >= 10, "%d opened" % opened)

	# level 1, the road: the chart starts a bar into The Entertainer, and every note is on a kick or a clap
	ed._open_level(ed._paths.find("res://levels/level_1_disco.tres"))
	ed._open_phase("road")
	_check("the road's chart starts on bar 2 of the tune", is_equal_approx(ed._tune_offset(), 4.0) and is_equal_approx(Music.tune_origin("ent"), -4.0),
			"tune origin %s" % Music.tune_origin("ent"))
	var groove: Dictionary = Music.events.groove(Music.events.groove_of(Music.playing_clip("beat")))
	var off := 0
	for d: Dictionary in ed.pattern.notes:
		var step := fposmod(float(d.beat), 4.0) * 4.0
		if not (step in groove.kick or step in groove.clap):
			off += 1
	_check("the road is drawn over the club groove, every note on one of its hits", Music.playing_clip("beat") == "club" and off == 0, "%d off" % off)
	var marks: Dictionary = ed._marks()
	var cyan := 0
	for d: Dictionary in marks:
		if marks[d] == ed._accents.syncopated_color:
			cyan += 1
	_check("marks: the road has syncopation marks", cyan > 10, "%d of %d notes" % [cyan, ed.pattern.notes.size()])

	# the sky level's second phase is the tune itself
	ed._open_level(ed._paths.find("res://levels/level_2_sky.tres"))
	ed._open_phase("ode")
	_check("it opens on the music of the bright stage: Ode to Joy over the plain groove", Music.events.song_of(Music.playing_clip("lead")) == "ode_to_joy" and Music.playing_clip("beat") == "groove")
	_check("the sky level's bright phase is the Ode to Joy chart", ed.pattern.notes.size() == 62 and is_equal_approx(ed.pattern.length_beats, 64.0))
	print("BEAT_EDITOR_%s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit()
