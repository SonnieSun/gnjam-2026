@tool
class_name MemeLib
extends RefCounted
## 猫 meme 序列帧图的清单（由素材转换脚本生成）。图在 assets/memes/ 下，来源见 assets/memes/CREDITS.md。
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


static func has(key: String) -> bool:
	return DATA.has(key)
