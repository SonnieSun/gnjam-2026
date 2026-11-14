class_name StarBurst
extends Node2D
## 一次性的小星星炸开效果，播完自动销毁。
## 用法：var fx := StarBurst.create(true); parent.add_child(fx); fx.global_position = ...

var count := 14
var speed_min := 220.0
var speed_max := 420.0
var size_min := 9.0
var size_max := 16.0
var lifetime := 0.55
var color := Color(1.0, 0.9, 0.3)
## 星星从离中心多远的地方出发（判定圈的半径附近）
var start_radius := 22.0

var _age := 0.0
var _stars: Array[Dictionary] = []
var _shape := PackedVector2Array()


## strong = true 是 Perfect 的强烈版，false 是 Good 的微弱版
static func create(strong: bool) -> StarBurst:
	var fx := StarBurst.new()
	if not strong:
		fx.count = 6
		fx.speed_min = 90.0
		fx.speed_max = 180.0
		fx.size_min = 5.0
		fx.size_max = 9.0
		fx.lifetime = 0.4
		fx.color = Color(0.6, 1.0, 0.7, 0.7)
	return fx


func _ready() -> void:
	# 单位大小的五角星
	for i in 10:
		var r := 1.0 if i % 2 == 0 else 0.45
		_shape.append(Vector2.from_angle(-PI / 2 + i * TAU / 10.0) * r)
	for i in count:
		# 方向大致均匀分布，再加一点随机
		var a := (i + randf_range(-0.35, 0.35)) * TAU / count
		_stars.append({
			"dir": Vector2.from_angle(a),
			"speed": randf_range(speed_min, speed_max),
			"size": randf_range(size_min, size_max),
			"rot": randf() * TAU,
			"spin": randf_range(-8.0, 8.0),
		})


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := _age / lifetime
	# 先快后慢地飞出去，同时缩小淡出
	var travel := 1.0 - (1.0 - t) * (1.0 - t)
	var c := color
	c.a *= 1.0 - t * t
	for s in _stars:
		var pos: Vector2 = s.dir * (start_radius + s.speed * lifetime * travel)
		var scale_now: float = s.size * (1.0 - 0.6 * t)
		draw_set_transform(pos, s.rot + s.spin * _age, Vector2.ONE * scale_now)
		draw_colored_polygon(_shape, c)
