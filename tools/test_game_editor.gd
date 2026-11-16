extends SceneTree
## Headless check of what the in-game editor panel (Tab) got for the rhythm work: the length of a phase and the
## settings of the rhythm components, both kept in the level file's section (SectionDef.phase_gain / fever_gain / fx).
## Nothing is saved to disk here.
##   godot --headless -s tools/test_game_editor.gd       (about 10 seconds)

var _fail := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_fail += 1
	print("  %s  %s  %s" % ["ok" if ok else "NO", what, detail])


func _run() -> void:
	var main_script = load("res://scripts/main.gd")
	main_script.in_run = false
	Levels.selected = 0
	change_scene_to_file(Levels.GAME_SCENE)
	await create_timer(0.6).timeout
	var game = current_scene
	game.start_from(0)
	game.judge.set_process(false)
	await create_timer(0.3).timeout
	game.toggle_editor()
	await process_frame
	var ed = game._editor
	var def = game.chart.sections[0]

	# the Rhythm page lists the components of this stage's scene
	var heads := []
	var controls := 0
	for c in ed._rhythm_box.get_children():
		if c is Label:
			heads.append((c as Label).text.get_slice("  ", 0))
		else:
			controls += c.get_child_count()
	_check("the Rhythm page lists the four components of level 1", heads == ["CatBounce", "NoteAccents", "CountInDisplay", "FeverFx"], str(heads))
	_check("with a control for each of their switches, numbers and colours", controls > 40, "%d controls" % controls)

	# changing one applies at once, is recorded for saving, and is applied again when the stage restarts
	var bounce: Node = game._current.get_node("CatBounce")
	ed._set_fx("CatBounce", "squash", 0.3)
	ed._set_fx("NoteAccents", "accent", false)
	_check("a change applies at once and is recorded in the stage's definition", is_equal_approx(bounce.squash, 0.3)
			and not game._current.get_node("NoteAccents").accent and def.fx == {"CatBounce": {"squash": 0.3}, "NoteAccents": {"accent": false}} and ed.dirty, str(def.fx))
	game.start_from(0)
	game.judge.set_process(false)
	await create_timer(0.3).timeout
	_check("it is applied again when the stage is entered", is_equal_approx(game._current.get_node("CatBounce").squash, 0.3))

	# the length of a phase
	_check("level 1's stretched phases come from the level file", is_equal_approx(def.phase_gain[3], 0.42) and is_equal_approx(def.fever_gain, 0.47))
	ed._load_section()
	ed._select_phase(1)
	ed._phase_gain.value = 0.5
	_check("Length on the Phases page writes the selected phase's number", is_equal_approx(def.phase_gain[1], 0.5), str(def.phase_gain))
	_check("and says how many hits that is", ed._phase_len.text.begins_with("= 8 perfect hits"), ed._phase_len.text)
	game.gauge.set_value(20)
	game.gauge.fire_passed_events()
	_check("the gauge uses it once the phase is reached", is_equal_approx(game.gauge.gain_scale, 0.5), "x%s" % game.gauge.gain_scale)
	var before: int = game.gauge.value
	for i in 4:
		game.gauge.apply(NoteData.Result.PERFECT)
	_check("four perfect hits there are worth two", game.gauge.value - before == 10, "+%d" % (game.gauge.value - before))
	print("GAME_EDITOR_%s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit()
