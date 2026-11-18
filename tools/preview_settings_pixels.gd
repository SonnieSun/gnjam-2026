extends SceneTree
## 看设置面板里的 PIXELS（原生像素）开关：主菜单上打开设置面板，开着截一张，点成 OFF 再截一张，
## 检查 RetroScreen 跟着切了、settings.cfg 里存上了。跑完把 settings.cfg 还原成跑之前的样子。要开窗口跑：
##   godot --path . --script res://tools/preview_settings_pixels.gd -- <输出目录>

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


func _saved_value() -> Variant:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	return cfg.get_value("video", "native_pixels", "missing")


func _run() -> void:
	var path := "user://settings.cfg"
	var backup := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	var settings := root.get_node("Settings")
	var retro := root.get_node("RetroScreen")
	print("  start: setting %s, retro native %s" % [settings.native_pixels, retro.native])
	settings.set_native_pixels(true)
	load("res://scripts/main.gd").in_run = false
	change_scene_to_file(Levels.MENU_SCENE)
	await create_timer(1.5).timeout
	var panel: Node = load("res://scripts/ui/settings_panel.gd").open_overlay(current_scene)
	await create_timer(0.6).timeout
	await _shot("settings_on.png")
	var btn: Button = panel.get("_pixels_btn")
	btn.button_pressed = false
	await create_timer(0.3).timeout
	print("  after OFF: button '%s', setting %s, retro native %s, saved %s" % [btn.text, settings.native_pixels, retro.native, _saved_value()])
	await _shot("settings_off.png")
	btn.button_pressed = true
	await create_timer(0.3).timeout
	print("  after ON: button '%s', setting %s, retro native %s, saved %s" % [btn.text, settings.native_pixels, retro.native, _saved_value()])
	# 还原跑之前的 settings.cfg
	if backup.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	print("  settings.cfg restored")
	print("PREVIEW_SETTINGS_PIXELS_DONE")
	quit()
