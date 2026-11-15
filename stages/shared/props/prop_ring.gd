class_name PropRing
extends PropArranger
## 一圈：把一样东西摆成一个圆，整圈慢慢转。玩家按一下，整圈被猛推一把（带惯性慢下来）；每拍半径弹一下；
## FEVER 里转得更快、圈更大。摆的是会转的 meme 时，就是 Cat Rotator 里那种猫曼陀罗。
## 一圈里再放一圈（item 用 prop_ring.tscn）就是花。

@export_group("一圈")
## 半径（像素）
@export var radius := 220.0
## 平时整圈转多快（圈 / 秒；负数 = 反着转）
@export var spin_speed := 0.08
## 按一下推多快（圈 / 秒），惯性多大（越大停得越快）
@export var hit_push := 0.5
@export var friction := 1.6
## 每一份头朝外（关掉 = 都保持正着）
@export var face_out := true
## 隔一份翻一下（左右镜像）
@export var mirror := false
## 每拍半径弹多少（比例，0 = 不弹）
@export_range(0.0, 0.5, 0.01) var beat_pulse := 0.08
## FEVER 里转速乘多少、半径乘多少
@export var fever_speed := 2.5
@export var fever_radius := 1.15

var _angle := 0.0
var _push := 0.0
var _pulse := 0.0
var _grow := 1.0


func on_hit() -> void:
	_push = minf(_push + hit_push, 3.0)
	for it in items:
		if it is MemeSpinner:
			it.spin(0.8)


func on_beat(_index: int) -> void:
	_pulse = beat_pulse


func arrange(delta: float) -> void:
	var speed := spin_speed * (fever_speed if fever else 1.0) + _push * signf(spin_speed if spin_speed != 0.0 else 1.0)
	_angle = fposmod(_angle + speed * TAU * delta, TAU)
	_push *= exp(-friction * delta)
	_pulse *= exp(-8.0 * delta)
	_grow = lerpf(_grow, fever_radius if fever else 1.0, minf(1.0, 3.0 * delta))
	var r := radius * _grow * (1.0 + _pulse)
	for i in items.size():
		var a := _angle + TAU * i / maxi(items.size(), 1)
		var it := items[i]
		it.position = Vector2.RIGHT.rotated(a) * r
		it.rotation = a + PI / 2.0 if face_out else 0.0
		it.scale = Vector2(-1.0 if mirror and i % 2 == 1 else 1.0, 1.0)
