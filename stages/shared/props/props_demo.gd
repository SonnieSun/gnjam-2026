extends Node2D
## 场景小模块的展示（F6）：每种模块放一个，全是用代码放的（PropKit），所以这个文件也是"怎么用代码放"的例子。
## 空格 = 按一下（模块会起反应）；F = 开 / 关 FEVER 的样子；R = 重新来。
## 只在这个测试场景里用。

var _fever := false


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.1, 0.2)
	bg.size = Vector2(4000, 4000)
	bg.position = Vector2(-1000, -1000)
	bg.z_index = -10
	add_child(bg)
	var size := get_viewport_rect().size
	var w := size.x
	var h := size.y
	# 一只会转的 meme
	_label("spinner", Vector2(w * 0.12, h * 0.08))
	PropKit.spawn("spinner", self, Vector2(w * 0.12, h * 0.27), {"meme": "oiia", "height": 150.0})
	# 一圈
	_label("ring", Vector2(w * 0.38, h * 0.08))
	PropKit.spawn("ring", self, Vector2(w * 0.38, h * 0.3), {"meme": "popcat", "count": 8, "radius": 105.0, "item_height": 60.0})
	# 一串：朝右上，由小变大
	_label("stream", Vector2(w * 0.68, h * 0.08))
	var stream := PropKit.spawn("stream", self, Vector2(w * 0.56, h * 0.42), {"meme": "nyan", "count": 6, "distance": 380.0, "item_height": 80.0})
	stream.rotation = -0.5
	# 跟拍跳着转
	_label("orbit", Vector2(w * 0.12, h * 0.55))
	PropKit.spawn("orbit", self, Vector2(w * 0.12, h * 0.78), {"meme": "catjam", "count": 3, "radius": 95.0, "item_height": 70.0})
	# 发光转圈猫（2D 卡片）
	_label("tabby", Vector2(w * 0.38, h * 0.55))
	PropKit.spawn("tabby", self, Vector2(w * 0.38, h * 0.8), {"height": 200.0})
	# 套起来：一圈"发光转圈猫"，和一圈"一串猫"
	_label("ring_of tabby", Vector2(w * 0.62, h * 0.55))
	PropKit.ring_of("tabby", self, Vector2(w * 0.62, h * 0.8), 5, 95.0, {"face_out": false})
	_label("ring_of stream", Vector2(w * 0.86, h * 0.55))
	var burst := PropKit.ring_of("stream", self, Vector2(w * 0.86, h * 0.8), 6, 0.0)
	for it in burst.items:
		(it as PropStream).configure({"meme": "banana", "count": 4, "distance": 130.0, "item_height": 40.0})


func _label(text: String, at: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = at - Vector2(60, 0)
	l.add_theme_font_size_override("font_size", 18)
	add_child(l)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_R:
		get_tree().reload_current_scene()
	elif k.physical_keycode == KEY_F:
		_fever = not _fever
		for m in find_children("*", "Node2D", true, false):
			if m is PropModule:
				m._fever(_fever)
