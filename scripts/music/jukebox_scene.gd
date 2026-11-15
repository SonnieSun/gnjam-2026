extends Control
## 曲库的独立页面（scenes/tools/jukebox.tscn）：只是听现在所有做好的曲子和音效，不改任何东西。
## 两个入口：游戏里按 Tab 调出编辑面板，点最上面一排的 "Jukebox"；或者在编辑器里打开这个场景按 F6。
## 内容在 jukebox.gd；这里只是给它一个底色、主题和"回主菜单"按钮。Space = 停，Esc = 回主菜单。

const THEME := preload("res://assets/ui/theme.tres")
const Jukebox := preload("res://scripts/music/jukebox.gd")

var _jukebox: VBoxContainer


func _ready() -> void:
	Conductor.stop()
	theme = THEME
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.12, 0.22)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_right = -16
	root.offset_top = 12
	root.offset_bottom = -12
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	root.add_child(top)
	var title := Label.new()
	title.text = "JUKEBOX 曲库"
	title.theme_type_variation = "Header"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var back := Button.new()
	back.text = "回主菜单 (Esc)"
	back.theme_type_variation = "Big"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_back)
	top.add_child(back)
	_jukebox = Jukebox.new()
	_jukebox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_jukebox)


func _back() -> void:
	_jukebox.stop_all()
	get_tree().change_scene_to_file(Levels.MENU_SCENE)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_SPACE:
		_jukebox.stop_all()
	elif k.keycode == KEY_ESCAPE:
		_back()
	else:
		return
	get_viewport().set_input_as_handled()
