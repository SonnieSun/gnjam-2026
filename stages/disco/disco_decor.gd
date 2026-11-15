extends Node2D
## 第 1 关（迪斯科）的小装饰：跟着音乐的档位（= 关卡的 9 条分数线 + 广场 fever 那条线）往画面上加 / 换
## stages/shared/props 里的小模块（一串流过去的猫图等），在 3D 场景的空间里莫名其妙冒出来的猫图（meme_field_3d.gd；路上的会迎面飞过来），和在 3D 里绕着猫飞的一圈圈猫图（meme_orbit_3d.gd）。都不是贴在屏幕上转的。它们自己会跟按键、节拍、FEVER 动。
## 挂在 disco.tscn 里的一个节点上就行，不需要关卡脚本配合；删掉这个节点 = 没有这些装饰。
## 每次升档还会让镜头"踢"一下（DiscoRoad.cam_kick，路上和广场上才有）。
##
## 每一档摆什么在 _set_for(tier) 里改。档位：
##   0 开头  1 星星灯  2 灯球  3 跳舞猫  4 漂移  5 房子打开（转场）  6 舞池  7 网格  8 广场（猫清唱）  9 广场 FEVER  10 结尾

## 装饰整体多透明（1 = 不透明）
@export_range(0.0, 1.0) var opacity := 0.92
## 整体大小（1 = 按 1280x720 设计的大小）
@export var size_scale := 1.0
## 升档时镜头踢多大（0 = 不踢）
@export var kick_strength := 1.0

var _items: Array[Node] = []
var _tier := -1
var _root: Node2D
var _orbits: Array[Node3D] = []


func _ready() -> void:
	# 装饰放在自己的一层画布上（在关卡画面上面、分数和积累条下面）：关卡节点自己会缩放、抖动，装饰不跟着跑
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_root = Node2D.new()
	_root.modulate.a = opacity
	layer.add_child(_root)
	if has_node("/root/Music"):
		var music: Node = get_node("/root/Music")
		music.tier_changed.connect(_on_tier)
		music.fever_ended.connect(func(): _show(10))


func _on_tier(tier: int, up: bool) -> void:
	if up:
		var road := get_parent().get_node_or_null("Road")
		if road == null:
			for c in get_parent().get_children():
				if c is DiscoRoad:
					road = c
		if road and kick_strength > 0.0:
			road.cam_kick(kick_strength)
	_show(tier)


func _show(tier: int) -> void:
	if tier == _tier:
		return
	_tier = tier
	# 旧的缩小消失，新的弹出来
	for old in _items:
		if is_instance_valid(old):
			var t := old.create_tween()
			t.tween_property(old, "scale", Vector2.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			t.tween_callback(old.queue_free)
	_items.clear()
	for o in _orbits:
		if is_instance_valid(o):
			o.leave()
	_orbits.clear()
	_set_for(tier)
	for i in _items.size():
		var n := _items[i] as Node2D
		var to := n.scale
		n.scale = Vector2.ZERO
		var t := n.create_tween()
		t.tween_interval(0.05 * i)
		t.tween_property(n, "scale", to, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# 屏幕上的一个点（按 1280x720 写，(0, 0) = 屏幕中心）
func _at(x: float, y: float) -> Vector2:
	var screen := get_viewport_rect().size
	var k := screen.y / 720.0
	return screen / 2.0 + Vector2(x, y) * k


func _add(kind: String, x: float, y: float, props: Dictionary) -> Node:
	var k := get_viewport_rect().size.y / 720.0 * size_scale
	var n := PropKit.spawn(kind, _root, _at(x, y), props)
	(n as Node2D).scale = Vector2.ONE * k
	_items.append(n)
	return n


# 一圈猫图在 3D 场景里绕着猫飞。大小都按"猫的几倍"写（radius、item_height、lift）
func _orbit(props: Dictionary) -> void:
	var cat := _find_cat()
	if cat == null:
		return
	var h: float = cat.cat_view_height
	var o := MemeOrbit3D.new()
	for k in props:
		o.set(k, props[k])
	o.radius = float(props.get("radius", 1.8)) * h
	o.item_height = float(props.get("item_height", 0.45)) * h
	o.lift = float(props.get("lift", 0.0)) * h
	o.center = cat.focus + cat.pose_position
	cat.world.add_child(o)
	_orbits.append(o)


func _find_cat() -> KisaSpinCat3D:
	for c in get_parent().get_children():
		if c is KisaSpinCat3D:
			return c
	return null


func _process(_delta: float) -> void:
	if _orbits.is_empty():
		return
	var cat := _find_cat()
	if cat == null:
		return
	for o in _orbits:
		if is_instance_valid(o):
			# 绕猫飞的圈跟着猫；冒出来的那些留在场景里自己的位置
			o.center = cat.focus + (cat.pose_position if o is MemeOrbit3D else o.get_meta("at"))


# 猫图在场景的空间里莫名其妙地冒出来（meme_field_3d.gd）。大小都按"猫的几倍"写（item_height、box、clear_width、flow、at）。
# at = 这块空间的中心离猫多远（比如路上放在猫的前面）
func _field(props: Dictionary) -> void:
	var cat := _find_cat()
	if cat == null:
		return
	var h: float = cat.cat_view_height
	var f := MemeField3D.new()
	for k in props:
		if k != "at":
			f.set(k, props[k])
	f.item_height = float(props.get("item_height", 0.6)) * h
	f.box = Vector3(props.get("box", Vector3(6, 3, 6))) * h
	f.clear_width = float(props.get("clear_width", 0.0)) * h
	f.flow = Vector3(props.get("flow", Vector3.ZERO)) * h
	f.set_meta("at", Vector3(props.get("at", Vector3.ZERO)) * h)
	f.center = cat.focus + f.get_meta("at")
	cat.world.add_child(f)
	_orbits.append(f)


const ROOM := {"box": Vector3(7, 2.5, 7), "at": Vector3(0, 1.6, 0), "clear_width": 1.6, "life_beats": 4.0}
# 路上：猫前面一长条空间，猫图迎面飞过来（+z 是朝着镜头）
const ROAD := {"box": Vector3(12, 4, 34), "at": Vector3(0, 2.6, -13), "clear_width": 3.0, "life_beats": 0.0, "flow": Vector3(0, 0, 2.2)}
# 广场：四周一大圈空间，冒出来又消失
const PLAZA := {"box": Vector3(16, 5, 16), "at": Vector3(0, 3.0, 0), "clear_width": 3.0, "life_beats": 3.0}


func _with(base: Dictionary, more: Dictionary) -> Dictionary:
	var d := base.duplicate()
	d.merge(more, true)
	return d


func _set_for(tier: int) -> void:
	match tier:
		1:  # 星星灯：房间里开始莫名其妙地冒出几只猫图
			_field(_with(ROOM, {"memes": ["popcat"], "count": 3}))
		2:  # 灯球出现：多几只、多几种
			_field(_with(ROOM, {"memes": ["popcat", "oiia"], "count": 6}))
		3:  # 跳舞猫，第一个小高潮：一圈 oiia 绕着猫飞，四周还在冒
			_orbit({"meme": "oiia", "count": 8, "radius": 1.8, "tilt": 18.0})
			_field(_with(ROOM, {"memes": ["catjam", "popcat", "lick"], "count": 7, "item_height": 0.7}))
		4:  # 漂移：再加上面流过去的一串彩虹猫
			_orbit({"meme": "oiia", "count": 8, "radius": 1.8, "tilt": 18.0})
			_field(_with(ROOM, {"memes": ["catjam", "popcat", "lick"], "count": 7, "item_height": 0.7, "life_beats": 2.0}))
			_add("stream", -700, -290, {"meme": "nyan", "count": 5, "distance": 1400.0, "item_height": 70.0,
					"from_scale": 1.0, "to_scale": 1.0, "beats_per_lap": 8.0})
		6:  # 舞池：猫图从前面迎面飞过来
			_field(_with(ROAD, {"memes": ["oiia", "popcat"], "count": 10, "item_height": 0.9}))
		7:  # 网格：更多更快，再加一个竖着的圈从猫头顶翻过去
			_field(_with(ROAD, {"memes": ["oiia", "catjam", "nyan", "lick"], "count": 16, "item_height": 1.0, "flow": Vector3(0, 0, 3.2)}))
			_orbit({"meme": "oiia", "count": 6, "radius": 1.6, "tilt": 72.0, "lift": 0.3, "turns_per_beat": 0.08})
		8:  # 广场，猫清唱：安静下来，四周慢慢冒出几只很大的、在唱歌的猫
			_field(_with(PLAZA, {"memes": ["meow"], "count": 4, "item_height": 2.2, "size_jitter": 0.2, "life_beats": 6.0, "beat_pulse": 0.08}))
		9:  # 广场 FEVER：到处都在冒，外加两个圈
			_field(_with(PLAZA, {"memes": ["oiia", "popcat", "catjam", "lick", "nyan", "grumpy"], "count": 22, "item_height": 1.2, "life_beats": 2.0, "beat_pulse": 0.3}))
			_orbit({"meme": "oiia", "count": 12, "radius": 2.0, "tilt": 22.0, "turns_per_beat": 0.07})
			_orbit({"meme": "lick", "count": 6, "radius": 1.4, "item_height": 0.5, "tilt": 75.0, "lift": 0.3, "turns_per_beat": 0.09})
		_:
			pass  # 0 开头、5 房子打开的转场、10 结尾：干净的画面
