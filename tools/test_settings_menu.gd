extends SceneTree
## 设置面板和主菜单：godot --headless --path . --script res://tools/test_settings_menu.gd
## 跑完会把 user://settings.cfg 还原成跑之前的样子。

const CFG := "user://settings.cfg"


func _initialize() -> void:
	call_deferred("_run")


func _press(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	root.push_input(e)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	root.push_input(up)


func _run() -> void:
	var backup := FileAccess.get_file_as_bytes(CFG) if FileAccess.file_exists(CFG) else PackedByteArray()
	var settings: Node = root.get_node("Settings")
	var conductor: Node = root.get_node("Conductor")

	# 总线
	assert(AudioServer.get_bus_index(&"Music") >= 0 and AudioServer.get_bus_index(&"SFX") >= 0, "Music / SFX buses")
	assert(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Music")) == &"Master")

	change_scene_to_file("res://scenes/menu.tscn")
	await create_timer(1.0).timeout
	var menu := current_scene
	# 播放器分到对的总线上
	assert((conductor.get("_player") as AudioStreamPlayer).bus == &"Music", "Conductor plays on Music")
	assert((menu.get_node("TurnSfx") as AudioStreamPlayer).bus == &"SFX", "menu sounds on SFX")

	# Esc 打开设置面板
	var selected := Levels.selected
	_press(&"ui_cancel")
	await create_timer(0.4).timeout
	var panel: Node = menu.get("_settings")
	assert(panel != null, "Esc opens settings")
	# 面板开着时 ← → 不转转盘、回车不开始游戏
	var focus := root.gui_get_focus_owner()
	assert(focus is HSlider, "first row (MASTER) has focus")
	settings.set_volume(&"Master", 1.0)
	(focus as HSlider).value = 1.0
	_press(&"ui_left")
	await process_frame
	await process_frame
	assert(Levels.selected == selected, "turntable does not turn while settings are open")
	assert(is_equal_approx(settings.get_volume(&"Master"), 0.95), "left lowers MASTER: %s" % settings.get_volume(&"Master"))
	assert(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.95))
	# ↓ 到 MUSIC，调到 0 = 静音
	_press(&"ui_down")
	await process_frame
	var music_slider := root.gui_get_focus_owner() as HSlider
	assert(music_slider != null and music_slider != focus, "down moves to MUSIC")
	music_slider.value = 0.0
	assert(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")), "MUSIC at 0 mutes")
	# 存盘了
	var cfg := ConfigFile.new()
	assert(cfg.load(CFG) == OK)
	assert(is_equal_approx(float(cfg.get_value("audio", "master")), 0.95))
	assert(is_equal_approx(float(cfg.get_value("audio", "music")), 0.0))
	# 判定延迟和校准是同一个值，存在 [latency]
	var old_offset: float = conductor.input_offset_sec
	settings.set_input_offset_ms(35.0)
	assert(is_equal_approx(conductor.input_offset_sec, 0.035))
	cfg.load(CFG)
	assert(is_equal_approx(float(cfg.get_value("latency", "input_offset_sec")), 0.035))
	assert(cfg.has_section_key("audio", "sfx"), "latency save keeps the audio section")
	conductor.input_offset_sec = old_offset
	_press(&"ui_accept")
	await create_timer(0.3).timeout
	assert(current_scene == menu, "Enter inside settings does not start the game")

	# Esc 关掉，菜单恢复
	_press(&"ui_cancel")
	await create_timer(0.4).timeout
	assert(not is_instance_valid(menu.get("_settings")), "Esc closes settings")
	menu.turn(1)
	await create_timer(0.5).timeout
	assert(Levels.selected == posmod(selected + 1, Levels.count()), "turntable works again")

	# 还原
	settings.set_volume(&"Master", 1.0)
	settings.set_volume(&"Music", 1.0)
	if backup.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	else:
		var f := FileAccess.open(CFG, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	print("SETTINGS_MENU_PASS: buses, routing, Esc open/close, keyboard sliders, menu input blocked, saved to settings.cfg")
	quit()
