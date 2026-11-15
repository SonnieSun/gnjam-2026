extends SceneTree
## Smoke-test the upstream level flow after merging the custom UI branch.
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var main_script = load("res://scripts/main.gd")
	main_script.in_run=false
	for index in Levels.count():
		Levels.selected=index
		change_scene_to_file(Levels.GAME_SCENE)
		await create_timer(.6).timeout
		var game=current_scene
		game.judge.set_process(false)
		for section_index in game.chart.sections.size():
			game.start_from(section_index)
			game.judge.set_process(false)
			await create_timer(.15).timeout
			assert(game._current != null)
			game.hud.set_stats(10000,50)
			game.hud.show_combo_milestone(50)
			assert(game.hud.score_label.color_stage==5)
		print("MERGE_LEVEL_PASS ",index," sections=",game.chart.sections.size())
	change_scene_to_file(Levels.MENU_SCENE)
	await create_timer(.5).timeout
	assert(current_scene._sectors.size()==Levels.count())
	print("MERGED_FLOW_PASS: every current chart/section enters, custom HUD remains connected, menu count matches")
	quit()
