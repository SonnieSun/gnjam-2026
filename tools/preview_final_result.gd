extends SceneTree
## 看最后一关的结尾：从披萨段开始，过 3 秒按调试键 N 把积累条加满，截三张图：
## 最后一下的大字（ALL CLEAR）、结算刚弹进来、结算全部弹完。要开窗口跑：
##   godot --path . --script res://tools/preview_final_result.gd -- <输出目录>
## 不写输出目录就存到 user://。

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


func _run() -> void:
	load("res://scripts/main.gd").in_run = false
	Levels.selected = Levels.count() - 1
	change_scene_to_file(Levels.GAME_SCENE)
	await create_timer(0.8).timeout
	var game := current_scene
	game.start_from(1)  # SPACE PIZZA
	await create_timer(3.0).timeout
	# 调试键 N：积累条直接加满（main.gd）
	var n := InputEventKey.new()
	n.keycode = KEY_N
	n.physical_keycode = KEY_N
	n.pressed = true
	root.push_input(n)
	var hud: Node = game.hud
	var t0 := Time.get_ticks_msec()
	while hud.get("_stamp") == null and Time.get_ticks_msec() - t0 < 40000:
		await process_frame
	await create_timer(0.35).timeout
	await _shot("final_pop.png")
	while not hud.result_label.visible and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	await create_timer(0.25).timeout
	await _shot("result_enter.png")
	await create_timer(5.5).timeout
	await _shot("result.png")
	print("  music bus effects: ", AudioServer.get_bus_effect_count(AudioServer.get_bus_index(&"Music")))
	print("PREVIEW_FINAL_RESULT_DONE")
	quit()
