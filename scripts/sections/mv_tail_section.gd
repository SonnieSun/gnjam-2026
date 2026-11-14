@tool
extends Spin3DSection
## MV 镜头 2 · 追尾巴：猫绕着圈追自己的尾巴，本来就在慢慢跑，每打中一下猛冲一段。
## 模型都在场景 mv_tail.tscn 里，这里只负责运镜和动画。

@onready var _spinner: Node3D = %Spinner  # 转它 = 猫绕圈
@onready var _cat: Node3D = %Cat


func _camera_pose(p: float, t: float) -> Dictionary:
	var a := t * 0.35  # 镜头绕着猫慢慢转
	return {"pos": Vector3(sin(a) * 6.0, 4.8 - p * 1.2, cos(a) * 6.0), "look": Vector3.ZERO, "roll": 0.0}


func _update_view(t: float) -> void:
	_spinner.transform = rest(_spinner).rotated_local(Vector3.UP, step_rot * 1.5 + t * 0.8)
	walk(_cat, 20.0, 0.8)
	_cat.transform = rest(_cat).rotated_local(Vector3.BACK, -pulse() * 0.2)  # 打中时往前一扑
