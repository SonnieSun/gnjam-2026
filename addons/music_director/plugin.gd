@tool
extends EditorPlugin
## 在编辑器顶部工具栏加一个“音乐”按钮（项目 → 工具 菜单里也有一项），点了就运行 Music Director 面板。
## 面板本身是一个普通场景（scenes/tools/music_director.tscn），要跑起来才有声音，所以这里只负责启动它。

const SCENE := "res://scenes/tools/music_director.tscn"
const MENU_ITEM := "Music Director（音乐面板）"

var _button: Button


func _enter_tree() -> void:
	_button = Button.new()
	_button.text = "音乐"
	_button.tooltip_text = "运行 Music Director：编辑每个大关的叠轨音乐"
	_button.flat = true
	_button.icon = EditorInterface.get_base_control().get_theme_icon("AudioStreamPlayer", "EditorIcons")
	_button.pressed.connect(_open)
	add_control_to_container(CONTAINER_TOOLBAR, _button)
	add_tool_menu_item(MENU_ITEM, _open)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ITEM)
	if _button:
		remove_control_from_container(CONTAINER_TOOLBAR, _button)
		_button.queue_free()


func _open() -> void:
	EditorInterface.play_custom_scene(SCENE)
