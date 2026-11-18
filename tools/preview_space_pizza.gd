extends SceneTree
## 看 SPACE PIZZA 一整段：自动打（每个音符到点按一下，结尾连按每个八分按一下），每换一个镜头截一张图，
## 打印每个镜头的名字、拍数、套的特效，以及三套谱面从哪一拍起、那首曲子从哪一拍起。要开窗口跑：
##   godot --path . --script res://tools/preview_space_pizza.gd -- <输出目录> [fast]
## fast = 开头直接把积累条拨到 45%（少等开头那一段）。不写输出目录就存到 user://。

var _out := "user://"
var _fast := false
var _n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0].trim_suffix("/") + "/"
	_fast = args.has("fast")
	call_deferred("_run")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(640, 480, Image.INTERPOLATE_BILINEAR)
	img.save_png(_out + name)


func _press() -> void:
	for down in [true, false]:
		var ev := InputEventAction.new()
		ev.action = "hit"
		ev.pressed = down
		Input.parse_input_event(ev)


func _run() -> void:
	load("res://scripts/main.gd").in_run = false
	Levels.selected = Levels.count() - 1
	change_scene_to_file(Levels.GAME_SCENE)
	await create_timer(0.8).timeout
	var game := current_scene
	var Conductor := root.get_node("Conductor")
	var Music := root.get_node("Music")
	game.start_from(1)  # SPACE PIZZA
	await process_frame
	if _fast:
		game.gauge.set_value(int(game.gauge.max_value * 0.45))
	var last_shot := {}
	var last_pressed: NoteData = null
	var last_mash := -1.0
	var mid_at := -1.0
	var done_at := -1
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 200000:
		await process_frame
		var sec: Node = game._current
		if sec == null:
			continue
		var beat: float = Conductor.input_beat()
		# 自动打
		for n: NoteData in sec.notes:
			if n.beat > beat:
				break
			if not n.judged and not n.free and n != last_pressed:
				last_pressed = n
				_press()
				break
		if not is_inf(sec.ending_from) and beat >= sec.ending_from and beat < sec.ending_from + 8.0:
			var slot := floorf(beat * 2.0)
			if slot != last_mash:
				last_mash = slot
				_press()
		# 每换一个镜头：打印 + 截图（镜头中间再截一张）
		var shot: Dictionary = sec._shot
		if not is_same(shot, last_shot):
			last_shot = shot
			_n += 1
			mid_at = (sec._shot_from + minf(sec._shot_to, sec._shot_from + 8.0)) / 2.0
			print("  shot %02d  beat %.1f  %s / %s  fx=%s  gauge=%d/%d  tunes=%s cc@%.0f cca@%.0f ccb@%.0f" % [
					_n, Conductor.song_beat, sec._mode, shot.get("id", "?"), shot.get("fx", ""),
					game.gauge.value, game.gauge.max_value, Music.tunes_playing(),
					Music.tune_origin("cc"), Music.tune_origin("cca"), Music.tune_origin("ccb")])
			await create_timer(0.12).timeout
			await _shot("pizza_%02d_%s_%s_a.png" % [_n, sec._mode, shot.get("id", "x")])
		elif mid_at >= 0.0 and Conductor.song_beat >= mid_at:
			mid_at = -1.0
			await _shot("pizza_%02d_%s_%s_b.png" % [_n, sec._mode, shot.get("id", "x")])
		if game._cleared and done_at < 0:
			done_at = Time.get_ticks_msec()
		if done_at >= 0 and Time.get_ticks_msec() - done_at > 3000:
			break
	await _shot("pizza_result.png")
	print("  charge=%d  cleared=%s  counts=%s" % [game._current._charge, game._cleared, game.judge.counts])
	print("PREVIEW_SPACE_PIZZA_DONE")
	quit()
