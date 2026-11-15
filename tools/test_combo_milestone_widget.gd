extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	change_scene_to_file(Levels.GAME_SCENE)
	await create_timer(1.0).timeout
	var game := current_scene
	game.judge.set_process(false)
	var hud = game.hud
	var popup: ComboMilestoneWidget = hud.milestone_label
	assert(not popup.visible)
	assert(game.judge.COMBO_MILESTONES == [10,20,50,100,200,300,400,500])
	var before_score: int = hud.score_label.value
	var before_combo: int = hud.combo_label.value
	for pair in [[1,0],[9,0],[10,1],[19,1],[20,2],[29,2],[30,3],[39,3],[40,4],[49,4],[50,5],[100,5],[500,5],[99999,5]]:
		hud.show_combo_milestone(pair[0])
		assert(popup.value == pair[0] and popup.number.text == str(pair[0]))
		assert(popup.color_stage == pair[1])
		assert(popup.scale.is_equal_approx(Vector2.ONE*.55))
		assert(popup.opacity == 1.0 and popup.visible)
		assert(popup.word.position.x < popup.number.position.x)
		assert(popup.word.size.y < 52 and popup.word.size.y > 35)
		assert(popup.content.position.x+popup.content.size.x*popup.content.scale.x <= popup.size.x+.01)
		assert(hud.score_label.value == before_score and hud.combo_label.value == before_combo)
	# The real Judge does not emit at 30 or 40.
	var emitted: Array[int] = []
	game.judge.combo_milestone.connect(func(n: int) -> void: emitted.append(n))
	for amount in [10,20,30,40,50,100]:
		game.judge.combo=amount-1
		game.judge._apply(NoteData.new(),NoteData.Result.PERFECT,0.0)
	assert(emitted == [10,20,50,100])
	hud.reset()
	assert(not popup.visible and popup.opacity == 0.0)
	hud.show_combo_milestone(10)
	await create_timer(.08).timeout
	assert(popup.scale.x > .55 and popup.scale.x < 1.13)
	hud.show_combo_milestone(20)
	assert(popup.scale.is_equal_approx(Vector2.ONE*.55) and popup.opacity == 1)
	assert(popup.value == 20 and popup.color_stage == 2)
	await create_timer(.17).timeout
	assert(popup.scale.x > 1.05)
	await create_timer(.14).timeout
	assert(popup.scale.is_equal_approx(Vector2.ONE))
	await create_timer(1.1).timeout
	assert(popup.opacity > 0 and popup.opacity < 1)
	assert(is_equal_approx(popup.opacity,popup.palette_material.get_shader_parameter("opacity")))
	await create_timer(.4).timeout
	assert(not popup.visible and is_zero_approx(popup.opacity))
	hud.show_combo_milestone(50)
	await create_timer(.05).timeout
	hud.reset()
	await create_timer(.3).timeout
	assert(not popup.visible and popup.opacity == 0 and popup.scale == Vector2.ONE)
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://docs/combo_milestone")
		for amount in [10,20,50,100,500]:
			hud.show_combo_milestone(amount)
			await create_timer(.32).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://docs/combo_milestone/combo_%d.png" % amount)
		# Actual frame sequence for a short animation preview.
		hud.show_combo_milestone(20)
		for i in 35:
			await create_timer(.05).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://docs/combo_milestone/frame_%02d.png" % i)
	print("COMBO_MILESTONE_PASS: palette boundaries, horizontal layout, long values, unchanged nodes, pop, restart, fade, reset")
	quit()
