extends Node2D
## 一次性的冲击环：从判定圈那么大开始往外扩一圈，越扩越细越淡，播完自动销毁。Perfect 专属。
## 用法：const ShockRing := preload("res://scripts/fx/shock_ring.gd")；var fx := ShockRing.create(section); parent.add_child(fx); fx.radius *= 判定圈半径; fx.global_position = ...

var color := Color(1.0, 0.9, 0.2)
## 从多大的圈开始（create 之后是“判定圈画大了几倍”，再乘上判定圈半径）
var radius := 1.0
## 扩到出发时的多少倍
var grow := 1.9
var width := 12.0
var lifetime := 0.32
## 竖向压扁比例：判定圈画成透视扁椭圆时（迪斯科），环也是同样的椭圆
var squash := 1.0

var _age := 0.0


## section = 当前小关：判定圈画大了 / 压扁了的关卡（迪斯科），环跟着一样
static func create(section: Node = null) -> Node2D:
	var fx := new()
	if section:
		if "judge_scale" in section:
			fx.radius = section.judge_scale
		for child in section.get_children():
			if child.has_method("ring_squash"):
				fx.squash = child.ring_squash()
				break
	return fx


func _ready() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := _age / lifetime
	var out := 1.0 - (1.0 - t) * (1.0 - t)  # 先快后慢
	var r := radius * lerpf(1.0, grow, out)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, squash))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Color(color, (1.0 - t) * 0.9), lerpf(width, 1.5, out), true)
	draw_arc(Vector2.ZERO, r * 0.94, 0.0, TAU, 96, Color(1.0, 1.0, 1.0, (1.0 - t) * 0.5), lerpf(width * 0.35, 1.0, out), true)
