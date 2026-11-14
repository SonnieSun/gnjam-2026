class_name Levels
extends RefCounted
## 大关列表：主菜单转盘上的每一格对应这里的一项，顺序一致。
## chart 填谱面脚本的路径（脚本里要有 static func build() -> SongChart）。
## 第 1 关是迪斯科猫砂盆，第 2 关是八种 2D 画法，第 3~5 关暂时都指向六个 MV 镜头；做出新的大关后改对应那一行即可。
## look（可选）= 这一大关里 3D 小关默认的画面风格，名字见 scripts/fx/comic_style.gd 的 NAMES；
## 不填 = 原样。游戏里随时可以按 C 键切换着看。
## 增减大关的数量后，主菜单场景 scenes/menu.tscn 里转盘上的格子也要跟着增减。

const LIST: Array[Dictionary] = [
	{"title": "LEVEL 1", "chart": "res://scripts/charts/disco_chart.gd"},
	{"title": "LEVEL 2", "chart": "res://scripts/charts/showcase_chart.gd"},
	{"title": "LEVEL 3", "chart": "res://scripts/charts/mv_chart.gd", "look": "HALFTONE"},
	{"title": "LEVEL 4", "chart": "res://scripts/charts/mv_chart.gd", "look": "Y2K"},
	{"title": "LEVEL 5", "chart": "res://scripts/charts/mv_chart.gd"},
]

const MENU_SCENE := "res://scenes/menu.tscn"
const GAME_SCENE := "res://main.tscn"

## 主菜单里当前选中的是第几大关（0 起）。直接运行 main.tscn 时就是第 1 关。
static var selected := 0


static func count() -> int:
	return LIST.size()


static func title() -> String:
	return LIST[selected].title


## 当前选中那一大关默认的画面风格名字
static func look() -> String:
	return LIST[selected].get("look", "OFF")


## 生成当前选中那一大关的谱面
static func build_chart() -> SongChart:
	return load(LIST[selected].chart).build()
