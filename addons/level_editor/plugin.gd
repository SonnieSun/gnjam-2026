@tool
extends EditorPlugin
## 关卡编辑器插件：在编辑器顶部（2D / 3D / Script 旁边）加一个“关卡”页。
## 面板本身在 level_editor_panel.gd；这里只负责把它挂进编辑器，以及面板做不了的事：
## 运行游戏、打开场景、在检查器里显示资源、刷新文件列表。

const EditorPanel := preload("res://addons/level_editor/level_editor_panel.gd")

var _panel: Control


func _enter_tree() -> void:
	_panel = EditorPanel.new()
	_panel.name = "LevelEditor"
	EditorInterface.get_editor_main_screen().add_child(_panel)
	_panel.play_requested.connect(_on_play)
	_panel.open_scene_requested.connect(func(path: String): EditorInterface.open_scene_from_path(path))
	_panel.inspect_requested.connect(func(res: Resource): EditorInterface.edit_resource(res))
	_panel.files_changed.connect(func(): EditorInterface.get_resource_filesystem().scan())
	_make_visible(false)


func _exit_tree() -> void:
	if _panel:
		_panel.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _panel:
		_panel.visible = visible
		if visible:
			_panel.refresh_lists()


func _get_plugin_name() -> String:
	return "关卡"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("AudioStreamPlayer", "EditorIcons")


## 试玩：把“玩哪个大关、从第几个小关开始”写进一个临时文件，游戏启动时读它（见 levels.gd）
func _on_play(level_path: String, section: int) -> void:
	var f := FileAccess.open(Levels.EDITOR_REQUEST_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"level": level_path, "section": section}))
		f.close()
	EditorInterface.play_custom_scene(Levels.GAME_SCENE)
