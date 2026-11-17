extends SceneTree
## 暂停转盘：godot --path . --script res://tools/test_pause_menu.gd （要开窗口跑，无头模式下音频不走，测不出时钟）
## 测：暂停时节拍时钟和音乐停住、继续后从停的地方接着走（不跳）；倒数时暂停也一样；
## RESUME / PLAY 跟着转盘变；继续时翻过的关被还原；设置面板开着时 Esc 只关面板。

var _pause: Node


func _initialize() -> void:
	call_deferred("_run")


func _esc() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.physical_keycode = KEY_ESCAPE
	e.pressed = true
	root.push_input(e)
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	root.push_input(up)


func _start_level(i: int) -> void:
	Levels.selected = i
	load("res://scripts/main.gd").reset_run()
	change_scene_to_file(Levels.GAME_SCENE)
	await process_frame
	await process_frame
	_pause = null
	for c in current_scene.get_children():
		if c.get_script() and c.get_script().resource_path.ends_with("pause_menu.gd"):
			_pause = c
	assert(_pause != null, "main has a pause menu")


func _run() -> void:
	var conductor: Node = root.get_node("Conductor")

	# ---- 正在放音乐时暂停（第 3 关：第 1 关开头要先摸猫，音乐不会自己开始） ----
	await _start_level(2)
	var t0 := Time.get_ticks_msec()
	while not (conductor.playing and not conductor.get("_waiting")) and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	await create_timer(2.0).timeout
	assert(conductor.playing and not conductor.get("_waiting"), "music is running")
	var player := conductor.get("_player") as AudioStreamPlayer
	var gap_before: float = conductor.song_time - player.get_playback_position()
	_esc()
	await process_frame
	assert(paused, "Esc pauses")
	var song_at_pause: float = conductor.song_time
	var pos_at_pause := player.get_playback_position()
	await create_timer(2.0).timeout  # 测试的计时器暂停时也走（process_always）
	assert(absf(conductor.song_time - song_at_pause) < 0.001, "clock stands still while paused")
	assert(absf(player.get_playback_position() - pos_at_pause) < 0.05, "music stands still while paused: %.3f -> %.3f" % [pos_at_pause, player.get_playback_position()])

	var menu: Node = _pause.get("_menu")
	assert(menu != null and menu.pause_level == 2)
	await create_timer(1.0).timeout  # 开场动画放完才收按键
	var play := menu.get_node("MenuActions/Play") as Button
	assert(play.text == "RESUME", "button says RESUME on the level being played")
	menu.turn(1)
	assert(Levels.selected == 3 and play.text == "PLAY", "turning to another level says PLAY")
	menu.turn(-1)
	assert(play.text == "RESUME")
	menu.turn(1)
	menu.turn(1)
	# 设置面板：Esc 只关面板，暂停转盘还在
	menu.open_settings()
	await create_timer(0.3).timeout
	assert(menu.is_busy(), "settings open in pause")
	_esc()
	await create_timer(0.4).timeout
	assert(not menu.is_busy(), "Esc closes the settings panel")
	assert(_pause.get("_menu") == menu and paused, "...and the pause menu stays")
	# Esc 继续：翻过的关还原
	_esc()
	await create_timer(1.6).timeout  # 退场动画
	assert(not paused, "Esc resumes")
	assert(Levels.selected == 2, "the level browsed in the pause menu is restored: %d" % Levels.selected)
	var song_after: float = conductor.song_time
	assert(song_after - song_at_pause < 1.9 and song_after - song_at_pause > 0.0,
			"clock goes on from where it stopped (moved %.2f s in the 1.6 s since resume)" % (song_after - song_at_pause))
	# 时钟和音乐对得上：比较“时钟 − 音频位置”在暂停前后差多少（音频位置按混音块跳，给 0.06 s 余量）
	await create_timer(1.0).timeout
	var gap_after: float = conductor.song_time - player.get_playback_position()
	var drift := absf(gap_after - gap_before)
	assert(drift < 0.06, "clock and music stay together after resume (drift %.3f s)" % drift)
	print("  playing: paused 3 s, after resume clock +%.2f s in 1.6 s, clock-vs-music drift %.3f s" % [song_after - song_at_pause, drift])

	# ---- RESUME 按钮 ----
	_esc()
	await create_timer(1.0).timeout
	menu = _pause.get("_menu")
	menu.start()
	await create_timer(1.6).timeout
	assert(not paused and _pause.get("_menu") == null, "RESUME resumes")

	# ---- 倒数（音乐还没开始）时暂停 ----
	await _start_level(3)
	await create_timer(0.3).timeout
	if conductor.playing and conductor.get("_waiting"):
		_esc()
		await process_frame
		var wait_at: float = conductor.song_time
		await create_timer(2.0).timeout
		_esc()
		await create_timer(0.1).timeout
		assert(conductor.song_time - wait_at < 1.0, "count-in does not jump after a pause (+%.2f s)" % (conductor.song_time - wait_at))
		print("  count-in: after resume clock +%.2f s" % (conductor.song_time - wait_at))
	else:
		print("  count-in: level 4 was not in its count-in at 0.3 s, skipped")

	print("PAUSE_MENU_PASS: clock and music hold while paused and resume in step, RESUME/PLAY, level restored, settings Esc")
	quit()
