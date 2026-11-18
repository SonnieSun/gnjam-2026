extends SceneTree
## 看片尾一整条：最后一关按 N 加满 → 结算 → 按 NEXT 进字幕（康康舞曲淡出、片尾曲开始）→ 字幕停住、出「按空格」→ 按空格回主菜单。
## 截两张图：字幕滚到一半、停住出提示之后；一路打印音乐总线音量和片尾曲在不在放。要开窗口跑（大约一分钟）：
##   godot --path . --script res://tools/preview_credits_end.gd -- <输出目录>

var _out := "user://"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0].trim_suffix("/") + "/"
	call_deferred("_run")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out + name)
	print("  saved ", _out + name)


func _key(code: Key) -> void:
	for down in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = down
		root.push_input(k)
		await process_frame


func _bus_db() -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music"))


func _run() -> void:
	load("res://scripts/main.gd").in_run = false
	Levels.selected = Levels.count() - 1
	change_scene_to_file(Levels.GAME_SCENE)
	await create_timer(0.8).timeout
	var game := current_scene
	game.start_from(1)
	await create_timer(3.0).timeout
	await _key(KEY_N)
	var hud: Node = game.hud
	var t0 := Time.get_ticks_msec()
	while not hud.result_label.visible and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	await create_timer(2.0).timeout
	print("  result up, music bus %.1f dB, conductor playing %s" % [_bus_db(), get_root().get_node("Conductor").playing])
	hud.result_label.next_pressed.emit()
	while current_scene == null or current_scene.scene_file_path != "res://scenes/credits.tscn":
		await process_frame
	var credits := current_scene
	for i in 6:
		await create_timer(0.3).timeout
		var song: AudioStreamPlayer = credits.get("_song")
		print("  credits +%.1fs: bus %.1f dB, conductor %s, song playing %s at %.2f" % [(i + 1) * 0.3, _bus_db(),
				get_root().get_node("Conductor").playing, song.playing, song.get_playback_position()])
	await create_timer(12.0).timeout
	await _shot("credits_mid.png")
	while float(credits.get("_done_for")) < float(credits.get("prompt_after")) + 1.0:
		await process_frame
	var song2: AudioStreamPlayer = credits.get("_song")
	print("  stopped: song at %.2f s (lands at %.2f), prompt alpha %.2f" % [song2.get_playback_position(),
			float(credits.get("crawl_seconds")), (credits.get_node("Prompt") as Label).modulate.a])
	await _shot("credits_end.png")
	await create_timer(4.0).timeout
	print("  still on credits after waiting: ", current_scene == credits)
	await _key(KEY_SPACE)
	await create_timer(1.2).timeout
	print("  after Space: scene ", current_scene.scene_file_path if current_scene else "none", ", bus %.1f dB" % _bus_db())
	print("PREVIEW_CREDITS_END_DONE")
	quit()
