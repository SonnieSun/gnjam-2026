@tool
extends Spin3DSection
## MV 镜头 1 · 唱片：猫站在斜放的唱片上原地迈步，每打中一下唱片转一格。
## 模型都在场景 mv_disc.tscn 里，这里只负责运镜和动画。

@onready var _disc: Node3D = %Disc
@onready var _cat: Node3D = %Cat


func _camera_pose(p: float, t: float) -> Dictionary:
	var a := -0.5 + p * 0.35
	return {
		"pos": Vector3(sin(a) * 7.5 - 0.5, 3.2 - p * 0.6, cos(a) * 7.5),
		"look": Vector3(0.4, 0.0, 0.0),
		"roll": 0.12 + sin(t * 1.2) * 0.04,
	}


func _update_view(t: float) -> void:
	_disc.transform = rest(_disc).rotated_local(Vector3.UP, -step_rot)
	walk(_cat, 14.0)
	var hop := absf(sin(t * 14.0)) * 0.05 + pulse() * 0.3  # 走路的小颠 + 打中时蹦一下
	_cat.transform = rest(_cat).translated_local(Vector3(0.0, hop / _cat.scale.y, 0.0))
