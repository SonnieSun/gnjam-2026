@tool
extends Spin3DSection
## MV 镜头 5 · 洗衣机：猫头和衣服在滚筒里转，本来就在慢慢转，每打中一下多转一截，机身还会抖。
## 照着猫咪 MV 原型里的 VIEWS.washer 移植。

var _box: MeshInstance3D
var _drum: Node3D


func _build(root: Node3D) -> void:
	_box = CatBuilder.box(Vector3(3.6, 4.2, 3.0), CatBuilder.toon(Color("fafafa")), Vector3(0.0, 0.0, -2.0))  # 机身正面在 z = -0.5
	root.add_child(_box)
	root.add_child(CatBuilder.box(Vector3(3.6, 0.6, 0.1), CatBuilder.toon(Color("dddddd")), Vector3(0.0, 1.8, -0.45)))  # 面板
	var knob := CatBuilder.cylinder(0.18, 0.18, 0.15, CatBuilder.toon(Color("888888")), 24)
	knob.position = Vector3(1.2, 1.8, -0.35)
	knob.rotation.x = PI / 2
	root.add_child(knob)
	var door_ring := CatBuilder.torus(1.25, 0.18, CatBuilder.toon(Color("aaaaaa")), Vector3(0.0, 0.0, 0.05))
	door_ring.rotation.x = PI / 2
	root.add_child(door_ring)
	var wall_mesh := CylinderMesh.new()  # 滚筒的筒壁：从机身正面伸出来接到门圈
	wall_mesh.top_radius = 1.25
	wall_mesh.bottom_radius = 1.25
	wall_mesh.height = 0.6
	wall_mesh.cap_top = false
	wall_mesh.cap_bottom = false
	var wall_mat := CatBuilder.toon(Color("2f5a85")).duplicate() as StandardMaterial3D
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wall := CatBuilder.part(wall_mesh, wall_mat, Vector3(0.0, 0.0, -0.22))
	wall.rotation.x = PI / 2
	root.add_child(wall)
	var back := CatBuilder.disc(1.25, CatBuilder.toon(Color("3a6ea0")), Vector3(0.0, 0.0, -0.49))  # 滚筒里面的底
	back.rotation.x = PI / 2
	root.add_child(back)

	_drum = Node3D.new()  # 滚筒里的东西都挂在这，一起转
	_drum.position.z = -0.15
	root.add_child(_drum)
	var head := CatBuilder.make_head({"r": 0.55, "eyes": "closed"})
	head.position.y = -0.2
	_drum.add_child(head)
	var sock := CatBuilder.capsule(0.12, 0.4, CatBuilder.toon(Color("ff6a8a")), Vector3(0.7, 0.5, 0.0))
	sock.rotation.z = 1.0
	_drum.add_child(sock)
	_drum.add_child(CatBuilder.box(Vector3(0.5, 0.4, 0.1), CatBuilder.toon(Color("6ac0ff")), Vector3(-0.6, 0.6, 0.0)))  # 衣服

	var glass := CatBuilder.disc(1.2, CatBuilder.flat(Color("bfe6ff"), 0.25), Vector3(0.0, 0.0, 0.1))
	glass.rotation.x = PI / 2
	root.add_child(glass)


func _focus() -> Vector3:
	return Vector3.ZERO


func _camera_pose(p: float, t: float) -> Dictionary:
	return {
		"pos": Vector3(0.6 - p * 1.2, 0.6 - p * 0.4, 8.0 - p * 2.2),
		"look": Vector3(0.0, 0.1, 0.0),
		"roll": sin(t * 9.0) * 0.015 + (p - 0.5) * 0.15,
	}


func _update_view(t: float) -> void:
	_drum.rotation.z = -step_rot * 1.3 - t * 0.5
	_box.position.x = sin(t * 1000.0 / 30.0) * 0.02 * (1.0 + pulse() * 4.0)  # 机身抖动
