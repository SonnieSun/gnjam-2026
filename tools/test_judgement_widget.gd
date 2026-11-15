extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/judgements")
	Levels.selected = 0
	change_scene_to_file(Levels.GAME_SCENE)
	await create_timer(0.9).timeout
	var game := current_scene
	game.judge.set_process(false)
	var hud = game.hud
	var art: JudgementWidget = hud.judgement_art
	assert(not art.visible)
	for spec in [[NoteData.Result.PERFECT,0.0,"perfect"],[NoteData.Result.GREAT,-0.06,"great"],[NoteData.Result.GOOD,0.11,"good"],[NoteData.Result.MISS,0.14,"miss"]]:
		hud.show_judgement(spec[0],spec[1])
		assert(art.visible and not hud.judge_label.visible)
		assert(art.picture.texture == JudgementWidget.ART[spec[0]])
		assert(art.scale == Vector2.ONE and art.modulate == Color.WHITE)
		assert(art.picture.scale.is_equal_approx(Vector2.ONE * art.entry_scale))
		assert(art.timing.text == ("EARLY" if spec[2] == "great" else "LATE" if spec[2] == "good" else ""))
		if spec[2] == "perfect" and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://docs/judgements/pop_entry.png")
		await create_timer(0.05).timeout
		assert(art.picture.scale.x > art.entry_scale and art.picture.scale.x <= art.peak_scale + 0.001)
		assert(art.picture.position.distance_to(art._picture_rest) <= art.shake_pixels * 1.3)
		if spec[2] == "perfect" and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://docs/judgements/pop_growing.png")
		await create_timer(0.26).timeout
		assert(art.picture.scale.is_equal_approx(Vector2.ONE))
		assert(art.picture.position.is_equal_approx(art._picture_rest))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://docs/judgements/%s.png" % spec[2])
		await create_timer(0.15).timeout
		assert(art.visible and art.modulate.a == 1.0 and art.scale == Vector2.ONE)
	await create_timer(0.6).timeout
	assert(not art.visible)
	hud.show_judgement(NoteData.Result.GREAT,0.06)
	assert(art.timing.text == "LATE")
	await create_timer(0.4).timeout
	hud.show_judgement(NoteData.Result.PERFECT,0.0)
	await create_timer(0.4).timeout
	assert(art.visible) # Previous result must not clear the newer one.
	hud.show_note("LOOK: OFF")
	assert(not art.visible and hud.judge_label.visible)
	hud.show_judgement(NoteData.Result.MISS,0.0)
	hud.reset()
	assert(not art.visible)
	print("JUDGEMENT_WIDGET_PASS: four textures, timing, centered pop, bounded shake, settled transform, lifetime, replacement, reset")
	current_scene.queue_free()
	await process_frame
	await process_frame
	quit()
