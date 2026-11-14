@tool
class_name MemeLib
extends RefCounted
## 猫 meme 素材的清单。用 MemeLib.find("名字") 查，用 MemeLib.keys() 列出全部。
## 第一批：下面这张表，图在 assets/memes/ 下（由素材转换脚本生成），来源见 assets/memes/CREDITS.md。
## frames = 总帧数，cols / rows = 图里横竖各几格，fps = 原动图的播放速度。

const DATA := {
	"lick": {"frames": 30, "cols": 8, "rows": 4, "fps": 4.0},
	"popcat": {"frames": 2, "cols": 2, "rows": 1, "fps": 10.0},
	"apple": {"frames": 8, "cols": 8, "rows": 1, "fps": 20.0},
	"banana": {"frames": 8, "cols": 8, "rows": 1, "fps": 20.0},
	"nyanrun": {"frames": 8, "cols": 8, "rows": 1, "fps": 14.29},
	"oiia": {"frames": 32, "cols": 8, "rows": 4, "fps": 11.35},
	"nyan": {"frames": 12, "cols": 8, "rows": 2, "fps": 14.29},
	"meow": {"frames": 28, "cols": 8, "rows": 4, "fps": 17.5},
	"catjam": {"frames": 32, "cols": 8, "rows": 4, "fps": 33.33},
	"flower": {"frames": 10, "cols": 8, "rows": 2, "fps": 14.29},
	"grumpy": {"frames": 1, "cols": 1, "rows": 1, "fps": 1.0},
}


## 第二批素材：assets/cats/ 整个文件夹，不用登记，放进去就能用（来源见 assets/cats/CREDITS.md）。
## 动图的文件名自带参数：名字.f<帧数>.s<帧率>.webp，比如 oiia.f67.s22.webp 用 "oiia" 这个名字取。
## 帧从左到右、从上到下排成接近正方形的网格。静态图就是 名字.png / .jpg。
const CATS_DIR := "res://assets/cats"

static var _cats := {}
static var _scanned := false


## 这个名字有没有对应的素材
static func has(key: String) -> bool:
	return not find(key).is_empty()


## 查一个素材：返回 {"path", "frames", "cols", "rows", "fps"}，找不到返回空字典。
## 两批素材重名时（比如 oiia）默认用 assets/memes 里的；写成 "cats/oiia" 就指定用 assets/cats 里的。
static func find(key: String) -> Dictionary:
	if DATA.has(key):
		var info: Dictionary = DATA[key].duplicate()
		info["path"] = "res://assets/memes/%s.png" % key
		return info
	_scan()
	return _cats.get(key.trim_prefix("cats/"), {})


## 所有能用的名字（两批合在一起，排好序）
static func keys() -> PackedStringArray:
	_scan()
	var out := PackedStringArray(DATA.keys())
	for k: String in _cats:
		out.append("cats/" + k if DATA.has(k) else k)
	out.sort()
	return out


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	var sheet := RegEx.create_from_string("^(.*)\\.f(\\d+)\\.s(\\d+)$")
	for file: String in ResourceLoader.list_directory(CATS_DIR):
		if not file.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
			continue
		var name := file.get_basename()
		var info := {"path": CATS_DIR.path_join(file), "frames": 1, "cols": 1, "rows": 1, "fps": 1.0}
		var m := sheet.search(name)
		if m and int(m.get_string(2)) > 1:
			name = m.get_string(1)
			info.frames = int(m.get_string(2))
			info.fps = maxf(1.0, float(m.get_string(3)))
			info.cols = ceili(sqrt(float(info.frames)))
			info.rows = ceili(float(info.frames) / info.cols)
		_cats[name] = info
