@tool
extends Spin3DSection
## MV 镜头 4 · 打大猫：小猫伸拳头打一个巨大的猫头，每打中一下大猫头转一格。
## 照着猫咪 MV 原型里的 VIEWS.bigcat 移植。

const BIG_POS := Vector3(1.4, 0.0, 0.0)

var _big: Node3D
var _arm_pivot: Node3D


func _build(root: Node3D) -> void:
	_big = CatBuilder.make_head({"r": 1.6, "eyes": "dot", "mouth": "w"})
	_big.position = BIG_POS
	root.add_child(_big)

	var cat := CatBuilder.make_cat({"eyes": "dot"})
	cat.scale = Vector3.ONE * 0.8
	cat.position = Vector3(-2.4, -0.6, 0.5)
	cat.rotation.y = -0.3
	root.add_child(cat)

	_arm_pivot = Node3D.new()  # 小猫的拳头
	_arm_pivot.position = Vector3(0.55, 0.3, 0.2)
	cat.add_child(_arm_pivot)
	var arm := CatBuilder.capsule(0.1, 0.5, CatBuilder.toon(CatBuilder.WHITE), Vector3(0.3, 0.0, 0.0))
	arm.rotation.z = PI / 2
	_arm_pivot.add_child(arm)


func _focus() -> Vector3:
	return BIG_POS


func _camera_pose(p: float, t: float) -> Dictionary:
	return {
		"pos": Vector3(-1.0 + p * 1.5, 0.5, 9.0 - p * 2.0),
		"look": Vector3(-0.5 + p * 1.2, 0.0, 0.0),
		"roll": sin(t * 2.0) * 0.03,
	}


func _update_view(_t: float) -> void:
	_big.rotation.z = -step_rot
	_big.scale = Vector3.ONE * (1.0 + pulse() * 0.08)  # 被打中时鼓一下
	var punch := sin(minf(hit_age / 0.2, 1.0) * PI)  # 打中后 0.2 秒内出一拳
	_arm_pivot.position.x = 0.55 + punch * 0.9
	_arm_pivot.rotation.z = 0.5 - punch * 0.5
