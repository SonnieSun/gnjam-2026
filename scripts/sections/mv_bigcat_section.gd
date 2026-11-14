@tool
extends Spin3DSection
## MV 镜头 4 · 打大猫：小猫伸拳头打一个巨大的猫头，每打中一下大猫头转一格。
## 模型都在场景 mv_bigcat.tscn 里，这里只负责运镜和动画。

@onready var _big: Node3D = %BigHead
@onready var _arm_pivot: Node3D = %ArmPivot  # 小猫的拳头


func _camera_pose(p: float, t: float) -> Dictionary:
	return {
		"pos": Vector3(-1.0 + p * 1.5, 0.5, 9.0 - p * 2.0),
		"look": Vector3(-0.5 + p * 1.2, 0.0, 0.0),
		"roll": sin(t * 2.0) * 0.03,
	}


func _update_view(_t: float) -> void:
	_big.transform = rest(_big).rotated_local(Vector3.BACK, -step_rot) \
			.scaled_local(Vector3.ONE * (1.0 + pulse() * 0.08))  # 被打中时鼓一下
	var punch := sin(minf(hit_age / 0.2, 1.0) * PI)  # 打中后 0.2 秒内出一拳
	var pose := rest(_arm_pivot)
	pose.basis = pose.basis * Basis(Vector3.BACK, -punch * 0.5)
	pose.origin.x += punch * 0.9
	_arm_pivot.transform = pose
