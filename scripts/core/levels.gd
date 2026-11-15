class_name Levels
extends RefCounted
## 大关列表。每个大关是 levels/ 文件夹里的一个 .tres 文件（SongChart），按文件名排序：
## level_1.tres 就是主菜单转盘上的第 1 格，以此类推。
## 加一个大关 = 在那个文件夹里再放一个 .tres（复制一个现成的改最省事）；
## 大关的名字、画面风格、小关和谱子都在 .tres 里编辑，见 levels/README.md。
## 文件夹可以在 项目设置 → Gnjam → Levels Folder 里改。
## 增减大关的数量后，主菜单场景 scenes/menu.tscn 里转盘上的格子也要跟着增减。

const LEVELS_FOLDER_SETTING := "gnjam/levels_folder"
const LEVELS_FOLDER_DEFAULT := "res://levels"

const MENU_SCENE := "res://scenes/menu.tscn"
const GAME_SCENE := "res://main.tscn"

## 主菜单里当前选中的是第几大关（0 起）。直接运行 main.tscn 时就是第 1 关。
static var selected := 0


static var _paths := PackedStringArray()


## 所有大关文件的路径，按文件名排序
static func paths() -> PackedStringArray:
	if _paths.is_empty():
		var folder: String = ProjectSettings.get_setting(LEVELS_FOLDER_SETTING, LEVELS_FOLDER_DEFAULT)
		var dir := DirAccess.open(folder)
		if dir:
			for f in dir.get_files():
				f = f.trim_suffix(".remap")  # 导出后的游戏里文件名会多这个后缀
				if f.get_extension() == "tres":
					_paths.append(folder.path_join(f))
		_paths.sort()
		if _paths.is_empty():
			push_error("大关文件夹 %s 里没有找到 .tres 文件" % folder)
	return _paths


## 重新扫描文件夹（运行中新加了大关文件之后调用）
static func rescan() -> void:
	_paths = PackedStringArray()


static func count() -> int:
	return paths().size()


static func _chart(index: int) -> SongChart:
	return load(paths()[clampi(index, 0, count() - 1)]) as SongChart


static func title() -> String:
	var t := _chart(selected).title
	return t if t != "" else "LEVEL %d" % (selected + 1)


## 当前选中那一大关默认的画面风格名字
static func look() -> String:
	return _chart(selected).look


## 生成当前选中那一大关的谱面（复制一份再用，游戏过程中不会改到文件里的数据）
static func build_chart() -> SongChart:
	var c := _chart(selected).duplicate(true) as SongChart
	c.recompute()
	return c
