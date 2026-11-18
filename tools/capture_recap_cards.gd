extends SceneTree
## 给 SPACE PIZZA 结尾虫洞里的回顾画面截图：前面几关各截一张（不带 HUD），存成
## stages/space_pizza/recap/card_1.png ...（480x360）。前面的关改了样子之后重新跑一遍。要开窗口跑：
##   godot --path . --script res://tools/capture_recap_cards.gd
## 跑完再跑一次 godot --path . --headless --import 让新图导入。

## [第几大关（0 起）, 第几小关, 开始后等几秒, 积累条拨到百分之几（0 = 不拨）]
const SHOTS := [
	[0, 0, 9.0, 0.0],   # DISCO
	[1, 0, 9.0, 0.5],   # SKY
	[2, 0, 9.0, 0.0],   # TV WALL 洗衣机
	[2, 2, 7.0, 0.5],   # 拍地球
	[3, 0, 9.0, 0.5],   # 太空打飞机
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	load("res://scripts/main.gd").in_run = false
	var dir := ProjectSettings.globalize_path("res://stages/space_pizza/recap/")
	DirAccess.make_dir_recursive_absolute(dir)
	for i in SHOTS.size():
		var s: Array = SHOTS[i]
		Levels.selected = int(s[0])
		change_scene_to_file(Levels.GAME_SCENE)
		await create_timer(1.0).timeout
		var game := current_scene
		game.start_from(int(s[1]))
		await create_timer(float(s[2]) * 0.5).timeout
		if float(s[3]) > 0.0:
			game.gauge.set_value(int(game.gauge.max_value * float(s[3])))
			game.gauge.fire_passed_events()
		await create_timer(float(s[2]) * 0.5).timeout
		game.hud.visible = false
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.resize(480, 360, Image.INTERPOLATE_LANCZOS)
		img.save_png(dir + "card_%d.png" % (i + 1))
		print("  saved card_%d.png  (level %d section %d)" % [i + 1, s[0], s[1]])
	print("CAPTURE_RECAP_CARDS_DONE")
	quit()
