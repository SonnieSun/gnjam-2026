extends SceneTree
## 看原生像素（RetroScreen 的 360 线取样）在各处是什么样：主菜单、四关开头、第 4 关披萨段、最后一关的结算，各截一张。
## 要开窗口跑：
##   godot --path . --script res://tools/preview_native_pixels.gd -- <输出目录> [off]
## 最后写 off 就是关着原生像素截（对比用）。

var _out := "user://"
var _tag := "native"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0].trim_suffix("/") + "/"
	if args.size() > 1 and args[1] == "off":
		_tag = "off"
	call_deferred("_run")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s%s_%s.png" % [_out, _tag, name])
	print("  saved ", name)


func _level(index: int, from_section: int, seconds: float) -> Node:
	Levels.selected = index
	change_scene_to_file(Levels.GAME_SCENE)
	await create_timer(0.8).timeout
	var game := current_scene
	game.start_from(from_section)
	await create_timer(seconds).timeout
	return game


func _run() -> void:
	var retro := root.get_node("RetroScreen")
	retro.set_native(_tag == "native")
	print("  window ", root.size, ", native pixel = ", retro.pixel_scale(), " window px")
	load("res://scripts/main.gd").in_run = false
	change_scene_to_file(Levels.MENU_SCENE)
	await create_timer(2.0).timeout
	await _shot("menu")
	for i in Levels.count():
		await _level(i, 0, 5.0)
		await _shot("level_%d" % (i + 1))
	var game := await _level(Levels.count() - 1, 1, 4.0)
	await _shot("pizza")
	var n := InputEventKey.new()
	n.keycode = KEY_N
	n.physical_keycode = KEY_N
	n.pressed = true
	root.push_input(n)
	var t0 := Time.get_ticks_msec()
	while not game.hud.result_label.visible and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	await create_timer(5.5).timeout
	await _shot("result")
	print("PREVIEW_NATIVE_PIXELS_DONE")
	quit()
