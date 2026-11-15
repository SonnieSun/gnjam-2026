extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Exact boundaries, immediately below boundaries, and empty playthrough.
	for spec in [[10000,100,"S"],[9500,100,"S"],[9499,100,"A"],[8500,100,"A"],[8499,100,"B"],[7000,100,"B"],[6999,100,"C"],[0,100,"C"],[0,0,"C"],[19000,200,"S"]]:
		assert(ResultWidget.rank_for(spec[0],spec[1]) == spec[2])
	DirAccess.make_dir_recursive_absolute("res://docs/result_grades")
	Levels.selected=0
	var game_script = load("res://scripts/main.gd")
	game_script.in_run = false
	change_scene_to_file(Levels.GAME_SCENE)
	await create_timer(0.8).timeout
	var game := current_scene
	game.judge.set_process(false)
	var judge=game.judge
	# Plausible 100-note performances with the game's actual 100/80/50 scoring.
	for spec in [[90,10,0,0,9800,"S"],[70,10,10,10,8300,"B"],[75,10,10,5,8800,"A"],[40,10,10,40,5300,"C"]]:
		judge._stage_weight=0.0 # Fixture already represents a banked stage.
		judge.possible=10000.0
		judge.counts={NoteData.Result.PERFECT:spec[0],NoteData.Result.GREAT:spec[1],NoteData.Result.GOOD:spec[2],NoteData.Result.MISS:spec[3]}
		judge.score=spec[4]
		judge.max_combo=60
		judge.hit_offsets.clear()
		judge.hit_offsets.append(-0.012)
		game.hud.set_stats(judge.score,12)
		game.hud.show_judgement(NoteData.Result.PERFECT,0.0)
		game._clear_level()
		var result: ResultWidget=game.hud.result_label
		assert(result.visible and result.grade==spec[5])
		assert(result.grade_art.texture==ResultWidget.GRADES[spec[5]])
		assert(is_equal_approx(result.accuracy,float(spec[4])/10000.0))
		assert(not game.hud.judgement_art.visible)
		assert(result.stats.text.contains(str(spec[4])))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://docs/result_grades/%s.png" % spec[5])
		game.hud.reset()
		assert(not result.visible)
	game.start_from(0)
	assert(not game.hud.result_label.visible)
	game.back_to_menu()
	await create_timer(0.5).timeout
	assert(current_scene.scene_file_path==Levels.MENU_SCENE)
	print("RESULT_WIDGET_PASS: boundaries, empty/looped runs, all grades, statistics, clear/reset/restart/menu")
	quit()
