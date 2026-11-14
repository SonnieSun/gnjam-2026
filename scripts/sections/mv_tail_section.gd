@tool
extends Spin3DSection
## MV 镜头 2 · 追尾巴：猫绕着圈追自己的尾巴，本来就在慢慢跑，每打中一下猛冲一段。
## 照着猫咪 MV 原型里的 VIEWS.tail 移植。

var _spinner: Node3D
var _cat: Node3D


func _build(root: Node3D) -> void:
	root.add_child(CatBuilder.disc(4.0, CatBuilder.toon(Color("e8d3a8")), Vector3(0.0, -0.625, 0.0)))  # 地板
	root.add_child(CatBuilder.disc(1.6, CatBuilder.toon(Color("d46a6a")), Vector3(0.0, -0.615, 0.0)))  # 红地毯圈
	root.add_child(CatBuilder.disc(1.2, CatBuilder.toon(Color("e8d3a8")), Vector3(0.0, -0.605, 0.0)))

	_spinner = Node3D.new()
	root.add_child(_spinner)
	_cat = CatBuilder.make_cat({"eyes": "big"})  # 猫头朝 +x 跑，转 _spinner 就是绕圈
	_cat.position = Vector3(0.0, 0.0, 1.0)
	_spinner.add_child(_cat)
	var tail: Node3D = _cat.get_meta("tail")
	tail.rotation.y = 0.4


func _focus() -> Vector3:
	return Vector3.ZERO


func _camera_pose(p: float, t: float) -> Dictionary:
	var a := t * 0.35  # 镜头绕着猫慢慢转
	return {"pos": Vector3(sin(a) * 6.0, 4.8 - p * 1.2, cos(a) * 6.0), "look": Vector3.ZERO, "roll": 0.0}


func _update_view(t: float) -> void:
	_spinner.rotation.y = step_rot * 1.5 + t * 0.8
	CatBuilder.walk(_cat, 20.0, 0.8)
	_cat.rotation.z = -0.1 - pulse() * 0.2  # 打中时往前一扑
