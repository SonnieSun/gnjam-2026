@tool
extends Spin3DSection
## MV 镜头 5 · 洗衣机：猫头和衣服在滚筒里转，本来就在慢慢转，每打中一下多转一截，机身还会抖。
## 模型都在场景 mv_washer.tscn 里，这里只负责运镜和动画。

@onready var _box: Node3D = %Box
@onready var _drum: Node3D = %Drum  # 滚筒里的东西都挂在它下面，一起转


func _camera_pose(p: float, t: float) -> Dictionary:
	return {
		"pos": Vector3(0.6 - p * 1.2, 0.6 - p * 0.4, 8.0 - p * 2.2),
		"look": Vector3(0.0, 0.1, 0.0),
		"roll": sin(t * 9.0) * 0.015 + (p - 0.5) * 0.15,
	}


func _update_view(t: float) -> void:
	_drum.transform = rest(_drum).rotated_local(Vector3.BACK, -step_rot * 1.3 - t * 0.5)
	var shake := sin(t * 1000.0 / 30.0) * 0.02 * (1.0 + pulse() * 4.0)  # 机身抖动
	_box.transform = rest(_box).translated(Vector3(shake, 0.0, 0.0))
