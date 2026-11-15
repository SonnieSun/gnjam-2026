extends SceneTree
## Run with Godot --path <project> --script res://tools/test_candy_menu.gd.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	change_scene_to_file("res://scenes/menu.tscn")
	await create_timer(1.0).timeout
	var menu := current_scene
	var labels := menu.get_node("Disc3D/View/Viewport/Stage/Labels")
	var font := load("res://assets/fonts/candy_gem/CandyGem.fnt") as Font
	for word in ["DISCO", "SPACESHIP", "ORBIT CAT", "TV WALL", "WASHING MACHINE", "1 2 3 4 5 STAGES"]:
		for c in word:
			assert(font.has_char(c.unicode_at(0)), "Missing glyph: " + c)
	for i in Levels.count():
		var chart := load(Levels.paths()[i]) as SongChart
		var title: Label3D = labels.get_node("Item%d/Anchor/Title" % (i + 1))
		var sub: Label3D = labels.get_node("Item%d/Anchor/Sub" % (i + 1))
		assert(title.text == chart.title.to_upper())
		assert(sub.text.begins_with(str(chart.sections.size()) + " "))
		assert(title.font == font)
		assert(title.get_script() == null and sub.get_script() == null)
		assert(title.modulate.a == 1.0 and sub.modulate.a == 1.0)
		assert(sub.font_size == 100)
		assert(title.font_size > 110)
		if i > 0:
			menu.turn(1)
			await create_timer(0.5).timeout
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://docs/menu_candy_level_%d.png" % (i + 1))
	menu.turn(1)
	await create_timer(0.5).timeout
	assert(Levels.selected == 0)
	menu.turn(1)
	await create_timer(0.5).timeout
	assert(Levels.selected == 1)
	menu.turn(-1)
	await create_timer(0.5).timeout
	assert(Levels.selected == 0)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/menu_candy_preview.png")
	menu.get_node("MenuActions/Play").pressed.emit()
	await create_timer(2.0).timeout
	assert(current_scene.scene_file_path == Levels.GAME_SCENE)
	var hud := current_scene.get_node("HUD")
	for label in [hud.judge_label, hud.milestone_label]:
		assert(label.get_theme_font("font") != font)
	assert(hud.score_label is ScoreComboWidget and hud.combo_label is ScoreComboWidget)
	current_scene.get_tree().change_scene_to_file(Levels.MENU_SCENE)
	await create_timer(0.5).timeout
	assert(current_scene.scene_file_path == Levels.MENU_SCENE)
	print("CANDY_MENU_PASS: enlarged five titles/counts, selection, PLAY, original HUD fonts, return")
	quit()
