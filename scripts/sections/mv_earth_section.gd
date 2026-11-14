@tool
extends Spin3DSection
## MV 镜头 3 · 拍地球：大猫探头伸爪子拍地球，地球一直在慢慢转，每拍中一下转得飞快再慢下来。
## 模型都在场景 mv_earth.tscn 里，这里只负责运镜和动画。

@onready var _earth: Node3D = %Earth
@onready var _arm_pivot: Node3D = %ArmPivot  # 肩膀；整条手臂绕着这里挥


func _camera_pose(p: float, _t: float) -> Dictionary:
	var a := -0.15 + p * 0.3
	var d := 8.0 - p * 1.6
	return {
		"pos": Vector3(sin(a) * d, 0.3 + p * 0.6, cos(a) * d),
		"look": Vector3(0.0, 0.2, 0.0),
		"roll": -0.06 + p * 0.12,
	}


func _update_view(_t: float) -> void:
	_earth.transform = rest(_earth).rotated_local(Vector3.UP, free_spin)
	var swing := sin(minf(hit_age / 0.25, 1.0) * PI)  # 打中后 0.25 秒内挥一下爪子
	var pose := rest(_arm_pivot)
	pose.basis = Basis(Vector3.RIGHT, swing * 0.3) * pose.basis * Basis(Vector3.BACK, -swing * 0.6)
	_arm_pivot.transform = pose
