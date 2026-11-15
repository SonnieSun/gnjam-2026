extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	change_scene_to_file(Levels.GAME_SCENE)
	await create_timer(1.0).timeout
	var game := current_scene
	game.judge.set_process(false)
	var hud = game.hud
	var score: ScoreComboWidget = hud.score_label
	var combo: ScoreComboWidget = hud.combo_label
	# Verify every requested value, synchronously before yielding a frame.
	for n in range(0,10001):
		score.set_value(n)
		assert(score.value == n and score.number.text == str(n))
		assert(score.color_stage == mini(n / 2000,5))
	for n in range(0,101):
		combo.set_value(n)
		assert(combo.value == n and combo.number.text == str(n))
		assert(combo.color_stage == mini(n / 10,5))
		assert(combo.visible == (n > 0))
	assert(score.palette_material != combo.palette_material)
	# Proportional advances follow the tight specimen instead of padded cells.
	var digit_font: Font = score.number.get_theme_font("font")
	assert(digit_font.get_string_size("11",HORIZONTAL_ALIGNMENT_LEFT,-1,64).x < digit_font.get_string_size("00",HORIZONTAL_ALIGNMENT_LEFT,-1,64).x)
	score.set_value(10000)
	combo.set_value(20)
	assert(score.number.get_theme_font_size("font_size") == combo.number.get_theme_font_size("font_size"))
	assert(score.number.get_theme_font_size("font_size") == 84)
	assert(score.title.position.y > score.number.position.y)
	assert(combo.number.get_theme_font_size("font_size") > combo.title.size.y*3.0)
	var original_judge_font: Font = hud.judge_label.get_theme_font("font")
	var original_result_font: Font = hud.result_label.get_theme_font("font")
	for pair in [[0,0],[1,1],[1999,9],[2000,10],[3999,19],[4000,20],[5999,29],[6000,30],[7999,39],[8000,40],[9999,49],[10000,50],[20000,100],[99999999,9999],[1,1]]:
		hud.set_stats(pair[0],pair[1])
		assert(score.number.text == str(pair[0]) and combo.number.text == str(pair[1]))
		assert(score.palette_material.get_shader_parameter("rainbow") == (pair[0] >= 10000))
		assert(combo.palette_material.get_shader_parameter("rainbow") == (pair[1] >= 50))
		assert(hud.judge_label.get_theme_font("font") == original_judge_font)
		assert(hud.result_label.get_theme_font("font") == original_result_font)
	hud.set_stats(10000,9)
	assert(score.color_stage == 5 and combo.color_stage == 0)
	hud.set_stats(1999,50)
	assert(score.color_stage == 0 and combo.color_stage == 5)
	# Test actual scoring signal path, not only the standalone widget setters.
	game.judge.score=1990
	game.judge.combo=9
	game.judge._apply(NoteData.new(),NoteData.Result.PERFECT,0.0)
	# Stage-weighted scoring leaves score unchanged until banking or a bonus.
	assert(score.value == 1990 and combo.value == 10)
	assert(score.color_stage == 0 and combo.color_stage == 1)
	game.judge.add_bonus(100)
	assert(score.value == 2090 and score.color_stage == 1)
	game.judge._apply(NoteData.new(),NoteData.Result.MISS,0.0)
	assert(combo.value == 0 and not combo.visible)
	hud.reset()
	await create_timer(1.2).timeout
	hud.set_stats(1999,9)
	var score_jumps := score.stage_jump_count
	var combo_jumps := combo.stage_jump_count
	hud.set_stats(2000,10)
	assert(score.stage_jump_count == score_jumps+1 and combo.stage_jump_count == combo_jumps+1)
	assert(score.number.text == "2000" and combo.number.text == "10")
	assert(score.color_stage == 1 and combo.color_stage == 1)
	await create_timer(0.06).timeout
	assert(score.visual.scale.x > 1.2 and combo.visual.scale.x > 1.2)
	assert(score.visual.position.y < 0 and combo.visual.position.y < 0)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/score_combo/stage_jump_peak.png")
	hud.set_stats(2100,11)
	assert(score.stage_jump_count == score_jumps+1 and combo.stage_jump_count == combo_jumps+1)
	await create_timer(0.5).timeout
	assert(score.visual.scale.is_equal_approx(Vector2.ONE) and combo.visual.position.is_equal_approx(Vector2.ZERO))
	hud.set_stats(10000,50)
	var rainbow_score_jumps := score.stage_jump_count
	var rainbow_combo_jumps := combo.stage_jump_count
	hud.set_stats(12000,60)
	assert(score.stage_jump_count == rainbow_score_jumps and combo.stage_jump_count == rainbow_combo_jumps)
	hud.set_stats(0,0)
	assert(score.visual.scale == Vector2.ONE and combo.visual.position == Vector2.ZERO)
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://docs/score_combo")
		for pair in [[1,1],[2000,10],[4000,20],[6000,30],[8000,40],[10000,50]]:
			hud.set_stats(pair[0],pair[1])
			await create_timer(0.5).timeout
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://docs/score_combo/stage_%d.png" % score.color_stage)
		# Player-window check: larger physical window must retain logical flake size.
		root.size=Vector2i(1920,1080)
		await process_frame
		await process_frame
		hud.set_stats(6000,30)
		await create_timer(0.5).timeout
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/score_combo/coarse_player_large.png")
	print("SCORE_COMBO_PASS: all values, exact boundaries, instant text/material, independent stages, reset, large values, Judge signals")
	quit()
