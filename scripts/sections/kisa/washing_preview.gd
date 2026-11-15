extends "res://scripts/main.gd"
## F6 直接测试洗衣机：复用完整游戏框架和第 5 关的真实谱面。

func _ready() -> void:
	var index := Levels.paths().find("res://levels/level_5.tres")
	if index < 0:
		push_error("Washing preview: levels/level_5.tres not found")
		return
	Levels.selected = index
	super._ready()
