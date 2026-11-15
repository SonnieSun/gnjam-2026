extends Node3D
## 虎斑猫测试场景（F6）：一排 4 只猫，每只的毛色和发光颜色都是随机的。
## 空格 = 一起转一圈（越转越亮，停下来慢慢变暗）；R = 重新随机；0 = 定住最亮，9 = 恢复自动。
## 只在这个测试场景里用。

@onready var cat: TabbySpinCat = $TabbySpinCat
@onready var info: Label = $UI/Info
var _cats: Array[TabbySpinCat] = []


func _ready() -> void:
	_cats.append(cat)
	cat.position.x = -1.5
	for i in 3:
		var c := preload("res://stages/shared/tabby_cat/tabby_spin_cat.tscn").instantiate() as TabbySpinCat
		c.position.x = -0.5 + i
		add_child(c)
		_cats.append(c)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.physical_keycode:
		KEY_R: get_tree().reload_current_scene()
		KEY_0:
			for c in _cats:
				c.set_glow(1.0)
		KEY_9:
			for c in _cats:
				c.set_glow(-1.0)


func _process(_d: float) -> void:
	info.text = "SPACE spin   R reroll coats + colors   0 max   9 auto\nglow %.2f" % cat.current_glow()
