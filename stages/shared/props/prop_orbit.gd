class_name PropOrbit
extends PropArranger
## 跟拍跳着转：几样东西绕着这个节点转，但不是匀速 —— 每到一拍猛地跳一格，带一点过头再弹回来（Cat Rotator 的 Beat Step）。
## 玩家按一下也多跳一格。像钟表的秒针、像一起点头的一圈猫。FEVER 里每拍跳两格。

@export_group("跟拍跳着转")
## 离中心多远（像素）
@export var radius := 240.0
## 每次跳多少度（负数 = 反着跳）
@export var step_degrees := 45.0
## 每几拍跳一次
@export_range(1, 8) var every_beats := 1
## 跳得多硬（越大越快到位）、弹几下才停（越小弹得越久）
@export var stiffness := 180.0
@export var damping := 14.0
## 每一份头朝外（关掉 = 都保持正着）
@export var face_out := false
## 平时再匀速慢慢转多快（圈 / 秒，0 = 只在拍子上动）
@export var drift := 0.0

var _angle := 0.0
var _target := 0.0
var _velocity := 0.0


func on_hit() -> void:
	_target += deg_to_rad(step_degrees)


func on_beat(index: int) -> void:
	if index % every_beats == 0:
		_target += deg_to_rad(step_degrees) * (2.0 if fever else 1.0)


func arrange(delta: float) -> void:
	_target += drift * TAU * delta
	# 弹簧：朝目标角度冲过去，冲过头再回来
	_velocity += (_target - _angle) * stiffness * delta
	_velocity *= exp(-damping * delta)
	_angle += _velocity * delta
	for i in items.size():
		var a := _angle + TAU * i / maxi(items.size(), 1)
		var it := items[i]
		it.position = Vector2.RIGHT.rotated(a) * radius
		it.rotation = a + PI / 2.0 if face_out else 0.0
